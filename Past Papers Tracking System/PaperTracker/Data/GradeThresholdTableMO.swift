import CoreData

/// One grade-boundary table entry, linked to a specific exam paper/series.
/// `rawSeriesKey` mirrors the normalised series string (e.g. "2025-05-P1V2") so
/// that the same threshold set can be auto-loaded for any future attempt of
/// the same paper.
@objc(GradeThresholdTableMO)
final class GradeThresholdTableMO: NSManagedObject {

    @NSManaged var id:               UUID?
    /// The normalised series key this table belongs to (e.g. "2025-05" or "2025-05-P1V2").
    @NSManaged var rawSeriesKey:     String?
    @NSManaged var maxPossibleMarks: Int16
    @NSManaged var hasAStar:         Bool
    /// Minimum mark for A* (only valid when hasAStar == true).
    @NSManaged var markAStar:        Int16
    @NSManaged var markA:            Int16
    @NSManaged var markB:            Int16
    @NSManaged var markC:            Int16
    @NSManaged var markD:            Int16
    @NSManaged var markE:            Int16
    @NSManaged var paper:            PaperMO?

    // MARK: - Grade calculation

    /// Returns the grade letter for a given raw score against this threshold table.
    func grade(for score: Double) -> String {
        let s = Int16(min(max(score, 0), Double(Int16.max)))
        if hasAStar && s >= markAStar { return "A*" }
        if s >= markA { return "A" }
        if s >= markB { return "B" }
        if s >= markC { return "C" }
        if s >= markD { return "D" }
        if s >= markE { return "E" }
        return "U"
    }

    /// Percentage score (0–100), or nil if maxPossibleMarks is 0.
    func percentage(for score: Double) -> Double? {
        guard maxPossibleMarks > 0 else { return nil }
        return (score / Double(maxPossibleMarks)) * 100.0
    }

    // MARK: - Fetch helpers

    static func fetchRequest() -> NSFetchRequest<GradeThresholdTableMO> {
        NSFetchRequest<GradeThresholdTableMO>(entityName: "GradeThresholdTableMO")
    }

    /// Returns the most recently inserted threshold for the given normalised series key,
    /// or nil if none exists.
    static func find(
        rawSeriesKey key: String,
        in context: NSManagedObjectContext
    ) -> GradeThresholdTableMO? {
        let req = fetchRequest()
        req.predicate = NSPredicate(format: "rawSeriesKey == %@", key)
        req.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    // MARK: - Insert

    @discardableResult
    static func insert(
        rawSeriesKey key:  String,
        paper:             PaperMO,
        in context:        NSManagedObjectContext
    ) -> GradeThresholdTableMO {
        let obj = GradeThresholdTableMO(context: context)
        obj.id           = UUID()
        obj.rawSeriesKey = key
        obj.paper        = paper
        return obj
    }
}
