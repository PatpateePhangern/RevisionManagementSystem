import SwiftUI
import CoreData

// MARK: - Notification
extension Notification.Name {
    static let openBatchLogsNewBatch = Notification.Name("openBatchLogsNewBatch")
}

/// Batch Logs workspace.
///
/// Left panel  — list of BatchMO records, newest first, + "New Batch" button.
/// Right panel — selected batch detail showing all BatchItemMO with their status.
struct BatchLogsView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdTimestamp", ascending: false)],
        animation: .default
    ) private var batches: FetchedResults<BatchMO>

    @State private var selectedBatchID:    NSManagedObjectID?
    @State private var showCreationSheet   = false
    @State private var searchText          = ""

    @Namespace private var batchSelectionNS

    private var selectedBatch: BatchMO? {
        guard let id = selectedBatchID else { return nil }
        return batches.first { $0.objectID == id }
    }

    private var filteredBatches: [BatchMO] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(batches) }
        return batches.filter { b in
            (b.name ?? "").lowercased().contains(q) ||
            (b.batchBarcodeValue ?? "").lowercased().contains(q)
        }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            detailPane
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $showCreationSheet) {
            BatchCreationSheet(isPresented: $showCreationSheet) { newBatch in
                withAnimation(.smooth(duration: 0.25)) {
                    selectedBatchID = newBatch.objectID
                }
            }
            .environment(\.managedObjectContext, ctx)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBatchLogsNewBatch)) { _ in
            showCreationSheet = true
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Batch Logs")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { showCreationSheet = true }
                } label: {
                    Label("New Batch  [⌘N]", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(BlueGlassButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
                .focusEffectDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                TextField("Search batches…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button { withAnimation(.smooth(duration: 0.18)) { searchText = "" } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    if filteredBatches.isEmpty {
                        Text(searchText.isEmpty ? "No batches yet" : "No results")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(filteredBatches, id: \.objectID) { batch in
                            batchSelectionRow(batch)
                        }
                    }
                }
                .padding(6)
                .animation(.smooth(duration: 0.22), value: searchText)
            }

            Divider()

            HStack {
                Text("\(filteredBatches.count) batch\(filteredBatches.count == 1 ? "" : "es")")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Batch selection row

    private func batchSelectionRow(_ batch: BatchMO) -> some View {
        let isSelected = selectedBatchID == batch.objectID
        return Button {
            withAnimation(.smooth(duration: 0.2)) { selectedBatchID = batch.objectID }
        } label: {
            batchRowContent(batch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.13))
                    .matchedGeometryEffect(id: "batchSelPill", in: batchSelectionNS)
            }
        }
        .animation(.easeOut(duration: 0.14), value: selectedBatchID)
    }

    @ViewBuilder
    private func batchRowContent(_ batch: BatchMO) -> some View {
        let total     = batch.totalCount
        let completed = batch.completedCount
        let fmtDate   = batch.createdTimestamp.map { BatchLogsView.dateFormatter.string(from: $0) } ?? ""

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(batch.batchBarcodeValue ?? "—")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .labelColor))
                if !fmtDate.isEmpty {
                    Text(fmtDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                batchProgressBadge(completed: completed, total: total)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func batchProgressBadge(completed: Int, total: Int) -> some View {
        let pct = total > 0 ? Double(completed) / Double(total) : 0
        let allDone = completed == total && total > 0
        let color: Color = allDone ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
        Text("\(completed)/\(total)")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        if total > 0 {
            ProgressView(value: pct)
                .progressViewStyle(.linear)
                .frame(width: 50)
                .tint(color)
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let batch = selectedBatch {
            BatchDetailView(batch: batch)
                .environment(\.managedObjectContext, ctx)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray.2")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text("Select a batch to view details")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Button("New Batch") { showCreationSheet = true }
                    .buttonStyle(BlueGlassButtonStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Formatters

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
}

// MARK: - Batch detail view

private struct BatchDetailView: View {
    @ObservedObject var batch: BatchMO
    @Environment(\.managedObjectContext) private var ctx

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                itemsSection
                Divider()
                actionRow
            }
            .padding(24)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(batch.batchBarcodeValue ?? "Unnamed Batch")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
            HStack(spacing: 12) {
                Label(batch.batchBarcodeValue ?? "—", systemImage: "barcode")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                if let ts = batch.createdTimestamp {
                    Label(BatchLogsView.dateFormatter.string(from: ts), systemImage: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            HStack(spacing: 6) {
                let c = batch.completedCount; let t = batch.totalCount
                let allDone = c == t && t > 0
                Circle().fill(allDone ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                    .frame(width: 8, height: 8)
                Text(allDone ? "All Complete" : "\(c) of \(t) processed")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Papers in Batch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 1) {
                ForEach(batch.sortedItems, id: \.objectID) { item in
                    BatchItemRow(item: item)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Print List") { printList() }
                .buttonStyle(BlueGlassButtonStyle())

            Spacer()

            Button("Delete Batch", role: .destructive) {
                ctx.delete(batch)
                PersistenceController.shared.save()
            }
            .buttonStyle(RedGlassButtonStyle())
        }
    }

    // MARK: - Payload builder

    private func makeListPayload() -> BatchListPDFGenerator.BatchListPayload {
        let barcodeVal = batch.batchBarcodeValue ?? ""
        let papers: [BatchListPDFGenerator.BatchPaperEntry] = batch.sortedItems.compactMap { item in
            guard let a = item.attempt, let p = a.paper else { return nil }
            return BatchListPDFGenerator.BatchPaperEntry(
                subjectName:    p.subject?.name ?? "Unknown",
                seriesDisplay:  SeriesNormalizationEngine.displayName(from: p.normalizedSeries ?? ""),
                attemptNumber:  a.attemptNumber,
                barcodeValue:   a.barcodeValue ?? "",
                printTimestamp: a.printTimestamp ?? Date()
            )
        }
        return BatchListPDFGenerator.BatchListPayload(batchBarcode: barcodeVal, papers: papers)
    }

    private func printList() {
        BatchListPDFGenerator.generateAndPrint(payload: makeListPayload())
    }
}

// MARK: - Batch item row

private struct BatchItemRow: View {
    @ObservedObject var item: BatchItemMO

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                let subj   = item.attempt?.paper?.subject?.name ?? "Unknown"
                let series = item.attempt?.paper?.normalizedSeries.map {
                    SeriesNormalizationEngine.displayName(from: $0)
                } ?? "—"
                let attNum = item.attempt?.attemptNumber ?? 0
                Text("\(subj) — \(series)  ATT\(attNum)")
                    .font(.system(size: 13, weight: .medium))
                Text(item.attempt?.barcodeValue ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBadge: some View {
        let isComplete = item.isComplete
        let color: Color = isComplete ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
        return Text(isComplete ? "Complete" : "Pending")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .animation(.smooth(duration: 0.25), value: isComplete)
    }
}
