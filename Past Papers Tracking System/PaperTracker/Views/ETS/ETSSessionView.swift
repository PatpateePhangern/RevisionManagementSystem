import SwiftUI
import CoreData

/// Full-screen exam simulation viewport.
///
/// Flow:
///   1. If the paper has no QuestionStructureMO entries → ETSQuestionSetupSheet.
///   2. User is prompted for exam duration.
///   3. Session runs: left sidebar (searchable questions) + right panel (timers / marks).
///   4. On complete → ETSPostSessionView sheet.
struct ETSSessionView: View {

    let paper:   PaperMO
    let attempt: AttemptMO

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss)              private var dismiss

    @EnvironmentObject private var appSettings: AppSettings

    // MARK: - Engine

    @State private var engine = ETSTimerEngine()

    // MARK: - Setup phase state

    @State private var questions:          [QuestionStructureMO] = []
    @State private var showQuestionSetup:  Bool = false
    @State private var showEditQuestions:  Bool = false
    @State private var durationString:     String = ""
    @State private var durationError:      String?
    @State private var setupComplete:      Bool = false

    // MARK: - Session UI state

    @State private var searchText:         String = ""
    @FocusState private var searchFocused: Bool
    @State private var showPostSession:    Bool = false

    // MARK: - Body

    var body: some View {
        Group {
            if !setupComplete {
                setupView
            } else if engine.sessionState == .idle {
                readyView
            } else {
                sessionView
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { loadQuestions() }
        .sheet(isPresented: $showQuestionSetup) {
            ETSQuestionSetupSheet(paper: paper) { saved in
                questions = saved
                showQuestionSetup = false
            }
            .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showEditQuestions) {
            ETSQuestionSetupSheet(paper: paper) { saved in
                questions = saved
                showEditQuestions = false
            }
            .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showPostSession) {
            ETSPostSessionView(engine: engine, attempt: attempt, paper: paper)
                .environment(\.managedObjectContext, context)
                .onDisappear { dismiss() }
        }
    }

    // MARK: - Setup view

    private var setupView: some View {
        VStack(spacing: 28) {
            // Icon + title
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "timer")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                Text("Set Exam Duration")
                    .font(.system(size: 20, weight: .bold))
                Text((paper.rawSeriesName ?? "").capitalized)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Duration field
            VStack(alignment: .leading, spacing: 6) {
                Text("Duration")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                TextField("e.g. 1h 30m or 90m", text: $durationString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: 220)
                    .onSubmit { confirmDuration() }
                if let err = durationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            // Buttons
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(GlassPillButtonStyle())
                    .glassEffect(in: Capsule())

                Button("Continue") { confirmDuration() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(BlueGlassButtonStyle())
                    .glassEffect(in: Capsule())
                    .disabled(durationString.isEmpty)
            }

            // Questions status
            HStack(spacing: 10) {
                if questions.isEmpty {
                    Label("No questions defined", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("\(questions.count) question\(questions.count == 1 ? "" : "s") loaded",
                          systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Edit Questions") { showEditQuestions = true }
                    .font(.caption)
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(48)
    }

    // MARK: - Ready view

    private var readyView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Ready to Start")
                    .font(.system(size: 28, weight: .bold))
                Text("\(questions.count) questions  ·  \(DurationParser.format(engine.totalAllottedSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Press ⌘S to begin")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glassEffect(in: Capsule())

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(GlassPillButtonStyle())
                    .glassEffect(in: Capsule())

                Button("Start Exam") {
                    engine.startSession()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        searchFocused = true
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(BlueGlassButtonStyle())
                .glassEffect(in: Capsule())
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main session view

    private var sessionView: some View {
        VStack(spacing: 0) {
            breakBanner

            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 240)

                Divider()

                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Keyboard shortcuts
        .background(
            Group {
                Button("") { engine.nextQuestion() }
                    .keyboardShortcut(.rightArrow, modifiers: .command).opacity(0)
                Button("") { engine.previousQuestion() }
                    .keyboardShortcut(.leftArrow,  modifiers: .command).opacity(0)
                Button("") { engine.togglePause() }
                    .keyboardShortcut("p", modifiers: .command).opacity(0)
                Button("") { engine.startBreakA() }
                    .keyboardShortcut("b", modifiers: .command).opacity(0)
                Button("") { engine.startBreakNA() }
                    .keyboardShortcut("b", modifiers: [.command, .shift]).opacity(0)
                Button("") { handleComplete() }
                    .keyboardShortcut(.return, modifiers: .command).opacity(0)
            }
        )
        // Session-end: play alarm and show post-session
        .onChange(of: engine.sessionState) { _, new in
            if new == .complete {
                appSettings.timeUpSound.play()
                MenuBarTimerController.shared.hide()
                showPostSession = true
            }
        }
        // Over-target notification
        .onChange(of: engine.justCrossedTarget) { _, fired in
            if fired { appSettings.etsOverTargetSound.play() }
        }
        // Menu bar: show on first tick, update each second
        .onAppear {
            MenuBarTimerController.shared.show()
        }
        .onDisappear {
            MenuBarTimerController.shared.hide()
        }
        .onChange(of: engine.globalCountdownSeconds) { _, secs in
            MenuBarTimerController.shared.update(
                countdown:  secs,
                isWarning:  secs < 300
            )
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Jump to question…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit { jumpToFirstFilteredQuestion() }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.background.secondary)

            Divider()

            // Question list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredQuestions, id: \.id) { q in
                        let idx = questions.firstIndex(where: { $0.id == q.id }) ?? 0
                        sidebarRow(q: q, index: idx)
                        Divider().opacity(0.5)
                    }
                }
            }

            Divider()

            // Session controls
            VStack(spacing: 8) {
                if engine.sessionState == .running {
                    HStack(spacing: 6) {
                        Button {
                            engine.startBreakA()
                        } label: {
                            Label("Break", systemImage: "figure.walk")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                        .buttonStyle(BlueGlassButtonStyle())
                        .glassEffect(in: Capsule())
                        .help("Accountable break — global timer still runs (⌘B)")

                        Button {
                            engine.startBreakNA()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                        .buttonStyle(BlueGlassButtonStyle())
                        .glassEffect(in: Capsule())
                        .help("Non-accountable pause — all timers stop (⌘⇧B)")
                    }
                } else if engine.sessionState == .breakA || engine.sessionState == .breakNA {
                    Button {
                        engine.endBreak()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .glassEffect(in: Capsule())
                    .keyboardShortcut(.return, modifiers: .command)
                }

                Button("Complete Exam") { handleComplete() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .padding(.vertical, 2)
                    .disabled(engine.sessionState != .running)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.background.tertiary)
    }

    @ViewBuilder
    private func sidebarRow(q: QuestionStructureMO, index: Int) -> some View {
        let isActive  = index == engine.currentQuestionIndex && engine.sessionState == .running
        let rawLabel  = q.questionLabel ?? "Q\(index + 1)"
        let label     = ETSTimerEngine.stripPageRange(rawLabel)
        let maxMarks  = q.maxMarks

        Button {
            engine.jumpToQuestion(index)
            searchText = ""
        } label: {
            HStack(spacing: 10) {
                // Active indicator dot
                Circle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 6, height: 6)
                    .animation(.smooth(duration: 0.2), value: isActive)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13)
                            .weight(isActive ? .bold : .regular))
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                        .animation(.smooth(duration: 0.2), value: isActive)
                    Text("\(maxMarks) marks")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isActive {
                    Color.accentColor.opacity(0.08)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.2), value: isActive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        let onBreak = engine.sessionState == .breakA || engine.sessionState == .breakNA

        return VStack(spacing: 0) {
            // Global countdown bar
            if !onBreak {
                HStack(spacing: 10) {
                    Label("Remaining", systemImage: "hourglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(engine.globalCountdownSeconds))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(engine.globalCountdownSeconds < 300 ? .red : .primary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth(duration: 0.3), value: engine.globalCountdownSeconds)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.background.secondary)
                Divider()
            }

            Spacer()

            // Current question display
            VStack(spacing: 20) {
                // Question label — large, glass-backed
                Text(engine.currentQuestionLabel)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .animation(.smooth(duration: 0.25), value: engine.currentQuestionLabel)
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))

                Text("\(engine.currentQuestionMaxMarks) marks")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                // Timer pair
                HStack(spacing: 36) {
                    // Time spent (stopwatch)
                    VStack(spacing: 4) {
                        Text(formatTime(engine.questionStopwatchSeconds))
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(engine.isOverTarget ? Color(nsColor: .systemRed) : .primary)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.3), value: engine.questionStopwatchSeconds)
                        Text("time spent")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Target time
                    if engine.targetSecondsPerMark > 0 {
                        VStack(spacing: 4) {
                            Text(formatTime(Int64(engine.targetSecondsForCurrentQuestion)))
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(engine.isOverTarget
                                    ? Color(nsColor: .systemRed).opacity(0.7)
                                    : .secondary)
                                .contentTransition(.numericText(countsDown: true))
                                .animation(.smooth(duration: 0.3), value: engine.targetSecondsForCurrentQuestion)
                            Text("target")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(24)
                .glassEffect(in: RoundedRectangle(cornerRadius: 20))
            }

            Spacer()

            Divider()

            // Navigation bar
            HStack(spacing: 0) {
                Button {
                    engine.previousQuestion()
                } label: {
                    Label("Previous", systemImage: "arrow.left")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .disabled(engine.currentQuestionIndex == 0 || engine.sessionState != .running)

                Spacer()

                Text("\(engine.currentQuestionIndex + 1) / \(questions.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: engine.currentQuestionIndex)

                Spacer()

                Button {
                    engine.nextQuestion()
                } label: {
                    Label("Next", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .disabled(engine.currentQuestionIndex >= questions.count - 1
                          || engine.sessionState != .running)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.background.secondary)
        }
    }

    // MARK: - Break banner

    @ViewBuilder
    private var breakBanner: some View {
        if engine.sessionState == .breakA || engine.sessionState == .breakNA {
            let isNA = engine.sessionState == .breakNA
            HStack(spacing: 14) {
                Image(systemName: isNA ? "pause.circle.fill" : "figure.walk.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isNA ? Color.orange : Color.blue)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isNA ? "Paused — All Timers Frozen"
                              : "Accountable Break — Global Timer Running")
                        .font(.system(size: 13, weight: .semibold))
                    Text(formatTime(engine.breakCurrentDurationSeconds))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.3), value: engine.breakCurrentDurationSeconds)
                }

                Spacer()

                if !isNA {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatTime(engine.globalCountdownSeconds))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(engine.globalCountdownSeconds < 300 ? .red : .primary)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.smooth(duration: 0.3), value: engine.globalCountdownSeconds)
                        Text("remaining")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    engine.endBreak()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .glassEffect(in: Capsule())
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isNA ? Color.orange.opacity(0.10) : Color.blue.opacity(0.10))
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private func loadQuestions() {
        guard let pid = paper.id else { return }
        var loaded = QuestionStructureMO.fetch(paperID: pid, in: context)
        // Keep only question-paper entries; deduplicate by stripped label
        // so that old data where source == nil for both QP and MS doesn't
        // produce duplicate sidebar rows.
        loaded = loaded.filter { ($0.source ?? "questionPaper") == "questionPaper" }
        var seen = Set<String>()
        loaded = loaded.filter { q in
            let key = ETSTimerEngine.stripPageRange(q.questionLabel ?? "")
            return seen.insert(key).inserted
        }
        if loaded.isEmpty {
            showQuestionSetup = true
        } else {
            questions = loaded
        }
    }

    private func confirmDuration() {
        guard let secs = DurationParser.parse(durationString), secs > 0 else {
            durationError = "Enter a valid duration, e.g. 1h 30m or 90m."
            return
        }
        durationError = nil
        engine.configure(questions: questions, totalSeconds: secs)
        setupComplete = true
    }

    private var filteredQuestions: [QuestionStructureMO] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return questions }
        return questions.filter {
            let label = ETSTimerEngine.stripPageRange($0.questionLabel ?? "")
            return label.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func jumpToFirstFilteredQuestion() {
        guard let first = filteredQuestions.first,
              let idx = questions.firstIndex(where: { $0.id == first.id }) else { return }
        engine.jumpToQuestion(idx)
        searchText    = ""
        searchFocused = false
    }

    private func handleComplete() {
        guard engine.sessionState == .running
           || engine.sessionState == .breakA
           || engine.sessionState == .breakNA else { return }
        engine.completeExam()
    }

    private func formatTime(_ totalSeconds: Int64) -> String {
        let s = max(totalSeconds, 0)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}
