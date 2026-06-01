//
//  TimingEngine.swift
//  Exam Timing System
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

import Foundation
import Combine
import AVFoundation
import AppKit

@MainActor
class TimingEngine: ObservableObject {
    @Published private(set) var session: ExamSession?
    @Published private(set) var currentElapsedTime: TimeInterval = 0
    @Published private(set) var currentRemainingTime: TimeInterval = 0
    
    private var timer: Timer?
    private var questionStartTime: Date?
    private var sessionStartTime: Date?
    private var breakStartTime: Date?
    
    // MARK: - Sound Alert System
    private var audioPlayer: AVAudioPlayer?
    private var fiveMinuteAlertTriggered = false
    private var timeUpAlertTriggered = false
    private let settings = AppSettings.shared
    
    // MARK: - Session Management
    
    func createSession(title: String, questionCount: Int, markAllocations: [Int], timeAllocations: [TimeInterval]) {
        guard markAllocations.count == questionCount,
              timeAllocations.count == questionCount else {
            print("Error: Mark and time allocations count must match question count")
            return
        }
        
        session = ExamSession(title: title, questionCount: questionCount, markAllocations: markAllocations, timeAllocations: timeAllocations)
        
        // Reset alert flags for new session
        fiveMinuteAlertTriggered = false
        timeUpAlertTriggered = false
    }
    
    func startSession() {
        guard var currentSession = session, !currentSession.isActive else { return }
        
        currentSession.isActive = true
        currentSession.isPaused = false
        currentSession.startTime = Date()
        
        sessionStartTime = Date()
        questionStartTime = Date()
        
        // Initialize remaining time for the first question
        if let firstQuestion = currentSession.currentQuestion {
            currentRemainingTime = firstQuestion.allocatedTime
        }
        
        // Log the start state
        logStateChange(state: .start, for: currentSession.currentQuestionIndex)
        
        session = currentSession
        startTimer()
    }
    
    func pauseSession() {
        guard var currentSession = session, currentSession.isActive, !currentSession.isPaused else { return }
        
        currentSession.isPaused = true
        
        // Update time before pausing
        updateCurrentQuestionTime()
        
        // Log the pause state
        logStateChange(state: .pause, for: currentSession.currentQuestionIndex)
        
        session = currentSession
        stopTimer()
    }
    
    func resumeSession() {
        guard var currentSession = session, currentSession.isActive, currentSession.isPaused else { return }
        
        currentSession.isPaused = false
        
        // Reset question start time for accurate tracking
        questionStartTime = Date()
        currentElapsedTime = 0
        
        // Log the resume state
        logStateChange(state: .resume, for: currentSession.currentQuestionIndex)
        
        session = currentSession
        startTimer()
    }
    
    func takeBreak() {
        guard var currentSession = session, currentSession.isActive, !currentSession.isOnBreak else { return }
        
        currentSession.isOnBreak = true
        
        // Store the current elapsed time before break
        // We DON'T call updateCurrentQuestionTime() because we want to preserve
        // the elapsed time and continue from where we left off after the break
        
        // Store break start time
        breakStartTime = Date()
        
        // Log the break state
        logStateChange(state: .break, for: currentSession.currentQuestionIndex)
        
        session = currentSession
        // Continue timer during break to track total time
        // The timer stays active but won't add to question time
    }
    
    func resumeFromBreak() {
        guard var currentSession = session, currentSession.isActive, currentSession.isOnBreak else { return }
        
        currentSession.isOnBreak = false
        
        // Calculate break duration and add to break time
        if let breakStart = breakStartTime {
            let breakDuration = Date().timeIntervalSince(breakStart)
            currentSession.breakTimeSpent += breakDuration
            
            // Adjust the questionStartTime to account for the break
            // This ensures the elapsed time calculation continues from where it left off
            if let currentQuestionStart = questionStartTime {
                questionStartTime = currentQuestionStart.addingTimeInterval(breakDuration)
            }
        }
        
        // Clear break start time
        breakStartTime = nil
        
        // Log the resume from break state
        logStateChange(state: .resumeFromBreak, for: currentSession.currentQuestionIndex)
        
        session = currentSession
        // Timer is already running and will continue tracking from where it left off
    }
    
    func finishSession() {
        guard var currentSession = session, currentSession.isActive else { return }
        
        // Update final question time before finishing
        updateCurrentQuestionTime()
        
        // Force one final update to ensure all times are saved
        if let finalSession = session {
            currentSession = finalSession
        }
        
        currentSession.isActive = false
        currentSession.isPaused = false
        currentSession.endTime = Date()
        
        // Log the finish state
        logStateChange(state: .finish, for: currentSession.currentQuestionIndex)
        
        // Debug: Print final question times
        print("DEBUG: Session finished. Question times:")
        for question in currentSession.questions {
            print("  Q\(question.number): \(question.timeSpent)s")
        }
        
        session = currentSession
        stopTimer()
    }
    
    // MARK: - Question Navigation
    
    func nextQuestion() {
        guard var currentSession = session,
              currentSession.isActive,
              !currentSession.isPaused,
              currentSession.currentQuestionIndex < currentSession.questions.count - 1 else { return }
        
        print("DEBUG: Moving from Q\(currentSession.currentQuestionIndex + 1) to Q\(currentSession.currentQuestionIndex + 2)")
        
        // Update current question time
        updateCurrentQuestionTime()
        
        // Log question switch for current question
        logStateChange(state: .questionSwitch, for: currentSession.currentQuestionIndex)
        
        // Move to next question
        currentSession.currentQuestionIndex += 1
        
        // Reset question timer
        questionStartTime = Date()
        currentElapsedTime = 0
        
        // Update remaining time for new question
        if let question = currentSession.currentQuestion {
            currentRemainingTime = question.remainingTime
        }
        
        // Log start for new question
        logStateChange(state: .start, for: currentSession.currentQuestionIndex)
        
        session = currentSession
    }
    
    func previousQuestion() {
        guard var currentSession = session,
              currentSession.isActive,
              !currentSession.isPaused,
              currentSession.currentQuestionIndex > 0 else { return }
        
        // Update current question time
        updateCurrentQuestionTime()
        
        // Log question switch for current question
        logStateChange(state: .questionSwitch, for: currentSession.currentQuestionIndex)
        
        // Move to previous question
        currentSession.currentQuestionIndex -= 1
        
        // Reset question timer
        questionStartTime = Date()
        currentElapsedTime = 0
        
        // Update remaining time for new question
        if let question = currentSession.currentQuestion {
            currentRemainingTime = question.remainingTime
        }
        
        // Log start for new question
        logStateChange(state: .start, for: currentSession.currentQuestionIndex)
        
        session = currentSession
    }
    
    func jumpToQuestion(_ index: Int) {
        guard var currentSession = session,
              currentSession.isActive,
              !currentSession.isPaused,
              index >= 0,
              index < currentSession.questions.count,
              index != currentSession.currentQuestionIndex else { return }
        
        // Update current question time
        updateCurrentQuestionTime()
        
        // Log question switch for current question
        logStateChange(state: .questionSwitch, for: currentSession.currentQuestionIndex)
        
        // Jump to specified question
        currentSession.currentQuestionIndex = index
        
        // Reset question timer
        questionStartTime = Date()
        currentElapsedTime = 0
        
        // Update remaining time for new question
        if let question = currentSession.currentQuestion {
            currentRemainingTime = question.remainingTime
        }
        
        // Log start for new question
        logStateChange(state: .start, for: currentSession.currentQuestionIndex)
        
        session = currentSession
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTimers()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTimers() {
        guard let sessionStart = sessionStartTime,
              var currentSession = session else { return }
        
        // Always update total time from session start (includes breaks)
        currentSession.totalTimeSpent = Date().timeIntervalSince(sessionStart)
        
        // Only update question time if not on break
        if !currentSession.isOnBreak, let questionStart = questionStartTime {
            let elapsed = Date().timeIntervalSince(questionStart)
            currentElapsedTime = elapsed
            
            // Calculate remaining time for current question
            if let currentQuestion = currentSession.currentQuestion {
                let questionTimeSpent = currentQuestion.timeSpent + currentElapsedTime
                currentRemainingTime = currentQuestion.allocatedTime - questionTimeSpent
            }
        }
        
        // Check for time alerts
        checkTimeAlerts(currentSession: currentSession)
        
        session = currentSession
    }
    
    // MARK: - Sound Alert System
    
    private func checkTimeAlerts(currentSession: ExamSession) {
        let remainingTime = currentSession.totalRemainingTime
        
        // 5 minutes warning (300 seconds)
        if !fiveMinuteAlertTriggered && remainingTime <= 300 && remainingTime > 0 {
            fiveMinuteAlertTriggered = true
            playWarningSound()
        }
        
        // Time up alert (when time runs out)
        if !timeUpAlertTriggered && remainingTime <= 0 {
            timeUpAlertTriggered = true
            playTimeUpSound()
        }
    }
    
    private func playWarningSound() {
        // Use user-selected warning sound
        settings.fiveMinuteWarningSound.play()
    }
    
    private func playTimeUpSound() {
        // Use user-selected time up sound
        settings.timeUpSound.play()
    }
    
    // MARK: - Computed Properties for Display
    
    /// Formatted elapsed time for the current question with milliseconds (stopwatch counting up)
    var formattedCurrentElapsedTime: String {
        guard let currentQuestion = session?.currentQuestion else {
            return "00:00.00"
        }
        
        let totalElapsed = currentQuestion.timeSpent + currentElapsedTime
        let minutes = Int(totalElapsed) / 60
        let seconds = Int(totalElapsed) % 60
        let milliseconds = Int((totalElapsed.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    /// Formatted elapsed time with microseconds precision for the current question
    var formattedCurrentElapsedTimeWithMicroseconds: String {
        guard let currentQuestion = session?.currentQuestion else {
            return "00:00.000000"
        }
        
        let totalElapsed = currentQuestion.timeSpent + currentElapsedTime
        let minutes = Int(totalElapsed) / 60
        let seconds = Int(totalElapsed) % 60
        let microseconds = Int((totalElapsed.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        return String(format: "%02d:%02d.%06d", minutes, seconds, microseconds)
    }
    
    /// Formatted remaining time for the current question (shows negative if overtime)
    var formattedCurrentRemainingTime: String {
        let time = abs(currentRemainingTime)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let sign = currentRemainingTime < 0 ? "-" : ""
        return String(format: "%@%02d:%02d", sign, minutes, seconds)
    }
    
    /// Returns true if the current question is in overtime
    var isCurrentQuestionOvertime: Bool {
        return currentRemainingTime < 0
    }
    
    private func updateCurrentQuestionTime() {
        guard let questionStart = questionStartTime,
              var currentSession = session else { return }
        
        // Don't update time if we're on break
        guard !currentSession.isOnBreak else { return }
        
        let elapsed = Date().timeIntervalSince(questionStart)
        let index = currentSession.currentQuestionIndex
        
        // Only add elapsed time if it's positive
        if elapsed > 0 {
            currentSession.questions[index].timeSpent += elapsed
            print("DEBUG: Updated Q\(currentSession.questions[index].number) time: +\(elapsed)s, total: \(currentSession.questions[index].timeSpent)s")
            
            // Update the session property to trigger the @Published update
            session = currentSession
            
            // Reset the question start time to now to avoid double-counting
            questionStartTime = Date()
            // Reset current elapsed time
            currentElapsedTime = 0
        }
    }
    
    private func logStateChange(state: SessionState, for questionIndex: Int) {
        guard var currentSession = session else { return }
        
        let log = StateChangeLog(state: state, questionNumber: currentSession.questions[questionIndex].number)
        currentSession.questions[questionIndex].stateChanges.append(log)
        
        session = currentSession
    }
    
    // MARK: - Cleanup
    
    deinit {
        timer?.invalidate()
    }
}
