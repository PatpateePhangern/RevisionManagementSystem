//
//  DataFlowDiagram.swift
//  Exam Timing System - Architecture Documentation
//
//  Created by Patpatee Phangern on 25/4/2569 BE.
//

/*
 
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                    EXAM TIMING SYSTEM - DATA FLOW                          ║
 ╚════════════════════════════════════════════════════════════════════════════╝
 
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                              APP ENTRY POINT                                 │
 │                                                                              │
 │  Exam_Timing_SystemApp.swift                                                │
 │  ├─ WindowGroup                                                             │
 │  │  └─ ContentView (root coordinator)                                       │
 │  └─ Commands (keyboard shortcuts in menu bar)                               │
 └─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                            MAIN COORDINATOR                                  │
 │                                                                              │
 │  ContentView.swift                                                          │
 │  ├─ @StateObject timingEngine: TimingEngine                                │
 │  ├─ @State appState: AppState (.welcome / .activeSession / .performanceLog)│
 │  ├─ @State showSessionSetup: Bool                                          │
 │  └─ @State completedSession: ExamSession?                                  │
 │                                                                              │
 │  State Machine:                                                             │
 │  .welcome ──[New Session]──> SessionSetupView ──[Create]──> .activeSession │
 │  .activeSession ──[Finish]──> .performanceLog ──[Close]──> .welcome        │
 └─────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
 ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
 │  SessionSetupView    │  │  ActiveSessionView   │  │  PerformanceLogView  │
 │                      │  │                      │  │                      │
 │  • Exam title input  │  │  • Timer display     │  │  • Statistics        │
 │  • Question count    │  │  • Question sidebar  │  │  • Performance table │
 │  • Mark allocation   │  │  • Controls          │  │  • State log         │
 │  • Validation        │  │  • Shortcuts         │  │  • Export PDF        │
 └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                              TIMING ENGINE                                   │
 │                                                                              │
 │  TimingEngine.swift (@MainActor, ObservableObject)                          │
 │                                                                              │
 │  @Published Properties:                                                     │
 │  ├─ session: ExamSession?           (entire session state)                 │
 │  └─ currentElapsedTime: TimeInterval (live timer for current question)     │
 │                                                                              │
 │  Private State:                                                             │
 │  ├─ timer: Timer?                   (0.1s update interval)                 │
 │  ├─ questionStartTime: Date?        (when current question started)        │
 │  └─ sessionStartTime: Date?         (when entire session started)          │
 │                                                                              │
 │  Public Methods:                                                            │
 │  ├─ createSession(...)              (initialize new session)               │
 │  ├─ startSession()                  (begin timing)                         │
 │  ├─ pauseSession()                  (stop timer, log pause)                │
 │  ├─ resumeSession()                 (restart timer, log resume)            │
 │  ├─ nextQuestion()                  (switch to next, log change)           │
 │  ├─ previousQuestion()              (switch to previous, log change)       │
 │  ├─ jumpToQuestion(index)           (jump to specific question)            │
 │  └─ finishSession()                 (end session, log finish)              │
 │                                                                              │
 │  Private Methods:                                                           │
 │  ├─ startTimer()                    (begin 0.1s updates)                   │
 │  ├─ stopTimer()                     (halt updates)                         │
 │  ├─ updateTimers()                  (calculate elapsed times)              │
 │  ├─ updateCurrentQuestionTime()     (accumulate time to question)          │
 │  └─ logStateChange(...)             (append to question's state log)       │
 │                                                                              │
 │  Key Guarantees:                                                            │
 │  • No duplicate state log entries (single chronological log)               │
 │  • Time only accumulates when active (pause-aware)                         │
 │  • Question time persists across switches (cumulative)                     │
 │  • All state changes are logged with timestamps                            │
 └─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                              DATA MODELS                                     │
 │                                                                              │
 │  ExamModels.swift                                                           │
 │                                                                              │
 │  SessionState (enum)                                                        │
 │  ├─ .start                                                                  │
 │  ├─ .pause                                                                  │
 │  ├─ .resume                                                                 │
 │  ├─ .questionSwitch                                                         │
 │  └─ .finish                                                                 │
 │                                                                              │
 │  StateChangeLog (struct, Identifiable, Codable)                            │
 │  ├─ id: UUID                                                                │
 │  ├─ timestamp: Date                                                         │
 │  ├─ state: SessionState                                                     │
 │  └─ questionNumber: Int?                                                    │
 │                                                                              │
 │  Question (struct, Identifiable, Codable)                                  │
 │  ├─ id: UUID                                                                │
 │  ├─ number: Int                                                             │
 │  ├─ markAllocation: Int                                                     │
 │  ├─ timeSpent: TimeInterval          (cumulative seconds)                  │
 │  ├─ stateChanges: [StateChangeLog]   (chronological log)                  │
 │  └─ Computed Properties:                                                    │
 │     ├─ formattedTime                 ("MM:SS")                             │
 │     ├─ timePerMark                   (seconds per mark)                    │
 │     └─ formattedTimePerMark          ("XXs/mark")                          │
 │                                                                              │
 │  ExamSession (struct, Identifiable, Codable)                               │
 │  ├─ id: UUID                                                                │
 │  ├─ title: String                                                           │
 │  ├─ createdAt: Date                                                         │
 │  ├─ questions: [Question]                                                   │
 │  ├─ currentQuestionIndex: Int                                               │
 │  ├─ totalTimeSpent: TimeInterval                                            │
 │  ├─ isActive: Bool                                                          │
 │  ├─ isPaused: Bool                                                          │
 │  ├─ startTime: Date?                                                        │
 │  ├─ endTime: Date?                                                          │
 │  └─ Computed Properties:                                                    │
 │     ├─ currentQuestion                                                      │
 │     ├─ formattedTotalTime            ("HH:MM:SS")                          │
 │     ├─ totalMarks                                                           │
 │     └─ averageTimePerMark                                                   │
 └─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                              PDF EXPORT                                      │
 │                                                                              │
 │  PDFExporter.swift                                                          │
 │                                                                              │
 │  static func generateSessionReceipt(for session: ExamSession) -> PDFDocument?│
 │  ├─ Create CGContext with A4 dimensions (595.28 × 841.89 pts)              │
 │  ├─ Draw header (title, subtitle)                                          │
 │  ├─ Draw session info (title, date, duration)                              │
 │  ├─ Draw statistics summary (questions, marks, averages)                   │
 │  ├─ Draw performance table:                                                 │
 │  │  ├─ Table header row                                                     │
 │  │  └─ For each question:                                                   │
 │  │     ├─ Question number                                                   │
 │  │     ├─ Time spent                                                        │
 │  │     ├─ Mark allocation                                                   │
 │  │     ├─ Time per mark                                                     │
 │  │     └─ Efficiency (color-coded)                                         │
 │  ├─ Draw state change log                                                   │
 │  ├─ Draw footer (generated date)                                           │
 │  └─ Return PDFDocument                                                      │
 │                                                                              │
 │  static func saveReceipt(_ pdfDocument: PDFDocument, defaultName: String)  │
 │  └─ Present NSSavePanel with default filename                              │
 └─────────────────────────────────────────────────────────────────────────────┘
 
 
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                         TIMING FLOW DIAGRAM                                 ║
 ╚════════════════════════════════════════════════════════════════════════════╝
 
  Session Start
       ↓
  ┌────────────────┐
  │ startSession() │
  │ • isActive=true│
  │ • Log: Start   │
  │ • Start timer  │
  └────────────────┘
       ↓
  [Timer fires every 0.1s]
       ↓
  ┌──────────────────┐
  │ updateTimers()   │
  │ • currentElapsed │
  │ • totalTime      │
  └──────────────────┘
       ↓
  ┌─────────────────────────────────┐
  │  User Actions (while active):   │
  │                                 │
  │  1. Pause (⌘P)                  │
  │     ↓                           │
  │  pauseSession()                 │
  │  • Update question time         │
  │  • isPaused=true                │
  │  • Log: Pause                   │
  │  • Stop timer                   │
  │     ↓                           │
  │  [User break time...]           │
  │     ↓                           │
  │  resumeSession()                │
  │  • Reset questionStartTime      │
  │  • isPaused=false               │
  │  • Log: Resume                  │
  │  • Start timer                  │
  │                                 │
  │  2. Next Question (⌘→)          │
  │     ↓                           │
  │  nextQuestion()                 │
  │  • Update current question time │
  │  • Log: QuestionSwitch          │
  │  • Increment index              │
  │  • Reset questionStartTime      │
  │  • Log: Start (new question)    │
  │                                 │
  │  3. Jump to Question (click)    │
  │     ↓                           │
  │  jumpToQuestion(index)          │
  │  • Update current question time │
  │  • Log: QuestionSwitch          │
  │  • Set new index                │
  │  • Reset questionStartTime      │
  │  • Log: Start (target question) │
  └─────────────────────────────────┘
       ↓
  ┌────────────────┐
  │ finishSession()│
  │ • Update time  │
  │ • isActive=false│
  │ • Log: Finish  │
  │ • Stop timer   │
  └────────────────┘
       ↓
  Performance Log View
 
 
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                      STATE CHANGE LOGGING PATTERN                          ║
 ╚════════════════════════════════════════════════════════════════════════════╝
 
  Example: User works on Q1, pauses, resumes, switches to Q2
 
  Question 1 State Changes:
  ├─ [09:00:00] Start      (Q1)  ← Session begins
  ├─ [09:05:30] Pause      (Q1)  ← User pauses
  ├─ [09:08:15] Resume     (Q1)  ← User resumes
  └─ [09:12:00] QuestionSwitch (Q1)  ← Switching to Q2
 
  Question 2 State Changes:
  ├─ [09:12:00] Start      (Q2)  ← Q2 begins
  ├─ [09:18:30] Pause      (Q2)  ← User pauses again
  ├─ [09:20:00] Resume     (Q2)  ← Resume
  └─ [09:25:00] Finish     (Q2)  ← Session ends
 
  Time Calculations:
  Q1 Time = (09:05:30 - 09:00:00) + (09:12:00 - 09:08:15)
          = 5:30 + 3:45 = 9:15 (9 minutes 15 seconds)
 
  Q2 Time = (09:18:30 - 09:12:00) + (09:25:00 - 09:20:00)
          = 6:30 + 5:00 = 11:30 (11 minutes 30 seconds)
 
  Total Session Time = 9:15 + 11:30 = 20:45
  (Pause periods NOT included in total)
 
 
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                         KEYBOARD SHORTCUT FLOW                             ║
 ╚════════════════════════════════════════════════════════════════════════════╝
 
  User presses: ⌘→
       ↓
  SwiftUI catches: .keyboardShortcut(.rightArrow, modifiers: .command)
       ↓
  Button action executes: engine.nextQuestion()
       ↓
  TimingEngine processes:
  ├─ Validates (not last question, not paused)
  ├─ Calls updateCurrentQuestionTime()
  ├─ Calls logStateChange(.questionSwitch, for: currentIndex)
  ├─ Increments currentQuestionIndex
  ├─ Resets questionStartTime = Date()
  ├─ Calls logStateChange(.start, for: newIndex)
  └─ Updates @Published session property
       ↓
  SwiftUI receives @Published change
       ↓
  All views observing engine.session automatically re-render:
  ├─ ActiveSessionView updates main timer display
  ├─ Sidebar highlights new active question
  └─ Control bar updates button states
 
  Result: Seamless, reactive UI update with guaranteed state logging
 
 
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                              DESIGN NOTES                                  ║
 ╚════════════════════════════════════════════════════════════════════════════╝
 
  Typography Hierarchy:
  ────────────────────
  72pt  → Main timer display (monospaced, .medium)
  32pt  → Welcome screen title (.semibold)
  22pt  → Modal headers (.semibold)
  18pt  → Important metrics (.medium, monospaced)
  15pt  → Section titles (.semibold)
  13pt  → Body text (.regular), labels (.medium)
  12pt  → Secondary info (.regular)
  11pt  → Tertiary/uppercase labels (.semibold, +tracking)
  10pt  → Small data (.regular, .medium)
  
  Color Semantics:
  ───────────────
  .primary    → Main content text
  .secondary  → Supporting text, labels
  .green      → Active state, high efficiency
  .orange     → Paused state, medium efficiency
  .red        → Low efficiency, alerts
  .gray       → Neutral dividers, backgrounds
  
  Spacing System:
  ──────────────
  4pt   → Tight internal spacing
  8pt   → Standard item spacing
  12pt  → Related group spacing
  16pt  → Section padding
  20pt  → View padding
  24pt  → Major section padding
  32pt  → Large section breaks
  
  
  END OF DATA FLOW DOCUMENTATION
  
 */

// This file is documentation only - no executable code
// It serves as a comprehensive reference for understanding the system architecture
