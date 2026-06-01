import SwiftUI
import PDFKit
import CoreData

// MARK: - ePEN Marking Window Controller

/// Manages standalone ePEN marking workspace windows — one per attempt.
///
/// Calling `open(attempt:)` raises the existing window when one is already
/// open for that attempt rather than spawning a duplicate.
final class EPENMarkingWindowController: NSWindowController, NSWindowDelegate {

    private static var liveControllers: [EPENMarkingWindowController] = []

    @MainActor
    static func open(attempt: AttemptMO) {
        if let existing = liveControllers.first(where: { $0.attemptID == attempt.objectID }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: false)
            return
        }
        let ctrl = EPENMarkingWindowController(attempt: attempt)
        liveControllers.append(ctrl)
        ctrl.showWindow(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private let attemptID: NSManagedObjectID

    init(attempt: AttemptMO) {
        self.attemptID = attempt.objectID

        let ctx         = PersistenceController.shared.container.viewContext
        let subjectName = attempt.paper?.subject?.name ?? "ePEN Marking"
        let barcode     = attempt.barcodeValue ?? "—"

        let rootView = EPENMarkingView(attempt: attempt)
            .environment(\.managedObjectContext, ctx)

        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title               = "\(subjectName)  —  \(barcode)  ·  ePEN Marking"
        window.setContentSize(NSSize(width: 1280, height: 700))
        window.minSize             = NSSize(width: 900, height: 520)
        window.styleMask           = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
        ]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    func windowWillClose(_ notification: Notification) {
        Self.liveControllers.removeAll { $0 === self }
    }
}

// MARK: - ePEN Marking View

/// Three-pane marking workspace:
///
///  • **Left** — Question Paper PDF, auto-scrolled to the current question's pages.
///  • **Centre** — Mark Scheme PDF, auto-scrolled to the matching answer pages.
///  • **Right** — Sequential question list with numeric mark entry.
struct EPENMarkingView: View {

    @ObservedObject var attempt: AttemptMO
    @Environment(\.managedObjectContext) private var ctx

    // ── Session state ──────────────────────────────────────────────────────
    /// Per-question marks keyed by stripped label.
    @State private var marks:      [String: Double] = [:]
    @State private var currentIdx: Int              = 0
    @FocusState private var focusedIdx: Int?

    // ── Cached PDF documents ───────────────────────────────────────────────
    @State private var qpDoc:      PDFDocument? = nil
    @State private var qpPath:     String?      = nil
    @State private var msDoc:      PDFDocument? = nil
    @State private var msPath:     String?      = nil

    @State private var feedback:   String?      = nil

    // MARK: - Derived question lists

    /// QP questions, sorted by displayOrder, deduplicated by stripped label.
    /// Handles old data where both QP+MS entries may have source = nil.
    private var qpQuestions: [QuestionStructureMO] {
        let all = (attempt.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
            .filter { ($0.source ?? "questionPaper") == "questionPaper" }
            .sorted { $0.displayOrder < $1.displayOrder }
        var seen = Set<String>()
        return all.filter { q in
            let key = cleanLabel(q.questionLabel)
            return seen.insert(key).inserted
        }
    }

    /// MS questions keyed by stripped label → first matching entry.
    private var msQuestionByLabel: [String: QuestionStructureMO] {
        let msAll = (attempt.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
            .filter { $0.source == "markScheme" }
        var dict: [String: QuestionStructureMO] = [:]
        for q in msAll {
            let key = cleanLabel(q.questionLabel)
            if dict[key] == nil { dict[key] = q }
        }
        return dict
    }

    private var totalMaxMarks: Int { qpQuestions.reduce(0) { $0 + Int($1.maxMarks) } }
    private var earnedTotal: Double { marks.values.reduce(0, +) }

    /// 0-based QP PDF page for the currently active question.
    private var activeQPPage: Int {
        guard qpQuestions.indices.contains(currentIdx) else { return 0 }
        return firstPageIndex(from: qpQuestions[currentIdx].questionLabel) ?? 0
    }

    /// 0-based MS PDF page for the currently active question (if MS is mapped).
    private var activeMSPage: Int {
        guard qpQuestions.indices.contains(currentIdx) else { return 0 }
        let lbl = cleanLabel(qpQuestions[currentIdx].questionLabel)
        return firstPageIndex(from: msQuestionByLabel[lbl]?.questionLabel) ?? 0
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // ── Left: Scanned student paper (falls back to original QP) ─
            pdfPane(
                doc:       qpDoc,
                pageIndex: activeQPPage,
                title:     attempt.scannedFilePath != nil ? "Scanned Paper" : "Question Paper",
                emptyMsg:  "No scanned paper — drop the student's PDF in Complete Logs first"
            )
            .frame(minWidth: 320)

            // ── Centre: MS ──────────────────────────────────────────────
            pdfPane(
                doc:       msDoc,
                pageIndex: activeMSPage,
                title:     "Mark Scheme",
                emptyMsg:  "No Mark Scheme PDF linked"
            )
            .frame(minWidth: 280)

            // ── Right: mark entry ────────────────────────────────────────
            markEntryPane
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            reloadDocuments()
            initMarks()
        }
        .onChange(of: attempt.objectID) { _, _ in
            reloadDocuments()
            initMarks()
        }
        .onChange(of: currentIdx) { _, newIdx in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedIdx = newIdx
            }
        }
    }

    // MARK: - PDF pane (reusable for both QP and MS)

    @ViewBuilder
    private func pdfPane(doc: PDFDocument?, pageIndex: Int,
                         title: String, emptyMsg: String) -> some View {
        VStack(spacing: 0) {
            // Tiny header label
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .textCase(.uppercase)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                Spacer()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            if let doc {
                EPENPDFPageView(document: doc, pageIndex: pageIndex)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(emptyMsg)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    // MARK: - Right pane — mark entry

    private var markEntryPane: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(attempt.paper?.subject?.name ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(attempt.barcodeValue ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let norm = attempt.paper?.normalizedSeries {
                        Text("·").foregroundStyle(Color(nsColor: .separatorColor))
                        Text(SeriesNormalizationEngine.displayName(from: norm))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                    }
                }

                Divider().padding(.top, 2)

                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Score")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        Text(String(format: "%.0f / %d", earnedTotal, totalMaxMarks))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Percentage")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        let pct = totalMaxMarks > 0
                            ? earnedTotal / Double(totalMaxMarks) * 100 : 0.0
                        Text(String(format: "%.1f%%", pct))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(pct >= 70
                                ? Color(nsColor: .systemGreen)
                                : (pct >= 50 ? Color(nsColor: .systemOrange)
                                             : Color(nsColor: .systemRed)))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Column header
            if !qpQuestions.isEmpty {
                HStack(spacing: 0) {
                    Spacer().frame(width: 22)
                    Text("Question")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Marks")
                        .frame(width: 92, alignment: .center)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }

            // Question list
            if qpQuestions.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No question structure defined")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Add questions in Papers Mapping → Question Structure.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(Array(qpQuestions.enumerated()), id: \.element.id) { idx, q in
                                markRow(idx: idx, q: q)
                                    .id(idx)
                                Divider()
                            }
                        }
                    }
                    .onChange(of: currentIdx) { _, newIdx in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Save row
            HStack(spacing: 10) {
                if let fb = feedback {
                    Label(fb, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                }
                Spacer()
                Button("Save Score  [⌘S]") { saveScore() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(BlueGlassButtonStyle())
                    .disabled(qpQuestions.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Question row

    @ViewBuilder
    private func markRow(idx: Int, q: QuestionStructureMO) -> some View {
        let lbl       = cleanLabel(q.questionLabel)
        let maxM      = Int(q.maxMarks)
        let isCurrent = idx == currentIdx

        let markBind = Binding<String>(
            get: {
                let v = marks[lbl] ?? 0
                return v > 0 ? String(Int(v)) : ""
            },
            set: { str in
                let raw    = Double(str.trimmingCharacters(in: .whitespaces)) ?? 0
                marks[lbl] = min(max(raw, 0), Double(maxM))
            }
        )

        HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(lbl)
                    .font(.system(size: 12,
                                  weight: isCurrent ? .semibold : .regular,
                                  design: .monospaced))
                    .foregroundStyle(isCurrent
                        ? Color(nsColor: .labelColor)
                        : Color(nsColor: .secondaryLabelColor))
                // Show QP page hint
                if let hint = pageAnnotation(q.questionLabel) {
                    Text("QP: \(hint)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                // Show MS page hint if available
                let msQ = msQuestionByLabel[lbl]
                if let msHint = pageAnnotation(msQ?.questionLabel) {
                    Text("MS: \(msHint)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(nsColor: .systemGreen).opacity(0.8))
                }
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("—", text: markBind)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
                    .focused($focusedIdx, equals: idx)
                    .onSubmit { advanceToNext() }

                Text("/ \(maxM)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            currentIdx = idx
            focusedIdx = idx
        }
    }

    // MARK: - Document lifecycle

    private func reloadDocuments() {
        // Left pane: the student's scanned/submitted paper (for digital marking).
        // Falls back to the original QP PDF if no scan has been checked in yet.
        let newQPPath = attempt.scannedFilePath
            ?? attempt.paper?.questionPaperPDFPath
            ?? ""
        if newQPPath != qpPath {
            qpPath = newQPPath
            qpDoc  = newQPPath.isEmpty ? nil : PDFDocument(url: URL(filePath: newQPPath))
        }
        let newMSPath = attempt.paper?.markSchemePDFPath ?? ""
        if newMSPath != msPath {
            msPath = newMSPath
            msDoc  = newMSPath.isEmpty ? nil : PDFDocument(url: URL(filePath: newMSPath))
        }
    }

    // MARK: - Session control

    private func initMarks() {
        var m: [String: Double] = [:]
        for q in qpQuestions { m[cleanLabel(q.questionLabel)] = 0 }
        marks      = m
        currentIdx = 0
        feedback   = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focusedIdx = 0 }
    }

    private func advanceToNext() {
        if currentIdx < qpQuestions.count - 1 {
            currentIdx += 1
        } else {
            saveScore()
        }
    }

    private func saveScore() {
        let total          = marks.values.reduce(0, +)
        attempt.totalScore = total
        PersistenceController.shared.save()
        feedback = String(format: "Saved  %.0f / %d", total, totalMaxMarks)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            feedback = nil
        }
    }

    // MARK: - Label helpers

    /// Strips `[pp.X-Y]` / `[p.X]` page range annotations.
    private func cleanLabel(_ raw: String?) -> String {
        guard let raw else { return "?" }
        return raw
            .replacingOccurrences(of: #"\s*\[pp?\..+?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Returns just the `[pp.X-Y]` annotation portion, or nil if absent.
    private func pageAnnotation(_ raw: String?) -> String? {
        guard let raw,
              let r = raw.range(of: #"\[pp?\..+?\]"#, options: .regularExpression)
        else { return nil }
        return String(raw[r])
    }

    /// Converts a `[pp.X-Y]` / `[p.X]` annotation to a 0-based PDF page index.
    private func firstPageIndex(from label: String?) -> Int? {
        guard let label,
              let bracketRange = label.range(of: #"\[pp?\."#, options: .regularExpression)
        else { return nil }
        let tail   = label[bracketRange.upperBound...]
        let digits = tail.prefix(while: { $0.isNumber })
        guard let pageNum = Int(digits), pageNum > 0 else { return nil }
        return pageNum - 1
    }
}

// MARK: - ePEN PDF page view

private struct EPENPDFPageView: NSViewRepresentable {

    let document:  PDFDocument
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode        = .singlePageContinuous
        v.autoScales         = true
        v.displaysPageBreaks = true
        v.backgroundColor    = .windowBackgroundColor
        v.document           = document
        if let page = document.page(at: pageIndex) { v.go(to: page) }
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        if let page = document.page(at: pageIndex), nsView.currentPage != page {
            nsView.go(to: page)
        }
    }
}
