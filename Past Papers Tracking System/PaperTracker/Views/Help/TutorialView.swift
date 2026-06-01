import SwiftUI

// MARK: - Tutorial step model

struct TutorialStep: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let body: String
    let detail: String?
    let accentColor: Color
}

private let tutorialSteps: [TutorialStep] = [
    TutorialStep(
        id: 0,
        icon: "doc.text.magnifyingglass",
        title: "Welcome to RMS",
        body: "RMS is the Records Management System for past paper tracking, exam timing, and performance analysis.",
        detail: "This tutorial covers the principal functions of the application. Estimated duration: two minutes. Select Skip at any time to dismiss.",
        accentColor: .blue
    ),
    TutorialStep(
        id: 1,
        icon: "plus.circle",
        title: "New Paper",
        body: "Initiate a new examination attempt using the New Paper tab (⌘1).",
        detail: "Select a subject, enter the exam series, and confirm the paper component and variant. The system assigns a barcode ID and records the attempt number automatically. Submit to log the entry.",
        accentColor: .green
    ),
    TutorialStep(
        id: 2,
        icon: "doc.text.magnifyingglass",
        title: "Papers Mapping",
        body: "Associate examination series with their corresponding PDF source files (⌘7).",
        detail: "Open the Papers Mapping workspace. Add a series entry, attach the PDF, and assign page ranges to each question. Mapped pages are stored and accessible during review sessions.",
        accentColor: .orange
    ),
    TutorialStep(
        id: 3,
        icon: "tray.full",
        title: "Complete Logs",
        body: "Inspect the full record of all logged examination attempts (⌘2).",
        detail: "Entries are sorted by subject and series. Select any attempt to view the attempt detail, grade threshold data, and associated PDF pages. Records may be filtered by subject or date range.",
        accentColor: .purple
    ),
    TutorialStep(
        id: 4,
        icon: "timer",
        title: "Exam Timing System",
        body: "Conduct timed examination sessions with per-question time allocation (⌘3).",
        detail: "Configure a session by selecting a subject and paper. The ETS distributes time across questions, sounds audible alerts at each boundary, and generates a session receipt upon completion.",
        accentColor: .red
    ),
    TutorialStep(
        id: 5,
        icon: "folder.badge.person.crop",
        title: "Subjects",
        body: "Maintain the registry of examination subjects (⌘4).",
        detail: "Add subjects by name. Each subject may carry up to four exam dates used by the ETS. Paper series and attempt counts are displayed per subject.",
        accentColor: .teal
    ),
    TutorialStep(
        id: 6,
        icon: "chart.bar.doc.horizontal",
        title: "Summary",
        body: "Review aggregated performance statistics across all subjects (⌘5).",
        detail: "The Summary tab presents attempt counts, completion rates, and score distributions. Data updates in real time as new attempts are recorded.",
        accentColor: .indigo
    ),
    TutorialStep(
        id: 7,
        icon: "square.grid.2x2",
        title: "Workspaces",
        body: "Three auxiliary workspaces extend the core functions of RMS.",
        detail: "DQA (⌘8) archives difficult questions for review. Print (⌘9) queues double-sided print jobs for dispatch to a Windows printer. Report generates a formatted PDF performance report for selected subjects.",
        accentColor: .cyan
    ),
    TutorialStep(
        id: 8,
        icon: "network",
        title: "Windows Print Server",
        body: "To send print jobs to a Windows PC on your local network, download and run rms_print_server.exe on the Windows machine.",
        detail: "Download rms_print_server.exe from the RMS GitHub releases page and run it on your Windows PC — no installation required, just double-click. Once running, open a browser on that PC and go to http://localhost:8999 to confirm it's active. Then enter the Windows PC's LAN IP address (found with ipconfig) into RMS Settings → Windows Print Server. Express Print sends jobs silently; Manual + VNC opens Screen Sharing so you can select a printer. SumatraPDF must be installed on the Windows PC for Express Print to work.",
        accentColor: .orange
    ),
]

// MARK: - Tutorial view

struct TutorialView: View {

    @AppStorage("rms_hasSeenTutorial") private var hasSeenTutorial = false
    @State private var currentStep = 0
    @Namespace private var progressNamespace

    var onDismiss: () -> Void = {}

    private var step: TutorialStep { tutorialSteps[currentStep] }
    private var isLast: Bool { currentStep == tutorialSteps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header strip ──────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Skip") {
                    hasSeenTutorial = true
                    onDismiss()
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .focusEffectDisabled()
                .font(.system(size: 12))
                .opacity(isLast ? 0 : 1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 4)

            // ── Main card ─────────────────────────────────────────────────
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(step.accentColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: step.icon)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(step.accentColor)
                }
                .animation(.smooth(duration: 0.35), value: currentStep)

                // Title
                Text(step.title)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .animation(.smooth(duration: 0.28), value: currentStep)

                // Body
                Text(step.body)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .animation(.smooth(duration: 0.28), value: currentStep)

                // Detail
                if let detail = step.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .animation(.smooth(duration: 0.28), value: currentStep)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            // ── Progress dots ─────────────────────────────────────────────
            HStack(spacing: 6) {
                ForEach(tutorialSteps) { s in
                    Capsule()
                        .fill(s.id == currentStep
                              ? step.accentColor
                              : Color.secondary.opacity(0.3))
                        .frame(width: s.id == currentStep ? 20 : 6, height: 6)
                        .animation(.smooth(duration: 0.3), value: currentStep)
                }
            }
            .padding(.bottom, 20)

            Divider()

            // ── Navigation row ────────────────────────────────────────────
            HStack(spacing: 10) {
                if currentStep > 0 {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { currentStep -= 1 }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .glassEffect(in: Capsule())
                    .focusEffectDisabled()
                }

                Spacer()

                Button {
                    if isLast {
                        hasSeenTutorial = true
                        onDismiss()
                    } else {
                        withAnimation(.smooth(duration: 0.3)) { currentStep += 1 }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isLast ? "Done" : "Continue")
                            .font(.system(size: 13, weight: .medium))
                        if !isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .focusEffectDisabled()
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
    }
}

// MARK: - Window controller

final class TutorialWindowController: NSWindowController, NSWindowDelegate {

    static let shared = TutorialWindowController()

    private init() {
        let view = TutorialView(onDismiss: { TutorialWindowController.shared.close() })
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "RMS — Quick Start"
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.center()
        win.setContentSize(NSSize(width: 520, height: 460))
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

    func windowWillClose(_ notification: Notification) {}
}
