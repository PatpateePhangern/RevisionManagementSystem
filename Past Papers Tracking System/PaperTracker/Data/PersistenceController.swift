import CoreData

final class PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentContainer

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PaperTracker")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable lightweight (inferred) migration so the store automatically
        // upgrades from v1 → v2 (addition of difficultQuestionsImageData and
        // additionalNotesImageData attributes on AttemptMO).
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically    = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                // Log diagnostics and surface a clear message rather than silent failure.
                let storeURL = description.url?.path ?? "unknown path"
                fatalError(
                    """
                    Core Data store failed at \(storeURL).
                    Error: \(error.localizedDescription)
                    UserInfo: \(error.userInfo)
                    """
                )
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = "ViewContext"
    }

    // MARK: - Save

    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("[PersistenceController] Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Background worker

    /// Returns a child background context configured with the same merge policy.
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.name = "BackgroundContext"
        return ctx
    }

    /// Perform a block on a private background context and propagate changes to viewContext.
    func performBackground(_ block: @Sendable @escaping (NSManagedObjectContext) throws -> Void) {
        let ctx = newBackgroundContext()
        ctx.perform {
            do {
                try block(ctx)
                if ctx.hasChanges { try ctx.save() }
            } catch {
                print("[PersistenceController] Background task failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Batch lookup

    /// Finds the BatchMO for a given batch barcode value.
    func findBatch(barcodeValue: String) -> BatchMO? {
        BatchMO.find(barcodeValue: barcodeValue, in: container.viewContext)
    }

    // MARK: - Compound attempt lookup

    /// Locates an `AttemptMO` using a compound `AND` predicate that matches
    /// the barcode value **and** the paper's normalised series parsed from the
    /// barcode string — more robust than a single-field lookup.
    ///
    /// **Barcode format:** `{SHORTCODE}-{SERIES}-ATT{N}`
    /// Examples:
    ///   - `P3MATH-2024-10-ATT1`       → series = `2024-10`
    ///   - `CS1CS2-2025-05-P1V2-ATT1`  → series = `2025-05-P1V2`
    ///
    /// Parsing strategy: split on `"-"`, find the first token that starts with
    /// `"ATT"` (case-insensitive), and rejoin `tokens[1..<attIndex]` as the
    /// normalised series.  Both `barcodeValue` and `paper.normalizedSeries`
    /// must match, eliminating any theoretical collision across different papers.
    func findAttempt(barcodeValue: String) -> AttemptMO? {
        let ctx = container.viewContext

        // Parse the normalised series from the barcode string.
        //
        // Barcode format: {SHORTCODE}-{SERIES}-ATT{N}
        //   e.g.  P3MATH-2024-10-ATT1      → tokens[0]="P3MATH", attIndex=3,  series="2024-10"
        //         CS1CS2-2025-05-P1V2-ATT1  → tokens[0]="CS1CS2", attIndex=4,  series="2025-05-P1V2"
        //
        // Strategy: split strictly on "-", locate the first token that starts with "ATT"
        // (case-insensitive), then rejoin tokens[1..<attIndex] as the normalised series.
        let parsedSeries: String? = {
            let tokens = barcodeValue.components(separatedBy: "-")
            // Need at least: shortcode + one series token + ATT token  (≥ 3 tokens)
            guard tokens.count >= 3 else { return nil }
            guard let attIndex = tokens.firstIndex(where: { $0.uppercased().hasPrefix("ATT") }),
                  attIndex >= 2 else { return nil }   // must have shortcode + ≥1 series token before ATT
            let series = tokens[1..<attIndex].joined(separator: "-")
            return series.isEmpty ? nil : series
        }()

        let req = AttemptMO.fetchRequest()

        if let series = parsedSeries {
            // Compound predicate: barcodeValue AND paper.normalizedSeries both match.
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "barcodeValue == %@", barcodeValue),
                NSPredicate(format: "paper.normalizedSeries == %@", series)
            ])
        } else {
            // Non-standard barcode format — fall back to barcodeValue-only match.
            req.predicate = NSPredicate(format: "barcodeValue == %@", barcodeValue)
        }

        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }
}
