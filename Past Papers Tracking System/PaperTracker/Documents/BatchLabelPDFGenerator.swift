import AppKit
import PDFKit
import CoreGraphics
import CoreText

/// Generates a 10 cm × 15 cm Batch Examination Records Index Label.
///
/// Layout mirrors the Examination Records Index:
///   - Header band: title (Univers) top-left, RMS logo (IBM Logo font) top-right,
///     barcode centred between title and logo, barcode reference below barcode
///   - Header bottom rule
///   - Paper list table rows
///   - Bottom margin
///
/// Also used for the "Completed" variant — same layout, title reads "Completed".
struct BatchLabelPDFGenerator {

    // MARK: - Page geometry: 10 cm × 15 cm
    // 1 inch = 72 PostScript points; 1 inch = 25.4 mm
    // 10 cm = 100 mm = 100/25.4 in × 72 pt/in ≈ 283.46 pt
    // 15 cm = 150 mm = 150/25.4 in × 72 pt/in ≈ 425.20 pt
    static let pageWidth:  CGFloat = (100.0 / 25.4) * 72.0   // ≈ 283.46 pt
    static let pageHeight: CGFloat = (150.0 / 25.4) * 72.0   // ≈ 425.20 pt
    private static let margin: CGFloat = 12

    // MARK: - Payload

    struct BatchLabelPayload {
        let batchBarcode: String
        let papers:       [BatchPaperEntry]
        /// When true the header reads "Completed" instead of the usual two-line title
        var isCompleted:  Bool = false
    }

    struct BatchPaperEntry {
        let subjectName:   String
        let seriesDisplay: String
        let attemptNumber: Int16
        let barcodeValue:  String
    }

    // MARK: - Public API

    static func generateAndPrint(payload: BatchLabelPayload) {
        guard let data = buildPDFData(payload: payload) else { return }
        let suffix = payload.isCompleted ? "completed" : "label"
        let tmp = FileManager.default.temporaryDirectory
            .appending(component: "\(payload.batchBarcode)-\(suffix).pdf")
        try? data.write(to: tmp)
        guard let doc = PDFDocument(url: tmp) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize    = NSSize(width: pageWidth, height: pageHeight)
        info.leftMargin   = 0; info.rightMargin  = 0
        info.topMargin    = 0; info.bottomMargin = 0
        if let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) {
            op.run()
        }
    }

    static func buildPDFData(payload: BatchLabelPayload) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        draw(ctx: ctx, payload: payload)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: - Layout engine

    private static func draw(ctx: CGContext, payload: BatchLabelPayload) {
        let W = pageWidth   // ≈ 283.46 pt
        let H = pageHeight  // ≈ 425.20 pt
        let m = margin      // 12 pt

        // ── White background ──────────────────────────────────────────────────
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(0.5)

        // ── Header band height = 44 pt (mirrors the proportions of the A4 index,
        //    scaled down for 10 × 15 cm) ──────────────────────────────────────
        let headerH:      CGFloat = 44
        let headerBottom: CGFloat = H - m - headerH   // bottom edge of header band

        // ── Title block (top-left) ────────────────────────────────────────────
        if payload.isCompleted {
            // Single-line "Completed" title
            drawText(ctx,
                     text: "Completed",
                     rect: CGRect(x: m, y: headerBottom + 20, width: 160, height: 14),
                     font: universHeaderFont(size: 11))
        } else {
            // Two-line title: "Batch Examination Records Index" then "Label" (italic)
            drawText(ctx,
                     text: "Batch Examination Records Index",
                     rect: CGRect(x: m, y: headerBottom + 26, width: 160, height: 10),
                     font: universHeaderFont(size: 8))
            drawText(ctx,
                     text: "Label",
                     rect: CGRect(x: m, y: headerBottom + 14, width: 60, height: 10),
                     font: universHeaderFont(size: 8, italic: true))
        }

        // ── RMS logotype — flush top-right ────────────────────────────────────
        drawText(ctx,
                 text: "RMS",
                 rect: CGRect(x: W - m - 44, y: headerBottom + 16, width: 44, height: 18),
                 font: ibmLogoFont(size: 15), alignment: .right)

        // ── Barcode — centred between title and RMS logo ──────────────────────
        let bcLeft:   CGFloat = 155        // just past title block
        let bcRight:  CGFloat = W - m - 50  // 4 pt gap before RMS block
        let bcWidth            = bcRight - bcLeft
        let bcHeight: CGFloat  = 28
        let bcBottom           = headerBottom + 8

        if let barcodeImg = BarcodeGenerator.generateImage(for: payload.batchBarcode, scaleFactor: 3.0),
           let cgBarcode  = barcodeImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.interpolationQuality = .none
            ctx.draw(cgBarcode,
                     in: CGRect(x: bcLeft, y: bcBottom, width: bcWidth, height: bcHeight))
            ctx.interpolationQuality = .default
        }

        // Barcode reference — Courier, directly under barcode
        drawText(ctx,
                 text: payload.batchBarcode,
                 rect: CGRect(x: bcLeft, y: headerBottom + 1, width: bcWidth, height: 7),
                 font: NSFont(name: "Courier", size: 5.5)
                      ?? NSFont.monospacedSystemFont(ofSize: 5.5, weight: .regular),
                 alignment: .center)

        // ── Header bottom rule ────────────────────────────────────────────────
        strokeLine(ctx, x1: m, y1: headerBottom, x2: W - m, y2: headerBottom)

        // ── Paper list ────────────────────────────────────────────────────────
        let listTop     = headerBottom - 6
        let rowH:  CGFloat = 9
        let rowFont = universBodyFont(size: 7)
        var y = listTop

        for entry in payload.papers {
            guard y - rowH > m else { break }
            let line = "\(entry.subjectName)  \(entry.seriesDisplay)  ATT \(entry.attemptNumber)"
            drawText(ctx, text: line,
                     rect: CGRect(x: m, y: y - rowH, width: W - 2 * m, height: rowH),
                     font: rowFont)
            y -= rowH + 2
        }
    }

    // MARK: - Drawing primitives

    static func strokeLine(_ ctx: CGContext,
                           x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) {
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
    }

    static func drawText(_ ctx: CGContext,
                         text: String, rect: CGRect,
                         font: NSFont,
                         alignment: NSTextAlignment = .left) {
        let ps = NSMutableParagraphStyle()
        ps.alignment     = alignment
        ps.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: NSColor.black,
            .paragraphStyle:  ps
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let fs      = CTFramesetterCreateWithAttributedString(attrStr)
        let path    = CGPath(rect: rect, transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, nil), ctx)
    }

    // MARK: - Brand font resolvers (matching PDFDocumentGenerator)

    /// Univers LT Std Bold Oblique → Helvetica Neue Bold Italic → system bold italic.
    /// Used for both "normal" header lines and (when italic) the "Label" subtitle.
    static func universHeaderFont(size: CGFloat, italic: Bool = false) -> NSFont {
        let candidates: [String] = italic
            ? ["UniversLTStd-BoldObl", "UniversLTStd-Bold",
               "Univers-BoldItalic",   "Univers-Bold",
               "HelveticaNeue-BoldItalic", "Helvetica-BoldOblique"]
            : ["UniversLTStd-Bold", "Univers-Bold",
               "HelveticaNeue-Bold", "Helvetica-Bold"]
        for name in candidates { if let f = NSFont(name: name, size: size) { return f } }
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        if italic {
            let desc = base.fontDescriptor.withSymbolicTraits([.bold, .italic])
            return NSFont(descriptor: desc, size: size) ?? base
        }
        return base
    }

    /// Regular Univers → Helvetica Neue → system font.
    static func universBodyFont(size: CGFloat) -> NSFont {
        let candidates = ["UniversLTStd", "Univers", "HelveticaNeue", "Helvetica"]
        for name in candidates { if let f = NSFont(name: name, size: size) { return f } }
        return NSFont.systemFont(ofSize: size)
    }

    /// IBM Logo → IBM Plex Mono Bold → heavy monospaced fallback.
    static func ibmLogoFont(size: CGFloat) -> NSFont {
        let candidates = ["IBM-Logo", "IBMPlexMono-Bold",
                          "IBMPlexMono-SemiBold", "IBMPlexSans-Bold",
                          "IBMPlexSans-SemiBold"]
        for name in candidates { if let f = NSFont(name: name, size: size) { return f } }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)
    }
}
