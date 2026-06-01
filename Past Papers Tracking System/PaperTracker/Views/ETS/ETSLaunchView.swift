import SwiftUI
import CoreData

/// Entry point for the Exam Timing System tab.
///
/// Lists all incomplete attempts (no completedTimestamp) so the user can
/// pick one and launch ETSSessionView directly from the tab bar.
struct ETSLaunchView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\AttemptMO.printTimestamp, order: .reverse)],
        predicate: NSPredicate(format: "completedTimestamp == nil"),
        animation: .default
    ) private var pendingAttempts: FetchedResults<AttemptMO>

    @State private var selectedAttemptID: NSManagedObjectID?
    @State private var showSession = false

    private var selectedAttempt: AttemptMO? {
        guard let id = selectedAttemptID else { return nil }
        return pendingAttempts.first { $0.objectID == id }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // ── Left: pending attempt list ───────────────────────────────────
            VStack(spacing: 0) {
                listHeader
                Divider()
                if pendingAttempts.isEmpty {
                    emptyState
                } else {
                    attemptList
                }
            }
            .frame(minWidth: 280, maxWidth: 340)

            // ── Right: detail + launch ───────────────────────────────────────
            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSession) {
            if let attempt = selectedAttempt, let paper = attempt.paper {
                ETSSessionView(paper: paper, attempt: attempt)
                    .environment(\.managedObjectContext, ctx)
            }
        }
    }

    // MARK: - List header

    private var listHeader: some View {
        HStack {
            Text("Pending Attempts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Spacer()
            Text("\(pendingAttempts.count)")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Attempt list

    private var attemptList: some View {
        List(pendingAttempts, id: \.objectID, selection: $selectedAttemptID) { attempt in
            attemptRow(attempt)
                .tag(attempt.objectID)
        }
        .listStyle(.inset)
    }

    private func attemptRow(_ a: AttemptMO) -> some View {
        let hasQuestions = !((a.paper?.questionStructures as? Set<QuestionStructureMO> ?? []).isEmpty)
        return VStack(alignment: .leading, spacing: 4) {
            Text(a.paper?.subject?.name ?? "Unknown Subject")
                .font(.system(size: 14, weight: .medium))

            Text(SeriesNormalizationEngine.displayName(
                from: a.paper?.normalizedSeries ?? ""))
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack(spacing: 6) {
                Text(a.barcodeValue ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                if hasQuestions {
                    Label("Questions ready", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            Text("No pending attempts")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text("Generate a new paper first, then return here to start an ETS session.")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Spacer()
        }
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let attempt = selectedAttempt {
            VStack(spacing: 0) {
                Spacer()

                // Paper info
                VStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)

                    Text(attempt.paper?.subject?.name ?? "—")
                        .font(.system(size: 22, weight: .bold))

                    Text(SeriesNormalizationEngine.displayName(
                        from: attempt.paper?.normalizedSeries ?? ""))
                        .font(.system(size: 16))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                    Text("ATT #\(attempt.attemptNumber)  ·  \(attempt.barcodeValue ?? "")")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                Spacer().frame(height: 32)

                // Question structure status
                let questions = (attempt.paper?.questionStructures as? Set<QuestionStructureMO> ?? [])
                    .sorted { $0.displayOrder < $1.displayOrder }

                if questions.isEmpty {
                    Label("No questions defined — you'll be prompted to add them on launch.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .frame(maxWidth: 300)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 4) {
                        Text("\(questions.count) questions · \(questions.reduce(0) { $0 + Int($1.maxMarks) }) total marks")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                        HStack(spacing: 6) {
                            ForEach(questions.prefix(8), id: \.id) { q in
                                Text(q.questionLabel ?? "?")
                                    .font(.system(size: 9, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .separatorColor).opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if questions.count > 8 {
                                Text("+\(questions.count - 8)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                    }
                }

                Spacer().frame(height: 28)

                // Launch button
                Button {
                    showSession = true
                } label: {
                    Label("Start ETS Session", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 220, height: 44)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)

                Text("⌘↩ to launch")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.top, 6)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "arrow.left")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text("Select a pending attempt to begin")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
