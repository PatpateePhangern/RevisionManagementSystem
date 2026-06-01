import CoreData

@objc(AttemptMO)
final class AttemptMO: NSManagedObject {

    @NSManaged var id: UUID?
    @NSManaged var paperID: UUID?
    @NSManaged var attemptNumber: Int16
    @NSManaged var barcodeValue: String?
    @NSManaged var printTimestamp: Date?
    @NSManaged var completedTimestamp: Date?
    @NSManaged var reviewQuestions: String?
    @NSManaged var additionalNotes: String?
    @NSManaged var scannedFilePath: String?

    // ── v10 section image blobs ─────────────────────────────────────────────
    /// PNG-encoded crop of the คำถามที่ต้องดู section (stored at page 2× scale).
    @NSManaged var difficultQuestionsImageData: Data?
    /// PNG-encoded crop of the Additional Notes section (stored at page 2× scale).
    @NSManaged var additionalNotesImageData: Data?
    @NSManaged var paper: PaperMO?

    // ── v4 grade / timing fields ────────────────────────────────────────────
    /// "practice" | "timed" | nil (not yet classified)
    @NSManaged var paperType: String?
    /// User-overridable workflow status label.
    /// Values: "Pending" | "Done" | "Ask Teacher" | "Pending Analysis" | nil (auto-derived).
    @NSManaged var manualStatus: String?
    /// Raw score entered by the user (e.g., 45.0).
    @NSManaged var totalScore: Double
    /// Computed grade letter, e.g. "A", "B", "A*". Nil until graded.
    @NSManaged var rawGrade: String?
    /// Exam duration in whole seconds (e.g., 5400 = 1 h 30 m).
    @NSManaged var durationInSeconds: Int64
    /// ETS event log entries recorded during a live session (ETSEventLogMO set).
    /// Non-nil and non-empty ↔ this attempt was driven by the Exam Timing System.
    @NSManaged var eventLogs: NSSet?

    /// Batch items that include this attempt (BatchItemMO set).
    @NSManaged var batchItems: NSSet?

    // MARK: - Computed

    var isComplete: Bool { completedTimestamp != nil }

    // MARK: - Convenience fetch

    static func fetchRequest() -> NSFetchRequest<AttemptMO> {
        NSFetchRequest<AttemptMO>(entityName: "AttemptMO")
    }

    /// All attempts, incomplete first then sorted by printTimestamp descending.
    static func fetchAllSorted(in context: NSManagedObjectContext) -> [AttemptMO] {
        let req = fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(key: "completedTimestamp", ascending: true),
            NSSortDescriptor(key: "printTimestamp", ascending: false)
        ]
        return (try? context.fetch(req)) ?? []
    }

    static func find(barcodeValue: String, in context: NSManagedObjectContext) -> AttemptMO? {
        let req = fetchRequest()
        req.predicate = NSPredicate(format: "barcodeValue == %@", barcodeValue)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    // MARK: - Insert

    @discardableResult
    static func insert(
        paper: PaperMO,
        attemptNumber: Int16,
        barcodeValue: String,
        in context: NSManagedObjectContext
    ) -> AttemptMO {
        let obj = AttemptMO(context: context)
        obj.id = UUID()
        obj.paperID = paper.id
        obj.attemptNumber = attemptNumber
        obj.barcodeValue = barcodeValue
        obj.printTimestamp = Date()
        obj.paper = paper
        return obj
    }
}
