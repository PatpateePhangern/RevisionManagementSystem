import SwiftUI
import AppKit

/// Top-level settings panel for the PaperTracker module.
///
/// Sections:
///   1. **PDF Archive Storage** — choose the folder where scanned PDFs are
///      saved after check-in.  The path is persisted in `UserDefaults` under
///      the key `customPDFStoragePath` and is read by `CompleteLogsView`'s
///      `processBarcode` pipeline.
///   2. **Windows Print Server** — configure the LAN address of the Windows
///      PC running `win_print_server.py`.  Persisted under `lanPrintWindowsIP`.
///      VNC is launched per-button (Manual route only), not as a global toggle.
///   3. **Backup & Restore** — delegates to the existing `BackupManagerView`.
struct PaperTrackerSettingsView: View {

    /// UserDefaults key consumed by `CompleteLogsView.processBarcode`.
    @AppStorage("customPDFStoragePath") private var customPDFStoragePath: String = ""

    // MARK: Windows Print Server
    @AppStorage("lanPrintWindowsIP")     private var windowsIP:       String = ""
    @State private var testStatus:        String = ""
    @State private var isTesting:         Bool   = false

    // MARK: Windows Print Deck Settings
    @AppStorage("lanPrintTargetPrinter") private var selectedPrinter: String = ""
    @State private var availablePrinters:  [String] = []
    @State private var loadingPrinters:    Bool     = false
    @State private var printerFetchStatus: String   = ""   // "" | "✓ …" | "✗ …"

    // MARK: Reset state
    @State private var showResetConfirm = false
    @State private var isResetting      = false
    @State private var resetStatus      = ""

    // MARK: Sound settings
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                alarmSoundsSection
                Divider()
                etsQuestionSoundsSection
                Divider()
                storageFolderSection
                Divider()
                windowsBridgeSection
                Divider()
                windowsPrintDeckSection
                Divider()
                BackupManagerView()
                Divider()
                resetSection
            }
        }
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset and Delete Everything", role: .destructive) {
                Task { await performReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A backup will be saved to your Downloads folder first. All subjects, papers, attempts, and settings will then be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Alarm Sounds section

    private var alarmSoundsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Alarm Sounds")
            VStack(spacing: 1) {
                soundRow(title: "5-Minute Warning",
                         description: "Plays when 5 minutes remain",
                         selected: $appSettings.fiveMinuteWarningSound,
                         sounds: AlarmSound.alarmSounds,
                         onChange: { appSettings.updateFiveMinuteWarningSound($0) })
                Divider().padding(.leading, 20)
                soundRow(title: "Time Up",
                         description: "Plays when time runs out",
                         selected: $appSettings.timeUpSound,
                         sounds: AlarmSound.alarmSounds,
                         onChange: { appSettings.updateTimeUpSound($0) })
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Question Notifications section

    private var etsQuestionSoundsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Question Notifications")
            VStack(spacing: 1) {
                soundRow(title: "Over Target",
                         description: "Notification when a question exceeds its target time",
                         selected: $appSettings.etsOverTargetSound,
                         sounds: AlarmSound.notificationSounds,
                         onChange: { appSettings.updateETSOverTargetSound($0) })
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Shared helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func soundRow(
        title: String,
        description: String,
        selected: Binding<AlarmSound>,
        sounds: [AlarmSound],
        onChange: @escaping (AlarmSound) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(sounds) { sound in
                    Button {
                        selected.wrappedValue = sound
                        onChange(sound)
                        sound.preview()
                    } label: {
                        HStack {
                            Text(sound.displayName)
                            if selected.wrappedValue == sound {
                                Spacer(); Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selected.wrappedValue.displayName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(nsColor: .controlColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .focusEffectDisabled()
            .fixedSize()

            Button { selected.wrappedValue.preview() } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .focusEffectDisabled()
            .help("Preview sound")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - PDF storage folder section

    private var storageFolderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Section label ────────────────────────────────────────────────
            Text("PDF Archive Storage")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // ── Row ──────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(nsColor: .systemYellow))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Destination Folder")
                        .font(.system(size: 12, weight: .medium))
                    Text(customPDFStoragePath.isEmpty
                         ? "No folder selected — scanned PDFs will not be archived"
                         : customPDFStoragePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(customPDFStoragePath.isEmpty
                                         ? Color(nsColor: .systemOrange)
                                         : Color(nsColor: .secondaryLabelColor))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Change Destination Folder") { chooseFolder() }
                    .controlSize(.regular)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            // ── Caption ──────────────────────────────────────────────────────
            Text("Files are saved as: <Destination Folder> / <Subject Name> / <Barcode>.pdf")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Windows Print Server section

    private var windowsBridgeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Section label ────────────────────────────────────────────────
            Text("Windows Print Server")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // ── IP address row ───────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Windows PC Address")
                        .font(.system(size: 12, weight: .medium))
                    TextField("192.168.1.70:8999", text: $windowsIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: 200)
                }

                Spacer()

                Button(isTesting ? "Testing…" : "Test Connection") {
                    testStatus = ""
                    isTesting  = true
                    Task { @MainActor in
                        let ok = await LANPrintRouter.testConnection(ipPort: windowsIP)
                        testStatus = ok ? "✓ Server is reachable" : "✗ No response"
                        isTesting  = false
                    }
                }
                .disabled(windowsIP.isEmpty || isTesting)
                .controlSize(.regular)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            // ── Status / caption ─────────────────────────────────────────────
            if !testStatus.isEmpty {
                Text(testStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(testStatus.hasPrefix("✓") ? Color.green : Color.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            } else {
                Text("Run  win_print_server.py  on the Windows PC, then enter its LAN IP:port above.  VNC opens automatically on the \"Manual\" route only.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Windows Print Deck Settings section

    private var windowsPrintDeckSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Section label ────────────────────────────────────────────────
            Text("Windows Print Deck Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // ── Printer configuration row ────────────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "printer.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(nsColor: .systemPurple))
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Printer Location")
                        .font(.system(size: 12, weight: .medium))

                    // ── Manual text entry (always available) ─────────────────
                    HStack(spacing: 6) {
                        TextField("Leave blank for System Default", text: $selectedPrinter)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: 300)
                        Text("(or pick from server below)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }

                    // ── Server-fetched picker ────────────────────────────────
                    if loadingPrinters {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Fetching printer list from server…")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }
                    } else if !availablePrinters.isEmpty {
                        Picker("", selection: $selectedPrinter) {
                            Text("System Default").tag("")
                            Divider()
                            ForEach(availablePrinters, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }

                    // ── Fetch status feedback ────────────────────────────────
                    if !printerFetchStatus.isEmpty {
                        Text(printerFetchStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(
                                printerFetchStatus.hasPrefix("✓") ? Color.green : Color.orange
                            )
                    }
                }

                Spacer()

                Button(loadingPrinters ? "Refreshing…" : "Fetch from Server") {
                    refreshPrinters()
                }
                .disabled(windowsIP.isEmpty || loadingPrinters)
                .controlSize(.regular)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            // ── Caption ──────────────────────────────────────────────────────
            Text("Type a printer name directly, or click \"Fetch from Server\" to auto-populate the list from the Windows PC.  Leave blank to use the Windows system default.")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // Silently attempt to auto-populate when this panel first appears.
            guard !windowsIP.isEmpty, availablePrinters.isEmpty else { return }
            await runFetchPrinters()
        }
    }

    // MARK: - Printer fetch helpers

    private func refreshPrinters() {
        guard !windowsIP.isEmpty else { return }
        Task { @MainActor in await runFetchPrinters() }
    }

    private func runFetchPrinters() async {
        loadingPrinters    = true
        printerFetchStatus = ""
        do {
            let names = try await LANPrintRouter.fetchPrinters(ipPort: windowsIP)
            availablePrinters = names
            if names.isEmpty {
                printerFetchStatus = "✗ Server reachable but returned no printers — is pywin32 installed?"
            } else {
                printerFetchStatus = "✓ \(names.count) printer\(names.count == 1 ? "" : "s") found"
                // If saved printer is no longer in the list, keep it — user may
                // have a custom name typed in; don't silently clear it.
            }
        } catch {
            availablePrinters  = []
            printerFetchStatus = "✗ Could not reach server — \(error.localizedDescription)"
        }
        loadingPrinters = false
    }

    // MARK: - Reset section

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reset Application")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete All Data")
                        .font(.system(size: 12, weight: .medium))
                    Text("A backup is created automatically before any data is removed.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    if !resetStatus.isEmpty {
                        Text(resetStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(resetStatus.hasPrefix("✓") ? Color.green : Color.red)
                    }
                }

                Spacer()

                Button(isResetting ? "Resetting…" : "Reset") {
                    showResetConfirm = true
                }
                .foregroundStyle(Color(nsColor: .systemRed))
                .disabled(isResetting)
                .controlSize(.regular)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func performReset() async {
        isResetting = true
        resetStatus = ""
        do {
            let url = try await PersistenceController.shared.resetAllData()
            resetStatus = "✓ Reset complete. Backup saved to \(url.lastPathComponent)"
        } catch {
            resetStatus = "✗ Reset failed: \(error.localizedDescription)"
        }
        isResetting = false
    }

    // MARK: - NSOpenPanel

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories   = true
        panel.canChooseFiles         = false
        panel.canCreateDirectories   = true
        panel.allowsMultipleSelection = false
        panel.prompt  = "Select Folder"
        panel.message = "Choose the folder where scanned PDFs will be archived."

        if panel.runModal() == .OK, let url = panel.url {
            customPDFStoragePath = url.path(percentEncoded: false)
        }
    }
}
