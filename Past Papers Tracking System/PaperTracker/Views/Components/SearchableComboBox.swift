import SwiftUI

/// Subject field with:
///   - Inline grey predictive completion (strict prefix match, ghost text overlay)
///   - Keyboard-navigable dropdown built from Button primitives (no gesture collision)
///   - Return confirms inline match, dismisses overlay, fires `onConfirm` to advance focus
///   - Down / Up arrows highlight rows without leaving the text field
///   - Escape dismisses without committing
///   - Liquid-glass dropdown panel with smooth spring animation
struct SearchableComboBox: View {

    @Binding var text: String
    @Binding var selectedSubject: SubjectMO?
    let subjects: [SubjectMO]
    var placeholder: String = "Type subject name…"
    /// Fired after a subject is confirmed — use it to advance keyboard focus.
    var onConfirm: (() -> Void)? = nil
    /// When true the text field steals focus as soon as the view appears.
    var autoFocus: Bool = false

    @FocusState private var fieldFocused: Bool
    @State private var showDropdown:    Bool = false
    @State private var highlightedIndex: Int? = nil

    // MARK: - Derived

    private var filtered: [SubjectMO] {
        guard !text.isEmpty else { return subjects }
        return subjects.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    private var inlineMatch: SubjectMO? {
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        return subjects.first { ($0.name ?? "").lowercased().hasPrefix(lower) }
    }

    private var completionSuffix: String {
        guard let name = inlineMatch?.name, name.count > text.count else { return "" }
        return String(name.dropFirst(text.count))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            inputField
                .onAppear {
                    if autoFocus {
                        // One run-loop delay so the sheet has finished presenting
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            fieldFocused = true
                        }
                    }
                }
            if showDropdown && !filtered.isEmpty {
                dropdownPanel
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.96, anchor: .top)
                                .combined(with: .opacity),
                            removal:   .scale(scale: 0.96, anchor: .top)
                                .combined(with: .opacity)
                        )
                    )
                    .zIndex(99)
            }
        }
        .animation(.smooth(duration: 0.22), value: showDropdown)
    }

    // MARK: - Input field

    private var inputField: some View {
        ZStack(alignment: .leading) {

            // Ghost layer
            if !completionSuffix.isEmpty {
                HStack(spacing: 0) {
                    Text(text)
                        .foregroundStyle(.clear)
                    Text(completionSuffix)
                        .foregroundStyle(Color(nsColor: .disabledControlTextColor))
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
            }

            // Live field
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .focused($fieldFocused)
                .onChange(of: text) { _, newVal in
                    if selectedSubject?.name == newVal { showDropdown = false; return }
                    selectedSubject  = nil
                    showDropdown     = !newVal.isEmpty
                    highlightedIndex = nil
                }
                .onSubmit {
                    if let idx = highlightedIndex, idx < filtered.count {
                        confirm(filtered[idx])
                    } else if let match = inlineMatch {
                        confirm(match)
                    }
                }
                .onKeyPress(.downArrow) {
                    guard !filtered.isEmpty else { return .ignored }
                    showDropdown     = true
                    highlightedIndex = highlightedIndex.map { min($0 + 1, filtered.count - 1) } ?? 0
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard let idx = highlightedIndex else { return .ignored }
                    highlightedIndex = idx > 0 ? idx - 1 : nil
                    return .handled
                }
                .onKeyPress(.escape) {
                    showDropdown     = false
                    highlightedIndex = nil
                    return .handled
                }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    fieldFocused
                        ? Color.accentColor.opacity(0.80)
                        : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: fieldFocused ? 1.5 : 0.5
                )
        )
        .animation(.smooth(duration: 0.18), value: fieldFocused)
    }

    // MARK: - Dropdown panel

    private var dropdownPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element.objectID) { idx, subject in
                    dropdownRow(subject: subject, index: idx)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 210)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Dropdown row

    private func dropdownRow(subject: SubjectMO, index: Int) -> some View {
        Button {
            confirm(subject)
        } label: {
            HStack(spacing: 0) {
                Text(subject.name ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background {
                if highlightedIndex == index {
                    Color.clear
                        .glassEffect(in: RoundedRectangle(cornerRadius: 7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPillButtonStyle())
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.15)) {
                highlightedIndex = isHovered ? index : nil
            }
        }
        .overlay(alignment: .bottom) {
            if index < filtered.count - 1 {
                Divider()
                    .padding(.leading, 12)
                    .opacity(0.4)
            }
        }
    }

    // MARK: - Commit

    private func confirm(_ subject: SubjectMO) {
        selectedSubject  = subject
        text             = subject.name ?? ""
        showDropdown     = false
        highlightedIndex = nil
        fieldFocused     = false
        // Delay onConfirm by one run-loop so the field can finish resigning
        // focus before the caller tries to set focus on the next field.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            onConfirm?()
        }
    }
}
