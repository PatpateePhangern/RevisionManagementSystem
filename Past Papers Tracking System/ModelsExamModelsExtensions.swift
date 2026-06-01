//
//  ExamModelsExtensions.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import Foundation

// MARK: - ExamSession Extensions

extension ExamSession {
    /// Returns a summary of the session for display purposes
    var summaryDescription: String {
        """
        \(title)
        Questions: \(questions.count)
        Total Marks: \(totalMarks)
        Duration: \(formattedTotalTime)
        """
    }
    
    /// Returns the most time-consuming question
    var longestQuestion: Question? {
        questions.max(by: { $0.timeSpent < $1.timeSpent })
    }
    
    /// Returns the most efficient question (lowest time per mark)
    var mostEfficientQuestion: Question? {
        questions.min(by: { $0.timePerMark < $1.timePerMark })
    }
    
    /// Returns the least efficient question (highest time per mark)
    var leastEfficientQuestion: Question? {
        questions.max(by: { $0.timePerMark < $1.timePerMark })
    }
    
    /// Returns questions grouped by efficiency rating
    var questionsByEfficiency: (efficient: [Question], normal: [Question], inefficient: [Question]) {
        let avg = averageTimePerMark
        
        var efficient: [Question] = []
        var normal: [Question] = []
        var inefficient: [Question] = []
        
        for question in questions {
            let ratio = avg > 0 ? question.timePerMark / avg : 1.0
            
            if ratio < 0.8 {
                efficient.append(question)
            } else if ratio < 1.2 {
                normal.append(question)
            } else {
                inefficient.append(question)
            }
        }
        
        return (efficient, normal, inefficient)
    }
    
    /// Calculates median time per question
    var medianTimePerQuestion: TimeInterval {
        let sortedTimes = questions.map { $0.timeSpent }.sorted()
        let count = sortedTimes.count
        
        guard count > 0 else { return 0 }
        
        if count % 2 == 0 {
            return (sortedTimes[count / 2 - 1] + sortedTimes[count / 2]) / 2
        } else {
            return sortedTimes[count / 2]
        }
    }
}

// MARK: - Question Extensions

extension Question {
    /// Returns a detailed description of the question
    var detailedDescription: String {
        """
        Question \(number)
        Time Spent: \(formattedTime)
        Marks: \(markAllocation)
        Time per Mark: \(formattedTimePerMark)
        State Changes: \(stateChanges.count)
        """
    }
    
    /// Returns the duration of the longest continuous work period
    var longestWorkPeriod: TimeInterval {
        guard stateChanges.count >= 2 else { return timeSpent }
        
        var maxDuration: TimeInterval = 0
        var startTime: Date?
        
        for change in stateChanges {
            switch change.state {
            case .start, .resume, .resumeFromBreak:
                startTime = change.timestamp
            case .pause, .questionSwitch, .finish, .break:
                if let start = startTime {
                    let duration = change.timestamp.timeIntervalSince(start)
                    maxDuration = max(maxDuration, duration)
                }
                startTime = nil
            }
        }
        
        return maxDuration
    }
    
    /// Returns the number of times the question was paused
    var pauseCount: Int {
        stateChanges.filter { $0.state == .pause }.count
    }
    
    /// Returns whether this question was completed in one continuous session
    var wasCompletedContinuously: Bool {
        pauseCount == 0 && stateChanges.filter({ $0.state == .questionSwitch }).count <= 1
    }
}

// MARK: - StateChangeLog Extensions

extension StateChangeLog {
    /// Returns a formatted timestamp string with milliseconds
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    /// Returns a human-readable description
    var readableDescription: String {
        let questionText = questionNumber.map { "Q\($0)" } ?? "Session"
        return "\(formattedTime) - \(questionText): \(state.rawValue)"
    }
}

// MARK: - Array Extensions for Statistics

extension Array where Element == Question {
    /// Calculates the total time spent on all questions
    var totalTimeSpent: TimeInterval {
        reduce(0) { $0 + $1.timeSpent }
    }
    
    /// Calculates the total marks across all questions
    var totalMarks: Int {
        reduce(0) { $0 + $1.markAllocation }
    }
    
    /// Returns questions sorted by time spent (descending)
    var sortedByTime: [Question] {
        sorted { $0.timeSpent > $1.timeSpent }
    }
    
    /// Returns questions sorted by efficiency (time per mark)
    var sortedByEfficiency: [Question] {
        sorted { $0.timePerMark < $1.timePerMark }
    }
}

// MARK: - Validation Extensions

extension ExamSession {
    /// Actual work time (total time minus break time)
    var actualWorkTime: TimeInterval {
        return totalTimeSpent - breakTimeSpent
    }
    
    /// Formatted actual work time
    var formattedActualWorkTime: String {
        let time = abs(actualWorkTime)
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
        }
    }
    
    /// Formatted break time
    var formattedBreakTime: String {
        let time = abs(breakTimeSpent)
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
        }
    }
    
    /// Validates the integrity of the session data
    var isValid: Bool {
        // Check basic requirements
        guard !title.isEmpty else { return false }
        guard !questions.isEmpty else { return false }
        guard totalMarks > 0 else { return false }
        
        // Check each question has valid data
        for question in questions {
            guard question.number > 0 else { return false }
            guard question.markAllocation > 0 else { return false }
            guard question.timeSpent >= 0 else { return false }
        }
        
        // Check question numbers are sequential
        for (index, question) in questions.enumerated() {
            guard question.number == index + 1 else { return false }
        }
        
        return true
    }
    
    /// Returns any validation warnings (non-critical issues)
    var validationWarnings: [String] {
        var warnings: [String] = []
        
        // Check for unusually long sessions
        if totalTimeSpent > 14400 { // 4 hours
            warnings.append("Session duration exceeds 4 hours")
        }
        
        // Check for questions with no time
        let questionsWithNoTime = questions.filter { $0.timeSpent == 0 }
        if !questionsWithNoTime.isEmpty {
            warnings.append("\(questionsWithNoTime.count) question(s) have no time recorded")
        }
        
        // Check for questions with excessive time
        let avg = averageTimePerMark
        for question in questions {
            if avg > 0 && question.timePerMark > avg * 3 {
                warnings.append("Question \(question.number) took significantly longer than average")
            }
        }
        
        return warnings
    }
}
