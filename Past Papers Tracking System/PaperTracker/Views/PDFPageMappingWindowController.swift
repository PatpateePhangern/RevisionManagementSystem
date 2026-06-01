import AppKit
import SwiftUI
import CoreData

// MARK: - PDFPageMappingWindowController

/// Manages standalone Page Mapping windows — one per paper.
///
/// Calling `open(paper:)` raises the existing window when one is already open
/// for that paper, preventing duplicate windows.  The pool is cleared when the
/// window closes so re-opening creates a fresh instance with clean state.
final class PDFPageMappingWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Pool

    private static var liveControllers: [PDFPageMappingWindowController] = []

    // MARK: Observers

    private var keyMonitor:    Any? = nil
    private var scaleObserver: Any? = nil

    // MARK: Factory

    @MainActor
    static func open(paper: PaperMO) {
        // Raise existing window if this paper is already open.
        if let existing = liveControllers.first(where: { $0.paperID == paper.objectID }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: false)
            return
        }
        let ctrl = PDFPageMappingWindowController(paper: paper)
        liveControllers.append(ctrl)
        ctrl.showWindow(nil)
        // Match the Papers Mapping window size/position if it's visible,
        // otherwise fall back to a sensible default (do NOT fill the whole screen).
        if let sourceFrame = PapersMappingWindowController.shared.window?.frame,
           let screen = NSScreen.main {
            let visibleH = screen.visibleFrame.height
            // Use the same width & X origin; cap height to screen.
            let h = min(max(sourceFrame.height, 700), visibleH)
            let y = screen.visibleFrame.minY + (visibleH - h) / 2
            ctrl.window?.setFrame(NSRect(x: sourceFrame.minX, y: y,
                                         width: sourceFrame.width, height: h),
                                   display: true)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            ctrl.window?.setFrame(NSRect(x: f.minX, y: f.minY,
                                          width: min(f.width, 1400), height: f.height),
                                   display: true)
        }
        ctrl.startKeyMonitor()
        ctrl.startScaleObserver()
        ctrl.applyBoundsScale()
        NSApp.activate(ignoringOtherApps: false)
    }

    // MARK: State

    private let paperID: NSManagedObjectID

    // MARK: Init

    init(paper: PaperMO) {
        self.paperID = paper.objectID

        let ctx         = PersistenceController.shared.container.viewContext
        let subjectName = paper.subject?.name ?? "Paper"
        let series      = paper.normalizedSeries.map {
            SeriesNormalizationEngine.displayName(from: $0)
        } ?? ""

        let rootView = PDFPageMappingPanel(paper: paper)
            .environment(\.managedObjectContext, ctx)

        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title               = "Page Mapping  —  \(subjectName)  \(series)"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize             = NSSize(width: 860, height: 560)
        window.styleMask           = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
        ]
        window.isReleasedWhenClosed = false
        window.animationBehavior    = .documentWindow
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopKeyMonitor()
        stopScaleObserver()
        Self.liveControllers.removeAll { $0 === self }
        NotificationCenter.default.post(name: .pdfMappingWindowClosed, object: paperID)
    }

    func windowDidResize(_ notification: Notification) {
        applyBoundsScale()
    }

    // MARK: - NSEvent keyboard monitor
    //
    // Posts .pdfMappingPanelKeyDown so PDFPageMappingPanel can safely mutate
    // @State on the main thread via .onReceive — same pattern used by
    // PapersMappingWindowController for the workspace window.

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window else { return event }
            // Pass through when user is typing — except Shift+↑/↓ for range extension.
            if NSApp.keyWindow?.firstResponder is NSTextView {
                let isArrow  = event.keyCode == 126 || event.keyCode == 125
                let hasShift = event.modifierFlags.contains(.shift)
                if !(isArrow && hasShift) { return event }
            }

            let code  = event.keyCode
            let isUp   = code == 126   // ↑
            let isDown = code == 125   // ↓
            let noMod  = event.modifierFlags
                .intersection([.command, .option, .control]).isEmpty
            let chars  = event.charactersIgnoringModifiers ?? ""
            // Allow bare digits for potential future shortcuts; for now forward
            // only arrow keys and ⌘↑/↓.
            let isNum  = noMod && (chars == "1" || chars == "2" || chars == "3")

            guard isUp || isDown || isNum else { return event }

            NotificationCenter.default.post(
                name: .pdfMappingPanelKeyDown,
                object: event
            )
            return nil  // consumed — suppresses system bell
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    // MARK: - UI scale (bounds-based zoom)

    fileprivate func startScaleObserver() {
        guard scaleObserver == nil else { return }
        scaleObserver = NotificationCenter.default.addObserver(
            forName: .rmsUIScaleDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.applyBoundsScale() }
    }

    fileprivate func stopScaleObserver() {
        if let obs = scaleObserver { NotificationCenter.default.removeObserver(obs) }
        scaleObserver = nil
    }

    fileprivate func applyBoundsScale() {
        guard let contentView = window?.contentView else { return }
        let raw   = UserDefaults.standard.double(forKey: "uiScaleFactor")
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
