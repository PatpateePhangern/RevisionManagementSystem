import CoreData

@objc(BatchItemMO)
final class BatchItemMO: NSManagedObject {

    @NSManaged var id: UUID?
    @NSManaged var batchID: UUID?
    @NSManaged var batchStatus: String?   // "Pending" | "Complete"
    @NSManaged var processedTimestamp: Date?
    @NSManaged var displayOrder: Int16
    @NSManaged var batch: BatchMO?
    @NSManaged var attempt: AttemptMO?

    // MARK: - Convenience fetch

    static func fetchRequest() -> NSFetchRequest<BatchItemMO> {
        NSFetchRequest<BatchItemMO>(entityName: "BatchItemMO")
    }

    var isComplete: Bool { batchStatus == "Complete" }

    // MARK: - Insert

    @discardableResult
    static func insert(
        attempt: AttemptMO,
        batch: BatchMO,
        displayOrder: Int16,
        in context: NSManagedObjectContext
    ) -> BatchItemMO {
        let obj = BatchItemMO(context: context)
        obj.id = UUID()
        obj.batchID = batch.id
        obj.batchStatus = "Pending"
        obj.displayOrder = displayOrder
        obj.batch = batch
        obj.attempt = attempt
        return obj
    }

    /// Mark this item as complete with the current timestamp.
    func markComplete() {
        batchStatus = "Complete"
        processedTimestamp = Date()
    }
}
