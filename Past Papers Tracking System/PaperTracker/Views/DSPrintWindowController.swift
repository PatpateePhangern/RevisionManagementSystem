import AppKit
import SwiftUI

// MARK: - DSPrintWindowController

/// Manages the standalone Print Queue workspace window.
///
/// Call `DSPrintWindowController.shared.open()` from anywhere to show or raise
/// the window.  The controller is a singleton so re-opening merely brings the
/// existing window to front rather than spawning a duplicate.
///
/// The window is intentionally independent of the main PaperTracker window:
/// it can be moved to a second monitor, zoomed, or entered into native
/// full-screen.
final class DSPrintWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Shared instance

    static let shared = DSPrintWindowController()

    // MARK: Init

    private init() {
        let hosting = NSHostingController(rootView: DSPrintingView())

        let window = NSWindow(contentViewController: hosting)
        window.title               = "Print Queue"
        window.setContentSize(NSSize(width: 860, height: 580))
        window.minSize             = NSSize(width: 720, height: 480)
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

    // MARK: Public API

    @MainActor
    func open() {
        if let w = window, !w.isVisible { w.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Nothing to tear down — the singleton window is merely hidden.
    }
}
