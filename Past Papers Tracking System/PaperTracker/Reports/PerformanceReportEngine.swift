import CoreData
import CoreGraphics
import CoreText
import AppKit
import Foundation

// MARK: - Public types

struct ReportConfig {
    var subjects:        [SubjectMO]
    var generatedDate:   Date              = Date()
    var includeSections: Set<ReportSection> = Set(ReportSection.allCases)
    var toField:         String?           = nil
    var fromField:       String?           = nil
}

enum ReportSection: String, CaseIterable {
    case averageCalculator  = "Average Calculator"
    case checklist          = "Checklist"
    case completeLogs       = "Complete Logs"
    case dqaAnalysis        = "DQA Analysis"
    case activityStats      = "Activity Statistics"
    case examReadiness      = "Exam Readiness"
    case productivityCharts = "Productivity Charts"
}

enum ReportStatus: String {
    case onTarget     = "On Target"
    case pastTarget   = "Past Target"
    case behindTarget = "Behind Target"
    case targetAway   = "Target Away"

    var nsColor: NSColor {
        // Neutral charcoal for table text cells
        return NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    }
    // Colour-coded hue used only for the large cover-page status headline
    var coverTextColor: NSColor {
        switch self {
        case .onTarget:     return NSColor(red: 0.14, green: 0.50, blue: 0.20, alpha: 1)  // forest green
        case .pastTarget:   return NSColor(red: 0.62, green: 0.14, blue: 0.10, alpha: 1)  // dark crimson
        case .behindTarget: return NSColor(red: 0.65, green: 0.30, blue: 0.05, alpha: 1)  // dark amber
        case .targetAway:   return NSColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1)  // neutral slate
        }
    }
}

// MARK: - Engine

final class PerformanceReportEngine {

    // ── Page geometry ────────────────────────────────────────────────────────
    private static let W:  CGFloat = 595.276
    private static let H:  CGFloat = 841.890
    private static let mL: CGFloat = 56
    private static let mR: CGFloat = 56
    private static let mT: CGFloat = 64
    private static let mB: CGFloat = 56
    private static var cW: CGFloat { W - mL - mR }

    // ── Apple-native colour tokens ───────────────────────────────────────────
    // Typography
    private static let ink1 = NSColor(red: 0.109, green: 0.109, blue: 0.118, alpha: 1) // #1C1C1E
    private static let ink2 = NSColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1) // #3A3A3C
    private static let ink3 = NSColor(red: 0.388, green: 0.388, blue: 0.400, alpha: 1) // #636366
    // Structure
    private static let sep  = NSColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1) // #E5E5EA
    private static let hdrBg = NSColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1) // #F5F5F7
    // Cover — pure charcoal/dark for branding; accent is neutral slate gray (no blue)
    private static let coverDark   = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) // #1C1C1E
    private static let coverAccent = NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1) // neutral slate gray

    // ── Fonts ────────────────────────────────────────────────────────────────
    private static func bodyFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let candidates = bold
            ? ["UniversLTStd-Bold", "Univers-Bold", "UniversLT-Bold", "HelveticaNeue-Bold"]
            : ["UniversLTStd", "Univers", "UniversLT", "HelveticaNeue"]
        for n in candidates { if let f = NSFont(name: n, size: size) { return f } }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }
    private static func headFont(_ size: CGFloat) -> NSFont {
        let candidates = ["IBMPlexSans-SemiBold", "IBMPlexSans-Bold",
                          "HelveticaNeue-Medium", "HelveticaNeue-Bold"]
        for n in candidates { if let f = NSFont(name: n, size: size) { return f } }
        return NSFont.boldSystemFont(ofSize: size)
    }
    // IBM Logo font — used for RMS logo / header branding
    private static func rmsFont(_ size: CGFloat) -> NSFont {
        let candidates = ["IBM-Logo", "IBMPlexMono-Bold", "IBMPlexMono-SemiBold",
                          "IBMPlexSans-SemiBold"]
        for n in candidates { if let f = NSFont(name: n, size: size) { return f } }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
    }

    // ── Public entry ─────────────────────────────────────────────────────────
    static func generate(config: ReportConfig, context: NSManagedObjectContext) -> Data {
        PerformanceReportEngine(config: config, ctx: context).build()
    }

    // ── Private state ────────────────────────────────────────────────────────
    private let config:  ReportConfig
    private let ctx:     NSManagedObjectContext
    private var pdfCtx:  CGContext!
    private var curY:    CGFloat = 0
    private var pageN:   Int     = 0
    private var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)

    private var allAttempts: [AttemptMO] = []
    private var allDQAs:     [DifficultQuestionsArchiveMO] = []
    private var tableRowIsEven = true

    private init(config: ReportConfig, ctx: NSManagedObjectContext) {
        self.config = config
        self.ctx    = ctx
    }

    // ── Build ─────────────────────────────────────────────────────────────────
    private func build() -> Data {
        let data = NSMutableData()
        pdfCtx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!,
                           mediaBox: &mediaBox, nil)!
        // Pre-fetch
        let subjectIDs   = Set(config.subjects.compactMap { $0.id })
        let subjectNames = Set(config.subjects.compactMap { $0.name })
        allAttempts = ((try? ctx.fetch(AttemptMO.fetchRequest())) ?? [])
            .filter { guard let sid = $0.paper?.subject?.id else { return false }; return subjectIDs.contains(sid) }
        allDQAs     = ((try? ctx.fetch(DifficultQuestionsArchiveMO.fetchRequest())) ?? [])
            .filter { subjectNames.contains($0.subject ?? "") }

        let metrics = computeAllMetrics()
        drawCoverPage(metrics: metrics)
        if config.includeSections.contains(.averageCalculator) { drawAverageCalculator(metrics: metrics) }
        if config.includeSections.contains(.checklist)         { drawChecklist() }
        if config.includeSections.contains(.completeLogs)      { drawCompleteLogs() }
        if config.includeSections.contains(.dqaAnalysis)       { drawDQAAnalysis() }
        if config.includeSections.contains(.activityStats)     { drawActivityStats(metrics: metrics) }
        if config.includeSections.contains(.examReadiness)     { drawExamReadiness(metrics: metrics) }
        if config.includeSections.contains(.productivityCharts){ drawProductivityCharts() }

        pdfCtx.endPage()
        pdfCtx.closePDF()
        return data as Data
    }

    // ── Page management ───────────────────────────────────────────────────────
    private func beginPage() {
        if pageN > 0 { pdfCtx.endPage() }
        pdfCtx.beginPage(mediaBox: &mediaBox)
        pageN += 1
        curY = Self.mT
        drawPageChrome()
    }

    private func ensureSpace(_ pts: CGFloat) {
        if curY + pts > Self.H - Self.mB { beginPage() }
    }

    private func pdfY(_ topY: CGFloat) -> CGFloat { Self.H - topY }

    // ── Page chrome ────────────────────────────────────────────────────────────
    private func drawPageChrome() {
        guard pageN > 1 else { return }
        // Thin top rule
        let ruleTopY = pdfY(Self.mT - 12)
        strokeHLine(y: ruleTopY, x0: Self.mL, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        // "RMS · Performance Report" left
        // "RMS" in IBM Logo font; the rest in Univers
        let rmsLogoW = strWidth("RMS", font: Self.rmsFont(7))
        drawStr("RMS", x: Self.mL, y: Self.H - Self.mT + 14,
                font: Self.rmsFont(7), color: Self.ink3)
        drawStr("  ·  PERFORMANCE REPORT", x: Self.mL + rmsLogoW, y: Self.H - Self.mT + 14,
                font: Self.bodyFont(7), color: Self.ink3, kern: 0.8)
        // Page number right
        let pn = "Page \(pageN)"
        drawStr(pn, x: Self.W - Self.mR - strWidth(pn, font: Self.bodyFont(8)),
                y: Self.H - Self.mT + 14, font: Self.bodyFont(8), color: Self.ink3)
        // Bottom rule + footer
        let footRuleY = pdfY(Self.H - Self.mB + 18)
        strokeHLine(y: footRuleY, x0: Self.mL, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        let rmsLogoW2 = strWidth("RMS", font: Self.rmsFont(7))
        drawStr("RMS", x: Self.mL, y: Self.mB - 12, font: Self.rmsFont(7), color: Self.ink3)
        drawStr("  ·  Revision Management System  ·  Confidential",
                x: Self.mL + rmsLogoW2, y: Self.mB - 12, font: Self.bodyFont(7), color: Self.ink3, kern: 0.4)
        let dateStr = dateFmt.string(from: config.generatedDate)
        drawStr("Generated \(dateStr)",
                x: Self.W - Self.mR - strWidth("Generated \(dateStr)", font: Self.bodyFont(7)),
                y: Self.mB - 12, font: Self.bodyFont(7), color: Self.ink3)
    }

    // ── Cover page ─────────────────────────────────────────────────────────────
    private func drawCoverPage(metrics: [SubjectMetrics]) {
        beginPage()

        // Compact dark band
        let bandH: CGFloat = 92
        fillRect(CGRect(x: 0, y: Self.H - bandH, width: Self.W, height: bandH),
                 color: Self.coverDark)
        // Thin accent strip below band
        fillRect(CGRect(x: 0, y: Self.H - bandH - 3, width: Self.W, height: 3),
                 color: Self.coverAccent)

        // Top-right: IBM Logo "RMS" — white, smaller, vertically centred
        let rmsBigFont = Self.rmsFont(30)
        let rmsBigW    = strWidth("RMS", font: rmsBigFont)
        drawStr("RMS", x: Self.W - Self.mR - rmsBigW, y: Self.H - 72,
                font: rmsBigFont, color: NSColor(white: 0.95, alpha: 1))

        // Main title — tighter spacing, fits within 92pt band
        drawStr("Performance", x: Self.mL, y: Self.H - 42,
                font: Self.headFont(30), color: .white)
        drawStr("Report", x: Self.mL, y: Self.H - 74,
                font: Self.headFont(30), color: NSColor(white: 0.72, alpha: 1))

        // ── Body below band ────────────────────────────────────────────────────
        let bodyY: CGFloat = bandH + 3 + 36   // band + strip + top padding
        curY = bodyY

        // Date + subjects in body (light, above To/From block)
        let dateStr = dateFmt.string(from: config.generatedDate)
        drawStr(dateStr, x: Self.mL, y: pdfY(curY + 13),
                font: Self.bodyFont(11, bold: true), color: Self.ink1)
        curY += 18
        let subNames = config.subjects.compactMap { $0.name }.joined(separator: "  ·  ")
        if !subNames.isEmpty {
            drawStr(subNames, x: Self.mL, y: pdfY(curY + 12),
                    font: Self.bodyFont(9), color: Self.ink3)
            curY += 16
        }
        curY += 10

        // Memo fields — only render rows that have a value (or Date, which is always present)
        let toVal   = config.toField   ?? ""
        let fromVal = config.fromField ?? ""
        var memoRows: [(String, String)] = []
        if !toVal.isEmpty   { memoRows.append(("To",   toVal)) }
        if !fromVal.isEmpty { memoRows.append(("From", fromVal)) }
        memoRows.append(("Date", dateStr))
        for (label, value) in memoRows {
            ensureSpace(22)
            let lw = strWidth(label + "  ", font: Self.bodyFont(9, bold: true))
            drawStr(label, x: Self.mL, y: pdfY(curY + 14),
                    font: Self.bodyFont(9, bold: true), color: Self.ink3)
            drawStr(value, x: Self.mL + lw + 4, y: pdfY(curY + 14),
                    font: Self.bodyFont(9), color: Self.ink1)
            strokeHLine(y: pdfY(curY + 16), x0: Self.mL, x1: Self.W - Self.mR,
                        color: Self.sep, width: 0.5)
            curY += 20
        }
        curY += 12

        // ── Status snapshot table ──────────────────────────────────────────────
        drawSubLabel("Status Snapshot")
        curY += 4
        let snapCols: [(String, CGFloat)] = [
            ("Subject", 162), ("Done", 48), ("Remaining", 68),
            ("Exam Date", 90), ("Status", 80)
        ]
        drawTableHeader(snapCols)
        for m in metrics {
            let examStr = m.subject.examDate1.map { dateFmt.string(from: $0) } ?? "—"
            drawTableRow([m.name, "\(m.completedPapers)", "\(m.remaining)", examStr, m.status.rawValue],
                         cols: snapCols, statusCol: 4, status: m.status)
        }
        curY += 16

        // ── Executive narrative ────────────────────────────────────────────────
        drawSubLabel("Executive Analysis")
        curY += 6
        let narrative = synthesizeExecutiveSummary(metrics: metrics)
        drawParagraph(narrative, font: Self.bodyFont(10), color: Self.ink2)
        curY += 20

        // ── Overall status — large centred headline with colour coding ─────────
        let overallStatus = computeOverallStatus(from: metrics)
        ensureSpace(52)
        strokeHLine(y: pdfY(curY + 2), x0: Self.mL, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        let statusFont    = Self.headFont(22)
        let statusLabel   = overallStatus.rawValue.uppercased()
        let statusLabelW  = strWidth(statusLabel, font: statusFont)
        drawStr(statusLabel,
                x: Self.mL + (Self.cW - statusLabelW) / 2,
                y: pdfY(curY + 38),
                font: statusFont, color: overallStatus.coverTextColor)
        curY += 48
        strokeHLine(y: pdfY(curY), x0: Self.mL, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        curY += 8

        // Cover footer — IBM Logo for "RMS" only; Univers for remainder
        let rmsLogoW4 = strWidth("RMS", font: Self.rmsFont(7))
        drawStr("RMS", x: Self.mL, y: Self.mB - 12, font: Self.rmsFont(7), color: Self.ink3)
        drawStr("  ·  Revision Management System  ·  Confidential",
                x: Self.mL + rmsLogoW4, y: Self.mB - 12, font: Self.bodyFont(7), color: Self.ink3, kern: 0.4)
    }

    // ── Average Calculator ──────────────────────────────────────────────────────
    private func drawAverageCalculator(metrics: [SubjectMetrics]) {
        beginPage()
        drawSectionTitle("Average Calculator")

        // Analytical intro
        let best = metrics.max(by: { a, b in
            let aAvg = averageScore(for: a.subject)
            let bAvg = averageScore(for: b.subject)
            return aAvg < bAvg
        })
        let introText: String = {
            if let b = best, averageScore(for: b.subject) > 0 {
                let pct = averagePercent(for: b.subject)
                let pctStr = pct > 0 ? " (\(String(format: "%.0f", pct))%)" : ""
                return "Score distributions across all attempted paper series are shown below. \(b.name) leads with the highest average score\(pctStr) in the current tracking window. Series without completed attempts are excluded."
            }
            return "Score distributions across all attempted paper series are shown below. Series without completed attempts are excluded."
        }()
        drawParagraph(introText, font: Self.bodyFont(10), color: Self.ink2)
        curY += 8

        for subject in config.subjects {
            let papers = sortedPapers(for: subject)
            guard !papers.isEmpty else { continue }
            drawSubjectHeader(subject.name ?? "Unknown Subject")

            let cols: [(String, CGFloat)] = [
                ("Series", 120), ("Attempts", 58), ("Avg Score", 78),
                ("Avg %", 58), ("Best Grade", 78), ("Max Marks", 66)
            ]
            drawTableHeader(cols)

            for paper in papers {
                let attempts = completedAttempts(for: paper)
                guard !attempts.isEmpty else { continue }
                let avgScore = attempts.map { $0.totalScore }.reduce(0, +) / Double(attempts.count)
                let mm    = Self.maxMarks(for: paper)
                let avgPct = mm > 0 ? (avgScore / Double(mm) * 100) : 0
                let grades = attempts.compactMap { $0.rawGrade }.sorted()
                let series = SeriesNormalizationEngine.displayName(from: paper.normalizedSeries ?? "")
                drawTableRow([series, "\(attempts.count)",
                              String(format: "%.1f", avgScore),
                              mm > 0 ? String(format: "%.0f%%", avgPct) : "—",
                              grades.first ?? "—",
                              mm > 0 ? "\(mm)" : "—"],
                             cols: cols)
            }
            let allComp = papers.flatMap { completedAttempts(for: $0) }
            if !allComp.isEmpty {
                let avg = allComp.filter { $0.totalScore > 0 }.map { $0.totalScore }.reduce(0, +) /
                          Double(allComp.filter { $0.totalScore > 0 }.count.nonZero ?? 1)
                drawTableRow(["TOTAL / AVERAGE", "\(allComp.count)",
                              String(format: "%.1f", avg), "—", "—", "—"],
                             cols: cols, bold: true, summaryRow: true)
            }
            curY += 12
        }
    }

    // ── Checklist ───────────────────────────────────────────────────────────────
    private func drawChecklist() {
        beginPage()
        drawSectionTitle("Checklist")

        let unstarted = config.subjects.flatMap { sortedPapers(for: $0) }
            .filter { (($0.attempts as? Set<AttemptMO>) ?? []).isEmpty }.count
        let intro = unstarted > 0
            ? "\(unstarted) paper series remain unstarted across the selected subjects. Consistent engagement with these series over the coming weeks will strengthen examination readiness."
            : "All paper series have at least one recorded attempt. Completion grades and statuses are shown below."
        drawParagraph(intro, font: Self.bodyFont(10), color: Self.ink2)
        curY += 8

        for subject in config.subjects {
            let papers = sortedPapers(for: subject)
            guard !papers.isEmpty else { continue }
            let maxAtt   = papers.map { (($0.attempts as? Set<AttemptMO>) ?? []).count }.max() ?? 1
            let maxCols  = min(maxAtt, 6)
            drawSubjectHeader(subject.name ?? "Unknown Subject")

            var cols: [(String, CGFloat)] = [("Series", 130)]
            for i in 1...max(1, maxCols) { cols.append(("Att \(i)", 52)) }
            cols.append(("Status", 70))
            drawTableHeader(cols)

            for paper in papers {
                let attempts = ((paper.attempts as? Set<AttemptMO>) ?? [])
                    .sorted { ($0.printTimestamp ?? .distantPast) < ($1.printTimestamp ?? .distantPast) }
                let series = SeriesNormalizationEngine.displayName(from: paper.normalizedSeries ?? "")
                var values: [String] = [series]
                for i in 0..<maxCols {
                    if i < attempts.count {
                        let a = attempts[i]
                        values.append(a.isComplete ? (a.rawGrade ?? "Done") : "Pending")
                    } else { values.append("—") }
                }
                values.append(attempts.last.map { attStatus($0) } ?? "Not Started")
                drawTableRow(values, cols: cols)
            }
            curY += 10
        }
    }

    // ── Complete Logs ────────────────────────────────────────────────────────────
    private func drawCompleteLogs() {
        beginPage()
        drawSectionTitle("Complete Logs")
        let intro = "Full detail for every recorded attempt is shown below, including timestamps, scores, grades, ETS timing events, and supplementary notes."
        drawParagraph(intro, font: Self.bodyFont(10), color: Self.ink2)
        curY += 10

        for subject in config.subjects {
            let papers = sortedPapers(for: subject)
            guard !papers.isEmpty else { continue }
            drawSubjectHeader(subject.name ?? "Unknown Subject")

            for paper in papers {
                let attempts = ((paper.attempts as? Set<AttemptMO>) ?? [])
                    .sorted { $0.attemptNumber < $1.attemptNumber }
                guard !attempts.isEmpty else { continue }
                let series = SeriesNormalizationEngine.displayName(from: paper.normalizedSeries ?? "")
                ensureSpace(24)
                drawStr(series, x: Self.mL + 10, y: pdfY(curY + 14),
                        font: Self.bodyFont(10, bold: true), color: Self.ink1)
                curY += 18
                for attempt in attempts { drawAttemptDetailBlock(attempt, paper: paper) }
                curY += 6
            }
        }
    }

    private func drawAttemptDetailBlock(_ a: AttemptMO, paper: PaperMO) {
        let rowH: CGFloat = 15
        ensureSpace(rowH * 6 + 10)

        // Attempt sub-header (minimal — just a light separator line above)
        strokeHLine(y: pdfY(curY + 1), x0: Self.mL + 10, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        curY += 4
        let barcode = a.barcodeValue ?? "—"
        drawStr("Attempt \(a.attemptNumber)  ·  \(barcode)",
                x: Self.mL + 10, y: pdfY(curY + 13),
                font: Self.bodyFont(8, bold: true), color: Self.ink1)
        curY += 16

        func infoLine(_ label: String, _ value: String) {
            ensureSpace(rowH)
            let lw: CGFloat = 96
            drawStr(label + ":", x: Self.mL + 18, y: pdfY(curY + 11),
                    font: Self.bodyFont(8), color: Self.ink3)
            drawStr(value, x: Self.mL + 18 + lw, y: pdfY(curY + 11),
                    font: Self.bodyFont(8), color: Self.ink1)
            curY += rowH
        }

        let printDate = a.printTimestamp.map { dateFmt.string(from: $0) } ?? "—"
        let doneDate  = a.completedTimestamp.map { dateFmt.string(from: $0) } ?? "Pending"
        let dur       = a.durationInSeconds > 0 ? fmtDuration(a.durationInSeconds) : "—"
        let mm        = Self.maxMarks(for: paper)
        let scoreStr  = a.totalScore > 0
            ? (mm > 0 ? "\(Int(a.totalScore)) / \(mm)  (\(String(format:"%.0f",a.totalScore/Double(mm)*100))%)" : "\(Int(a.totalScore))")
            : "—"

        infoLine("Printed",   printDate)
        infoLine("Completed", doneDate)
        infoLine("Type",      (a.paperType ?? "—").capitalized)
        infoLine("Score",     scoreStr)
        infoLine("Grade",     a.rawGrade ?? "—")
        infoLine("Duration",  dur)
        infoLine("Status",    a.manualStatus ?? (a.isComplete ? "Done" : "Pending"))

        if let rq = a.reviewQuestions, !rq.isEmpty {
            ensureSpace(rowH + 4)
            drawStr("Review Qs:", x: Self.mL + 18, y: pdfY(curY + 11), font: Self.bodyFont(8), color: Self.ink3)
            for line in wrapText(rq, font: Self.bodyFont(8), width: Self.cW - 114) {
                drawStr(line, x: Self.mL + 18 + 96, y: pdfY(curY + 11), font: Self.bodyFont(8), color: Self.ink1)
                curY += rowH
            }
        }
        if let notes = a.additionalNotes, !notes.isEmpty {
            ensureSpace(rowH + 4)
            drawStr("Notes:", x: Self.mL + 18, y: pdfY(curY + 11), font: Self.bodyFont(8), color: Self.ink3)
            for line in wrapText(notes, font: Self.bodyFont(8), width: Self.cW - 114).prefix(4) {
                drawStr(line, x: Self.mL + 18 + 96, y: pdfY(curY + 11), font: Self.bodyFont(8), color: Self.ink1)
                curY += rowH
            }
        }
        let logs = ((a.eventLogs as? Set<ETSEventLogMO>) ?? []).sorted { $0.sequenceIndex < $1.sequenceIndex }
        if !logs.isEmpty {
            ensureSpace(rowH * 2)
            drawStr("ETS:", x: Self.mL + 18, y: pdfY(curY + 11), font: Self.bodyFont(8), color: Self.ink3)
            curY += rowH
            for log in logs {
                ensureSpace(rowH)
                let marks = log.marksEarned > 0 ? "  \(String(format:"%.1f",log.marksEarned)) pts" : ""
                drawStr("· \(log.label ?? log.eventType ?? "—")  \(fmtDuration(log.durationSeconds))\(marks)",
                        x: Self.mL + 28, y: pdfY(curY + 11), font: Self.bodyFont(7.5), color: Self.ink3)
                curY += rowH - 1
            }
        }
        curY += 5
    }

    // ── DQA Analysis ─────────────────────────────────────────────────────────────
    private func drawDQAAnalysis() {
        beginPage()
        drawSectionTitle("Difficult Questions Archive (DQA) Analysis")

        let totalDQAs    = allDQAs.count
        let completeDQAs = allDQAs.filter { $0.isComplete }.count
        let activeDQAs   = allDQAs.filter { !$0.isComplete && !$0.isOutdated }.count
        let overdueDQAs  = allDQAs.filter {
            !$0.isComplete && !$0.isOutdated && ($0.committedDate.map { $0 < Date() } ?? false)
        }.count
        let totalQ = allDQAs.map { $0.decodedSourceQuestions.count }.reduce(0, +)
        let avgQ   = totalDQAs > 0 ? Double(totalQ) / Double(totalDQAs) : 0

        let intro: String = {
            var parts: [String] = []
            if totalDQAs == 0 {
                return "No DQA sessions have been created within the selected subjects."
            }
            parts.append("\(totalDQAs) DQA session\(totalDQAs == 1 ? "" : "s") have been created, of which \(completeDQAs) \(completeDQAs == 1 ? "is" : "are") complete.")
            if overdueDQAs > 0 {
                parts.append("\(overdueDQAs) \(overdueDQAs == 1 ? "session is" : "sessions are") currently overdue — completing these before the examination date is strongly recommended.")
            } else if activeDQAs > 0 {
                parts.append("All \(activeDQAs) active session\(activeDQAs == 1 ? "" : "s") \(activeDQAs == 1 ? "is" : "are") within schedule.")
            }
            if avgQ > 0 {
                parts.append("The average session contains \(String(format: "%.1f", avgQ)) source questions.")
            }
            return parts.joined(separator: " ")
        }()
        drawParagraph(intro, font: Self.bodyFont(10), color: Self.ink2)
        curY += 8

        // Summary stats
        let sCols: [(String, CGFloat)] = [
            ("Total Created", 110), ("Completed", 90), ("Active", 80), ("Overdue", 80), ("Avg Questions", 88)
        ]
        drawTableHeader(sCols)
        drawTableRow(["\(totalDQAs)", "\(completeDQAs)", "\(activeDQAs)", "\(overdueDQAs)",
                      String(format: "%.1f", avgQ)], cols: sCols)
        curY += 14

        // Per-subject breakdown
        drawSubLabel("Breakdown by Subject")
        curY += 4
        let bkCols: [(String, CGFloat)] = [
            ("Subject", 160), ("DQAs", 46), ("Done", 46),
            ("Questions", 66), ("Avg Q/DQA", 66), ("Last Activity", 74)
        ]
        drawTableHeader(bkCols)
        let grouped = Dictionary(grouping: allDQAs) { $0.subject ?? "Unknown" }
        for (name, dqas) in grouped.sorted(by: { $0.key < $1.key }) {
            let done  = dqas.filter { $0.isComplete }.count
            let tQ    = dqas.map { $0.decodedSourceQuestions.count }.reduce(0, +)
            let aQ    = dqas.isEmpty ? 0 : Double(tQ) / Double(dqas.count)
            let last  = dqas.compactMap { $0.dqaCompletedTimestamp ?? $0.createdTimestamp }
                            .max().map { dateFmt.string(from: $0) } ?? "—"
            drawTableRow([name, "\(dqas.count)", "\(done)", "\(tQ)",
                          String(format: "%.1f", aQ), last], cols: bkCols, bold: false, summaryRow: true)
        }
        curY += 14

        // Schedule adherence
        drawSubLabel("Schedule Adherence")
        curY += 4
        let adCols: [(String, CGFloat)] = [
            ("DQA Barcode", 148), ("Subject", 110), ("Committed", 78), ("Completed", 78), ("Schedule", 44)
        ]
        drawTableHeader(adCols)
        for dqa in allDQAs.sorted(by: { ($0.createdTimestamp ?? .distantPast) < ($1.createdTimestamp ?? .distantPast) }) {
            let comm = dqa.committedDate.map { dateFmt.string(from: $0) } ?? "Not Set"
            let comp = dqa.dqaCompletedTimestamp.map { dateFmt.string(from: $0) } ?? "Pending"
            let adh: String = {
                if let c1 = dqa.committedDate, let c2 = dqa.dqaCompletedTimestamp {
                    return c2 <= c1 ? "On Time" : "Late"
                }
                if let c = dqa.committedDate, c < Date(), !dqa.isComplete { return "Overdue" }
                return dqa.isComplete ? "Done" : "Active"
            }()
            drawTableRow([dqa.dqaBarcode ?? "—", dqa.subject ?? "—", comm, comp, adh], cols: adCols)
        }
        curY += 14

        // DQA trend chart
        let cal = Calendar.current
        var dayBuckets: [Date: Int] = [:]
        for dqa in allDQAs {
            guard let ts = dqa.createdTimestamp else { continue }
            dayBuckets[cal.startOfDay(for: ts), default: 0] += dqa.decodedSourceQuestions.count
        }
        if !dayBuckets.isEmpty {
            drawSubLabel("Questions per Day Trend")
            curY += 4
            let sorted = dayBuckets.sorted { $0.key < $1.key }
            drawBarChart(values: sorted.map { Double($0.value) },
                         labels: sorted.map { shortDate($0.key) },
                         yLabel: "Questions", width: Self.cW, height: 100)
        }
    }

    // ── Activity Statistics ───────────────────────────────────────────────────────
    private func drawActivityStats(metrics: [SubjectMetrics]) {
        beginPage()
        drawSectionTitle("Activity Statistics")

        let cal      = Calendar.current
        let total    = allAttempts.count
        let done     = allAttempts.filter { $0.isComplete }.count
        let practice = allAttempts.filter { $0.paperType == "practice" }.count
        let past     = allAttempts.filter { ($0.paperType ?? "") != "practice" }.count
        let timed    = allAttempts.filter { $0.durationInSeconds > 0 }.count
        let graded   = allAttempts.filter { $0.rawGrade != nil && !($0.rawGrade?.isEmpty ?? true) }.count

        var perDay: [Date: Int] = [:]
        var perHour: [Int: Int] = [:]
        for a in allAttempts {
            guard let ts = a.printTimestamp else { continue }
            perDay[cal.startOfDay(for: ts), default: 0] += 1
            perHour[cal.component(.hour, from: ts), default: 0] += 1
        }
        let maxDay  = perDay.values.max() ?? 0
        let minDay  = perDay.values.min() ?? 0
        let maxHour = perHour.max(by: { $0.value < $1.value })

        // Narrative
        let peakHourStr = maxHour.map { "\($0.key):00–\($0.key + 1):00" } ?? "no data"
        let intro: String = {
            var parts: [String] = []
            if total == 0 {
                return "No paper attempts have been logged for the selected subjects."
            }
            parts.append("During the tracking window, \(total) paper attempt\(total == 1 ? "" : "s") \(total == 1 ? "was" : "were") logged, of which \(done) \(done == 1 ? "is" : "are") marked complete.")
            if maxDay > 0 {
                parts.append("The most productive single day reached \(maxDay) paper\(maxDay == 1 ? "" : "s"), with the minimum recorded day at \(minDay).")
            }
            if maxHour != nil {
                parts.append("Activity is most concentrated during the \(peakHourStr) window.")
            }
            // Trend note
            let recent30Total  = metrics.reduce(0) { $0 + $1.recent30 }
            let prev30Total    = metrics.reduce(0) { $0 + $1.prev30 }
            if prev30Total > 0 && recent30Total > 0 {
                let delta = Double(recent30Total) - Double(prev30Total)
                let pct   = Int(abs(delta / Double(prev30Total) * 100))
                if pct > 10 {
                    parts.append(delta > 0
                        ? "Month-on-month revision output has increased by approximately \(pct)% against the preceding 30-day period, indicating a productive improvement in examination preparation."
                        : "Month-on-month revision output has declined by approximately \(pct)% against the preceding 30-day period; re-establishing a consistent daily programme of paper completion is recommended.")
                }
            }
            return parts.joined(separator: " ")
        }()
        drawParagraph(intro, font: Self.bodyFont(10), color: Self.ink2)
        curY += 8

        // Key figures table
        drawSubLabel("Key Figures")
        curY += 4
        let kfCols: [(String, CGFloat)] = [("Metric", 200), ("Value", 100)]
        let avgScore: Double = {
            let s = allAttempts.filter { $0.isComplete && $0.totalScore > 0 }
            guard !s.isEmpty else { return 0 }
            return s.map { $0.totalScore }.reduce(0, +) / Double(s.count)
        }()
        drawTableHeader(kfCols)
        for (k, v): (String, String) in [
            ("Total Papers Logged",         "\(total)"),
            ("Completed Papers",            "\(done)"),
            ("Past Papers",                 "\(past)"),
            ("Practice Papers",             "\(practice)"),
            ("Timed Papers",                "\(timed)"),
            ("Graded Papers",               "\(graded)"),
            ("Average Score (completed)",   avgScore > 0 ? String(format: "%.1f", avgScore) : "—"),
            ("Max Papers in a Single Day",  "\(maxDay)"),
            ("Min Papers in a Single Day",  "\(minDay)"),
            ("Max Papers in a Single Hour", "\(maxHour?.value ?? 0)"),
        ] { drawTableRow([k, v], cols: kfCols) }
        curY += 14

        // Most productive ranges
        var wdHour: [Int: Int] = [:]; var weHour: [Int: Int] = [:]
        for a in allAttempts {
            guard let ts = a.printTimestamp else { continue }
            let h = cal.component(.hour, from: ts)
            let wd = cal.component(.weekday, from: ts)
            if wd == 1 || wd == 7 { weHour[h, default: 0] += 1 }
            else { wdHour[h, default: 0] += 1 }
        }
        func peakStr(_ b: [Int: Int]) -> String {
            guard let pk = b.max(by: { $0.value < $1.value }) else { return "No data" }
            return "\(pk.key):00–\(pk.key + 1):00 (\(pk.value) papers)"
        }
        drawSubLabel("Most Productive Time Ranges")
        curY += 4
        let prCols: [(String, CGFloat)] = [("Day Type", 130), ("Peak Hour Range", 220)]
        drawTableHeader(prCols)
        drawTableRow(["Weekday", peakStr(wdHour)], cols: prCols)
        drawTableRow(["Weekend", peakStr(weHour)], cols: prCols)
        curY += 14

        // Papers per day chart
        if !perDay.isEmpty {
            drawSubLabel("Papers per Day")
            curY += 4
            let sd = perDay.sorted { $0.key < $1.key }
            drawBarChart(values: sd.map { Double($0.value) }, labels: sd.map { shortDate($0.key) },
                         yLabel: "Papers", width: Self.cW, height: 96)
        }

        // Papers per week
        var perWeek: [Date: Int] = [:]
        for a in allAttempts {
            guard let ts = a.printTimestamp,
                  let ws = cal.dateInterval(of: .weekOfYear, for: ts)?.start else { continue }
            perWeek[ws, default: 0] += 1
        }
        if !perWeek.isEmpty {
            drawSubLabel("Papers per Week")
            curY += 4
            let sw = perWeek.sorted { $0.key < $1.key }
            drawBarChart(values: sw.map { Double($0.value) }, labels: sw.map { shortDate($0.key) },
                         yLabel: "Papers", width: Self.cW, height: 96)
        }

        // Hourly distribution
        if !perHour.isEmpty {
            drawSubLabel("Activity by Time of Day")
            curY += 4
            drawBarChart(values: (0..<24).map { Double(perHour[$0] ?? 0) },
                         labels: (0..<24).map { "\($0)h" },
                         yLabel: "Papers", width: Self.cW, height: 90)
        }
    }

    // ── Exam Readiness ────────────────────────────────────────────────────────────
    private func drawExamReadiness(metrics: [SubjectMetrics]) {
        beginPage()
        drawSectionTitle("Exam Readiness Forecast")

        let behindCount = metrics.filter { $0.status == .behindTarget }.count
        let intro: String = {
            var parts = ["The forecast below projects completion of all available paper series against each subject's scheduled examination date, using the 30-day rolling completion rate as the velocity baseline."]
            if behindCount > 0 {
                parts.append("Status definitions — On Target: current pace is sufficient; Behind Target: acceleration required; Past Target: exam date has passed; Target Away: examination is ≥ 90 days away.")
            } else {
                parts.append("Status: On Target (pace sufficient), Behind Target (acceleration needed), Past Target (date passed), Target Away (≥ 90 days away).")
            }
            return parts.joined(separator: " ")
        }()
        drawParagraph(intro, font: Self.bodyFont(10), color: Self.ink2)
        curY += 10

        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        for m in metrics {
            drawSubjectHeader(m.name)

            // Per-subject narrative
            let narrativeParts: [String] = {
                var p: [String] = []
                p.append("\(m.name) has \(m.completedPapers) of \(m.totalPapers) paper series completed (\(m.totalPapers > 0 ? Int(Double(m.completedPapers)/Double(m.totalPapers)*100) : 0)%).")
                if m.dailyRate30 > 0 {
                    if m.remaining > 0 {
                        let daysNeeded = Int(ceil(Double(m.remaining) / m.dailyRate30))
                        let projDate   = dateFmt.string(from: Date().addingTimeInterval(Double(daysNeeded) * 86400))
                        p.append("At the current pace of \(String(format: "%.2f", m.dailyRate30)) papers per day, the remaining \(m.remaining) series are projected to be completed by \(projDate).")
                    } else {
                        p.append("All paper series have been completed.")
                    }
                } else {
                    if m.remaining > 0 {
                        p.append("No completion activity was recorded in the last 30 days. Immediate re-engagement is advised.")
                    }
                }
                if m.status == .behindTarget, let days = m.daysToExam, days > 0, m.remaining > 0 {
                    let needed = Double(m.remaining) / Double(days)
                    p.append("An optimisation of approximately \(String(format: "%.1f", needed)) papers per day is required to secure full coverage before the examination threshold.")
                }
                return p
            }()
            drawParagraph(narrativeParts.joined(separator: " "), font: Self.bodyFont(10), color: Self.ink2)
            curY += 6

            // Overview table
            let daysToFinish = m.dailyRate30 > 0 ? Int(ceil(Double(m.remaining) / m.dailyRate30)) : -1
            let projFinish: String = {
                if m.remaining == 0 { return "Completed ✓" }
                if m.dailyRate30 <= 0 { return "No recent activity" }
                return dateFmt.string(from: Date().addingTimeInterval(Double(daysToFinish) * 86400))
            }()
            let ovCols: [(String, CGFloat)] = [("Metric", 200), ("Value", 130)]
            drawTableHeader(ovCols)
            for (k, v): (String, String) in [
                ("Total Paper Series",    "\(m.totalPapers)"),
                ("Completed",             "\(m.completedPapers)"),
                ("Remaining",             "\(m.remaining)"),
                ("30-day Rate",           String(format: "%.2f papers/day", m.dailyRate30)),
                ("Projected Finish",      projFinish),
            ] { drawTableRow([k, v], cols: ovCols) }
            curY += 10

            // Forecast table per exam date
            let examDates: [(String, Date?)] = m.subject.hasMultiplePaperDates
                ? [("P1", m.subject.examDate1), ("P2", m.subject.examDate2),
                   ("P3", m.subject.examDate3), ("P4", m.subject.examDate4)]
                : [("Exam", m.subject.examDate1)]

            for (label, examDate) in examDates {
                guard let examDate = examDate else { continue }
                let daysLeft = cal.dateComponents([.day], from: today, to: examDate).day ?? 0
                let status   = computeStatusRaw(remaining: m.remaining, daysLeft: daysLeft,
                                                dailyRate: m.dailyRate30)
                ensureSpace(100)
                let headerStr = "\(label) Exam: \(dateFmt.string(from: examDate))  ·  \(daysLeft) days remaining"
                drawStr(headerStr, x: Self.mL + 10, y: pdfY(curY + 13),
                        font: Self.bodyFont(9, bold: true), color: Self.ink1)
                curY += 18

                let fCols: [(String, CGFloat)] = [
                    ("Window", 80), ("Papers Done (proj.)", 128),
                    ("% Complete (proj.)", 118), ("Status", 86)
                ]
                drawTableHeader(fCols)
                for weeks in [1, 2, 3, 4, 6, 8, 10, 12] {
                    let projDays   = weeks * 7
                    let projDone   = m.completedPapers + Int(Double(projDays) * m.dailyRate30)
                    let projPct    = m.totalPapers > 0 ? min(100, Int(Double(projDone)/Double(m.totalPapers)*100)) : 0
                    let projSt     = computeStatusRaw(remaining: max(0, m.totalPapers - projDone),
                                                      daysLeft: daysLeft - projDays,
                                                      dailyRate: m.dailyRate30)
                    drawTableRow(["\(weeks)w", "\(min(projDone, m.totalPapers))", "\(projPct)%", projSt.rawValue],
                                 cols: fCols, statusCol: 3, status: projSt)
                    if daysLeft - projDays <= 0 { break }
                }
                curY += 6
                drawStatusBadge(status, topLeft: CGPoint(x: Self.mL + 10, y: curY + 22),
                                width: 110, height: 22)
                curY += 30
            }
        }
    }

    // ── Productivity Charts ───────────────────────────────────────────────────────
    private func drawProductivityCharts() {
        beginPage()
        drawSectionTitle("Productivity & Grade Trends")

        let scored = allAttempts.filter { $0.totalScore > 0 && $0.completedTimestamp != nil }
            .sorted { ($0.completedTimestamp ?? .distantPast) < ($1.completedTimestamp ?? .distantPast) }
        let graded = allAttempts.filter { $0.rawGrade != nil && $0.isComplete }

        // Narrative
        let intro: String = {
            var parts: [String] = ["The charts below present score trends and activity patterns across the full tracking period."]
            if scored.count >= 3 {
                let first3   = scored.prefix(3).map { $0.totalScore }.reduce(0, +) / 3
                let last3    = scored.suffix(3).map { $0.totalScore }.reduce(0, +) / 3
                let delta    = last3 - first3
                let absDelta = abs(delta)
                if absDelta > 1 {
                    parts.append(delta > 0
                        ? "Score data shows an upward trajectory, with recent attempts averaging \(String(format: "%.1f", absDelta)) marks higher than the earliest recorded sessions."
                        : "Score data indicates a slight downward trend of approximately \(String(format: "%.1f", absDelta)) marks versus the earliest recorded sessions; targeted review of recurring difficulty areas is recommended.")
                }
            }
            return parts.joined(separator: " ")
        }()
        drawParagraph(intro, font: Self.bodyFont(10), color: Self.ink2)
        curY += 8

        // Grade distribution
        if !graded.isEmpty {
            var gradeCounts: [String: Int] = [:]
            for a in graded { gradeCounts[a.rawGrade ?? "?", default: 0] += 1 }
            let order = ["A*", "A", "B", "C", "D", "E", "F"]
            drawSubLabel("Grade Distribution")
            curY += 4
            drawBarChart(values: order.map { Double(gradeCounts[$0] ?? 0) },
                         labels: order, yLabel: "Attempts", width: Self.cW, height: 96)
        }

        // Score trend
        if scored.count >= 2 {
            drawSubLabel("Score Trend (Chronological)")
            curY += 4
            drawLineChart(values: scored.map { $0.totalScore },
                          labels: scored.map { dateFmt.string(from: $0.completedTimestamp!) },
                          width: Self.cW, height: 96, yLabel: "Score")
        }

        // ETS
        let allLogs = allAttempts.flatMap { ($0.eventLogs as? Set<ETSEventLogMO>) ?? [] }
        let qLogs   = allLogs.filter {
            ($0.eventType?.lowercased().contains("question") ?? false) ||
            ($0.label?.lowercased().hasPrefix("q") ?? false)
        }
        if !qLogs.isEmpty {
            let avgSec = qLogs.map { Double($0.durationSeconds) }.reduce(0, +) / Double(qLogs.count)
            let totSec = qLogs.map { $0.durationSeconds }.reduce(0, +)
            drawSubLabel("ETS: Time per Question")
            curY += 4
            let eCols: [(String, CGFloat)] = [("Metric", 200), ("Value", 130)]
            drawTableHeader(eCols)
            drawTableRow(["Average time per question", fmtDuration(Int64(avgSec))], cols: eCols)
            drawTableRow(["Total questions timed",     "\(qLogs.count)"],           cols: eCols)
            drawTableRow(["Total ETS time",            fmtDuration(totSec)],        cols: eCols)
            curY += 14
        }

        // Cumulative papers
        let allByDate = allAttempts.filter { $0.printTimestamp != nil }
            .sorted { $0.printTimestamp! < $1.printTimestamp! }
        if allByDate.count >= 2 {
            var cum: [(Double, String)] = []
            for (i, a) in allByDate.enumerated() {
                if i % max(1, allByDate.count / 20) == 0 || i == allByDate.count - 1 {
                    cum.append((Double(i + 1), shortDate(a.printTimestamp!)))
                }
            }
            drawSubLabel("Cumulative Papers Over Time")
            curY += 4
            drawLineChart(values: cum.map { $0.0 }, labels: cum.map { $0.1 },
                          width: Self.cW, height: 96, yLabel: "Total")
        }

        // Average score by subject
        let sCols: [(String, CGFloat)] = [
            ("Subject", 158), ("Avg Score", 78), ("Avg %", 78), ("Best Grade", 78)
        ]
        drawSubLabel("Average Score by Subject")
        curY += 4
        drawTableHeader(sCols)
        for subject in config.subjects {
            let sa = allAttempts.filter { $0.isComplete && $0.totalScore > 0 && $0.paper?.subject?.id == subject.id }
            guard !sa.isEmpty else { continue }
            let avgS  = sa.map { $0.totalScore }.reduce(0, +) / Double(sa.count)
            let mm    = sa.compactMap { Self.maxMarks(for: $0.paper) }.max() ?? 0
            let avgPct = mm > 0 ? avgS / Double(mm) * 100 : 0
            let bGrade = sa.compactMap { $0.rawGrade }.sorted().first ?? "—"
            drawTableRow([subject.name ?? "—", String(format: "%.1f", avgS),
                          mm > 0 ? String(format: "%.0f%%", avgPct) : "—", bGrade], cols: sCols)
        }
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Narrative synthesis
    // ────────────────────────────────────────────────────────────────────────────

    private struct SubjectMetrics {
        let subject:          SubjectMO
        let name:             String
        let totalPapers:      Int
        let completedPapers:  Int
        let remaining:        Int
        let recent30:         Int      // attempts completed in last 30 days
        let prev30:           Int      // attempts completed in 30–60 days ago
        let dailyRate30:      Double
        let daysToExam:       Int?
        let status:           ReportStatus
    }

    private func computeAllMetrics() -> [SubjectMetrics] {
        let cal     = Calendar.current
        let today   = cal.startOfDay(for: Date())
        let cut30   = cal.date(byAdding: .day, value: -30, to: today)!
        let cut60   = cal.date(byAdding: .day, value: -60, to: today)!

        return config.subjects.map { subject in
            let papers     = sortedPapers(for: subject)
            let done       = papers.filter { !completedAttempts(for: $0).isEmpty }.count
            let remaining  = papers.count - done
            let sAttempts  = allAttempts.filter { $0.paper?.subject?.id == subject.id && $0.isComplete }
            let recent30   = sAttempts.filter { ($0.completedTimestamp ?? .distantPast) >= cut30 }.count
            let prev30     = sAttempts.filter {
                let ts = $0.completedTimestamp ?? .distantPast
                return ts >= cut60 && ts < cut30
            }.count
            let dailyRate  = Double(recent30) / 30.0
            let examDate   = subject.examDate1
            let daysToExam = examDate.map { cal.dateComponents([.day], from: today, to: $0).day }
            let status     = computeStatusRaw(remaining: remaining,
                                              daysLeft: (daysToExam ?? nil) ?? 999,
                                              dailyRate: dailyRate)
            return SubjectMetrics(subject: subject, name: subject.name ?? "Unknown",
                                  totalPapers: papers.count, completedPapers: done,
                                  remaining: remaining, recent30: recent30, prev30: prev30,
                                  dailyRate30: dailyRate, daysToExam: daysToExam ?? nil,
                                  status: status)
        }
    }

    private func synthesizeExecutiveSummary(metrics: [SubjectMetrics]) -> String {
        guard !metrics.isEmpty else {
            return "No subject data is available for this reporting period."
        }
        var parts: [String] = []
        let total     = allAttempts.count
        let completed = allAttempts.filter { $0.isComplete }.count

        if total == 0 {
            return "No paper attempts have been logged for the selected subjects. Begin logging attempts to generate a meaningful performance analysis."
        }

        // Trend classification
        let improving = metrics.filter { m in
            m.prev30 > 0 ? Double(m.recent30) / Double(m.prev30) >= 1.20 : m.recent30 > 2
        }
        let declining = metrics.filter { m in
            m.recent30 == 0 || (m.prev30 > 0 && Double(m.recent30) / Double(m.prev30) <= 0.80)
        }

        if improving.count > 0 && declining.count > 0 {
            let impNames = improving.prefix(2).map { $0.name }.joined(separator: " and ")
            let decNames = declining.prefix(2).map { $0.name }.joined(separator: " and ")
            let uplift   = improving.first.map { m in
                m.prev30 > 0 ? Int(((Double(m.recent30) / Double(m.prev30)) - 1) * 100) : 0
            } ?? 0
            parts.append("Whilst \(decNames) registered diminished revision output during the period under review, \(impNames) demonstrated\(uplift > 5 ? " an improvement of +\(uplift)%" : " increased engagement"), reflecting commendable effort. A more equitable distribution of attention across all subjects is recommended to maintain comprehensive examination coverage.")
        } else if declining.count == metrics.count {
            parts.append("The records indicate a period of reduced revision output across all tracked subjects. Directed attention toward outstanding past paper components is recommended, with a view to re-establishing a regular programme of examination preparation.")
        } else if improving.count == metrics.count {
            let tR = metrics.reduce(0) { $0 + $1.recent30 }
            let tP = metrics.reduce(0) { $0 + $1.prev30 }
            let up = tP > 0 ? Int(((Double(tR) / Double(tP)) - 1) * 100) : 0
            parts.append("A sustained improvement in revision output has been recorded across all tracked subjects\(up > 5 ? ", representing an increase of approximately \(up)% against the preceding period" : ""). The present trajectory affords satisfactory coverage prospects ahead of the scheduled examinations.")
        } else {
            parts.append("This report summarises performance across \(metrics.count) subject\(metrics.count == 1 ? "" : "s"), covering \(total) logged attempt\(total == 1 ? "" : "s") of which \(completed) \(completed == 1 ? "is" : "are") complete.")
        }

        // Velocity forecast for behind-target subjects
        let behind = metrics.filter { $0.status == .behindTarget }
        if !behind.isEmpty {
            let s           = behind.first!
            let daysLeft    = s.daysToExam ?? 0
            let neededRate  = daysLeft > 0 ? Double(s.remaining) / Double(daysLeft) : 0
            let subjectDesc = behind.count == 1 ? s.name : "\(behind.count) subjects"
            if neededRate > 0 {
                parts.append("The current rate of completion for \(subjectDesc) requires an increase to approximately \(String(format: "%.1f", neededRate)) paper\(neededRate == 1 ? "" : "s") per day in order to attain full coverage prior to the scheduled examination date.")
            }
        }

        // DQA advisory
        let overdueDQAs = allDQAs.filter { !$0.isComplete && !$0.isOutdated && ($0.committedDate.map { $0 < Date() } ?? false) }.count
        if overdueDQAs > 0 {
            parts.append("\(overdueDQAs) DQA session\(overdueDQAs == 1 ? "" : "s") \(overdueDQAs == 1 ? "is" : "are") currently overdue; completing these before the examination date is strongly recommended.")
        }

        return parts.joined(separator: "\n\n")
    }

    private func computeOverallStatus(from metrics: [SubjectMetrics]) -> ReportStatus {
        let statuses = metrics.map { $0.status }
        if statuses.contains(.behindTarget) { return .behindTarget }
        if statuses.contains(.targetAway)   { return .targetAway }
        if statuses.allSatisfy({ $0 == .pastTarget }) { return .pastTarget }
        return .onTarget
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Paragraph typesetting (CoreText native)
    // ────────────────────────────────────────────────────────────────────────────

    @discardableResult
    private func drawParagraph(_ text: String, font: NSFont, color: NSColor,
                               indent: CGFloat = 0, lineSpacing: CGFloat = 3) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let astr = NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            .paragraphStyle: style
        ])
        let setter = CTFramesetterCreateWithAttributedString(astr)
        let availW = Self.cW - indent
        var fitRange = CFRange(location: 0, length: 0)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: availW, height: .greatestFiniteMagnitude), &fitRange)
        let h = ceil(size.height) + lineSpacing + 2
        ensureSpace(h)
        let rect  = CGRect(x: Self.mL + indent, y: pdfY(curY + h), width: availW, height: h)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                             CGPath(rect: rect, transform: nil), nil)
        pdfCtx.saveGState()
        CTFrameDraw(frame, pdfCtx)
        pdfCtx.restoreGState()
        curY += h
        return h
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Table primitives (Apple open-rule style)
    // ────────────────────────────────────────────────────────────────────────────

    private func drawTableHeader(_ cols: [(String, CGFloat)]) {
        let rowH: CGFloat = 17
        ensureSpace(rowH)
        var x = Self.mL
        let totalW = cols.reduce(0) { $0 + $1.1 }
        // Header background — light gray
        fillRect(CGRect(x: Self.mL, y: pdfY(curY + rowH), width: totalW, height: rowH),
                 color: Self.hdrBg)
        for (label, w) in cols {
            drawStr(label, x: x + 5, y: pdfY(curY + rowH) + 5,
                    font: Self.bodyFont(8, bold: true), color: Self.ink1)
            x += w
        }
        // Bottom rule — slightly stronger than data rows
        strokeHLine(y: pdfY(curY + rowH), x0: Self.mL, x1: Self.mL + totalW,
                    color: NSColor(white: 0.78, alpha: 1), width: 0.5)
        curY += rowH
        tableRowIsEven = true
    }

    private func drawTableRow(_ values: [String], cols: [(String, CGFloat)],
                              bold: Bool = false, summaryRow: Bool = false,
                              statusCol: Int = -1, status: ReportStatus = .onTarget) {
        let rowH: CGFloat = 16
        ensureSpace(rowH)
        var x = Self.mL
        let totalW = cols.reduce(0) { $0 + $1.1 }
        // Summary rows get a very light fill; regular rows are white
        if summaryRow {
            fillRect(CGRect(x: Self.mL, y: pdfY(curY + rowH), width: totalW, height: rowH),
                     color: Self.hdrBg)
        }
        for (i, (_, w)) in cols.enumerated() {
            let val   = i < values.count ? values[i] : ""
            let fnt   = Self.bodyFont(9, bold: bold || summaryRow)
            let clr   = i == statusCol ? status.nsColor : Self.ink1
            drawStr(val, x: x + 5, y: pdfY(curY + rowH) + 4, font: fnt, color: clr)
            x += w
        }
        // Thin bottom separator
        strokeHLine(y: pdfY(curY + rowH), x0: Self.mL, x1: Self.mL + totalW,
                    color: Self.sep, width: 0.5)
        curY += rowH
        tableRowIsEven.toggle()
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Section / subject header primitives
    // ────────────────────────────────────────────────────────────────────────────

    private func drawSectionTitle(_ text: String) {
        ensureSpace(28)
        // 2pt accent bar on left
        fillRect(CGRect(x: Self.mL, y: pdfY(curY + 26), width: 2, height: 24),
                 color: Self.coverAccent)
        drawStr(text, x: Self.mL + 10, y: pdfY(curY + 22),
                font: Self.headFont(16), color: Self.ink1)
        curY += 28
        strokeHLine(y: pdfY(curY), x0: Self.mL, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        curY += 8
    }

    private func drawSubjectHeader(_ name: String) {
        ensureSpace(22)
        drawStr(name, x: Self.mL, y: pdfY(curY + 16),
                font: Self.headFont(13), color: Self.ink1)
        curY += 18
        strokeHLine(y: pdfY(curY), x0: Self.mL, x1: Self.W - Self.mR, color: Self.sep, width: 0.5)
        curY += 5
    }

    private func drawSubLabel(_ text: String) {
        ensureSpace(18)
        drawStr(text.uppercased(), x: Self.mL, y: pdfY(curY + 13),
                font: Self.bodyFont(8, bold: true), color: Self.ink3, kern: 0.8)
        curY += 16
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Status badge
    // ────────────────────────────────────────────────────────────────────────────

    private func drawStatusBadge(_ status: ReportStatus, topLeft: CGPoint, width: CGFloat, height: CGFloat) {
        let rect = CGRect(x: topLeft.x, y: pdfY(topLeft.y + height), width: width, height: height)
        pdfCtx.saveGState()
        // Neutral light-gray background fill — no colorful tints
        pdfCtx.setFillColor(Self.hdrBg.cgColor)
        pdfCtx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        pdfCtx.fillPath()
        // Thin neutral border
        pdfCtx.setStrokeColor(Self.sep.cgColor)
        pdfCtx.setLineWidth(0.8)
        pdfCtx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        pdfCtx.strokePath()
        pdfCtx.restoreGState()
        let fs: CGFloat = height > 24 ? 9.5 : 8.5
        let tw = strWidth(status.rawValue, font: Self.bodyFont(fs, bold: true))
        drawStr(status.rawValue,
                x: topLeft.x + (width - tw) / 2,
                y: pdfY(topLeft.y + height) + (height - fs) / 2,
                font: Self.bodyFont(fs, bold: true), color: Self.ink1)
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Chart primitives
    // ────────────────────────────────────────────────────────────────────────────

    private func drawBarChart(values: [Double], labels: [String],
                              yLabel: String, width: CGFloat, height: CGFloat) {
        guard !values.isEmpty else { return }
        ensureSpace(height + 28)
        let chartX    = Self.mL + 34        // left margin for gridline labels
        let chartY    = curY
        let chartW    = width - 36
        // Cap bar width so single-data-point charts don't fill the whole area
        let barW      = max(3, min(36, (chartW / CGFloat(values.count)) - 1.5))
        let maxVal    = values.max() ?? 1
        let scale     = maxVal > 0 ? (height - 18) / maxVal : 1
        let axisBaseY = pdfY(chartY + height)   // PDF-Y of axis baseline

        // Axis baseline
        strokeHLine(y: axisBaseY, x0: chartX, x1: chartX + chartW,
                    color: Self.sep, width: 0.5)

        // Bars (drawn first, so gridlines overlay them)
        let showEvery = max(1, values.count / 18)
        let barColor  = NSColor(white: 0.52, alpha: 1)   // mid-gray — gridlines readable on top
        for (i, val) in values.enumerated() {
            let barH = max(0, CGFloat(val) * CGFloat(scale))
            let bX   = chartX + CGFloat(i) * (barW + 1.5)
            fillRect(CGRect(x: bX, y: axisBaseY, width: barW, height: barH), color: barColor)
            if i % showEvery == 0 && i < labels.count {
                let lab = labels[i]
                let lX  = bX + barW / 2 - strWidth(lab, font: Self.bodyFont(5)) / 2
                drawStr(lab, x: lX, y: axisBaseY - 8, font: Self.bodyFont(5), color: Self.ink3)
            }
        }

        // Gridlines drawn on top of bars, with value labels in the left gutter
        for i in 1...3 {
            let gY    = (height - 18) * CGFloat(3 - i) / 3
            let gYPDF = pdfY(chartY + 18 + gY)
            strokeHLine(y: gYPDF, x0: chartX, x1: chartX + chartW,
                        color: NSColor(white: 0.80, alpha: 1), width: 0.4)
            let gVal = maxVal * Double(i) / 3
            drawStr(String(format: gVal < 10 ? "%.1f" : "%.0f", gVal),
                    x: Self.mL, y: gYPDF - 3,
                    font: Self.bodyFont(5.5), color: Self.ink3)
        }
        curY += height + 22
    }

    private func drawLineChart(values: [Double], labels: [String],
                               width: CGFloat, height: CGFloat, yLabel: String) {
        guard values.count >= 2 else { return }
        ensureSpace(height + 24)
        let chartX = Self.mL + 24
        let chartY = curY
        let chartW = width - 26
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let range  = maxVal == minVal ? 1 : maxVal - minVal
        let scaleY = (height - 18) / range

        strokeHLine(y: pdfY(chartY + height), x0: chartX, x1: chartX + chartW, color: Self.sep, width: 0.5)
        drawStr(yLabel, x: Self.mL, y: pdfY(chartY + height * 0.5), font: Self.bodyFont(6.5), color: Self.ink3)

        pdfCtx.saveGState()
        pdfCtx.setStrokeColor(Self.ink2.cgColor)
        pdfCtx.setLineWidth(1.2)
        let stepX  = chartW / CGFloat(values.count - 1)
        let points = values.enumerated().map { (i, val) in
            CGPoint(x: chartX + CGFloat(i) * stepX,
                    y: pdfY(chartY + height) + CGFloat((val - minVal) * scaleY))
        }
        pdfCtx.beginPath()
        pdfCtx.move(to: points[0])
        for pt in points.dropFirst() { pdfCtx.addLine(to: pt) }
        pdfCtx.strokePath()
        pdfCtx.setFillColor(Self.ink2.cgColor)
        for pt in points { pdfCtx.fillEllipse(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)) }
        pdfCtx.restoreGState()

        let lineAxisBaseY = pdfY(chartY + height)
        let showEvery = max(1, values.count / 10)
        for (i, lab) in labels.enumerated() where i % showEvery == 0 {
            let px = points[i].x - strWidth(lab, font: Self.bodyFont(5)) / 2
            drawStr(lab, x: px, y: lineAxisBaseY - 8, font: Self.bodyFont(5), color: Self.ink3)
        }
        curY += height + 20
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Drawing primitives
    // ────────────────────────────────────────────────────────────────────────────

    private func drawStr(_ text: String, x: CGFloat, y: CGFloat,
                         font: NSFont, color: NSColor, kern: CGFloat = 0) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if kern != 0 { attrs[.kern] = kern }
        let str = NSAttributedString(string: text, attributes: attrs)
        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(cgContext: pdfCtx, flipped: false)
        NSGraphicsContext.current = gc
        str.draw(at: CGPoint(x: x, y: y))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func strWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func wrapText(_ text: String, font: NSFont, width: CGFloat) -> [String] {
        var lines: [String] = []
        var cur = ""
        for word in text.components(separatedBy: " ") {
            let test = cur.isEmpty ? word : cur + " " + word
            if strWidth(test, font: font) <= width { cur = test }
            else { if !cur.isEmpty { lines.append(cur) }; cur = word }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    private func fillRect(_ rect: CGRect, color: NSColor) {
        pdfCtx.setFillColor(color.cgColor); pdfCtx.fill(rect)
    }

    private func strokeHLine(y: CGFloat, x0: CGFloat, x1: CGFloat, color: NSColor, width: CGFloat) {
        pdfCtx.saveGState()
        pdfCtx.setStrokeColor(color.cgColor)
        pdfCtx.setLineWidth(width)
        pdfCtx.move(to: CGPoint(x: x0, y: y))
        pdfCtx.addLine(to: CGPoint(x: x1, y: y))
        pdfCtx.strokePath()
        pdfCtx.restoreGState()
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Data helpers
    // ────────────────────────────────────────────────────────────────────────────

    private func sortedPapers(for subject: SubjectMO) -> [PaperMO] {
        ((subject.papers as? Set<PaperMO>) ?? [])
            .sorted { ($0.normalizedSeries ?? "") < ($1.normalizedSeries ?? "") }
    }

    private func completedAttempts(for paper: PaperMO) -> [AttemptMO] {
        ((paper.attempts as? Set<AttemptMO>) ?? []).filter { $0.isComplete }
    }

    private static func maxMarks(for paper: PaperMO?) -> Int {
        guard let p = paper else { return 0 }
        if let qs = p.questionStructures as? Set<QuestionStructureMO>, !qs.isEmpty {
            return Int(qs.map { $0.maxMarks }.reduce(0, +))
        }
        if let gt = (p.gradeThresholds as? Set<GradeThresholdTableMO>)?.first {
            return Int(gt.maxPossibleMarks)
        }
        return 0
    }

    private func averageScore(for subject: SubjectMO) -> Double {
        let sa = allAttempts.filter { $0.isComplete && $0.totalScore > 0 && $0.paper?.subject?.id == subject.id }
        guard !sa.isEmpty else { return 0 }
        return sa.map { $0.totalScore }.reduce(0, +) / Double(sa.count)
    }

    private func averagePercent(for subject: SubjectMO) -> Double {
        let sa = allAttempts.filter { $0.isComplete && $0.totalScore > 0 && $0.paper?.subject?.id == subject.id }
        guard !sa.isEmpty else { return 0 }
        let mm = sa.compactMap { Self.maxMarks(for: $0.paper) }.max() ?? 0
        guard mm > 0 else { return 0 }
        return averageScore(for: subject) / Double(mm) * 100
    }

    private func attStatus(_ attempt: AttemptMO) -> String {
        attempt.manualStatus ?? (attempt.isComplete ? "Done" : "Pending")
    }

    private func computeStatus(for subject: SubjectMO) -> ReportStatus {
        let cal      = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let papers   = sortedPapers(for: subject)
        let done     = papers.filter { !completedAttempts(for: $0).isEmpty }.count
        let remaining = papers.count - done
        let daysLeft: Int = subject.examDate1.map {
            cal.dateComponents([.day], from: today, to: $0).day ?? 0
        } ?? 999
        let cutoff   = cal.date(byAdding: .day, value: -30, to: today)!
        let recent   = allAttempts.filter {
            $0.isComplete && $0.paper?.subject?.id == subject.id &&
            ($0.completedTimestamp ?? .distantPast) >= cutoff
        }.count
        return computeStatusRaw(remaining: remaining, daysLeft: daysLeft,
                                dailyRate: Double(recent) / 30.0)
    }

    private func computeStatusRaw(remaining: Int, daysLeft: Int, dailyRate: Double) -> ReportStatus {
        if daysLeft < 0   { return .pastTarget }
        if remaining == 0 { return .onTarget }
        if daysLeft >= 90 { return .targetAway }
        let needed = daysLeft > 0 ? Double(remaining) / Double(daysLeft) : Double.infinity
        return dailyRate >= needed ? .onTarget : .behindTarget
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: - Formatters
    // ────────────────────────────────────────────────────────────────────────────

    private lazy var dateFmt: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "d MMMM yyyy"
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d/M"
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: date)
    }

    private func fmtDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "—" }
        let h = seconds / 3600; let m = (seconds % 3600) / 60; let s = seconds % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

// MARK: - Helpers
private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
