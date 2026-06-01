import AppKit
import PDFKit
import CoreGraphics
import CoreText

/// Generates an A4 Batch Examination Records Index List.
///
/// Layout mirrors the Examination Records Index A4 sheet:
///   - Header band 60 pt: "Batch Examination Records Index" / "List" (Univers),
///     RMS (IBM Logo font) top-right, barcode centred, barcode reference below
///   - Header bottom rule
///   - Batch barcode reference row
///   - Column-header row + data rows for each paper in the batch
struct BatchListPDFGenerator {

    // MARK: - A4 page geometry
    static let pageWidth:  CGFloat = 595.276
    static let pageHeight: CGFloat = 841.890
    private static let margin: CGFloat = 24

    // MARK: - Payload

    struct BatchListPayload {
        let batchBarcode: String
        let papers:       [BatchPaperEntry]
    }

    struct BatchPaperEntry {
        let subjectName:    String
        let seriesDisplay:  String
        let attemptNumber:  Int16
        let barcodeValue:   String
        let printTimestamp: Date
    }

    // MARK: - Date formatters

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd MMMM yyyy"; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "(HH:mm:ss)"; return f
    }()

    // MARK: - Public API

    static func generateAndPrint(payload: BatchListPayload) {
        guard let data = buildPDFData(payload: payload) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appending(component: "\(payload.batchBarcode)-list.pdf")
        try? data.write(to: tmp)
        guard let doc = PDFDocument(url: tmp) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        // Force A4 paper: set both the named paper and the explicit dimensions
        info.paperName    = NSPrinter.PaperName(rawValue: "A4")
        info.paperSize    = NSSize(width: pageWidth, height: pageHeight)
        info.orientation  = .portrait
        info.leftMargin   = 0; info.rightMargin  = 0
        info.topMargin    = 0; info.bottomMargin = 0
        if let op = doc.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) {
            op.run()
        }
    }

    static func buildPDFData(payload: BatchListPayload) -> Data? {
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

    // MARK: - Layout engine (mirrors PDFDocumentGenerator header exactly)

    private static func draw(ctx: CGContext, payload: BatchListPayload) {
        let W = pageWidth   // 595.276
        let H = pageHeight  // 841.890
        let m = margin      // 24

        // ── White background ──────────────────────────────────────────────────
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(0.5)

        // ── Header band (60 pt, mirrors PDFDocumentGenerator exactly) ─────────
        let headerBottom: CGFloat = H - m - 60   // 757.89

        // Title lines — top-left (same offsets as Examination Records Index)
        drawText(ctx,
                 text: "Batch Examination Records Index",
                 rect: CGRect(x: m, y: headerBottom + 32, width: 240, height: 18),
                 font: universHeaderFont(size: 14))
        drawText(ctx,
                 text: "List",
                 rect: CGRect(x: m, y: headerBottom + 14, width: 80, height: 18),
                 font: universHeaderFont(size: 14, italic: true))

        // RMS logotype — flush top-right
        drawText(ctx,
                 text: "RMS",
                 rect: CGRect(x: W - m - 80, y: headerBottom + 18, width: 80, height: 26),
                 font: ibmLogoFont(size: 20), alignment: .right)

        // Barcode — centred between title block and RMS logo (same geometry as A4 index)
        let barcodeHdrLeft:  CGFloat = 250
        let barcodeHdrRight: CGFloat = W - m - 88
        let barcodeHdrWidth            = barcodeHdrRight - barcodeHdrLeft
        let barcodeHdrHeight: CGFloat  = 38
        let barcodeHdrBottom           = headerBottom + 10

        if let barcodeImg = BarcodeGenerator.generateImage(for: payload.batchBarcode, scaleFactor: 3.0),
           let cgBarcode  = barcodeImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.interpolationQuality = .none
            ctx.draw(cgBarcode,
                     in: CGRect(x: barcodeHdrLeft, y: barcodeHdrBottom,
                                width: barcodeHdrWidth, height: barcodeHdrHeight))
            ctx.interpolationQuality = .default
        }

        // Barcode reference — Courier, same as A4 index
        drawText(ctx,
                 text: payload.batchBarcode,
                 rect: CGRect(x: barcodeHdrLeft, y: headerBottom + 1,
                              width: barcodeHdrWidth, height: 9),
                 font: NSFont(name: "Courier", size: 7)
                      ?? NSFont.monospacedSystemFont(ofSize: 7, weight: .regular),
                 alignment: .center)

        // Header bottom rule
        strokeLine(ctx, x1: m, y1: headerBottom, x2: W - m, y2: headerBottom)

        // ── Table setup ───────────────────────────────────────────────────────
        // Columns: ATT (60) | Subject (170) | Exam Series (130) | Printed Date (100) | Time (remainder)
        let col1x: CGFloat = m          // ATT
        let col2x = col1x + 60          // Subject
        let col3x = col2x + 170         // Exam Series
        let col4x = col3x + 130         // Printed Date
        let col5x = col4x + 100         // Time
        let colEnd: CGFloat = W - m

        // Column header row (12 pt)
        let colHdrY    = headerBottom - 22
        let labelRowH: CGFloat = 18
        let hdrFont    = NSFont.boldSystemFont(ofSize: 7.5)

        // Draw header row background
        ctx.setFillColor(CGColor(gray: 0.92, alpha: 1.0))
        ctx.fill(CGRect(x: col1x, y: colHdrY, width: colEnd - col1x, height: labelRowH))
        ctx.setFillColor(NSColor.white.cgColor)

        // Outer box for header row
        strokeLine(ctx, x1: col1x, y1: colHdrY, x2: colEnd,  y2: colHdrY)
        strokeLine(ctx, x1: col1x, y1: colHdrY + labelRowH, x2: colEnd, y2: colHdrY + labelRowH)
        strokeLine(ctx, x1: col1x, y1: colHdrY, x2: col1x, y2: colHdrY + labelRowH)
        strokeLine(ctx, x1: colEnd, y1: colHdrY, x2: colEnd, y2: colHdrY + labelRowH)
        for x in [col2x, col3x, col4x, col5x] {
            strokeLine(ctx, x1: x, y1: colHdrY, x2: x, y2: colHdrY + labelRowH)
        }

        let hdrLabelY = colHdrY + 5
        drawText(ctx, text: "ATT",          rect: CGRect(x: col1x + 4, y: hdrLabelY, width: 52,  height: 10), font: hdrFont)
        drawText(ctx, text: "Subject",      rect: CGRect(x: col2x + 4, y: hdrLabelY, width: 160, height: 10), font: hdrFont)
        drawText(ctx, text: "Exam Series",  rect: CGRect(x: col3x + 4, y: hdrLabelY, width: 120, height: 10), font: hdrFont)
        drawText(ctx, text: "Printed Date", rect: CGRect(x: col4x + 4, y: hdrLabelY, width: 90,  height: 10), font: hdrFont)
        drawText(ctx, text: "Time",         rect: CGRect(x: col5x + 4, y: hdrLabelY, width: colEnd - col5x - 8, height: 10), font: hdrFont)

        // ── Data rows ─────────────────────────────────────────────────────────
        let rowH:    CGFloat = 20
        let rowFont  = NSFont(name: "Courier", size: 8)
                       ?? NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let bodyFont = NSFont.systemFont(ofSize: 9)
        var rowY     = colHdrY

        for entry in payload.papers {
            guard rowY - rowH > m else { break }
            rowY -= rowH

            // Row outline and vertical dividers
            strokeLine(ctx, x1: col1x, y1: rowY, x2: colEnd, y2: rowY)
            strokeLine(ctx, x1: col1x, y1: rowY + rowH, x2: colEnd, y2: rowY + rowH)
            strokeLine(ctx, x1: col1x, y1: rowY, x2: col1x, y2: rowY + rowH)
            strokeLine(ctx, x1: colEnd, y1: rowY, x2: colEnd, y2: rowY + rowH)
            for x in [col2x, col3x, col4x, col5x] {
                strokeLine(ctx, x1: x, y1: rowY, x2: x, y2: rowY + rowH)
            }

            let cellY = rowY + 5
            drawText(ctx, text: "ATT \(entry.attemptNumber)",
                     rect: CGRect(x: col1x + 4, y: cellY, width: 52, height: 12), font: rowFont)
            drawText(ctx, text: entry.subjectName,
                     rect: CGRect(x: col2x + 4, y: cellY, width: 160, height: 12), font: bodyFont)
            drawText(ctx, text: entry.seriesDisplay,
                     rect: CGRect(x: col3x + 4, y: cellY, width: 120, height: 12), font: bodyFont)
            drawText(ctx, text: dateFmt.string(from: entry.printTimestamp),
                     rect: CGRect(x: col4x + 4, y: cellY, width: 90, height: 12), font: bodyFont)
            drawText(ctx, text: timeFmt.string(from: entry.printTimestamp),
                     rect: CGRect(x: col5x + 4, y: cellY, width: colEnd - col5x - 8, height: 12), font: bodyFont)
        }
    }

    // MARK: - Drawing primitives

    private static func strokeLine(_ ctx: CGContext,
                                   x1: CGFloat, y1: CGFloat,
                                   x2: CGFloat, y2: CGFloat) {
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
    }

    private static func drawText(_ ctx: CGContext,
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
        CTFrameDraw(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0),
                                            CGPath(rect: rect, transform: nil), nil), ctx)
    }

    // MARK: - Font resolvers (identical to PDFDocumentGenerator)

    private static func universHeaderFont(size: CGFloat, italic: Bool = false) -> NSFont {
        let candidates: [String] = italic
            ? ["UniversLTStd-BoldObl", "UniversLTStd-Bold",
               "Univers-BoldItalic",   "Univers-Bold",
               "HelveticaNeue-BoldItalic", "Helvetica-BoldOblique"]
            : ["UniversLTStd-BoldObl", "UniversLTStd-Bold",
               "Univers-BoldItalic",   "Univers-Bold",
               "HelveticaNeue-BoldItalic", "Helvetica-BoldOblique"]
        for name in candidates { if let f = NSFont(name: name, size: size) { return f } }
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        let desc = base.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: desc, size: size) ?? base
    }

    private static func ibmLogoFont(size: CGFloat) -> NSFont {
        let candidates = ["IBM-Logo", "IBMPlexMono-Bold",
                          "IBMPlexMono-SemiBold", "IBMPlexSans-Bold",
                          "IBMPlexSans-SemiBold", "IBMPlexMono-Regular"]
        for name in candidates { if let f = NSFont(name: name, size: size) { return f } }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)
    }
}
