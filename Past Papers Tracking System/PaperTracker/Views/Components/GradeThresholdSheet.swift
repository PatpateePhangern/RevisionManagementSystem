import SwiftUI
import CoreData

/// Sheet presented after a "Timed & Graded" attempt is confirmed.
///
/// Captures per-question earned marks (or a single total score when no
/// question structure is defined), the exam duration, and the grade-boundary
/// table for the current paper series.
///
/// Question structure (labels + max marks) is persisted to `QuestionStructureMO`
/// on the paper so that future ETS sessions and Grade Capture sheets for the
/// same paper series are pre-populated automatically.
struct GradeThresholdSheet: View {

    @Environment(\.managedObjectContext) private var ctx

    let attempt:    AttemptMO
    @Binding var isPresented: Bool

    // MARK: - Local question row model

    private struct QuestionEntry: Identifiable {
        let id:       UUID   = UUID()
        var label:    String = ""
        var maxMarks: String = ""
        var earned:   String = ""
    }

    // ── Question entries ──────────────────────────────────────────────────────
    @State private var questionEntries: [QuestionEntry] = []

    // ── Score / timing (used when no questions are defined) ───────────────────
    @State private var scoreText:    String = ""
    @State private var maxMarksText: String = ""
    @State private var durationText: String = ""

    // ── Grade boundaries ──────────────────────────────────────────────────────
    @State private var hasAStar:      Bool   = false
    @State private var markAStarText: String = ""
    @State private var markAText:     String = ""
    @State private var markBText:     String = ""
    @State private var markCText:     String = ""
    @State private var markDText:     String = ""
    @State private var markEText:     String = ""

    // ── Live grade ────────────────────────────────────────────────────────────
    @State private var computedGrade:      String = ""
    @State private var computedPercentage: String = ""

    // ── Historical autocomplete detection ─────────────────────────────────────
    @State private var historicalLoaded: Bool = false

    private var seriesKey: String { attempt.paper?.normalizedSeries ?? "" }

    // MARK: - Computed totals from question entries

    private var questionsTotal: Double {
        questionEntries.reduce(0.0) { $0 + (Double($1.earned) ?? 0) }
    }

    private var questionsMaxTotal: Int {
        questionEntries.reduce(0) { $0 + (Int($1.maxMarks) ?? 0) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            questionSection
            Divider()
            scoreRow
            Divider()
            boundarySection
            Divider()
            footerRow
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { loadHistoricalIfAvailable() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Grade Capture")
                    .font(.system(size: 14, weight: .semibold))
                if let norm = attempt.paper?.normalizedSeries {
                    Text(SeriesNormalizationEngine.displayName(from: norm))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            Spacer()
            if !computedGrade.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(computedGrade)
                        .font(.system(size: 28, weight: .bold))
                    if !computedPercentage.isEmpty {
                        Text(computedPercentage + "%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
            Button("Skip") { isPresented = false }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.leading, 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Question section

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Questions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        questionEntries.append(QuestionEntry())
                    }
                } label: {
                    Label("Add Question", systemImage: "plus.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.small)
            }

            if questionEntries.isEmpty {
                Text("No question structure defined. Add questions for a per-question mark breakdown — the structure is saved to this paper and reused automatically in future ETS sessions.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("Question")
                        .frame(width: 110, alignment: .leading)
                    Text("Max")
                        .frame(width: 56, alignment: .trailing)
                    Text("Earned")
                        .frame(width: 66, alignment: .trailing)
                    Spacer()
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.top, 2)

                Divider()

                // One row per question
                ForEach(questionEntries.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("e.g. Q1", text: $questionEntries[i].label)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 102)
                            .font(.system(size: 11))

                        TextField("0", text: $questionEntries[i].maxMarks)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                            .font(.system(size: 11))
                            .onChange(of: questionEntries[i].maxMarks) { _, _ in recalculate() }

                        TextField("0", text: $questionEntries[i].earned)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 58)
                            .font(.system(size: 11))
                            .onChange(of: questionEntries[i].earned) { _, _ in recalculate() }

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                _ = questionEntries.remove(at: i)
                            }
                            recalculate()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)

                        Spacer()
                    }
                    .padding(.vertical, 3)
                }

                Divider()

                // Totals row
                HStack(spacing: 0) {
                    Text("Total")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 110, alignment: .leading)
                    Text("\(questionsMaxTotal)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                    Text(String(format: "%.0f", questionsTotal))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 66, alignment: .trailing)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Score row
    // Shows manual Score + Out of only when no question structure is defined.
    // Always shows Duration.

    private var scoreRow: some View {
        HStack(alignment: .top, spacing: 24) {
            if questionEntries.isEmpty {
                // Manual total score entry
                fieldColumn(label: "Score") {
                    TextField("e.g. 45", text: $scoreText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onChange(of: scoreText) { _, _ in recalculate() }
                }
                fieldColumn(label: "Out of") {
                    TextField("e.g. 75", text: $maxMarksText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onChange(of: maxMarksText) { _, _ in recalculate() }
                }
            } else {
                // Read-only computed total (questions drive the score)
                fieldColumn(label: "Score (computed)") {
                    Text(String(format: "%.0f / %d", questionsTotal, questionsMaxTotal))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .frame(height: 22)
                }
            }
            fieldColumn(label: "Duration") {
                TextField("e.g. 1h 30m", text: $durationText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Boundary section

    private var boundarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Grade Boundaries")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Toggle("Enable A* grade", isOn: $hasAStar)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .onChange(of: hasAStar) { _, _ in recalculate() }
            }

            if historicalLoaded {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(nsColor: .systemBlue))
                    Text("Auto-loaded from a previous session with the same series")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            boundaryGrid
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var boundaryGrid: some View {
        let entries: [(label: String, text: Binding<String>, active: Bool)] = [
            ("A*", $markAStarText, hasAStar),
            ("A",  $markAText,    true),
            ("B",  $markBText,    true),
            ("C",  $markCText,    true),
            ("D",  $markDText,    true),
            ("E",  $markEText,    true),
        ]
        HStack(spacing: 12) {
            ForEach(entries, id: \.label) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.active
                                         ? Color(nsColor: .labelColor)
                                         : Color(nsColor: .disabledControlTextColor))
                    TextField("0", text: entry.text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 46)
                        .disabled(!entry.active)
                        .onChange(of: entry.text.wrappedValue) { _, _ in recalculate() }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            Spacer()
            Button("Save") { save() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldColumn<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            content()
        }
    }

    // MARK: - Business logic

    private func loadHistoricalIfAvailable() {
        // Load grade threshold
        if !seriesKey.isEmpty,
           let hist = GradeThresholdTableMO.find(rawSeriesKey: seriesKey, in: ctx) {
            maxMarksText  = hist.maxPossibleMarks > 0 ? "\(hist.maxPossibleMarks)" : ""
            hasAStar      = hist.hasAStar
            markAStarText = hist.hasAStar ? "\(hist.markAStar)" : ""
            markAText     = hist.markA > 0 ? "\(hist.markA)" : ""
            markBText     = hist.markB > 0 ? "\(hist.markB)" : ""
            markCText     = hist.markC > 0 ? "\(hist.markC)" : ""
            markDText     = hist.markD > 0 ? "\(hist.markD)" : ""
            markEText     = hist.markE > 0 ? "\(hist.markE)" : ""
            historicalLoaded = true
        }

        // Load question structures
        if let paper = attempt.paper, let pid = paper.id {
            let qs = QuestionStructureMO.fetch(paperID: pid, in: ctx)
            if !qs.isEmpty {
                questionEntries = qs.map { q in
                    QuestionEntry(
                        label:    q.questionLabel ?? "",
                        maxMarks: "\(q.maxMarks)",
                        earned:   ""
                    )
                }
            }
        }

        recalculate()
    }

    private func recalculate() {
        let effectiveScore: Double
        let effectiveMax:   Double

        if !questionEntries.isEmpty {
            effectiveScore = questionsTotal
            effectiveMax   = Double(questionsMaxTotal)
        } else {
            guard let s = Double(scoreText) else {
                computedGrade      = ""
                computedPercentage = ""
                return
            }
            effectiveScore = s
            effectiveMax   = Double(maxMarksText) ?? 0
        }

        // Must have at least one boundary configured to produce a grade
        guard !markAText.isEmpty || !markEText.isEmpty else {
            computedGrade      = ""
            computedPercentage = ""
            // Still compute percentage if max is known
            if effectiveMax > 0 {
                computedPercentage = String(format: "%.1f", effectiveScore / effectiveMax * 100)
            }
            return
        }

        let s = Int16(max(0, min(effectiveScore, Double(Int16.max))))

        if hasAStar, let aStar = Int16(markAStarText), aStar > 0, s >= aStar {
            computedGrade = "A*"
        } else if let a = Int16(markAText), a > 0, s >= a {
            computedGrade = "A"
        } else if let b = Int16(markBText), b > 0, s >= b {
            computedGrade = "B"
        } else if let c = Int16(markCText), c > 0, s >= c {
            computedGrade = "C"
        } else if let d = Int16(markDText), d > 0, s >= d {
            computedGrade = "D"
        } else if let e = Int16(markEText), e > 0, s >= e {
            computedGrade = "E"
        } else if !markEText.isEmpty {
            computedGrade = "U"
        } else {
            computedGrade = ""
        }

        if effectiveMax > 0 {
            let pct = (effectiveScore / effectiveMax) * 100
            computedPercentage = String(format: "%.1f", pct)
        } else {
            computedPercentage = ""
        }
    }

    private func save() {
        // ── Derive final score and max ────────────────────────────────────────
        let finalScore: Double
        let finalMax:   Int16

        if !questionEntries.isEmpty {
            finalScore = questionsTotal
            finalMax   = Int16(min(questionsMaxTotal, Int(Int16.max)))
        } else {
            finalScore = Double(scoreText) ?? 0
            finalMax   = Int16(maxMarksText) ?? 0
        }

        if finalScore > 0 { attempt.totalScore = finalScore }
        attempt.rawGrade = computedGrade.isEmpty ? nil : computedGrade
        if let dur = DurationParser.parse(durationText) {
            attempt.durationInSeconds = dur
        }

        // ── Persist question structure ────────────────────────────────────────
        // Only update when the user has defined at least one valid question row.
        let validQuestions = questionEntries.filter { entry in
            !entry.label.trimmingCharacters(in: .whitespaces).isEmpty
                && (Int16(entry.maxMarks) ?? 0) > 0
        }
        if !validQuestions.isEmpty, let paper = attempt.paper {
            // Delete all existing structures for this paper, then insert fresh.
            let old = (paper.questionStructures as? Set<QuestionStructureMO>) ?? []
            old.forEach { ctx.delete($0) }
            for (idx, entry) in validQuestions.enumerated() {
                QuestionStructureMO.insert(
                    label:        entry.label.trimmingCharacters(in: .whitespaces),
                    maxMarks:     Int16(entry.maxMarks)!,
                    displayOrder: Int16(idx),
                    paper:        paper,
                    in:           ctx
                )
            }
        }

        // ── Persist grade threshold table ─────────────────────────────────────
        if !seriesKey.isEmpty, let paper = attempt.paper {
            let threshold = GradeThresholdTableMO.find(rawSeriesKey: seriesKey, in: ctx)
                ?? GradeThresholdTableMO.insert(rawSeriesKey: seriesKey, paper: paper, in: ctx)

            threshold.maxPossibleMarks = finalMax
            threshold.hasAStar  = hasAStar
            threshold.markAStar = hasAStar ? (Int16(markAStarText) ?? 0) : 0
            threshold.markA     = Int16(markAText) ?? 0
            threshold.markB     = Int16(markBText) ?? 0
            threshold.markC     = Int16(markCText) ?? 0
            threshold.markD     = Int16(markDText) ?? 0
            threshold.markE     = Int16(markEText) ?? 0
        }

        PersistenceController.shared.save()
        isPresented = false
    }
}
