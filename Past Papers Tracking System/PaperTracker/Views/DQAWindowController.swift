import AppKit
import SwiftUI
import CoreData

// MARK: - DQAWindowController

/// Manages the standalone Difficult Questions Archive (DQA) window.
///
/// Call `DQAWindowController.shared.open()` from anywhere to show or raise
/// the window.  The controller is a singleton so re-opening merely brings the
/// existing window to front rather than spawning a duplicate.
///
/// The window is intentionally independent of the main PaperTracker window:
/// it can be moved to a second monitor, zoomed, or entered into native
/// full-screen.
final class DQAWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Shared instance

    static let shared = DQAWindowController()

    // MARK: Init

    private init() {
        let ctx = PersistenceController.shared.container.viewContext

        let rootView = DQAMainView()
            .environment(\.managedObjectContext, ctx)

        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title               = "Difficult Questions Archive"
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.minSize             = NSSize(width: 880, height: 580)
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
