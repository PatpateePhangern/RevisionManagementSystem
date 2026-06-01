import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - DQAMainView

/// Root view for the Difficult Questions Archive standalone window.
///
/// Layout:
///   Left sidebar  — searchable master list sorted by urgency / committedDate
///   Right pane    — detail view for the selected DQA record, or an empty-state prompt
struct DQAMainView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \DifficultQuestionsArchiveMO.isOutdated,          ascending: true),
            NSSortDescriptor(keyPath: \DifficultQuestionsArchiveMO.dqaCompletedTimestamp, ascending: true),
            NSSortDescriptor(keyPath: \DifficultQuestionsArchiveMO.committedDate,        ascending: true),
            NSSortDescriptor(keyPath: \DifficultQuestionsArchiveMO.createdTimestamp,     ascending: false)
        ],
        animation: .default
    )
    private var allRecords: FetchedResults<DifficultQuestionsArchiveMO>

    @State private var subjectSearch: String = ""
    @State private var seriesSearch:  String = ""
    @State private var barcodeSearch: String = ""
    @State private var selectedID: NSManagedObjectID? = nil
    @State private var showSetupSheet    = false

    // MARK: Filtered list

    private var filteredRecords: [DifficultQuestionsArchiveMO] {
        allRecords.filter { rec in
            let subjectOK  = subjectSearch.isEmpty
                || (rec.subject       ?? "").localizedCaseInsensitiveContains(subjectSearch)
            let seriesOK   = seriesSearch.isEmpty
                || (rec.examSeries    ?? "").localizedCaseInsensitiveContains(seriesSearch)
            let barcodeOK  = barcodeSearch.isEmpty
                || (rec.originalBarcode ?? "").localizedCaseInsensitiveContains(barcodeSearch)
                || (rec.dqaBarcode      ?? "").localizedCaseInsensitiveContains(barcodeSearch)
            return subjectOK && seriesOK && barcodeOK
        }
    }

    // MARK: Search suggestion lists (unique sorted values from all records)

    private var subjectSuggestions:  [String] { Array(Set(allRecords.compactMap(\.subject))).sorted() }
    private var seriesSuggestions:   [String] { Array(Set(allRecords.compactMap(\.examSeries))).sorted() }
    private var barcodeSuggestions:  [String] { Array(Set(allRecords.compactMap(\.originalBarcode))).sorted() }

    private var selectedRecord: DifficultQuestionsArchiveMO? {
        guard let id = selectedID else { return nil }
        return allRecords.first { $0.objectID == id }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // ── Left: master list ─────────────────────────────────────────────
            VStack(spacing: 0) {
                listHeader
                Divider()
                searchPanel
                Divider()
                if filteredRecords.isEmpty {
                    emptyListPlaceholder
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredRecords, id: \.objectID) { rec in
                                DQARowView(record: rec, isSelected: selectedID == rec.objectID)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedID = rec.objectID }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            .background(Color(nsColor: .controlBackgroundColor))

            // ── Right: detail pane ────────────────────────────────────────────
            Group {
                if let rec = selectedRecord {
                    DQADetailView(record: rec)
                        .id(rec.objectID)          // reset state on record change
                } else {
                    DQAEmptyDetailView()
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSetupSheet) {
            DQASetupSheet { newID in
                selectedID = newID
            }
            .environment(\.managedObjectContext, ctx)
        }
        .focusEffectDisabled()
    }

    // MARK: Sub-views

    private var listHeader: some View {
        HStack {
            Text("Difficult Questions Archive")
                .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { showSetupSheet = true }
            } label: {
                Label("New DQA", systemImage: "plus")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .foregroundStyle(Color.accentColor)
            .focusEffectDisabled()
            .help("Start a new Difficult Questions Archive entry")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // MARK: Search panel (triple-mode)

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Barcode — full width (scanner input)
            HStack(spacing: 6) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                TextField("Barcode / scanner input…", text: $barcodeSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        if let first = barcodeSuggestions.first(where: {
                            $0.localizedCaseInsensitiveContains(barcodeSearch)
                        }) { barcodeSearch = first }
                    }
                if !barcodeSearch.isEmpty {
                    Button { barcodeSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Row 2: Subject + Series
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                TextField("Subject name…", text: $subjectSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        if let first = subjectSuggestions.first(where: {
                            $0.localizedCaseInsensitiveContains(subjectSearch)
                        }) { subjectSearch = first }
                    }
                TextField("Series / year…", text: $seriesSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        if let first = seriesSuggestions.first(where: {
                            $0.localizedCaseInsensitiveContains(seriesSearch)
                        }) { seriesSearch = first }
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyListPlaceholder: some View {
        let isFiltering = !subjectSearch.isEmpty || !seriesSearch.isEmpty || !barcodeSearch.isEmpty
        return VStack(spacing: 12) {
            Image(systemName: "archivebox").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(isFiltering ? "No matches" : "No DQA entries yet")
                .font(.callout).foregroundStyle(.secondary)
            if !isFiltering {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { showSetupSheet = true }
                } label: {
                    Text("Start a new DQA")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .foregroundStyle(Color.accentColor)
                .focusEffectDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DQARowView

private struct DQARowView: View {
    let record: DifficultQuestionsArchiveMO
    let isSelected: Bool

    private var statusColor: Color {
        if record.isOutdated { return .gray }
        if record.isComplete { return .green }
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let d = record.committedDate, d < todayStart { return .red }
        return .orange
    }
    private var statusLabel: String {
        if record.isOutdated { return "Outdated" }
        if record.isComplete { return "Complete" }
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let d = record.committedDate, d < todayStart { return "Overdue" }
        return "Active"
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(statusColor).frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.subject ?? "—").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text("D\(record.dqaAttemptNumber)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(record.examSeries.map { SeriesNormalizationEngine.displayName(from: $0) } ?? "—")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusLabel).font(.system(size: 10)).foregroundStyle(statusColor)
                    if let d = record.committedDate, !record.isComplete, !record.isOutdated {
                        Spacer()
                        Text(DateFormatter.dqaGregorianFormat("dd MMM yyyy").string(from: d))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - DQADetailView

struct DQADetailView: View {
    @ObservedObject var record: DifficultQuestionsArchiveMO
    @Environment(\.managedObjectContext) private var ctx

    // Part 3 — calendar cascade
    @State private var pendingCascadeDelta:   TimeInterval? = nil
    @State private var pendingCascadeOldDate: Date?         = nil
    @State private var showCascadeAlert       = false

    // Part 5 — drop scan
    @State private var isDropTargeted    = false
    @State private var dropError: String? = nil
    @State private var showRepeatAlert   = false
    @State private var showRepeatSetup   = false

    // LAN print routing feedback
    @State private var routingStatus: String = ""

    // Double-sided print toggle (persisted across sessions)
    @AppStorage("dqaDoubleSided") private var isDoubleSidedSelected: Bool = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "en_GB")
        f.calendar  = Calendar(identifier: .gregorian)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                statusCard
                printActionsCard       // Part 4
                calendarCard           // Part 3
                if !record.isComplete && !record.isOutdated { dropScanCard }   // Part 5
                if !record.decodedSourceQuestions.isEmpty   { questionsCard }
                filesCard              // Part 6 file ops
                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // Part 5 — whole pane is a drop target when record is active
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !record.isComplete, !record.isOutdated else { return false }
            guard let p = providers.first else { return false }
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { processDropScan(url: url) }
            }
            return true
        }
        .overlay(alignment: .bottom) {
            if isDropTargeted { dropTargetBanner }
        }
        // Part 5 — repeat alert
        .alert("Repeat this DQA?", isPresented: $showRepeatAlert) {
            Button("Yes — Schedule a Repeat") { showRepeatSetup = true }
            Button("No — Cycle Complete", role: .cancel) { }
        } message: {
            Text("Has the student mastered these questions, or do they need another practice cycle?")
        }
        .sheet(isPresented: $showRepeatSetup) {
            DQASetupSheet { _ in }
                .environment(\.managedObjectContext, ctx)
        }
        // Part 3 — cascade alert
        .alert("Apply Cascade Shift?", isPresented: $showCascadeAlert) {
            Button("Shift All Future DQAs") { applyCascade() }
            Button("This Record Only", role: .cancel) {
                PersistenceController.shared.save()
                clearCascade()
            }
        } message: {
            let days = Int(round((pendingCascadeDelta ?? 0) / 86400))
            Text("Shift all DQAs scheduled after this one by \(days > 0 ? "+" : "")\(days) day\(abs(days) == 1 ? "" : "s")?")
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        detailCard(title: "Archive Entry") {
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Subject",           value: record.subject ?? "—")
                DetailRow(label: "Series",            value: record.examSeries.map { SeriesNormalizationEngine.displayName(from: $0) } ?? "—")
                DetailRow(label: "Paper Type",        value: record.paperType?.capitalized ?? "—")
                DetailRow(label: "Original Attempt",  value: "ATT\(record.parentExamAttemptNumber)")
                DetailRow(label: "DQA Attempt",       value: "D\(record.dqaAttemptNumber)")
                Divider()
                DetailRow(label: "Original Barcode",  value: record.originalBarcode ?? "—", monospaced: true)
                DetailRow(label: "DQA Barcode",       value: record.dqaBarcode ?? "—",      monospaced: true)
            }
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        detailCard(title: "Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { statusBadge; Spacer() }
                if let ts = record.createdTimestamp {
                    DetailRow(label: "Created",             value: Self.dateFmt.string(from: ts))
                }
                if let orig = record.originalCompletedTimestamp {
                    DetailRow(label: "Original Completed",  value: Self.dateFmt.string(from: orig))
                }
                if let dqaTS = record.dqaCompletedTimestamp {
                    DetailRow(label: "DQA Completed",       value: Self.dateFmt.string(from: dqaTS))
                }
            }
        }
    }

    // MARK: - Print actions card (Part 4)

    private var printActionsCard: some View {
        detailCard(title: "Print") {
            VStack(alignment: .leading, spacing: 8) {

                // Double-sided toggle — inserts a blank page 2 so exam questions
                // begin on a fresh sheet when the index cover is printed double-sided.
                Button { isDoubleSidedSelected.toggle() } label: {
                    Label("Double-sided (insert blank page 2)",
                          systemImage: isDoubleSidedSelected ? "doc.on.doc.fill" : "doc.on.doc")
                        .font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .foregroundStyle(isDoubleSidedSelected ? Color.accentColor : Color.secondary)
                .focusEffectDisabled()

                HStack(spacing: 10) {
                    printMenu("Print DQA Paper", icon: "doc.text",
                        onLocal: {
                            DQAPrintManager.printDQAPaper(for: record,
                                                          isDoubleSided: isDoubleSidedSelected)
                        },
                        onWindowsExpress: {
                            try await DQAPrintManager.routeDQAPaperToWindows(
                                for: record, isDoubleSided: isDoubleSidedSelected,
                                mode: .expressDefault)
                        },
                        onWindowsManual: {
                            try await DQAPrintManager.routeDQAPaperToWindows(
                                for: record, isDoubleSided: isDoubleSidedSelected,
                                mode: .manualWithVNC)
                        })

                    printMenu("Mark Scheme", icon: "doc.text.fill",
                        onLocal: {
                            if let p = record.compiledMarkSchemePDFPath {
                                DQAPrintManager.printPDF(at: p)
                            }
                        },
                        onWindowsExpress: {
                            if let p = record.compiledMarkSchemePDFPath {
                                try await DQAPrintManager.routeFileToWindows(
                                    at: p, filename: "MarkScheme.pdf", mode: .expressDefault)
                            }
                        },
                        onWindowsManual: {
                            if let p = record.compiledMarkSchemePDFPath {
                                try await DQAPrintManager.routeFileToWindows(
                                    at: p, filename: "MarkScheme.pdf", mode: .manualWithVNC)
                            }
                        })
                    .disabled(record.compiledMarkSchemePDFPath == nil)

                    printMenu("Index Sheet", icon: "barcode",
                        onLocal: { DQAPrintManager.printIndexSheet(for: record) },
                        onWindowsExpress: {
                            try await DQAPrintManager.routeIndexSheetToWindows(
                                for: record, mode: .expressDefault)
                        },
                        onWindowsManual: {
                            try await DQAPrintManager.routeIndexSheetToWindows(
                                for: record, mode: .manualWithVNC)
                        })
                }

                if !routingStatus.isEmpty {
                    Text(routingStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(routingStatus.hasPrefix("✓") ? Color.green : Color.red)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Drop-down menu button with three print destinations.
    /// Success/failure feedback is written to `routingStatus`.
    private func printMenu(
        _ label: String,
        icon: String,
        onLocal: @escaping () -> Void,
        onWindowsExpress: @escaping () async throws -> Void,
        onWindowsManual:  @escaping () async throws -> Void
    ) -> some View {
        Menu {
            // ── Local ────────────────────────────────────────────────────────
            Button { onLocal() } label: {
                Label("Native Mac Spool", systemImage: "printer")
            }
            Divider()
            // ── Windows: Express (no VNC) ────────────────────────────────────
            Button {
                routingStatus = ""
                Task { @MainActor in
                    do {
                        try await onWindowsExpress()
                        routingStatus = "✓ Sent — Express Windows Print"
                    } catch {
                        routingStatus = "✗ \(error.localizedDescription)"
                    }
                }
            } label: {
                Label("Express Windows Print (Default Settings)", systemImage: "network")
            }
            // ── Windows: Manual + VNC ────────────────────────────────────────
            Button {
                routingStatus = ""
                Task { @MainActor in
                    do {
                        try await onWindowsManual()
                        routingStatus = "✓ Sent — Screen Sharing opened"
                    } catch {
                        routingStatus = "✗ \(error.localizedDescription)"
                    }
                }
            } label: {
                Label("Manual Windows Config (VNC Screen Mirror)", systemImage: "display")
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label).font(.system(size: 10)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .menuStyle(.borderlessButton)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Calendar card (Part 3)

    private var calendarCard: some View {
        detailCard(title: "Schedule") {
            DQACalendarSection(
                record: record,
                pendingCascadeDelta:   $pendingCascadeDelta,
                pendingCascadeOldDate: $pendingCascadeOldDate,
                showCascadeAlert:      $showCascadeAlert
            )
        }
    }

    // MARK: - Drop scan card (Part 5)

    private var dropScanCard: some View {
        detailCard(title: "Submit Completed DQA Scan") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Drop the scanned completed DQA PDF, or choose a file. The filename should contain the DQA barcode \(record.dqaBarcode ?? "").")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("Drop scanned PDF anywhere in this detail pane")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { pickScanFile() }
                    } label: {
                        Text("Choose File…")
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .glassEffect(in: Capsule())
                    .focusEffectDisabled()
                }
                .padding(10)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 8))

                if let err = dropError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    private var dropTargetBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
            Text("Drop completed DQA scan here")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 16)
    }

    // MARK: - Questions card

    private var questionsCard: some View {
        let qs = record.decodedSourceQuestions
        return detailCard(title: "Selected Questions (\(qs.count))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(qs, id: \.self) { q in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
                        Text(dqaDisplayLabel(q)).font(.system(size: 12))
                    }
                }
            }
        }
    }

    // MARK: - Files card (Part 6 file ops)

    private var filesCard: some View {
        detailCard(title: "Compiled Files") {
            VStack(alignment: .leading, spacing: 10) {
                DQAFilePathRow(
                    label: "Question Paper PDF",
                    path: record.compiledQuestionPDFPath
                ) { path in
                    record.compiledQuestionPDFPath = path
                    PersistenceController.shared.save()
                }
                DQAFilePathRow(
                    label: "Mark Scheme PDF",
                    path: record.compiledMarkSchemePDFPath
                ) { path in
                    record.compiledMarkSchemePDFPath = path
                    PersistenceController.shared.save()
                }
                DQAFilePathRow(
                    label: "Completed DQA Scan",
                    path: record.completedDQAFilePath
                ) { path in
                    record.completedDQAFilePath = path
                    PersistenceController.shared.save()
                }
            }
        }
    }

    // MARK: - Card builder

    @ViewBuilder
    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            if record.isOutdated { return ("Outdated", .gray) }
            if record.isComplete { return ("Complete", .green) }
            let todayStart = Calendar.current.startOfDay(for: Date())
            if let d = record.committedDate, d < todayStart { return ("Overdue", .red) }
            return ("Active", .orange)
        }()
        return Text(label)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    // MARK: - Drop scan logic (Part 5)

    private func pickScanFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Select the scanned completed DQA PDF"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            processDropScan(url: url)
        }
    }

    private func processDropScan(url: URL) {
        dropError = nil
        let dqaBarcode = record.dqaBarcode ?? ""
        let filename   = url.deletingPathExtension().lastPathComponent

        // Accept if filename contains the DQA barcode, or starts with "DQA-"
        guard filename.contains(dqaBarcode) || filename.hasPrefix("DQA-") else {
            dropError = "Filename doesn't match DQA barcode \(dqaBarcode). Expected: \(dqaBarcode).pdf"
            return
        }

        // Copy to DQA directory
        do {
            let dir  = try DQAFileManager.ensureDirectory(for: dqaBarcode)
            let dest = dir.appendingPathComponent("Completed-\(url.lastPathComponent)")
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: url, to: dest)
            }
            record.completedDQAFilePath  = dest.path
            record.dqaCompletedTimestamp = Date()
            PersistenceController.shared.save()
            showRepeatAlert = true
        } catch {
            dropError = "Failed to copy file: \(error.localizedDescription)"
        }
    }

    // MARK: - Cascade logic (Part 3)

    private func applyCascade() {
        guard let delta = pendingCascadeDelta,
              let oldDate = pendingCascadeOldDate else {
            PersistenceController.shared.save()
            clearCascade()
            return
        }
        let req = DifficultQuestionsArchiveMO.fetchRequest()
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "committedDate > %@", oldDate as NSDate),
            NSPredicate(format: "isOutdated == NO"),
            NSPredicate(format: "dqaCompletedTimestamp == nil"),
            NSPredicate(format: "SELF != %@", record.objectID)
        ])
        let others = (try? ctx.fetch(req)) ?? []
        for other in others {
            if let d = other.committedDate {
                other.committedDate = d.addingTimeInterval(delta)
            }
        }
        PersistenceController.shared.save()
        clearCascade()
    }

    private func clearCascade() {
        pendingCascadeDelta   = nil
        pendingCascadeOldDate = nil
    }
}

// MARK: - DQACalendarSection (Part 3)

/// Month-grid calendar for scheduling and cascade rescheduling.
private struct DQACalendarSection: View {

    let record: DifficultQuestionsArchiveMO
    @Binding var pendingCascadeDelta:   TimeInterval?
    @Binding var pendingCascadeOldDate: Date?
    @Binding var showCascadeAlert:      Bool

    @Environment(\.managedObjectContext) private var ctx

    // Fetch all active DQAs to show dots for other committed dates
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DifficultQuestionsArchiveMO.committedDate, ascending: true)],
        predicate: NSPredicate(format: "isOutdated == NO AND dqaCompletedTimestamp == nil")
    )
    private var activeDQAs: FetchedResults<DifficultQuestionsArchiveMO>

    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    private let cal = Calendar.current
    private let weekHeaders = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button(action: prevMonth) { Image(systemName: "chevron.left").font(.caption) }.buttonStyle(.plain)
                Spacer()
                Text(monthTitle).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: nextMonth) { Image(systemName: "chevron.right").font(.caption) }.buttonStyle(.plain)
            }

            // Day-of-week headers
            HStack(spacing: 0) {
                ForEach(weekHeaders, id: \.self) { h in
                    Text(h).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Date grid
            let cells = buildCells()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(cells.indices, id: \.self) { i in
                    if let date = cells[i] {
                        calCell(for: date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }

            if let d = record.committedDate {
                Text("Committed: \(DateFormatter.dqaGregorianFormat("dd MMM yyyy").string(from: d))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear { syncMonthDisplay() }
        .onChange(of: record.committedDate) { _ in syncMonthDisplay() }
    }

    // MARK: Helpers

    private var monthTitle: String {
        DateFormatter.dqaGregorianFormat("MMMM yyyy").string(from: displayedMonth)
    }
    private func prevMonth() {
        displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }
    private func nextMonth() {
        displayedMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }
    private func syncMonthDisplay() {
        if let d = record.committedDate {
            let c = cal.dateComponents([.year, .month], from: d)
            displayedMonth = cal.date(from: c) ?? displayedMonth
        }
    }

    private func buildCells() -> [Date?] {
        guard let daysRange = cal.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWD = cal.component(.weekday, from: displayedMonth) - 1  // 0-indexed Sun=0
        var cells: [Date?] = Array(repeating: nil, count: firstWD)
        for day in daysRange {
            var c = cal.dateComponents([.year, .month], from: displayedMonth); c.day = day
            cells.append(cal.date(from: c))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    @ViewBuilder
    private func calCell(for date: Date) -> some View {
        let day        = cal.component(.day, from: date)
        let isToday    = cal.isDateInToday(date)
        let isSelected = record.committedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let hasDot     = activeDQAs.contains {
            $0.objectID != record.objectID &&
            ($0.committedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false)
        }
        let isPast     = date < cal.startOfDay(for: Date())

        Button(action: { selectDate(date) }) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.green : isToday ? Color.accentColor.opacity(0.2) : Color.clear)
                        .frame(width: 24, height: 24)
                    Text("\(day)")
                        .font(.system(size: 11, weight: isSelected || isToday ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected ? .white :
                            isPast     ? Color.secondary :
                                         Color.primary
                        )
                }
                Circle()
                    .fill(hasDot ? Color.orange : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(height: 28)
        }
        .buttonStyle(.plain)
    }

    private func selectDate(_ date: Date) {
        let newDate = cal.startOfDay(for: date)
        let oldDate = record.committedDate
        record.committedDate = newDate

        if let old = oldDate {
            let delta = newDate.timeIntervalSince(old)
            if abs(delta) >= 86400 {    // at least 1 day to trigger cascade prompt
                pendingCascadeDelta   = delta
                pendingCascadeOldDate = old
                showCascadeAlert      = true
                return  // save deferred to cascade handler
            }
        }
        PersistenceController.shared.save()
    }
}

// MARK: - DQAEmptyDetailView

private struct DQAEmptyDetailView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox.fill").font(.system(size: 48)).foregroundStyle(.tertiary)
            Text("Select a DQA entry").font(.title3).foregroundStyle(.secondary)
            Text("Choose a record from the list on the left to view its details.")
                .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - DetailRow (shared)

struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .foregroundStyle(.primary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - DQAFilePathRow (Part 6 file ops)

/// Displays a path with Open-in-Preview, Reveal-in-Finder, and Delete actions.
struct DQAFilePathRow: View {
    let label: String
    let path: String?
    /// Called with the updated path (nil when file is deleted).
    var onPathChange: ((String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let p = path {
                    Image(systemName: "doc.fill").foregroundStyle(Color.accentColor).font(.system(size: 11))
                    Text(URL(fileURLWithPath: p).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Color.accentColor)
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
                    }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Color.accentColor)
                    Button("Delete") { deleteFile(at: p) }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.red)
                } else {
                    Image(systemName: "doc.badge.ellipsis").foregroundStyle(.tertiary).font(.system(size: 11))
                    Text("Not yet generated").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func deleteFile(at path: String) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        onPathChange?(nil)
    }
}

// MARK: - DQASetupPlaceholder removed; DQASetupSheet is in DQASetupSheet.swift
