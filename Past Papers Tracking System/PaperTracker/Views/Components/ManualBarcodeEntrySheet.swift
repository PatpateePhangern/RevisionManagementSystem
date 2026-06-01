import SwiftUI

/// Modal sheet presented when Vision scanning fails or produces inconsistent reads.
/// Automatically focuses the text field so the user can type without a mouse click.
struct ManualBarcodeEntrySheet: View {

    @Binding var isPresented: Bool
    let onConfirm: (String) -> Void

    @State private var input: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual Barcode Entry")
                .font(.headline)

            Text("Barcode could not be read automatically. Enter the reference string printed below the barcode.")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            TextField("e.g. P2MATH-2025-05-ATT2", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($fieldFocused)
                .onSubmit { commit() }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Confirm") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { fieldFocused = true }
    }

    private func commit() {
        let v = input.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        onConfirm(v)
        isPresented = false
    }
}
