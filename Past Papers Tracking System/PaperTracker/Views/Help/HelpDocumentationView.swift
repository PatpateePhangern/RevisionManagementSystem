import SwiftUI

// MARK: - Data model

struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let shortcut: String?
    let paragraphs: [String]
    let items: [(String, String)]   // [(term, definition)]
}

private let helpSections: [HelpSection] = [

    HelpSection(
        icon: "square.grid.2x2",
        title: "Overview",
        shortcut: nil,
        paragraphs: [
            "RMS consolidates past paper tracking, examination timing, and performance analysis in a single application. All data is stored locally in a Core Data repository and backed up automatically.",
            "The primary window contains five tabs. Four auxiliary workspaces are accessible via the action strip or keyboard shortcuts ⌘7–⌘9.",
        ],
        items: []
    ),

    HelpSection(
        icon: "plus.circle",
        title: "New Paper",
        shortcut: "⌘1",
        paragraphs: [
            "Use New Paper to register an examination attempt. Select a subject from the list, enter the exam series in the prescribed format, and specify the paper component and variant.",
            "Upon submission, the system resolves the normalised series identifier, assigns a sequential attempt number, and generates a barcode ID. A printed receipt may be produced immediately.",
        ],
        items: [
            ("Series format", "e.g. 9709/12/O/N/24 or 9709/12/2024 for Computer Science"),
            ("Barcode ID", "Unique identifier composed of subject code, component, variant, and attempt number"),
            ("Auto-print", "Enable the print toggle to dispatch a receipt to the configured printer upon submission"),
        ]
    ),

    HelpSection(
        icon: "doc.text.magnifyingglass",
        title: "Papers Mapping",
        shortcut: "⌘7",
        paragraphs: [
            "Papers Mapping associates each recorded series with its PDF source file and maps individual questions to specific pages. Mapped data is used during review sessions to surface the relevant question instantly.",
            "Add a series entry, attach a PDF, then assign page ranges per question. The page mapping panel provides a live PDF preview alongside the question list.",
        ],
        items: [
            ("Add Series", "Opens a sheet to register a new series entry. Enter subject and exam series; the system locates or creates the corresponding record."),
            ("Page mapping", "Drag the page slider or type a page number in the mapping panel to assign pages to questions."),
            ("PDF viewer", "Double-click any question row to open its assigned pages in a floating viewer."),
        ]
    ),

    HelpSection(
        icon: "tray.full",
        title: "Complete Logs",
        shortcut: "⌘2",
        paragraphs: [
            "Complete Logs presents the full history of all recorded attempts, grouped by subject. Each entry displays the series, attempt number, barcode ID, date, and score where entered.",
            "Select an attempt to open its detail view. Scores and grade threshold tables may be entered or amended in the detail view at any time.",
        ],
        items: [
            ("Attempt detail", "Double-click or press Space on any log entry to open the full attempt record."),
            ("Grade thresholds", "Enter A, B, C, D, and E threshold marks in the detail view to enable grade computation."),
        ]
    ),

    HelpSection(
        icon: "timer",
        title: "Exam Timing System",
        shortcut: "⌘3",
        paragraphs: [
            "The Exam Timing System conducts timed examination sessions. Configure a session by selecting a subject and specifying the total duration and question set. The ETS distributes allocated time across questions and sounds an audible alert at each boundary.",
            "A session receipt is generated at the conclusion of each session and may be printed or saved.",
        ],
        items: [
            ("Question time", "The ETS divides the total session duration proportionally unless individual question times are specified."),
            ("Audible alerts", "A tone sounds at the start of each question boundary. Adjust alert volume in Settings."),
            ("Receipt", "The post-session receipt lists each question, its allocated time, and any deviation recorded."),
        ]
    ),

    HelpSection(
        icon: "folder.badge.person.crop",
        title: "Subjects",
        shortcut: "⌘4",
        paragraphs: [
            "The Subjects tab maintains the registry of examination subjects. Each subject serves as the organisational unit for papers, attempts, and ETS sessions.",
            "Subjects may carry up to four exam dates. These dates are displayed in the ETS session setup and in the Summary tab.",
        ],
        items: [
            ("Add subject", "Enter a subject name and press Add Subject or ⌘↩."),
            ("Exam dates", "Set up to four exam dates per subject using the date pickers in the edit form."),
            ("Delete subject", "Select the subject and press ⌘⌫. Deletion removes all associated papers and attempts permanently."),
        ]
    ),

    HelpSection(
        icon: "chart.bar.doc.horizontal",
        title: "Summary",
        shortcut: "⌘5",
        paragraphs: [
            "The Summary tab aggregates attempt data across all subjects. Statistics include total attempts, average scores, and score distributions presented per subject.",
            "Data refreshes automatically when new attempts are recorded or existing records are amended.",
        ],
        items: []
    ),

    HelpSection(
        icon: "archivebox",
        title: "Difficult Questions Archive",
        shortcut: "⌘8",
        paragraphs: [
            "The DQA workspace stores questions identified as requiring further revision. Entries may be created manually or by dropping a barcode PDF for automated extraction.",
            "Each DQA entry records the source paper, question number, and any notes. Entries may be printed in batches via the Print workspace.",
        ],
        items: [
            ("Manual entry", "Enter the subject, series, question number, and notes directly."),
            ("Barcode PDF", "Drop a generated barcode PDF onto the DQA setup sheet to create entries from scanned barcodes."),
        ]
    ),

    HelpSection(
        icon: "square.stack.fill",
        title: "Print",
        shortcut: "⌘9",
        paragraphs: [
            "Print queues double-sided print jobs and dispatches them to a configured printer. Jobs may be sent to the local macOS print system or forwarded to a Windows PC on the local network.",
            "Configure the target printer and Windows PC address in Settings under the Printing section.",
        ],
        items: [
            ("Express print", "Sends the job directly to the Windows PC default printer without opening a print dialog."),
            ("Remote print", "Sends the job to the Windows PC and opens Screen Sharing to allow printer selection."),
        ]
    ),

    HelpSection(
        icon: "doc.richtext",
        title: "Performance Report",
        shortcut: nil,
        paragraphs: [
            "The Report workspace generates a formatted PDF performance report. Select the subjects and sections to include, enter recipient and sender names, then press Generate.",
            "The completed report may be previewed in Preview, saved as a PDF, or printed via the local or Windows printer.",
        ],
        items: [
            ("Sections", "Include or exclude Summary, Per-Subject Statistics, Attempt Log, and Grade Distribution sections as required."),
            ("Recipients", "The To and From fields appear on the report cover page."),
        ]
    ),

    HelpSection(
        icon: "keyboard",
        title: "Keyboard Shortcuts",
        shortcut: nil,
        paragraphs: [
            "The following keyboard shortcuts are operative throughout the application.",
        ],
        items: [
            ("⌘1", "New Paper"),
            ("⌘2", "Complete Logs"),
            ("⌘3", "Exam Timing System"),
            ("⌘4", "Subjects"),
            ("⌘5", "Summary"),
            ("⌘7", "Papers Mapping workspace"),
            ("⌘8", "DQA workspace"),
            ("⌘9", "Print workspace"),
            ("⌘,", "Settings"),
            ("⌘⌫", "Delete selected subject (Subjects tab)"),
            ("⌘↩", "Confirm primary action in most forms"),
        ]
    ),
]

// MARK: - Help documentation view

struct HelpDocumentationView: View {

    @State private var selectedSectionID: UUID? = helpSections.first?.id
    @State private var searchText = ""

    private var filteredSections: [HelpSection] {
        if searchText.isEmpty { return helpSections }
        let q = searchText.lowercased()
        return helpSections.filter { sec in
            sec.title.lowercased().contains(q)
            || sec.paragraphs.joined().lowercased().contains(q)
            || sec.items.contains { $0.0.lowercased().contains(q) || $0.1.lowercased().contains(q) }
        }
    }

    var body: some View {
        HSplitView {
            // ── Left nav ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                    .focusEffectDisabled()

                Divider()

                List(filteredSections, selection: $selectedSectionID) { sec in
                    HStack(spacing: 8) {
                        Image(systemName: sec.icon)
                            .frame(width: 18)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sec.title)
                                .font(.system(size: 13, weight: .medium))
                            if let sc = sec.shortcut {
                                Text(sc)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(sec.id)
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // ── Right content ─────────────────────────────────────────────
            ScrollView {
                if let id = selectedSectionID,
                   let sec = helpSections.first(where: { $0.id == id }) {
                    sectionContent(sec)
                        .frame(maxWidth: 620, alignment: .topLeading)
                        .padding(32)
                } else {
                    Text("Select a topic.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .focusEffectDisabled()
    }

    // MARK: - Section content

    @ViewBuilder
    private func sectionContent(_ sec: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 24) {

            // Title row
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: sec.icon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(sec.title)
                        .font(.system(size: 22, weight: .semibold))
                    if let sc = sec.shortcut {
                        Text("Keyboard shortcut: \(sc)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Paragraphs
            ForEach(Array(sec.paragraphs.enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Terms
            if !sec.items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sec.items.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .top, spacing: 0) {
                            Text(item.0)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 160, alignment: .topLeading)
                                .padding(.vertical, 10)
                                .padding(.leading, 14)
                            Text(item.1)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 10)
                                .padding(.trailing, 14)
                            Spacer(minLength: 0)
                        }
                        .background(idx % 2 == 0
                                    ? Color(nsColor: .separatorColor).opacity(0.08)
                                    : Color.clear)
                        if idx < sec.items.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Window controller

final class HelpDocumentationWindowController: NSWindowController, NSWindowDelegate {

    static let shared = HelpDocumentationWindowController()

    private init() {
        let view = HelpDocumentationView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "RMS Help"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        win.setContentSize(NSSize(width: 800, height: 560))
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func open() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
