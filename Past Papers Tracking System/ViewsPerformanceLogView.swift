//
//  PerformanceLogView.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

struct PerformanceLogView: View {
    let session: ExamSession
    let onExportPDF: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Statistics Overview
            statisticsOverview
            
            Divider()
            
            // Performance Table
            ScrollView {
                performanceTable
            }
            
            Divider()
            
            // State Change Log
            stateChangeLogView
            
            Divider()
            
            // Footer Actions
            footerActions
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Log")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                Label(session.title, systemImage: "doc.text")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                
                if let startTime = session.startTime {
                    Label(formatDate(startTime), systemImage: "calendar")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
    
    // MARK: - Statistics Overview
    
    private var statisticsOverview: some View {
        HStack(spacing: 32) {
            statisticItem(
                title: "Total Time",
                value: session.formattedTotalTime,
                icon: "clock.fill"
            )
            
            Divider()
                .frame(height: 40)
            
            statisticItem(
                title: "Questions",
                value: "\(session.questions.count)",
                icon: "list.number"
            )
            
            Divider()
                .frame(height: 40)
            
            statisticItem(
                title: "Total Marks",
                value: "\(session.totalMarks)",
                icon: "star.fill"
            )
            
            Divider()
                .frame(height: 40)
            
            statisticItem(
                title: "Avg Time/Mark",
                value: session.formattedAverageTimePerMark,
                icon: "chart.bar.fill"
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func statisticItem(title: String, value: String, icon: String) -> some View {
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Performance Table
    
    private var performanceTable: some View {
        VStack(spacing: 0) {
            // Table Header
            tableHeaderRow
            
            Divider()
            
            // Table Rows
            ForEach(session.questions) { question in
                tableRow(for: question)
                Divider()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var tableHeaderRow: some View {
        HStack(spacing: 16) {
            Text("Question")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .frame(width: 80, alignment: .leading)
            
            Text("Time Spent")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .frame(width: 100, alignment: .trailing)
            
            Text("Marks")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .frame(width: 80, alignment: .trailing)
            
            Text("Time/Mark")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .frame(width: 100, alignment: .trailing)
            
            Text("Efficiency")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
    
    private func tableRow(for question: Question) -> some View {
        return HStack(spacing: 16) {
            Text("Q\(question.number)")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)
            
            Text(question.formattedTime)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .trailing)
            
            Text("\(question.markAllocation)")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .trailing)
            
            Text(question.formattedTimePerMark)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .trailing)
            
            efficiencyBar(for: question)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
    
    private func efficiencyBar(for question: Question) -> some View {
        // Calculate efficiency ratio
        let ratio: Double
        if session.averageTimePerMark > 0 && question.timePerMark > 0 {
            ratio = question.timePerMark / session.averageTimePerMark
        } else if question.timeSpent == 0 {
            // Question not started yet
            ratio = 0
        } else {
            ratio = 1.0
        }
        
        let color: Color = {
            if question.timeSpent == 0 {
                return .gray
            } else if ratio < 0.8 {
                return .green
            } else if ratio < 1.2 {
                return .orange
            } else {
                return .red
            }
        }()
        
        let displayText: String
        if question.timeSpent == 0 {
            displayText = "N/A"
        } else {
            displayText = String(format: "%.0f%%", ratio * 100)
        }
        
        return HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    if question.timeSpent > 0 {
                        Rectangle()
                            .fill(color)
                            .frame(width: min(geometry.size.width * CGFloat(ratio), geometry.size.width), height: 6)
                            .cornerRadius(3)
                    }
                }
            }
            .frame(width: 100, height: 6)
            
            Text(displayText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 50, alignment: .trailing)
        }
    }
    
    // MARK: - State Change Log
    
    private var stateChangeLogView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State Change Log")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(session.questions) { question in
                        ForEach(question.stateChanges) { log in
                            stateChangeRow(log: log)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 200)
        }
    }
    
    private func stateChangeRow(log: StateChangeLog) -> some View {
        return HStack(spacing: 12) {
            Text(formatTimestamp(log.timestamp))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            if let questionNumber = log.questionNumber {
                Text("Q\(questionNumber)")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
            } else {
                Text("—")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            
            stateLabel(log.state)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }
    
    private func stateLabel(_ state: SessionState) -> some View {
        let config: (String, Color) = {
            switch state {
            case .start: return ("Start", .green)
            case .pause: return ("Pause", .orange)
            case .resume: return ("Resume", .blue)
            case .break: return ("Break", .purple)
            case .resumeFromBreak: return ("Resume from Break", .cyan)
            case .questionSwitch: return ("Switch", .purple)
            case .finish: return ("Finish", .red)
            }
        }()
        
        return Text(config.0)
            .font(.system(size: 11, weight: .medium, design: .default))
            .foregroundColor(config.1)
    }
    
    // MARK: - Footer Actions
    
    private var footerActions: some View {
        HStack(spacing: 12) {
            Button("Close") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button(action: onExportPDF) {
                Label("Export PDF", systemImage: "arrow.down.doc.fill")
                    .font(.system(size: 12, weight: .semibold, design: .default))
            }
            .keyboardShortcut("e", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func formatTimePerMark(_ seconds: TimeInterval) -> String {
        let milliseconds = Int(seconds * 1000)
        if milliseconds < 1000 {
            return String(format: "%dms", milliseconds)
        } else {
            let wholeSeconds = Int(seconds)
            let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(format: "%d.%03ds", wholeSeconds, ms)
        }
    }
}

#Preview {
    @Previewable @State var session = ExamSession(
        title: "Mathematics Final Exam", 
        questionCount: 5, 
        markAllocations: [10, 15, 20, 10, 15],
        timeAllocations: [120, 180, 240, 120, 180] // 2, 3, 4, 2, 3 minutes
    )
    
    PerformanceLogView(session: session, onExportPDF: {
        print("Export PDF")
    }, onClose: {
        print("Close")
    })
    .frame(width: 900, height: 700)
}
