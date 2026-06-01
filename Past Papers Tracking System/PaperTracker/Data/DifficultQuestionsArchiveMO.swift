import CoreData

// MARK: - DifficultQuestionsArchiveMO

@objc(DifficultQuestionsArchiveMO)
final class DifficultQuestionsArchiveMO: NSManagedObject {

    // MARK: Identity

    /// Unique identifier for this DQA record.
    @NSManaged var dqaID: UUID?
    /// Barcode of the original attempt that spawned this DQA, e.g. `P3MATH-2024-10-ATT1`.
    @NSManaged var originalBarcode: String?
    /// DQA-specific barcode, e.g. `DQA-P3MATH-2024-10-ATT1-D1`.
    @NSManaged var dqaBarcode: String?

    // MARK: Exam metadata (denormalised for quick display without fetching PaperMO)

    /// Subject name, e.g. "Mathematics".
    @NSManaged var subject: String?
    /// Normalised series string, e.g. "2024-10".
    @NSManaged var examSeries: String?
    /// "practice" | "timed" | nil — mirrors `AttemptMO.paperType`.
    @NSManaged var paperType: String?
    /// Attempt number of the parent exam attempt (1-based).
    @NSManaged var parentExamAttemptNumber: Int16
    /// Which repetition of this DQA this is (1 = first, 2 = repeat, …).
    @NSManaged var dqaAttemptNumber: Int16

    // MARK: Scheduling

    /// Scheduled date the student should complete this DQA by.
    @NSManaged var committedDate: Date?
    /// True when a newer DQA exists for the same original barcode (auto-set by the system).
    @NSManaged var isOutdated: Bool

    // MARK: Question selection

    /// Binary-encoded `[String]` of selected question label strings, e.g. `["Q1 [pp.3-5]", "Q3 [p.7]"]`.
    /// Stored as a plist-encoded `Data` blob so it survives lightweight migration.
    @NSManaged var sourceQuestionLabels: Data?

    // MARK: Compiled PDF paths

    /// Absolute file path to the compiled question-paper PDF for this DQA.
    @NSManaged var compiledQuestionPDFPath: String?
    /// Absolute file path to the compiled mark-scheme PDF for this DQA.
    @NSManaged var compiledMarkSchemePDFPath: String?
    /// Absolute file path of the scanned completed DQA PDF after drop-scan.
    @NSManaged var completedDQAFilePath: String?

    // MARK: Timestamps

    /// When this DQA record was first created.
    @NSManaged var createdTimestamp: Date?
    /// When the *original* exam attempt was completed (copied from `AttemptMO.completedTimestamp`).
    @NSManaged var originalCompletedTimestamp: Date?
    /// When the student's completed DQA scan was ingested and the cycle closed.
    @NSManaged var dqaCompletedTimestamp: Date?

    // MARK: - Computed helpers

    /// Convenience accessor for `sourceQuestionLabels` as a decoded Swift array.
    var decodedSourceQuestions: [String] {
        get {
            guard let data = sourceQuestionLabels else { return [] }
            return (try? PropertyListDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            sourceQuestionLabels = try? PropertyListEncoder().encode(newValue)
        }
    }

    /// `true` when `dqaCompletedTimestamp` has been set (the cycle is closed).
    var isComplete: Bool { dqaCompletedTimestamp != nil }

    // MARK: - Urgency sort key

    /// Urgency for list ordering: incomplete items sorted by committedDate ascending,
    /// outdated or complete items sorted to the bottom.
    var urgencyKey: Date {
        if isOutdated || isComplete { return Date.distantFuture }
        return committedDate ?? Date.distantFuture
    }

    // MARK: - Fetch

    static func fetchRequest() -> NSFetchRequest<DifficultQuestionsArchiveMO> {
        NSFetchRequest<DifficultQuestionsArchiveMO>(entityName: "DifficultQuestionsArchiveMO")
    }

    /// All DQA records sorted by urgency (active items first, then by committedDate).
    static func fetchAllSorted(in context: NSManagedObjectContext) -> [DifficultQuestionsArchiveMO] {
        let req = fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(key: "isOutdated", ascending: true),
            NSSortDescriptor(key: "dqaCompletedTimestamp", ascending: true),
            NSSortDescriptor(key: "committedDate", ascending: true),
            NSSortDescriptor(key: "createdTimestamp", ascending: false)
        ]
        return (try? context.fetch(req)) ?? []
    }

    /// Find an existing active DQA record for a given original barcode (not outdated, not complete).
    static func findActive(originalBarcode: String, in context: NSManagedObjectContext) -> DifficultQuestionsArchiveMO? {
        let req = fetchRequest()
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "originalBarcode == %@", originalBarcode),
            NSPredicate(format: "isOutdated == NO"),
            NSPredicate(format: "dqaCompletedTimestamp == nil")
        ])
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    // MARK: - Insert

    /// Creates a new DQA record wired to the given attempt.
    @discardableResult
    static func insert(
        originalBarcode: String,
        dqaAttemptNumber: Int16 = 1,
        subject: String,
        examSeries: String,
        paperType: String?,
        parentExamAttemptNumber: Int16,
        originalCompletedTimestamp: Date?,
        in context: NSManagedObjectContext
    ) -> DifficultQuestionsArchiveMO {
        let obj = DifficultQuestionsArchiveMO(context: context)
        obj.dqaID = UUID()
        obj.originalBarcode = originalBarcode
        obj.dqaAttemptNumber = dqaAttemptNumber
        // Build DQA barcode: DQA-{originalBarcode}-D{N}
        obj.dqaBarcode = "DQA-\(originalBarcode)-D\(dqaAttemptNumber)"
        obj.subject = subject
        obj.examSeries = examSeries
        obj.paperType = paperType
        obj.parentExamAttemptNumber = parentExamAttemptNumber
        obj.isOutdated = false
        obj.createdTimestamp = Date()
        obj.originalCompletedTimestamp = originalCompletedTimestamp
        return obj
    }

    // MARK: - Outdate all existing active records for same original barcode

    /// Marks every non-outdated, incomplete DQA for `originalBarcode` as outdated
    /// so only the newest record is treated as live.
    static func outdateAll(originalBarcode: String, in context: NSManagedObjectContext) {
        let req = fetchRequest()
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "originalBarcode == %@", originalBarcode),
            NSPredicate(format: "isOutdated == NO"),
            NSPredicate(format: "dqaCompletedTimestamp == nil")
        ])
        let existing = (try? context.fetch(req)) ?? []
        for record in existing { record.isOutdated = true }
    }
}
