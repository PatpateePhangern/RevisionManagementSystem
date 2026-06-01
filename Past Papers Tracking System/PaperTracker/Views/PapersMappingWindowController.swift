import AppKit
import Combine
import SwiftUI

// MARK: - Shared observable state (AppKit ↔ SwiftUI bridge)

/// Shared observable state owned by the window controller and injected into
/// `PapersMappingView` as an environment object.  Mutating it from AppKit
/// directly drives SwiftUI sheet presentation — no notification timing issues.
final class PapersMappingState: ObservableObject {
    @Published var showAddSeries:    Bool                   = false
    @Published var addSeriesPrefill: PapersMappingPrefill?  = nil
}

// MARK: - Shared keyboard notification
//
// Internal (not private) so PDFPageMappingPanel can subscribe via .onReceive.
// The window controller posts it; the panel view handles the state mutation.
extension Notification.Name {
    static let pdfMappingPanelKeyDown  = Notification.Name("pdfMappingPanelKeyDown")
    /// Posted by Settings whenever the user changes the UI scale factor.
    static let rmsUIScaleDidChange     = Notification.Name("rmsUIScaleDidChange")
    /// Posted by PDFPageMappingWindowController when a mapping window closes.
    /// `object` is the `NSManagedObjectID` of the paper that was being mapped.
    static let pdfMappingWindowClosed  = Notification.Name("pdfMappingWindowClosed")
}

// MARK: - PapersMappingWindowController

/// Manages the standalone Papers Mapping workspace window.
///
/// Call `PapersMappingWindowController.shared.open()` from anywhere to show or
/// bring-to-front the window.  The controller is a singleton so re-opening
/// merely raises the existing window rather than spawning a duplicate.
///
/// The window can be moved to a second monitor, zoomed to fill a display, or
/// entered into native full-screen — completely independent of the main
/// PaperTracker window.
///
/// ## Keyboard event monitor (Part 3)
///
/// A local `NSEvent` monitor is registered here — inside the window
/// controller's lifecycle — rather than inside the SwiftUI view hierarchy.
/// This guarantees the monitor is installed exactly once, remains active
/// regardless of SwiftUI re-renders, and is torn down cleanly when the
/// window closes.
///
/// The monitor intercepts:
///   - **↑ / ↓**           — previous / next thumbnail page
///   - **⌘↑ / ⌘↓**       — jump to first / last page
///   - **1, 2, 3**         — set range start, extend range, reveal form
///
/// It posts `.pdfMappingPanelKeyDown` so the SwiftUI view mutates its own
/// `@State` safely on the main thread via `.onReceive`.
final class PapersMappingWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Shared instance

    static let shared = PapersMappingWindowController()

    // MARK: Shared state (survives window hide/show)
    private(set) var mappingState: PapersMappingState!

    // MARK: Observers

    private var keyMonitor:   Any? = nil
    private var scaleObserver: Any? = nil

    // MARK: Init

    private init() {
        let ctx   = PersistenceController.shared.container.viewContext
        let state = PapersMappingState()

        let rootView = PapersMappingView()
            .environment(\.managedObjectContext, ctx)
            .environmentObject(state)

        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title               = "Papers Mapping"
        // ── Part 2: aggressive default geometry ─────────────────────────────
        window.setContentSize(NSSize(width: 1400, height: 900))
        window.minSize             = NSSize(width: 1200, height: 800)
        window.styleMask           = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
        ]
        // Keeps the window alive after the user closes it so re-opening is fast.
        window.isReleasedWhenClosed = false
        window.animationBehavior    = .documentWindow
        window.center()

        super.init(window: window)
        mappingState    = state
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: Public API

    /// Opens the window AND immediately shows the Add Series sheet pre-filled
    /// with the supplied prefill data.  State is set synchronously on the
    /// `mappingState` ObservableObject before the window appears, so SwiftUI
    /// sees the values on its very first render — no notification timing issues.
    @MainActor
    func openAddSeries(prefill: PapersMappingPrefill) {
        mappingState.addSeriesPrefill = prefill
        mappingState.showAddSeries    = true
        open()
    }

    /// Shows the window, centring it on first open; raises it on subsequent calls.
    /// Also ensures the keyboard event monitor and scale observer are running.
    @MainActor
    func open() {
        if let w = window, !w.isVisible { w.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        startKeyMonitor()
        startScaleObserver()
        applyBoundsScale()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopKeyMonitor()
        stopScaleObserver()
    }

    func windowDidResize(_ notification: Notification) {
        applyBoundsScale()
    }

    // MARK: - Keyboard event monitor

    /// Registers a local `NSEvent` monitor that intercepts page-navigation and
    /// range-selection shortcuts for the Papers Mapping workspace.
    ///
    /// Guards ensure we do NOT swallow keystrokes when:
    ///   • A different top-level window is key (main PaperTracker window, etc.)
    ///   • The mapping-form text fields are the first responder (user is typing).
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Only intercept when the Papers Mapping window (or a sheet it
            // presents, such as PDFPageMappingPanel) is the key window.
            let keyWin = NSApp.keyWindow
            guard keyWin === self.window ||
                  keyWin?.sheetParent === self.window
            else { return event }

            // Pass through when a text field is focused — EXCEPT Shift+↑/↓
            // which the user needs for range extension even while typing a label.
            if keyWin?.firstResponder is NSTextView {
                let isArrow  = event.keyCode == 126 || event.keyCode == 125
                let hasShift = event.modifierFlags.contains(.shift)
                if !(isArrow && hasShift) { return event }
            }

            let code  = event.keyCode
            let noMod = event.modifierFlags
                .intersection([.command, .option, .control, .shift]).isEmpty
            let chars = event.charactersIgnoringModifiers ?? ""

            // ↑ / ↓  (with or without Cmd)
            let isUp   = code == 126
            let isDown = code == 125
            // 1 / 2 / 3  (no modifiers — avoid clashing with ⌘1 tab shortcuts)
            let isNum  = noMod && (chars == "1" || chars == "2" || chars == "3")

            guard isUp || isDown || isNum else { return event }

            NotificationCenter.default.post(
                name: .pdfMappingPanelKeyDown,
                object: event
            )
            return nil  // event consumed — suppress system bell
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    // MARK: - UI scale (bounds-based zoom)

    private func startScaleObserver() {
        guard scaleObserver == nil else { return }
        scaleObserver = NotificationCenter.default.addObserver(
            forName: .rmsUIScaleDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.applyBoundsScale() }
    }

    private func stopScaleObserver() {
        if let obs = scaleObserver { NotificationCenter.default.removeObserver(obs) }
        scaleObserver = nil
    }

    private func applyBoundsScale() {
        guard let contentView = window?.contentView else { return }
        let raw  = UserDefaults.standard.double(forKey: "uiScaleFactor")
        let scale = CGFloat(raw <= 0 ? 1.0 : min(max(raw, 1.0), 1.4))
        let frame = contentView.frame
        if scale == 1.0 {
            contentView.setBoundsSize(frame.size)
        } else {
            contentView.setBoundsSize(NSSize(width:  frame.width  / scale,
                                             height: frame.height / scale))
        }
    }
}
