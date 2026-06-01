import AppKit
import PDFKit
import CoreGraphics
import CoreText

/// Generates an A4 chronological event receipt for a completed ETS session
/// and opens the macOS print panel (which includes PDF ▾ → "Save as PDF…").
///
/// Layout:
///   Header band  — "Exam Timing Receipt" label + barcode centred + RMS logotype
///   Info row     — subject · series · attempt number · time used
///   Column headers (Univers bold) + rule
///   Event table  — Q1, Break 1, Q2 … (Courier New for content)
///   Footer       — generation timestamp
struct ETSPDFReceiptGenerator {

    // MARK: - Page geometry (A4 portrait)

    private static let pageWidth:  CGFloat = 595.276   // 210 mm
    private static let pageHeight: CGFloat = 841.890   // 297 mm
    private static let margin:     CGFloat = 24

    // MARK: - Public entry

    /// Generates the receipt PDF and opens the system print panel.
    /// Pass `targetSecondsPerMark` so over-target rows can be highlighted.
    static func generate(attempt: AttemptMO, paper: PaperMO, targetSecondsPerMark: Double = 0) {
        guard let data = buildReceiptData(attempt: attempt, paper: paper,
                                          targetSecondsPerMark: targetSecondsPerMark) else { return }
        let barcode = attempt.barcodeValue ?? "receipt"
        let tmp = FileManager.default.temporaryDirectory
            .appending(component: "ETS-Receipt-\(barcode).pdf")
        do {
            try data.write(to: tmp)
        } catch {
            print("[ETSReceipt] Write failed: \(error.localizedDescription)")
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

    static func buildReceiptData(attempt: AttemptMO, paper: PaperMO,
                                  targetSecondsPerMark: Double = 0) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)
        drawReceipt(ctx: ctx, attempt: attempt, paper: paper,
                    targetSecondsPerMark: targetSecondsPerMark)
        ctx.endPDFPage()
        ctx.closePDF()

        return data as Data
    }

    // MARK: - Drawing

    private static func drawReceipt(ctx: CGContext, attempt: AttemptMO, paper: PaperMO,
                                     targetSecondsPerMark: Double) {
        let W = pageWidth   // 595.276
        let H = pageHeight  // 841.890
        let m = margin      // 24

        // Background
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // ── Header band (top 50 pt) ────────────────────────────────────────
        let headerBottom: CGFloat = H - m - 50  // 767.890

        drawText(ctx,
                 text: "Exam Timing Receipt",
                 rect: CGRect(x: m, y: headerBottom + 20, width: 200, height: 18),
                 font: universFont(size: 11, bold: true, italic: true),
                 color: .black)

        // RMS logotype — IBM Plex Sans Bold (IBM logo look)
        drawText(ctx,
                 text: "RMS",
                 rect: CGRect(x: W - m - 72, y: headerBottom + 14, width: 72, height: 26),
                 font: ibmLogoFont(size: 20),
                 color: .black,
                 alignment: .right)

        // Barcode in header centre
        if let barcodeVal = attempt.barcodeValue,
           let barcodeImg = BarcodeGenerator.generateImage(for: barcodeVal, scaleFactor: 3.0),
           let cgBar = barcodeImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bX: CGFloat = 230
            let bW: CGFloat = W - m - 80 - bX - 8
            let bH: CGFloat = 36
            let bY: CGFloat = headerBottom + 7
            ctx.interpolationQuality = .none
            ctx.draw(cgBar, in: CGRect(x: bX, y: bY, width: bW, height: bH))
        }

        // Header rule
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: m, y: headerBottom))
        ctx.addLine(to: CGPoint(x: W - m, y: headerBottom))
        ctx.strokePath()

        // ── Info row ─────────────────────────────────────────────────────
        let infoY: CGFloat = headerBottom - 22
        let subjectName = paper.subject?.name ?? "—"
        let series      = paper.rawSeriesName?.capitalized ?? "—"
        let attNum      = attempt.attemptNumber
        let elapsed     = attempt.durationInSeconds
        let infoText    = "\(subjectName)  ·  \(series)  ·  ATT #\(attNum)  ·  \(formatTime(elapsed))"
        drawText(ctx,
                 text: infoText,
                 rect: CGRect(x: m, y: infoY, width: W - 2 * m, height: 14),
                 font: universFont(size: 8.5, bold: false, italic: false),
                 color: NSColor.darkGray.cgColor)

        // ── Column headers (Univers Bold) ──────────────────────────────────
        let tableTop: CGFloat = infoY - 24
        let col0x: CGFloat = m
        let col1x: CGFloat = m + 28      // Seq #
        let col2x: CGFloat = col1x + 120 // Label
        let col3x: CGFloat = col2x + 72  // Type
        let col4x: CGFloat = col3x + 72  // Duration
        let col5x: CGFloat = col4x + 72  // Target
        let col6x: CGFloat = col5x + 60  // Marks

        let colHeaders: [(String, CGFloat)] = [
            ("#", col0x), ("Label", col1x), ("Type", col2x),
            ("Duration", col3x), ("Target", col4x), ("Marks", col5x)
        ]
        for (hdr, x) in colHeaders {
            drawText(ctx,
                     text: hdr,
                     rect: CGRect(x: x, y: tableTop, width: 110, height: 11),
                     font: universFont(size: 7.5, bold: true, italic: false),
                     color: NSColor.darkGray.cgColor)
        }

        ctx.move(to: CGPoint(x: m, y: tableTop - 3))
        ctx.addLine(to: CGPoint(x: W - m, y: tableTop - 3))
        ctx.setLineWidth(0.3)
        ctx.strokePath()

        // ── Build label → maxMarks lookup from QP question structures ──────
        let qpStructures = (paper.questionStructures as? Set<QuestionStructureMO>)?
            .filter { ($0.source ?? "questionPaper") == "questionPaper" } ?? []
        var marksByLabel: [String: Int16] = [:]
        for q in qpStructures {
            let stripped = ETSTimerEngine.stripPageRange(q.questionLabel ?? "")
            if !stripped.isEmpty { marksByLabel[stripped] = q.maxMarks }
        }

        // ── Event rows (Courier New for content) ─────────────────────────
        let logs = (attempt.eventLogs as? Set<ETSEventLogMO>)?
            .sorted { $0.sequenceIndex < $1.sequenceIndex } ?? []

        let rowH:    CGFloat = 14
        var cursorY: CGFloat = tableTop - rowH - 2

        for log in logs {
            guard cursorY > m + 20 else { break }   // stop near bottom margin

            let isBreak = log.eventType?.hasPrefix("BREAK") ?? false

            // Strip page-range annotation from label
            let rawLabel    = log.label ?? ""
            let cleanLabel  = ETSTimerEngine.stripPageRange(rawLabel)

            let typeLabel: String = {
                switch log.eventType {
                case "QUESTION_SPENT": return "Q"
                case "BREAK_A":        return "Brk-A"
                case "BREAK_NA":       return "Brk-NA"
                default:               return log.eventType ?? "?"
                }
            }()

            // Determine if over target
            let maxMarks    = isBreak ? 0 : Int(marksByLabel[cleanLabel] ?? 0)
            let targetSecs  = targetSecondsPerMark > 0 && maxMarks > 0
                              ? targetSecondsPerMark * Double(maxMarks) : 0.0
            let isOver      = !isBreak && targetSecs > 0
                              && Double(log.durationSeconds) > targetSecs
            let targetStr   = targetSecs > 0 ? formatTime(Int64(targetSecs)) : "—"
            let markStr     = isBreak ? "—" : String(format: "%.1f", log.marksEarned)

            // Over-target row background tint
            if isOver {
                ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.06).cgColor)
                ctx.fill(CGRect(x: m, y: cursorY - 2, width: W - 2 * m, height: rowH))
            }

            let rowColor: CGColor = isOver ? NSColor.systemRed.cgColor : .black

            drawText(ctx, text: "\(log.sequenceIndex)",
                     rect: CGRect(x: col0x, y: cursorY, width: 26, height: 11),
                     font: courierFont(size: 8),
                     color: rowColor)
            drawText(ctx, text: cleanLabel,
                     rect: CGRect(x: col1x, y: cursorY, width: 118, height: 11),
                     font: courierFont(size: 8, bold: !isBreak),
                     color: rowColor)
            drawText(ctx, text: typeLabel,
                     rect: CGRect(x: col2x, y: cursorY, width: 70, height: 11),
                     font: courierFont(size: 8),
                     color: isBreak ? NSColor.darkGray.cgColor : rowColor)
            drawText(ctx, text: formatTime(log.durationSeconds),
                     rect: CGRect(x: col3x, y: cursorY, width: 70, height: 11),
                     font: courierFont(size: 8),
                     color: rowColor)
            drawText(ctx, text: targetStr,
                     rect: CGRect(x: col4x, y: cursorY, width: 58, height: 11),
                     font: courierFont(size: 8),
                     color: isBreak ? NSColor.darkGray.cgColor : NSColor.darkGray.cgColor)
            drawText(ctx, text: markStr,
                     rect: CGRect(x: col5x, y: cursorY, width: 55, height: 11),
                     font: courierFont(size: 8),
                     color: .black)

            cursorY -= rowH
        }

        // ── Closing rule ──────────────────────────────────────────────────
        ctx.move(to: CGPoint(x: m, y: cursorY + rowH - 2))
        ctx.addLine(to: CGPoint(x: W - m, y: cursorY + rowH - 2))
        ctx.setLineWidth(0.3)
        ctx.strokePath()

        // ── Footer ────────────────────────────────────────────────────────
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        drawText(ctx,
                 text: "Generated \(df.string(from: Date()))",
                 rect: CGRect(x: m, y: m, width: W - 2 * m, height: 10),
                 font: universFont(size: 7, bold: false, italic: false),
                 color: NSColor.lightGray.cgColor)
    }

    // MARK: - Text drawing

    private enum TextAlignment { case left, center, right }

    private static func drawText(
        _ ctx:      CGContext,
        text:       String,
        rect:       CGRect,
        font:       CTFont,
        color:      CGColor = .black,
        alignment:  TextAlignment = .left
    ) {
        let paraStyle = NSMutableParagraphStyle()
        switch alignment {
        case .left:   paraStyle.alignment = .left
        case .center: paraStyle.alignment = .center
        case .right:  paraStyle.alignment = .right
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: NSColor(cgColor: color) ?? .black,
            .paragraphStyle:  paraStyle
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    // MARK: - Font helpers

    /// Univers (or Helvetica Neue fallback) for headings and info text.
    private static func universFont(size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        let candidates: [String] = {
            switch (bold, italic) {
            case (true,  true):  return ["UniversLTStd-BoldObl", "HelveticaNeue-BoldItalic"]
            case (true,  false): return ["UniversLTStd-Bold",    "HelveticaNeue-Bold"]
            case (false, true):  return ["UniversLTStd-Obl",     "HelveticaNeue-Italic"]
            case (false, false): return ["UniversLTStd",         "HelveticaNeue"]
            }
        }()
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return CTFontCreateWithName(name as CFString, size, nil)
            }
        }
        return CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
    }

    /// IBM Plex Sans Bold (or best available fallback) for the RMS logotype.
    private static func ibmLogoFont(size: CGFloat) -> CTFont {
        for name in ["IBMPlexSans-Bold", "IBMPlexSansCondensed-Bold",
                     "IBMPlexMono-Bold", "HelveticaNeue-Bold", "Helvetica-Bold"] {
            if NSFont(name: name, size: size) != nil {
                return CTFontCreateWithName(name as CFString, size, nil)
            }
        }
        return CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    /// Courier New for table content rows.
    private static func courierFont(size: CGFloat, bold: Bool = false) -> CTFont {
        let candidates = bold
            ? ["CourierNewPS-BoldMT", "Courier-Bold"]
            : ["CourierNewPSMT", "Courier"]
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return CTFontCreateWithName(name as CFString, size, nil)
            }
        }
        let fallbackName = bold ? "Courier-Bold" : "Courier"
        return CTFontCreateWithName(fallbackName as CFString, size, nil)
    }

    // MARK: - Time formatting

    private static func formatTime(_ s: Int64) -> String {
        let t = max(s, 0)
        let h = t / 3600
        let m = (t % 3600) / 60
        let sec = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
