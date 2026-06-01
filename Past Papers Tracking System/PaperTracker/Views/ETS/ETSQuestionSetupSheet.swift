import SwiftUI
import CoreData

/// Modal sheet for defining (or editing) the question structure of a paper.
///
/// Keyboard shortcuts:
///   ⌘N        → Add a new question row
///   ⌘↩        → Save
///   ⎋         → Cancel
///
/// Pre-populates from existing QuestionStructureMO entries so repeat edits
/// don't force the user to re-enter all questions from scratch.
struct ETSQuestionSetupSheet: View {

    let paper: PaperMO
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss)              private var dismiss

    /// Callback fired with the saved structures so the caller can proceed.
    var onSave: ([QuestionStructureMO]) -> Void = { _ in }

    // MARK: - Local row model

    private struct QuestionRow: Identifiable {
        let id = UUID()
        var label:    String = ""
        var maxMarks: String = ""
    }

    @State private var rows: [QuestionRow] = []
    @State private var validationError: String?
    @FocusState private var focusedRowID: UUID?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Question Structure")
                        .font(.headline)
                    Text((paper.rawSeriesName ?? "").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    addRow()
                } label: {
                    Label("Add Question", systemImage: "plus.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(BlueGlassButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
                .help("Add question (⌘N)")
            }
            .padding()

            Divider()

            // ── Column headers ───────────────────────────────────────────────
            HStack {
                Text("Label")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 160, alignment: .leading)
                Text("Max Marks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text("Delete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .center)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // ── Question rows ────────────────────────────────────────────────
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No questions yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Press ⌘N or tap Add Question to create the first row.")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    Spacer()
                }
                .frame(minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($rows) { $row in
                            HStack(spacing: 10) {
                                TextField("e.g. Q1 / 4a", text: $row.label)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .focused($focusedRowID, equals: row.id)

                                TextField("e.g. 12", text: $row.maxMarks)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    // Tab on the last marks field → add a new row
                                    .onSubmit {
                                        if rows.last?.id == row.id {
                                            addRow()
                                        }
                                    }

                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        rows.removeAll { $0.id == row.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 32)
                                .help("Delete this question")

                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)

                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 340)
            }

            // ── Validation error ─────────────────────────────────────────────
            if let err = validationError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            Divider()
                .padding(.top, 6)

            // ── Footer buttons ───────────────────────────────────────────────
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("\(rows.count) question\(rows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(BlueGlassButtonStyle())
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 440)
        .onAppear { loadExistingRows() }
    }

    // MARK: - Helpers

    private func addRow() {
        let newRow = QuestionRow()
        rows.append(newRow)
        // Focus the label field of the new row after a brief layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedRowID = newRow.id
        }
    }

    /// Pre-populates from existing QuestionStructureMO entries (for edits).
    private func loadExistingRows() {
        guard let pid = paper.id else {
            rows = [QuestionRow()]
            return
        }
        let existing = QuestionStructureMO.fetch(paperID: pid, in: context)
        if existing.isEmpty {
            rows = [QuestionRow()]
        } else {
            rows = existing.map { q in
                var row = QuestionRow()
                row.label    = q.questionLabel ?? ""
                row.maxMarks = "\(q.maxMarks)"
                return row
            }
        }
    }

    // MARK: - Validation

    private var canSave: Bool {
        !rows.isEmpty && rows.allSatisfy {
            !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
                && Int16($0.maxMarks) != nil
                && (Int16($0.maxMarks) ?? 0) > 0
        }
    }

    // MARK: - Save

    private func save() {
        guard !rows.isEmpty else {
            validationError = "Add at least one question before saving."
            return
        }
        for row in rows {
            guard !row.label.trimmingCharacters(in: .whitespaces).isEmpty else {
                validationError = "All question labels must be filled in."
                return
            }
            guard let m = Int16(row.maxMarks), m > 0 else {
                validationError = "Max marks must be a whole number greater than zero."
                return
            }
        }
        validationError = nil

        // Remove existing structures then insert new ones.
        let old = (paper.questionStructures as? Set<QuestionStructureMO>) ?? []
        old.forEach { context.delete($0) }

        var saved: [QuestionStructureMO] = []
        for (idx, row) in rows.enumerated() {
            let q = QuestionStructureMO.insert(
                label:        row.label.trimmingCharacters(in: .whitespaces),
                maxMarks:     Int16(row.maxMarks)!,
                displayOrder: Int16(idx),
                paper:        paper,
                in:           context
            )
            saved.append(q)
        }
        try? context.save()
        onSave(saved)
        dismiss()
    }
}
