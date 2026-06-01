import Foundation
import Combine
import SwiftUI

/// Manages automatic hourly backups to
/// ~/Library/Application Support/PaperTracker/AutoBackups/
///
/// Each backup is a ZIP containing:
///   manifest.json  — full Core Data export (all subjects / papers / attempts)
///   settings.json  — all relevant UserDefaults keys
///   pdfs/          — every QP and MS PDF referenced by PaperMO records
///   DQA/           — compiled Difficult Questions Archive PDFs
///
/// At most 24 backups are kept (one per hour for the last 24 hours); older
/// files are pruned automatically after each successful backup.
@MainActor
final class AutoBackupService: ObservableObject {

    static let shared = AutoBackupService()

    // MARK: - Published state

    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var recentBackups: [URL] = []

    // MARK: - Settings

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "autoBackupEnabled")
            isEnabled ? scheduleNext() : stopTimer()
        }
    }

    // MARK: - Constants

    static let backupInterval: TimeInterval = 3600      // 1 hour
    static let maxBackupsToKeep = 24
    private static let udLastBackupKey  = "autoBackupLastDate"
    private static let udEnabledKey     = "autoBackupEnabled"

    /// All relevant UserDefaults keys to include in the settings snapshot.
    private static let settingsKeys: [String] = [
        "customPDFStoragePath",
        "lanPrintWindowsIP",
        "lanPrintTargetPrinter",
        "dqaDoubleSided",
        "autoBackupEnabled"
    ]

    // MARK: - Folder

    var autoBackupFolderURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("PaperTracker", isDirectory: true)
            .appendingPathComponent("AutoBackups",  isDirectory: true)
    }

    // MARK: - Private

    private var timer: Timer?

    // MARK: - Init

    private init() {
        // Load persisted enabled state (default true on first launch)
        let stored = UserDefaults.standard.object(forKey: Self.udEnabledKey)
        isEnabled = (stored as? Bool) ?? true

        // Load last backup date
        lastBackupDate = UserDefaults.standard.object(forKey: Self.udLastBackupKey) as? Date

        refreshBackupList()

        if isEnabled { scheduleNext() }
    }

    // MARK: - Timer management

    /// Schedules the next single-shot timer based on when the last backup ran.
    /// If overdue, fires immediately; otherwise waits out the remaining interval.
    private func scheduleNext() {
        stopTimer()
        let now = Date()
        let remaining: TimeInterval
        if let last = lastBackupDate {
            let elapsed = now.timeIntervalSince(last)
            remaining = max(0, Self.backupInterval - elapsed)
        } else {
            remaining = 0  // never backed up — run immediately
        }

        if remaining == 0 {
            Task { @MainActor in
                await self.performBackup()
                self.startRecurringTimer()
            }
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.performBackup()
                    self?.startRecurringTimer()
                }
            }
        }
    }

    private func startRecurringTimer() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.backupInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performBackup()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Public API

    /// Trigger a backup immediately (also used by the "Back Up Now" button).
    func performBackup() async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        do {
            try await runBackup()
            let now = Date()
            lastBackupDate = now
            UserDefaults.standard.set(now, forKey: Self.udLastBackupKey)
            refreshBackupList()
            pruneOldBackups()
        } catch {
            lastError = error.localizedDescription
        }
        isRunning = false
    }

    // MARK: - Backup internals

    private func runBackup() async throws {
        let fm = FileManager.default

        // Ensure destination folder exists
        try fm.createDirectory(at: autoBackupFolderURL, withIntermediateDirectories: true)

        // Create a temporary staging directory
        let staging = fm.temporaryDirectory
            .appendingPathComponent(
                "PaperTrackerAutoBackup-\(UUID().uuidString)",
                isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // ── 1. Core Data JSON manifest ────────────────────────────────────────
        let jsonData = try await PersistenceController.shared.generateMasterBackup()
        try jsonData.write(to: staging.appendingPathComponent("manifest.json"))

        // ── 2. UserDefaults settings snapshot ────────────────────────────────
        var settings: [String: Any] = [:]
        for key in Self.settingsKeys {
            if let val = UserDefaults.standard.object(forKey: key) {
                settings[key] = val
            }
        }
        // Include per-subject checklist column counts
        for (key, val) in UserDefaults.standard.dictionaryRepresentation()
            where key.hasPrefix("checklistCols_") {
            settings[key] = val
        }
        let settingsData = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys])
        try settingsData.write(to: staging.appendingPathComponent("settings.json"))

        // ── 3. Linked QP + MS PDFs ────────────────────────────────────────────
        let pdfDest = staging.appendingPathComponent("pdfs", isDirectory: true)
        try fm.createDirectory(at: pdfDest, withIntermediateDirectories: true)
        try copyLinkedPDFs(to: pdfDest)

        // ── 4. DQA compiled PDFs ──────────────────────────────────────────────
        let dqaSource = DQAFileManager.dqaBaseURL
        if fm.fileExists(atPath: dqaSource.path) {
            try fm.copyItem(
                at: dqaSource,
                to: staging.appendingPathComponent("DQA", isDirectory: true))
        }

        // ── 5. Compress staging directory into a ZIP ──────────────────────────
        let tag = isoTag()
        let destZIP = autoBackupFolderURL.appendingPathComponent("AutoBackup-\(tag).zip")
        let process = Process()
        process.executableURL       = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments           = ["-r", destZIP.path, "."]
        process.currentDirectoryURL = staging
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BackupError.zipFailed(code: Int(process.terminationStatus))
        }
    }

    /// Copies every unique QP/MS PDF referenced by PaperMO records into `destDir`.
    /// Files are renamed with a UUID prefix when a name collision occurs.
    private func copyLinkedPDFs(to destDir: URL) throws {
        let fm  = FileManager.default
        let ctx = PersistenceController.shared.container.viewContext
        let req = PaperMO.fetchRequest()
        let papers = (try? ctx.fetch(req)) ?? []

        var seen = Set<String>()
        for paper in papers {
            for path in [paper.questionPaperPDFPath, paper.markSchemePDFPath]
                .compactMap({ $0 }) where !path.isEmpty && !seen.contains(path) {
                seen.insert(path)
                let src = URL(filePath: path)
                guard fm.fileExists(atPath: src.path) else { continue }
                let candidate = destDir.appendingPathComponent(src.lastPathComponent)
                let finalDest = fm.fileExists(atPath: candidate.path)
                    ? destDir.appendingPathComponent("\(UUID().uuidString)-\(src.lastPathComponent)")
                    : candidate
                try fm.copyItem(at: src, to: finalDest)
            }
        }
    }

    // MARK: - Rotation

    private func pruneOldBackups() {
        let fm = FileManager.default
        let files = sortedBackupFiles()
        for old in files.dropFirst(Self.maxBackupsToKeep) {
            try? fm.removeItem(at: old)
        }
    }

    // MARK: - List refresh

    func refreshBackupList() {
        recentBackups = sortedBackupFiles()
    }

    private func sortedBackupFiles() -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: autoBackupFolderURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles)
        else { return [] }

        return files
            .filter { $0.pathExtension == "zip" }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2
            }
    }

    // MARK: - Restore from auto-backup

    /// Extracts `manifest.json` from a backup ZIP and restores the database.
    func restoreFromAutoBackup(url: URL) async throws {
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory
            .appendingPathComponent(
                "PaperTrackerRestore-\(UUID().uuidString)",
                isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extractDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments     = ["-o", url.path, "manifest.json", "-d", extractDir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BackupError.unzipFailed(code: Int(process.terminationStatus))
        }

        let manifestData = try Data(contentsOf: extractDir.appendingPathComponent("manifest.json"))
        try await PersistenceController.shared.restoreFromBackup(data: manifestData)
    }

    // MARK: - Computed helpers

    var nextBackupDate: Date? {
        guard isEnabled, let last = lastBackupDate else {
            return isEnabled ? Date() : nil
        }
        return last.addingTimeInterval(Self.backupInterval)
    }

    // MARK: - Errors

    enum BackupError: LocalizedError {
        case zipFailed(code: Int)
        case unzipFailed(code: Int)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let c):   return "zip exited with code \(c)"
            case .unzipFailed(let c): return "unzip exited with code \(c)"
            }
        }
    }

    // MARK: - Private helpers

    private func isoTag() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .replacingOccurrences(of: "Z", with: "")
    }
}
