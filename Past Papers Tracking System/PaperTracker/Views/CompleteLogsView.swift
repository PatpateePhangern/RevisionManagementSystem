import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Displays all attempts with multi-selection, bulk deletion, and native PDF preview.
///
/// Feature set:
///   - Triple-mode search bar (barcode scanner stream, subject filter, series filter)
///   - Multi-selection via native SwiftUI Set binding (Cmd+Click, Shift+Click, Cmd+A)
///   - Action bar: "Delete Selected" (⌘⌫) — also purges the archived PDF from disk
///   - Expanded three-line row: subject name, barcode ID, series display name
///   - Drag-and-drop PDF check-in with Vision 3-pass scanning + manual fallback
///   - Validation sheet to confirm/override inferred paper type
///   - Grade capture sheet for Timed & Graded papers
///   - Five-vector detail header: attempt #, series, subject, barcode, 4-state status
///   - Dynamic font scaling — detail pane typography proportional to window height
///   - Historical performance panel in detail pane
///   - "Open in Preview [⌘P]" routes directly to macOS Preview via NSWorkspace
struct CompleteLogsView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\.completedTimestamp, order: .forward),
            SortDescriptor(\.printTimestamp,     order: .reverse)
        ],
        animation: .default
    ) private var attempts: FetchedResults<AttemptMO>

    // ── Multi-selection ──────────────────────────────────────────────────────
    @State private var selectedAttemptIDs: Set<NSManagedObjectID> = []
    @Namespace private var selectionNamespace

    private var selectedAttempt: AttemptMO? {
        guard let id = selectedAttemptIDs.first else { return nil }
        return attempts.first { $0.objectID == id }
    }

    // ── Triple-mode search state ─────────────────────────────────────────────
    @State private var barcodeSearch: String = ""
    @State private var subjectSearch: String = ""
    @State private var seriesSearch:  String = ""

    // ── Chip filter state ─────────────────────────────────────────────────────
    @State private var filterSubject:  String = "All"
    @State private var filterPaper:    String = "All"
    @State private var filterVariant:  String = "All"

    // MARK: - Filter option lists

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

    private var hasActiveFilter: Bool {
        filterSubject != "All" || filterPaper != "All" || filterVariant != "All"
    }

    private var filteredAttempts: [AttemptMO] {
        attempts.filter { a in
            let barcodeOK = barcodeSearch.isEmpty ||
                (a.barcodeValue ?? "").localizedCaseInsensitiveContains(barcodeSearch)

            let subjectOK = subjectSearch.isEmpty ||
                (a.paper?.subject?.name ?? "").localizedCaseInsensitiveContains(subjectSearch)

            let seriesOK: Bool = {
                guard !seriesSearch.isEmpty else { return true }
                let norm    = a.paper?.normalizedSeries ?? ""
                let display = SeriesNormalizationEngine.displayName(from: norm)
                return norm.localizedCaseInsensitiveContains(seriesSearch)
                    || display.localizedCaseInsensitiveContains(seriesSearch)
            }()

            if !(barcodeOK && subjectOK && seriesOK) { return false }

            // Chip filters
            if filterSubject != "All", (a.paper?.subject?.name ?? "") != filterSubject { return false }

            if filterPaper != "All" {
                let pLabel = a.paper?.normalizedSeries.flatMap { SeriesFilterHelper.paperLabel(from: $0) }
                if pLabel != filterPaper { return false }
            }

            if filterVariant != "All" {
                let vLabel = a.paper?.normalizedSeries.flatMap { SeriesFilterHelper.variantLabel(from: $0) }
                if vLabel != filterVariant { return false }
            }

            return true
        }
    }

    // ── Drag-drop / scan ─────────────────────────────────────────────────────
    @State private var isDropTargeted   = false
    @State private var isProcessingScan = false   // true while VisionBarcodeScanner is running
    @State private var scanTask: Task<Void, Never>?
    // Batch progress counters (0/0 when no batch is active).
    @State private var batchCurrent: Int = 0
    @State private var batchTotal:   Int = 0

    // ── Scan validation pipeline ─────────────────────────────────────────────
    @State private var pendingScanResult:  ScanResult?   = nil
    @State private var pendingDropURL:     URL?          = nil
    @State private var showValidation:     Bool          = false

    // ── Manual entry fallback ────────────────────────────────────────────────
    @State private var showManualEntry = false

    // ── Grade capture ────────────────────────────────────────────────────────
    @State private var showGradeCapture: Bool = false

    // ── Detail editor ────────────────────────────────────────────────────────
    @State private var reviewText:       String = ""
    @State private var notesText:        String = ""
    @State private var durationEdit:     String = ""
    /// Per-question marks for the selected ETS attempt, keyed by question label.
    @State private var questionMarks:    [String: Double] = [:]
    /// Date/time used when marking an attempt as complete (replaces system clock).
    @State private var completionDateTime: Date = Date()

    // ── ETS Session launcher ─────────────────────────────────────────────────
    @State private var showETSSession: Bool = false

    // ── LAN print routing ────────────────────────────────────────────────────
    @AppStorage("lanPrintWindowsIP") private var windowsIP: String = ""
    @State private var routingStatus: String = ""

    // ── Dynamic font scaling ─────────────────────────────────────────────────
    /// Measured height of the detail pane; updated whenever the pane resizes.
    /// Reference height 700 pt → scale 1.0; clamped to [0.80, 1.40].
    @State private var detailPaneHeight: CGFloat = 700

    private var detailFontScale: CGFloat {
        min(max(detailPaneHeight / 700.0, 0.80), 1.40)
    }

    /// Returns `base` scaled to the current detail-pane height, rounded to
    /// the nearest 0.5 pt so text stays on clean pixel boundaries.
    private func df(_ base: CGFloat) -> CGFloat {
        (base * detailFontScale * 2).rounded() / 2
    }

    // ── Detail window (double-click) ─────────────────────────────────────────
    @Environment(\.openWindow) private var openWindow

    // ── PDF archive root (set in PaperTrackerSettingsView) ───────────────────
    @AppStorage("customPDFStoragePath") private var customPDFStoragePath: String = ""

    /// Effective archive root for scanned PDFs.
    /// Uses the user-configured path when set; otherwise falls back to
    /// ~/Library/Application Support/PaperTracker/PDFs so files are always kept.
    private var effectivePDFArchiveRoot: URL? {
        if !customPDFStoragePath.isEmpty {
            return URL(filePath: customPDFStoragePath)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(components: "PaperTracker", "PDFs")
    }

    // ── Shared timestamp formatter ───────────────────────────────────────────
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Body

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 340, idealWidth: 480, maxWidth: 540)
            detailPane
                .frame(minWidth: 340)
        }
        // ── Manual barcode entry ─────────────────────────────────────────────
        .sheet(isPresented: $showManualEntry) {
            ManualBarcodeEntrySheet(isPresented: $showManualEntry) { value in
                // No PDF image available — create a minimal ScanResult for validation.
                let result = ScanResult(
                    barcodeValue:        value,
                    checkboxRegionImage: nil,
                    inferredPaperType:   nil
                )
                pendingScanResult = result
                showValidation    = true
            }
        }
        // ── Validation sheet (paper type confirm/override) ───────────────────
        .sheet(isPresented: $showValidation) {
            if let result = pendingScanResult {
                ValidationPaneView(
                    scanResult:  result,
                    isPresented: $showValidation
                ) { confirmedType in
                    let barcode      = result.barcodeValue
                    let batchBarcode = result.batchBarcodeValue
                    let dropURL = pendingDropURL
                    let qdData  = result.difficultQuestionsImageData
                    let anData  = result.additionalNotesImageData
                    pendingScanResult = nil
                    pendingDropURL    = nil
                    processBarcode(
                        barcode,
                        paperType: confirmedType,
                        sourceURL: dropURL,
                        difficultQuestionsData: qdData,
                        additionalNotesData:    anData,
                        batchBarcodeValue:      batchBarcode
                    )
                }
            }
        }
        // Ensure residual scan state is cleared whenever the sheet closes
        // (covers the Cancel / Escape path as well as the Proceed path).
        .onChange(of: showValidation) { _, isShowing in
            if !isShowing {
                pendingScanResult = nil
                pendingDropURL    = nil
            }
        }
        // ── Grade capture sheet ──────────────────────────────────────────────
        .sheet(isPresented: $showGradeCapture) {
            if let attempt = selectedAttempt {
                GradeThresholdSheet(attempt: attempt, isPresented: $showGradeCapture)
                    .environment(\.managedObjectContext, ctx)
            }
        }
        // ── ETS Session ──────────────────────────────────────────────────────
        .sheet(isPresented: $showETSSession) {
            if let attempt = selectedAttempt, let paper = attempt.paper {
                ETSSessionView(paper: paper, attempt: attempt)
                    .environment(\.managedObjectContext, ctx)
                    .environmentObject(AppSettings.shared)
            }
        }
        // ── Navigate to attempt from Checklist ───────────────────────────────
        .onReceive(
            NotificationCenter.default.publisher(for: .selectAttemptInCompleteLogs)
        ) { note in
            if let objectID = note.object as? NSManagedObjectID {
                selectedAttemptIDs = [objectID]
                syncEditorFromSelected()
            }
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            dropZoneBanner
            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    ForEach(filteredAttempts, id: \.objectID) { attempt in
                        attemptSelectionRow(attempt)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) { openSelectedFile(); return .handled }
            .onKeyPress(.space)  { openSelectedFile(); return .handled }
            .onKeyPress(phases: .down) { press in
                guard press.key == "a", press.modifiers.contains(.command) else { return .ignored }
                selectedAttemptIDs = Set(filteredAttempts.map(\.objectID))
                return .handled
            }

            Divider()
            actionBar
        }
        .onChange(of: selectedAttemptIDs) { _, _ in syncEditorFromSelected() }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                deleteSelectedAttempts()
            } label: {
                let n = selectedAttemptIDs.count
                Label(n == 1 ? "Delete 1 Attempt" : "Delete \(n) Attempts",
                      systemImage: "trash")
                    .font(.system(size: 11))
            }
            .disabled(selectedAttemptIDs.isEmpty)
            .keyboardShortcut(.delete, modifiers: .command)

            Spacer()

            if selectedAttemptIDs.isEmpty {
                Text("\(filteredAttempts.count) record\(filteredAttempts.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            } else {
                Text("\(selectedAttemptIDs.count) of \(filteredAttempts.count) selected")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Triple-mode search bar

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                TextField("Barcode / scanner input…", text: $barcodeSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { selectMatchingBarcode() }
                if !barcodeSearch.isEmpty {
                    Button { barcodeSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                TextField("Subject name…", text: $subjectSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        if let first = filteredAttempts.first {
                            selectedAttemptIDs = [first.objectID]
                            syncEditorFromSelected()
                        }
                    }
                TextField("Series / year…", text: $seriesSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        if let first = filteredAttempts.first {
                            selectedAttemptIDs = [first.objectID]
                            syncEditorFromSelected()
                        }
                    }
            }

            // ── Chip filters ─────────────────────────────────────────────────
            logsFilterBar
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Chip filter bar

    private var logsFilterBar: some View {
        HStack(spacing: 6) {
            logsFilterChip(label: "Subject", value: filterSubject, options: allSubjectNames) { v in
                withAnimation(.smooth(duration: 0.18)) { filterSubject = v }
            }

            if allPaperNumbers.count > 1 {
                logsFilterChip(label: "Paper", value: filterPaper, options: allPaperNumbers) { v in
                    withAnimation(.smooth(duration: 0.18)) { filterPaper = v }
                }
            }

            if allVariantNumbers.count > 1 {
                logsFilterChip(label: "Variant", value: filterVariant, options: allVariantNumbers) { v in
                    withAnimation(.smooth(duration: 0.18)) { filterVariant = v }
                }
            }

            if hasActiveFilter {
                Button {
                    withAnimation(.smooth(duration: 0.18)) {
                        filterSubject = "All"; filterPaper = "All"; filterVariant = "All"
                    }
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            Spacer()
        }
        .animation(.smooth(duration: 0.2), value: hasActiveFilter)
    }

    @ViewBuilder
    private func logsFilterChip(label: String, value: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    onChange(opt)
                } label: {
                    HStack {
                        Text(opt)
                        if opt == value { Spacer(); Image(systemName: "checkmark") }
                    }
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(value != "All"
                          ? Color.accentColor.opacity(0.12)
                          : Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusEffectDisabled()
    }

    // MARK: - Drop zone banner

    private var dropZoneBanner: some View {
        ZStack {
            Rectangle()
                .fill(isDropTargeted || isProcessingScan
                      ? Color(nsColor: .selectedControlColor).opacity(0.18)
                      : Color(nsColor: .controlBackgroundColor))

            if isProcessingScan {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                    Group {
                        if batchTotal > 1 {
                            Text("Scanning \(batchCurrent) of \(batchTotal)…")
                        } else {
                            Text("Scanning barcode…")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            } else {
                Text(isDropTargeted
                     ? "Release to scan"
                     : "Drop scanned PDF here to check in — drop multiple files for batch import")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .frame(height: 40)
        .onDrop(of: [UTType.pdf], isTargeted: $isDropTargeted) { providers in
            guard !isProcessingScan, !providers.isEmpty else { return false }

            if providers.count == 1 {
                // Single file: existing validation-sheet flow.
                _ = providers[0].loadFileRepresentation(for: .pdf) { url, _, _ in
                    guard let url else { return }
                    let tmp = FileManager.default.temporaryDirectory
                        .appending(component: "drop_\(UUID().uuidString).pdf")
                    try? FileManager.default.copyItem(at: url, to: tmp)
                    Task { @MainActor in self.startScan(for: tmp) }
                }
            } else {
                // Multiple files: sequential batch pipeline without per-file
                // validation sheets — inferred paper type is applied directly.
                Task { await self.startBatchScan(providers: providers) }
            }
            return true
        }
    }

    // MARK: - Attempt row

    private func attemptRow(_ a: AttemptMO) -> some View {
        AttemptRowContent(attempt: a)
    }

    /// Custom selection row — light-blue pill + matchedGeometryEffect slide,
    /// identical to the Papers Mapping list.
    private func attemptSelectionRow(_ a: AttemptMO) -> some View {
        let isSelected = selectedAttemptIDs.contains(a.objectID)
        let isSingle   = selectedAttemptIDs.count == 1

        return Button {
            let cmdHeld = NSEvent.modifierFlags.contains(.command)
            if cmdHeld {
                if isSelected { selectedAttemptIDs.remove(a.objectID) }
                else          { selectedAttemptIDs.insert(a.objectID) }
            } else {
                selectedAttemptIDs = [a.objectID]
            }
        } label: {
            AttemptRowContent(attempt: a)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                if isSingle {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.13))
                        .matchedGeometryEffect(id: "attemptSelPill", in: selectionNamespace)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.10))
                }
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.14), value: selectedAttemptIDs)
        // Double-click: open PDF / detail window
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedAttemptIDs = [a.objectID]
                if let path = a.scannedFilePath {
                    PDFFloatingWindowController.open(
                        url:   URL(filePath: path),
                        title: a.barcodeValue ?? "Scanned PDF"
                    )
                } else if let id = a.id {
                    openWindow(id: "attempt-detail", value: id)
                }
            }
        )
    }

    /// Computes the max marks for an attempt from question structures or thresholds.
    static func maxMarks(for attempt: AttemptMO) -> Int {
        let qs = (attempt.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
        if !qs.isEmpty { return qs.reduce(0) { $0 + Int($1.maxMarks) } }
        if let t = (attempt.paper?.gradeThresholds as? Set<GradeThresholdTableMO>)?.first {
            return Int(t.maxPossibleMarks)
        }
        return 0
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let attempt = selectedAttempt {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        detailHeader(attempt)
                        Divider()
                        durationField(for: attempt)
                        if isETSSourced(attempt) {
                            Divider()
                            etsMarksTable(for: attempt)
                        }
                        Divider()
                        reviewField
                        Divider()
                        notesField
                        if attempt.paperType == "timed" {
                            Divider()
                            historicalPanel(for: attempt)
                        }
                        if !attempt.isComplete {
                            Divider()
                            completionSection(for: attempt)
                        }
                        Divider()
                        actionRow(attempt)
                    }
                    // +40% wider side padding for structural breathing room (20 → 28).
                    .padding(.horizontal, 28)
                }
                .padding(.vertical, 20)
            }
            // ── Dynamic font scaling measurement ─────────────────────────────
            // A zero-size background GeometryReader reads the pane height without
            // affecting layout; the captured value drives df() for all body text.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear      { detailPaneHeight = geo.size.height }
                        .onChange(of: geo.size) { _, s in detailPaneHeight = s.height }
                }
            )
        } else {
            VStack(spacing: 6) {
                Spacer()
                if selectedAttemptIDs.count > 1 {
                    Text("\(selectedAttemptIDs.count) attempts selected")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text("Use \u{2318}\u{232B} to delete selection")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                } else {
                    Text("Select an attempt to view details")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Returns (label, color) for the four-state workflow status.
    private func statusState(for a: AttemptMO) -> (label: String, color: Color) {
        Self.statusState(for: a)
    }

    /// Shared status logic used by both the detail pane and `AttemptStatusBadge`.
    static func statusState(for a: AttemptMO) -> (label: String, color: Color) {
        if let manual = a.manualStatus, !manual.isEmpty {
            return (manual, AttemptStatusBadge.color(for: manual))
        }
        guard a.isComplete else {
            return ("Pending", Color(nsColor: .systemOrange))
        }
        let hasReview = !(a.reviewQuestions ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if hasReview {
            return ("Ask Teacher", Color(nsColor: .systemBlue))
        }
        if a.paperType == "timed", (a.rawGrade == nil || (a.rawGrade ?? "").isEmpty) {
            return ("Pending Analysis", Color(nsColor: .secondaryLabelColor))
        }
        return ("Done", Color(nsColor: .systemGreen))
    }

    private func detailHeader(_ a: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Subject & type badge ────────────────────────────────────────
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(a.paper?.subject?.name ?? "—")
                    .font(.system(size: df(15), weight: .semibold))

                if let pt = a.paperType {
                    Text(pt == "timed" ? "Timed & Graded" : "Practice")
                        .font(.system(size: df(9), weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(pt == "timed"
                                    ? Color(nsColor: .systemBlue).opacity(0.12)
                                    : Color(nsColor: .systemGray).opacity(0.15))
                        .foregroundStyle(pt == "timed"
                                         ? Color(nsColor: .systemBlue)
                                         : Color(nsColor: .secondaryLabelColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Divider()

            // ── Five data vectors ───────────────────────────────────────────
            // 1. Attempt Number (bold, prominent)
            headerRow(label: "Attempt") {
                Text("ATT \(a.attemptNumber)")
                    .font(.system(size: df(13), weight: .bold, design: .monospaced))
            }

            // 2. Exam Series
            if let norm = a.paper?.normalizedSeries {
                headerRow(label: "Exam Series") {
                    Text(SeriesNormalizationEngine.displayName(from: norm))
                        .font(.system(size: df(12)))
                }
            }

            // 3. Subject (full identifier)
            headerRow(label: "Subject") {
                Text(a.paper?.subject?.name ?? "—")
                    .font(.system(size: df(12)))
            }

            // 4. Barcode Reference (monospaced)
            headerRow(label: "Barcode") {
                Text(a.barcodeValue ?? "—")
                    .font(.system(size: df(12), design: .monospaced))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            // 5. Status Layout Row — interactive override picker
            headerRow(label: "Status") {
                let statusOptions = ["Pending", "Done", "Ask Teacher", "Pending Analysis"]
                let effectiveStatus = statusState(for: a).label
                let statusColor     = statusState(for: a).color
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .animation(.smooth(duration: 0.3), value: effectiveStatus)
                    Picker("", selection: Binding(
                        get: { effectiveStatus },
                        set: { newVal in
                            a.manualStatus = newVal
                            PersistenceController.shared.save()
                        }
                    )) {
                        ForEach(statusOptions, id: \.self) { opt in
                            Text(opt).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .controlSize(.small)
                    .animation(.smooth(duration: 0.3), value: effectiveStatus)
                }
            }

            Divider()

            // ── Timestamps ──────────────────────────────────────────────────
            if let ts = a.printTimestamp {
                Text("Printed: \(Self.timestampFormatter.string(from: ts))")
                    .font(.system(size: df(11)))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            if let ts = a.completedTimestamp {
                Text("Completed: \(Self.timestampFormatter.string(from: ts))")
                    .font(.system(size: df(11)))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            // ── Score / grade / duration summary ────────────────────────────
            if a.totalScore > 0 || a.durationInSeconds > 0 {
                HStack(spacing: 12) {
                    if a.totalScore > 0 {
                        Label(String(format: "%.0f", a.totalScore), systemImage: "sum")
                            .font(.system(size: df(11)))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    if let grade = a.rawGrade, !grade.isEmpty {
                        Text("Grade: \(grade)")
                            .font(.system(size: df(11), weight: .semibold))
                    }
                    if a.durationInSeconds > 0 {
                        Label(DurationParser.format(a.durationInSeconds),
                              systemImage: "clock")
                            .font(.system(size: df(11)))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }

    /// Label for a Menu button — leading icon + title + trailing chevron so the
    /// user knows it opens a dropdown.
    private func menuLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.7)
        }
    }

    /// Two-column label/value row used in the detail header metadata grid.
    /// The label column is fixed-width; the value view is caller-supplied.
    private func headerRow<V: View>(label: String, @ViewBuilder valueView: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: df(10), weight: .semibold))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 10)
            valueView()
        }
    }

    private var reviewField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("คำถามที่ต้องดู")
                .font(.system(size: df(11), weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            // ReviewClipView uses @ObservedObject so it re-renders immediately
            // when difficultQuestionsImageData is cleared via the Clear Clip button.
            if let attempt = selectedAttempt {
                ReviewClipView(attempt: attempt)
            }

            TextEditor(text: $reviewText)
                .font(.system(size: 12))
                .frame(minHeight: 60)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Additional Notes")
                .font(.system(size: df(11), weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            // NotesClipView uses @ObservedObject so it re-renders immediately
            // when additionalNotesImageData is cleared via the Clear Clip button.
            if let attempt = selectedAttempt {
                NotesClipView(attempt: attempt)
            }

            TextEditor(text: $notesText)
                .font(.system(size: 12))
                .frame(minHeight: 80)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
    }

    /// Duration field — editable for manual (non-ETS) attempts; locked and
    /// greyed out when the attempt was driven by the Exam Timing System.
    @ViewBuilder
    private func durationField(for attempt: AttemptMO) -> some View {
        let etsSourced = isETSSourced(attempt)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Exam Duration")
                    .font(.system(size: df(11), weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                if etsSourced {
                    Label("Set by ETS", systemImage: "lock.fill")
                        .font(.system(size: df(9)))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            TextField("e.g. 1h 30m", text: $durationEdit)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .disabled(etsSourced)
                .foregroundStyle(etsSourced
                                 ? Color(nsColor: .tertiaryLabelColor)
                                 : Color(nsColor: .labelColor))
        }
    }

    /// Returns `true` when `attempt.eventLogs` is non-empty — indicating the
    /// session was recorded by the Exam Timing System and duration must not be
    /// overwritten manually.
    private func isETSSourced(_ attempt: AttemptMO) -> Bool {
        !((attempt.eventLogs as? Set<ETSEventLogMO>) ?? []).isEmpty
    }

    // MARK: - ETS marks entry table

    /// Editable per-question marks table for ETS-sourced attempts.
    /// Live-updates `attempt.totalScore` as the user types.
    /// Also shows time spent on each question vs the target time.
    @ViewBuilder
    private func etsMarksTable(for attempt: AttemptMO) -> some View {
        // Build QP-only question list, deduplicating by stripped label.
        // Old data (source = nil) may contain both QP and MS entries that are
        // indistinguishable by source alone, so we deduplicate after stripping
        // page-range annotations, keeping the first occurrence (lowest displayOrder).
        let allStructures = (attempt.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
            .filter { ($0.source ?? "questionPaper") == "questionPaper" }
            .sorted { $0.displayOrder < $1.displayOrder }
        var seenLabels = Set<String>()
        let questions = allStructures.filter { q in
            let key = ETSTimerEngine.stripPageRange(q.questionLabel ?? "?")
            return seenLabels.insert(key).inserted
        }

        if !questions.isEmpty {
            let totalMaxMarks  = questions.reduce(0) { $0 + Int($1.maxMarks) }
            let targetPerMark: Double = attempt.durationInSeconds > 0 && totalMaxMarks > 0
                ? Double(attempt.durationInSeconds) / Double(totalMaxMarks) : 0

            // Event logs store either the raw label or stripped label depending on
            // when the session was recorded. Build a lookup that handles both by
            // normalising every stored label the same way we display it.
            let spentSec: [String: Int64] = (attempt.eventLogs as? Set<ETSEventLogMO> ?? [])
                .filter { $0.eventType == "QUESTION_SPENT" }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }
                .reduce(into: [:]) { result, log in
                    let key = ETSTimerEngine.stripPageRange(log.label ?? "?")
                    result[key] = (result[key] ?? 0) + log.durationSeconds
                }

            VStack(alignment: .leading, spacing: 8) {
                // ── Header ────────────────────────────────────────────────
                HStack {
                    Text("Question Marks")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Spacer()
                    let total = questionMarks.values.reduce(0, +)
                    Text(String(format: "Total: %.0f / %d", total, totalMaxMarks))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }

                // ── Column headers ────────────────────────────────────────
                HStack(spacing: 0) {
                    Text("Question")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Earned")
                        .frame(width: 62, alignment: .trailing)
                    Text("Max")
                        .frame(width: 44, alignment: .trailing)
                    Text("Spent")
                        .frame(width: 68, alignment: .trailing)
                    Text("Target")
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                Divider()

                // ── One row per question ──────────────────────────────────
                ForEach(questions, id: \.id) { q in
                    let rawLbl  = q.questionLabel ?? "?"
                    let dispLbl = ETSTimerEngine.stripPageRange(rawLbl) // display without page range
                    let maxM    = q.maxMarks
                    let spent   = spentSec[dispLbl] ?? 0
                    let target  = targetPerMark * Double(maxM)
                    let over    = target > 0 && Double(spent) > target

                    // questionMarks keyed by stripped label for consistent lookup
                    let marksBinding = Binding<Double>(
                        get: { questionMarks[dispLbl] ?? 0 },
                        set: { val in
                            questionMarks[dispLbl] = max(0, min(val, Double(maxM)))
                            attempt.totalScore       = questionMarks.values.reduce(0, +)
                        }
                    )

                    HStack(spacing: 0) {
                        Text(dispLbl)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("0", value: marksBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(width: 58)

                        Text("/ \(maxM)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .frame(width: 48, alignment: .trailing)

                        // Time spent — red if over target
                        Group {
                            if spent > 0 {
                                Text(formatTimeSec(spent))
                                    .foregroundStyle(over ? .red : Color(nsColor: .secondaryLabelColor))
                                    .fontWeight(over ? .semibold : .regular)
                            } else {
                                Text("—")
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 68, alignment: .trailing)

                        // Target time
                        Text(target > 0 ? formatTimeSec(Int64(target)) : "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// Formats an Int64 seconds value as MM:SS (or H:MM:SS if ≥ 1 hour).
    private func formatTimeSec(_ s: Int64) -> String {
        let t = max(s, 0)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }

    // MARK: - Completion date/time section

    /// Replaces the old "Mark Complete" button.
    /// Provides a DatePicker (date) + DatePicker (time) so the user can log a
    /// historic completion timestamp rather than being forced to use the clock.
    private func completionSection(for attempt: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mark as Complete")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    DatePicker("", selection: $completionDateTime,
                               displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time (HH:MM)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    DatePicker("", selection: $completionDateTime,
                               displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                Spacer()
                Button("Set Complete  [⌘K]") {
                    commitEdits()
                    attempt.completedTimestamp = completionDateTime
                    PersistenceController.shared.save()
                }
                .buttonStyle(BlueGlassButtonStyle())
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }

    /// Shows a compact chronological list of all past *timed* attempts for the
    /// same paper (excluding the currently selected attempt).
    @ViewBuilder
    private func historicalPanel(for attempt: AttemptMO) -> some View {
        let paper = attempt.paper
        let past = ((paper?.attempts as? Set<AttemptMO>) ?? [])
            .filter { $0.paperType == "timed" && $0.objectID != attempt.objectID }
            .sorted { $0.attemptNumber < $1.attemptNumber }

        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Past Performances — same paper")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                ForEach(past, id: \.objectID) { a in
                    HStack(spacing: 8) {
                        Text("ATT \(a.attemptNumber)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 46, alignment: .leading)

                        if a.totalScore > 0 {
                            Text(String(format: "%.0f", a.totalScore))
                                .font(.system(size: 10, weight: .medium))
                        }

                        if let g = a.rawGrade, !g.isEmpty {
                            Text(g)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color(nsColor: .separatorColor).opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        Spacer()

                        if a.durationInSeconds > 0 {
                            Text(DurationParser.format(a.durationInSeconds))
                                .font(.system(size: 10))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }

                        if let ts = a.completedTimestamp {
                            Text(Self.timestampFormatter.string(from: ts))
                                .font(.system(size: 9))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func actionRow(_ a: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // ── Primary actions ──────────────────────────────────────────
                Button("Save  [⌘S]") { commitEdits() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.regular)

                Button("Print Index  [⌘R]") { reprintIndexSheet(a) }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.regular)
                    .help("Regenerate the A4 tracking sheet and send to print")

                // ── Open PDFs menu ──────────────────────────────────────────
                let hasPDF   = a.scannedFilePath != nil
                let hasQP    = !(a.paper?.questionPaperPDFPath ?? "").isEmpty
                let hasMS    = !(a.paper?.markSchemePDFPath ?? "").isEmpty
                if hasPDF || hasQP || hasMS {
                    Menu {
                        if hasPDF {
                            Button {
                                openSelectedFile()
                            } label: {
                                Label("Scanned PDF  [⌘P]", systemImage: "doc.fill")
                            }
                        }
                        if hasQP, let qPath = a.paper?.questionPaperPDFPath {
                            Button {
                                NSWorkspace.shared.open(URL(filePath: qPath))
                            } label: {
                                Label("Question Paper", systemImage: "doc.text")
                            }
                        }
                        if hasMS, let msPath = a.paper?.markSchemePDFPath {
                            Button {
                                NSWorkspace.shared.open(URL(filePath: msPath))
                            } label: {
                                Label("Mark Scheme", systemImage: "doc.text.fill")
                            }
                        }
                    } label: {
                        menuLabel("Open PDF", icon: "doc")
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.regular)
                }

                // ── Actions menu ────────────────────────────────────────────
                let hasQuestions = !(a.paper?.questionStructures as? Set<QuestionStructureMO> ?? []).isEmpty
                let hasModeActions = a.paperType == "timed" || hasQuestions || true
                if hasModeActions {
                    Menu {
                        if a.paperType == "timed" {
                            Button("Edit Grade") { showGradeCapture = true }
                        }
                        if hasQuestions {
                            Button {
                                EPENMarkingWindowController.open(attempt: a)
                            } label: {
                                Label("Mark (ePEN)", systemImage: "pencil.and.list.clipboard")
                            }
                        }
                        // Always allow ETS — redo clears previous logs first
                        Button {
                            // Clear old event logs so the redo starts fresh
                            if isETSSourced(a) {
                                let old = (a.eventLogs as? Set<ETSEventLogMO>) ?? []
                                old.forEach { ctx.delete($0) }
                                PersistenceController.shared.save()
                            }
                            showETSSession = true
                        } label: {
                            Label(isETSSourced(a) ? "Redo ETS Session" : "Start ETS Session",
                                  systemImage: "timer")
                        }
                    } label: {
                        menuLabel("Actions", icon: "ellipsis.circle")
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.regular)
                }

                // ── Windows PC print menu ───────────────────────────────────
                if !windowsIP.isEmpty {
                    Menu {
                        Button {
                            routingStatus = ""
                            Task { @MainActor in
                                guard let payload = buildPrintPayload(for: a),
                                      let data = PDFDocumentGenerator.buildPDFData(payload: payload) else {
                                    routingStatus = "✗ Could not build PDF"; return
                                }
                                do {
                                    try await LANPrintRouter.sendToWindows(
                                        data: data,
                                        filename: "\(a.barcodeValue ?? "index").pdf",
                                        mode: .expressDefault)
                                    routingStatus = "✓ Sent — Express Print"
                                } catch {
                                    routingStatus = "✗ \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Label("Express Print (Default Settings)", systemImage: "network")
                        }
                        Button {
                            routingStatus = ""
                            Task { @MainActor in
                                guard let payload = buildPrintPayload(for: a),
                                      let data = PDFDocumentGenerator.buildPDFData(payload: payload) else {
                                    routingStatus = "✗ Could not build PDF"; return
                                }
                                do {
                                    try await LANPrintRouter.sendToWindows(
                                        data: data,
                                        filename: "\(a.barcodeValue ?? "index").pdf",
                                        mode: .manualWithVNC)
                                    routingStatus = "✓ Sent — Screen Sharing opened"
                                } catch {
                                    routingStatus = "✗ \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Label("Manual + VNC Screen Mirror", systemImage: "display")
                        }
                    } label: {
                        menuLabel("→ Windows PC", icon: "network")
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.regular)
                    .help("Route the index sheet PDF to the Windows print server")
                }

                Spacer()
            }

            if !routingStatus.isEmpty {
                Text(routingStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(routingStatus.hasPrefix("✓") ? Color.green : Color.red)
            }
        }
    }

    // MARK: - Vision scanning pipeline

    /// Initiates the scan-with-checkbox flow for a dropped PDF.
    /// `isProcessingScan` is set to `true` immediately and is guaranteed to
    /// reset to `false` on every exit path (success, error, or thrown exception)
    /// so the drop-zone overlay never gets stuck in a loading state.
    private func startScan(for url: URL) {
        scanTask?.cancel()
        pendingDropURL   = url
        isProcessingScan = true

        scanTask = Task {
            let scanner = VisionBarcodeScanner()
            do {
                let result = try await scanner.scanWithCheckbox(pdfURL: url)
                await MainActor.run {
                    isProcessingScan  = false   // ← always cleared before presenting sheet
                    pendingScanResult = result
                    showValidation    = true
                }
            } catch {
                // Vision failed — fall back to manual barcode entry.
                await MainActor.run {
                    isProcessingScan = false   // ← always cleared before presenting sheet
                    showManualEntry  = true
                }
            }
        }
    }

    /// Writes the barcode check-in to CoreData, saves section image blobs,
    /// organises the scanned file, then optionally surfaces the grade-capture
    /// sheet for timed papers.
    private func processBarcode(
        _ barcode: String,
        paperType: String?,
        sourceURL: URL?,
        difficultQuestionsData: Data? = nil,
        additionalNotesData: Data? = nil,
        batchBarcodeValue: String? = nil
    ) {
        // Use the compound-predicate lookup (barcodeValue AND paper.normalizedSeries)
        // to avoid mapping mismatches when barcodes share a prefix across papers.
        guard let attempt = PersistenceController.shared.findAttempt(barcodeValue: barcode) else { return }

        attempt.paperType = paperType

        // Persist section image blobs when provided by the scanner.
        if let data = difficultQuestionsData { attempt.difficultQuestionsImageData = data }
        if let data = additionalNotesData    { attempt.additionalNotesImageData    = data }

        if let srcURL = sourceURL,
           let archiveRoot = effectivePDFArchiveRoot,
           let subjectName = attempt.paper?.subject?.name {
            if let dest = try? FileOrganizationPipeline.organize(
                sourceURL: srcURL,
                subjectName: subjectName,
                barcodeValue: barcode,
                archiveRoot: archiveRoot
            ) {
                attempt.scannedFilePath = dest.path(percentEncoded: false)
            }
        }

        // ── Batch item completion ────────────────────────────────────────────
        if let batchBarcode = batchBarcodeValue,
           let batch = PersistenceController.shared.findBatch(barcodeValue: batchBarcode) {
            let matchingItem = (batch.items as? Set<BatchItemMO>)?
                .first { $0.attempt?.objectID == attempt.objectID }
            matchingItem?.markComplete()
        }

        PersistenceController.shared.save()
        selectedAttemptIDs = [attempt.objectID]
        syncEditorFromSelected()

        if paperType == "timed" {
            // Small async hop lets the selection animation settle first.
            Task { @MainActor in showGradeCapture = true }
        }
    }

    // MARK: - Batch scan pipeline

    /// Resolves each provider to a temporary local URL asynchronously.
    /// Returns `nil` for any provider that fails to load or copy.
    private func loadTemporaryURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadFileRepresentation(for: .pdf) { url, _, _ in
                guard let url else { cont.resume(returning: nil); return }
                let tmp = FileManager.default.temporaryDirectory
                    .appending(component: "batch_\(UUID().uuidString).pdf")
                do {
                    try FileManager.default.copyItem(at: url, to: tmp)
                    cont.resume(returning: tmp)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Sequentially scans each provider, auto-applies the inferred paper type,
    /// and processes the result without showing a per-file validation sheet.
    /// Failed or barcode-free files are skipped with a console warning.
    private func startBatchScan(providers: [NSItemProvider]) async {
        isProcessingScan = true
        batchTotal       = providers.count
        batchCurrent     = 0

        // Phase 1 — resolve all providers to local temp files in parallel.
        var urls: [URL] = []
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask { await self.loadTemporaryURL(from: provider) }
            }
            for await result in group {
                if let url = result { urls.append(url) }
            }
        }

        // Phase 2 — scan sequentially to keep CoreData writes serial.
        let scanner = VisionBarcodeScanner()
        for (idx, url) in urls.enumerated() {
            batchCurrent = idx + 1
            do {
                let result = try await scanner.scanWithCheckbox(pdfURL: url)
                processBarcode(
                    result.barcodeValue,
                    paperType:              result.inferredPaperType ?? "practice",
                    sourceURL:              url,
                    difficultQuestionsData: result.difficultQuestionsImageData,
                    additionalNotesData:    result.additionalNotesImageData,
                    batchBarcodeValue:      result.batchBarcodeValue
                )
            } catch {
                print("[BatchScan] Skipped '\(url.lastPathComponent)': \(error.localizedDescription)")
            }
        }

        isProcessingScan = false
        isDropTargeted   = false
        batchTotal       = 0
        batchCurrent     = 0
    }

    // MARK: - Index sheet reprint

    /// Rebuilds the original A4 tracking sheet for `attempt` using
    /// `PDFDocumentGenerator` and routes it to the system print panel.
    private func reprintIndexSheet(_ attempt: AttemptMO) {
        guard let payload = buildPrintPayload(for: attempt) else { return }
        PDFDocumentGenerator.generateAndPrint(payload: payload)
    }

    /// Builds the `PrintPayload` for `attempt`; returns `nil` if required fields are missing.
    private func buildPrintPayload(for attempt: AttemptMO) -> PDFDocumentGenerator.PrintPayload? {
        guard let barcodeValue = attempt.barcodeValue,
              let paper        = attempt.paper,
              let subjectName  = paper.subject?.name else { return nil }
        let normalizedSeries  = paper.normalizedSeries ?? ""
        let seriesDisplayName = SeriesNormalizationEngine.displayName(from: normalizedSeries)
        return PDFDocumentGenerator.PrintPayload(
            subjectName:       subjectName,
            seriesDisplayName: seriesDisplayName,
            normalizedSeries:  normalizedSeries,
            attemptNumber:     attempt.attemptNumber,
            barcodeValue:      barcodeValue,
            printTimestamp:    attempt.printTimestamp ?? Date()
        )
    }

    // MARK: - Search helpers

    private func selectMatchingBarcode() {
        let query = barcodeSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        if let match = filteredAttempts.first(where: {
            ($0.barcodeValue ?? "").caseInsensitiveCompare(query) == .orderedSame
        }) {
            selectedAttemptIDs = [match.objectID]
            syncEditorFromSelected()
        }
    }

    // MARK: - Bulk delete

    private func deleteSelectedAttempts() {
        let toDelete = attempts.filter { selectedAttemptIDs.contains($0.objectID) }
        for attempt in toDelete {
            // Atomic disk purge: remove the archived PDF before dropping the record.
            if let path = attempt.scannedFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            ctx.delete(attempt)
        }
        PersistenceController.shared.save()
        selectedAttemptIDs.removeAll()
        reviewText   = ""
        notesText    = ""
    }

    // MARK: - Editor sync / commit

    private func syncEditorFromSelected() {
        reviewText   = selectedAttempt?.reviewQuestions ?? ""
        notesText    = selectedAttempt?.additionalNotes ?? ""
        let secs     = selectedAttempt?.durationInSeconds ?? 0
        durationEdit = secs > 0 ? DurationParser.format(secs) : ""
        completionDateTime = selectedAttempt?.completedTimestamp ?? Date()

        // Section images are read directly from CoreData binary blobs
        // (difficultQuestionsImageData / additionalNotesImageData) — no async
        // on-demand PDF loading needed.

        // Load per-question marks for ETS-sourced attempts.
        // Keys are always the stripped (no page-range) label so they align with the table.
        if let attempt = selectedAttempt, isETSSourced(attempt) {
            let allQ = (attempt.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
                .filter { ($0.source ?? "questionPaper") == "questionPaper" }
                .sorted { $0.displayOrder < $1.displayOrder }
            var seenQ = Set<String>()
            let questions = allQ.filter { q in
                let key = ETSTimerEngine.stripPageRange(q.questionLabel ?? "?")
                return seenQ.insert(key).inserted
            }
            var marks: [String: Double] = Dictionary(
                uniqueKeysWithValues: questions.compactMap { q in
                    guard let lbl = q.questionLabel else { return nil }
                    return (ETSTimerEngine.stripPageRange(lbl), 0.0)
                }
            )
            // Overwrite with logged values (last QUESTION_SPENT visit per label wins)
            let logs = (attempt.eventLogs as? Set<ETSEventLogMO> ?? [])
                .filter { $0.eventType == "QUESTION_SPENT" }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }
            for log in logs {
                let key = ETSTimerEngine.stripPageRange(log.label ?? "?")
                marks[key] = log.marksEarned
            }
            questionMarks = marks
        } else {
            questionMarks = [:]
        }
    }

    private func commitEdits() {
        guard let attempt = selectedAttempt else { return }
        attempt.reviewQuestions = reviewText
        attempt.additionalNotes = notesText
        if !isETSSourced(attempt) {
            if let parsed = DurationParser.parse(durationEdit) {
                attempt.durationInSeconds = parsed
            }
        }
        // Persist question marks back to the ETSEventLogMO entries.
        if isETSSourced(attempt), !questionMarks.isEmpty {
            let logs = (attempt.eventLogs as? Set<ETSEventLogMO> ?? [])
                .filter { $0.eventType == "QUESTION_SPENT" }
                .sorted { $0.sequenceIndex > $1.sequenceIndex }   // descending → last visit first
            var updated: Set<String> = []
            for log in logs {
                let key = ETSTimerEngine.stripPageRange(log.label ?? "?")
                if !updated.contains(key) {
                    log.marksEarned = questionMarks[key] ?? 0
                    updated.insert(key)
                }
            }
            attempt.totalScore = questionMarks.values.reduce(0, +)
        }
        PersistenceController.shared.save()
    }

    private func markComplete() {
        guard let attempt = selectedAttempt else { return }
        commitEdits()
        attempt.completedTimestamp = Date()
        PersistenceController.shared.save()
    }

    private func openSelectedFile() {
        guard let path = selectedAttempt?.scannedFilePath else { return }
        NSWorkspace.shared.open(URL(filePath: path))
    }
}

// MARK: - Attempt row sub-views (reactive via @ObservedObject)

/// Full-width row for the Complete Logs list.  Using @ObservedObject ensures
/// the row re-renders immediately when any AttemptMO property changes (e.g.
/// manualStatus), without waiting for the parent @FetchRequest to cycle.
private struct AttemptRowContent: View {
    @ObservedObject var attempt: AttemptMO

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(attempt.paper?.subject?.name ?? "Unknown Subject")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text(attempt.barcodeValue ?? "—")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                if let norm = attempt.paper?.normalizedSeries {
                    Text(SeriesNormalizationEngine.displayName(from: norm))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                // Marks / percentage row
                if attempt.totalScore > 0 {
                    let maxM = CompleteLogsView.maxMarks(for: attempt)
                    let score = Int(attempt.totalScore)
                    if maxM > 0 {
                        let pct = (attempt.totalScore / Double(maxM)) * 100.0
                        Text("\(score)/\(maxM)  (\(String(format: "%.0f", pct))%)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    } else {
                        Text("\(score) marks")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                AttemptStatusBadge(attempt: attempt)
                if let grade = attempt.rawGrade, !grade.isEmpty {
                    Text(grade)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                if let path = attempt.scannedFilePath {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .systemBlue).opacity(0.75))
                        .help("Double-click row or click here to open PDF")
                        .onTapGesture {
                            PDFFloatingWindowController.open(
                                url:   URL(filePath: path),
                                title: attempt.barcodeValue ?? "Scanned PDF"
                            )
                        }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Status badge that re-renders whenever `attempt.manualStatus` or
/// `attempt.completedTimestamp` changes.
private struct AttemptStatusBadge: View {
    @ObservedObject var attempt: AttemptMO

    var body: some View {
        let (status, color) = CompleteLogsView.statusState(for: attempt)
        return Text(status)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .animation(.smooth(duration: 0.3), value: status)
    }

    static func color(for status: String) -> Color {
        switch status {
        case "Done":             return Color(nsColor: .systemGreen)
        case "Ask Teacher":      return Color(nsColor: .systemBlue)
        case "Pending Analysis": return Color(nsColor: .secondaryLabelColor)
        default:                 return Color(nsColor: .systemOrange)
        }
    }
}

// MARK: - Clip display subviews
//
// These are file-private structs (NOT nested inside CompleteLogsView) so they
// can hold @ObservedObject.  Using @ObservedObject on AttemptMO (which is an
// NSManagedObject / ObservableObject) means the view re-renders the moment a
// property like difficultQuestionsImageData is set to nil — which is what
// makes the "Clear Clip" button collapse the image instantly.

private struct ReviewClipView: View {
    @ObservedObject var attempt: AttemptMO

    var body: some View {
        if let data = attempt.difficultQuestionsImageData,
           let rep  = NSBitmapImageRep(data: data),
           let img  = rep.cgImage {
            VStack(alignment: .trailing, spacing: 4) {
                Button("Clear Clip") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        attempt.difficultQuestionsImageData = nil
                        PersistenceController.shared.save()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                Image(decorative: img, scale: 2.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .help("Scanned คำถามที่ต้องดู section")
            }
        }
    }
}

private struct NotesClipView: View {
    @ObservedObject var attempt: AttemptMO

    var body: some View {
        if let data = attempt.additionalNotesImageData,
           let rep  = NSBitmapImageRep(data: data),
           let img  = rep.cgImage {
            VStack(alignment: .trailing, spacing: 4) {
                Button("Clear Clip") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        attempt.additionalNotesImageData = nil
                        PersistenceController.shared.save()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                Image(decorative: img, scale: 2.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .help("Scanned Additional Notes section")
            }
        }
    }
}
