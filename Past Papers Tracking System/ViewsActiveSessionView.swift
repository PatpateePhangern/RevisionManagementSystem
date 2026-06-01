//
//  ActiveSessionView.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

struct ActiveSessionView: View {
    @ObservedObject var engine: TimingEngine
    let onFinish: () -> Void
    
    @State private var searchText = ""
    @State private var showSettings = false
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Sidebar - Question List
                VStack(spacing: 0) {
                    questionSidebar
                }
                .frame(width: 320)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                
                Divider()
                
                // Right Side - Main Content
                VStack(spacing: 0) {
                    // Top Bar
                    topBar
                    
                    Divider()
                    
                    // Main Timer Display
                    mainTimerView
                    
                    Divider()
                    
                    // Bottom Control Bar
                    controlBar
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.session?.title ?? "Exam Session")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                
                Text("Session in progress")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Settings Button
            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            
            Divider()
                .frame(height: 24)
            
            // Total Time Display - Much Bigger with Milliseconds
            VStack(alignment: .trailing, spacing: 4) {
                Text("TOTAL TIME")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                
                Text(engine.session?.formattedTotalTimeWithMilliseconds ?? "00:00.00")
                    .font(.system(size: 42, weight: .medium, design: .monospaced))
                    .foregroundColor(engine.session?.isOvertime == true ? .red : .primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Question Sidebar
    
    private var questionSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            HStack {
                Text("Questions")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.0)
                
                Spacer()
                
                Text("\(filteredQuestions.count) of \(engine.session?.questions.count ?? 0)")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                TextField("Search questions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .default))
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(7)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Divider()
            
            // Question List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filteredQuestions.enumerated()), id: \.element.id) { _, question in
                        if let index = engine.session?.questions.firstIndex(where: { $0.id == question.id }) {
                            questionRow(question: question, index: index)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private var filteredQuestions: [Question] {
        guard let questions = engine.session?.questions else { return [] }
        
        if searchText.isEmpty {
            return questions
        }
        
        return questions.filter { question in
            "Q\(question.number)".localizedCaseInsensitiveContains(searchText) ||
            "\(question.number)".contains(searchText)
        }
    }
    
    private func questionRow(question: Question, index: Int) -> some View {
        let isActive = engine.session?.currentQuestionIndex == index
        let isPaused = engine.session?.isPaused ?? false
        let isOnBreak = engine.session?.isOnBreak ?? false
        
        return Button(action: {
            if !(engine.session?.isPaused ?? true) && !(engine.session?.isOnBreak ?? false) {
                engine.jumpToQuestion(index)
            }
        }) {
            HStack(spacing: 14) {
                // Question Number
                Text("Q\(question.number)")
                    .font(.system(size: 15, weight: isActive ? .semibold : .medium, design: .default))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(width: 44, alignment: .leading)
                
                // Mark allocation
                Text("\(question.markAllocation) marks")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Active Indicator
                if isActive {
                    Circle()
                        .fill(isOnBreak ? Color.purple : (isPaused ? Color.orange : Color.green))
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(engine.session?.isPaused ?? true || engine.session?.isOnBreak ?? false)
    }
    
    // MARK: - Main Timer View
    
    private var mainTimerView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                // Question Number
                Text("Question \(engine.session?.currentQuestion?.number ?? 0)")
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(2.0)
                
                // Elapsed Time Display (Stopwatch Style - Counting UP) with Milliseconds & Microseconds
                VStack(spacing: 12) {
                    // Main timer with milliseconds
                    Text(engine.formattedCurrentElapsedTime)
                        .font(.system(size: 120, weight: .medium, design: .monospaced))
                        .foregroundColor(engine.isCurrentQuestionOvertime ? .red : .primary)
                        .monospacedDigit()
                    
                    // Microseconds display (smaller, below main timer)
                    Text(engine.formattedCurrentElapsedTimeWithMicroseconds)
                        .font(.system(size: 18, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    Text(engine.isCurrentQuestionOvertime ? "Elapsed Time (Overtime)" : "Elapsed Time")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(engine.isCurrentQuestionOvertime ? .red : .secondary)
                }
                
                // Mark and Time Allocation
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Allocated:")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                        
                        Text("\(engine.session?.currentQuestion?.markAllocation ?? 0) marks")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                    }
                    
                    if let currentQuestion = engine.session?.currentQuestion {
                        HStack(spacing: 12) {
                            Text("Time Limit:")
                                .font(.system(size: 15, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                            
                            Text(currentQuestion.formattedAllocatedTime)
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                
                // Status Indicator
                if let session = engine.session {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(session.isOnBreak ? Color.purple : (session.isPaused ? Color.orange : Color.green))
                            .frame(width: 12, height: 12)
                        
                        Text(session.isOnBreak ? "On Break" : (session.isPaused ? "Paused" : "Active"))
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(session.isOnBreak ? .purple : (session.isPaused ? .orange : .green))
                    }
                    .padding(.top, 16)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Control Bar
    
    private var controlBar: some View {
        HStack(spacing: 16) {
            let settings = AppSettings.shared
            
            // Previous Question
            Button(action: {
                engine.previousQuestion()
            }) {
                Label("Previous", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .medium, design: .default))
            }
            .disabled((engine.session?.currentQuestionIndex ?? 0) == 0 || (engine.session?.isPaused ?? true) || (engine.session?.isOnBreak ?? false))
            .keyboardShortcut(
                KeyEquivalent(settings.getShortcut(for: .previousQuestion).key.first ?? "a"),
                modifiers: settings.getShortcut(for: .previousQuestion).modifiers
            )
            
            // Next Question
            Button(action: {
                engine.nextQuestion()
            }) {
                Label("Next", systemImage: "chevron.right")
                    .font(.system(size: 13, weight: .medium, design: .default))
            }
            .disabled((engine.session?.currentQuestionIndex ?? 0) >= ((engine.session?.questions.count ?? 1) - 1) || (engine.session?.isPaused ?? true) || (engine.session?.isOnBreak ?? false))
            .keyboardShortcut(
                KeyEquivalent(settings.getShortcut(for: .nextQuestion).key.first ?? "a"),
                modifiers: settings.getShortcut(for: .nextQuestion).modifiers
            )
            
            Spacer()
            
            // Break/Resume from Break
            if engine.session?.isOnBreak ?? false {
                Button(action: {
                    engine.resumeFromBreak()
                }) {
                    Label("Resume from Break", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .medium, design: .default))
                }
                .keyboardShortcut("b", modifiers: .command)
            } else {
                Button(action: {
                    engine.takeBreak()
                }) {
                    Label("Take Break", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 13, weight: .medium, design: .default))
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(engine.session?.isPaused ?? true)
            }
            
            // Pause/Resume
            if engine.session?.isPaused ?? false {
                Button(action: {
                    engine.resumeSession()
                }) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .medium, design: .default))
                }
                .keyboardShortcut(
                    KeyEquivalent(settings.getShortcut(for: .pauseResume).key.first ?? "a"),
                    modifiers: settings.getShortcut(for: .pauseResume).modifiers
                )
                .disabled(engine.session?.isOnBreak ?? false)
            } else {
                Button(action: {
                    engine.pauseSession()
                }) {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.system(size: 13, weight: .medium, design: .default))
                }
                .keyboardShortcut(
                    KeyEquivalent(settings.getShortcut(for: .pauseResume).key.first ?? "a"),
                    modifiers: settings.getShortcut(for: .pauseResume).modifiers
                )
                .disabled(engine.session?.isOnBreak ?? false)
            }
            
            // Finish
            Button(action: {
                engine.finishSession()
                onFinish()
            }) {
                Label("Finish Exam", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .default))
            }
            .keyboardShortcut(
                KeyEquivalent(settings.getShortcut(for: .finishExam).key.first ?? "a"),
                modifiers: settings.getShortcut(for: .finishExam).modifiers
            )
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Helper Methods
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

#Preview {
    @Previewable @State var engine: TimingEngine = {
        let engine = TimingEngine()
        engine.createSession(
            title: "Mathematics Final Exam", 
            questionCount: 10, 
            markAllocations: Array(repeating: 10, count: 10),
            timeAllocations: Array(repeating: 120, count: 10) // 2 minutes per question
        )
        engine.startSession()
        return engine
    }()
    
    ActiveSessionView(engine: engine) {
        print("Session finished")
    }
    .frame(width: 1400, height: 900)
}
