import SwiftUI
import CoreData

/// Two-column subject management panel.
/// Left pane: sorted list with keyboard delete.
/// Right pane: add-new / rename form.
struct SubjectManagerView: View {

    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name, order: .forward)],
        animation: .smooth(duration: 0.35)
    ) private var subjects: FetchedResults<SubjectMO>

    @State private var selectedID:  NSManagedObjectID?
    @State private var nameField:   String = ""
    @State private var showDeleteConfirm = false

    private var selectedSubject: SubjectMO? {
        guard let id = selectedID else { return nil }
        return subjects.first { $0.objectID == id }
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 220, maxWidth: 300)
            detailPane
                .frame(minWidth: 280)
        }
        .onChange(of: selectedID) { _, _ in
            nameField = selectedSubject?.name ?? ""
        }
        .confirmationDialog(
            "Confirm Deletion",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedSubject?.name ?? "subject")", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let name = selectedSubject?.name {
                Text("Delete \(name)? All papers and attempt records under this subject will be permanently removed.")
            }
        }
    }

    // MARK: - Left list pane

    private var listPane: some View {
        VStack(spacing: 0) {
            // Persistent "New Subject" affordance — always returns the
            // right pane to the add form, even when a subject is selected.
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedID = nil
                    nameField  = ""
                }
            } label: {
                Label("New Subject", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPillButtonStyle())
            .glassEffect(in: Capsule())
            .focusEffectDisabled()
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(subjects, id: \.objectID) { subject in
                        let isSelected = selectedID == subject.objectID
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedID = subject.objectID
                            }
                        } label: {
                            Text(subject.name ?? "")
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                        .animation(.smooth(duration: 0.18), value: isSelected)
                    }
                }
                .padding(8)
            }
            .onKeyPress(phases: .down) { press in
                guard press.key == .delete,
                      press.modifiers.contains(.command),
                      selectedSubject != nil else { return .ignored }
                showDeleteConfirm = true
                return .handled
            }

            Divider()

            // Status bar showing subject count
            HStack {
                Text("\(subjects.count) subject\(subjects.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Text("⌘⌫ to delete")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Right detail / add pane

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sel = selectedSubject {
                editForm(for: sel)
            } else {
                addForm
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Subject")
                .font(.system(size: 13, weight: .semibold))

            // Glass card wrapping the input
            VStack(alignment: .leading, spacing: 10) {
                subjectNameField(placeholder: "Subject name (e.g. P2 Mathematics)")

                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { addSubject() }
                } label: {
                    Label("Add Subject", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(GlassPillButtonStyle())
                .glassEffect(in: Capsule())
                .focusEffectDisabled()
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(nameField.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            .glassEffect(in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func editForm(for subject: SubjectMO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Subject")
                .font(.system(size: 13, weight: .semibold))

            // Glass card wrapping inputs + actions
            VStack(alignment: .leading, spacing: 10) {
                subjectNameField(placeholder: subject.name ?? "")

                HStack(spacing: 8) {
                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { renameSelected() }
                    } label: {
                        Label("Save Changes", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .glassEffect(in: Capsule())
                    .focusEffectDisabled()
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(nameField.trimmingCharacters(in: .whitespaces).isEmpty
                               || nameField == subject.name)

                    Spacer()

                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { showDeleteConfirm = true }
                    } label: {
                        Label("Delete…", systemImage: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .glassEffect(in: Capsule())
                    .focusEffectDisabled()
                }
            }
            .padding(14)
            .glassEffect(in: RoundedRectangle(cornerRadius: 14))

            Divider()
            examDateSection(for: subject)
            Divider()
            paperCountLabel(for: subject)
        }
    }

    @ViewBuilder
    private func examDateSection(for subject: SubjectMO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exam Dates")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            if subject.hasMultiplePaperDates {
                examDateRow("Paper 1 Exam Date", keyPath: \.examDate1, subject: subject)
                examDateRow("Paper 2 Exam Date", keyPath: \.examDate2, subject: subject)
                examDateRow("Paper 3 Exam Date", keyPath: \.examDate3, subject: subject)
                examDateRow("Paper 4 Exam Date", keyPath: \.examDate4, subject: subject)
            } else {
                examDateRow("Exam Date", keyPath: \.examDate1, subject: subject)
            }
        }
    }

    private func examDateRow(
        _ label: String,
        keyPath: ReferenceWritableKeyPath<SubjectMO, Date?>,
        subject: SubjectMO
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            if let date = subject[keyPath: keyPath] {
                DatePicker("", selection: Binding(
                    get: { subject[keyPath: keyPath] ?? Date() },
                    set: { newVal in
                        subject[keyPath: keyPath] = newVal
                        PersistenceController.shared.save()
                    }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

                Button {
                    subject[keyPath: keyPath] = nil
                    PersistenceController.shared.save()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.borderless)
                .help("Clear exam date")
            } else {
                Button("Set Date") {
                    subject[keyPath: keyPath] = Calendar.current.date(
                        byAdding: .month, value: 6, to: Date()) ?? Date()
                    PersistenceController.shared.save()
                }
                .buttonStyle(BlueGlassButtonStyle())
                .controlSize(.small)
            }
        }
    }

    private func subjectNameField(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            TextField(placeholder, text: $nameField)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func paperCountLabel(for subject: SubjectMO) -> some View {
        let papers = (subject.papers?.count ?? 0)
        let attempts = subject.papers?
            .compactMap { ($0 as? PaperMO)?.attempts?.count }
            .reduce(0, +) ?? 0
        return Text("\(papers) paper series · \(attempts) total attempts")
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
    }

    // MARK: - Actions

    private func addSubject() {
        let trimmed = nameField.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        SubjectMO.insert(name: trimmed, in: ctx)
        PersistenceController.shared.save()
        nameField = ""
    }

    private func renameSelected() {
        let trimmed = nameField.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let subj = selectedSubject else { return }
        subj.name = trimmed
        PersistenceController.shared.save()
    }

    private func deleteSelected() {
        guard let subj = selectedSubject else { return }
        selectedID = nil
        nameField  = ""
        ctx.delete(subj)
        PersistenceController.shared.save()
    }
}
