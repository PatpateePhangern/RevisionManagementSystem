import CoreData
import Foundation

extension PersistenceController {

    // MARK: - Export

    /// Serialises the entire database to JSON on a private background context.
    ///
    /// Output format: `JSONEncoder` with `.prettyPrinted` + `.sortedKeys` and
    /// ISO-8601 date encoding — fully human-readable in any text editor.
    ///
    /// The manifest is built on a background context then the JSON encoding runs
    /// on the caller's actor so the `Codable` conformance is always used in the
    /// correct actor context (avoids the "nonisolated context" warning under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
    func generateMasterBackup() async throws -> Data {
        // Phase 1 — build plain-Swift value tree on background context
        let manifest: MasterBackupManifest =
            try await withCheckedThrowingContinuation { continuation in
                let ctx = newBackgroundContext()
                ctx.perform {
                    do {
                        let req = SubjectMO.fetchRequest()
                        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                        let subjects = try ctx.fetch(req)

                        let subjectBackups: [SubjectBackup] = subjects.map { s in
                            let papers = ((s.papers as? Set<PaperMO>) ?? [])
                                .sorted { ($0.normalizedSeries ?? "") < ($1.normalizedSeries ?? "") }

                            let paperBackups: [PaperBackup] = papers.map { p in
                                let qsBackups: [QuestionStructureBackup] =
                                    ((p.questionStructures as? Set<QuestionStructureMO>) ?? [])
                                    .sorted { $0.displayOrder < $1.displayOrder }
                                    .map { q in
                                        QuestionStructureBackup(
                                            questionLabel: q.questionLabel,
                                            maxMarks:      q.maxMarks,
                                            displayOrder:  q.displayOrder
                                        )
                                    }

                                let attemptBackups: [AttemptBackup] =
                                    ((p.attempts as? Set<AttemptMO>) ?? [])
                                    .sorted { $0.attemptNumber < $1.attemptNumber }
                                    .map { a in
                                        let logBackups: [ETSEventLogBackup] =
                                            ((a.eventLogs as? Set<ETSEventLogMO>) ?? [])
                                            .sorted { $0.sequenceIndex < $1.sequenceIndex }
                                            .map { l in
                                                ETSEventLogBackup(
                                                    id:              l.id ?? UUID(),
                                                    sequenceIndex:   l.sequenceIndex,
                                                    eventType:       l.eventType,
                                                    label:           l.label,
                                                    durationSeconds: l.durationSeconds,
                                                    marksEarned:     l.marksEarned
                                                )
                                            }
                                        return AttemptBackup(
                                            id:                a.id ?? UUID(),
                                            attemptNumber:     a.attemptNumber,
                                            barcodeValue:      a.barcodeValue,
                                            paperType:         a.paperType,
                                            totalScore:        a.totalScore,
                                            rawGrade:          a.rawGrade,
                                            durationInSeconds: a.durationInSeconds,
                                            printTimestamp:    a.printTimestamp,
                                            completedTimestamp: a.completedTimestamp,
                                            reviewQuestions:   a.reviewQuestions,
                                            additionalNotes:   a.additionalNotes,
                                            scannedFilePath:   a.scannedFilePath,
                                            eventLogs:         logBackups
                                        )
                                    }

                                return PaperBackup(
                                    rawSeriesName:      p.rawSeriesName,
                                    normalizedSeries:   p.normalizedSeries,
                                    questionStructures: qsBackups,
                                    attempts:           attemptBackups
                                )
                            }

                            return SubjectBackup(name: s.name ?? "", papers: paperBackups)
                        }

                        continuation.resume(returning: MasterBackupManifest(
                            exportedAt: Date(),
                            subjects:   subjectBackups
                        ))

                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

        // Phase 2 — encode on the caller's actor (MainActor when invoked from the UI)
        let encoder = JSONEncoder()
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    // MARK: - Reset (backup-first full wipe)

    /// Creates an automatic backup then deletes every entity in the store.
    /// Returns the file URL of the backup so the caller can surface it to the user.
    func resetAllData() async throws -> URL {
        // Phase 1 — backup
        let backupData = try await generateMasterBackup()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        df.calendar   = Calendar(identifier: .gregorian)
        df.locale     = Locale(identifier: "en_US_POSIX")
        let fname      = "PaperTracker-PreReset-Backup-\(df.string(from: Date())).json"
        let backupURL  = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fname)
        try backupData.write(to: backupURL)

        // Phase 2 — wipe all entities on a background context
        let entities = ["ETSEventLogMO", "QuestionStructureMO", "GradeThresholdTableMO",
                        "AttemptMO", "DifficultQuestionsArchiveMO", "PaperMO", "SubjectMO"]
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let ctx = newBackgroundContext()
            ctx.perform {
                do {
                    for name in entities {
                        let req = NSFetchRequest<NSFetchRequestResult>(entityName: name)
                        let del = NSBatchDeleteRequest(fetchRequest: req)
                        del.resultType = .resultTypeObjectIDs
                        let result = try ctx.execute(del) as? NSBatchDeleteResult
                        if let ids = result?.result as? [NSManagedObjectID] {
                            NSManagedObjectContext.mergeChanges(
                                fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                                into: [self.container.viewContext])
                        }
                    }
                    DispatchQueue.main.async { self.container.viewContext.refreshAllObjects() }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        return backupURL
    }

    // MARK: - Restore

    /// Imports a JSON backup produced by `generateMasterBackup()` into the store.
    ///
    /// Strategy: **idempotent upsert** — subjects are matched by name, papers
    /// by `normalizedSeries` within a subject, and attempts by `barcodeValue`.
    /// Existing records are updated; new records are inserted.  Question
    /// structures and event logs are always replaced wholesale.
    ///
    /// All writes happen inside a single `ctx.perform` block and are rolled
    /// back atomically on any error.  On success the view context is refreshed
    /// so SwiftUI `@FetchRequest` views pick up the new data immediately.
    func restoreFromBackup(data: Data) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(MasterBackupManifest.self, from: data)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let ctx = newBackgroundContext()
            ctx.perform {
                do {
                    for subjectData in manifest.subjects {
                        // ── Subject (dedup by name) ──────────────────────────
                        let sReq = SubjectMO.fetchRequest()
                        sReq.predicate  = NSPredicate(format: "name == %@", subjectData.name)
                        sReq.fetchLimit = 1
                        let subject: SubjectMO
                        if let existing = try ctx.fetch(sReq).first {
                            subject = existing
                        } else {
                            subject    = SubjectMO(context: ctx)
                            subject.id = UUID()
                        }
                        subject.name = subjectData.name

                        for paperData in subjectData.papers {
                            // ── Paper (dedup by normalizedSeries) ────────────
                            let existingPapers = (subject.papers as? Set<PaperMO>) ?? []
                            let paper: PaperMO
                            if let existing = existingPapers.first(where: {
                                $0.normalizedSeries == paperData.normalizedSeries
                            }) {
                                paper = existing
                            } else {
                                paper         = PaperMO(context: ctx)
                                paper.id      = UUID()
                                paper.subject = subject
                            }
                            // subjectID is a required denormalized field — always keep in sync.
                            paper.subjectID    = subject.id ?? UUID()
                            paper.rawSeriesName    = paperData.rawSeriesName
                            paper.normalizedSeries = paperData.normalizedSeries

                            let paperID = paper.id ?? UUID()

                            // ── Question structures (replace) ────────────────
                            ((paper.questionStructures as? Set<QuestionStructureMO>) ?? [])
                                .forEach { ctx.delete($0) }
                            for qsData in paperData.questionStructures {
                                let qs           = QuestionStructureMO(context: ctx)
                                qs.id            = UUID()
                                qs.paperID       = paperID   // required non-optional field
                                qs.questionLabel = qsData.questionLabel
                                qs.maxMarks      = qsData.maxMarks
                                qs.displayOrder  = qsData.displayOrder
                                qs.paper         = paper
                            }

                            // ── Attempts (dedup by barcode) ──────────────────
                            let existingAttempts = (paper.attempts as? Set<AttemptMO>) ?? []
                            for attemptData in paperData.attempts {
                                let attempt: AttemptMO
                                if let bv = attemptData.barcodeValue,
                                   let existing = existingAttempts.first(where: {
                                       $0.barcodeValue == bv
                                   }) {
                                    attempt = existing
                                } else {
                                    attempt       = AttemptMO(context: ctx)
                                    attempt.id    = attemptData.id
                                    attempt.paper = paper
                                }
                                // paperID is a required denormalized field — always keep in sync.
                                attempt.paperID           = paperID
                                attempt.attemptNumber     = attemptData.attemptNumber
                                attempt.barcodeValue      = attemptData.barcodeValue
                                attempt.paperType         = attemptData.paperType
                                attempt.totalScore        = attemptData.totalScore
                                attempt.rawGrade          = attemptData.rawGrade
                                attempt.durationInSeconds = attemptData.durationInSeconds
                                attempt.printTimestamp    = attemptData.printTimestamp
                                attempt.completedTimestamp = attemptData.completedTimestamp
                                attempt.reviewQuestions   = attemptData.reviewQuestions
                                attempt.additionalNotes   = attemptData.additionalNotes
                                attempt.scannedFilePath   = attemptData.scannedFilePath

                                // ── Event logs (replace) ─────────────────────
                                ((attempt.eventLogs as? Set<ETSEventLogMO>) ?? [])
                                    .forEach { ctx.delete($0) }
                                for logData in attemptData.eventLogs {
                                    let log             = ETSEventLogMO(context: ctx)
                                    log.id              = logData.id
                                    log.sequenceIndex   = logData.sequenceIndex
                                    log.eventType       = logData.eventType
                                    log.label           = logData.label
                                    log.durationSeconds = logData.durationSeconds
                                    log.marksEarned     = logData.marksEarned
                                    log.attempt         = attempt
                                }
                            }
                        }
                    }

                    try ctx.save()

                    // Prompt viewContext to surface the merged objects immediately.
                    DispatchQueue.main.async {
                        self.container.viewContext.refreshAllObjects()
                    }

                    continuation.resume()

                } catch {
                    ctx.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
