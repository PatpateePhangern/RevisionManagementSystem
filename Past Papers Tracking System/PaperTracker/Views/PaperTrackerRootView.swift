import SwiftUI
import CoreData

enum PaperTrackerTab: String, CaseIterable {
    case newPaper     = "New Paper"
    case completeLogs = "Complete Logs"
    case batchLogs    = "Batch Logs"
    case ets          = "ETS"
    case subjects     = "Subjects"
    case summary      = "Summary"
}

extension Notification.Name {
    static let switchPaperTrackerTab        = Notification.Name("switchPaperTrackerTab")
    static let selectAttemptInCompleteLogs  = Notification.Name("selectAttemptInCompleteLogs")
    static let openPapersMappingAddSeries   = Notification.Name("openPapersMappingAddSeries")
}

// Prefill payload sent from StartNewPaperView → PapersMappingView AddSeriesSheet.
struct PapersMappingPrefill {
    let subjectObjectID:  NSManagedObjectID   // direct Core Data lookup — always resolves
    let subjectName:      String
    let seriesRaw:        String              // raw series text (non-CS)
    let isCS:             Bool
    let paperComponent:   Int
    let variantNumber:    Int
    let normalizedSeries: String?            // used to extract year/month for CS
}

// MARK: - Root view

struct PaperTrackerRootView: View {

    @State private var activeTab:          PaperTrackerTab = .newPaper
    @State private var keyMonitor:         NSObjectProtocol? = nil
    @Environment(\.managedObjectContext) private var ctx

    // Tab strip animation
    @Namespace private var tabNamespace

    // Action button drag-to-highlight
    @Namespace private var actionNamespace
    @State private var actionHighlightIdx: Int?    = nil
    @State private var actionStripWidth:   CGFloat = 400

    private static let tabMap: [String: PaperTrackerTab] = [
        "1": .newPaper, "2": .completeLogs, "3": .batchLogs, "4": .ets, "5": .subjects, "6": .summary
    ]

    // Static descriptors for the four standalone-window action buttons
    private struct ActionItem: Identifiable {
        let id: Int
        let label: String
        let icon: String
        let helpText: String
    }
    private let actionItems: [ActionItem] = [
        .init(id: 0, label: "Papers Mapping", icon: "doc.text.magnifyingglass",
              helpText: "Open Papers Mapping workspace  [⌘7]"),
        .init(id: 1, label: "DQA",            icon: "archivebox",
              helpText: "Open Difficult Questions Archive  [⌘8]"),
        .init(id: 2, label: "Print",        icon: "square.stack.fill",
              helpText: "Open Print Queue workspace  [⌘9]"),
        .init(id: 3, label: "Report",          icon: "doc.richtext",
              helpText: "Generate Performance Report"),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            HStack(spacing: 14) {
                Spacer()

                // Swipeable tab strip
                tabStrip

                // Drag-to-highlight action buttons
                actionStrip

                Spacer()
            }
            .padding(.vertical, 10)
            .background(headerBackground)

            Divider()

            // ── Content ──────────────────────────────────────────────────────
            ZStack {

                Group {
                    switch activeTab {
                    case .newPaper:     StartNewPaperView()
                    case .completeLogs: CompleteLogsView()
                    case .batchLogs:    BatchLogsView()
                    case .ets:          ETSLaunchView()
                    case .subjects:     SubjectManagerView()
                    case .summary:      SummaryView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.28), value: activeTab)
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .background(windowBackground.ignoresSafeArea())
        .onAppear {
            startKeyMonitor()
            _ = AutoBackupService.shared
        }
        .onDisappear { stopKeyMonitor() }
        .onReceive(
            NotificationCenter.default.publisher(for: .switchPaperTrackerTab)
        ) { note in
            if let tab = note.object as? PaperTrackerTab {
                withAnimation(.smooth(duration: 0.3)) { activeTab = tab }
            }
        }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(PaperTrackerTab.allCases, id: \.self) { tab in
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        withAnimation(.smooth(duration: 0.3)) { activeTab = tab }
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(activeTab == tab ? Color.primary : Color.secondary)
                        .animation(.smooth(duration: 0.2), value: activeTab)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background {
                            if activeTab == tab {
                                Capsule()
                                    .fill(Color(white: 0, opacity: 0.10))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "rootTab", in: tabNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPillButtonStyle())
                .help("\(tab.rawValue)  [\(shortcutKey(for: tab))]")
            }
        }
        .padding(3)
        .glassEffect(in: Capsule())
        .focusEffectDisabled()
        // ── Trackpad swipe to change tab ────────────────────────────────────
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let tabs = PaperTrackerTab.allCases
                    guard let idx = tabs.firstIndex(of: activeTab) else { return }
                    if value.translation.width < -40, idx < tabs.count - 1 {
                        withAnimation(.smooth(duration: 0.3)) { activeTab = tabs[idx + 1] }
                    } else if value.translation.width > 40, idx > 0 {
                        withAnimation(.smooth(duration: 0.3)) { activeTab = tabs[idx - 1] }
                    }
                }
        )
    }

    // MARK: - Action strip

    private var actionStrip: some View {
        HStack(spacing: 0) {
            ForEach(actionItems) { item in
                if item.id > 0 { Divider().frame(height: 14) }

                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { openActionAt(item.id) }
                } label: {
                    Label(item.label, systemImage: item.icon)
                        .font(.system(size: 11))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPillButtonStyle())
                .help(item.helpText)
                .background {
                    if actionHighlightIdx == item.id {
                        Color.clear
                            .glassEffect(in: Capsule())
                            .matchedGeometryEffect(id: "actionHL", in: actionNamespace)
                    }
                }
            }
        }
        .glassEffect(in: Capsule())
        .focusEffectDisabled()
        // Capture strip width so the drag gesture can map position → index
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ActionStripWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(ActionStripWidthKey.self) { actionStripWidth = $0 }
        // ── Trackpad drag to highlight then open ────────────────────────────
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let fraction  = value.location.x / max(actionStripWidth, 1)
                    let idx       = min(actionItems.count - 1,
                                       max(0, Int(fraction * CGFloat(actionItems.count))))
                    withAnimation(.smooth(duration: 0.12)) { actionHighlightIdx = idx }
                }
                .onEnded { value in
                    if let idx = actionHighlightIdx { openActionAt(idx) }
                    withAnimation(.smooth(duration: 0.25)) { actionHighlightIdx = nil }
                }
        )
    }

    // MARK: - Backgrounds

    private var headerBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    private var windowBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    // MARK: - Action helpers

    private func openActionAt(_ idx: Int) {
        switch idx {
        case 0: PapersMappingWindowController.shared.open()
        case 1: DQAWindowController.shared.open()
        case 2: DSPrintWindowController.shared.open()
        case 3: ReportWindowController.shared.open()
        default: break
        }
    }

    // MARK: - Key monitor

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  let ch = event.charactersIgnoringModifiers
            else { return event }

            if ch == "7" { PapersMappingWindowController.shared.open(); return nil }
            if ch == "8" { DQAWindowController.shared.open();            return nil }
            if ch == "9" { DSPrintWindowController.shared.open();        return nil }

            guard let tab = Self.tabMap[ch] else { return event }
            NotificationCenter.default.post(name: .switchPaperTrackerTab, object: tab)
            return nil
        } as? NSObjectProtocol
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    // MARK: - Helpers

    private func shortcutKey(for tab: PaperTrackerTab) -> String {
        switch tab {
        case .newPaper:     "⌘1"
        case .completeLogs: "⌘2"
        case .batchLogs:    "⌘3"
        case .ets:          "⌘4"
        case .subjects:     "⌘5"
        case .summary:      "⌘6"
        }
    }
}

// MARK: - PreferenceKey for action strip width

private struct ActionStripWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Shared glass button style

struct GlassPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .opacity(configuration.isPressed ? 0.70 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.30, dampingFraction: 0.45),
                value: configuration.isPressed
            )
    }
}

// MARK: - Tinted glass button style (light accent fill + accent text, Apple tinted style)

struct BlueGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.80 : 1.0)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Red tinted button style (delete / destructive actions)

struct RedGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: .systemRed))
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .systemRed).opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.80 : 1.0)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Grey tinted button style (disabled / unavailable actions)

struct GreyGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.80 : 1.0)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Bounce-on-press modifier (for .plain / icon buttons)

struct BounceOnPressModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.80 : 1.0)
            .animation(
                isPressed
                    ? .easeIn(duration: 0.07)
                    : .spring(response: 0.28, dampingFraction: 0.42),
                value: isPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded   { _ in isPressed = false }
            )
    }
}

extension View {
    func bounceOnPress() -> some View {
        modifier(BounceOnPressModifier())
    }
}
