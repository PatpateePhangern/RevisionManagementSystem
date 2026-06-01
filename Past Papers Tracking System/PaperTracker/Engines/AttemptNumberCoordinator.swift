import CoreData

/// Thread-safe coordinator that determines the next sequential attempt number
/// for a given subject + series combination and propagates schematic question
/// structures to newly-created papers so the user never re-enters questions
/// for repeat attempts of the same paper variant.
struct AttemptNumberCoordinator {

    // MARK: - Attempt numbering

    /// Returns `count(existing matching attempts) + 1`.
    ///
    /// The query joins through the Paper relationship so a single fetch counts
    /// every AttemptMO whose parent paper belongs to the target subject and series.
    nonisolated static func nextAttemptNumber(
        subjectID: UUID,
        normalizedSeries: String,
        context: NSManagedObjectContext
    ) throws -> Int16 {
        let req = NSFetchRequest<AttemptMO>(entityName: "AttemptMO")
        req.predicate = NSPredicate(
            format: "paper.subjectID == %@ AND paper.normalizedSeries == %@",
            subjectID as CVarArg,
            normalizedSeries
        )
        let count = try context.count(for: req)
        return Int16(count) + 1
    }

    /// Async variant — executes on the supplied context's private queue to
    /// avoid blocking the main thread during rapid sequential calls.
    nonisolated static func nextAttemptNumberAsync(
        subjectID: UUID,
        normalizedSeries: String,
        context: NSManagedObjectContext
    ) async throws -> Int16 {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let n = try nextAttemptNumber(
                        subjectID: subjectID,
                        normalizedSeries: normalizedSeries,
                        context: context
                    )
                    continuation.resume(returning: n)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Schematic caching

    /// Looks for any earlier PaperMO sharing the same subjectID + normalizedSeries
    /// that already has QuestionStructureMO entries, and copies those structures
    /// onto `targetPaper` if it has none of its own.
    ///
    /// Call this immediately after creating a new PaperMO (before saving) so
    /// the ETS timer screen can pre-populate question rows without prompting
    /// the user to re-enter them.
    nonisolated static func applySchematicCacheIfAvailable(
        to targetPaper: PaperMO,
        subjectID: UUID,
        normalizedSeries: String,
        in context: NSManagedObjectContext
    ) {
        // Skip if the target already has structures (e.g., user just edited them).
        let existing = (targetPaper.questionStructures as? Set<QuestionStructureMO>) ?? []
        guard existing.isEmpty else { return }

        // Find the most-recently-created sibling paper with question structures.
        let req = NSFetchRequest<PaperMO>(entityName: "PaperMO")
        req.predicate = NSPredicate(
            format: "subjectID == %@ AND normalizedSeries == %@ AND SELF != %@",
            subjectID as CVarArg,
            normalizedSeries,
            targetPaper
        )
        req.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let candidates = (try? context.fetch(req)) ?? []

        guard let source = candidates.first(where: {
            !( ($0.questionStructures as? Set<QuestionStructureMO> ?? []).isEmpty )
        }) else { return }

        QuestionStructureMO.copyStructures(from: source, to: targetPaper, in: context)
    }
}
