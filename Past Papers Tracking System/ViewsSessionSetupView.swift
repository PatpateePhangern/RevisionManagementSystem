//
//  SessionSetupView.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import SwiftUI

// Model for question row in table
struct QuestionRow: Identifiable {
    let id = UUID()
    var questionNumber: String
    var markAllocation: Int
    var timeAllocation: TimeInterval // in seconds
    
    // Formatted time for display
    var formattedTime: String {
        let minutes = Int(timeAllocation) / 60
        let seconds = Int(timeAllocation) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct SessionSetupView: View {
    @Binding var isPresented: Bool
    let onCreateSession: (String, Int, [Int], [TimeInterval]) -> Void
    
    @State private var examTitle: String = ""
    @State private var totalExamTimeHours: Int = 1
    @State private var totalExamTimeMinutes: Int = 0
    @State private var totalExamTimeSeconds: Int = 0
    @State private var questionRows: [QuestionRow] = []
    @State private var selection = Set<QuestionRow.ID>()
    @FocusState private var focusedField: FocusedField?
    
    enum FocusedField: Hashable {
        case questionNumber(UUID)
        case markAllocation(UUID)
        case totalExamTimeHours
        case totalExamTimeMinutes
        case totalExamTimeSeconds
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("New Exam Session")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                
                Text("Configure exam parameters")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            // Scrollable Form Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Exam Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exam Title")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Mathematics Final Exam", text: $examTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // Total Exam Time
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total Exam Time")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            // Hours
                            TextField("", value: $totalExamTimeHours, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .multilineTextAlignment(.trailing)
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .frame(width: 60)
                                .focused($focusedField, equals: .totalExamTimeHours)
                                .onChange(of: totalExamTimeHours) { oldValue, newValue in
                                    totalExamTimeHours = max(0, newValue)
                                }
                            
                            Text("h")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                            
                            // Minutes
                            TextField("", value: $totalExamTimeMinutes, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .multilineTextAlignment(.trailing)
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .frame(width: 60)
                                .focused($focusedField, equals: .totalExamTimeMinutes)
                                .onChange(of: totalExamTimeMinutes) { oldValue, newValue in
                                    totalExamTimeMinutes = max(0, min(59, newValue))
                                }
                            
                            Text("m")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                            
                            // Seconds
                            TextField("", value: $totalExamTimeSeconds, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .multilineTextAlignment(.trailing)
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .frame(width: 60)
                                .focused($focusedField, equals: .totalExamTimeSeconds)
                                .onChange(of: totalExamTimeSeconds) { oldValue, newValue in
                                    totalExamTimeSeconds = max(0, min(59, newValue))
                                }
                            
                            Text("s")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                            
                            if totalMarks > 0 {
                                Spacer()
                                Text("→ \(formattedTimePerMark)")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Questions Table
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Questions")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(.secondary)
                            
                            Text("(Double-click cells to edit)")
                                .font(.system(size: 11, weight: .regular, design: .default))
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            // Table Actions
                            HStack(spacing: 8) {
                                Button(action: addQuestion) {
                                    Label("Add", systemImage: "plus")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .keyboardShortcut("+", modifiers: .command)
                                
                                Button(action: removeSelectedQuestions) {
                                    Label("Remove", systemImage: "minus")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .disabled(selection.isEmpty)
                                .keyboardShortcut(.delete, modifiers: .command)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Table
                        Table($questionRows, selection: $selection) {
                            TableColumn("Question #") { $row in
                                TextField("", text: $row.questionNumber)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: .regular, design: .default))
                                    .multilineTextAlignment(.center)
                                    .labelsHidden()
                                    .focused($focusedField, equals: .questionNumber(row.id))
                                    .onSubmit {
                                        // Tab moves to mark allocation in same row
                                        focusedField = .markAllocation(row.id)
                                    }
                            }
                            .width(min: 70, ideal: 90, max: 110)
                            
                            TableColumn("Marks") { $row in
                                TextField("", value: $row.markAllocation, format: .number)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: .regular, design: .default))
                                    .multilineTextAlignment(.center)
                                    .labelsHidden()
                                    .focused($focusedField, equals: .markAllocation(row.id))
                                    .onSubmit {
                                        // Tab moves to next row's question number
                                        if let currentIndex = questionRows.firstIndex(where: { $0.id == row.id }) {
                                            let nextIndex = currentIndex + 1
                                            if nextIndex < questionRows.count {
                                                focusedField = .questionNumber(questionRows[nextIndex].id)
                                            } else {
                                                // Wrap to first row
                                                if !questionRows.isEmpty {
                                                    focusedField = .questionNumber(questionRows[0].id)
                                                }
                                            }
                                        }
                                    }
                                    .onChange(of: row.markAllocation) { oldValue, newValue in
                                        row.markAllocation = max(1, newValue)
                                    }
                            }
                            .width(min: 60, ideal: 80, max: 100)
                            
                            TableColumn("Allocated Time") { $row in
                                Text(formattedQuestionTime(for: row))
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                            .width(min: 100, ideal: 120, max: 140)
                        }
                        .tableStyle(.inset)
                        .frame(height: 280)
                        .padding(.horizontal, 24)
                        .focusable(true)
                        .onMoveCommand { direction in
                            handleArrowKey(direction)
                        }
                    }
                    
                    // Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Summary")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Text("Total Questions:")
                                    .font(.system(size: 12, weight: .regular, design: .default))
                                Text("\(questionRows.count)")
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                            }
                            
                            HStack(spacing: 4) {
                                Text("Total Marks:")
                                    .font(.system(size: 12, weight: .regular, design: .default))
                                Text("\(totalMarks)")
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                            }
                            
                            HStack(spacing: 4) {
                                Text("Total Time:")
                                    .font(.system(size: 12, weight: .regular, design: .default))
                                Text(formattedTotalTime)
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                            }
                        }
                        .foregroundColor(.secondary)
                        
                        if totalMarks > 0 {
                            HStack(spacing: 4) {
                                Text("Time per Mark:")
                                    .font(.system(size: 12, weight: .regular, design: .default))
                                Text(formattedTimePerMark)
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            
            Divider()
            
            // Footer Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create Session") {
                    createSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreateSession)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 550)
    }
    
    // MARK: - Computed Properties
    
    /// Total exam time in seconds
    private var totalExamTimeInSeconds: TimeInterval {
        TimeInterval(totalExamTimeHours * 3600 + totalExamTimeMinutes * 60 + totalExamTimeSeconds)
    }
    
    private var totalMarks: Int {
        questionRows.reduce(0) { $0 + $1.markAllocation }
    }
    
    /// Time per mark in seconds, calculated from total exam time
    private var timePerMark: TimeInterval {
        guard totalMarks > 0 else { return 0 }
        return totalExamTimeInSeconds / TimeInterval(totalMarks)
    }
    
    /// Formatted time per mark for display
    private var formattedTimePerMark: String {
        let seconds = Int(timePerMark)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        
        if minutes > 0 {
            return String(format: "%d min %d sec/mark", minutes, remainingSeconds)
        } else {
            return String(format: "%d sec/mark", seconds)
        }
    }
    
    /// Calculate allocated time for a specific question based on its marks
    private func calculatedTimeAllocation(for row: QuestionRow) -> TimeInterval {
        return timePerMark * TimeInterval(row.markAllocation)
    }
    
    /// Formatted time allocation for a question
    private func formattedQuestionTime(for row: QuestionRow) -> String {
        let totalSeconds = calculatedTimeAllocation(for: row)
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var totalTime: TimeInterval {
        totalExamTimeInSeconds
    }
    
    private var formattedTotalTime: String {
        let totalSeconds = Int(totalExamTimeInSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        var components: [String] = []
        if hours > 0 {
            components.append("\(hours) h")
        }
        if minutes > 0 {
            components.append("\(minutes) m")
        }
        if seconds > 0 || components.isEmpty {
            components.append("\(seconds) s")
        }
        
        return components.joined(separator: " ")
    }
    
    private var canCreateSession: Bool {
        !examTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        !questionRows.isEmpty &&
        totalExamTimeInSeconds > 0
    }
    
    // MARK: - Helper Methods
    
    private func handleArrowKey(_ direction: MoveCommandDirection) {
        guard let currentFocus = focusedField else { return }
        
        switch currentFocus {
        case .questionNumber(let id):
            if let currentIndex = questionRows.firstIndex(where: { $0.id == id }) {
                switch direction {
                case .up:
                    if currentIndex > 0 {
                        focusedField = .questionNumber(questionRows[currentIndex - 1].id)
                    }
                case .down:
                    if currentIndex < questionRows.count - 1 {
                        focusedField = .questionNumber(questionRows[currentIndex + 1].id)
                    }
                case .left, .right:
                    break // Don't move horizontally with arrow keys
                @unknown default:
                    break
                }
            }
            
        case .markAllocation(let id):
            if let currentIndex = questionRows.firstIndex(where: { $0.id == id }) {
                switch direction {
                case .up:
                    if currentIndex > 0 {
                        focusedField = .markAllocation(questionRows[currentIndex - 1].id)
                    }
                case .down:
                    if currentIndex < questionRows.count - 1 {
                        focusedField = .markAllocation(questionRows[currentIndex + 1].id)
                    }
                case .left, .right:
                    break // Don't move horizontally with arrow keys
                @unknown default:
                    break
                }
            }
            
        case .totalExamTimeHours, .totalExamTimeMinutes, .totalExamTimeSeconds:
            break // No arrow key navigation from total exam time fields
        }
    }
    
    private func addQuestion() {
        // Find the next question number - try to parse existing numbers
        let existingNumbers = questionRows.compactMap { Int($0.questionNumber) }
        let nextNumber = (existingNumbers.max() ?? 0) + 1
        let newQuestion = QuestionRow(questionNumber: "\(nextNumber)", markAllocation: 10, timeAllocation: 0) // timeAllocation is now calculated
        questionRows.append(newQuestion)
        
        // Auto-focus the new question's number field
        focusedField = .questionNumber(newQuestion.id)
    }
    
    private func removeSelectedQuestions() {
        guard !selection.isEmpty else { return }
        questionRows.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
    
    private func createSession() {
        let title = examTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Sort by question number (try to sort numerically if possible, otherwise alphabetically)
        let sortedRows = questionRows.sorted { lhs, rhs in
            // Try to parse as integers for proper numeric sorting
            if let lhsNum = Int(lhs.questionNumber), let rhsNum = Int(rhs.questionNumber) {
                return lhsNum < rhsNum
            }
            // Fallback to string comparison for mixed formats like "4a)ii)"
            return lhs.questionNumber < rhs.questionNumber
        }
        let marks = sortedRows.map { $0.markAllocation }
        
        // Calculate time allocations based on marks and time per mark
        let times = sortedRows.map { row in
            calculatedTimeAllocation(for: row)
        }
        let count = questionRows.count
        
        onCreateSession(title, count, marks, times)
        isPresented = false
    }
}

#Preview("Session Setup") {
    @Previewable @State var isPresented = true
    
    SessionSetupView(isPresented: $isPresented) { title, count, marks, times in
        print("Created: \(title), \(count) questions")
        print("Marks: \(marks)")
        print("Times: \(times)")
    }
    .frame(width: 600, height: 550)
}
