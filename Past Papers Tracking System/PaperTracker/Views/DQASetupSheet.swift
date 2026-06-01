import SwiftUI
import CoreData
import PDFKit
import UniformTypeIdentifiers

// MARK: - DQAFileManager

/// Filesystem helpers for DQA compiled PDF storage.
/// All DQA files live under: ~/Library/Application Support/PaperTracker/DQA/{dqaBarcode}/
enum DQAFileManager {

    static var dqaBaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("PaperTracker", isDirectory: true)
            .appendingPathComponent("DQA", isDirectory: true)
    }

    /// Returns (and creates if needed) the directory for a given DQA barcode.
    @discardableResult
    static func ensureDirectory(for dqaBarcode: String) throws -> URL {
        let dir = dqaBaseURL.appendingPathComponent(dqaBarcode, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Extracts pages referenced by `ranges` (1-indexed) from the PDF at `pdfPath`
    /// and writes a new PDF to `destURL`. Pages shared across multiple questions are
    /// deduplicated; ranges are extracted in document order.
    /// Returns `true` on success.
    static func extractPages(from pdfPath: String,
                             ranges: [ClosedRange<Int>],
                             to destURL: URL) -> Bool {
        guard let src = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else { return false }
        let result = PDFDocument()
        var destIdx = 0
        var seen = Set<Int>()
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            for page1 in range {
                guard seen.insert(page1).inserted else { continue }
                let page0 = page1 - 1
                guard page0 >= 0, page0 < src.pageCount,
                      let pg = src.page(at: page0) else { continue }
                result.insert(pg, at: destIdx)
                destIdx += 1
            }
        }
        guard destIdx > 0 else { return false }
        return result.write(to: destURL)
    }
}

// MARK: - DQASetupSheet

/// "Start a new DQA" sheet.
///
/// Track Alpha — manual subject/paper/attempt selection with question checklist.
/// Track Beta  — drop or open a scanned answer-sheet PDF whose filename encodes
///               the attempt barcode; the paper and question list are filled
///               automatically via a Core Data lookup.
///
/// On commit the sheet:
///   1. Outdates any existing active DQA for the same `originalBarcode`.
///   2. Creates a `DifficultQuestionsArchiveMO` record with the next
///      `dqaAttemptNumber`.
///   3. Extracts selected question pages from the linked QP and MS PDFs.
///   4. Saves and calls `onCreate` with the new record's object ID.
struct DQASetupSheet: View {

    /// Called after the DQA record is successfully created.
    var onCreate: (NSManagedObjectID) -> Void = { _ in }

    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    // MARK: Track

    enum SetupTrack: String, CaseIterable {
        case alpha = "Manual Entry"
        case beta  = "Drop Barcode PDF"
    }
    @State private var track: SetupTrack = .beta
    @Namespace private var trackNamespace

    // MARK: Track Alpha state

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \SubjectMO.name, ascending: true)])
    private var allSubjects: FetchedResults<SubjectMO>

    /// Backing text for the SearchableComboBox subject field.
    @State private var alphaSubjectText: String    = ""
    /// Selected SubjectMO from SearchableComboBox; synced → alphaSubjectID.
    @State private var alphaSubjectObj:  SubjectMO? = nil
    @State private var alphaSubjectID:  NSManagedObjectID? = nil
    @State private var alphaPaperID:    NSManagedObjectID? = nil
    @State private var alphaAttemptID:  NSManagedObjectID? = nil

    // MARK: Track Beta state

    @State private var betaIsTargeted  = false
    @State private var betaAttempt: AttemptMO? = nil
    @State private var betaError: String?      = nil

    // MARK: Shared state

    @State private var selectedQuestions: Set<String> = []
    @State private var previewDoc:        PDFDocument? = nil
    @State private var scrollToPage:      Int?         = nil
    @State private var committedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isSaving           = false
    @State private var saveError: String? = nil

    // MARK: Derived helpers

    private var alphaSubject: SubjectMO? { allSubjects.first { $0.objectID == alphaSubjectID } }

    private var alphaPapers: [PaperMO] {
        ((alphaSubject?.papers as? Set<PaperMO>) ?? [])
            .sorted { ($0.normalizedSeries ?? "") < ($1.normalizedSeries ?? "") }
    }

    private var alphaPaper: PaperMO? { alphaPapers.first { $0.objectID == alphaPaperID } }

    private var alphaAttempts: [AttemptMO] {
        ((alphaPaper?.attempts as? Set<AttemptMO>) ?? [])
            .sorted { $0.attemptNumber < $1.attemptNumber }
    }

    private var alphaAttempt: AttemptMO? { alphaAttempts.first { $0.objectID == alphaAttemptID } }

    private var activeAttempt: AttemptMO? { track == .alpha ? alphaAttempt : betaAttempt }
    private var activePaper:   PaperMO?   { activeAttempt?.paper }

    private var questionStructures: [QuestionStructureMO] {
        ((activePaper?.questionStructures as? Set<QuestionStructureMO>) ?? [])
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private var canCommit: Bool { activeAttempt != nil && !selectedQuestions.isEmpty && !isSaving }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            HSplitView {
                leftPane.frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
                rightPane.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            Divider()
            sheetFooter
        }
        .frame(width: 800, height: 620)
        .focusEffectDisabled()
        // Bridge: SearchableComboBox selection → existing ID-based logic
        .onChange(of: alphaSubjectObj) { _, s in alphaSubjectID = s?.objectID }
        .onChange(of: alphaSubjectID) { _ in alphaPaperID = nil; alphaAttemptID = nil; resetShared() }
        .onChange(of: alphaPaperID)   { _ in alphaAttemptID = alphaAttempts.last?.objectID; resetShared(); loadPreview() }
        .onChange(of: alphaAttemptID) { _ in resetShared(); loadPreview() }
        .onChange(of: betaAttempt)    { _ in resetShared(); loadPreview() }
        .onChange(of: track)          { _, _ in
            alphaSubjectText = ""; alphaSubjectObj = nil
            resetShared(); loadPreview()
        }
    }

    // MARK: - Header / Footer

    private var sheetHeader: some View {
        HStack {
            Text("Start a New DQA").font(.title2.bold())
            Spacer()
            // Glass pill track switcher — replaces segmented control
            HStack(spacing: 0) {
                ForEach(SetupTrack.allCases, id: \.self) { t in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { track = t }
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(track == t ? Color.primary : Color.secondary)
                            .animation(.smooth(duration: 0.2), value: track)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background {
                                if track == t {
                                    Capsule()
                                        .fill(Color(white: 0, opacity: 0.10))
                                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                        .matchedGeometryEffect(id: "dqaTrack", in: trackNamespace)
                                }
                            }
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .focusEffectDisabled()
                }
            }
            .padding(3)
            .glassEffect(in: Capsule())
            .focusEffectDisabled()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var sheetFooter: some View {
        HStack {
            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }
            Spacer()
            Button("Cancel", role: .cancel) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { dismiss() }
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .focusEffectDisabled()
            .keyboardShortcut(.escape)
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { commitDQA() }
            } label: {
                Text(isSaving ? "Creating…" : "Create DQA")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 7)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .foregroundStyle(Color.accentColor)
            .focusEffectDisabled()
            .disabled(!canCommit)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Left pane

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if track == .alpha { alphaForm } else { betaForm }
                if activeAttempt != nil {
                    Divider()
                    questionChecklist
                    if !selectedQuestions.isEmpty {
                        Divider()
                        committedDateRow
                    }
                }
                Spacer(minLength: 12)
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Track Alpha

    @ViewBuilder
    private var alphaForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Manual Entry", systemImage: "keyboard").font(.headline)
            formLabel("Subject")
            SearchableComboBox(
                text: $alphaSubjectText,
                selectedSubject: $alphaSubjectObj,
                subjects: Array(allSubjects),
                placeholder: "Type subject name…",
                autoFocus: track == .alpha
            )
            .frame(maxWidth: .infinity)

            if alphaSubject != nil {
                formLabel("Paper / Series")
                Picker("Paper", selection: $alphaPaperID) {
                    Text("Select series…").tag(NSManagedObjectID?.none)
                    ForEach(alphaPapers, id: \.objectID) { p in
                        Text(p.normalizedSeries.map { SeriesNormalizationEngine.displayName(from: $0) } ?? "")
                            .tag(Optional(p.objectID))
                    }
                }.labelsHidden().disabled(alphaPapers.isEmpty)
            }

            if alphaPaper != nil {
                if alphaAttempts.isEmpty {
                    Text("No attempts recorded for this paper.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    formLabel("Exam Attempt")
                    Picker("Attempt", selection: $alphaAttemptID) {
                        Text("Select attempt…").tag(NSManagedObjectID?.none)
                        ForEach(alphaAttempts, id: \.objectID) { a in
                            Text("ATT\(a.attemptNumber)  \(a.barcodeValue ?? "")").tag(Optional(a.objectID))
                        }
                    }.labelsHidden()
                }
            }
        }
    }

    // MARK: Track Beta

    @ViewBuilder
    private var betaForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Drop Barcode PDF", systemImage: "arrow.down.doc").font(.headline)
            Text("Drop or select the scanned answer-sheet PDF whose filename matches the attempt barcode (e.g. P3MATH-2024-10-ATT1.pdf). The paper and question list are filled automatically.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        betaIsTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 2, dash: [5])
                    )
                    .background(
                        betaIsTargeted ? Color.accentColor.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                if let a = betaAttempt {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
                        Text(a.barcodeValue ?? "").font(.system(size: 11, design: .monospaced))
                        Text(a.paper?.subject?.name ?? "").font(.caption).foregroundStyle(.secondary)
                        Button("Clear") { betaAttempt = nil; betaError = nil }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.red)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("Drop PDF here").font(.callout).foregroundStyle(.secondary)
                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { pickBetaFile() }
                        } label: {
                            Text("Choose file…")
                                .font(.system(size: 11))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                        }
                        .buttonStyle(GlassPillButtonStyle())
                        .glassEffect(in: Capsule())
                        .focusEffectDisabled()
                    }
                }
            }
            .frame(height: 120)
            .onDrop(of: [.fileURL], isTargeted: $betaIsTargeted) { providers in
                guard let p = providers.first else { return false }
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { processBetaURL(url) }
                }
                return true
            }

            if let err = betaError {
                Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
            }
        }
    }

    // MARK: Question checklist

    @ViewBuilder
    private var questionChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Question Selection").font(.headline)
                Spacer()
                if !questionStructures.isEmpty {
                    Button(selectedQuestions.count == questionStructures.count ? "Deselect All" : "Select All") {
                        if selectedQuestions.count == questionStructures.count {
                            selectedQuestions = []
                        } else {
                            selectedQuestions = Set(questionStructures.compactMap { $0.questionLabel })
                        }
                    }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                }
            }

            if questionStructures.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle.portrait").foregroundStyle(.tertiary)
                    Text("No page mapping found.\nGo to Papers Mapping to define page ranges first.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                ForEach(questionStructures, id: \.objectID) { q in
                    let label = q.questionLabel ?? ""
                    let isOn  = selectedQuestions.contains(label)
                    HStack(spacing: 8) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dqaDisplayLabel(label)).font(.system(size: 12)).lineLimit(1)
                            Text("\(q.maxMarks) mark\(q.maxMarks == 1 ? "" : "s")")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOn {
                            selectedQuestions.remove(label)
                        } else {
                            selectedQuestions.insert(label)
                            if let r = pageRange(from: label) { scrollToPage = r.lowerBound }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private var committedDateRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Committed Date").font(.headline)
            DatePicker("", selection: $committedDate, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact)
        }
    }

    // MARK: - Right pane (PDF preview)

    private var rightPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Question Paper Preview")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if activePaper != nil && activePaper?.questionPaperPDFPath == nil {
                    Label("No QP PDF linked", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            if let doc = previewDoc {
                DQAPDFPreviewView(document: doc, scrollToPage: scrollToPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(activeAttempt == nil
                         ? "Select a paper to preview question pages"
                         : "No Question Paper PDF linked to this paper")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 260)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func formLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func resetShared() { selectedQuestions = []; scrollToPage = nil }

    private func loadPreview() {
        guard let path = activePaper?.questionPaperPDFPath else { previewDoc = nil; return }
        previewDoc = PDFDocument(url: URL(fileURLWithPath: path))
    }

    private func pickBetaFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Select the scanned answer-sheet PDF"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            processBetaURL(url)
        }
    }

    private func processBetaURL(_ url: URL) {
        betaError = nil
        let name   = url.deletingPathExtension().lastPathComponent
        let tokens = name.components(separatedBy: "-")
        guard tokens.count >= 3, tokens.contains(where: { $0.uppercased().hasPrefix("ATT") }) else {
            betaError = "Filename doesn't match barcode format {SHORTCODE}-{SERIES}-ATT{N}"
            return
        }
        if let attempt = PersistenceController.shared.findAttempt(barcodeValue: name) {
            betaAttempt = attempt
        } else {
            betaError = "No matching attempt found for barcode: \(name)"
        }
    }

    /// Parses `[pp.X-Y]` or `[p.X]` out of a question label.
    func pageRange(from label: String) -> ClosedRange<Int>? {
        let pattern = #"\[pp\.(\d+)-(\d+)\]|\[p\.(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = label as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: label, range: fullRange) else { return nil }
        if m.range(at: 1).location != NSNotFound, m.range(at: 2).location != NSNotFound,
           let s = Int(ns.substring(with: m.range(at: 1))),
           let e = Int(ns.substring(with: m.range(at: 2))) {
            return s...e
        }
        if m.range(at: 3).location != NSNotFound,
           let p = Int(ns.substring(with: m.range(at: 3))) {
            return p...p
        }
        return nil
    }

    // MARK: - Commit

    private func commitDQA() {
        guard let attempt = activeAttempt,
              let paper   = attempt.paper,
              let subject = paper.subject else { saveError = "Invalid selection."; return }

        isSaving = true; saveError = nil

        let originalBarcode = attempt.barcodeValue ?? ""

        // Compute next dqaAttemptNumber
        let countReq = DifficultQuestionsArchiveMO.fetchRequest()
        countReq.predicate = NSPredicate(format: "originalBarcode == %@", originalBarcode)
        let existingCount = (try? ctx.count(for: countReq)) ?? 0
        let dqaN = Int16(existingCount + 1)

        // Outdate any existing active records for the same barcode
        DifficultQuestionsArchiveMO.outdateAll(originalBarcode: originalBarcode, in: ctx)

        // Create new DQA record
        let dqa = DifficultQuestionsArchiveMO.insert(
            originalBarcode: originalBarcode,
            dqaAttemptNumber: dqaN,
            subject: subject.name ?? "",
            examSeries: paper.normalizedSeries ?? "",
            paperType: attempt.paperType,
            parentExamAttemptNumber: attempt.attemptNumber,
            originalCompletedTimestamp: attempt.completedTimestamp,
            in: ctx
        )
        dqa.committedDate = Calendar.current.startOfDay(for: committedDate)
        dqa.decodedSourceQuestions = Array(selectedQuestions).sorted()

        // Extract PDF pages
        let dqaBarcode = dqa.dqaBarcode ?? ""
        let ranges = Array(selectedQuestions).compactMap { pageRange(from: $0) }

        do {
            let dir = try DQAFileManager.ensureDirectory(for: dqaBarcode)
            if let qpPath = paper.questionPaperPDFPath, !qpPath.isEmpty {
                let dest = dir.appendingPathComponent("QP.pdf")
                if DQAFileManager.extractPages(from: qpPath, ranges: ranges, to: dest) {
                    dqa.compiledQuestionPDFPath = dest.path
                }
            }
            if let msPath = paper.markSchemePDFPath, !msPath.isEmpty {
                let dest = dir.appendingPathComponent("MS.pdf")
                if DQAFileManager.extractPages(from: msPath, ranges: ranges, to: dest) {
                    dqa.compiledMarkSchemePDFPath = dest.path
                }
            }
        } catch {
            saveError = "File error: \(error.localizedDescription)"
            isSaving = false; return
        }

        PersistenceController.shared.save()
        let newID = dqa.objectID
        isSaving = false
        onCreate(newID)
        dismiss()
    }
}

// MARK: - DQAPDFPreviewView

/// Wraps `PDFView` for the setup-sheet question-paper preview.
/// Scrolls to `scrollToPage` whenever it changes (1-indexed).
struct DQAPDFPreviewView: NSViewRepresentable {
    let document: PDFDocument
    let scrollToPage: Int?

    class Coordinator { var lastPage: Int? = nil }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales      = true
        v.displayMode     = .singlePageContinuous
        v.displayDirection = .vertical
        v.document        = document
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document {
            v.document = document
            context.coordinator.lastPage = nil
        }
        if let page = scrollToPage,
           page != context.coordinator.lastPage,
           page >= 1, page <= document.pageCount,
           let pg = document.page(at: page - 1) {
            context.coordinator.lastPage = page
            v.go(to: pg)
        }
    }
}
