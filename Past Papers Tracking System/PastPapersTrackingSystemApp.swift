//
//  PastPapersTrackingSystemApp.swift
//  Past Papers Tracking System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI
import CoreData
import AppKit

// MARK: - AppDelegate — direct AppKit menu construction

final class RMSAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First-launch tutorial
        let seen = UserDefaults.standard.bool(forKey: "rms_hasSeenTutorial")
        if !seen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                TutorialWindowController.shared.open()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Become delegate of the Help menu so menuWillOpen fires before display
        if let helpMenu = NSApp.mainMenu?.item(withTitle: "Help")?.submenu {
            helpMenu.delegate = self
        }
    }

    // NSMenuDelegate — fires right before the menu appears, after SwiftUI is done
    func menuWillOpen(_ menu: NSMenu) {
        // Rewire "RMS Help" to our handler every time (SwiftUI resets its action)
        if let rmsHelp = menu.items.first(where: { $0.title == "RMS Help" }) {
            rmsHelp.action = #selector(openHelp)
            rmsHelp.target = self
        }
        // Add Tutorial once
        guard !menu.items.contains(where: { $0.title == "Quick Start Tutorial" }) else { return }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Quick Start Tutorial",
                              action: #selector(openTutorial),
                              keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func openHelp()     { HelpDocumentationWindowController.shared.open() }
    @objc private func openTutorial() { TutorialWindowController.shared.open() }
}

// MARK: - App

@main
struct PastPapersTrackingSystemApp: App {

    @NSApplicationDelegateAdaptor(RMSAppDelegate.self) var appDelegate

    private let persistence = PersistenceController.shared

    var body: some Scene {
        // ── Primary window ──────────────────────────────────────────────────
        WindowGroup("RMS") {
            PaperTrackerRootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1600, height: 1200)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Append Tutorial after the default help entry
            CommandGroup(after: .help) {
                Button("Quick Start Tutorial") {
                    TutorialWindowController.shared.open()
                }
            }
        }

        // ── Secondary window: Exam Timing System (legacy) ───────────────────
        WindowGroup("Exam Timing", id: "timing") {
            ContentView()
                .frame(minWidth: 1000, idealWidth: 1400, maxWidth: .infinity,
                       minHeight: 700, idealHeight: 900, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // ── Attempt detail window ────────────────────────────────────────────
        WindowGroup("Attempt Detail", id: "attempt-detail", for: UUID.self) { $attemptID in
            if let id = attemptID {
                AttemptDetailView(attemptID: id)
                    .environment(\.managedObjectContext, persistence.container.viewContext)
            }
        }
        .defaultSize(width: 780, height: 700)
        .windowResizability(.contentSize)

        // ── Settings window — appears in app menu as "Settings…" (⌘,) ───────
        Settings {
            PaperTrackerSettingsView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .frame(minWidth: 620, minHeight: 480)
        }
    }
}
