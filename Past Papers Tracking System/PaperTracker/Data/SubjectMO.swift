import CoreData

@objc(SubjectMO)
final class SubjectMO: NSManagedObject {

    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var papers: NSSet?

    // Exam dates (P1 is also the single date for non-CS subjects)
    @NSManaged var examDate1: Date?
    @NSManaged var examDate2: Date?
    @NSManaged var examDate3: Date?
    @NSManaged var examDate4: Date?

    /// Returns the exam date for a given paper number (1-indexed).
    /// Falls back to examDate1 when the paper-specific date is nil.
    func examDate(forPaper paper: Int) -> Date? {
        switch paper {
        case 2: return examDate2 ?? examDate1
        case 3: return examDate3 ?? examDate1
        case 4: return examDate4 ?? examDate1
        default: return examDate1
        }
    }

    /// True when the subject has multiple paper-level exam dates (CS variants).
    var hasMultiplePaperDates: Bool {
        guard let n = name?.uppercased() else { return false }
        return n.contains("CS1") || n.contains("CS2") || n.contains("CS3") || n.contains("CS4")
            || n.contains("COMPUTER SCIENCE")
    }

    // MARK: - Convenience fetch

    static func fetchRequest() -> NSFetchRequest<SubjectMO> {
        NSFetchRequest<SubjectMO>(entityName: "SubjectMO")
    }

    static func fetchAll(in context: NSManagedObjectContext) -> [SubjectMO] {
        let req = fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare))]
        return (try? context.fetch(req)) ?? []
    }

    // MARK: - Insert

    @discardableResult
    static func insert(name: String, in context: NSManagedObjectContext) -> SubjectMO {
        let obj = SubjectMO(context: context)
        obj.id = UUID()
        obj.name = name
        return obj
    }
}
