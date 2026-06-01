import SwiftUI
import CoreData

/// Sheet for creating a new batch from Complete Logs attempts.
///
/// Flow:
///  1. Scrollable list of all AttemptMO records (sorted newest print date first),
///     searchable by subject / series / variant.
///  2. Tick checkboxes to include attempts.
///  3. "Create Batch & Print" auto-generates the batch barcode, builds BatchMO,
///     generates both batch PDFs, and calls back.
struct BatchCreationSheet: View {

    @Environment(\.managedObjectContext) private var ctx
    @Binding var isPresented: Bool
    var onCreate: (BatchMO) -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "printTimestamp", ascending: false)],
        animation: .default
    ) private var attempts: FetchedResults<AttemptMO>

    @State private var searchText     = ""
    @State private var filterSubject  = "All"
    @State private var filterPaper    = "All"
    @State private var filterVariant  = "All"
    @State private var selectedIDs:   Set<NSManagedObjectID> = []
    @State private var isCreating     = false

    // MARK: - Filtered list

    private var allSubjectNames: [String] {
        let names = Set(attempts.compactMap { $0.paper?.subject?.name })
        return ["All"] + names.sorted()
    }
    private var allPaperNumbers: [String] {
        let nums = Set(attempts.compactMap { a -> String? in
            guard let s = a.paper?.normalizedSeries else { return nil }
            return SeriesFilterHelper.paperLabel(from: s)
        })
        return nums.isEmpty ? [] : ["All"] + nums.sorted()
    }
    private var allVariantNumbers: [String] {
        let nums = Set(attempts.compactMap { a -> String? in
            guard let s = a.paper?.normalizedSeries else { return nil }
            return SeriesFilterHelper.variantLabel(from: s)
        })
        return nums.isEmpty ? [] : ["All"] + nums.sorted()
    }

    private var filteredAttempts: [AttemptMO] {
        attempts.filter { a in
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                let subjHit   = (a.paper?.subject?.name ?? "").lowercased().contains(q)
                let seriesHit = (a.paper?.normalizedSeries ?? "").lowercased().contains(q)
                let dispHit   = (a.paper?.normalizedSeries ?? "")
                    .lowercased().contains(q)
                let bcHit     = (a.barcodeValue ?? "").lowercased().contains(q)
                if !(subjHit || seriesHit || dispHit || bcHit) { return false }
            }
            if filterSubject != "All", (a.paper?.subject?.name ?? "") != filterSubject { return false }
            if filterPaper   != "All" {
                let p = a.paper?.normalizedSeries.flatMap { SeriesFilterHelper.paperLabel(from: $0) }
                if p != filterPaper { return false }
            }
            if filterVariant != "All" {
                let v = a.paper?.normalizedSeries.flatMap { SeriesFilterHelper.variantLabel(from: $0) }
                if v != filterVariant { return false }
            }
            return true
        }
    }

    private static let printFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("New Batch")
                    .font(.system(size: 20, weight: .semibold))
                Text("Select papers from Complete Logs to include in this batch.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

            Divider()

            // ── Search + filters ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    TextField("Search subject, series, barcode…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .glassEffect(in: RoundedRectangle(cornerRadius: 8))

                // Filter chips
                HStack(spacing: 6) {
                    sheetFilterChip(label: "Subject", value: filterSubject, options: allSubjectNames) { filterSubject = $0 }
                    if allPaperNumbers.count > 1 {
                        sheetFilterChip(label: "Paper", value: filterPaper, options: allPaperNumbers) { filterPaper = $0 }
                    }
                    if allVariantNumbers.count > 1 {
                        sheetFilterChip(label: "Variant", value: filterVariant, options: allVariantNumbers) { filterVariant = $0 }
                    }
                    if filterSubject != "All" || filterPaper != "All" || filterVariant != "All" {
                        Button {
                            withAnimation(.smooth(duration: 0.18)) { filterSubject = "All"; filterPaper = "All"; filterVariant = "All" }
                        } label: {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        let ids = Set(filteredAttempts.map { $0.objectID })
                        withAnimation(.smooth(duration: 0.18)) { selectedIDs = ids }
                    } label: {
                        Text("Select All (\(filteredAttempts.count))")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    if !selectedIDs.isEmpty {
                        Button {
                            withAnimation(.smooth(duration: 0.18)) { selectedIDs.removeAll() }
                        } label: {
                            Text("Deselect All")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
                .animation(.smooth(duration: 0.2), value: selectedIDs.isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ── Attempt list ─────────────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 1) {
                    if filteredAttempts.isEmpty {
                        Text("No papers match your search")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(filteredAttempts, id: \.objectID) { attempt in
                            attemptCheckRow(attempt)
                        }
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 8)
                .animation(.smooth(duration: 0.2), value: searchText)
            }
            .frame(minHeight: 200, maxHeight: 400)

            Divider()

            // ── Footer ───────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Text("\(selectedIDs.count) paper\(selectedIDs.count == 1 ? "" : "s") selected")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.escape)

                Button {
                    createBatch()
                } label: {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create Batch & Print")
                    }
                }
                .buttonStyle(BlueGlassButtonStyle())
                .disabled(selectedIDs.isEmpty || isCreating)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680, height: 640)
    }

    // MARK: - Attempt check row

    private func attemptCheckRow(_ attempt: AttemptMO) -> some View {
        let isSelected = selectedIDs.contains(attempt.objectID)
        return Button {
            withAnimation(.smooth(duration: 0.14)) {
                if isSelected { selectedIDs.remove(attempt.objectID) }
                else           { selectedIDs.insert(attempt.objectID) }
            }
        } label: {
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .animation(.smooth(duration: 0.15), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(attempt.paper?.subject?.name ?? "Unknown")
                            .font(.system(size: 13, weight: .semibold))
                        if let norm = attempt.paper?.normalizedSeries {
                            Text(SeriesNormalizationEngine.displayName(from: norm))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }
                    }
                    HStack(spacing: 6) {
                        Text(attempt.barcodeValue ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        if let ts = attempt.printTimestamp {
                            Text("Printed: \(BatchCreationSheet.printFmt.string(from: ts))")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                }
                Spacer()
                Text("ATT \(attempt.attemptNumber)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.08)
                          : Color(nsColor: .windowBackgroundColor))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.14), value: isSelected)
    }

    // MARK: - Filter chip helper

    @ViewBuilder
    private func sheetFilterChip(label: String, value: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    withAnimation(.smooth(duration: 0.18)) { onChange(opt) }
                } label: {
                    HStack { Text(opt); if opt == value { Spacer(); Image(systemName: "checkmark") } }
                }
            }
        } label: {
            HStack(spacing: 3) {
                if value != "All" {
                    Text("\(label):").font(.system(size: 10)).foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text(value).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
                } else {
                    Text(label).font(.system(size: 10)).foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(value != "All" ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(value != "All" ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        }
        .menuStyle(.borderlessButton).fixedSize().focusEffectDisabled()
    }

    // MARK: - Create batch

    private func createBatch() {
        guard !selectedIDs.isEmpty else { return }
        isCreating = true

        let selectedAttempts = attempts
            .filter { selectedIDs.contains($0.objectID) }
            .sorted { ($0.printTimestamp ?? .distantPast) > ($1.printTimestamp ?? .distantPast) }

        // Auto-generate batch: BatchMO.insert handles the barcode/name generation
        let batch = BatchMO.insert(name: "", in: ctx)

        for (idx, attempt) in selectedAttempts.enumerated() {
            _ = BatchItemMO.insert(attempt: attempt, batch: batch,
                                   displayOrder: Int16(idx), in: ctx)
        }
        PersistenceController.shared.save()

        let barcodeVal = batch.batchBarcodeValue ?? ""

        let listPapers: [BatchListPDFGenerator.BatchPaperEntry] = selectedAttempts.compactMap { a in
            guard let p = a.paper else { return nil }
            return BatchListPDFGenerator.BatchPaperEntry(
                subjectName:    p.subject?.name ?? "Unknown",
                seriesDisplay:  SeriesNormalizationEngine.displayName(from: p.normalizedSeries ?? ""),
                attemptNumber:  a.attemptNumber,
                barcodeValue:   a.barcodeValue ?? "",
                printTimestamp: a.printTimestamp ?? Date())
        }

        let listPayload = BatchListPDFGenerator.BatchListPayload(
            batchBarcode: barcodeVal, papers: listPapers)

        isPresented = false
        onCreate(batch)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            BatchListPDFGenerator.generateAndPrint(payload: listPayload)
            isCreating = false
        }
    }
}
