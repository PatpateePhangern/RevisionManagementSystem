import AppKit
import SwiftUI

// MARK: - Observable state shared between AppKit and SwiftUI

@MainActor
@Observable
final class MenuBarTimerState {
    var countdown:  Int64 = 0
    var isWarning:  Bool  = false
}

// MARK: - SwiftUI view rendered inside the status item

private struct MenuBarTimerView: View {
    var state: MenuBarTimerState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.isWarning ? Color.red : Color.primary)

            Text(formatTime(state.countdown))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.isWarning ? Color.red : Color.primary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth(duration: 0.25), value: state.countdown)
        }
        .padding(.horizontal, 4)
    }

    private func formatTime(_ s: Int64) -> String {
        let t = max(s, 0)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Controller

/// Shows a live exam countdown in the macOS menu bar.
/// Call `show()` when the session starts, `update(countdown:)` each second,
/// and `hide()` when the session ends.
@MainActor
final class MenuBarTimerController {

    static let shared = MenuBarTimerController()

    private var statusItem:  NSStatusItem?
    private var hostingView: NSHostingView<MenuBarTimerView>?
    private let state = MenuBarTimerState()

    private init() {}

    // MARK: - Public API

    func show() {
        guard statusItem == nil else { return }

        // Use a fixed width so the SwiftUI view is always fully visible.
        // "00:00:00" in the current font is ~95 pt; 110 gives comfortable margin.
        let item = NSStatusBar.system.statusItem(withLength: 110)
        statusItem = item

        guard let button = item.button else { return }

        // Clear default button chrome
        button.title = ""
        button.image = nil

        // Embed SwiftUI view — frame-based layout is more reliable for
        // NSStatusItem buttons than Auto Layout.
        let barHeight = NSStatusBar.system.thickness
        let view = MenuBarTimerView(state: state)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 110, height: barHeight)
        host.autoresizingMask = [.width, .height]
        button.addSubview(host)
        hostingView = host
    }

    func update(countdown: Int64, isWarning: Bool) {
        state.countdown = countdown
        state.isWarning = isWarning
    }

    func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem  = nil
        hostingView = nil
    }
}
