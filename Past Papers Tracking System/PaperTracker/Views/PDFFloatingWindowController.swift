import AppKit
import PDFKit

/// Opens an independent, non-modal PDF viewer window that can live on any
/// screen or Space without affecting the main PaperTracker workspace.
///
/// ## Usage
///
///     PDFFloatingWindowController.open(
///         url:   URL(filePath: attempt.scannedFilePath!),
///         title: attempt.barcodeValue ?? "Scanned PDF"
///     )
///
/// Each call produces a new, independent window.  Multiple windows can be
/// open simultaneously.  Windows remove themselves from the live pool when
/// the user closes them, freeing memory automatically.
final class PDFFloatingWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Pool

    /// Retains all open instances so they are not deallocated while visible.
    private static var liveControllers: [PDFFloatingWindowController] = []

    // MARK: - Factory

    /// Opens a new independent PDF viewer window on the main thread.
    /// Safe to call from any Swift concurrency context.
    @MainActor
    static func open(url: URL, title: String) {
        let ctrl = PDFFloatingWindowController(url: url, title: title)
        liveControllers.append(ctrl)
        ctrl.showWindow(nil)
    }

    // MARK: - Init

    init(url: URL, title: String) {
        // ── PDF view ──────────────────────────────────────────────────────
        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 720, height: 960))
        pdfView.document         = PDFDocument(url: url)
        pdfView.autoScales       = true
        pdfView.displayMode      = .singlePageContinuous
        pdfView.minScaleFactor   = 0.10
        pdfView.maxScaleFactor   = 5.0
        pdfView.backgroundColor  = .windowBackgroundColor

        // ── Host window ───────────────────────────────────────────────────
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 960),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable,
                          .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        window.title               = title
        window.contentView         = pdfView
        window.isReleasedWhenClosed = false   // pool owns lifetime
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - NSWindowDelegate

    /// When the window is closed, remove this controller from the pool so ARC
    /// can reclaim the memory.
    func windowWillClose(_ notification: Notification) {
        Self.liveControllers.removeAll { $0 === self }
    }
}
