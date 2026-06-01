import CoreData

@objc(BatchMO)
final class BatchMO: NSManagedObject {

    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var batchBarcodeValue: String?
    @NSManaged var createdTimestamp: Date?
    @NSManaged var items: NSSet?

    // MARK: - Convenience fetch

    static func fetchRequest() -> NSFetchRequest<BatchMO> {
        NSFetchRequest<BatchMO>(entityName: "BatchMO")
    }

    /// All batches sorted newest first.
    static func fetchAllSorted(in context: NSManagedObjectContext) -> [BatchMO] {
        let req = fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdTimestamp", ascending: false)]
        return (try? context.fetch(req)) ?? []
    }

    static func find(barcodeValue: String, in context: NSManagedObjectContext) -> BatchMO? {
        let req = fetchRequest()
        req.predicate = NSPredicate(format: "batchBarcodeValue == %@", barcodeValue)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    // MARK: - Insert

    @discardableResult
    static func insert(name: String = "", in context: NSManagedObjectContext) -> BatchMO {
        let obj = BatchMO(context: context)
        obj.id = UUID()
        obj.createdTimestamp = Date()
        obj.batchBarcodeValue = BatchMO.generateBarcodeValue()
        // name is stored as the barcode value for display purposes; callers may pass ""
        obj.name = obj.batchBarcodeValue
        return obj
    }

    // MARK: - Sorted items

    var sortedItems: [BatchItemMO] {
        let set = items as? Set<BatchItemMO> ?? []
        return set.sorted { $0.displayOrder < $1.displayOrder }
    }

    var completedCount: Int {
        (items as? Set<BatchItemMO> ?? []).filter { $0.batchStatus == "Complete" }.count
    }

    var totalCount: Int {
        (items as? Set<BatchItemMO> ?? []).count
    }

    // MARK: - Barcode generation

    /// Generates a unique batch barcode: BATCH-YYYYMMDD-HHMMSS
    static func generateBarcodeValue() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return "BATCH-\(fmt.string(from: Date()))"
    }

    static func isBatchBarcode(_ value: String) -> Bool {
        value.hasPrefix("BATCH-")
    }
}
