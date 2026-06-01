import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

// MARK: - DSPrintingView

/// Print Queue workspace.
///
/// Presents a drag-and-drop ingestion tray on the left and a chronological
/// FIFO file queue on the right.  Two action buttons at the bottom route the
/// entire queue to the Windows print server — either silently via the express
/// driver path or interactively via the Brave Browser / VNC manual path.
///
/// Supported drop types: PDF documents and raster images (PNG, JPEG, TIFF,
/// BMP).  Images are transcoded to single-page A4 PDFs before transmission.
/// Duplex Output inserts a blank A4 page at the end of any document whose
/// page count is odd, so every file starts on the recto side of a new sheet.
struct DSPrintingView: View {

    // MARK: Persisted preferences
    @AppStorage("lanPrintWindowsIP")     private var windowsIP:       String = ""
    @AppStorage("lanPrintTargetPrinter") private var selectedPrinter: String = ""

    // MARK: Queue state
    @State private var fileQueue:    [DSQueueItem] = []
    @State private var isDuplex:     Bool          = false
    @State private var isTargeted:   Bool          = false

    // MARK: Routing feedback
    @State private var routingStatus: String = ""
    @State private var isProcessing:  Bool   = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                dropZone
                    .frame(minWidth: 220, maxWidth: 280)
                Divider()
                queueTable
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footerBar
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer.filled.and.paper.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color(nsColor: .systemIndigo))
            Text("Print Queue")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Duplex toggle — glass capsule pill, no system focus ring
            Button { isDuplex.toggle() } label: {
                Label("Duplex Output",
                      systemImage: isDuplex ? "doc.on.doc.fill" : "doc.on.doc")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .foregroundStyle(isDuplex ? Color.accentColor : Color.secondary)
            .focusEffectDisabled()
            .help("Append a blank A4 page after each odd-page document so every file starts on the front face of a new sheet")

            Divider().frame(height: 16)

            Text(fileQueue.isEmpty
                 ? "No files queued"
                 : "\(fileQueue.count) file\(fileQueue.count == 1 ? "" : "s") queued")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: isTargeted ? .selectedControlColor : .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isTargeted
                                ? Color(nsColor: .systemBlue)
                                : Color(nsColor: .separatorColor),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1,
                                               dash: isTargeted ? [] : [6, 4])
                        )
                )
                .padding(16)

            // Prompt
            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color(nsColor: isTargeted ? .systemBlue : .tertiaryLabelColor))
                Text("Drop files here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Text("PDF · PNG · JPEG · TIFF")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .frame(maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    // MARK: - Queue table

    private var queueTable: some View {
        Group {
            if fileQueue.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    Text("Queue is empty")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(fileQueue) { item in
                        queueRow(item)
                    }
                    .onDelete { indexSet in
                        fileQueue.remove(atOffsets: indexSet)
                    }
                    .onMove { src, dst in
                        fileQueue.move(fromOffsets: src, toOffset: dst)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func queueRow(_ item: DSQueueItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: .systemRed))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            // Per-item remove button
            Button {
                fileQueue.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .bounceOnPress()
            .focusEffectDisabled()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Footer bar

    private var footerBar: some View {
        HStack(spacing: 10) {
            // ── Express Print — prominent blue glass pill ─────────────────────
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    runQueue(mode: .expressDefault)
                }
            } label: {
                Label("Express Print Queue", systemImage: "network")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .foregroundStyle(Color.accentColor)
            .focusEffectDisabled()
            .disabled(fileQueue.isEmpty || isProcessing || windowsIP.isEmpty)
            .help(windowsIP.isEmpty
                  ? "Configure Windows PC address in Settings first"
                  : "Send all queued files to the Windows express spool (X-Target-Printer: \(selectedPrinter.isEmpty ? "System Default" : selectedPrinter))")

            // ── Manual / VNC — secondary glass pill ──────────────────────────
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    runQueue(mode: .manualWithVNC)
                }
            } label: {
                Label("Manual Print Queue (VNC Screen Mirror)", systemImage: "display")
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .focusEffectDisabled()
            .disabled(fileQueue.isEmpty || isProcessing || windowsIP.isEmpty)
            .help(windowsIP.isEmpty
                  ? "Configure Windows PC address in Settings first"
                  : "Send all queued files to Brave Browser + open Screen Sharing")

            if isProcessing {
                ProgressView().controlSize(.small)
            }

            if !routingStatus.isEmpty {
                Text(routingStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(routingStatus.hasPrefix("✓") ? Color.green : Color.red)
                    .lineLimit(1)
            }

            Spacer()

            // ── Clear Queue — destructive glass pill ──────────────────────────
            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    fileQueue.removeAll()
                    routingStatus = ""
                }
            } label: {
                Label("Clear Queue", systemImage: "trash")
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .foregroundStyle(Color(nsColor: .systemRed))
            .focusEffectDisabled()
            .disabled(fileQueue.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let sourceURL = url else { return }
                DispatchQueue.main.async {
                    enqueue(sourceURL)
                }
            }
        }
        return true
    }

    private func enqueue(_ url: URL) {
        // Avoid duplicates in the same session
        guard !fileQueue.contains(where: { $0.url == url }) else { return }
        fileQueue.append(DSQueueItem(url: url))
    }

    // MARK: - Queue execution

    private func runQueue(mode: WindowsPrintMode) {
        routingStatus = ""
        isProcessing  = true
        let snapshot  = fileQueue
        let duplex    = isDuplex
        let printer   = selectedPrinter.isEmpty ? nil : selectedPrinter
        let ip        = windowsIP

        Task { @MainActor in
            // ── Step 1: guard against missing config ─────────────────────────
            guard !ip.isEmpty else {
                routingStatus = "✗ No Windows PC address — configure it in Settings"
                isProcessing  = false
                return
            }

            // ── Step 2: preflight /status check ─────────────────────────────
            routingStatus = "Checking server…"
            let reachable = await LANPrintRouter.testConnection(ipPort: ip)
            guard reachable else {
                routingStatus = "✗ Cannot reach \(ip) — ensure win_print_server.py is running on the Windows PC"
                isProcessing  = false
                return
            }

            // ── Step 3: send each file in FIFO order ─────────────────────────
            routingStatus = "Sending…"
            do {
                for (index, item) in snapshot.enumerated() {
                    routingStatus = "Sending \(index + 1) / \(snapshot.count) — \(item.displayName)"
                    guard let data = buildPDFData(for: item.url, isDuplex: duplex) else {
                        throw DSPrintError.conversionFailed(item.displayName)
                    }
                    try await LANPrintRouter.sendToWindows(
                        data:          data,
                        filename:      item.pdfFilename,
                        mode:          mode,
                        targetPrinter: printer
                    )
                }
                let modeLabel = (mode == .expressDefault)
                    ? "Express Windows Print"
                    : "Manual Windows Config — Screen Sharing opened"
                routingStatus = "✓ \(snapshot.count) file\(snapshot.count == 1 ? "" : "s") sent — \(modeLabel)"
            } catch {
                routingStatus = "✗ \(error.localizedDescription)"
            }
            isProcessing = false
        }
    }

    // MARK: - PDF conversion helpers

    /// Convert `url` to PDF bytes, optionally appending a blank A4 page when
    /// the document has an odd page count (duplex alignment).
    private func buildPDFData(for url: URL, isDuplex: Bool) -> Data? {
        let ext = url.pathExtension.lowercased()

        let doc: PDFDocument
        if ext == "pdf" {
            guard let d = PDFDocument(url: url) else { return nil }
            doc = d
        } else if let img = NSImage(contentsOf: url) {
            // Raster image → single-page PDF scaled to fit A4
            let combined = PDFDocument()
            if let page = PDFPage(image: img) {
                combined.insert(page, at: 0)
            } else { return nil }
            doc = combined
        } else {
            return nil
        }

        // Duplex alignment: ensure even page count
        if isDuplex && doc.pageCount % 2 != 0 {
            if let blankData = blankPageData(),
               let blankDoc  = PDFDocument(data: blankData),
               let blankPage = blankDoc.page(at: 0) {
                doc.insert(blankPage, at: doc.pageCount)
            }
        }

        return doc.dataRepresentation()
    }

    /// Blank white A4 page rendered as PDF bytes via CoreGraphics.
    private func blankPageData() -> Data? {
        let w: CGFloat = 595.28  // A4 points
        let h: CGFloat = 841.89
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }
        var box = CGRect(x: 0, y: 0, width: w, height: h)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.endPDFPage()
        ctx.closePDF()
        return mutableData as Data
    }
}

// MARK: - DSQueueItem

/// Value-type wrapper for a file URL in the DS print queue.
struct DSQueueItem: Identifiable, Equatable {
    let id:  UUID = UUID()
    let url: URL

    var displayName: String { url.lastPathComponent }
    var pdfFilename: String {
        url.deletingPathExtension().lastPathComponent + ".pdf"
    }
    var subtitle: String {
        url.deletingLastPathComponent().path(percentEncoded: false)
    }
    var icon: String {
        switch url.pathExtension.lowercased() {
        case "pdf":             return "doc.richtext"
        case "png", "jpg",
             "jpeg", "tiff",
             "bmp", "heic":    return "photo"
        default:               return "doc"
        }
    }

    static func == (lhs: DSQueueItem, rhs: DSQueueItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - DSPrintError

enum DSPrintError: LocalizedError {
    case conversionFailed(String)
    var errorDescription: String? {
        switch self {
        case .conversionFailed(let name):
            return "Could not convert \"\(name)\" to PDF. Check the file format."
        }
    }
}
