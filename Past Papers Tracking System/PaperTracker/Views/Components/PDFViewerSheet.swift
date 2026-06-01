import SwiftUI
import PDFKit

/// Modal sheet presenting an interactive PDFView for a scanned attempt file.
/// Displayed when the user clicks "View Scanned PDF" or double-clicks a completed row.
struct PDFViewerSheet: View {

    let url: URL
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ─────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ── PDF canvas ──────────────────────────────────────────────────
            PDFKitView(url: url)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 700, idealHeight: 820)
    }
}

// MARK: - NSViewRepresentable bridge

struct PDFKitView: NSViewRepresentable {

    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales        = true
        view.displayMode       = .singlePageContinuous
        view.displayDirection  = .vertical
        view.backgroundColor   = .windowBackgroundColor
        if let doc = PDFDocument(url: url) {
            view.document = doc
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Re-load only if the URL changed (e.g., sheet reused for a different record).
        guard nsView.document?.documentURL != url else { return }
        if let doc = PDFDocument(url: url) {
            nsView.document = doc
            nsView.autoScales = true
        }
    }
}
