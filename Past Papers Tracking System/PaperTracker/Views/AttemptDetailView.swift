import SwiftUI
import CoreData

/// Standalone detail window for a single attempt.
/// Opened via double-click in Complete Logs.
///
/// Shows the same content as the right panel — plus per-question time
/// breakdown (spent vs target) for ETS-sourced attempts — all in a
/// dedicated window so nothing is cramped into a sidebar.
struct AttemptDetailView: View {

    let attemptID: UUID

    @Environment(\.managedObjectContext) private var ctx
    @FetchRequest private var results: FetchedResults<AttemptMO>

    // MARK: - Editing state (mirrors CompleteLogsView right panel)

    @State private var reviewText:          String = ""
    @State private var notesText:           String = ""
    @State private var durationEdit:        String = ""
    @State private var questionMarks:       [String: Double] = [:]
    @State private var completionDateTime:  Date = Date()
    @State private var showTimeline:        Bool = false

    // MARK: - Sheet state

    @State private var showGradeCapture: Bool = false
    @State private var showPDFViewer:    Bool = false

    // MARK: - Init

    init(attemptID: UUID) {
        self.attemptID = attemptID
        _results = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", attemptID as CVarArg)
        )
    }

    private var attempt: AttemptMO? { results.first }

    // MARK: - Body

    var body: some View {
        Group {
            if let attempt {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerBand(attempt)
                        Divider()
                        contentSections(attempt)
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .onAppear { syncFromAttempt(attempt) }
            } else {
                Text("Attempt not found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 660, minHeight: 540)
        .sheet(isPresented: $showGradeCapture) {
            if let a = attempt {
                GradeThresholdSheet(attempt: a, isPresented: $showGradeCapture)
                    .environment(\.managedObjectContext, ctx)
            }
        }
        .sheet(isPresented: $showPDFViewer) {
            if let path = attempt?.scannedFilePath {
                PDFViewerSheet(url: URL(filePath: path), isPresented: $showPDFViewer)
            }
        }
    }

    // MARK: - Content sections

    @ViewBuilder
    private func contentSections(_ a: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 20) {

            durationSection(a)
            Divider()

            if isETSSourced(a) {
                etsMarksAndTimeTable(a)
                Divider()
                // Collapsible event timeline
                DisclosureGroup(isExpanded: $showTimeline) {
                    timelineSection(a)
                        .padding(.top, 8)
                } label: {
                    let count = (a.eventLogs as? Set<ETSEventLogMO>)?.count ?? 0
                    Text("Event Timeline (\(count) events)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            } else {
                nonETSScoreRow(a)
            }

            Divider()
            reviewSection
            Divider()
            notesSection

            if a.paperType == "timed" {
                Divider()
                historicalPanel(a)
            }

            if !a.isComplete {
                Divider()
                completionSection(a)
            }

            Divider()
            actionRow(a)
        }
        .padding(20)
    }

    // MARK: - Header band

    private func headerBand(_ a: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Title row ────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.paper?.subject?.name ?? "—")
                        .font(.system(size: 20, weight: .bold))

                    if let norm = a.paper?.normalizedSeries {
                        Text(SeriesNormalizationEngine.displayName(from: norm))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("Attempt \(a.attemptNumber)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        if let pt = a.paperType {
                            Text(pt == "timed" ? "Timed & Graded" : "Practice")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(pt == "timed"
                                            ? Color(nsColor: .systemBlue).opacity(0.15)
                                            : Color(nsColor: .systemGray).opacity(0.2))
                                .foregroundStyle(pt == "timed"
                                                 ? Color(nsColor: .systemBlue)
                                                 : Color(nsColor: .secondaryLabelColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    if a.totalScore > 0 {
                        HStack(spacing: 8) {
                            Text(String(format: "%.0f pts", a.totalScore))
                                .font(.system(size: 13, weight: .semibold))
                            if let grade = a.rawGrade, !grade.isEmpty {
                                Text(grade)
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color(nsColor: .systemBlue).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    if a.durationInSeconds > 0 {
                        Label(DurationParser.format(a.durationInSeconds),
                              systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().padding(.top, 14).padding(.bottom, 10)

            // ── Metadata grid ────────────────────────────────────────────────
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    metaLabel("Barcode Reference")
                    Text(a.barcodeValue ?? "—")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
                GridRow {
                    metaLabel("Exam Series")
                    Text(a.paper?.normalizedSeries.flatMap {
                        SeriesNormalizationEngine.displayName(from: $0)
                    } ?? (a.paper?.rawSeriesName?.capitalized ?? "—"))
                        .font(.system(size: 12))
                }
                GridRow {
                    metaLabel("Subject")
                    Text(a.paper?.subject?.name ?? "—")
                        .font(.system(size: 12))
                }
                GridRow {
                    metaLabel("Printed")
                    Text(a.printTimestamp.map {
                        $0.formatted(.dateTime
                            .day().month(.wide).year()
                            .hour(.twoDigits(amPM: .abbreviated))
                            .minute()
                            .second())
                    } ?? "—")
                        .font(.system(size: 12))
                }
                GridRow {
                    metaLabel("Completed")
                    if let ts = a.completedTimestamp {
                        Text(ts.formatted(.dateTime
                            .day().month(.wide).year()
                            .hour(.twoDigits(amPM: .abbreviated))
                            .minute()
                            .second()))
                            .font(.system(size: 12))
                    } else {
                        Text("Not yet completed")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                    }
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .frame(width: 130, alignment: .leading)
    }

    // MARK: - Duration section

    @ViewBuilder
    private func durationSection(_ a: AttemptMO) -> some View {
        let locked = isETSSourced(a)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Exam Duration")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                if locked {
                    Label("Set by ETS", systemImage: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            TextField("e.g. 1h 30m", text: $durationEdit)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .font(.system(size: 11))
                .disabled(locked)
                .foregroundStyle(locked
                                 ? Color(nsColor: .tertiaryLabelColor)
                                 : Color(nsColor: .labelColor))
        }
    }

    // MARK: - ETS combined marks + time table

    @ViewBuilder
    private func etsMarksAndTimeTable(_ a: AttemptMO) -> some View {
        let questions = (a.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
            .sorted { $0.displayOrder < $1.displayOrder }

        if !questions.isEmpty {
            let totalMaxMarks  = questions.reduce(0) { $0 + Int($1.maxMarks) }
            let targetPerMark: Double = a.durationInSeconds > 0 && totalMaxMarks > 0
                ? Double(a.durationInSeconds) / Double(totalMaxMarks) : 0

            // Aggregate time spent per question label from event logs
            let spentSec: [String: Int64] = (a.eventLogs as? Set<ETSEventLogMO> ?? [])
                .filter { $0.eventType == "QUESTION_SPENT" }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }
                .reduce(into: [:]) { result, log in
                    let lbl = log.label ?? "?"
                    result[lbl] = (result[lbl] ?? 0) + log.durationSeconds
                }

            VStack(alignment: .leading, spacing: 8) {

                // ── Section header ─────────────────────────────────────────
                HStack {
                    Text("Question Marks & Time")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Spacer()
                    Text(String(format: "Total: %.0f / %d",
                                questionMarks.values.reduce(0, +), totalMaxMarks))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if targetPerMark > 0 {
                        Text("·  \(String(format: "%.0f", targetPerMark)) s / mark")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }

                // ── Column headers ─────────────────────────────────────────
                HStack(spacing: 0) {
                    Text("Question")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Earned")
                        .frame(width: 64, alignment: .trailing)
                    Text("Max")
                        .frame(width: 44, alignment: .trailing)
                    Text("Time Spent")
                        .frame(width: 84, alignment: .trailing)
                    Text("Target")
                        .frame(width: 72, alignment: .trailing)
                    Text("Diff")
                        .frame(width: 58, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                Divider()

                // ── Question rows ──────────────────────────────────────────
                ForEach(questions, id: \.id) { q in
                    let lbl    = q.questionLabel ?? "?"
                    let maxM   = q.maxMarks
                    let spent  = spentSec[lbl] ?? 0
                    let target = targetPerMark * Double(maxM)
                    let over   = target > 0 && Double(spent) > target
                    let diff   = Int64(Double(spent) - target)

                    let marksBinding = Binding<Double>(
                        get:  { questionMarks[lbl] ?? 0 },
                        set:  { val in
                            questionMarks[lbl] = max(0, min(val, Double(maxM)))
                            a.totalScore = questionMarks.values.reduce(0, +)
                        }
                    )

                    HStack(spacing: 0) {
                        Text(lbl)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("0", value: marksBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)

                        Text("/ \(maxM)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .frame(width: 48, alignment: .trailing)

                        // Time spent — red + bold if over target
                        Group {
                            if spent > 0 {
                                Text(formatTime(spent))
                                    .foregroundStyle(over ? .red : .primary)
                                    .fontWeight(over ? .bold : .regular)
                            } else {
                                Text("—")
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 84, alignment: .trailing)

                        // Target
                        Text(target > 0 ? formatTime(Int64(target)) : "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .frame(width: 72, alignment: .trailing)

                        // Diff
                        Group {
                            if target > 0 && spent > 0 {
                                Text(diffStr(diff))
                                    .foregroundStyle(over ? .red : Color(nsColor: .systemGreen))
                                    .fontWeight(over ? .bold : .regular)
                            } else {
                                Text("—")
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 58, alignment: .trailing)
                    }
                    .padding(.vertical, 3)

                    Divider()
                }

                // ── Totals row ─────────────────────────────────────────────
                let totalSpent = spentSec.values.reduce(0, +)
                HStack(spacing: 0) {
                    Text("TOTAL")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.0f", questionMarks.values.reduce(0, +)))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                    Text("/ \(totalMaxMarks)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 44, alignment: .trailing)
                    Text(totalSpent > 0 ? formatTime(totalSpent) : "—")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 84, alignment: .trailing)
                    Spacer().frame(width: 130)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Non-ETS score row

    @ViewBuilder
    private func nonETSScoreRow(_ a: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Score")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            if a.totalScore > 0 {
                HStack(spacing: 8) {
                    Text(String(format: "%.0f marks", a.totalScore))
                        .font(.system(size: 13, weight: .medium))
                    if let g = a.rawGrade, !g.isEmpty {
                        Text(g)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(nsColor: .systemBlue).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            } else {
                Text("No score recorded")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
        }
    }

    // MARK: - Review / Notes editors

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("คำถามที่ต้องดู")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            TextEditor(text: $reviewText)
                .font(.system(size: 12))
                .frame(minHeight: 80)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Additional Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            TextEditor(text: $notesText)
                .font(.system(size: 12))
                .frame(minHeight: 100)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }

    // MARK: - Historical panel

    @ViewBuilder
    private func historicalPanel(_ a: AttemptMO) -> some View {
        let past = ((a.paper?.attempts as? Set<AttemptMO>) ?? [])
            .filter { $0.paperType == "timed" && $0.objectID != a.objectID }
            .sorted { $0.attemptNumber < $1.attemptNumber }

        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Past Performances — same paper")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                ForEach(past, id: \.objectID) { p in
                    HStack(spacing: 8) {
                        Text("ATT \(p.attemptNumber)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 46, alignment: .leading)
                        if p.totalScore > 0 {
                            Text(String(format: "%.0f", p.totalScore))
                                .font(.system(size: 10, weight: .medium))
                        }
                        if let g = p.rawGrade, !g.isEmpty {
                            Text(g)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color(nsColor: .separatorColor).opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        if p.durationInSeconds > 0 {
                            Text(DurationParser.format(p.durationInSeconds))
                                .font(.system(size: 10))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                        if let ts = p.completedTimestamp {
                            Text(ts.formatted(.dateTime.day().month().year()))
                                .font(.system(size: 9))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    // MARK: - Event timeline (collapsible)

    private func timelineSection(_ a: AttemptMO) -> some View {
        let logs = (a.eventLogs as? Set<ETSEventLogMO> ?? [])
            .sorted { $0.sequenceIndex < $1.sequenceIndex }

        return VStack(alignment: .leading, spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("#").frame(width: 28, alignment: .center)
                Text("Label").frame(maxWidth: .infinity, alignment: .leading)
                Text("Type").frame(width: 70, alignment: .center)
                Text("Duration").frame(width: 80, alignment: .trailing)
                Text("Marks").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            .padding(.bottom, 4)

            Divider()

            ForEach(logs, id: \.id) { log in
                timelineRow(log)
                Divider().padding(.horizontal, 0)
            }

            HStack {
                Spacer()
                Text("== END ==")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func timelineRow(_ log: ETSEventLogMO) -> some View {
        let isBreak = log.eventType?.hasPrefix("BREAK") ?? false
        let typeShort: String = {
            switch log.eventType {
            case "QUESTION_SPENT": return "Q"
            case "BREAK_A":        return "Brk-A"
            case "BREAK_NA":       return "Brk-NA"
            default:               return log.eventType ?? "?"
            }
        }()

        HStack(spacing: 0) {
            Text("\(log.sequenceIndex)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 28, alignment: .center)
            Text(log.label ?? "—")
                .font(.system(size: 12,
                              weight: isBreak ? .regular : .medium,
                              design: .monospaced))
                .foregroundStyle(isBreak ? Color(nsColor: .secondaryLabelColor) : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(typeShort)
                .font(.system(size: 10))
                .foregroundStyle(isBreak
                                 ? Color(nsColor: .systemOrange)
                                 : Color(nsColor: .systemBlue))
                .frame(width: 70, alignment: .center)
            Text(formatTime(log.durationSeconds))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
            Text(isBreak ? "—" : String(format: "%.1f", log.marksEarned))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isBreak ? Color(nsColor: .tertiaryLabelColor) : .primary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .background(isBreak ? Color(nsColor: .systemOrange).opacity(0.04) : Color.clear)
    }

    // MARK: - Completion section

    private func completionSection(_ a: AttemptMO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mark as Complete")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    DatePicker("", selection: $completionDateTime,
                               displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time (HH:MM)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    DatePicker("", selection: $completionDateTime,
                               displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                Spacer()
                Button("Set Complete") {
                    commitEdits(a)
                    a.completedTimestamp = completionDateTime
                    PersistenceController.shared.save()
                }
                .buttonStyle(BlueGlassButtonStyle())
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }

    // MARK: - Action row

    private func actionRow(_ a: AttemptMO) -> some View {
        HStack(spacing: 10) {
            if a.scannedFilePath != nil {
                Button("View Scanned PDF") { showPDFViewer = true }
                Button("Open in Preview") {
                    guard let path = a.scannedFilePath else { return }
                    NSWorkspace.shared.open(URL(filePath: path))
                }
            }
            if a.paperType == "timed" {
                Button("Edit Grade") { showGradeCapture = true }
            }
            Spacer()
            Button("Save") { commitEdits(a) }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(BlueGlassButtonStyle())
        }
    }

    // MARK: - Helpers

    private func isETSSourced(_ a: AttemptMO) -> Bool {
        !((a.eventLogs as? Set<ETSEventLogMO>) ?? []).isEmpty
    }

    private func syncFromAttempt(_ a: AttemptMO) {
        reviewText          = a.reviewQuestions ?? ""
        notesText           = a.additionalNotes ?? ""
        let secs            = a.durationInSeconds
        durationEdit        = secs > 0 ? DurationParser.format(secs) : ""
        completionDateTime  = a.completedTimestamp ?? Date()

        // Seed question marks from ETS event logs
        if isETSSourced(a) {
            let questions = (a.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
            var marks: [String: Double] = Dictionary(
                uniqueKeysWithValues: questions.compactMap { q in
                    guard let lbl = q.questionLabel else { return nil }
                    return (lbl, 0.0)
                }
            )
            let logs = (a.eventLogs as? Set<ETSEventLogMO> ?? [])
                .filter { $0.eventType == "QUESTION_SPENT" }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }
            for log in logs { marks[log.label ?? "?"] = log.marksEarned }
            questionMarks = marks
        } else {
            questionMarks = [:]
        }
    }

    private func commitEdits(_ a: AttemptMO) {
        a.reviewQuestions = reviewText
        a.additionalNotes = notesText
        if !isETSSourced(a) {
            if let parsed = DurationParser.parse(durationEdit) {
                a.durationInSeconds = parsed
            }
        }
        if isETSSourced(a), !questionMarks.isEmpty {
            // Write marks back to the last ETSEventLogMO visit per question label
            let logs = (a.eventLogs as? Set<ETSEventLogMO> ?? [])
                .filter { $0.eventType == "QUESTION_SPENT" }
                .sorted { $0.sequenceIndex > $1.sequenceIndex }   // descending → last visit first
            var updated: Set<String> = []
            for log in logs {
                let lbl = log.label ?? "?"
                if !updated.contains(lbl) {
                    log.marksEarned = questionMarks[lbl] ?? 0
                    updated.insert(lbl)
                }
            }
            a.totalScore = questionMarks.values.reduce(0, +)
        }
        PersistenceController.shared.save()
    }

    private func formatTime(_ s: Int64) -> String {
        let t = max(s, 0)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }

    private func diffStr(_ d: Int64) -> String {
        let a = Swift.abs(d)
        let m = (a % 3600) / 60; let s = a % 60
        return (d >= 0 ? "+" : "-") + String(format: "%02d:%02d", m, s)
    }
}
