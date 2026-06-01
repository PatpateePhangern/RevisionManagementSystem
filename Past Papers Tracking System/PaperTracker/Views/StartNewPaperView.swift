import SwiftUI
import CoreData
import PDFKit

/// Workflow: pick a subject → enter a series → review computed attempt info → print.
struct StartNewPaperView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name, order: .forward)],
        animation: .none
    ) private var subjects: FetchedResults<SubjectMO>

    // Papers that already have a QP linked — used for series autocomplete.
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.normalizedSeries, order: .reverse)],
        predicate: NSPredicate(format: "questionPaperPDFPath != nil AND questionPaperPDFPath != ''"),
        animation: .none
    ) private var papersWithQP: FetchedResults<PaperMO>

    // Form state
    @State private var subjectText:        String     = ""
    @State private var selectedSubject:    SubjectMO? = nil
    @State private var seriesInput:        String     = ""
    @State private var normalizedSeries:   String?    = nil
    @State private var attemptNumber:      Int16      = 1
    @State private var barcodeID:          String     = ""
    @State private var isComputingAttempt: Bool       = false
    @State private var normalizationError: String?    = nil
    @State private var isSaving:           Bool       = false
    @State private var printRoutingStatus: String     = ""
    @State private var doubleSided:        Bool       = false

    // Series combo-box
    @State private var showSeriesDropdown:  Bool = false
    @State private var highlightedSeriesIdx: Int? = nil

    @AppStorage("lanPrintWindowsIP") private var windowsIPNewPaper: String = ""

    @FocusState private var seriesFocused: Bool

    // CS variant expansion
    @State private var paperComponent: Int = 1
    @State private var variantNumber:  Int = 1

    // MARK: - Computed helpers

    private var isCSVariant: Bool {
        guard let name = selectedSubject?.name else { return false }
        let u = name.uppercased()
        return u.contains("CS1") || u.contains("CS2") || u.contains("CS3")
            || u.contains("CS4") || u.contains("COMPUTER SCIENCE")
    }

    /// Existing papers with a QP linked for the selected subject, newest first.
    private var availableSeries: [PaperMO] {
        guard let sid = selectedSubject?.id else { return [] }
        return papersWithQP
            .filter { $0.subject?.id == sid }
            .sorted { ($0.normalizedSeries ?? "") > ($1.normalizedSeries ?? "") }
    }

    /// Subset of `availableSeries` matching the current series text.
    private var filteredSeries: [PaperMO] {
        let trimmed = seriesInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return availableSeries }
        return availableSeries.filter {
            let display = SeriesNormalizationEngine.displayName(from: $0.normalizedSeries ?? "")
            return display.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// The paper record that already exists in the DB for this subject+series.
    private var linkedPaper: PaperMO? {
        guard let sub = selectedSubject, let sid = sub.id,
              let norm = normalizedSeries else { return nil }
        return PaperMO.find(subjectID: sid, normalizedSeries: norm, in: ctx)
    }

    /// True when the paper for the current series has a QP PDF already mapped.
    private var hasQPInMapping: Bool {
        guard let path = linkedPaper?.questionPaperPDFPath else { return false }
        return !path.isEmpty
    }

    private var isReady: Bool {
        selectedSubject != nil && normalizedSeries != nil
            && !barcodeID.isEmpty && !isComputingAttempt
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── 1 Subject ────────────────────────────────────────────────
                sectionHeader("1 — Subject")

                SearchableComboBox(
                    text: $subjectText,
                    selectedSubject: $selectedSubject,
                    subjects: Array(subjects),
                    placeholder: "Type subject name…",
                    onConfirm: { seriesFocused = true },
                    autoFocus: true
                )
                .frame(maxWidth: 400)

                if selectedSubject == nil && !subjectText.isEmpty {
                    Text("No matching subject. Add one in Subject Manager.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Divider()

                // ── 2 Exam Series ────────────────────────────────────────────
                sectionHeader(isCSVariant ? "2 — Series, Paper & Variant" : "2 — Exam Series")

                // Glass series combo-box (always a type-box, with autocomplete)
                VStack(alignment: .leading, spacing: 4) {
                    seriesInputField
                    if showSeriesDropdown && !filteredSeries.isEmpty {
                        seriesDropdownPanel
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.96, anchor: .top)
                                        .combined(with: .opacity),
                                    removal:   .scale(scale: 0.96, anchor: .top)
                                        .combined(with: .opacity)
                                )
                            )
                            .zIndex(99)
                    }
                }
                .animation(.smooth(duration: 0.22), value: showSeriesDropdown)
                .frame(maxWidth: 400)

                if isCSVariant { csComponentPickers }

                if let err = normalizationError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }

                Divider()

                // ── 3 Computed Details ───────────────────────────────────────
                sectionHeader("3 — Computed Details")

                if let norm = normalizedSeries {
                    infoGrid(norm: norm)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                            removal:   .opacity
                        ))
                } else {
                    Text("Enter a series above and press Return to compute.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .transition(.opacity)
                }


                Divider()

                // ── Action ───────────────────────────────────────────────────
                if isReady && !hasQPInMapping {
                    noMappingChoiceView
                } else {
                    printButton
                }
            }
            .padding(28)
        }
        .animation(.smooth(duration: 0.3), value: normalizedSeries)
        .focusEffectDisabled()
        .onChange(of: selectedSubject) { _, _ in
            paperComponent     = 1
            variantNumber      = 1
            normalizedSeries   = nil
            barcodeID          = ""
            doubleSided        = false
            showSeriesDropdown = false
            highlightedSeriesIdx = nil
        }
    }

    // MARK: - Series input field (glass)

    private var seriesInputField: some View {
        TextField(
            "e.g. May 2025, Oct 24, 2025-05…",
            text: $seriesInput
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .focused($seriesFocused)
        .disabled(selectedSubject == nil)
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
        .onChange(of: seriesInput) { _, _ in
            // Clear computed state so the user must re-submit after editing.
            normalizedSeries     = nil
            barcodeID            = ""
            normalizationError   = nil
            showSeriesDropdown   = !seriesInput.trimmingCharacters(in: .whitespaces).isEmpty
            highlightedSeriesIdx = nil
        }
        .onSubmit {
            if let idx = highlightedSeriesIdx, idx < filteredSeries.count {
                selectSeries(filteredSeries[idx])
            } else {
                showSeriesDropdown = false
                normalizeSeries()
            }
        }
        .onKeyPress(.downArrow) {
            guard !filteredSeries.isEmpty else { return .ignored }
            showSeriesDropdown   = true
            highlightedSeriesIdx = highlightedSeriesIdx
                .map { min($0 + 1, filteredSeries.count - 1) } ?? 0
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard let idx = highlightedSeriesIdx else { return .ignored }
            highlightedSeriesIdx = idx > 0 ? idx - 1 : nil
            return .handled
        }
        .onKeyPress(.escape) {
            showSeriesDropdown   = false
            highlightedSeriesIdx = nil
            return .handled
        }
    }

    // MARK: - Series autocomplete dropdown (glass)

    private var seriesDropdownPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredSeries.enumerated()), id: \.element.objectID) { idx, paper in
                    Button {
                        selectSeries(paper)
                    } label: {
                        HStack(spacing: 0) {
                            Text(SeriesNormalizationEngine.displayName(
                                    from: paper.normalizedSeries ?? ""))
                                .font(.system(size: 13))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .background {
                            if highlightedSeriesIdx == idx {
                                Color.clear
                                    .glassEffect(in: RoundedRectangle(cornerRadius: 7))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .onHover { hovered in
                        withAnimation(.smooth(duration: 0.15)) {
                            highlightedSeriesIdx = hovered ? idx : nil
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if idx < filteredSeries.count - 1 {
                            Divider().padding(.leading, 12).opacity(0.4)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 160)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - No-mapping choice card (glass)

    private var noMappingChoiceView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text("No paper found in the mapping for this series.")
                        .font(.system(size: 13, weight: .semibold))
                    Text("You can create it as a new series (saves to the database and prints), or just print the index sheet without adding it to the mapping.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { openMappingWithPrefill() }
                } label: {
                    Text("Create New Series  [⌘↩]")
                        .font(.system(size: 12))
                }
                .buttonStyle(BlueGlassButtonStyle())
                .focusEffectDisabled()
                .disabled(selectedSubject == nil || normalizedSeries == nil)
                .keyboardShortcut(.return, modifiers: .command)

                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { printIndexSheetOnly() }
                } label: {
                    Text("Print Index Sheet Only")
                        .font(.system(size: 12))
                }
                .buttonStyle(BlueGlassButtonStyle())
                .focusEffectDisabled()
                .disabled(isSaving)
            }
        }
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Normal print button (shown when QP is already in mapping)

    @ViewBuilder
    private var printButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Double-sided toggle (only shown when QP is already mapped)
            if isReady, let qpPath = linkedPaper?.questionPaperPDFPath, !qpPath.isEmpty {
                Button { doubleSided.toggle() } label: {
                    Label("Append Question Paper (double-sided print)",
                          systemImage: doubleSided ? "doc.on.doc.fill" : "doc.on.doc")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .glassEffect(in: Capsule())
                .foregroundStyle(doubleSided ? Color.accentColor : Color.secondary)
                .focusEffectDisabled()
            }

            HStack(spacing: 8) {
                // Primary action
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { saveAndPrint() }
                } label: {
                    Text(isSaving ? "Saving…" : "Generate & Print Index Sheet  [⌘↩]")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .glassEffect(in: Capsule())
                .foregroundStyle(Color.accentColor)
                .focusEffectDisabled()
                .disabled(!isReady || isSaving)
                .keyboardShortcut(.return, modifiers: .command)

                // Windows PC menu
                if !windowsIPNewPaper.isEmpty && isReady {
                    Menu {
                        Button {
                            guard let payload = buildNewPaperPayload(),
                                  let data = buildFinalPDFData(payload: payload) else {
                                printRoutingStatus = "✗ Could not build PDF"; return
                            }
                            Task { @MainActor in
                                do {
                                    try await LANPrintRouter.sendToWindows(
                                        data: data,
                                        filename: "\(payload.barcodeValue).pdf",
                                        mode: .expressDefault)
                                    printRoutingStatus = "✓ Sent — Express Print"
                                } catch {
                                    printRoutingStatus = "✗ \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Label("Express Print (Default Settings)", systemImage: "network")
                        }
                        Button {
                            guard let payload = buildNewPaperPayload(),
                                  let data = buildFinalPDFData(payload: payload) else {
                                printRoutingStatus = "✗ Could not build PDF"; return
                            }
                            Task { @MainActor in
                                do {
                                    try await LANPrintRouter.sendToWindows(
                                        data: data,
                                        filename: "\(payload.barcodeValue).pdf",
                                        mode: .manualWithVNC)
                                    printRoutingStatus = "✓ Sent — Screen Sharing opened"
                                } catch {
                                    printRoutingStatus = "✗ \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Label("Manual + VNC Screen Mirror", systemImage: "display")
                        }
                    } label: {
                        Label("→ Windows PC", systemImage: "network")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .glassEffect(in: Capsule())
                    .focusEffectDisabled()
                    .help("Route the index sheet PDF to the Windows print server")
                }
            }

            // Past paper quick-print row
            if isReady {
                let qPath  = linkedPaper?.questionPaperPDFPath
                let msPath = linkedPaper?.markSchemePDFPath
                if qPath != nil || msPath != nil {
                    HStack(spacing: 8) {
                        Text("Print Past Paper:")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        if let qp = qPath, !qp.isEmpty {
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                                    printPDFAtPath(qp)
                                }
                            } label: {
                                Label("Question Paper", systemImage: "doc.text")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                            }
                            .buttonStyle(BlueGlassButtonStyle())
                            .glassEffect(in: Capsule())
                            .focusEffectDisabled()
                        }
                        if let ms = msPath, !ms.isEmpty {
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                                    printPDFAtPath(ms)
                                }
                            } label: {
                                Label("Mark Scheme", systemImage: "doc.text.fill")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                            }
                            .buttonStyle(BlueGlassButtonStyle())
                            .glassEffect(in: Capsule())
                            .focusEffectDisabled()
                        }
                    }
                }
            }

            if !printRoutingStatus.isEmpty {
                Text(printRoutingStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        printRoutingStatus.hasPrefix("✓") ? Color.green : Color.red
                    )
            }
        }
    }

    // MARK: - Sub-views

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .textCase(.uppercase)
    }

    @ViewBuilder
    private var csComponentPickers: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Paper")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: $paperComponent) {
                Text("P1").tag(1); Text("P2").tag(2)
                Text("P3").tag(3); Text("P4").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Spacer()
        }
        .onChange(of: paperComponent) { _, _ in
            guard !seriesInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            normalizeSeries()
        }

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Variant")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: $variantNumber) {
                Text("V1").tag(1); Text("V2").tag(2); Text("V3").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Spacer()
        }
        .onChange(of: variantNumber) { _, _ in
            guard !seriesInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            normalizeSeries()
        }
    }

    private func infoGrid(norm: String) -> some View {
        VStack(spacing: 0) {
            infoRow("Normalized Series", value: norm, delay: 0.00)
            Divider().opacity(0.4)
            infoRow("Attempt Number",
                    value: isComputingAttempt ? "Computing…" : "\(attemptNumber)",
                    delay: 0.06)
            Divider().opacity(0.4)
            infoRow("Barcode ID", value: barcodeID.isEmpty ? "—" : barcodeID, delay: 0.12)
        }
        .padding(.vertical, 6)
        .glassEffect(in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 560)
    }

    private func infoRow(_ label: String, value: String, delay: Double = 0) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 150, alignment: .trailing)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal:   .opacity
        ))
        .animation(.smooth(duration: 0.32).delay(delay), value: value)
    }

    // MARK: - Series selection helper

    private func selectSeries(_ paper: PaperMO) {
        let display = SeriesNormalizationEngine.displayName(from: paper.normalizedSeries ?? "")
        seriesInput          = display
        showSeriesDropdown   = false
        highlightedSeriesIdx = nil
        normalizeSeries()
    }

    // MARK: - Business logic

    private func normalizeSeries() {
        normalizationError = nil
        let raw = seriesInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let subject = selectedSubject else { return }

        guard let baseSeries = SeriesNormalizationEngine.normalize(raw) else {
            normalizationError = "Could not identify a month and year in: \(raw)"
            return
        }
        let norm = isCSVariant
            ? SeriesNormalizationEngine.normalizeCSVariant(
                baseSeries: baseSeries,
                paperNumber: paperComponent,
                variantNumber: variantNumber)
            : baseSeries
        normalizedSeries = norm
        computeAttemptFromNorm(norm)
    }

    /// Opens the Papers Mapping window and pre-fills the Add Series sheet
    /// with the subject and series already entered, so the user just needs
    /// to attach the QP and MS PDFs before saving.
    private func openMappingWithPrefill() {
        guard let subject = selectedSubject, let norm = normalizedSeries else { return }
        let prefill = PapersMappingPrefill(
            subjectObjectID:  subject.objectID,
            subjectName:      subject.name ?? "",
            seriesRaw:        seriesInput,
            isCS:             isCSVariant,
            paperComponent:   paperComponent,
            variantNumber:    variantNumber,
            normalizedSeries: norm
        )
        PapersMappingWindowController.shared.openAddSeries(prefill: prefill)
    }

    private func saveAndPrint() {
        guard let subject = selectedSubject,
              let norm    = normalizedSeries,
              !barcodeID.isEmpty else { return }

        isSaving = true

        let payload = PDFDocumentGenerator.PrintPayload(
            subjectName:       subject.name ?? "",
            seriesDisplayName: SeriesNormalizationEngine.displayName(from: norm),
            normalizedSeries:  norm,
            attemptNumber:     attemptNumber,
            barcodeValue:      barcodeID,
            printTimestamp:    Date()
        )

        let sid      = subject.id ?? UUID()
        let bid      = barcodeID
        let num      = attemptNumber
        let rawSeries = isCSVariant
            ? "\(seriesInput) Paper \(paperComponent) Variant \(variantNumber)"
            : seriesInput

        PersistenceController.shared.performBackground { bgCtx in
            let req = NSFetchRequest<SubjectMO>(entityName: "SubjectMO")
            req.predicate  = NSPredicate(format: "id == %@", sid as CVarArg)
            req.fetchLimit = 1
            guard let subjectObj = (try? bgCtx.fetch(req))?.first else { return }

            let paper = PaperMO.find(subjectID: sid, normalizedSeries: norm, in: bgCtx)
                ?? PaperMO.insert(subject: subjectObj, rawSeriesName: rawSeries,
                                  normalizedSeries: norm, in: bgCtx)

            AttemptMO.insert(paper: paper, attemptNumber: num, barcodeValue: bid, in: bgCtx)

            let prevAttempts = (paper.attempts as? Set<AttemptMO>) ?? []
            for prev in prevAttempts where prev.attemptNumber < num {
                if let bc = prev.barcodeValue {
                    DifficultQuestionsArchiveMO.outdateAll(originalBarcode: bc, in: bgCtx)
                }
            }
        }

        if let finalData = buildFinalPDFData(payload: payload) {
            printPDFData(finalData)
        } else {
            PDFDocumentGenerator.generateAndPrint(payload: payload)
        }

        resetForm()
    }

    /// Prints the index sheet only — no Core Data record is created.
    private func printIndexSheetOnly() {
        guard let subject = selectedSubject,
              let norm    = normalizedSeries,
              !barcodeID.isEmpty else { return }

        let payload = PDFDocumentGenerator.PrintPayload(
            subjectName:       subject.name ?? "",
            seriesDisplayName: SeriesNormalizationEngine.displayName(from: norm),
            normalizedSeries:  norm,
            attemptNumber:     attemptNumber,
            barcodeValue:      barcodeID,
            printTimestamp:    Date()
        )
        PDFDocumentGenerator.generateAndPrint(payload: payload)
        resetForm()
    }

    private func resetForm() {
        subjectText          = ""
        selectedSubject      = nil
        seriesInput          = ""
        normalizedSeries     = nil
        attemptNumber        = 1
        barcodeID            = ""
        paperComponent       = 1
        variantNumber        = 1
        doubleSided          = false
        isSaving             = false
        showSeriesDropdown   = false
        highlightedSeriesIdx = nil
    }

    // MARK: - Attempt computation

    private func computeAttemptFromNorm(_ norm: String) {
        guard let subject = selectedSubject else { return }
        isComputingAttempt = true
        barcodeID = ""
        let sid         = subject.id ?? UUID()
        let subjectName = subject.name ?? ""
        let bgCtx       = PersistenceController.shared.newBackgroundContext()
        Task.detached(priority: .userInitiated) {
            do {
                let n = try await AttemptNumberCoordinator.nextAttemptNumberAsync(
                    subjectID: sid, normalizedSeries: norm, context: bgCtx)
                let bid = BarcodeGenerator.buildBarcodeID(
                    subjectName: subjectName, normalizedSeries: norm, attemptNumber: n)
                await MainActor.run {
                    self.attemptNumber      = n
                    self.barcodeID          = bid
                    self.isComputingAttempt = false
                }
            } catch {
                await MainActor.run {
                    self.normalizationError  = "Database query failed: \(error.localizedDescription)"
                    self.isComputingAttempt  = false
                }
            }
        }
    }

    // MARK: - PDF helpers

    private func buildNewPaperPayload() -> PDFDocumentGenerator.PrintPayload? {
        guard let subject = selectedSubject,
              let norm = normalizedSeries, !barcodeID.isEmpty else { return nil }
        return PDFDocumentGenerator.PrintPayload(
            subjectName:       subject.name ?? "",
            seriesDisplayName: SeriesNormalizationEngine.displayName(from: norm),
            normalizedSeries:  norm,
            attemptNumber:     attemptNumber,
            barcodeValue:      barcodeID,
            printTimestamp:    Date()
        )
    }

    private func buildFinalPDFData(payload: PDFDocumentGenerator.PrintPayload) -> Data? {
        guard let indexData = PDFDocumentGenerator.buildPDFData(payload: payload) else { return nil }
        if doubleSided,
           let qpPath = linkedPaper?.questionPaperPDFPath, !qpPath.isEmpty {
            return combinePDFs(indexData: indexData,
                               qpURL: URL(filePath: qpPath)) ?? indexData
        }
        return indexData
    }

    private func combinePDFs(indexData: Data, qpURL: URL) -> Data? {
        guard let combined = PDFDocument(data: indexData),
              let qpDoc    = PDFDocument(url: qpURL) else { return nil }
        if let blank = blankPage() { combined.insert(blank, at: combined.pageCount) }
        for i in 0..<qpDoc.pageCount {
            if let page = qpDoc.page(at: i) {
                combined.insert(page, at: combined.pageCount)
            }
        }
        return combined.dataRepresentation()
    }

    private func blankPage() -> PDFPage? {
        let mutableData = NSMutableData()
        var box = CGRect(x: 0, y: 0,
                         width:  PDFDocumentGenerator.pageWidth,
                         height: PDFDocumentGenerator.pageHeight)
        guard let ctx = CGContext(
                consumer: CGDataConsumer(data: mutableData as CFMutableData)!,
                mediaBox: &box, nil) else { return nil }
        ctx.beginPage(mediaBox: &box); ctx.endPage(); ctx.closePDF()
        return PDFDocument(data: mutableData as Data)?.page(at: 0)
    }

    private func printPDFAtPath(_ path: String) {
        let url = URL(filePath: path)
        guard let doc = PDFDocument(url: url) else { NSWorkspace.shared.open(url); return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize    = NSSize(width: PDFDocumentGenerator.pageWidth,
                                   height: PDFDocumentGenerator.pageHeight)
        info.leftMargin   = 0; info.rightMargin  = 0
        info.topMargin    = 0; info.bottomMargin = 0
        if let op = doc.printOperation(for: info,
                                       scalingMode: .pageScaleToFit,
                                       autoRotate: false) { op.run() }
    }

    private func printPDFData(_ data: Data) {
        guard let doc = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize   = NSSize(width: PDFDocumentGenerator.pageWidth,
                                  height: PDFDocumentGenerator.pageHeight)
        info.leftMargin  = 0; info.rightMargin  = 0
        info.topMargin   = 0; info.bottomMargin = 0
        if let op = doc.printOperation(for: info,
                                       scalingMode: .pageScaleToFit,
                                       autoRotate: false) { op.run() }
    }
}
