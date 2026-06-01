import Foundation
import CoreData
import Observation

// MARK: - Session state

enum ETSSessionState {
    /// No session has started yet.
    case idle
    /// Timer running; user is on a question.
    case running
    /// Accountable break — global countdown keeps ticking; question stopwatch paused.
    case breakA
    /// Non-accountable break — all timers paused.
    case breakNA
    /// Exam finished (time expired or user chose Complete).
    case complete
}

// MARK: - Engine

/// Thread-safe exam timer managing two simultaneous counters:
///   `globalCountdownSeconds` — total remaining exam time (counts down).
///   `questionStopwatchSeconds` — time spent on the current question (counts up).
///
/// Keyboard shortcut mappings (wired in SwiftUI via `.keyboardShortcut`):
///   Cmd+S      → startSession()
///   Cmd+→      → nextQuestion()
///   Cmd+←      → previousQuestion()
///   Cmd+P      → togglePause()  (breakNA toggle)
///   Cmd+B      → startBreakA()
///   Cmd+Shift+B → startBreakNA()
///   Cmd+Return → completeExam()
@MainActor
@Observable
final class ETSTimerEngine {

    // MARK: - Observed state

    private(set) var sessionState: ETSSessionState = .idle
    /// Remaining exam seconds (counts down from totalAllottedSeconds).
    private(set) var globalCountdownSeconds: Int64 = 0
    /// Seconds spent on the current question slot (resets on navigation).
    private(set) var questionStopwatchSeconds: Int64 = 0
    /// Seconds elapsed in the active break (resets on endBreak).
    private(set) var breakCurrentDurationSeconds: Int64 = 0
    /// Zero-based index of the question the user is currently on.
    private(set) var currentQuestionIndex: Int = 0
    /// Pulses true for one tick the moment a question first crosses its target.
    /// Observe with `.onChange(of: engine.justCrossedTarget)` to play a sound.
    private(set) var justCrossedTarget: Bool = false

    // MARK: - Configuration (set before startSession)

    /// Ordered question definitions loaded from QuestionStructureMO.
    var questions: [QuestionStructureMO] = []
    /// Total exam duration in seconds (e.g. 5400 = 1 h 30 m).
    var totalAllottedSeconds: Int64 = 0
    /// Per-question marks entered by the user (indexed by questionIndex).
    var marksEarned: [Double] = []

    // MARK: - Private

    private struct PendingEvent {
        var sequenceIndex: Int
        var eventType: String       // "QUESTION_SPENT" | "BREAK_A" | "BREAK_NA"
        var label: String
        var durationSeconds: Int64
        var marksEarned: Double
    }

    private var tickTask: Task<Void, Never>?
    private var pendingEvents: [PendingEvent] = []
    private var sequenceCounter: Int = 0
    /// Prevents repeated over-target notifications for the same question.
    private var hasAlertedOverTarget: Bool = false

    // MARK: - Setup

    /// Initialises (or resets) engine state for a new exam session.
    func configure(questions: [QuestionStructureMO], totalSeconds: Int64) {
        tickTask?.cancel()
        tickTask = nil
        self.questions             = questions
        self.totalAllottedSeconds  = totalSeconds
        self.globalCountdownSeconds = totalSeconds
        self.questionStopwatchSeconds = 0
        self.breakCurrentDurationSeconds = 0
        self.currentQuestionIndex  = 0
        self.pendingEvents         = []
        self.sequenceCounter       = 0
        self.marksEarned           = Array(repeating: 0.0, count: questions.count)
        self.sessionState          = .idle
    }

    // MARK: - Session lifecycle

    /// Starts the session; transitions from `.idle` → `.running`.
    func startSession() {
        guard sessionState == .idle, !questions.isEmpty else { return }
        sessionState = .running
        startTickLoop()
    }

    // MARK: - Navigation

    /// Records current question spent and advances to the next one.
    func nextQuestion() {
        guard sessionState == .running,
              currentQuestionIndex < questions.count - 1 else { return }
        recordQuestionSpent()
        currentQuestionIndex += 1
        questionStopwatchSeconds = 0
        hasAlertedOverTarget = false
    }

    /// Records current question spent and moves back one slot.
    func previousQuestion() {
        guard sessionState == .running, currentQuestionIndex > 0 else { return }
        recordQuestionSpent()
        currentQuestionIndex -= 1
        questionStopwatchSeconds = 0
        hasAlertedOverTarget = false
    }

    /// Records current question spent and jumps to an arbitrary index.
    func jumpToQuestion(_ index: Int) {
        guard sessionState == .running,
              (0 ..< questions.count).contains(index),
              index != currentQuestionIndex else { return }
        recordQuestionSpent()
        currentQuestionIndex = index
        questionStopwatchSeconds = 0
        hasAlertedOverTarget = false
    }

    // MARK: - Breaks

    /// Starts an accountable break (global timer still runs).
    func startBreakA() {
        guard sessionState == .running else { return }
        recordQuestionSpent()
        breakCurrentDurationSeconds = 0
        sessionState = .breakA
    }

    /// Starts a non-accountable break (all timers paused).
    func startBreakNA() {
        guard sessionState == .running else { return }
        recordQuestionSpent()
        breakCurrentDurationSeconds = 0
        sessionState = .breakNA
    }

    /// Ends the current break and resumes the question timer.
    func endBreak() {
        guard sessionState == .breakA || sessionState == .breakNA else { return }
        let eventType = sessionState == .breakA ? "BREAK_A" : "BREAK_NA"
        let label = nextBreakLabel()
        pendingEvents.append(PendingEvent(
            sequenceIndex:  sequenceCounter,
            eventType:      eventType,
            label:          label,
            durationSeconds: breakCurrentDurationSeconds,
            marksEarned:    0
        ))
        sequenceCounter += 1
        breakCurrentDurationSeconds = 0
        questionStopwatchSeconds = 0
        sessionState = .running
    }

    /// Convenience toggle: if running → startBreakNA; if breakNA → endBreak.
    func togglePause() {
        switch sessionState {
        case .running:  startBreakNA()
        case .breakNA:  endBreak()
        default:        break
        }
    }

    // MARK: - Complete

    /// Finalises the session. Flushes any open event (question or break) then
    /// stops the ticker. Transitions to `.complete`.
    func completeExam() {
        guard sessionState == .running
           || sessionState == .breakA
           || sessionState == .breakNA else { return }

        switch sessionState {
        case .running:
            recordQuestionSpent()
        case .breakA, .breakNA:
            // Close out the pending break entry.
            let eventType = sessionState == .breakA ? "BREAK_A" : "BREAK_NA"
            let label = nextBreakLabel()
            pendingEvents.append(PendingEvent(
                sequenceIndex:  sequenceCounter,
                eventType:      eventType,
                label:          label,
                durationSeconds: breakCurrentDurationSeconds,
                marksEarned:    0
            ))
            sequenceCounter += 1
        default:
            break
        }

        tickTask?.cancel()
        tickTask = nil
        sessionState = .complete
    }

    // MARK: - Persist

    /// Writes all accumulated PendingEvent entries as ETSEventLogMO objects,
    /// updates attempt.durationInSeconds and attempt.totalScore, then saves.
    func saveEventLog(to attempt: AttemptMO, in context: NSManagedObjectContext) {
        // Guard against double-save: if the attempt already has event logs,
        // only update the scalar fields (don't insert duplicate log entries).
        let alreadySaved = !((attempt.eventLogs as? Set<ETSEventLogMO>) ?? []).isEmpty
        if !alreadySaved {
            for event in pendingEvents {
                ETSEventLogMO.insert(
                    sequenceIndex:   event.sequenceIndex,
                    eventType:       event.eventType,
                    label:           event.label,
                    durationSeconds: event.durationSeconds,
                    marksEarned:     event.marksEarned,
                    attempt:         attempt,
                    in:              context
                )
            }
        }
        let elapsed = totalAllottedSeconds - globalCountdownSeconds
        attempt.durationInSeconds = max(elapsed, 0)
        attempt.totalScore = pendingEvents
            .filter { $0.eventType == "QUESTION_SPENT" }
            .reduce(0) { $0 + $1.marksEarned }
        try? context.save()
    }

    // MARK: - Derived efficiency properties

    /// Sum of maxMarks across all questions.
    var totalMaxMarks: Int {
        questions.reduce(0) { $0 + Int($1.maxMarks) }
    }

    /// Ideal seconds a student should spend per mark.
    var targetSecondsPerMark: Double {
        guard totalMaxMarks > 0 else { return 0 }
        return Double(totalAllottedSeconds) / Double(totalMaxMarks)
    }

    /// Target duration for the current question based on its max marks.
    var targetSecondsForCurrentQuestion: Double {
        Double(currentQuestionMaxMarks) * targetSecondsPerMark
    }

    /// `true` when the user has spent more than their allotted time on this question.
    var isOverTarget: Bool {
        targetSecondsForCurrentQuestion > 0
            && Double(questionStopwatchSeconds) > targetSecondsForCurrentQuestion
    }

    var currentQuestionLabel: String {
        guard questions.indices.contains(currentQuestionIndex) else { return "" }
        let raw = questions[currentQuestionIndex].questionLabel ?? "Q\(currentQuestionIndex + 1)"
        return Self.stripPageRange(raw)
    }

    /// Strips `[p.X]` / `[pp.X-Y]` annotations from a question label.
    static func stripPageRange(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s*\[p+\.\d[^\]]*\]"#, with: "",
                                 options: .regularExpression)
           .trimmingCharacters(in: .whitespaces)
    }

    var currentQuestionMaxMarks: Int16 {
        guard questions.indices.contains(currentQuestionIndex) else { return 0 }
        return questions[currentQuestionIndex].maxMarks
    }

    // MARK: - Private helpers

    private func startTickLoop() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break   // cancelled
                }
                guard let self, !Task.isCancelled else { break }
                self.tick()
            }
        }
    }

    private func tick() {
        switch sessionState {
        case .running:
            if globalCountdownSeconds > 0 { globalCountdownSeconds -= 1 }
            questionStopwatchSeconds += 1

            // Fire over-target notification once per question
            let target = targetSecondsForCurrentQuestion
            if !hasAlertedOverTarget && target > 0
                && Double(questionStopwatchSeconds) >= target {
                hasAlertedOverTarget = true
                justCrossedTarget = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.justCrossedTarget = false
                }
            }

            if globalCountdownSeconds == 0 { completeExam() }

        case .breakA:
            if globalCountdownSeconds > 0 { globalCountdownSeconds -= 1 }
            breakCurrentDurationSeconds += 1
            if globalCountdownSeconds == 0 { completeExam() }

        case .breakNA:
            // All timers frozen.
            break

        case .idle, .complete:
            break
        }
    }

    private func recordQuestionSpent() {
        guard questions.indices.contains(currentQuestionIndex) else { return }
        let q = questions[currentQuestionIndex]
        let label = q.questionLabel ?? "Q\(currentQuestionIndex + 1)"
        let marks = marksEarned.indices.contains(currentQuestionIndex)
            ? marksEarned[currentQuestionIndex]
            : 0.0
        pendingEvents.append(PendingEvent(
            sequenceIndex:  sequenceCounter,
            eventType:      "QUESTION_SPENT",
            label:          label,
            durationSeconds: questionStopwatchSeconds,
            marksEarned:    marks
        ))
        sequenceCounter += 1
    }

    private func nextBreakLabel() -> String {
        let count = pendingEvents.filter {
            $0.eventType == "BREAK_A" || $0.eventType == "BREAK_NA"
        }.count + 1
        return "Break \(count)"
    }
}
