import SwiftUI
import PDFKit
import CoreData
import UniformTypeIdentifiers

// pdfMappingPanelKeyDown is defined in PapersMappingWindowController.swift

// MARK: - Tab enum

private enum PDFMappingTab: String, CaseIterable {
    case questionPaper = "Question Paper"
    case markScheme    = "Mark Scheme"
}

// MARK: - Main panel

struct PDFPageMappingPanel: View {

    @ObservedObject var paper: PaperMO
    @Environment(\.managedObjectContext) private var ctx

    @State private var activeTab:     PDFMappingTab = .questionPaper
    @State private var selectedPage:  Int           = 0
    @State private var rangeAnchor:   Int?          = nil
    @State private var selectedRange: ClosedRange<Int>? = nil

    @State private var cachedDoc:  PDFDocument? = nil
    @State private var cachedPath: String?      = nil

    // Mapping form
    @State private var mappingLabel: String = ""
    @State private var mappingMarks: String = ""
    @FocusState private var labelFocused: Bool

    // PDF page zoom — persisted across sessions (0 = fit-to-page)
    @AppStorage("pdfPageMappingZoom") private var zoomFactor: Double = 0
    // Last computed fit-to-page scale (reported back from PDFPageView; not persisted)
    @State private var lastFitScale: CGFloat = 0.85

    // Thumbnail cell size — persisted across sessions (default 35 % wider than original 140)
    @AppStorage("pdfPageMappingThumbWidth") private var thumbnailCellWidth: Double = 189

    // Empty-state drop target
    @State private var isEmptyDropTargeted: Bool = false
    // Set when a path is stored but PDFDocument fails to open the file
    @State private var docLoadFailed: Bool = false
    // Keyboard focus for the thumbnail strip
    @FocusState private var thumbnailFocused: Bool
    // Pinch-to-zoom: records cell width at gesture start so scale is relative
    @State private var thumbPinchBase: Double? = nil

    // Namespace for the animated tab-selection pill
    @Namespace private var tabNamespace

    // Grade threshold sheet
    @State private var showThresholdSheet = false

    private var activePDFPath: String? {
        activeTab == .questionPaper ? paper.questionPaperPDFPath : paper.markSchemePDFPath
    }

    // Sorted questions for the current tab only.
    // "questionPaper" is also the default for rows migrated from v2 (source == nil).
    private var questions: [QuestionStructureMO] {
        let activeSource = activeTab == .questionPaper ? "questionPaper" : "markScheme"
        return (paper.questionStructures as? Set<QuestionStructureMO> ?? [])
            .filter { ($0.source ?? "questionPaper") == activeSource }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            tabPicker
            Divider()

            if let doc = cachedDoc {
                HSplitView {
                    leftPanel(doc: doc)
                        .frame(minWidth: 200, idealWidth: 300, maxWidth: 380)
                    rightPanel(doc: doc)
                        .frame(minWidth: 440)
                }
            } else if docLoadFailed {
                invalidFileState
            } else {
                emptyState
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { reloadDocument() }
        .onChange(of: paper.questionPaperPDFPath) { _, _ in reloadDocument() }
        .onChange(of: paper.markSchemePDFPath)    { _, _ in reloadDocument() }
        .onReceive(
            NotificationCenter.default.publisher(for: .pdfMappingPanelKeyDown)
        ) { note in
            guard let event = note.object as? NSEvent else { return }
            handleMappingKeyEvent(event)
        }
        // Auto-focus label field whenever a range is newly selected
        .onChange(of: selectedRange) { _, newRange in
            if newRange != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    labelFocused = true
                }
            }
        }
        .sheet(isPresented: $showThresholdSheet) {
            MappingThresholdSheet(paper: paper, isPresented: $showThresholdSheet) {
                // After sheet dismisses, close the Page Mapping window too.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.keyWindow?.close()
                }
            }
            .environment(\.managedObjectContext,
                          PersistenceController.shared.container.viewContext)
        }
    }

    // MARK: - Question order validity (current tab)
    // nil  = no mappings yet
    // true = sequential from 1 with no gaps (green)
    // false = out-of-order or gap (red)
    private var mappingOrderValid: Bool? {
        guard !questions.isEmpty else { return nil }
        let nums: [Int] = questions.compactMap { q in
            let label = cleanLabel(q.questionLabel ?? "")
            // Strip leading non-digits then parse first run of digits: "Q1"→1, "4a"→4
            let digits = label.drop(while: { !$0.isNumber })
            return Int(String(digits.prefix(while: { $0.isNumber })))
        }
        guard nums.count == questions.count, nums.first == 1 else { return false }
        for i in 1..<nums.count {
            if nums[i] != nums[i - 1] && nums[i] != nums[i - 1] + 1 { return false }
        }
        return true
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text("Page Mapping")
                .font(.headline)
                .fixedSize()
                .layoutPriority(2)

            // Key hints — lowest priority, hidden first when space is tight
            HStack(spacing: 8) {
                keyHint("↑↓", "navigate")
                keyHint("⇧↑↓", "extend range")
                keyHint("⇧Click", "select range")
                keyHint("⌘↑↓", "first / last")
                keyHint("⌘↩", "map")
            }
            .lineLimit(1)
            .layoutPriority(0)

            Spacer(minLength: 8)

            // PDF page zoom controls — fixed size, never compress
            HStack(spacing: 0) {
                Button {
                    let base = zoomFactor == 0 ? Double(lastFitScale) : zoomFactor
                    zoomFactor = max(0.25, base - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .bounceOnPress()
                .help("Zoom out page")

                Divider().frame(height: 14)

                Button {
                    zoomFactor = 0
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .bounceOnPress()
                .help("Fit full page to window")

                Divider().frame(height: 14)

                Button {
                    let base = zoomFactor == 0 ? Double(lastFitScale) : zoomFactor
                    zoomFactor = min(3.0, base + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .bounceOnPress()
                .help("Zoom in page")
            }
            .fixedSize()
            .glassEffect(in: Capsule())
            .focusEffectDisabled()
            .layoutPriority(1)

            Button {
                showThresholdSheet = true
            } label: {
                Label("Proceed", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .focusEffectDisabled()
            .fixedSize()
            .layoutPriority(1)

            Button("Close") { NSApp.keyWindow?.close() }
                .keyboardShortcut("w", modifiers: .command)
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(PDFMappingTab.allCases, id: \.self) { tab in
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        withAnimation(.smooth(duration: 0.3)) { activeTab = tab }
                        selectedPage  = 0
                        rangeAnchor   = nil
                        selectedRange = nil
                        reloadDocument()
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(activeTab == tab ? Color.primary : Color.secondary)
                        .animation(.smooth(duration: 0.2), value: activeTab)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 7)
                        .background {
                            if activeTab == tab {
                                Color.clear
                                    .glassEffect(in: Capsule())
                                    .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(in: Capsule())
        .focusEffectDisabled()
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Left panel (thumbnails + existing mappings)

    private func leftPanel(doc: PDFDocument) -> some View {
        VStack(spacing: 0) {
            thumbnailZoomHeader
            Divider()
            thumbnailStrip(doc: doc)
            Divider()
            mappingsTable
        }
    }

    // Thumbnail strip zoom controls
    private var thumbnailZoomHeader: some View {
        HStack(spacing: 6) {
            Text("THUMBNAILS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .kerning(0.5)

            Spacer()

            Button {
                thumbnailCellWidth = max(60, thumbnailCellWidth - 30)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bounceOnPress()
            .background(Color(nsColor: .controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("Smaller thumbnails (see more pages)")
            .disabled(thumbnailCellWidth <= 60)

            Button {
                thumbnailCellWidth = min(240, thumbnailCellWidth + 30)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bounceOnPress()
            .background(Color(nsColor: .controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("Larger thumbnails (see more detail)")
            .disabled(thumbnailCellWidth >= 240)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Right panel (page canvas + form)

    private func rightPanel(doc: PDFDocument) -> some View {
        VStack(spacing: 0) {
            pageCanvas(doc: doc)

            if selectedRange != nil {
                Divider()
                mappingForm
            }
        }
    }

    // MARK: - Empty state (drag-and-drop zone)

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(isEmptyDropTargeted
                      ? Color.accentColor.opacity(0.07)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.4))
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isEmptyDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(
                        lineWidth: isEmptyDropTargeted ? 2 : 1,
                        dash: [10, 5]
                    )
                )

            VStack(spacing: 18) {
                Image(systemName: isEmptyDropTargeted ? "doc.badge.arrow.up.fill" : "doc.badge.plus")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(isEmptyDropTargeted ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                    .animation(.spring(duration: 0.2), value: isEmptyDropTargeted)
                    .symbolEffect(.bounce, value: isEmptyDropTargeted)

                VStack(spacing: 6) {
                    Text(isEmptyDropTargeted
                         ? "Drop to link \(activeTab.rawValue)"
                         : "No PDF linked for \(activeTab.rawValue)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isEmptyDropTargeted ? Color.accentColor : Color(nsColor: .labelColor))

                    Text("Drop a PDF here, or click Browse to select one")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Button {
                    browsePDFForActiveTab()
                } label: {
                    Label("Browse…", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.regular)
            }
            .padding(48)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.pdf], isTargeted: $isEmptyDropTargeted) { providers in
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
                let path = dest.path(percentEncoded: false)
                Task { @MainActor in linkPDFPath(path) }
            }
            return true
        }
    }

    // MARK: - Invalid file state

    private var invalidFileState: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .symbolEffect(.pulse)

            VStack(spacing: 6) {
                Text("File is not a valid PDF")
                    .font(.system(size: 15, weight: .semibold))
                Text("The linked file could not be opened. It may be corrupted, an HTML page,\nor a download that failed. Drop a real PDF file to replace it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    if activeTab == .questionPaper {
                        paper.questionPaperPDFPath = nil
                    } else {
                        paper.markSchemePDFPath = nil
                    }
                    PersistenceController.shared.save()
                    cachedDoc     = nil
                    cachedPath    = nil
                    docLoadFailed = false
                } label: {
                    Label("Clear Link", systemImage: "xmark.circle")
                }
                .buttonStyle(BlueGlassButtonStyle())

                Button {
                    browsePDFForActiveTab()
                } label: {
                    Label("Browse for PDF…", systemImage: "folder")
                }
                .buttonStyle(BlueGlassButtonStyle())
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browsePDFForActiveTab() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.title = "Select \(activeTab.rawValue) PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dest = PapersMappingView.copyPDFToLinkedStorage(from: url) ?? url
        linkPDFPath(dest.path(percentEncoded: false))
    }

    private func linkPDFPath(_ path: String) {
        if activeTab == .questionPaper {
            paper.questionPaperPDFPath = path
        } else {
            paper.markSchemePDFPath = path
        }
        PersistenceController.shared.save()
        reloadDocument()
    }

    // MARK: - Document lifecycle

    private func reloadDocument() {
        guard let path = activePDFPath, !path.isEmpty else {
            cachedDoc      = nil
            cachedPath     = nil
            docLoadFailed  = false
            return
        }
        guard path != cachedPath || docLoadFailed else { return }
        let doc        = PDFDocument(url: URL(filePath: path))
        cachedDoc      = doc
        cachedPath     = path
        docLoadFailed  = (doc == nil)
        selectedPage   = 0
    }

    // MARK: - Mapping-awareness helpers

    private var pageMappingLabels: [Int: String] {
        var result: [Int: String] = [:]
        for q in questions {
            guard let raw = q.questionLabel, let range = pageRangeFromLabel(raw) else { continue }
            let cleaned = cleanLabel(raw)
            for idx in range { result[idx] = cleaned }
        }
        return result
    }

    private func pageRangeFromLabel(_ label: String) -> ClosedRange<Int>? {
        guard let open  = label.lastIndex(of: "["),
              let close = label.lastIndex(of: "]"),
              open < close else { return nil }
        let annotation = String(label[label.index(after: open)..<close])
        guard let dot = annotation.firstIndex(of: ".") else { return nil }
        let numPart = String(annotation[annotation.index(after: dot)...])
        if numPart.contains("-") {
            let parts = numPart.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, parts[0] > 0 else { return nil }
            return (parts[0] - 1)...(parts[1] - 1)
        } else {
            guard let n = Int(numPart), n > 0 else { return nil }
            return (n - 1)...(n - 1)
        }
    }

    private func cleanLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s*\[p+\.\d.*?\]"#, with: "", options: .regularExpression)
           .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Key hint chip

    private func keyHint(_ key: String, _ description: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color(nsColor: .controlColor))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
    }

    // MARK: - Thumbnail strip

    private func thumbnailStrip(doc: PDFDocument) -> some View {
        let mappings  = pageMappingLabels
        let cellW     = CGFloat(thumbnailCellWidth)
        let columns   = [GridItem(.adaptive(minimum: cellW, maximum: cellW), spacing: 4)]
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<doc.pageCount, id: \.self) { idx in
                        if let page = doc.page(at: idx) {
                            ThumbnailCell(
                                page:         page,
                                pageIndex:    idx,
                                cellWidth:    cellW,
                                isSelected:   isInRange(idx),
                                isCurrent:    selectedPage == idx,
                                mappingLabel: mappings[idx]
                            ) { shiftHeld in
                                handleThumbnailTap(idx: idx, shiftHeld: shiftHeld)
                            }
                            .id(idx)
                        }
                    }
                }
                .padding(6)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            // Pinch-to-zoom resizes thumbnails.  We record the cell width at
            // gesture-start so the scale stays relative (same feel as Photos).
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if thumbPinchBase == nil { thumbPinchBase = thumbnailCellWidth }
                        let base = thumbPinchBase ?? thumbnailCellWidth
                        thumbnailCellWidth = min(240, max(60, base * scale))
                    }
                    .onEnded { _ in
                        thumbPinchBase = nil
                    }
            )
            // Arrow-key navigation works whether the user clicked a thumbnail
            // (focus shifts here) or the PDF canvas (handled by the NSEvent monitor).
            .focusable()
            .focused($thumbnailFocused)
            .focusEffectDisabled()  // no blue focus ring on a scroll view
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let isUp  = press.key == .upArrow
                let cmd   = press.modifiers.contains(.command)
                let shift = press.modifiers.contains(.shift)
                navigatePage(up: isUp, cmd: cmd, shift: shift)
                return .handled
            }
            .onChange(of: selectedPage) { _, newPage in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newPage, anchor: .center)
                }
            }
        }
    }

    // MARK: - Existing mappings table

    private var mappingsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mappings")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                // Order validity indicator
                if let valid = mappingOrderValid {
                    Circle()
                        .fill(valid ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
                        .frame(width: 7, height: 7)
                        .help(valid
                              ? "Questions are in order"
                              : "Question order looks wrong — check for gaps or out-of-sequence labels")
                        .animation(.smooth(duration: 0.3), value: valid)
                }

                Spacer()
                if !questions.isEmpty {
                    Button {
                        clearAllMappings()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                    .buttonStyle(.plain)
                    .help("Clear all mappings")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if questions.isEmpty {
                Text("No mappings yet")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(questions, id: \.id) { q in
                            mappingRow(q)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal:   .move(edge: .leading).combined(with: .opacity)
                                ))
                            Divider()
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: questions.map(\.id))
                }
                .frame(maxHeight: 200)

                Divider()

                // Total marks footer
                let total = questions.reduce(0) { $0 + Int($1.maxMarks) }
                HStack {
                    Text("Total")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Spacer()
                    Text("\(total)mk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func mappingRow(_ q: QuestionStructureMO) -> some View {
        let raw   = q.questionLabel ?? ""
        let label = cleanLabel(raw)
        let range: String = {
            guard let r = pageRangeFromLabel(raw) else { return "—" }
            return r.count == 1 ? "p.\(r.lowerBound + 1)" : "pp.\(r.lowerBound + 1)-\(r.upperBound + 1)"
        }()

        return HStack(spacing: 4) {
            Button {
                if let r = pageRangeFromLabel(raw) { selectedPage = r.lowerBound }
            } label: {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Jump to \(range)")

            Text(range)
                .font(.system(size: 9))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)

            Spacer()

            Text("\(q.maxMarks)mk")
                .font(.system(size: 9))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

            Button {
                ctx.delete(q)
                PersistenceController.shared.save()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed).opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete mapping")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - Page canvas

    private func pageCanvas(doc: PDFDocument) -> some View {
        VStack(spacing: 0) {
            if let existingLabel = pageMappingLabels[selectedPage] {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text("Page \(selectedPage + 1) is mapped as")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Text(existingLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Spacer()
                    Text("Re-select a range to remap")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .systemGreen).opacity(0.08))
                Divider()
            }

            PDFPageView(
                document:           doc,
                pageIndex:          selectedPage,
                zoomFactor:         CGFloat(zoomFactor),
                lastKnownFitScale:  lastFitScale,
                onPageChanged:      { newPage in selectedPage = newPage },
                onFitScaleComputed: { scale in lastFitScale = scale }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Text("Page \(selectedPage + 1) of \(doc.pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Mapping form

    private var mappingForm: some View {
        HStack(spacing: 12) {
            let rangeStr: String = {
                guard let r = selectedRange else { return "—" }
                return r.count == 1
                    ? "p.\(r.lowerBound + 1)"
                    : "pp.\(r.lowerBound + 1)-\(r.upperBound + 1)"
            }()

            Text("Map \(rangeStr):")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()

            TextField("Label  e.g. Q1, 4a", text: $mappingLabel)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .focused($labelFocused)
                .onSubmit { }

            if activeTab == .questionPaper {
                TextField("Marks", text: $mappingMarks)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 72)
                    .onSubmit { commitMappingIfValid() }
            }

            Button("Map") { commitMappingIfValid() }
                .keyboardShortcut(.return, modifiers: .command)
                .controlSize(.regular)
                .disabled(mappingLabel.trimmingCharacters(in: .whitespaces).isEmpty
                          || (activeTab == .questionPaper && Int16(mappingMarks) == nil))

            Divider().frame(height: 22)

            Button("Clear") {
                selectedRange = nil
                rangeAnchor   = nil
                mappingLabel  = ""
                mappingMarks  = ""
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Interaction

    private func handleThumbnailTap(idx: Int, shiftHeld: Bool) {
        if shiftHeld, let anchor = rangeAnchor {
            selectedRange = min(anchor, idx)...max(anchor, idx)
        } else {
            rangeAnchor   = idx
            selectedRange = idx...idx
        }
        selectedPage     = idx
        thumbnailFocused = true   // give keyboard focus so ↑/↓ navigate immediately
    }

    private func isInRange(_ idx: Int) -> Bool {
        selectedRange?.contains(idx) ?? false
    }

    // MARK: - Page navigation (shared by keyboard monitor and thumbnail strip)

    private func navigatePage(up: Bool, cmd: Bool, shift: Bool) {
        guard let doc = cachedDoc, doc.pageCount > 0 else { return }
        let pageCount = doc.pageCount
        let newPage: Int
        if up {
            newPage = cmd ? 0 : max(0, selectedPage - 1)
        } else {
            newPage = cmd ? pageCount - 1 : min(pageCount - 1, selectedPage + 1)
        }
        if shift {
            if rangeAnchor == nil { rangeAnchor = selectedPage }
            selectedPage = newPage
            if let anchor = rangeAnchor {
                selectedRange = min(anchor, selectedPage)...max(anchor, selectedPage)
            }
        } else {
            selectedPage = newPage
            rangeAnchor  = newPage
        }
    }

    // MARK: - Keyboard event (forwarded from NSEvent monitor)

    private func handleMappingKeyEvent(_ event: NSEvent) {
        let code  = event.keyCode
        let cmd   = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch code {
        case 126: navigatePage(up: true,  cmd: cmd, shift: shift)   // ↑
        case 125: navigatePage(up: false, cmd: cmd, shift: shift)   // ↓
        default:  break
        }
    }

    // MARK: - Commit mapping

    private func commitMappingIfValid() {
        guard let r = selectedRange else { return }
        let rawLabel = mappingLabel.trimmingCharacters(in: .whitespaces)
        guard !rawLabel.isEmpty else { return }
        if activeTab == .questionPaper {
            guard Int16(mappingMarks.trimmingCharacters(in: .whitespaces)) != nil else { return }
        }
        let rangeStr = r.count == 1
            ? "p.\(r.lowerBound + 1)"
            : "pp.\(r.lowerBound + 1)-\(r.upperBound + 1)"
        commitMapping(rangeStr: rangeStr)
    }

    private func commitMapping(rangeStr: String) {
        let rawLabel = mappingLabel.trimmingCharacters(in: .whitespaces)
        guard !rawLabel.isEmpty else { return }

        let activeSource = activeTab == .questionPaper ? "questionPaper" : "markScheme"

        // For mark scheme, inherit marks from the matching question paper entry.
        let marks: Int16
        if activeTab == .questionPaper {
            guard let m = Int16(mappingMarks.trimmingCharacters(in: .whitespaces)) else { return }
            marks = m
        } else {
            let qpStructures = (paper.questionStructures as? Set<QuestionStructureMO> ?? [])
                .filter { ($0.source ?? "questionPaper") == "questionPaper" }
            marks = qpStructures.first { cleanLabel($0.questionLabel ?? "") == rawLabel }?.maxMarks ?? 0
        }

        let fullLabel = "\(rawLabel) [\(rangeStr)]"
        let order = Int16(questions.count)

        QuestionStructureMO.insert(
            label:        fullLabel,
            maxMarks:     marks,
            displayOrder: order,
            source:       activeSource,
            paper:        paper,
            in:           ctx
        )
        PersistenceController.shared.save()

        mappingLabel  = ""
        mappingMarks  = ""

        // Advance to the page immediately after the mapped range so the user
        // can start selecting the next question without manually navigating.
        if let r = pageRangeFromLabel(fullLabel) {
            let nextPage = min(r.upperBound + 1, (cachedDoc?.pageCount ?? 1) - 1)
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPage  = nextPage
                rangeAnchor   = nextPage
                selectedRange = nextPage...nextPage
            }
        } else {
            selectedRange = nil
            rangeAnchor   = nil
        }
    }

    private func clearAllMappings() {
        for q in questions { ctx.delete(q) }
        PersistenceController.shared.save()
    }
}

// MARK: - Grade threshold sheet (shown after mapping via Proceed)

private struct MappingThresholdSheet: View {

    @ObservedObject var paper: PaperMO
    @Binding var isPresented: Bool
    var onDone: (() -> Void)? = nil
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

    private var threshold: GradeThresholdTableMO? {
        (paper.gradeThresholds as? Set<GradeThresholdTableMO>)?.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grade Thresholds")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(paper.subject?.name ?? "") · \(paper.normalizedSeries.flatMap { SeriesNormalizationEngine.displayName(from: $0) } ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    isPresented = false
                    onDone?()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusEffectDisabled()
            }

            Divider()

            // Form — threshold is guaranteed to exist by onAppear
            VStack(alignment: .leading, spacing: 10) {
                    thresholdRow("Max Marks", binding: $maxMarksStr, field: .maxMarks,
                                 next: { focus = hasAStar ? .aStar : .a },
                                 placeholder: "e.g. 75", isHeader: true)

                    Toggle("Include A* Grade", isOn: $hasAStar)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .focusEffectDisabled()

                    Divider()

                    if hasAStar { thresholdRow("A*", binding: $aStarStr, field: .aStar, next: { focus = .a }) }
                    thresholdRow("A",  binding: $aStr,  field: .a, next: { focus = .b })
                    thresholdRow("B",  binding: $bStr,  field: .b, next: { focus = .c })
                    thresholdRow("C",  binding: $cStr,  field: .c, next: { focus = .d })
                    thresholdRow("D",  binding: $dStr,  field: .d, next: { focus = .e })
                    thresholdRow("E",  binding: $eStr,  field: .e, next: { saveThresholds(); focus = nil })

                    Button {
                        saveThresholds()
                        focus = nil
                        withAnimation(.smooth(duration: 0.25)) { didSave = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.smooth(duration: 0.3)) { didSave = false }
                        }
                    } label: {
                        Label(didSave ? "Saved" : "Save Thresholds",
                              systemImage: didSave ? "checkmark" : "square.and.arrow.down")
                            .animation(.smooth(duration: 0.2), value: didSave)
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.regular)
            }

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 340, idealWidth: 380, minHeight: 420)
        .onAppear {
            // Auto-create the threshold record so the form is always ready.
            if threshold == nil, let norm = paper.normalizedSeries {
                _ = GradeThresholdTableMO.insert(rawSeriesKey: norm, paper: paper, in: ctx)
                PersistenceController.shared.save()
            }
            loadThresholds()
        }
        .onChange(of: threshold?.objectID) { _, _ in loadThresholds() }
    }

    private func thresholdRow(_ label: String, binding: Binding<String>,
                               field: Field, next: @escaping () -> Void,
                               placeholder: String = "Min marks",
                               isHeader: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(isHeader
                      ? .system(size: 12)
                      : .system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(isHeader ? Color.secondary : Color.primary)
                .frame(width: 90, alignment: .trailing)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .font(.system(size: 13))
                .focused($focus, equals: field)
                .onSubmit { next() }
        }
    }

    private func loadThresholds() {
        guard let t = threshold else { return }
        maxMarksStr = t.maxPossibleMarks > 0 ? "\(t.maxPossibleMarks)" : ""
        hasAStar    = t.hasAStar
        aStarStr    = t.markAStar > 0 ? "\(t.markAStar)" : ""
        aStr        = t.markA     > 0 ? "\(t.markA)"     : ""
        bStr        = t.markB     > 0 ? "\(t.markB)"     : ""
        cStr        = t.markC     > 0 ? "\(t.markC)"     : ""
        dStr        = t.markD     > 0 ? "\(t.markD)"     : ""
        eStr        = t.markE     > 0 ? "\(t.markE)"     : ""
    }

    private func saveThresholds() {
        guard let t = threshold else { return }
        if let v = Int16(maxMarksStr) { t.maxPossibleMarks = v }
        t.hasAStar = hasAStar
        if let v = Int16(aStarStr) { t.markAStar = v }
        if let v = Int16(aStr)     { t.markA     = v }
        if let v = Int16(bStr)     { t.markB     = v }
        if let v = Int16(cStr)     { t.markC     = v }
        if let v = Int16(dStr)     { t.markD     = v }
        if let v = Int16(eStr)     { t.markE     = v }
        PersistenceController.shared.save()
    }
}

// MARK: - Thumbnail cell

private struct ThumbnailCell: View {

    let page:         PDFPage
    let pageIndex:    Int
    let cellWidth:    CGFloat
    let isSelected:   Bool
    let isCurrent:    Bool
    let mappingLabel: String?
    let onTap:        (_ shiftHeld: Bool) -> Void

    private var thumbnail: NSImage { makeHighDensityThumbnail(page, targetWidth: max(cellWidth, 60)) }

    private func makeHighDensityThumbnail(_ pdfPage: PDFPage, targetWidth: CGFloat) -> NSImage {
        let pageBounds  = pdfPage.bounds(for: .mediaBox)
        let scale       = targetWidth / max(pageBounds.width, 1)
        let targetSize  = CGSize(width: targetWidth, height: pageBounds.height * scale)
        let density: CGFloat = 2.0
        let pixelW = Int(targetSize.width * density)
        let pixelH = Int(targetSize.height * density)

        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pdfPage.thumbnail(of: targetSize, for: .mediaBox) }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelW), height: CGFloat(pixelH)))
        ctx.scaleBy(x: scale * density, y: scale * density)
        pdfPage.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else { return pdfPage.thumbnail(of: targetSize, for: .mediaBox) }
        return NSImage(cgImage: cgImage, size: targetSize)
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: cellWidth)
                .overlay(
                    RoundedRectangle(cornerRadius: 3).stroke(
                        isSelected
                            ? Color.accentColor
                            : (isCurrent ? Color(nsColor: .separatorColor) : Color.clear),
                        lineWidth: isSelected ? 2 : 1
                    )
                )
                .background(
                    isSelected ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .overlay(alignment: .topLeading) {
                    if mappingLabel != nil {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .systemGreen).opacity(0.12))
                    }
                }

            HStack(spacing: 4) {
                Text("\(pageIndex + 1)")
                    .font(.system(size: min(11, max(8, cellWidth / 13))))
                    .foregroundStyle(.secondary)

                if let lbl = mappingLabel, cellWidth >= 90 {
                    Text(lbl)
                        .font(.system(size: min(10, max(7, cellWidth / 15)), weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color(nsColor: .systemGreen).opacity(0.18))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .frame(width: cellWidth)
        .overlay(ClickCatcher(onTap: onTap))
    }
}

// MARK: - ClickCatcher

private struct ClickCatcher: NSViewRepresentable {

    let onTap: (_ shiftHeld: Bool) -> Void

    func makeNSView(context: Context) -> _ClickView {
        let v = _ClickView()
        v.onTap = onTap
        return v
    }

    func updateNSView(_ nsView: _ClickView, context: Context) {
        nsView.onTap = onTap
    }

    final class _ClickView: NSView {
        var onTap: ((_ shiftHeld: Bool) -> Void)?
        override func mouseDown(with event: NSEvent) {
            onTap?(event.modifierFlags.contains(.shift))
        }
    }
}

// MARK: - PDFPageView (continuous scroll with sticky zoom and fit-to-page default)

private struct PDFPageView: NSViewRepresentable {

    let document:           PDFDocument
    let pageIndex:          Int
    let zoomFactor:         CGFloat   // 0 = fit-to-page (computed); >0 = explicit scale
    let lastKnownFitScale:  CGFloat   // best-guess scale passed in from @State to prevent flash
    let onPageChanged:      (Int) -> Void
    let onFitScaleComputed: (CGFloat) -> Void

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode        = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor    = .windowBackgroundColor
        // ⚠️  Set document FIRST, then disable autoScales.
        // PDFKit resets autoScales→true internally when a document is assigned;
        // setting it before the document has no lasting effect.
        v.document           = document
        v.autoScales         = false

        let c = context.coordinator
        c.pdfView            = v
        c.onPageChanged      = onPageChanged
        c.onFitScaleComputed = onFitScaleComputed
        c.document           = document

        NotificationCenter.default.addObserver(
            c,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: v
        )

        // Navigate to initial page without firing our onChange handler.
        if let page = document.page(at: pageIndex) {
            c.suppressNotification = true
            v.go(to: page)
            c.suppressNotification = false
            c.lastSetIndex = pageIndex
        }

        if zoomFactor > 0 {
            // Explicit zoom stored from a previous session.
            v.scaleFactor  = zoomFactor
            c.desiredScale = zoomFactor
        } else {
            // Apply a best-guess scale immediately so the user never sees the
            // full-width flash while the real fit-to-page computation defers.
            let guess      = lastKnownFitScale > 0.1 ? lastKnownFitScale : 0.75
            v.scaleFactor  = guess
            c.desiredScale = guess
            // Refine once the view has been laid out.
            let coordinator = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak v] in
                guard let v else { return }
                coordinator.applyFitToPage(v)
            }
        }

        return v
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let c = context.coordinator
        c.onPageChanged      = onPageChanged
        c.onFitScaleComputed = onFitScaleComputed

        // ── Document swap (tab switch or path change) ────────────────────────
        let docChanged = nsView.document !== document
        if docChanged {
            c.suppressNotification = true
            c.lastSetIndex         = -1
            nsView.document        = document
            nsView.autoScales      = false   // re-assert; PDFKit resets on doc swap
            c.document             = document
            c.suppressNotification = false
        }

        // ── Page navigation ──────────────────────────────────────────────────
        // When page change came from the user scrolling, pageChanged() already
        // updated lastSetIndex synchronously, so pageIndex == lastSetIndex and
        // we skip the go(to:) call — scale is preserved without touching it.
        // When navigation is from a thumbnail click, go(to:) scrolls the view;
        // we then re-assert desiredScale in case PDFKit reset it.
        if pageIndex != c.lastSetIndex {
            if let page = document.page(at: pageIndex), nsView.currentPage != page {
                c.suppressNotification = true
                nsView.go(to: page)
                c.suppressNotification = false
                // go(to:) can trigger a PDFKit layout that re-applies autoScales.
                let target = c.desiredScale
                if target > 0 {
                    DispatchQueue.main.async { [weak nsView] in
                        guard let v = nsView else { return }
                        v.autoScales = false
                        if abs(v.scaleFactor - target) > 0.001 { v.scaleFactor = target }
                    }
                }
            }
            c.lastSetIndex = pageIndex
        }

        // ── Zoom state machine ───────────────────────────────────────────────
        let fitMode    = zoomFactor == 0
        let fitChanged = fitMode != c.lastFitMode
        c.lastFitMode  = fitMode

        if fitMode {
            if docChanged || fitChanged {
                let coordinator = c
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak nsView] in
                    guard let v = nsView else { return }
                    coordinator.applyFitToPage(v)
                }
            }
            // Pure page navigation in fit mode: desiredScale is re-asserted by
            // pageChanged() if PDFKit resets it on the page-change layout pass.
        } else {
            nsView.autoScales  = false
            nsView.scaleFactor = zoomFactor
            c.desiredScale     = zoomFactor
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        weak var pdfView:           PDFView?
        var document:               PDFDocument?
        var onPageChanged:          ((Int) -> Void)?
        var onFitScaleComputed:     ((CGFloat) -> Void)?
        var lastSetIndex:           Int     = -1
        var suppressNotification:   Bool    = false
        var lastFitMode:            Bool    = true   // matches default zoomFactor == 0
        /// Last scale we successfully applied. Re-asserted on every PDFViewPageChanged
        /// so a PDFKit-internal layout pass cannot silently reset our zoom.
        var desiredScale:           CGFloat = 0

        /// Computes the scale that fits the current page entirely inside the
        /// PDFView's visible bounds (min of fit-to-height and fit-to-width with margin).
        /// Retries up to 10 times if the view has not been laid out yet.
        func applyFitToPage(_ v: PDFView, attempt: Int = 0) {
            guard let page = v.currentPage ?? v.document?.page(at: 0) else { return }
            let pageBounds = page.bounds(for: .mediaBox)
            let viewSize   = v.bounds.size
            guard viewSize.height > 20, pageBounds.height > 0, pageBounds.width > 0 else {
                if attempt < 10 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak v] in
                        guard let self, let v else { return }
                        self.applyFitToPage(v, attempt: attempt + 1)
                    }
                }
                return
            }
            let margin: CGFloat = 24
            let scaleH = (viewSize.height - margin) / pageBounds.height
            let scaleW = (viewSize.width  - margin) / pageBounds.width
            let scale  = max(0.25, min(scaleH, scaleW))
            v.autoScales  = false
            v.scaleFactor = scale
            desiredScale  = scale
            onFitScaleComputed?(scale)
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !suppressNotification,
                  let v    = notification.object as? PDFView,
                  let page = v.currentPage,
                  let doc  = document
            else { return }

            // Re-assert our scale — PDFKit may reset scaleFactor during its
            // internal page-change layout pass (especially when autoScales was
            // previously true, e.g. right after a document assignment).
            let target = desiredScale
            if target > 0 {
                DispatchQueue.main.async { [weak v] in
                    guard let v else { return }
                    v.autoScales = false
                    if abs(v.scaleFactor - target) > 0.001 { v.scaleFactor = target }
                }
            }

            let idx = doc.index(for: page)
            lastSetIndex = idx
            DispatchQueue.main.async { [weak self] in self?.onPageChanged?(idx) }
        }
    }
}
