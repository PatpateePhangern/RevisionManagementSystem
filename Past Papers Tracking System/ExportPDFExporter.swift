//
//  PDFExporter.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//
//  PDF Export with Professional Table Borders:
//  - Full table borders (1.0pt outer, 0.5pt column separators)
//  - Proper header styling with background
//  - Consistent row height (20pt)
//  - Vertical centering of cell content
//  - Professional grid layout optimized for A4
//  - Automatic page breaks with header continuation

import AppKit
import PDFKit
import UniformTypeIdentifiers
import CoreText

final class PDFExporter {
    
    // Prevent instantiation
    private init() {}
    
    static func generateSessionReceipt(for session: ExamSession) -> PDFDocument? {
        // A4 dimensions in points (72 points = 1 inch)
        // A4: 210mm x 297mm = 595.28 x 841.89 points
        let pageWidth: CGFloat = 595.28
        let pageHeight: CGFloat = 841.89
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        // Margins
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)
        
        // Create PDF context
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        
        // Start page
        context.beginPage(mediaBox: &mediaBox)
        
        var yPosition: CGFloat = pageHeight - margin
        
        // Helper function to draw text
        @discardableResult
        func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, y: CGFloat, alignment: NSTextAlignment = .left, maxWidth: CGFloat? = nil) -> CGFloat {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let size = attributedString.size()
            
            var drawX = x
            let effectiveWidth = maxWidth ?? size.width
            
            if alignment == .right {
                drawX = x + effectiveWidth - size.width
            } else if alignment == .center {
                drawX = x + (effectiveWidth - size.width) / 2
            }
            
            // Use Core Graphics directly for better compatibility
            context.saveGState()
            context.setFillColor(color.cgColor)
            context.textMatrix = .identity
            // Flip coordinate system for text rendering - PDF uses bottom-left origin
            context.translateBy(x: 0, y: pageHeight)
            context.scaleBy(x: 1.0, y: -1.0)
            
            // Convert from top-origin (our working coordinates) to bottom-origin (PDF coordinates)
            // y parameter comes from top, so we need to flip it relative to page height
            let flippedY = pageHeight - y
            
            let line = CTLineCreateWithAttributedString(attributedString)
            context.textPosition = CGPoint(x: drawX, y: flippedY)
            CTLineDraw(line, context)
            
            context.restoreGState()
            
            return size.height
        }
        
        // Helper function to draw line
        func drawLine(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor, width: CGFloat = 0.5) {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
            context.strokePath()
        }
        
        // MARK: - Header
        
        let titleFont = NSFont.systemFont(ofSize: 24, weight: .semibold)
        let titleHeight = drawText("EXAM SESSION RECEIPT", font: titleFont, color: .black, x: margin, y: yPosition, alignment: .center, maxWidth: contentWidth)
        yPosition -= titleHeight + 8
        
        let subtitleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let subtitleHeight = drawText("Performance Analysis Report", font: subtitleFont, color: .gray, x: margin, y: yPosition, alignment: .center, maxWidth: contentWidth)
        yPosition -= subtitleHeight + 20
        
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1)
        yPosition -= 25
        
        // MARK: - Session Information
        
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        
        let labelHeight = drawText("EXAM TITLE:", font: labelFont, color: .gray, x: margin, y: yPosition)
        yPosition -= labelHeight + 4
        let titleValueHeight = drawText(session.title, font: valueFont, color: .black, x: margin, y: yPosition)
        yPosition -= titleValueHeight + 12
        
        if let startTime = session.startTime {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .medium
            
            let dateLabel = drawText("DATE & TIME:", font: labelFont, color: .gray, x: margin, y: yPosition)
            yPosition -= dateLabel + 4
            let dateValue = drawText(dateFormatter.string(from: startTime), font: valueFont, color: .black, x: margin, y: yPosition)
            yPosition -= dateValue + 12
        }
        
        let durationLabel = drawText("TOTAL DURATION:", font: labelFont, color: .gray, x: margin, y: yPosition)
        yPosition -= durationLabel + 4
        
        // Format total time spent with milliseconds
        let totalTime = session.totalTimeSpent
        let hours = Int(totalTime) / 3600
        let minutes = (Int(totalTime) % 3600) / 60
        let seconds = Int(totalTime) % 60
        let milliseconds = Int((totalTime.truncatingRemainder(dividingBy: 1)) * 1000)
        let durationString: String
        if hours > 0 {
            durationString = String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        } else {
            durationString = String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
        }
        
        let durationValue = drawText(durationString, font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), color: .black, x: margin, y: yPosition)
        yPosition -= durationValue + 20
        
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .lightGray)
        yPosition -= 25
        
        // MARK: - Statistics Summary
        
        let statsFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        
        let col1X = margin
        let col2X = margin + (contentWidth / 4)
        let col3X = margin + (contentWidth / 2)
        let col4X = margin + (3 * contentWidth / 4)
        
        let stat1 = drawText("Total Questions", font: labelFont, color: .gray, x: col1X, y: yPosition)
        drawText("Total Marks", font: labelFont, color: .gray, x: col2X, y: yPosition)
        drawText("Avg Time/Question", font: labelFont, color: .gray, x: col3X, y: yPosition)
        drawText("Avg Time/Mark", font: labelFont, color: .gray, x: col4X, y: yPosition)
        yPosition -= stat1 + 4
        
        let stat1Val = drawText("\(session.questions.count)", font: statsFont, color: .black, x: col1X, y: yPosition)
        drawText("\(session.totalMarks)", font: statsFont, color: .black, x: col2X, y: yPosition)
        
        let avgTimePerQuestion = session.questions.count > 0 ? session.totalTimeSpent / Double(session.questions.count) : 0
        let avgQuestionMins = Int(avgTimePerQuestion) / 60
        let avgQuestionSecs = Int(avgTimePerQuestion) % 60
        let avgQuestionMs = Int((avgTimePerQuestion.truncatingRemainder(dividingBy: 1)) * 1000)
        drawText(String(format: "%02d:%02d.%03d", avgQuestionMins, avgQuestionSecs, avgQuestionMs), font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), color: .black, x: col3X, y: yPosition)
        
        // Format average time per mark with milliseconds
        let avgTimePerMark = session.averageTimePerMark
        let avgMarkMs = Int(avgTimePerMark * 1000)
        let avgTimePerMarkString: String
        if avgMarkMs < 1000 {
            avgTimePerMarkString = String(format: "%dms", avgMarkMs)
        } else {
            let wholeSeconds = Int(avgTimePerMark)
            let ms = Int((avgTimePerMark.truncatingRemainder(dividingBy: 1)) * 1000)
            avgTimePerMarkString = String(format: "%d.%03ds", wholeSeconds, ms)
        }
        drawText(avgTimePerMarkString, font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), color: .black, x: col4X, y: yPosition)
        yPosition -= stat1Val + 25
        
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1)
        yPosition -= 25
        
        // MARK: - Performance Table Header
        
        let tableHeaderFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let tableCellFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        
        // Column positions with better spacing for A4
        let qCol = margin
        let qColWidth: CGFloat = 70
        let timeCol = qCol + qColWidth
        let timeColWidth: CGFloat = 90
        let marksCol = timeCol + timeColWidth
        let marksColWidth: CGFloat = 70
        let timePerMarkCol = marksCol + marksColWidth
        let timePerMarkColWidth: CGFloat = 90
        let efficiencyCol = timePerMarkCol + timePerMarkColWidth
        
        // Draw table border (outer box)
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
        
        // Draw header background
        let headerBg = CGRect(x: margin, y: yPosition - 22, width: contentWidth, height: 22)
        context.setFillColor(NSColor.lightGray.withAlphaComponent(0.2).cgColor)
        context.fill(headerBg)
        
        // Draw vertical column separators for header
        drawLine(x1: timeCol, y1: yPosition, x2: timeCol, y2: yPosition - 22, color: .black, width: 0.5)
        drawLine(x1: marksCol, y1: yPosition, x2: marksCol, y2: yPosition - 22, color: .black, width: 0.5)
        drawLine(x1: timePerMarkCol, y1: yPosition, x2: timePerMarkCol, y2: yPosition - 22, color: .black, width: 0.5)
        drawLine(x1: efficiencyCol, y1: yPosition, x2: efficiencyCol, y2: yPosition - 22, color: .black, width: 0.5)
        
        // Draw left and right table borders for header
        drawLine(x1: margin, y1: yPosition, x2: margin, y2: yPosition - 22, color: .black, width: 1.0)
        drawLine(x1: pageWidth - margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition - 22, color: .black, width: 1.0)
        
        drawText("QUESTION", font: tableHeaderFont, color: .black, x: qCol + 8, y: yPosition - 7)
        drawText("TIME SPENT", font: tableHeaderFont, color: .black, x: timeCol + 8, y: yPosition - 7)
        drawText("MARKS", font: tableHeaderFont, color: .black, x: marksCol + 8, y: yPosition - 7)
        drawText("TIME/MARK", font: tableHeaderFont, color: .black, x: timePerMarkCol + 8, y: yPosition - 7)
        drawText("EFFICIENCY", font: tableHeaderFont, color: .black, x: efficiencyCol + 8, y: yPosition - 7)
        
        yPosition -= 22
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
        yPosition -= 2
        
        // MARK: - Performance Table Rows
        
        let rowHeight: CGFloat = 20
        
        for question in session.questions {
            if yPosition < margin + 60 {
                // Close current table with bottom border before new page
                drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
                
                // Start new page if needed
                context.endPage()
                context.beginPage(mediaBox: &mediaBox)
                yPosition = pageHeight - margin - 30
                
                // Redraw table header on new page
                let headerBg = CGRect(x: margin, y: yPosition - 22, width: contentWidth, height: 22)
                context.setFillColor(NSColor.lightGray.withAlphaComponent(0.2).cgColor)
                context.fill(headerBg)
                
                drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
                drawLine(x1: margin, y1: yPosition, x2: margin, y2: yPosition - 22, color: .black, width: 1.0)
                drawLine(x1: pageWidth - margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition - 22, color: .black, width: 1.0)
                
                drawLine(x1: timeCol, y1: yPosition, x2: timeCol, y2: yPosition - 22, color: .black, width: 0.5)
                drawLine(x1: marksCol, y1: yPosition, x2: marksCol, y2: yPosition - 22, color: .black, width: 0.5)
                drawLine(x1: timePerMarkCol, y1: yPosition, x2: timePerMarkCol, y2: yPosition - 22, color: .black, width: 0.5)
                drawLine(x1: efficiencyCol, y1: yPosition, x2: efficiencyCol, y2: yPosition - 22, color: .black, width: 0.5)
                
                drawText("QUESTION", font: tableHeaderFont, color: .black, x: qCol + 8, y: yPosition - 7)
                drawText("TIME SPENT", font: tableHeaderFont, color: .black, x: timeCol + 8, y: yPosition - 7)
                drawText("MARKS", font: tableHeaderFont, color: .black, x: marksCol + 8, y: yPosition - 7)
                drawText("TIME/MARK", font: tableHeaderFont, color: .black, x: timePerMarkCol + 8, y: yPosition - 7)
                drawText("EFFICIENCY", font: tableHeaderFont, color: .black, x: efficiencyCol + 8, y: yPosition - 7)
                
                yPosition -= 22
                drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
                yPosition -= 2
            }
            
            let rowTop = yPosition
            yPosition -= rowHeight
            
            // Draw left and right borders for this row
            drawLine(x1: margin, y1: rowTop, x2: margin, y2: yPosition, color: .black, width: 1.0)
            drawLine(x1: pageWidth - margin, y1: rowTop, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
            
            // Draw vertical column separators
            drawLine(x1: timeCol, y1: rowTop, x2: timeCol, y2: yPosition, color: .lightGray, width: 0.3)
            drawLine(x1: marksCol, y1: rowTop, x2: marksCol, y2: yPosition, color: .lightGray, width: 0.3)
            drawLine(x1: timePerMarkCol, y1: rowTop, x2: timePerMarkCol, y2: yPosition, color: .lightGray, width: 0.3)
            drawLine(x1: efficiencyCol, y1: rowTop, x2: efficiencyCol, y2: yPosition, color: .lightGray, width: 0.3)
            
            // Draw cell content with better vertical centering
            let textY = yPosition + 5
            
            drawText("Q\(question.number)", font: tableCellFont, color: .black, x: qCol + 8, y: textY)
            
            // Format time spent with milliseconds
            let timeSpent = question.timeSpent
            let mins = Int(timeSpent) / 60
            let secs = Int(timeSpent) % 60
            let ms = Int((timeSpent.truncatingRemainder(dividingBy: 1)) * 1000)
            let timeString = String(format: "%02d:%02d.%03d", mins, secs, ms)
            drawText(timeString, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), color: .black, x: timeCol + 8, y: textY)
            
            drawText("\(question.markAllocation)", font: tableCellFont, color: .black, x: marksCol + 8, y: textY)
            
            // Format time per mark with milliseconds
            let timePerMarkMs = Int(question.timePerMark * 1000)
            let timePerMarkString: String
            if timePerMarkMs < 1000 {
                timePerMarkString = String(format: "%dms", timePerMarkMs)
            } else {
                let wholeSeconds = Int(question.timePerMark)
                let ms = Int((question.timePerMark.truncatingRemainder(dividingBy: 1)) * 1000)
                timePerMarkString = String(format: "%d.%03ds", wholeSeconds, ms)
            }
            drawText(timePerMarkString, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), color: .black, x: timePerMarkCol + 8, y: textY)
            
            // Efficiency indicator
            let ratio: Double
            let efficiencyText: String
            let efficiencyColor: NSColor
            
            if question.timeSpent == 0 {
                efficiencyText = "N/A"
                efficiencyColor = .gray
            } else if session.averageTimePerMark > 0 && question.timePerMark > 0 {
                ratio = question.timePerMark / session.averageTimePerMark
                efficiencyText = String(format: "%.0f%%", ratio * 100)
                
                if ratio < 0.8 {
                    efficiencyColor = NSColor.systemGreen
                } else if ratio < 1.2 {
                    efficiencyColor = NSColor.systemOrange
                } else {
                    efficiencyColor = NSColor.systemRed
                }
            } else {
                efficiencyText = "N/A"
                efficiencyColor = .gray
            }
            
            drawText(efficiencyText, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold), color: efficiencyColor, x: efficiencyCol + 8, y: textY)
            
            // Draw bottom border for this row
            drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .lightGray, width: 0.3)
        }
        
        // Draw final bottom border of table
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1.0)
        
        yPosition -= 20
        
        // MARK: - State Change Log Section
        
        if yPosition < margin + 100 {
            context.endPage()
            context.beginPage(mediaBox: &mediaBox)
            yPosition = pageHeight - margin
        }
        
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .black, width: 1)
        yPosition -= 25
        
        let logTitleHeight = drawText("STATE CHANGE LOG", font: NSFont.systemFont(ofSize: 13, weight: .semibold), color: .black, x: margin, y: yPosition)
        yPosition -= logTitleHeight + 15
        
        let logFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        
        for question in session.questions {
            for log in question.stateChanges {
                if yPosition < margin + 20 {
                    context.endPage()
                    context.beginPage(mediaBox: &mediaBox)
                    yPosition = pageHeight - margin
                }
                
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm:ss.SSS"
                let timestamp = timeFormatter.string(from: log.timestamp)
                
                let questionNum = log.questionNumber.map { "Q\($0)" } ?? "—"
                let logLine = String(format: "%@ | %@ | %@", timestamp, questionNum.padding(toLength: 4, withPad: " ", startingAt: 0), log.state.rawValue)
                
                let logHeight = drawText(logLine, font: logFont, color: .darkGray, x: margin + 8, y: yPosition)
                yPosition -= logHeight + 2
            }
        }
        
        // MARK: - Footer
        
        yPosition = margin + 20
        drawLine(x1: margin, y1: yPosition, x2: pageWidth - margin, y2: yPosition, color: .lightGray, width: 0.5)
        yPosition -= 15
        
        let footerFont = NSFont.systemFont(ofSize: 8, weight: .regular)
        drawText("Generated by RMS — Revision Management System", font: footerFont, color: .gray, x: margin, y: yPosition)
        
        let generatedDate = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        drawText("Generated: \(generatedDate)", font: footerFont, color: .gray, x: margin, y: yPosition, alignment: .right, maxWidth: contentWidth)
        
        // End page and close PDF
        context.endPage()
        context.closePDF()
        
        // Convert to PDFDocument
        let data = pdfData as Data
        return PDFDocument(data: data)
    }
    
    static func saveReceipt(_ pdfDocument: PDFDocument, defaultName: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = defaultName
        savePanel.title = "Export Session Receipt"
        savePanel.message = "Choose a location to save your exam session receipt"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            _ = pdfDocument.write(to: url)
        }
    }
}
