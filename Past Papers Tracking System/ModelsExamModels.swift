//
//  ExamModels.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import Foundation

// MARK: - State Change Types

enum SessionState: String, Codable {
    case start = "Start"
    case pause = "Pause"
    case resume = "Resume"
    case `break` = "Break"
    case resumeFromBreak = "Resume from Break"
    case questionSwitch = "Question Switch"
    case finish = "Finish"
}

// MARK: - State Change Log Entry

struct StateChangeLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let state: SessionState
    let questionNumber: Int?
    
    init(id: UUID = UUID(), timestamp: Date = Date(), state: SessionState, questionNumber: Int? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.questionNumber = questionNumber
    }
}

// MARK: - Question Model

struct Question: Identifiable, Codable {
    let id: UUID
    let number: Int
    let markAllocation: Int
    let allocatedTime: TimeInterval // Total time allocated for this question in seconds
    var timeSpent: TimeInterval // In seconds (tracked for analytics)
    var stateChanges: [StateChangeLog]
    
    init(id: UUID = UUID(), number: Int, markAllocation: Int, allocatedTime: TimeInterval) {
        self.id = id
        self.number = number
        self.markAllocation = markAllocation
        self.allocatedTime = allocatedTime
        self.timeSpent = 0
        self.stateChanges = []
    }
    
    /// Time remaining for this question (can be negative if overtime)
    var remainingTime: TimeInterval {
        return allocatedTime - timeSpent
    }
    
    /// Formatted time showing time spent (not remaining)
    var formattedTime: String {
        let time = abs(timeSpent)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
    
    /// Formatted time showing remaining/overtime
    var formattedRemainingTime: String {
        let time = abs(remainingTime)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let sign = remainingTime < 0 ? "-" : ""
        return String(format: "%@%02d:%02d", sign, minutes, seconds)
    }
    
    /// Formatted allocated time
    var formattedAllocatedTime: String {
        let minutes = Int(allocatedTime) / 60
        let seconds = Int(allocatedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Returns true if the question is overtime
    var isOvertime: Bool {
        return timeSpent > allocatedTime
    }
    
    var timePerMark: TimeInterval {
        guard markAllocation > 0 else { return 0 }
        return timeSpent / Double(markAllocation)
    }
    
    var formattedTimePerMark: String {
        let milliseconds = Int(timePerMark * 1000)
        if milliseconds < 1000 {
            return String(format: "%dms/mark", milliseconds)
        } else {
            let seconds = timePerMark
            let wholeSeconds = Int(seconds)
            let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(format: "%d.%03ds/mark", wholeSeconds, ms)
        }
    }
}

// MARK: - Exam Session Model

struct ExamSession: Identifiable, Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    var questions: [Question]
    var currentQuestionIndex: Int
    var totalTimeSpent: TimeInterval
    var breakTimeSpent: TimeInterval // Track break time separately
    var isActive: Bool
    var isPaused: Bool
    var isOnBreak: Bool
    var startTime: Date?
    var endTime: Date?
    
    init(id: UUID = UUID(), title: String, questionCount: Int, markAllocations: [Int], timeAllocations: [TimeInterval]) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.questions = zip(zip(1...questionCount, markAllocations), timeAllocations).map { (numberAndMarks, time) in
            let (number, marks) = numberAndMarks
            return Question(number: number, markAllocation: marks, allocatedTime: time)
        }
        self.currentQuestionIndex = 0
        self.totalTimeSpent = 0
        self.breakTimeSpent = 0
        self.isActive = false
        self.isPaused = false
        self.isOnBreak = false
    }
    
    var currentQuestion: Question? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }
    
    /// Total allocated time for the entire exam
    var totalAllocatedTime: TimeInterval {
        questions.reduce(0) { $0 + $1.allocatedTime }
    }
    
    /// Total remaining time across all questions
    var totalRemainingTime: TimeInterval {
        return totalAllocatedTime - totalTimeSpent
    }
    
    /// Formatted total time spent with milliseconds
    var formattedTotalTime: String {
        let time = abs(totalTimeSpent)
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
    
    /// Formatted total time with milliseconds
    var formattedTotalTimeWithMilliseconds: String {
        let time = abs(totalRemainingTime)
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        let sign = totalRemainingTime < 0 ? "-" : ""
        
        if hours > 0 {
            return String(format: "%@%02d:%02d:%02d.%02d", sign, hours, minutes, seconds, milliseconds)
        } else {
            return String(format: "%@%02d:%02d.%02d", sign, minutes, seconds, milliseconds)
        }
    }
    
    /// Formatted total time with microseconds
    var formattedTotalTimeWithMicroseconds: String {
        let time = abs(totalRemainingTime)
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let microseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        let sign = totalRemainingTime < 0 ? "-" : ""
        
        if hours > 0 {
            return String(format: "%@%02d:%02d:%02d.%06d", sign, hours, minutes, seconds, microseconds)
        } else {
            return String(format: "%@%02d:%02d.%06d", sign, minutes, seconds, microseconds)
        }
    }
    
    /// Formatted allocated total time
    var formattedAllocatedTime: String {
        let hours = Int(totalAllocatedTime) / 3600
        let minutes = (Int(totalAllocatedTime) % 3600) / 60
        let seconds = Int(totalAllocatedTime) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Returns true if the session is currently overtime
    var isOvertime: Bool {
        return totalTimeSpent > totalAllocatedTime
    }
    
    var totalMarks: Int {
        questions.reduce(0) { $0 + $1.markAllocation }
    }
    
    var averageTimePerMark: TimeInterval {
        guard totalMarks > 0 else { return 0 }
        return totalTimeSpent / Double(totalMarks)
    }
    
    var formattedAverageTimePerMark: String {
        let milliseconds = Int(averageTimePerMark * 1000)
        if milliseconds < 1000 {
            return String(format: "%dms", milliseconds)
        } else {
            let seconds = averageTimePerMark
            let wholeSeconds = Int(seconds)
            let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(format: "%d.%03ds", wholeSeconds, ms)
        }
    }
}
