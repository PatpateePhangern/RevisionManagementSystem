import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Root view

/// Papers Mapping workspace.
///
/// Left panel  — scrollable index of all PaperMO records, grouped by subject.
/// Right panel — question structure editor and grade threshold editor for the
///               selected paper, plus a drag-and-drop PDF association zone.
/// Header bar  — [ + Add Series ] button that opens the `AddSeriesSheet`.
struct PapersMappingView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.normalizedSeries, order: .reverse)],
        animation: .default
    ) private var papers: FetchedResults<PaperMO>

    @EnvironmentObject private var mappingState: PapersMappingState

    @State private var selectedPaperIDs: Set<NSManagedObjectID> = []
    @State private var showDeleteConfirm      = false
    @State private var showMultiDeleteConfirm = false
    @State private var pendingThresholdPaper: PaperMO? = nil
    @State private var isQDropTargeted        = false
    @State private var isMSDropTargeted       = false
    @State private var searchText:            String = ""
    @FocusState private var searchFocused: Bool

    // ── Multi-filter state ───────────────────────────────────────────────────
    @State private var filterSubject:  String = "All"
    @State private var filterPaper:    String = "All"
    @State private var filterVariant:  String = "All"

    @Namespace private var selectionNamespace

    private var selectedPaper: PaperMO? {
        guard let id = selectedPaperIDs.first, selectedPaperIDs.count == 1 else { return nil }
        return papers.first { $0.objectID == id }
    }

    // MARK: - Filter helpers

    private var allSubjectNames: [String] {
        let names = Set(papers.compactMap { $0.subject?.name })
        return ["All"] + names.sorted()
    }

    private var allPaperNumbers: [String] {
        let nums = Set(papers.compactMap { p -> String? in
            guard let s = p.normalizedSeries else { return nil }
            return SeriesFilterHelper.paperLabel(from: s)
        })
        return nums.isEmpty ? [] : ["All"] + nums.sorted()
    }

    private var allVariantNumbers: [String] {
        let nums = Set(papers.compactMap { p -> String? in
            guard let s = p.normalizedSeries else { return nil }
            return SeriesFilterHelper.variantLabel(from: s)
        })
        return nums.isEmpty ? [] : ["All"] + nums.sorted()
    }

    private var hasActiveFilter: Bool {
        filterSubject != "All" || filterPaper != "All" || filterVariant != "All"
    }

    private var filteredPapers: [PaperMO] {
        papers.filter { p in
            // Text search
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            let textOK: Bool = q.isEmpty || {
                let subjectHit = (p.subject?.name ?? "").lowercased().contains(q)
                let normHit    = (p.normalizedSeries ?? "").lowercased().contains(q)
                let displayHit = p.normalizedSeries.map {
                    SeriesNormalizationEngine.displayName(from: $0).lowercased().contains(q)
                } ?? false
                return subjectHit || normHit || displayHit
            }()
            guard textOK else { return false }

            // Subject filter
            if filterSubject != "All", (p.subject?.name ?? "") != filterSubject { return false }

            // Paper filter
            if filterPaper != "All" {
                let pLabel = p.normalizedSeries.flatMap { SeriesFilterHelper.paperLabel(from: $0) }
                if pLabel != filterPaper { return false }
            }

            // Variant filter
            if filterVariant != "All" {
                let vLabel = p.normalizedSeries.flatMap { SeriesFilterHelper.variantLabel(from: $0) }
                if vLabel != filterVariant { return false }
            }

            return true
        }
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 260, maxWidth: 360)
            detailArea
                .frame(minWidth: 480)
        }
        .sheet(isPresented: $mappingState.showAddSeries,
               onDismiss: { mappingState.addSeriesPrefill = nil }) {
            AddSeriesSheet(isPresented: $mappingState.showAddSeries,
                           prefill: mappingState.addSeriesPrefill)
                .environment(\.managedObjectContext, ctx)
        }
        // Single-paper delete
        .confirmationDialog(
            "Delete this exam series?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Series", role: .destructive) {
                if let paper = selectedPaper { deletePaper(paper) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let p = selectedPaper {
                let name = p.subject?.name ?? "Unknown"
                let series = p.normalizedSeries ?? ""
                Text("\"\(name) \u{2014} \(series)\" and all associated attempt records will be permanently removed.")
            }
        }
        // Multi-paper delete
        .confirmationDialog(
            "Delete \(selectedPaperIDs.count) exam series?",
            isPresented: $showMultiDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedPaperIDs.count) Series", role: .destructive) {
                deleteSelectedPapers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All selected series and their attempt records will be permanently removed.")
        }
        // Arrow key navigation for list
        .onKeyPress(phases: .down) { press in
            let fp = filteredPapers
            guard selectedPaperIDs.count == 1, !fp.isEmpty else { return .ignored }
            let currentIndex = fp.firstIndex { $0.objectID == selectedPaperIDs.first }
            if press.key == .upArrow {
                let nextIndex = currentIndex.flatMap { $0 > 0 ? $0 - 1 : nil } ?? fp.count - 1
                withAnimation(.smooth(duration: 0.25)) { selectedPaperIDs = [fp[nextIndex].objectID] }
                return .handled
            } else if press.key == .downArrow {
                let nextIndex = currentIndex.flatMap { $0 < fp.count - 1 ? $0 + 1 : nil } ?? 0
                withAnimation(.smooth(duration: 0.25)) { selectedPaperIDs = [fp[nextIndex].objectID] }
                return .handled
            }
            return .ignored
        }
        // When a page-mapping window closes for a new paper that has no grade
        // thresholds yet, prompt the user to set them immediately.
        .onReceive(
            NotificationCenter.default.publisher(for: .pdfMappingWindowClosed)
        ) { note in
            guard let oid = note.object as? NSManagedObjectID,
                  let paper = papers.first(where: { $0.objectID == oid }),
                  (paper.gradeThresholds as? Set<GradeThresholdTableMO> ?? []).isEmpty
            else { return }
            pendingThresholdPaper = paper
        }
        .alert(
            "Set Grade Thresholds?",
            isPresented: Binding(
                get: { pendingThresholdPaper != nil },
                set: { if !$0 { pendingThresholdPaper = nil } }
            )
        ) {
            Button("Set Now") {
                if let p = pendingThresholdPaper {
                    withAnimation(.smooth(duration: 0.25)) {
                        selectedPaperIDs = [p.objectID]
                    }
                }
                pendingThresholdPaper = nil
            }
            Button("Later", role: .cancel) { pendingThresholdPaper = nil }
        } message: {
            if let p = pendingThresholdPaper {
                let name   = p.subject?.name ?? "this paper"
                let series = p.normalizedSeries.flatMap {
                    SeriesNormalizationEngine.displayName(from: $0)
                } ?? ""
                Text("No grade thresholds have been set for \(name) \(series). Set them now?")
            }
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            // ── Header bar ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                Text("Papers Index")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                if selectedPaperIDs.count > 1 {
                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                            showMultiDeleteConfirm = true
                        }
                    } label: {
                        Label("Delete \(selectedPaperIDs.count)", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(RedGlassButtonStyle())
                    .focusEffectDisabled()
                }
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { mappingState.showAddSeries = true }
                } label: {
                    Label("Add Series  [⌘N]", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(BlueGlassButtonStyle())
                .help("Create a new exam series entry  [⌘N]")
                .keyboardShortcut("n", modifiers: .command)
                .focusEffectDisabled()
            }
            .focusEffectDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            // ── Search bar ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                TextField("Search subject, month, year…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { withAnimation(.smooth(duration: 0.18)) { searchText = "" } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            .onAppear { searchFocused = false }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            // ── Filter chips ─────────────────────────────────────────────────
            filterBar
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ── Paper list (custom glass selection) ─────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    let fp = filteredPapers
                    if fp.isEmpty {
                        Text(searchText.isEmpty ? "No papers" : "No results for \"\(searchText)\"")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(fp, id: \.objectID) { paper in
                            selectionRow(for: paper)
                        }
                    }
                }
                .padding(6)
                .animation(.smooth(duration: 0.22), value: searchText)
            }

            Divider()
            // ── Footer bar ──────────────────────────────────────────────────
            HStack {
                let fp = filteredPapers
                if selectedPaperIDs.isEmpty {
                    Text(searchText.isEmpty
                         ? "\(papers.count) series"
                         : "\(fp.count) of \(papers.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                } else {
                    Text("\(selectedPaperIDs.count) of \(fp.count) selected")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            // Subject filter
            filterChip(
                label: "Subject",
                value: filterSubject,
                options: allSubjectNames
            ) { filterSubject = $0 }

            // Paper filter (only when papers with P# exist)
            if allPaperNumbers.count > 1 {
                filterChip(
                    label: "Paper",
                    value: filterPaper,
                    options: allPaperNumbers
                ) { filterPaper = $0 }
            }

            // Variant filter (only when papers with V# exist)
            if allVariantNumbers.count > 1 {
                filterChip(
                    label: "Variant",
                    value: filterVariant,
                    options: allVariantNumbers
                ) { filterVariant = $0 }
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
    private func filterChip(label: String, value: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    withAnimation(.smooth(duration: 0.18)) { onChange(opt) }
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

    // MARK: - Custom selection row (glass highlight + smooth animation)

    private func selectionRow(for paper: PaperMO) -> some View {
        let isSelected = selectedPaperIDs.contains(paper.objectID)
        let isSingle   = selectedPaperIDs.count == 1

        return Button {
            // No animation wrapper — state change is instant; only the background
            // colour transitions, driven by the .animation below.
            let cmdHeld = NSEvent.modifierFlags.contains(.command)
            if cmdHeld {
                if isSelected { selectedPaperIDs.remove(paper.objectID) }
                else          { selectedPaperIDs.insert(paper.objectID) }
            } else {
                selectedPaperIDs = [paper.objectID]
            }
        } label: {
            paperRow(paper)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                if isSingle {
                    // Light-blue pill that slides between rows
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.13))
                        .matchedGeometryEffect(id: "selectionPill", in: selectionNamespace)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.10))
                }
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.14), value: selectedPaperIDs)
    }

    // MARK: - PDF drop helper (used in detail panel)

    private func pdfDropRow(
        label: String,
        friendlyName: String,
        shortcutHint: String,
        path: String?,
        isTargeted: Binding<Bool>,
        onDrop: @escaping (URL) -> Void,
        onOpen: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onBrowse: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row label
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack(spacing: 6) {
                // Drop / status zone
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTargeted.wrappedValue
                              ? Color.accentColor.opacity(0.08)
                              : (path != nil
                                 ? Color(nsColor: .systemGreen).opacity(0.06)
                                 : Color(nsColor: .controlBackgroundColor)))
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isTargeted.wrappedValue ? Color.accentColor : Color(nsColor: .separatorColor),
                            style: StrokeStyle(
                                lineWidth: isTargeted.wrappedValue ? 1.5 : 0.5,
                                dash: path == nil ? [6, 3] : []
                            )
                        )

                    if path != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(nsColor: .systemGreen))
                            Text(friendlyName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: isTargeted.wrappedValue
                                  ? "doc.badge.arrow.up.fill"
                                  : "arrow.down.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(isTargeted.wrappedValue
                                                 ? Color.accentColor
                                                 : Color(nsColor: .tertiaryLabelColor))
                                .symbolEffect(.bounce, value: isTargeted.wrappedValue)
                                .animation(.spring(duration: 0.2), value: isTargeted.wrappedValue)
                            Text(isTargeted.wrappedValue ? "Drop to link" : "Drop PDF  \(shortcutHint)")
                                .font(.system(size: 10))
                                .foregroundStyle(isTargeted.wrappedValue
                                                 ? Color.accentColor
                                                 : Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .onDrop(of: [.pdf], isTargeted: isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadDataRepresentation(forTypeIdentifier: "com.adobe.pdf") { data, _ in
                        guard let data else { return }
                        let fm = FileManager.default
                        guard let appSupport = fm.urls(for: .applicationSupportDirectory,
                                                       in: .userDomainMask).first else { return }
                        let dir = appSupport.appendingPathComponent("PaperTracker/LinkedPDFs",
                                                                    isDirectory: true)
                        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                        let dest = dir.appendingPathComponent("\(UUID().uuidString).pdf")
                        try? data.write(to: dest)
                        Task { @MainActor in onDrop(dest) }
                    }
                    return true
                }
                .onTapGesture { if path != nil { onOpen() } }

                // Browse button
                Button {
                    onBrowse()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.small)
                .help("Browse for PDF file")

                // Open button (only when linked)
                if path != nil {
                    Button {
                        onOpen()
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.small)
                    .help("Open PDF")
                }

                // Clear / delete link button
                if path != nil {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .systemRed).opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Remove PDF link")
                }
            }
        }
    }

    private func paperRow(_ p: PaperMO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(p.subject?.name ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))

            HStack(spacing: 6) {
                if let norm = p.normalizedSeries {
                    Text(SeriesNormalizationEngine.displayName(from: norm))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text(norm)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            // Status chips
            HStack(spacing: 5) {
                let qCount = (p.questionStructures as? Set<QuestionStructureMO> ?? [])
                    .filter { ($0.source ?? "questionPaper") == "questionPaper" }.count
                let hasThresholds = !(p.gradeThresholds as? Set<GradeThresholdTableMO> ?? []).isEmpty

                if qCount > 0 {
                    Text("\(qCount)Q")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(nsColor: .systemBlue).opacity(0.12))
                        .foregroundStyle(Color(nsColor: .systemBlue))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("No Qs")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                if hasThresholds {
                    Text("Thresholds")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(nsColor: .systemGreen).opacity(0.12))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if (p.attempts as? Set<AttemptMO>)?.contains(where: { $0.scannedFilePath != nil }) == true {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .systemBlue).opacity(0.6))
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Detail area

    @ViewBuilder
    private var detailArea: some View {
        if let paper = selectedPaper {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    paperDetailHeader(paper)
                    Divider()
                    QuestionStructureEditor(paper: paper)
                        .environment(\.managedObjectContext, ctx)
                    Divider()
                    GradeThresholdEditor(paper: paper)
                        .environment(\.managedObjectContext, ctx)
                }
                .padding(28)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Text("Select a paper from the index to configure its structure")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text("Use [ + Add Series ] to create a new paper entry")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .quaternaryLabelColor))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func paperDetailHeader(_ p: PaperMO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Title row ────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.subject?.name ?? "—")
                        .font(.system(size: 16, weight: .bold))
                    HStack(spacing: 10) {
                        if let norm = p.normalizedSeries {
                            Text(SeriesNormalizationEngine.displayName(from: norm))
                                .font(.system(size: 13))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            Text(norm)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                    let attCount  = (p.attempts as? Set<AttemptMO> ?? []).count
                    let qpOnly    = (p.questionStructures as? Set<QuestionStructureMO> ?? [])
                        .filter { ($0.source ?? "questionPaper") == "questionPaper" }
                    let qCount    = qpOnly.count
                    let maxTotal  = qpOnly.reduce(0) { $0 + Int($1.maxMarks) }
                    HStack(spacing: 16) {
                        Label("\(attCount) attempt\(attCount == 1 ? "" : "s")", systemImage: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        if qCount > 0 {
                            Label("\(qCount) questions — \(maxTotal) marks", systemImage: "list.number")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    let pageMappingEnabled = p.questionPaperPDFPath != nil || p.markSchemePDFPath != nil
                    Button {
                        PDFPageMappingWindowController.open(paper: p)
                    } label: {
                        Label("Page Mapping…", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .opacity(pageMappingEnabled ? 1.0 : 0.35)
                    .grayscale(pageMappingEnabled ? 0 : 1)
                    .help("Open Page Mapping  [⌘M]")
                    .keyboardShortcut("m", modifiers: .command)
                    .disabled(!pageMappingEnabled)

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Series", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(RedGlassButtonStyle())
                    .help("Delete series  [⌦]")
                    .keyboardShortcut(.delete, modifiers: [])
                }
            }

            Divider()

            // ── PDF link rows — drop, browse, open, or clear ─────────────────
            pdfDropRow(
                label: "Question Paper  [⌘O]",
                friendlyName: "Question Paper.pdf",
                shortcutHint: "or ⌘O to browse",
                path: p.questionPaperPDFPath,
                isTargeted: $isQDropTargeted,
                onDrop: { url in
                    let dest = Self.copyPDFToLinkedStorage(from: url) ?? url
                    p.questionPaperPDFPath = dest.path(percentEncoded: false)
                    PersistenceController.shared.save()
                },
                onOpen: {
                    if let path = p.questionPaperPDFPath { NSWorkspace.shared.open(URL(filePath: path)) }
                },
                onClear: {
                    p.questionPaperPDFPath = nil
                    PersistenceController.shared.save()
                },
                onBrowse: { browsePDF { url in
                    p.questionPaperPDFPath = url.path(percentEncoded: false)
                    PersistenceController.shared.save()
                }}
            )
            // ⌘O — open/browse question paper
            .background(
                Button("") {
                    if let path = p.questionPaperPDFPath {
                        NSWorkspace.shared.open(URL(filePath: path))
                    } else {
                        browsePDF { url in
                            p.questionPaperPDFPath = url.path(percentEncoded: false)
                            PersistenceController.shared.save()
                        }
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                .hidden()
            )

            pdfDropRow(
                label: "Mark Scheme  [⌘⇧O]",

                friendlyName: "Mark Scheme.pdf",
                shortcutHint: "or ⌘⇧O to browse",
                path: p.markSchemePDFPath,
                isTargeted: $isMSDropTargeted,
                onDrop: { url in
                    let dest = Self.copyPDFToLinkedStorage(from: url) ?? url
                    p.markSchemePDFPath = dest.path(percentEncoded: false)
                    PersistenceController.shared.save()
                },
                onOpen: {
                    if let path = p.markSchemePDFPath { NSWorkspace.shared.open(URL(filePath: path)) }
                },
                onClear: {
                    p.markSchemePDFPath = nil
                    PersistenceController.shared.save()
                },
                onBrowse: { browsePDF { url in
                    p.markSchemePDFPath = url.path(percentEncoded: false)
                    PersistenceController.shared.save()
                }}
            )
            // ⌘⇧O — open/browse mark scheme
            .background(
                Button("") {
                    if let path = p.markSchemePDFPath {
                        NSWorkspace.shared.open(URL(filePath: path))
                    } else {
                        browsePDF { url in
                            p.markSchemePDFPath = url.path(percentEncoded: false)
                            PersistenceController.shared.save()
                        }
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .hidden()
            )
        }
    }

    /// Opens an NSOpenPanel for PDF selection, copies to permanent storage,
    /// then calls `completion` with the permanent URL on the main thread.
    private func browsePDF(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.title = "Select PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dest = Self.copyPDFToLinkedStorage(from: url) ?? url
        completion(dest)
    }

    /// Copies `url` into `~/Library/Application Support/PaperTracker/LinkedPDFs/`
    /// with a stable UUID filename and returns the permanent URL, or `nil` on failure.
    @discardableResult
    static func copyPDFToLinkedStorage(from url: URL) -> URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("PaperTracker/LinkedPDFs",
                                                    isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        do {
            try fm.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Delete helpers

    private func deletePaper(_ paper: PaperMO) {
        let pdfPaths: [String] = ((paper.attempts as? Set<AttemptMO>) ?? [])
            .compactMap { $0.scannedFilePath }.filter { !$0.isEmpty }
        ctx.delete(paper)
        PersistenceController.shared.save()
        selectedPaperIDs.remove(paper.objectID)
        for path in pdfPaths { try? FileManager.default.removeItem(atPath: path) }
    }

    /// Deletes all currently selected papers in one pass.
    private func deleteSelectedPapers() {
        let toDelete = papers.filter { selectedPaperIDs.contains($0.objectID) }
        var allPaths: [String] = []
        for paper in toDelete {
            allPaths += ((paper.attempts as? Set<AttemptMO>) ?? [])
                .compactMap { $0.scannedFilePath }.filter { !$0.isEmpty }
            ctx.delete(paper)
        }
        PersistenceController.shared.save()
        selectedPaperIDs.removeAll()
        for path in allPaths { try? FileManager.default.removeItem(atPath: path) }
    }

    // MARK: - PDF link helper

    private func linkPDF(url: URL, to paper: PaperMO) {
        // Associate the dropped PDF with the most recent attempt for this paper.
        guard let attempt = ((paper.attempts as? Set<AttemptMO>) ?? [])
            .sorted(by: { ($0.printTimestamp ?? .distantPast) > ($1.printTimestamp ?? .distantPast) })
            .first,
              let barcode = attempt.barcodeValue,
              let subjectName = paper.subject?.name,
              let archiveRoot = effectivePDFArchiveRoot
        else { return }

        if let dest = try? FileOrganizationPipeline.organize(
            sourceURL: url,
            subjectName: subjectName,
            barcodeValue: barcode,
            archiveRoot: archiveRoot
        ) {
            attempt.scannedFilePath = dest.path(percentEncoded: false)
            PersistenceController.shared.save()
        }
    }

    @AppStorage("customPDFStoragePath") private var customPDFStoragePath: String = ""

    private var effectivePDFArchiveRoot: URL? {
        if !customPDFStoragePath.isEmpty { return URL(filePath: customPDFStoragePath) }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(components: "PaperTracker", "PDFs")
    }
}

// MARK: - Question structure editor

private struct QuestionStructureEditor: View {

    @ObservedObject var paper: PaperMO
    @Environment(\.managedObjectContext) private var ctx

    @State private var newLabel:     String = ""
    @State private var newMaxMarks:  String = ""
    @State private var newPageRange: String = ""

    private var questions: [QuestionStructureMO] {
        (paper.questionStructures as? Set<QuestionStructureMO> ?? [])
            .filter { ($0.source ?? "questionPaper") == "questionPaper" }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private func cleanQuestionLabel(_ raw: String?) -> String {
        guard let raw else { return "—" }
        return raw
            .replacingOccurrences(of: #"\s*\[p+\.\d.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private var totalMarks: Int {
        questions.reduce(0) { $0 + Int($1.maxMarks) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Section header ──────────────────────────────────────────────
            HStack {
                Text("Question Structure")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                if totalMarks > 0 {
                    Text("Total: \(totalMarks) marks")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                // Batch operations
                if !questions.isEmpty {
                    Button {
                        clearAllPageRanges()
                    } label: {
                        Label("Clear Ranges", systemImage: "xmark.circle")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.small)
                    .help("Clear all page ranges from questions  [⌘⌫]")
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }

            // ── Column headers ──────────────────────────────────────────────
            HStack(spacing: 0) {
                Text("Question")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Page Range")
                    .frame(width: 120, alignment: .leading)
                Text("Max Marks")
                    .frame(width: 90, alignment: .trailing)
                Spacer().frame(width: 36)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            .padding(.horizontal, 2)

            Divider()

            // ── Existing rows ───────────────────────────────────────────────
            if questions.isEmpty {
                Text("No questions defined yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.vertical, 4)
            } else {
                ForEach(questions, id: \.id) { q in
                    HStack(spacing: 0) {
                        Text(cleanQuestionLabel(q.questionLabel))
                            .font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(pageRangeSuffix(q.questionLabel))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 120, alignment: .leading)

                        Text("\(q.maxMarks)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .frame(width: 90, alignment: .trailing)

                        Button {
                            ctx.delete(q)
                            PersistenceController.shared.save()
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }
                        .buttonStyle(.plain)
                        .frame(width: 36)
                    }
                    .padding(.vertical, 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
                .animation(.smooth(duration: 0.3), value: questions.map(\.id))
            }

            Divider()

            // ── Add new question row ────────────────────────────────────────
            HStack(spacing: 8) {
                TextField("Label  e.g. Q1, 4a", text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .onSubmit { addQuestion() }

                TextField("Pages  e.g. 3-4", text: $newPageRange)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 110)

                TextField("Marks", text: $newMaxMarks)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 68)
                    .onSubmit { addQuestion() }

                Button("Add") { addQuestion() }
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty
                              || Int16(newMaxMarks) == nil)
            }
        }
    }

    /// Extracts a "[pp.X-Y]" annotation embedded in the question label, if any.
    private func pageRangeSuffix(_ label: String?) -> String {
        guard let label else { return "—" }
        if let r = label.range(of: #"\[pp\..*?\]"#, options: .regularExpression) {
            return String(label[r])
        }
        return "—"
    }

    private func addQuestion() {
        let rawLabel = newLabel.trimmingCharacters(in: .whitespaces)
        guard !rawLabel.isEmpty, let marks = Int16(newMaxMarks.trimmingCharacters(in: .whitespaces)) else { return }

        // Embed page range into the label as "[pp.X-Y]" annotation if provided.
        let pageAnn = newPageRange.trimmingCharacters(in: .whitespaces)
        let fullLabel = pageAnn.isEmpty ? rawLabel : "\(rawLabel) [pp.\(pageAnn)]"

        let order = Int16(questions.count)
        QuestionStructureMO.insert(
            label:        fullLabel,
            maxMarks:     marks,
            displayOrder: order,
            paper:        paper,
            in:           ctx
        )
        PersistenceController.shared.save()
        newLabel     = ""
        newMaxMarks  = ""
        newPageRange = ""
    }

    private func clearAllPageRanges() {
        for q in questions {
            guard let label = q.questionLabel else { continue }
            // Remove "[pp.X-Y]" suffix from the label
            let cleaned = label.replacingOccurrences(of: #"\s*\[pp\..*?\]"#, with: "", options: .regularExpression)
            q.questionLabel = cleaned.isEmpty ? "—" : cleaned
        }
        PersistenceController.shared.save()
    }
}

// MARK: - Grade threshold editor

private struct GradeThresholdEditor: View {

    @ObservedObject var paper: PaperMO
    @Environment(\.managedObjectContext) private var ctx

    @State private var configSkipped = false

    private var threshold: GradeThresholdTableMO? {
        (paper.gradeThresholds as? Set<GradeThresholdTableMO>)?.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Grade Thresholds")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                if threshold == nil && !configSkipped {
                    Button("Skip Configuration") {
                        configSkipped = true
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            if configSkipped && threshold == nil {
                HStack(spacing: 8) {
                    Text("Grade threshold configuration skipped for this paper.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    Button("Configure") { configSkipped = false }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                }
            } else if let t = threshold {
                ThresholdEditView(threshold: t)
                    .environment(\.managedObjectContext, ctx)
            } else {
                Button("+ Add Grade Thresholds") {
                    guard let norm = paper.normalizedSeries else { return }
                    _ = GradeThresholdTableMO.insert(rawSeriesKey: norm, paper: paper, in: ctx)
                    PersistenceController.shared.save()
                }
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Threshold edit form

private struct ThresholdEditView: View {

    @ObservedObject var threshold: GradeThresholdTableMO
    @Environment(\.managedObjectContext) private var ctx

    @State private var maxMarksStr: String = ""
    @State private var aStarStr:    String = ""
    @State private var aStr:        String = ""
    @State private var bStr:        String = ""
    @State private var cStr:        String = ""
    @State private var dStr:        String = ""
    @State private var eStr:        String = ""
    @State private var hasAStar:    Bool   = false
    @State private var didSave:     Bool   = false

    private enum Field { case maxMarks, aStar, a, b, c, d, e }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            gradeRow("Max Marks", binding: $maxMarksStr, field: .maxMarks,
                     next: { focus = hasAStar ? .aStar : .a }, isHeader: true)

            Toggle("Include A* Grade", isOn: $hasAStar)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .focusEffectDisabled()

            Divider()

            if hasAStar { gradeRow("A*", binding: $aStarStr, field: .aStar, next: { focus = .a }) }
            gradeRow("A", binding: $aStr, field: .a, next: { focus = .b })
            gradeRow("B", binding: $bStr, field: .b, next: { focus = .c })
            gradeRow("C", binding: $cStr, field: .c, next: { focus = .d })
            gradeRow("D", binding: $dStr, field: .d, next: { focus = .e })
            gradeRow("E", binding: $eStr, field: .e, next: { save(); focus = nil })

            Button {
                save()
                focus = nil
                withAnimation(.smooth(duration: 0.25)) { didSave = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.smooth(duration: 0.3)) { didSave = false }
                }
            } label: {
                Label(
                    didSave ? "Saved" : "Save Thresholds  [⌘S]",
                    systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                )
                .animation(.smooth(duration: 0.2), value: didSave)
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(BlueGlassButtonStyle())
            .controlSize(.small)
        }
        .onAppear { load() }
        .onChange(of: threshold.objectID) { _, _ in load() }
    }

    private func gradeRow(_ label: String, binding: Binding<String>,
                           field: Field, next: @escaping () -> Void,
                           isHeader: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(isHeader
                      ? .system(size: 11)
                      : .system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isHeader
                                 ? Color(nsColor: .secondaryLabelColor)
                                 : Color(nsColor: .labelColor))
                .frame(width: 84, alignment: .trailing)
            TextField(isHeader ? "e.g. 75" : "Min marks", text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
                .font(.system(size: 11))
                .focused($focus, equals: field)
                .onSubmit { next() }
        }
    }

    private func load() {
        maxMarksStr = threshold.maxPossibleMarks > 0 ? "\(threshold.maxPossibleMarks)" : ""
        hasAStar    = threshold.hasAStar
        aStarStr    = threshold.markAStar > 0 ? "\(threshold.markAStar)" : ""
        aStr        = threshold.markA     > 0 ? "\(threshold.markA)"     : ""
        bStr        = threshold.markB     > 0 ? "\(threshold.markB)"     : ""
        cStr        = threshold.markC     > 0 ? "\(threshold.markC)"     : ""
        dStr        = threshold.markD     > 0 ? "\(threshold.markD)"     : ""
        eStr        = threshold.markE     > 0 ? "\(threshold.markE)"     : ""
    }

    private func save() {
        if let v = Int16(maxMarksStr) { threshold.maxPossibleMarks = v }
        threshold.hasAStar = hasAStar
        if let v = Int16(aStarStr) { threshold.markAStar = v }
        if let v = Int16(aStr)     { threshold.markA     = v }
        if let v = Int16(bStr)     { threshold.markB     = v }
        if let v = Int16(cStr)     { threshold.markC     = v }
        if let v = Int16(dStr)     { threshold.markD     = v }
        if let v = Int16(eStr)     { threshold.markE     = v }
        PersistenceController.shared.save()
    }
}

// MARK: - Add Series sheet

/// Modal sheet for creating a new PaperMO series entry.
///
/// For CS subjects, a combined-session session picker converts:
///   "May/June" input → normalised month 06  (display: "May June YYYY")
///   "Oct/Nov"  input → normalised month 11  (display: "Oct Nov YYYY")
/// For all other subjects, standard series input is used (any month/year string
/// accepted by `SeriesNormalizationEngine.normalize(_:)`).
private struct AddSeriesSheet: View {

    @Binding var isPresented: Bool
    var prefill: PapersMappingPrefill? = nil

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name, order: .forward)],
        animation: .none
    ) private var subjects: FetchedResults<SubjectMO>

    // Form state
    @State private var subjectText:      String     = ""
    @State private var selectedSubject: SubjectMO? = nil
    @State private var yearText:         String     = ""
    @State private var seriesInput:      String     = ""
    @State private var csSession:        CSSession  = .mayJune
    @State private var paperComponent:   Int        = 1
    @State private var variantNumber:    Int        = 1
    @State private var normError:        String?    = nil

    // Focus routing: Enter on subject → jump straight to series / year field
    @FocusState private var seriesFocused: Bool
    @FocusState private var yearFocused:   Bool

    // CS combined-session options
    private enum CSSession: String, CaseIterable {
        case mayJune = "May/June"
        case octNov  = "Oct/Nov"
    }

    private var isCS: Bool {
        guard let name = selectedSubject?.name else { return false }
        let u = name.uppercased()
        return u.contains("CS1") || u.contains("CS2") || u.contains("CS3")
            || u.contains("CS4") || u.contains("COMPUTER SCIENCE")
    }

    // MARK: Derived normalised series key

    private var derivedNorm: String? {
        guard selectedSubject != nil else { return nil }
        if isCS {
            // CS: derive month from combined-session picker + 4-digit year
            let yr = yearText.trimmingCharacters(in: .whitespaces)
            guard !yr.isEmpty else { return nil }
            let month = csSession == .mayJune ? "06" : "11"
            let base  = "\(yr)-\(month)"
            return SeriesNormalizationEngine.normalizeCSVariant(
                baseSeries:    base,
                paperNumber:   paperComponent,
                variantNumber: variantNumber
            )
        } else {
            let raw = seriesInput.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            return SeriesNormalizationEngine.normalize(raw)
        }
    }

    /// Human-readable label for the derived series key — shows "May June YYYY"
    /// or "Oct Nov YYYY" for CS combined sessions.
    private var derivedDisplayName: String? {
        guard let norm = derivedNorm else { return nil }
        if isCS {
            let parts = norm.split(separator: "-", maxSplits: 2)
            guard parts.count >= 2, let m = Int(parts[1]) else {
                return SeriesNormalizationEngine.displayName(from: norm)
            }
            let yr         = String(parts[0])
            let sessionStr = (m == 6) ? "May June" : "Oct Nov"
            // Append paper/variant suffix if present (e.g. "P1V2").
            if parts.count == 3, let suffix = parts.last {
                return "\(sessionStr) \(yr) · \(suffix)"
            }
            return "\(sessionStr) \(yr)"
        }
        return SeriesNormalizationEngine.displayName(from: norm)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Title row ────────────────────────────────────────────────────
            HStack {
                Text("Add Exam Series")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Close  [Esc]")
                .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()

            // ── Subject ──────────────────────────────────────────────────────
            formSection("Subject") {
                SearchableComboBox(
                    text: $subjectText,
                    selectedSubject: $selectedSubject,
                    subjects: Array(subjects),
                    placeholder: "Type subject name…",
                    onConfirm: {
                        // Jump to series or year field immediately after Enter
                        if isCS { yearFocused = true } else { seriesFocused = true }
                    },
                    autoFocus: true
                )
                .frame(maxWidth: 340)
                .onChange(of: selectedSubject) { _, _ in normError = nil }
            }

            // ── Series input — CS vs standard ────────────────────────────────
            if isCS {
                formSection("Session") {
                    Picker("", selection: $csSession) {
                        ForEach(CSSession.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)

                    Text("May/June → stored as month 06   ·   Oct/Nov → stored as month 11")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                formSection("Year") {
                    // Inline glass field so we can attach the struct-level @FocusState
                    TextField("e.g. 2025", text: $yearText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .focused($yearFocused)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    yearFocused
                                        ? Color.accentColor.opacity(0.80)
                                        : Color(nsColor: .separatorColor).opacity(0.6),
                                    lineWidth: yearFocused ? 1.5 : 0.5
                                )
                        )
                        .animation(.smooth(duration: 0.18), value: yearFocused)
                        .frame(maxWidth: 110)
                }

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paper")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        Picker("", selection: $paperComponent) {
                            Text("P1").tag(1); Text("P2").tag(2)
                            Text("P3").tag(3); Text("P4").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Variant")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        Picker("", selection: $variantNumber) {
                            Text("V1").tag(1); Text("V2").tag(2); Text("V3").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    }
                }

            } else {
                formSection("Exam Series") {
                    // Inline glass field so we can attach the struct-level @FocusState
                    TextField("e.g. May 2025, Oct 24, 2025-05…", text: $seriesInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .focused($seriesFocused)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    seriesFocused
                                        ? Color.accentColor.opacity(0.80)
                                        : Color(nsColor: .separatorColor).opacity(0.6),
                                    lineWidth: seriesFocused ? 1.5 : 0.5
                                )
                        )
                        .animation(.smooth(duration: 0.18), value: seriesFocused)
                        .frame(maxWidth: 340)
                        .onSubmit { create() }
                }
            }

            // ── Preview derived key ──────────────────────────────────────────
            if let norm = derivedNorm {
                HStack(spacing: 6) {
                    Text("Key:")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text(norm)
                        .font(.system(size: 10, design: .monospaced))
                    if let display = derivedDisplayName {
                        Text("→ \(display)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            }

            if let err = normError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }

            Divider()

            // ── Action row ───────────────────────────────────────────────────
            HStack {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { isPresented = false }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .glassEffect(in: Capsule())
                .keyboardShortcut(.escape, modifiers: [])
                .focusEffectDisabled()
                Spacer()
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { create() }
                } label: {
                    Text("Create Series  [⌘↩]")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .glassEffect(in: Capsule())
                .foregroundStyle(Color.accentColor)
                .keyboardShortcut(.return, modifiers: .command)
                .focusEffectDisabled()
                .disabled(selectedSubject == nil || derivedNorm == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 540)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        .padding(20)
        .presentationBackground(.clear)
        .task { applyPrefill() }
    }

    private func applyPrefill() {
        guard let p = prefill else { return }
        // Resolve subject directly from objectID — works even before @FetchRequest populates
        if let subject = try? ctx.existingObject(with: p.subjectObjectID) as? SubjectMO {
            selectedSubject = subject
            subjectText     = subject.name ?? p.subjectName
        } else {
            subjectText = p.subjectName
        }
        if p.isCS {
            paperComponent = p.paperComponent
            variantNumber  = p.variantNumber
            // Extract year and month from normalizedSeries (format: "YYYY-MM-...")
            if let norm = p.normalizedSeries {
                let parts = norm.split(separator: "-", maxSplits: 2)
                if parts.count >= 2, let month = Int(parts[1]) {
                    yearText  = String(parts[0])
                    csSession = (month == 6) ? .mayJune : .octNov
                }
            }
        } else {
            seriesInput = p.seriesRaw
        }
    }

    // Glass text field helper
    @ViewBuilder
    private func glassTextField(_ placeholder: String, text: Binding<String>) -> some View {
        @FocusState var focused: Bool
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .focused($focused)
            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        focused
                            ? Color.accentColor.opacity(0.80)
                            : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: focused ? 1.5 : 0.5
                    )
            )
            .animation(.smooth(duration: 0.18), value: focused)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func formSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            content()
        }
    }

    private func create() {
        normError = nil
        guard let subject = selectedSubject else {
            normError = "Please select a subject."
            return
        }
        guard let norm = derivedNorm else {
            normError = isCS
                ? "Please enter a valid 4-digit year."
                : "Could not identify a valid exam series from the input."
            return
        }
        if PaperMO.find(subjectID: subject.id ?? UUID(), normalizedSeries: norm, in: ctx) != nil {
            normError = "A paper with series '\(norm)' already exists for \(subject.name ?? "this subject")."
            return
        }
        let rawName = isCS
            ? "\(csSession.rawValue) \(yearText) Paper \(paperComponent) V\(variantNumber)"
            : seriesInput.trimmingCharacters(in: .whitespaces)
        let paper = PaperMO.insert(subject: subject, rawSeriesName: rawName, normalizedSeries: norm, in: ctx)
        PersistenceController.shared.save()
        isPresented = false
        // Auto-open the Page Mapping window for the new paper so the user
        // can immediately link PDFs and map pages without extra clicks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PDFPageMappingWindowController.open(paper: paper)
        }
    }
}
