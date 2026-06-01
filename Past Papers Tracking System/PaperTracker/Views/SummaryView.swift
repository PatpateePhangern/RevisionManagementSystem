import SwiftUI
import CoreData

// MARK: - Summary pane enum

private enum SummaryPane: String, CaseIterable {
    case averageCalculator = "Average Calculator"
    case checklist         = "Checklist"
}

// MARK: - Data model

private struct SummaryRow: Identifiable {
    let id             = UUID()
    let subjectName:   String
    /// "Paper 1" / "Paper 2" … for CS subjects; nil for standard subjects.
    let paperComponent: String?
    /// Inclusive Attempts — timed (paperType == "timed") count only.
    let incAtt:  Int
    /// Exclusive Attempts — first-run timed only (attemptNumber == 1 AND timed).
    let excAtt:  Int
    /// All Attempts — total record count regardless of type.
    let allAtt:  Int
    let avgPercentage:  Double?   // nil when no threshold data
    let avgGrade:       String?
    let avgDurationSec: Double?
}

// MARK: - Top-level view

struct SummaryView: View {

    @Environment(\.managedObjectContext) private var ctx
    @State private var activePane: SummaryPane = .averageCalculator
    @Namespace private var paneNamespace

    var body: some View {
        VStack(spacing: 0) {
            // ── Pane picker ──────────────────────────────────────────────────
            HStack {
                Spacer()
                paneStrip
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch activePane {
                case .averageCalculator: AverageCalculatorView()
                case .checklist:         ChecklistView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.managedObjectContext, ctx)
            .animation(.smooth(duration: 0.25), value: activePane)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Custom glass pill strip — mirrors PaperTrackerRootView.tabStrip so the
    // selection indicator slides smoothly via matchedGeometryEffect.
    private var paneStrip: some View {
        HStack(spacing: 0) {
            ForEach(SummaryPane.allCases, id: \.self) { pane in
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        withAnimation(.smooth(duration: 0.3)) { activePane = pane }
                    }
                } label: {
                    Text(pane.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(activePane == pane ? Color.primary : Color.secondary)
                        .animation(.smooth(duration: 0.2), value: activePane)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background {
                            if activePane == pane {
                                Capsule()
                                    .fill(Color(white: 0, opacity: 0.10))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "paneTab", in: paneNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(3)
        .glassEffect(in: Capsule())
        .focusEffectDisabled()
    }
}

// MARK: - Average Calculator (original content)

private struct AverageCalculatorView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name, order: .forward)],
        animation: .default
    ) private var subjects: FetchedResults<SubjectMO>

    var body: some View {
        let rows = buildRows()
        return Group {
            if rows.isEmpty {
                emptyState
            } else {
                table(rows: rows)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No attempts recorded yet.")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text("Record attempts in Complete Logs to see analytics here.")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
    }

    private func table(rows: [SummaryRow]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                ForEach(rows) { row in
                    SummaryRowView(row: row)
                    Divider()
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Subject / Paper")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Inc. ATT")
                .frame(width: 64, alignment: .center)
                .help("Inclusive Attempts — Timed & Graded only")
            Text("Exc. ATT")
                .frame(width: 64, alignment: .center)
                .help("Exclusive Attempts — First run (ATT 1) Timed & Graded only")
            Text("All ATT")
                .frame(width: 60, alignment: .center)
                .help("All Attempts — every record regardless of type")
            Text("Avg %")
                .frame(width: 62, alignment: .center)
            Text("Avg Grade")
                .frame(width: 76, alignment: .center)
            Text("Avg Duration")
                .frame(width: 96, alignment: .center)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func buildRows() -> [SummaryRow] {
        var rows: [SummaryRow] = []
        var csSubjects: [SubjectMO] = []
        var regularSubjects: [SubjectMO] = []
        for subject in subjects {
            if isCSSubject(subject.name ?? "") { csSubjects.append(subject) }
            else { regularSubjects.append(subject) }
        }
        for paperNum in 1...4 {
            let paperKey = "P\(paperNum)"
            var timedAttempts: [AttemptMO] = []
            var allAttempts:   [AttemptMO] = []
            for subject in csSubjects {
                let papers = (subject.papers as? Set<PaperMO>) ?? []
                let matching = papers.filter { ($0.normalizedSeries ?? "").contains("-\(paperKey)") }
                for paper in matching {
                    let attempts = (paper.attempts as? Set<AttemptMO>) ?? []
                    allAttempts.append(contentsOf: attempts)
                    timedAttempts.append(contentsOf: attempts.filter { $0.paperType == "timed" })
                }
            }
            guard !allAttempts.isEmpty else { continue }
            rows.append(makeSummaryRow(subjectName: "Computer Science", paperComponent: "Paper \(paperNum)", allAttempts: allAttempts, timedAttempts: timedAttempts))
        }
        for subject in regularSubjects {
            let papers = (subject.papers as? Set<PaperMO>) ?? []
            var allAttempts:   [AttemptMO] = []
            var timedAttempts: [AttemptMO] = []
            for paper in papers {
                let attempts = (paper.attempts as? Set<AttemptMO>) ?? []
                allAttempts.append(contentsOf: attempts)
                timedAttempts.append(contentsOf: attempts.filter { $0.paperType == "timed" })
            }
            guard !allAttempts.isEmpty else { continue }
            rows.append(makeSummaryRow(subjectName: subject.name ?? "—", paperComponent: nil, allAttempts: allAttempts, timedAttempts: timedAttempts))
        }
        return rows
    }

    private func makeSummaryRow(subjectName: String, paperComponent: String?, allAttempts: [AttemptMO], timedAttempts: [AttemptMO]) -> SummaryRow {
        let incAtt = timedAttempts.count
        let excAtt = timedAttempts.filter { $0.attemptNumber == 1 }.count
        let allAtt = allAttempts.count
        let percentages: [Double] = timedAttempts.compactMap { attempt -> Double? in
            guard attempt.totalScore > 0 else { return nil }
            guard let norm = attempt.paper?.normalizedSeries,
                  let threshold = GradeThresholdTableMO.find(rawSeriesKey: norm, in: ctx),
                  threshold.maxPossibleMarks > 0 else { return nil }
            return (attempt.totalScore / Double(threshold.maxPossibleMarks)) * 100.0
        }
        let avgPct: Double? = percentages.isEmpty ? nil : percentages.reduce(0, +) / Double(percentages.count)
        let avgGrade = averageGrade(from: timedAttempts)
        let durations = timedAttempts.filter { $0.durationInSeconds > 0 }.map { Double($0.durationInSeconds) }
        let avgDur: Double? = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        return SummaryRow(subjectName: subjectName, paperComponent: paperComponent, incAtt: incAtt, excAtt: excAtt, allAtt: allAtt, avgPercentage: avgPct, avgGrade: avgGrade, avgDurationSec: avgDur)
    }

    private func isCSSubject(_ name: String) -> Bool {
        let u = name.uppercased()
        return u.contains("CS1") || u.contains("CS2") || u.contains("CS3") || u.contains("CS4") || u.contains("COMPUTER SCIENCE")
    }

    private let gradeToOrdinal: [String: Int] = ["U": 0, "E": 1, "D": 2, "C": 3, "B": 4, "A": 5, "A*": 6]
    private let ordinalToGrade: [Int: String]  = [0: "U", 1: "E", 2: "D", 3: "C", 4: "B", 5: "A", 6: "A*"]

    private func averageGrade(from attempts: [AttemptMO]) -> String? {
        let grades = attempts.compactMap { $0.rawGrade }.filter { !$0.isEmpty }
        let nums = grades.compactMap { gradeToOrdinal[$0] }
        guard !nums.isEmpty else { return nil }
        let avg = Int((Double(nums.reduce(0, +)) / Double(nums.count)).rounded())
        return ordinalToGrade[min(max(avg, 0), 6)]
    }
}

// MARK: - Summary row sub-view

private struct SummaryRowView: View {
    let row: SummaryRow

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.subjectName)
                    .font(.system(size: 12, weight: .medium))
                if let component = row.paperComponent {
                    Text(component)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.incAtt)").font(.system(size: 12, weight: .semibold)).frame(width: 64, alignment: .center)
            Text("\(row.excAtt)").font(.system(size: 12)).foregroundStyle(Color(nsColor: .secondaryLabelColor)).frame(width: 64, alignment: .center)
            Text("\(row.allAtt)").font(.system(size: 11)).foregroundStyle(Color(nsColor: .tertiaryLabelColor)).frame(width: 60, alignment: .center)
            Group {
                if let pct = row.avgPercentage { Text(String(format: "%.1f%%", pct)).font(.system(size: 12, weight: .medium)) }
                else { Text("—").foregroundStyle(Color(nsColor: .tertiaryLabelColor)) }
            }.font(.system(size: 12)).frame(width: 62, alignment: .center)
            Group {
                if let grade = row.avgGrade { Text(grade).font(.system(size: 13, weight: .bold)) }
                else { Text("—").foregroundStyle(Color(nsColor: .tertiaryLabelColor)) }
            }.frame(width: 76, alignment: .center)
            Group {
                if let dur = row.avgDurationSec { Text(DurationParser.format(Int64(dur))).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(nsColor: .secondaryLabelColor)) }
                else { Text("—").foregroundStyle(Color(nsColor: .tertiaryLabelColor)) }
            }.frame(width: 96, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}

// MARK: - Checklist view

private struct ChecklistView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name, order: .forward)],
        animation: .default
    ) private var subjects: FetchedResults<SubjectMO>

    @State private var selectedSubjectID: NSManagedObjectID? = nil

    private var selectedSubject: SubjectMO? {
        guard let id = selectedSubjectID else { return nil }
        return subjects.first { $0.objectID == id }
    }

    var body: some View {
        HSplitView {
            // ── Subject list (sidebar) ───────────────────────────────────────
            VStack(spacing: 0) {
                Text("Subjects")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(subjects, id: \.objectID) { subject in
                            let isSelected = selectedSubjectID == subject.objectID
                            Button {
                                selectedSubjectID = subject.objectID
                            } label: {
                                Text(subject.name ?? "—")
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected
                                          ? Color.accentColor
                                          : Color.clear)
                            )
                            .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
                            .animation(.smooth(duration: 0.18), value: selectedSubjectID)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

            // ── Checklist table ──────────────────────────────────────────────
            if let subject = selectedSubject {
                ChecklistSubjectTable(subject: subject)
                    .environment(\.managedObjectContext, ctx)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Select a subject to view its checklist")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Checklist per-subject table

private struct ChecklistSubjectTable: View {

    @ObservedObject var subject: SubjectMO
    @Environment(\.managedObjectContext) private var ctx

    /// Number of attempt columns to display for this subject.
    /// Persisted per-subject in UserDefaults under "checklistCols_<uuid>".
    @State private var colCount: Int = 2
    /// When true, practice (paperType == "practice") attempts are included.
    @State private var includePractice: Bool = false
    /// Used to show an alert when the user taps a cell with no linked attempt.
    @State private var showMissingAlert: Bool = false

    private var udKey: String { "checklistCols_\(subject.id?.uuidString ?? "default")" }

    private var papers: [PaperMO] {
        ((subject.papers as? Set<PaperMO>) ?? [])
            .sorted { ($0.normalizedSeries ?? "") < ($1.normalizedSeries ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ──────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Text(subject.name ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                // Column controls
                HStack(spacing: 6) {
                    Text("Attempt Columns:")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    Button {
                        if colCount > 1 { colCount -= 1; saveColCount() }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .disabled(colCount <= 1)
                    Text("\(colCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, alignment: .center)
                    Button {
                        if colCount < 10 { colCount += 1; saveColCount() }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(BlueGlassButtonStyle())
                    .disabled(colCount >= 10)
                }
                // Include Practice Papers — animated checkmark toggle
                Button {
                    withAnimation(.smooth(duration: 0.2)) { includePractice.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: includePractice ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(includePractice ? Color.accentColor : Color.secondary)
                            .animation(.smooth(duration: 0.2), value: includePractice)
                            .contentTransition(.symbolEffect(.replace))
                        Text("Practice Papers")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(BlueGlassButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if papers.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No papers found for \(subject.name ?? "this subject").")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    Text("Add series in the Papers Mapping menu first.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .quaternaryLabelColor))
                    Spacer()
                }
            } else {
                // ── Table ────────────────────────────────────────────────────
                ScrollView {
                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            Text("Paper")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)

                            ForEach(1...colCount, id: \.self) { col in
                                Text("Attempt \(col)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                    .frame(width: 110, alignment: .center)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))

                        Divider()

                        // Data rows
                        ForEach(papers, id: \.objectID) { paper in
                            ChecklistRow(
                                paper: paper,
                                colCount: colCount,
                                includePractice: includePractice,
                                onMissingAttempt: { showMissingAlert = true }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .alert("No Record Found", isPresented: $showMissingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There is no attempt record for this slot in Complete Logs.")
        }
        .onAppear {
            colCount = UserDefaults.standard.integer(forKey: udKey)
            if colCount < 1 { colCount = 2 }
        }
    }

    private func saveColCount() {
        UserDefaults.standard.set(colCount, forKey: udKey)
    }
}

// MARK: - Checklist row

private struct ChecklistRow: View {

    @ObservedObject var paper: PaperMO
    let colCount: Int
    let includePractice: Bool
    let onMissingAttempt: () -> Void

    private var sortedAttempts: [AttemptMO] {
        var all = (paper.attempts as? Set<AttemptMO> ?? [])
            .sorted { $0.attemptNumber < $1.attemptNumber }
        if !includePractice {
            all = all.filter { $0.paperType != "practice" }
        }
        return all
    }

    var body: some View {
        HStack(spacing: 0) {
            // Paper name
            if let norm = paper.normalizedSeries {
                Text(SeriesNormalizationEngine.displayName(from: norm))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
            } else {
                Text(paper.rawSeriesName ?? "—")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            Spacer(minLength: 8)

            // Attempt columns
            ForEach(1...colCount, id: \.self) { col in
                let attempt: AttemptMO? = col <= sortedAttempts.count ? sortedAttempts[col - 1] : nil
                ChecklistCell(attempt: attempt, onMissingAttempt: onMissingAttempt)
                    .frame(width: 110)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Checklist cell

private struct ChecklistCell: View {

    let attempt: AttemptMO?
    let onMissingAttempt: () -> Void

    var body: some View {
        if let a = attempt {
            ObservedCell(attempt: a)
        } else {
            Button {
                onMissingAttempt()
            } label: {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .quaternaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Inner cell that observes the attempt for live status updates.
private struct ObservedCell: View {
    @ObservedObject var attempt: AttemptMO

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .switchPaperTrackerTab, object: PaperTrackerTab.completeLogs)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .selectAttemptInCompleteLogs, object: attempt.objectID)
            }
        } label: {
            let status = attempt.manualStatus ?? (attempt.isComplete ? "Done" : "Pending")
            let color  = checklistStatusColor(status)
            Text(status)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
    }
}

private func checklistStatusColor(_ status: String) -> Color {
    switch status {
    case "Done":             return Color(nsColor: .systemGreen)
    case "Ask Teacher":      return Color(nsColor: .systemBlue)
    case "Pending Analysis": return Color(nsColor: .secondaryLabelColor)
    default:                 return Color(nsColor: .systemOrange)
    }
}
