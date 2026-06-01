import CoreData

@objc(PaperMO)
final class PaperMO: NSManagedObject {

    @NSManaged var id: UUID?
    @NSManaged var subjectID: UUID?
    @NSManaged var rawSeriesName: String?
    @NSManaged var normalizedSeries: String?
    /// File-system path of the linked Question Paper PDF (nil if not yet assigned).
    @NSManaged var questionPaperPDFPath: String?
    /// File-system path of the linked Mark Scheme PDF (nil if not yet assigned).
    @NSManaged var markSchemePDFPath: String?
    @NSManaged var subject: SubjectMO?
    @NSManaged var attempts: NSSet?
    /// Grade boundary tables attached to this paper (one per exam series variant).
    @NSManaged var gradeThresholds: NSSet?
    /// Question structure definitions for this paper (QuestionStructureMO set).
    @NSManaged var questionStructures: NSSet?

    // MARK: - Convenience fetch

    static func fetchRequest() -> NSFetchRequest<PaperMO> {
        NSFetchRequest<PaperMO>(entityName: "PaperMO")
    }

    /// Returns the existing paper for a given subject + series, or nil.
    static func find(subjectID: UUID, normalizedSeries: String, in context: NSManagedObjectContext) -> PaperMO? {
        let req = fetchRequest()
        req.predicate = NSPredicate(
            format: "subjectID == %@ AND normalizedSeries == %@",
            subjectID as CVarArg, normalizedSeries
        )
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    // MARK: - Insert

    @discardableResult
    static func insert(
        subject: SubjectMO,
        rawSeriesName: String,
        normalizedSeries: String,
        in context: NSManagedObjectContext
    ) -> PaperMO {
        let obj = PaperMO(context: context)
        obj.id = UUID()
        obj.subjectID = subject.id
        obj.rawSeriesName = rawSeriesName
        obj.normalizedSeries = normalizedSeries
        obj.subject = subject
        return obj
    }
}
