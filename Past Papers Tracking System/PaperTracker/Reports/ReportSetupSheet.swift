import SwiftUI
import CoreData
import PDFKit
import AppKit
import UniformTypeIdentifiers

/// Standalone Performance Report configuration panel.
/// Opened via ReportWindowController.shared.open() — not a SwiftUI sheet.
struct ReportSetupSheet: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true,
                                           selector: #selector(NSString.localizedCaseInsensitiveCompare))],
        animation: .none
    ) private var allSubjects: FetchedResults<SubjectMO>

    @State private var selectedSubjectIDs: Set<NSManagedObjectID> = []
    @State private var selectedSections:   Set<ReportSection>     = Set(ReportSection.allCases)
    @State private var toField:    String = ""
    @State private var fromField:  String = ""
    @State private var isGenerating = false
    @State private var generatedPDF: Data? = nil
    @State private var statusMessage = ""
    @State private var isPrinting    = false
    @State private var printStatus   = ""

    @AppStorage("lanPrintWindowsIP")     private var windowsIP:     String = ""
    @AppStorage("lanPrintTargetPrinter") private var targetPrinter: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    subjectsSection
                    sectionsSection
                    recipientSection
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            statusRow
            Divider()
            buttonRow
        }
        .frame(minWidth: 560, minHeight: 540)
        .focusEffectDisabled()
        .onAppear {
            if selectedSubjectIDs.isEmpty {
                selectedSubjectIDs = Set(allSubjects.map { $0.objectID })
            }
        }
    }

    // MARK: - Subjects section

    private var subjectsSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(allSubjects, id: \.objectID) { subject in
                    subjectRow(subject)
                    if subject.objectID != allSubjects.last?.objectID {
                        Divider().padding(.leading, 28)
                    }
                }
                if allSubjects.isEmpty {
                    Text("No subjects found. Add subjects in the Subjects tab.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        } label: {
            HStack {
                Text("Subjects")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(selectedSubjectIDs.count == allSubjects.count ? "Deselect All" : "Select All") {
                    if selectedSubjectIDs.count == allSubjects.count {
                        selectedSubjectIDs = []
                    } else {
                        selectedSubjectIDs = Set(allSubjects.map { $0.objectID })
                    }
                }
                .buttonStyle(BlueGlassButtonStyle())
                .font(.system(size: 11))
                .focusEffectDisabled()
            }
        }
    }

    private func subjectRow(_ subject: SubjectMO) -> some View {
        let on = selectedSubjectIDs.contains(subject.objectID)
        return HStack(spacing: 8) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .animation(.smooth(duration: 0.2), value: on)
                .contentTransition(.symbolEffect(.replace))
            Text(subject.name ?? "Untitled")
                .font(.system(size: 13))
            Spacer()
            let papers = subject.papers?.count ?? 0
            Text("\(papers) series")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if on { selectedSubjectIDs.remove(subject.objectID) }
            else  { selectedSubjectIDs.insert(subject.objectID) }
        }
    }

    // MARK: - Sections section

    private var sectionsSection: some View {
        GroupBox {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(ReportSection.allCases, id: \.self) { section in
                    sectionToggle(section)
                }
            }
        } label: {
            HStack {
                Text("Sections")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(selectedSections.count == ReportSection.allCases.count
                       ? "Deselect All" : "Select All") {
                    if selectedSections.count == ReportSection.allCases.count {
                        selectedSections = []
                    } else {
                        selectedSections = Set(ReportSection.allCases)
                    }
                }
                .buttonStyle(BlueGlassButtonStyle())
                .font(.system(size: 11))
                .focusEffectDisabled()
            }
        }
    }

    private func sectionToggle(_ section: ReportSection) -> some View {
        let on = selectedSections.contains(section)
        return HStack(spacing: 6) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .animation(.smooth(duration: 0.2), value: on)
                .contentTransition(.symbolEffect(.replace))
            Text(section.rawValue)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if on { selectedSections.remove(section) }
            else  { selectedSections.insert(section) }
        }
    }

    // MARK: - Recipient section

    private var recipientSection: some View {
        GroupBox {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Recipient name", text: $toField)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Sender name", text: $fromField)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Recipients")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 6) {
            if isGenerating || isPrinting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
            let msg = printStatus.isEmpty ? statusMessage : printStatus
            if !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if generatedPDF != nil {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { savePDF() }
                } label: {
                    Text("Save PDF…")
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Button row

    private var buttonRow: some View {
        HStack(spacing: 8) {
            // Generate — prominent
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { generateReport() }
            } label: {
                Label(isGenerating ? "Generating…" : "Generate",
                      systemImage: "doc.badge.gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(BlueGlassButtonStyle())
            .focusEffectDisabled()
            .disabled(isGenerating || selectedSubjectIDs.isEmpty || selectedSections.isEmpty)

            // Preview
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { openInPreview() }
            } label: {
                Label("Preview", systemImage: "doc.richtext")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .buttonStyle(BlueGlassButtonStyle())
            .focusEffectDisabled()
            .disabled(generatedPDF == nil)

            Spacer()

            // macOS Print
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { printLocally() }
            } label: {
                Label("Print", systemImage: "printer")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .buttonStyle(BlueGlassButtonStyle())
            .focusEffectDisabled()
            .disabled(generatedPDF == nil || isPrinting)

            // Windows Express
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    Task { await sendToWindows(mode: .expressDefault) }
                }
            } label: {
                Label("Win Express", systemImage: "pc")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .buttonStyle(BlueGlassButtonStyle())
            .focusEffectDisabled()
            .disabled(generatedPDF == nil || isPrinting || windowsIP.isEmpty)
            .help("Send to Windows PC — prints via default driver")

            // Windows Remote
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    Task { await sendToWindows(mode: .manualWithVNC) }
                }
            } label: {
                Label("Win Remote", systemImage: "display.2")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .buttonStyle(BlueGlassButtonStyle())
            .focusEffectDisabled()
            .disabled(generatedPDF == nil || isPrinting || windowsIP.isEmpty)
            .help("Send to Windows PC and open print dialog via Screen Sharing")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func generateReport() {
        let subjects = allSubjects.filter { selectedSubjectIDs.contains($0.objectID) }
        guard !subjects.isEmpty, !selectedSections.isEmpty else { return }
        isGenerating  = true
        statusMessage = "Generating…"
        printStatus   = ""
        let cfg = ReportConfig(
            subjects: Array(subjects),
            generatedDate: Date(),
            includeSections: selectedSections,
            toField:   toField.isEmpty   ? nil : toField,
            fromField: fromField.isEmpty ? nil : fromField
        )
        let context = ctx
        Task.detached(priority: .userInitiated) {
            let data = PerformanceReportEngine.generate(config: cfg, context: context)
            await MainActor.run {
                self.generatedPDF  = data
                self.isGenerating  = false
                self.statusMessage = "Ready — \(data.count / 1024) KB · \(dateStr())"
            }
        }
    }

    private func openInPreview() {
        guard let data = generatedPDF else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RMS-PerformanceReport-\(dateStr()).pdf")
        do {
            try data.write(to: tmp)
            NSWorkspace.shared.open(tmp)
        } catch {
            statusMessage = "Could not open preview: \(error.localizedDescription)"
        }
    }

    private func savePDF() {
        guard let data = generatedPDF else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType.pdf]
        panel.nameFieldStringValue = "PerformanceReport-\(dateStr()).pdf"
        panel.title = "Save Performance Report"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            statusMessage = "Saved to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func printLocally() {
        guard let data = generatedPDF,
              let doc  = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize    = NSSize(width: 595.276, height: 841.890)
        info.leftMargin   = 0; info.rightMargin  = 0
        info.topMargin    = 0; info.bottomMargin = 0
        if let op = doc.printOperation(for: info,
                                       scalingMode: .pageScaleToFit,
                                       autoRotate: false) {
            op.run()
        }
    }

    private func sendToWindows(mode: WindowsPrintMode) async {
        guard let data = generatedPDF else { return }
        isPrinting  = true
        printStatus = "Sending to Windows PC…"
        let filename = "PerformanceReport-\(dateStr()).pdf"
        do {
            try await LANPrintRouter.sendToWindows(
                data: data,
                filename: filename,
                mode: mode,
                targetPrinter: targetPrinter.isEmpty ? nil : targetPrinter
            )
            printStatus = mode == .expressDefault
                ? "Sent — printing via default driver."
                : "Sent — Screen Sharing launched."
        } catch {
            printStatus = "Error: \(error.localizedDescription)"
        }
        isPrinting = false
    }

    // MARK: - Helpers

    private func dateStr() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
}
