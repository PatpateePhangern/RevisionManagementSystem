import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// Minimalist data management pane.
/// Hosts auto-backup status, manual export, and import/restore controls.
struct BackupManagerView: View {

    @ObservedObject private var autoBackup = AutoBackupService.shared

    @State private var isExporting:    Bool = false
    @State private var isImporting:    Bool = false
    @State private var isZIPExporting: Bool = false
    @State private var alertMessage: String = ""
    @State private var alertIsError: Bool   = false
    @State private var showAlert:    Bool   = false
    @State private var restoreTarget: URL?  = nil
    @State private var showRestoreConfirm = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                Divider()
                autoBackupSection
                Divider()
                exportSection
                Divider()
                zipExportSection
                Divider()
                importSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(alertIsError ? "Export / Restore Error" : "Operation Complete",
               isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "Restore from Auto-Backup",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                guard let url = restoreTarget else { return }
                Task {
                    do {
                        try await AutoBackupService.shared.restoreFromAutoBackup(url: url)
                        await MainActor.run {
                            alertMessage = "Database restored from:\n\(url.lastPathComponent)"
                            alertIsError = false
                            showAlert    = true
                        }
                    } catch {
                        await MainActor.run {
                            alertMessage = "Restore failed:\n\(error.localizedDescription)"
                            alertIsError = true
                            showAlert    = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will merge the selected backup into the current database. Existing records will be updated. This cannot be undone.")
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Data Management")
                .font(.system(size: 18, weight: .semibold))
            Text("Export all records as a portable JSON archive, or restore a previously saved backup. Operations run on a background thread and do not block the UI.")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Auto Backup section

    private var autoBackupSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header row ────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AUTO BACKUP")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .tracking(0.5)
                    Text("Hourly Automatic Backup")
                        .font(.system(size: 13, weight: .medium))
                    Text("Creates a full ZIP archive every hour and stores it in ~/Library/Application Support/PaperTracker/AutoBackups/. Includes the database, settings, all linked QP/MS PDFs, and DQA files. The 24 most recent backups are kept.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("Enabled", isOn: $autoBackup.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()

                    Button {
                        Task { await AutoBackupService.shared.performBackup() }
                    } label: {
                        if autoBackup.isRunning {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.72).controlSize(.small)
                                Text("Backing up…").fixedSize()
                            }
                        } else {
                            Label("Back Up Now", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .disabled(autoBackup.isRunning)
                    .frame(minWidth: 120)
                }
            }

            // ── Status card ───────────────────────────────────────────────────
            HStack(spacing: 24) {
                statusPill(
                    icon: "clock.badge.checkmark",
                    label: "Last backup",
                    value: autoBackup.lastBackupDate.map { relativeTime($0) } ?? "Never"
                )
                statusPill(
                    icon: "clock.arrow.2.circlepath",
                    label: "Next backup",
                    value: nextBackupString
                )
                if let err = autoBackup.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 11))
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 240)
                }
            }

            // ── Recent backups list ───────────────────────────────────────────
            if !autoBackup.recentBackups.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recent Backups")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(AutoBackupService.shared.autoBackupFolderURL)
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(autoBackup.recentBackups.prefix(10), id: \.path) { url in
                            HStack {
                                Image(systemName: "doc.zipper")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(nsColor: .systemBlue))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                    if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
                                        Text(Self.backupDateString(created))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                    }
                                }
                                Spacer()
                                Button("Restore") {
                                    restoreTarget      = url
                                    showRestoreConfirm = true
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .systemBlue))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            if url != autoBackup.recentBackups.prefix(10).last {
                                Divider().padding(.horizontal, 10)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if autoBackup.isEnabled {
                Text("No backups yet — the first backup will run shortly.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.vertical, 22)
    }

    private func statusPill(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var nextBackupString: String {
        guard autoBackup.isEnabled else { return "Disabled" }
        guard let next = autoBackup.nextBackupDate else { return "Soon" }
        if next <= Date() { return "Soon" }
        return relativeTime(next)
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = abs(date.timeIntervalSinceNow)
        if secs < 90    { return "Just now" }
        if secs < 3600  { return "\(Int(secs / 60)) min" + (date < Date() ? " ago" : "") }
        let hrs = Int(secs / 3600)
        return "\(hrs) hr\(hrs == 1 ? "" : "s")" + (date < Date() ? " ago" : "")
    }

    // MARK: - Export section

    private var exportSection: some View {
        sectionRow(
            label:       "EXPORT",
            title:       "Export Master Backup File",
            description: "Serialises all subjects, papers, attempts, question structures, and ETS event logs to a human-readable JSON file. Suitable for archiving, migration, and off-site storage.",
            actionLabel: "Export",
            actionIcon:  "square.and.arrow.up",
            isWorking:   isExporting,
            workingLabel: "Exporting…"
        ) {
            runExport()
        }
        .padding(.vertical, 22)
    }

    // MARK: - ZIP Export section (Part 6)

    private var zipExportSection: some View {
        sectionRow(
            label:        "FULL SYSTEM BACKUP",
            title:        "Export ZIP Archive",
            description:  "Bundles the JSON database manifest together with all compiled DQA PDFs (Question Papers, Mark Schemes, Index Sheets) into a single ZIP file. Suitable for off-site backup and full system migration.",
            actionLabel:  "Export ZIP",
            actionIcon:   "archivebox.circle",
            isWorking:    isZIPExporting,
            workingLabel: "Archiving…"
        ) {
            runZIPExport()
        }
        .padding(.vertical, 22)
    }

    // MARK: - Import section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionRow(
                label:       "IMPORT & RESTORE",
                title:       "Import & Restore Database Manifest",
                description: "Merges records from a backup JSON file into the current database. Subjects are matched by name, papers by series key, and attempts by barcode — existing records are updated and new ones are inserted. This operation is non-destructive by default.",
                actionLabel: "Import",
                actionIcon:  "square.and.arrow.down",
                isWorking:   isImporting,
                workingLabel: "Restoring…"
            ) {
                runImport()
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                Text("ETS event logs for matched attempts are replaced wholesale during a restore.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.vertical, 22)
    }

    // MARK: - Shared section row builder

    private func sectionRow(
        label:        String,
        title:        String,
        description:  String,
        actionLabel:  String,
        actionIcon:   String,
        isWorking:    Bool,
        workingLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .tracking(0.5)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }

            Spacer()

            Button(action: action) {
                if isWorking {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.72).controlSize(.small)
                        Text(workingLabel).fixedSize()
                    }
                } else {
                    Label(actionLabel, systemImage: actionIcon)
                }
            }
            .buttonStyle(BlueGlassButtonStyle())
            .disabled(isExporting || isImporting)
            .frame(minWidth: 120)
        }
    }

    // MARK: - ZIP Export action

    private func runZIPExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.zip]
        panel.nameFieldStringValue = "PaperTracker-FullBackup-\(dateTag()).zip"
        panel.title                = "Export Full System ZIP"
        panel.message              = "Choose where to save the ZIP archive."
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isZIPExporting = true
        Task {
            do {
                // ── 1. Generate JSON manifest ────────────────────────────────
                let jsonData = try await PersistenceController.shared.generateMasterBackup()

                // ── 2. Assemble staging directory ────────────────────────────
                let fm      = FileManager.default
                let staging = fm.temporaryDirectory
                    .appendingPathComponent("PaperTrackerZIPStaging-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: staging) }

                // JSON manifest
                let jsonDest = staging.appendingPathComponent("PaperTracker-Backup-\(dateTag()).json")
                try jsonData.write(to: jsonDest)

                // DQA compiled PDFs
                let dqaSource = DQAFileManager.dqaBaseURL
                if fm.fileExists(atPath: dqaSource.path) {
                    let dqaDest = staging.appendingPathComponent("DQA", isDirectory: true)
                    try fm.copyItem(at: dqaSource, to: dqaDest)
                }

                // ── 3. ZIP the staging directory ─────────────────────────────
                let process = Process()
                process.executableURL      = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments          = ["-r", destURL.path, "."]
                process.currentDirectoryURL = staging
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "DQABackup", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: "zip exited with code \(process.terminationStatus)"])
                }

                await MainActor.run {
                    isZIPExporting = false
                    alertMessage   = "ZIP archive exported successfully.\n\(destURL.lastPathComponent)"
                    alertIsError   = false
                    showAlert      = true
                }
            } catch {
                await MainActor.run {
                    isZIPExporting = false
                    alertMessage   = "ZIP export failed:\n\(error.localizedDescription)"
                    alertIsError   = true
                    showAlert      = true
                }
            }
        }
    }

    // MARK: - Export action

    private func runExport() {
        // Show save panel on main thread before launching the async export.
        let panel = NSSavePanel()
        panel.allowedContentTypes    = [.json]
        panel.nameFieldStringValue   = "PaperTracker-Backup-\(dateTag()).json"
        panel.title                  = "Export Master Backup"
        panel.message                = "Choose where to save the backup file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        Task {
            do {
                let data = try await PersistenceController.shared.generateMasterBackup()
                try data.write(to: url, options: .atomic)
                await MainActor.run {
                    isExporting  = false
                    alertMessage = "Backup exported successfully.\n\(url.lastPathComponent)"
                    alertIsError = false
                    showAlert    = true
                }
            } catch {
                await MainActor.run {
                    isExporting  = false
                    alertMessage = "Export failed:\n\(error.localizedDescription)"
                    alertIsError = true
                    showAlert    = true
                }
            }
        }
    }

    // MARK: - Import action

    private func runImport() {
        // Show open panel on main thread before launching the async restore.
        let panel = NSOpenPanel()
        panel.allowedContentTypes   = [.json]
        panel.allowsMultipleSelection = false
        panel.title                  = "Import Backup Manifest"
        panel.message                = "Select a PaperTracker JSON backup file to restore."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        Task {
            do {
                let data = try Data(contentsOf: url)
                try await PersistenceController.shared.restoreFromBackup(data: data)
                await MainActor.run {
                    isImporting  = false
                    alertMessage = "Database restored successfully.\n\(url.lastPathComponent)"
                    alertIsError = false
                    showAlert    = true
                }
            } catch {
                await MainActor.run {
                    isImporting  = false
                    alertMessage = "Restore failed:\n\(error.localizedDescription)"
                    alertIsError = true
                    showAlert    = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func dateTag() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.calendar   = Calendar(identifier: .gregorian)
        df.locale     = Locale(identifier: "en_US_POSIX")
        return df.string(from: Date())
    }

    /// Formats a backup file creation date in Gregorian calendar regardless of
    /// the system locale (prevents Buddhist Era output on Thai-locale devices).
    private static func backupDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy 'at' HH:mm"
        df.calendar   = Calendar(identifier: .gregorian)
        df.locale     = Locale(identifier: "en_GB")
        return df.string(from: date)
    }
}
