import AppKit
import PDFKit
import CoreGraphics
import CoreText

// MARK: - DQAPrintManager

/// Print helpers for DQA compiled PDFs and the A4 index sheet.
enum DQAPrintManager {

    // MARK: - A4 geometry (matches PDFDocumentGenerator)

    private static let W: CGFloat = 595.276   // 210 mm
    private static let H: CGFloat = 841.890   // 297 mm
    private static let m: CGFloat = 24        // margin

    /// 0.5 cm ruled-line interval in PostScript points ( 5/10 × 72/2.54 ≈ 14.17 pt ).
    private static let ruleSpacingPt: CGFloat = (5.0 / 10.0) * (72.0 / 2.54)

    /// Subtle ruled-line colour — RGB(0.8, 0.8, 0.8) at 60 % opacity.
    private static let ruleColor: CGColor = CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.6)

    // MARK: - Print compiled PDF (mark scheme / standalone QP)

    /// Opens the system print dialog for the PDF at `path`.
    static func printPDF(at path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let doc = PDFDocument(url: url) else { return }
        let info          = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize    = NSSize(width: W, height: H)
        info.topMargin    = 0; info.bottomMargin = 0
        info.leftMargin   = 0; info.rightMargin  = 0
        if let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) {
            op.showsPrintPanel    = true
            op.showsProgressPanel = true
            op.run()
        }
    }

    // MARK: - Print DQA Paper (index sheet + optional blank + compiled QP)

    /// Builds a combined PDF and opens the system print dialog.
    ///
    /// When `isDoubleSided` is `true` a blank A4 page is inserted between the
    /// index sheet (page 1) and the exam questions (page 3+) so the exam text
    /// never prints onto the physical reverse of the index sheet cover.
    static func printDQAPaper(for record: DifficultQuestionsArchiveMO,
                               isDoubleSided: Bool = false) {
        guard let combined = buildDQACombinedPDF(for: record, isDoubleSided: isDoubleSided),
              combined.pageCount > 0 else { return }
        let info          = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize    = NSSize(width: W, height: H)
        info.leftMargin   = 0; info.rightMargin  = 0
        info.topMargin    = 0; info.bottomMargin = 0
        if let op = combined.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) {
            op.showsPrintPanel    = true
            op.showsProgressPanel = true
            op.run()
        }
    }

    // MARK: - Print Index Sheet only (opens in Preview)

    static func printIndexSheet(for record: DifficultQuestionsArchiveMO) {
        guard let data = renderIndexSheet(for: record) else { return }
        let dqaBarcode = record.dqaBarcode ?? "DQA"
        do {
            let dir  = try DQAFileManager.ensureDirectory(for: dqaBarcode)
            let dest = dir.appendingPathComponent("IndexSheet.pdf")
            try data.write(to: dest)
            NSWorkspace.shared.open(dest)
        } catch { /* silently ignore write errors */ }
    }

    // MARK: - Combined PDF builder (shared by print and LAN routing)

    /// Assembles the index sheet, optional blank separator, and compiled QP
    /// pages into one `PDFDocument`.  Returns `nil` if the index sheet cannot
    /// be rendered.
    private static func buildDQACombinedPDF(for record: DifficultQuestionsArchiveMO,
                                             isDoubleSided: Bool) -> PDFDocument? {
        guard let indexData = renderIndexSheet(for: record) else { return nil }
        let combined = PDFDocument()

        // Page 1: Index sheet
        if let doc = PDFDocument(data: indexData) {
            for i in 0..<doc.pageCount {
                if let pg = doc.page(at: i) { combined.insert(pg, at: combined.pageCount) }
            }
        }

        // Page 2: Blank separator — double-sided mode only
        if isDoubleSided,
           let blankData = blankPageData(),
           let blankDoc  = PDFDocument(data: blankData),
           let blankPage = blankDoc.page(at: 0) {
            combined.insert(blankPage, at: combined.pageCount)
        }

        // Page 3+: Compiled exam question pages
        if let qpPath = record.compiledQuestionPDFPath,
           FileManager.default.fileExists(atPath: qpPath),
           let doc = PDFDocument(url: URL(fileURLWithPath: qpPath)) {
            for i in 0..<doc.pageCount {
                if let pg = doc.page(at: i) { combined.insert(pg, at: combined.pageCount) }
            }
        }

        return combined.pageCount > 0 ? combined : nil
    }

    /// Returns the raw bytes for a blank white A4 PDF page.
    private static func blankPageData() -> Data? {
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.endPDFPage()
        ctx.closePDF()
        return mutableData as Data
    }

    // MARK: - LAN Routing (Windows Print Server)

    /// Routes a PDF file at `path` to the Windows print server via the LAN.
    static func routeFileToWindows(at path: String,
                                   filename: String,
                                   mode: WindowsPrintMode) async throws {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw CocoaError(.fileReadUnknown)
        }
        try await LANPrintRouter.sendToWindows(data: data, filename: filename, mode: mode)
    }

    /// Builds the combined DQA paper (with optional blank separator) and routes it to Windows.
    static func routeDQAPaperToWindows(for record: DifficultQuestionsArchiveMO,
                                        isDoubleSided: Bool = false,
                                        mode: WindowsPrintMode) async throws {
        guard let combined = buildDQACombinedPDF(for: record, isDoubleSided: isDoubleSided),
              let data = combined.dataRepresentation() else {
            throw CocoaError(.fileReadUnknown)
        }
        try await LANPrintRouter.sendToWindows(data: data, filename: "DQAPaper.pdf", mode: mode)
    }

    /// Renders the DQA index sheet and routes it to Windows.
    static func routeIndexSheetToWindows(for record: DifficultQuestionsArchiveMO,
                                          mode: WindowsPrintMode) async throws {
        guard let data = renderIndexSheet(for: record) else {
            throw CocoaError(.fileReadUnknown)
        }
        try await LANPrintRouter.sendToWindows(data: data, filename: "IndexSheet.pdf", mode: mode)
    }

    // MARK: - Index Sheet Rendering

    /// Renders an A4 DQA index sheet that exactly mirrors the Examination Records Index
    /// layout from PDFDocumentGenerator — same fonts, section-header pattern, and ruled
    /// line style.
    ///
    /// Layout (top → bottom):
    ///   Header band (60 pt)          — title | DQA barcode (unified) | RMS
    ///   Info table (104 pt)          — 4 col × header row + 2 data rows
    ///   Selected Questions section   — bordered box, multi-column bullet list
    ///   คำถามที่ต้องดู section        — separator + label + strokeRect + ruled lines
    ///   Additional Notes section     — separator + label + strokeRect + ruled lines
    static func renderIndexSheet(for record: DifficultQuestionsArchiveMO) -> Data? {
        var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)

        // White background
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(0.5)

        let origBC = record.originalBarcode ?? ""
        let dqaBC  = record.dqaBarcode ?? ""

        // ── Zone anchors ─────────────────────────────────────────────────────
        //   Header: 60 pt
        //   Table:  104 pt  (12 pt label row + 46 pt × 2 data rows)
        let headerBottom: CGFloat = H - m - 60      // 757.890
        let labelRowH:   CGFloat  = 12
        let dataRowH:    CGFloat  = 46
        let tableH                = labelRowH + dataRowH * 2   // 104
        let tableTop:    CGFloat  = headerBottom
        let tableBottom: CGFloat  = tableTop - tableH           // 653.890

        // ── Selected-questions box sizing ────────────────────────────────────
        //   • Each question line: lineH = 15 pt  (14 pt font + 1 pt leading;
        //     CTFrameDraw needs rect.height > ascender+descender ≈ 12 pt for 10 pt
        //     font — using 15 pt gives comfortable headroom so text never silently drops)
        //   • Box padding: boxPad pt top and bottom
        //   • Up to maxLinesPerCol lines per column; overflow → 2 columns;
        //     beyond 2 columns → "… and N more" in the last slot
        let questions     = record.decodedSourceQuestions
        let lineH:    CGFloat = 15
        let boxPad:   CGFloat = 8
        let maxLinesPerCol    = 8
        let numCols           = questions.count <= maxLinesPerCol ? 1 : 2
        let maxVisible        = maxLinesPerCol * numCols
        let hasOverflow       = questions.count > maxVisible
        // If overflow, reserve one slot for "… and N more"
        let totalShown        = hasOverflow ? maxVisible - 1 : questions.count
        let colLines          = numCols == 1 ? totalShown : maxLinesPerCol
        let qBoxH: CGFloat    = max(CGFloat(colLines) * lineH + boxPad * 2, 30)

        // All downstream zone anchors depend on qBoxH
        let sqLabelY:     CGFloat = tableBottom - 20        // separator/label zone
        let sqBottom:     CGFloat = sqLabelY - qBoxH
        let reviewLabelY: CGFloat = sqBottom - 20
        let reviewBottom: CGFloat = reviewLabelY - 220
        let notesLabelY:  CGFloat = reviewBottom - 20

        // ═══════════════════════════════════════════════════════════════════
        // HEADER BAND — matches PDFDocumentGenerator geometry exactly
        // ═══════════════════════════════════════════════════════════════════

        drawText(ctx,
                 text: "DQA Archive",
                 rect: CGRect(x: m, y: headerBottom + 32, width: 240, height: 18),
                 font: universHeaderFont(size: 14), alignment: .left)

        drawText(ctx,
                 text: "Index",
                 rect: CGRect(x: m, y: headerBottom + 14, width: 240, height: 18),
                 font: universHeaderFont(size: 14), alignment: .left)

        drawText(ctx,
                 text: "RMS",
                 rect: CGRect(x: W - m - 80, y: headerBottom + 18, width: 80, height: 26),
                 font: ibmLogoFont(size: 20), alignment: .right)

        // DQA barcode (unified — encodes both original + DQA info) centred in header
        let barcodeHdrLeft:  CGFloat = 250
        let barcodeHdrRight: CGFloat = W - m - 88
        if let img = BarcodeGenerator.generateImage(for: dqaBC, scaleFactor: 3.0),
           let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: barcodeHdrLeft,
                                    y: headerBottom + 10,
                                    width: barcodeHdrRight - barcodeHdrLeft,
                                    height: 38))
            ctx.interpolationQuality = .default
        }

        strokeLine(ctx, x1: m, y1: headerBottom, x2: W - m, y2: headerBottom)

        // ═══════════════════════════════════════════════════════════════════
        // INFO TABLE — 4 columns, header row + 2 data rows
        //   col1 (Paper)      x=24  → 224   (200 pt)
        //   col2 (Printed)    x=224 → 372   (148 pt)
        //   col3 (Completed)  x=372 → 472   (100 pt)
        //   col4 (ATT. NUM)   x=472 → 571   ( ~99 pt)
        // ═══════════════════════════════════════════════════════════════════
        let col1x: CGFloat = m            //  24
        let col2x: CGFloat = m + 200      // 224
        let col3x: CGFloat = m + 348      // 372
        let col4x: CGFloat = m + 448      // 472
        let colEnd: CGFloat = W - m       // 571.276

        strokeRect(ctx, rect: CGRect(x: col1x, y: tableBottom,
                                     width: colEnd - col1x, height: tableH))
        strokeLine(ctx, x1: col2x, y1: tableBottom, x2: col2x, y2: tableTop)
        strokeLine(ctx, x1: col3x, y1: tableBottom, x2: col3x, y2: tableTop)
        strokeLine(ctx, x1: col4x, y1: tableBottom, x2: col4x, y2: tableTop)

        let colHeaderY = tableTop - labelRowH + 2
        let hdrFont    = NSFont.boldSystemFont(ofSize: 7.5)
        drawText(ctx, text: "Paper",
                 rect: CGRect(x: col1x+5, y: colHeaderY, width: col2x-col1x-10, height: 10),
                 font: hdrFont, alignment: .left)
        drawText(ctx, text: "Printed",
                 rect: CGRect(x: col2x+5, y: colHeaderY, width: col3x-col2x-10, height: 10),
                 font: hdrFont, alignment: .left)
        drawText(ctx, text: "Completed",
                 rect: CGRect(x: col3x+5, y: colHeaderY, width: col4x-col3x-10, height: 10),
                 font: hdrFont, alignment: .left)
        drawText(ctx, text: "ATT. NUM",
                 rect: CGRect(x: col4x+5, y: colHeaderY, width: colEnd-col4x-10, height: 10),
                 font: hdrFont, alignment: .left)

        let dataTop    = tableTop - labelRowH
        strokeLine(ctx, x1: col1x, y1: dataTop, x2: colEnd, y2: dataTop)

        let rowABottom = dataTop - dataRowH
        strokeLine(ctx, x1: col1x, y1: rowABottom, x2: colEnd, y2: rowABottom)

        let dateFmt = DateFormatter.dqaGregorianFormat("dd MMM yyyy")
        let timeFmt = DateFormatter.dqaGregorianFormat("(HH:mm)")

        // ── Row A: Original Examination ───────────────────────────────────
        let rowATop = dataTop
        let seriesDisplay = record.examSeries.map {
            SeriesNormalizationEngine.displayName(from: $0)
        } ?? "—"

        drawText(ctx, text: record.subject ?? "—",
                 rect: CGRect(x: col1x+5, y: rowATop-15, width: col2x-col1x-10, height: 13),
                 font: NSFont.systemFont(ofSize: 10), alignment: .left)
        drawText(ctx, text: seriesDisplay,
                 rect: CGRect(x: col1x+5, y: rowATop-29, width: col2x-col1x-10, height: 13),
                 font: NSFont.systemFont(ofSize: 9), alignment: .left)
        drawText(ctx, text: "ORIGINAL EXAMINATION",
                 rect: CGRect(x: col1x+5, y: rowABottom+4, width: col2x-col1x-10, height: 10),
                 font: NSFont.systemFont(ofSize: 6.5, weight: .semibold),
                 color: NSColor.secondaryLabelColor, alignment: .left)

        let origPrint: Date? = {
            if !origBC.isEmpty,
               let attempt = PersistenceController.shared.findAttempt(barcodeValue: origBC) {
                return attempt.printTimestamp
            }
            return record.createdTimestamp
        }()
        if let pt = origPrint {
            drawText(ctx, text: dateFmt.string(from: pt),
                     rect: CGRect(x: col2x+5, y: rowATop-15, width: col3x-col2x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
            drawText(ctx, text: timeFmt.string(from: pt),
                     rect: CGRect(x: col2x+5, y: rowATop-29, width: col3x-col2x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
        } else {
            drawText(ctx, text: "—",
                     rect: CGRect(x: col2x+5, y: rowATop-22, width: col3x-col2x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
        }

        if let ct = record.originalCompletedTimestamp {
            drawText(ctx, text: dateFmt.string(from: ct),
                     rect: CGRect(x: col3x+5, y: rowATop-15, width: col4x-col3x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
            drawText(ctx, text: timeFmt.string(from: ct),
                     rect: CGRect(x: col3x+5, y: rowATop-29, width: col4x-col3x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
        } else {
            drawText(ctx, text: "—",
                     rect: CGRect(x: col3x+5, y: rowATop-22, width: col4x-col3x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
        }

        drawText(ctx, text: "\(record.parentExamAttemptNumber)",
                 rect: CGRect(x: col4x+4, y: rowABottom+3, width: colEnd-col4x-8, height: dataRowH-6),
                 font: NSFont.boldSystemFont(ofSize: 22), alignment: .center)

        // ── Row B: This DQA ───────────────────────────────────────────────
        let rowBTop    = rowABottom
        let rowBBottom = tableBottom

        drawText(ctx, text: dqaBC.isEmpty ? "—" : dqaBC,
                 rect: CGRect(x: col1x+5, y: rowBTop-16, width: col2x-col1x-10, height: 13),
                 font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular), alignment: .left)
        drawText(ctx, text: "THIS DQA",
                 rect: CGRect(x: col1x+5, y: rowBBottom+4, width: col2x-col1x-10, height: 10),
                 font: NSFont.systemFont(ofSize: 6.5, weight: .semibold),
                 color: NSColor.secondaryLabelColor, alignment: .left)

        let now = Date()
        drawText(ctx, text: dateFmt.string(from: now),
                 rect: CGRect(x: col2x+5, y: rowBTop-15, width: col3x-col2x-10, height: 13),
                 font: NSFont.systemFont(ofSize: 9), alignment: .left)
        drawText(ctx, text: timeFmt.string(from: now),
                 rect: CGRect(x: col2x+5, y: rowBTop-29, width: col3x-col2x-10, height: 13),
                 font: NSFont.systemFont(ofSize: 9), alignment: .left)

        if let cd = record.committedDate {
            drawText(ctx, text: dateFmt.string(from: cd),
                     rect: CGRect(x: col3x+5, y: rowBTop-15, width: col4x-col3x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 9), alignment: .left)
        } else {
            drawText(ctx, text: "Not scheduled",
                     rect: CGRect(x: col3x+5, y: rowBTop-22, width: col4x-col3x-10, height: 13),
                     font: NSFont.systemFont(ofSize: 8), alignment: .left)
        }

        drawText(ctx, text: "D\(record.dqaAttemptNumber)",
                 rect: CGRect(x: col4x+4, y: rowBBottom+3, width: colEnd-col4x-8, height: dataRowH-6),
                 font: NSFont.boldSystemFont(ofSize: 18), alignment: .center)

        // ═══════════════════════════════════════════════════════════════════
        // SELECTED QUESTIONS — bordered box, multi-column when > maxLinesPerCol
        //
        // Section header pattern (matches PDFDocumentGenerator exactly):
        //   • horizontal separator at sqLabelY + 18
        //   • bold label at sqLabelY + 2
        //   • strokeRect content box from sqBottom → sqLabelY
        //
        // Column layout:
        //   • 1 column  when questions.count ≤ maxLinesPerCol
        //   • 2 columns when questions.count > maxLinesPerCol
        //   • "… and N more" in last slot if questions exceed 2 × maxLinesPerCol
        //   • Vertical divider separates columns inside the box
        //
        // Text rect height = lineH = 15 pt for a 10 pt font.
        // CTFrameDraw silently drops lines whose rect.height ≤ (ascender + |descender|)
        // ≈ 12 pt for SF Pro 10 pt — using 15 pt gives safe headroom.
        // ═══════════════════════════════════════════════════════════════════
        strokeLine(ctx, x1: m, y1: sqLabelY + 18, x2: W - m, y2: sqLabelY + 18)
        drawText(ctx,
                 text: "Selected Questions (\(questions.count))",
                 rect: CGRect(x: m, y: sqLabelY + 2, width: W - 2*m, height: 15),
                 font: NSFont.boldSystemFont(ofSize: 11), alignment: .left)

        strokeRect(ctx, rect: CGRect(x: m, y: sqBottom, width: W - 2*m, height: qBoxH))

        // Column geometry
        let qColW  = (W - 2*m) / CGFloat(numCols)
        let qTextW = qColW - 16   // 8 pt inset each side

        // Vertical divider between columns
        if numCols == 2 {
            strokeLine(ctx, x1: m + qColW, y1: sqBottom, x2: m + qColW, y2: sqLabelY)
        }

        // Draw question bullets
        // y formula: sqLabelY - boxPad - row * lineH - lineH  →  this is rect.minY
        // rect.maxY = rect.minY + lineH = sqLabelY - boxPad - row * lineH  (just inside box top for row 0)
        for qi in 0..<totalShown {
            let col  = qi / maxLinesPerCol
            let row  = qi % maxLinesPerCol
            let qX   = m + CGFloat(col) * qColW + 8
            let qY   = sqLabelY - boxPad - CGFloat(row) * lineH - lineH   // rect.minY
            let display = dqaDisplayLabel(questions[qi])
            drawText(ctx, text: "• \(display)",
                     rect: CGRect(x: qX, y: qY, width: qTextW, height: lineH),
                     font: NSFont.systemFont(ofSize: 10))
        }

        // "… and N more" in the next slot after totalShown
        if hasOverflow {
            let col  = totalShown / maxLinesPerCol
            let row  = totalShown % maxLinesPerCol
            let qX   = m + CGFloat(col) * qColW + 8
            let qY   = sqLabelY - boxPad - CGFloat(row) * lineH - 12   // slightly shorter
            drawText(ctx,
                     text: "  … and \(questions.count - totalShown) more",
                     rect: CGRect(x: qX, y: qY, width: qTextW, height: 12),
                     font: NSFont.systemFont(ofSize: 9),
                     color: NSColor.secondaryLabelColor)
        }

        // ═══════════════════════════════════════════════════════════════════
        // คำถามที่ต้องดู — separator + label + strokeRect + 0.5 cm ruled lines
        // (identical pattern to PDFDocumentGenerator "REVIEW" section)
        // ═══════════════════════════════════════════════════════════════════
        strokeLine(ctx, x1: m, y1: reviewLabelY + 18, x2: W - m, y2: reviewLabelY + 18)
        drawText(ctx,
                 text: "คำถามที่ต้องดู",
                 rect: CGRect(x: m, y: reviewLabelY + 2, width: 200, height: 15),
                 font: NSFont.boldSystemFont(ofSize: 11), alignment: .left)

        let reviewRect = CGRect(x: m, y: reviewBottom,
                                width: W - 2*m, height: reviewLabelY - reviewBottom)
        strokeRect(ctx, rect: reviewRect)
        drawRuledLines(ctx: ctx, inRect: reviewRect,
                       spacing: ruleSpacingPt, color: ruleColor)

        // ═══════════════════════════════════════════════════════════════════
        // ADDITIONAL NOTES — separator + label + strokeRect + 0.5 cm ruled lines
        // (identical pattern to PDFDocumentGenerator "NOTES" section)
        // ═══════════════════════════════════════════════════════════════════
        strokeLine(ctx, x1: m, y1: notesLabelY + 18, x2: W - m, y2: notesLabelY + 18)
        drawText(ctx,
                 text: "Additional Notes",
                 rect: CGRect(x: m, y: notesLabelY + 2, width: 200, height: 15),
                 font: NSFont.boldSystemFont(ofSize: 11), alignment: .left)

        let notesRect = CGRect(x: m, y: m, width: W - 2*m, height: notesLabelY - m)
        strokeRect(ctx, rect: notesRect)
        drawRuledLines(ctx: ctx, inRect: notesRect,
                       spacing: ruleSpacingPt, color: ruleColor)

        ctx.endPDFPage()
        ctx.closePDF()
        return mutableData as Data
    }

    // MARK: - Drawing primitives (static, CTFrameDraw — no NSGraphicsContext needed)

    private static func strokeLine(_ ctx: CGContext,
                                   x1: CGFloat, y1: CGFloat,
                                   x2: CGFloat, y2: CGFloat) {
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
    }

    private static func strokeRect(_ ctx: CGContext, rect: CGRect) {
        ctx.stroke(rect, width: 0.5)
    }

    /// Draws horizontal ruled guide lines inside `rect` — identical to
    /// PDFDocumentGenerator.drawRuledLines: clips insetBy(2,2), 0.3 pt line width.
    private static func drawRuledLines(
        ctx: CGContext,
        inRect rect: CGRect,
        spacing: CGFloat,
        color: CGColor
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
        color: NSColor = .black,
        alignment: NSTextAlignment = .left
    ) {
        let ps = NSMutableParagraphStyle()
        ps.alignment     = alignment
        ps.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: color,
            .paragraphStyle:  ps
        ]
        let attrStr     = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path        = CGPath(rect: rect, transform: nil)
        let frame       = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    // MARK: - Brand font resolvers (mirrors PDFDocumentGenerator — IBM-Logo first)

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
