import AppKit
import PDFKit
import CoreGraphics
import CoreText

/// Generates a print-ready A4 tracking sheet and dispatches it to the system
/// print panel (which includes the built-in PDF ▾ → "Save as PDF…" button).
struct PDFDocumentGenerator {

    // MARK: - A4 page geometry (PostScript points at 72 DPI)

    static let pageWidth:  CGFloat = 595.276   // 210 mm
    static let pageHeight: CGFloat = 841.890   // 297 mm
    private static let margin: CGFloat = 24

    // MARK: - Metric constants

    /// 0.5 cm ruled-line interval in PostScript points  ( 5/10 × 72/2.54 ≈ 14.17 pt ).
    private static let ruleSpacingPt: CGFloat = (5.0 / 10.0) * (72.0 / 2.54)

    /// Subtle ruled-line colour — RGB(0.8, 0.8, 0.8) at 60 % opacity.
    private static let ruleColor: CGColor = CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.6)

    // MARK: - Public entry

    struct PrintPayload {
        let subjectName:       String
        let seriesDisplayName: String
        let normalizedSeries:  String
        let attemptNumber:     Int16
        let barcodeValue:      String
        let printTimestamp:    Date
    }

    /// Generates A4 PDF data then presents the system print panel.
    /// The print panel's built-in "PDF ▾ → Save as PDF…" button lets the user
    /// save directly to disk without a physical printer.
    static func generateAndPrint(payload: PrintPayload) {
        guard let data = buildPDFData(payload: payload) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appending(component: "\(payload.barcodeValue).pdf")
        do {
            try data.write(to: tmp)
        } catch {
            print("[PDF] Temp write failed: \(error.localizedDescription)")
            return
        }
        guard let doc = PDFDocument(url: tmp) else { return }
        let info          = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize    = NSSize(width: pageWidth, height: pageHeight)
        info.leftMargin   = 0
        info.rightMargin  = 0
        info.topMargin    = 0
        info.bottomMargin = 0
        if let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) {
            op.run()
        }
    }

    // MARK: - PDF construction

    static func buildPDFData(payload: PrintPayload) -> Data? {
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

    private static func draw(ctx: CGContext, payload: PrintPayload) {
        let W = pageWidth   // 595.276
        let H = pageHeight  // 841.890
        let m = margin      // 24

        // ── Background ──────────────────────────────────────────────────────
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(0.5)

        // ── Zone Y anchors (y = 0 at page bottom) ───────────────────────────
        //   Header band      : 60 pt
        //   Info table       : 100 pt
        //   Completed row    : 32 pt
        //   Section label gap: 20 pt each
        //   Review content   : 220 pt
        //   Notes content    : remaining ~346 pt to bottom margin
        let headerBottom:    CGFloat = H - m - 60        // 757.890
        let tableTop:        CGFloat = headerBottom
        let tableBottom:     CGFloat = tableTop  - 100   // 657.890
        let completedBottom: CGFloat = tableBottom - 32  // 625.890
        let reviewLabelY:    CGFloat = completedBottom - 20  // 605.890
        let reviewBottom:    CGFloat = reviewLabelY    - 220 // 385.890
        let notesLabelY:     CGFloat = reviewBottom    - 20  // 365.890
        // notes content: m (24) → notesLabelY (365.890) = ~342 pt

        // ═══════════════════════════════════════════════════════════════════
        // HEADER BAND — 60 pt tall
        // ═══════════════════════════════════════════════════════════════════

        drawText(ctx,
                 text: "Examination Records",
                 rect: CGRect(x: m, y: headerBottom + 32, width: 240, height: 18),
                 font: universHeaderFont(size: 14),
                 alignment: .left)

        drawText(ctx,
                 text: "Index",
                 rect: CGRect(x: m, y: headerBottom + 14, width: 240, height: 18),
                 font: universHeaderFont(size: 14),
                 alignment: .left)

        // ── "RMS" logotype — flush top-right ─────────────────────────────
        drawText(ctx,
                 text: "RMS",
                 rect: CGRect(x: W - m - 80, y: headerBottom + 18, width: 80, height: 26),
                 font: ibmLogoFont(size: 20),
                 alignment: .right)

        // ── Barcode — centred between title block and RMS logo ────────────
        let barcodeHdrLeft:  CGFloat = 250
        let barcodeHdrRight: CGFloat = W - m - 88   // 4 pt gap before RMS block
        let barcodeHdrWidth            = barcodeHdrRight - barcodeHdrLeft
        let barcodeHdrHeight: CGFloat  = 38
        let barcodeHdrBottom           = headerBottom + 10

        if let barcodeImg = BarcodeGenerator.generateImage(for: payload.barcodeValue, scaleFactor: 3.0),
           let cgBarcode  = barcodeImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.interpolationQuality = .none
            ctx.draw(cgBarcode, in: CGRect(x: barcodeHdrLeft, y: barcodeHdrBottom,
                                           width: barcodeHdrWidth, height: barcodeHdrHeight))
            ctx.interpolationQuality = .default
        }

        // Header bottom rule
        strokeLine(ctx, x1: m, y1: headerBottom, x2: W - m, y2: headerBottom)

        // ═══════════════════════════════════════════════════════════════════
        // INFO TABLE — four columns (100 pt total height)
        //   col1 (Paper)      : 200 pt
        //   col2 (Printed)    : 148 pt
        //   col3 (Completed)  : 100 pt
        //   col4 (ATT. NUM)   :  ~99 pt (to colEnd)
        // Column-header row   : 12 pt → data area : 88 pt
        // ═══════════════════════════════════════════════════════════════════
        let col1x:  CGFloat = m              //  24
        let col2x:  CGFloat = m + 200        // 224
        let col3x:  CGFloat = m + 348        // 372
        let col4x:  CGFloat = m + 448        // 472
        let colEnd: CGFloat = W - m          // 571.276

        // Outer box
        strokeRect(ctx, rect: CGRect(x: col1x, y: tableBottom,
                                     width: colEnd - col1x, height: tableTop - tableBottom))

        // Vertical dividers
        strokeLine(ctx, x1: col2x, y1: tableBottom, x2: col2x, y2: tableTop)
        strokeLine(ctx, x1: col3x, y1: tableBottom, x2: col3x, y2: tableTop)
        strokeLine(ctx, x1: col4x, y1: tableBottom, x2: col4x, y2: tableTop)

        // Column header labels (12 pt header row)
        let labelRowH: CGFloat = 12
        let colHeaderY         = tableTop - labelRowH + 2
        let hdrFont            = NSFont.boldSystemFont(ofSize: 7.5)

        drawText(ctx, text: "Paper",
                 rect: CGRect(x: col1x + 5, y: colHeaderY, width: col2x - col1x - 10, height: 10),
                 font: hdrFont, alignment: .left)
        drawText(ctx, text: "Printed",
                 rect: CGRect(x: col2x + 5, y: colHeaderY, width: col3x - col2x - 10, height: 10),
                 font: hdrFont, alignment: .left)
        drawText(ctx, text: "Completed",
                 rect: CGRect(x: col3x + 5, y: colHeaderY, width: col4x - col3x - 10, height: 10),
                 font: hdrFont, alignment: .left)
        drawText(ctx, text: "ATT. NUM",
                 rect: CGRect(x: col4x + 5, y: colHeaderY, width: colEnd - col4x - 10, height: 10),
                 font: hdrFont, alignment: .left)

        // Header-row separator
        strokeLine(ctx, x1: col1x, y1: tableTop - labelRowH, x2: colEnd, y2: tableTop - labelRowH)

        // ── Data area (88 pt) ─────────────────────────────────────────────
        let dataTop = tableTop - labelRowH

        // Col 1: subject name, series, barcode reference
        drawText(ctx, text: payload.subjectName,
                 rect: CGRect(x: col1x + 5, y: dataTop - 14, width: col2x - col1x - 10, height: 13),
                 font: NSFont.systemFont(ofSize: 10), alignment: .left)
        drawText(ctx, text: payload.seriesDisplayName,
                 rect: CGRect(x: col1x + 5, y: dataTop - 28, width: col2x - col1x - 10, height: 12),
                 font: NSFont.systemFont(ofSize: 9), alignment: .left)
        drawText(ctx, text: payload.barcodeValue,
                 rect: CGRect(x: col1x + 5, y: tableBottom + 4,
                              width: col2x - col1x - 10, height: 10),
                 font: NSFont(name: "Courier", size: 7)
                      ?? NSFont.monospacedSystemFont(ofSize: 7, weight: .regular),
                 alignment: .left)

        // Col 2: print timestamp
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "dd MMMM yyyy"
        let dateLine = dateFmt.string(from: payload.printTimestamp)
        dateFmt.dateFormat = "(HH:mm:ss)"
        let timeLine = dateFmt.string(from: payload.printTimestamp)

        drawText(ctx, text: dateLine,
                 rect: CGRect(x: col2x + 5, y: dataTop - 14, width: col3x - col2x - 10, height: 12),
                 font: NSFont.systemFont(ofSize: 9), alignment: .left)
        drawText(ctx, text: timeLine,
                 rect: CGRect(x: col2x + 5, y: dataTop - 28, width: col3x - col2x - 10, height: 12),
                 font: NSFont.systemFont(ofSize: 9), alignment: .left)

        // Col 4: bare bold integer attempt number — fills the 88 pt data cell
        drawText(ctx, text: "\(payload.attemptNumber)",
                 rect: CGRect(x: col4x + 4, y: tableBottom + 3,
                              width: colEnd - col4x - 8, height: dataTop - tableBottom - 6),
                 font: NSFont.boldSystemFont(ofSize: 28), alignment: .center)

        // ═══════════════════════════════════════════════════════════════════
        // COMPLETED ROW  (32 pt tall, full table width)
        // ═══════════════════════════════════════════════════════════════════
        strokeRect(ctx, rect: CGRect(x: col1x, y: completedBottom,
                                     width: colEnd - col1x, height: tableBottom - completedBottom))

        drawText(ctx, text: "Completed:",
                 rect: CGRect(x: col1x + 5, y: completedBottom + 10, width: 72, height: 12),
                 font: NSFont.boldSystemFont(ofSize: 9), alignment: .left)

        // ── Checkbox targets ─────────────────────────────────────────────
        let cbSize: CGFloat = 8
        let cbY: CGFloat = completedBottom + (32 - cbSize) / 2  // vertically centred

        // [ ] Practice Paper
        let cb1x: CGFloat = col1x + 80
        ctx.stroke(CGRect(x: cb1x, y: cbY, width: cbSize, height: cbSize), width: 0.5)
        drawText(ctx, text: "Practice Paper",
                 rect: CGRect(x: cb1x + cbSize + 4, y: completedBottom + 10.5, width: 90, height: 11),
                 font: NSFont.systemFont(ofSize: 7.5), alignment: .left)

        // [ ] Timed & Graded
        let cb2x: CGFloat = cb1x + 110
        ctx.stroke(CGRect(x: cb2x, y: cbY, width: cbSize, height: cbSize), width: 0.5)
        drawText(ctx, text: "Timed & Graded",
                 rect: CGRect(x: cb2x + cbSize + 4, y: completedBottom + 10.5, width: 100, height: 11),
                 font: NSFont.systemFont(ofSize: 7.5), alignment: .left)

        // ═══════════════════════════════════════════════════════════════════
        // REVIEW — "คำถามที่ต้องดู"   border + 0.5 cm ruled lines
        // ═══════════════════════════════════════════════════════════════════
        strokeLine(ctx, x1: m, y1: reviewLabelY + 18, x2: W - m, y2: reviewLabelY + 18)
        drawText(ctx, text: "คำถามที่ต้องดู",
                 rect: CGRect(x: m, y: reviewLabelY + 2, width: 200, height: 15),
                 font: NSFont.boldSystemFont(ofSize: 11), alignment: .left)

        let reviewRect = CGRect(x: m, y: reviewBottom,
                                width: W - 2 * m, height: reviewLabelY - reviewBottom)
        strokeRect(ctx, rect: reviewRect)
        drawRuledLines(ctx: ctx, inRect: reviewRect, spacing: ruleSpacingPt, color: ruleColor)

        // ═══════════════════════════════════════════════════════════════════
        // NOTES — "Additional Notes"   border + 0.5 cm ruled lines
        // ═══════════════════════════════════════════════════════════════════
        strokeLine(ctx, x1: m, y1: notesLabelY + 18, x2: W - m, y2: notesLabelY + 18)
        drawText(ctx, text: "Additional Notes",
                 rect: CGRect(x: m, y: notesLabelY + 2, width: 200, height: 15),
                 font: NSFont.boldSystemFont(ofSize: 11), alignment: .left)

        let notesRect = CGRect(x: m, y: m,
                               width: W - 2 * m, height: notesLabelY - m)
        strokeRect(ctx, rect: notesRect)
        drawRuledLines(ctx: ctx, inRect: notesRect, spacing: ruleSpacingPt, color: ruleColor)
    }

    // MARK: - Drawing primitives

    private static func strokeLine(
        _ ctx: CGContext, x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat
    ) {
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
    }

    private static func strokeRect(_ ctx: CGContext, rect: CGRect) {
        ctx.stroke(rect, width: 0.5)
    }

    /// Draws horizontal ruled guide lines inside `rect` at `spacing`-point intervals.
    private static func drawRuledLines(
        ctx: CGContext, inRect rect: CGRect, spacing: CGFloat, color: CGColor
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.3)

        let clip = rect.insetBy(dx: 2, dy: 2)
        ctx.clip(to: clip)

        let x1 = clip.minX + 2
        let x2 = clip.maxX - 2
        var y  = clip.maxY - spacing

        while y > clip.minY {
            ctx.move(to:    CGPoint(x: x1, y: y))
            ctx.addLine(to: CGPoint(x: x2, y: y))
            ctx.strokePath()
            y -= spacing
        }

        ctx.restoreGState()
    }

    private static func drawText(
        _ ctx: CGContext,
        text: String,
        rect: CGRect,
        font: NSFont,
        alignment: NSTextAlignment = .left
    ) {
        let ps = NSMutableParagraphStyle()
        ps.alignment     = alignment
        ps.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: NSColor.black,
            .paragraphStyle:  ps
        ]
        let attrStr     = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path        = CGPath(rect: rect, transform: nil)
        let frame       = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    // MARK: - Brand font resolvers

    /// IBM Logo → IBM Plex Mono Bold → IBM Plex Sans Bold → heavy monospaced fallback.
    private static func ibmLogoFont(size: CGFloat) -> NSFont {
        let candidates = [
            "IBM-Logo",
            "IBMPlexMono-Bold",
            "IBMPlexMono-SemiBold",
            "IBMPlexSans-Bold", "IBMPlexSans-SemiBold",
            "IBMPlexMono-Regular",
        ]
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)
    }

    /// Univers LT Std Bold Oblique → Helvetica Neue Bold Italic →
    /// synthesised bold+italic from system neo-grotesque.
    private static func universHeaderFont(size: CGFloat) -> NSFont {
        let candidates = [
            "UniversLTStd-BoldObl", "UniversLTStd-Bold",
            "Univers-BoldItalic",   "Univers-Bold",
            "HelveticaNeue-BoldItalic", "Helvetica-BoldOblique",
        ]
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        let desc = base.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: desc, size: size) ?? base
    }
}
