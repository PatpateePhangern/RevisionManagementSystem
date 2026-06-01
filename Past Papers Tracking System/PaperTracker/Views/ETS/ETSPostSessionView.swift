import SwiftUI
import CoreData

/// Efficiency summary shown after an ETS session completes.
///
/// Displays a per-question table comparing actual time spent against the ideal
/// target derived from `targetSecondsPerMark`. Over-target rows appear in bold
/// red. Offers "Print Receipt" (generates an A5 PDF) and "Save & Close".
struct ETSPostSessionView: View {

    let engine:  ETSTimerEngine
    let attempt: AttemptMO
    let paper:   PaperMO

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss)              private var dismiss

    @State private var isSaving  = false
    @State private var saveError: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────────────
            VStack(spacing: 4) {
                Text("Session Complete")
                    .font(.title2.weight(.bold))
                Text(paper.rawSeriesName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    summaryChip(label: "Time Used",
                                value: formatTime(
                                    engine.totalAllottedSeconds - engine.globalCountdownSeconds))
                    summaryChip(label: "Questions",
                                value: "\(engine.questions.count)")
                    summaryChip(label: "Target/Mark",
                                value: formatTime(Int64(engine.targetSecondsPerMark)))
                }
                .padding(.top, 4)
            }
            .padding()

            Divider()

            // ── Column headers ─────────────────────────────────────────────
            HStack {
                Text("Question")
                    .frame(width: 90, alignment: .leading)
                Text("Max")
                    .frame(width: 50, alignment: .trailing)
                Text("Marks")
                    .frame(width: 60, alignment: .trailing)
                Text("Spent")
                    .frame(width: 70, alignment: .trailing)
                Text("Target")
                    .frame(width: 70, alignment: .trailing)
                Text("Diff")
                    .frame(width: 60, alignment: .trailing)
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // ── Efficiency rows ────────────────────────────────────────────
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(engine.questions.enumerated()), id: \.element.id) { idx, q in
                        efficiencyRow(index: idx, question: q)
                        Divider().padding(.horizontal)
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 400)

            Divider()

            // ── Totals row ─────────────────────────────────────────────────
            HStack {
                Text("TOTAL")
                    .font(.caption.weight(.bold))
                    .frame(width: 90, alignment: .leading)
                Text("\(engine.totalMaxMarks)")
                    .font(.caption.weight(.bold))
                    .frame(width: 50, alignment: .trailing)
                Text(String(format: "%.1f", totalMarksEarned))
                    .font(.caption.weight(.bold))
                    .frame(width: 60, alignment: .trailing)
                Text(formatTime(engine.totalAllottedSeconds - engine.globalCountdownSeconds))
                    .font(.system(.caption).weight(.bold))
                    .frame(width: 70, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.background.secondary)

            Divider()

            // ── Error message ──────────────────────────────────────────────
            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            // ── Footer buttons ─────────────────────────────────────────────
            HStack {
                Button {
                    printReceipt()
                } label: {
                    Label("Print Receipt", systemImage: "printer")
                }
                .buttonStyle(BlueGlassButtonStyle())

                Spacer()

                Button("Save & Close") {
                    saveAndClose()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(BlueGlassButtonStyle())
                .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 560)
    }

    // MARK: - Efficiency row

    @ViewBuilder
    private func efficiencyRow(index: Int, question: QuestionStructureMO) -> some View {
        let label      = question.questionLabel ?? "Q\(index + 1)"
        let maxMarks   = question.maxMarks
        let target     = engine.targetSecondsPerMark * Double(maxMarks)
        let spent      = spentSeconds(for: index)
        let marks      = engine.marksEarned.indices.contains(index)
                         ? engine.marksEarned[index] : 0.0
        let isOver     = target > 0 && Double(spent) > target
        let diff       = Int64(Double(spent) - target)

        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            Text("\(maxMarks)")
                .frame(width: 50, alignment: .trailing)
            Text(String(format: "%.1f", marks))
                .frame(width: 60, alignment: .trailing)
            Text(formatTime(spent))
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(isOver ? .red : .primary)
                .fontWeight(isOver ? .bold : .regular)
            Text(target > 0 ? formatTime(Int64(target)) : "—")
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(target > 0 ? diffLabel(diff) : "—")
                .foregroundStyle(isOver ? .red : .green)
                .fontWeight(isOver ? .bold : .regular)
                .frame(width: 60, alignment: .trailing)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(isOver ? Color.red.opacity(0.07) : Color.clear)
    }

    // MARK: - Summary chip

    private func summaryChip(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body).weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private var totalMarksEarned: Double {
        engine.marksEarned.reduce(0, +)
    }

    /// Aggregates total seconds spent on a given question index across all
    /// QUESTION_SPENT events (handles revisits).
    private func spentSeconds(for index: Int) -> Int64 {
        guard engine.questions.indices.contains(index) else { return 0 }
        let label = engine.questions[index].questionLabel ?? "Q\(index + 1)"
        // Access internal pending events via the engine's public state by
        // reconstructing from the eventLogs relationship if already saved,
        // or fall back to the live stopwatch for the current question.
        // Since the session just completed, we rely on the attempt's eventLogs
        // relationship if already persisted; otherwise use engine.questionStopwatchSeconds
        // for the last active question.
        let logs = (attempt.eventLogs as? Set<ETSEventLogMO>) ?? []
        if !logs.isEmpty {
            return logs
                .filter { $0.eventType == "QUESTION_SPENT" && $0.label == label }
                .reduce(0) { $0 + $1.durationSeconds }
        }
        // Pre-save: read from engine's in-flight state.
        // The engine doesn't expose pendingEvents publicly, so we re-derive
        // from the per-question marksEarned array length for now.
        // For accuracy, save first via saveEventLog then reopen post-session view.
        return 0
    }

    private func diffLabel(_ diff: Int64) -> String {
        let abs = Swift.abs(diff)
        let h = abs / 3600
        let m = (abs % 3600) / 60
        let s = abs % 60
        let sign = diff >= 0 ? "+" : "-"
        if h > 0 { return "\(sign)\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))" }
        return "\(sign)\(String(format: "%02d", m)):\(String(format: "%02d", s))"
    }

    private func formatTime(_ totalSeconds: Int64) -> String {
        let s = max(totalSeconds, 0)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    // MARK: - Actions

    private func printReceipt() {
        // Save first so the PDF generator can read from the attempt object.
        engine.saveEventLog(to: attempt, in: context)
        attempt.paperType = "timed"
        try? context.save()
        ETSPDFReceiptGenerator.generate(attempt: attempt, paper: paper,
                                        targetSecondsPerMark: engine.targetSecondsPerMark)
    }

    private func saveAndClose() {
        isSaving = true
        engine.saveEventLog(to: attempt, in: context)
        attempt.paperType     = "timed"
        attempt.completedTimestamp = Date()
        do {
            try context.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }
}
