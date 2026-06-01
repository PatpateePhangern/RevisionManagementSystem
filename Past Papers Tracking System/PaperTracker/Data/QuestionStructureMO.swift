import CoreData

/// Defines one question slot in an exam paper's structural blueprint.
/// The compound uniqueness constraint on [paperID, questionLabel] prevents
/// duplicate question labels for the same paper variant.
@objc(QuestionStructureMO)
final class QuestionStructureMO: NSManagedObject {

    @NSManaged var id:             UUID?
    /// Human-readable label, e.g. "Q1", "4a", "Section B".
    @NSManaged var questionLabel:  String?
    /// Maximum marks available for this question.
    @NSManaged var maxMarks:       Int16
    /// Zero-based sort index controlling display order.
    @NSManaged var displayOrder:   Int16
    /// Denormalised paper UUID — mirrors paper.id for the compound constraint.
    @NSManaged var paperID:        UUID?
    /// Which PDF tab this mapping belongs to: "questionPaper" or "markScheme".
    @NSManaged var source:         String?
    @NSManaged var paper:          PaperMO?

    // MARK: - Fetch helpers

    static func fetchRequest() -> NSFetchRequest<QuestionStructureMO> {
        NSFetchRequest<QuestionStructureMO>(entityName: "QuestionStructureMO")
    }

    /// Ordered question list for a given paper.
    static func fetch(
        paperID: UUID,
        in context: NSManagedObjectContext
    ) -> [QuestionStructureMO] {
        let req = fetchRequest()
        req.predicate = NSPredicate(format: "paperID == %@", paperID as CVarArg)
        req.sortDescriptors = [NSSortDescriptor(key: "displayOrder", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    // MARK: - Insert

    @discardableResult
    static func insert(
        label:        String,
        maxMarks:     Int16,
        displayOrder: Int16,
        source:       String = "questionPaper",
        paper:        PaperMO,
        in context:   NSManagedObjectContext
    ) -> QuestionStructureMO {
        let obj = QuestionStructureMO(context: context)
        obj.id            = UUID()
        obj.questionLabel = label
        obj.maxMarks      = maxMarks
        obj.displayOrder  = displayOrder
        obj.source        = source
        obj.paperID       = paper.id
        obj.paper         = paper
        return obj
    }

    // MARK: - Schematic cache copy
    /// Duplicates this question set onto a new paper that shares the same
    /// subject + normalised-series pairing, so the user doesn't re-enter
    /// questions for repeat attempts of the same paper.
    static func copyStructures(
        from sourcePaper: PaperMO,
        to   targetPaper: PaperMO,
        in   context:     NSManagedObjectContext
    ) {
        let existing = (sourcePaper.questionStructures as? Set<QuestionStructureMO>) ?? []
        guard !existing.isEmpty else { return }
        // Remove any pre-existing entries on the target first.
        let old = (targetPaper.questionStructures as? Set<QuestionStructureMO>) ?? []
        old.forEach { context.delete($0) }
        // Clone each structure.
        for q in existing.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            insert(
                label:        q.questionLabel ?? "",
                maxMarks:     q.maxMarks,
                displayOrder: q.displayOrder,
                paper:        targetPaper,
                in:           context
            )
        }
    }
}
