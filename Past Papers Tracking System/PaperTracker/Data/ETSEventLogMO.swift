import CoreData

/// Immutable chronological event recorded during a live ETS session.
///
/// Event types:
///   `QUESTION_SPENT` — the user moved off a question; duration = time spent.
///   `BREAK_A`        — accountable break; global timer kept running.
///   `BREAK_NA`       — non-accountable break; all timers paused.
@objc(ETSEventLogMO)
final class ETSEventLogMO: NSManagedObject {

    @NSManaged var id:             UUID?
    /// Zero-based index preserving chronological order.
    @NSManaged var sequenceIndex:  Int16
    @NSManaged var eventType:      String?
    /// Human-readable label, e.g. "Q1", "Break 2", "Q4 Resumed".
    @NSManaged var label:          String?
    @NSManaged var durationSeconds: Int64
    /// Raw marks entered by the user for this question slot (0 for breaks).
    @NSManaged var marksEarned:    Double
    @NSManaged var attempt:        AttemptMO?

    // MARK: - Fetch helpers

    static func fetchRequest() -> NSFetchRequest<ETSEventLogMO> {
        NSFetchRequest<ETSEventLogMO>(entityName: "ETSEventLogMO")
    }

    /// Returns all event log entries for an attempt, sorted by sequenceIndex.
    static func fetch(
        attempt: AttemptMO,
        in context: NSManagedObjectContext
    ) -> [ETSEventLogMO] {
        let req = fetchRequest()
        req.predicate = NSPredicate(format: "attempt == %@", attempt)
        req.sortDescriptors = [NSSortDescriptor(key: "sequenceIndex", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    // MARK: - Insert

    @discardableResult
    static func insert(
        sequenceIndex:   Int,
        eventType:       String,
        label:           String,
        durationSeconds: Int64,
        marksEarned:     Double,
        attempt:         AttemptMO,
        in context:      NSManagedObjectContext
    ) -> ETSEventLogMO {
        let obj = ETSEventLogMO(context: context)
        obj.id              = UUID()
        obj.sequenceIndex   = Int16(sequenceIndex)
        obj.eventType       = eventType
        obj.label           = label
        obj.durationSeconds = durationSeconds
        obj.marksEarned     = marksEarned
        obj.attempt         = attempt
        return obj
    }
}
