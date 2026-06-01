import AppKit
import SwiftUI

/// Manages the standalone Performance Report workspace window.
/// Call `ReportWindowController.shared.open()` to show or raise it.
final class ReportWindowController: NSWindowController, NSWindowDelegate {

    static let shared = ReportWindowController()

    private init() {
        let rootView = ReportSetupSheet()
            .environment(\.managedObjectContext,
                          PersistenceController.shared.container.viewContext)

        let hosting = NSHostingController(rootView: rootView)
        let window  = NSWindow(contentViewController: hosting)
        window.title               = "Performance Report"
        window.setContentSize(NSSize(width: 660, height: 720))
        window.minSize             = NSSize(width: 560, height: 560)
        window.styleMask           = NSWindow.StyleMask(
            [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior    = .documentWindow
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    @MainActor
    func open() {
        if let w = window, !w.isVisible { w.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    func windowWillClose(_ notification: Notification) {}
}
