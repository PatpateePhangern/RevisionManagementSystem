import SwiftUI
import AppKit

/// Modal verification sheet shown immediately after a PDF is scanned.
///
/// Displays the cropped checkbox region extracted from the PDF so the user can
/// visually confirm which box was marked, then manually select the paper type.
/// Automatic pixel-level detection has been intentionally removed — the image
/// gives the user all the information they need without false positives.
struct ValidationPaneView: View {

    let scanResult: ScanResult
    @Binding var isPresented: Bool
    /// Called with "practice" or "timed" when the user confirms.
    let onConfirm: (String) -> Void

    @State private var selectedType: String

    init(
        scanResult:  ScanResult,
        isPresented: Binding<Bool>,
        onConfirm:   @escaping (String) -> Void
    ) {
        self.scanResult   = scanResult
        self._isPresented = isPresented
        self.onConfirm    = onConfirm
        // Pre-select "practice" by default (user must actively choose Timed & Graded).
        self._selectedType = State(initialValue: scanResult.inferredPaperType ?? "practice")
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Verify Paper Type")
                        .font(.system(size: 14, weight: .semibold))
                    Text(scanResult.barcodeValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // ── Main content ──────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {

                // Left: checkbox region extracted from the PDF
                VStack(alignment: .leading, spacing: 10) {
                    Text("CHECKBOX REGION FROM PDF")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .tracking(0.8)

                    if let regionImage = scanResult.checkboxRegionImage {
                        // Use CGImage directly (scale: 2.0 because the page was
                        // rendered at 2×) to avoid the NSImage y-axis flip issue.
                        Image(decorative: regionImage, scale: 2.0)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 300)
                            .background(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 300, height: 64)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                    Text("No preview available\n(manual entry)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                        .multilineTextAlignment(.center)
                                }
                            )
                    }

                    Text("Review the checkbox marks above and\nselect the correct paper type on the right.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300)
                }
                .padding(20)

                Divider()

                // Right: manual selection radio buttons
                VStack(alignment: .leading, spacing: 14) {
                    Text("PAPER TYPE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .tracking(0.8)

                    typeButton(label: "Practice Paper",
                               icon:  "doc.text",
                               value: "practice")

                    typeButton(label: "Timed & Graded",
                               icon:  "clock.badge.checkmark",
                               value: "timed")

                    Spacer()

                    Text("Select the type that matches the\nmark on the physical paper.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(minWidth: 190)
            }

            Divider()

            // ── Action row ────────────────────────────────────────────────────
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Proceed") { confirm() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(BlueGlassButtonStyle())
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Sub-views

    /// Radio-button-style row that uses an `onTapGesture` rather than `Button`
    /// to avoid macOS focus rings staying visible after a click.
    @ViewBuilder
    private func typeButton(label: String, icon: String, value: String) -> some View {
        let isSelected = selectedType == value
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected
                                 ? Color(nsColor: .controlAccentColor)
                                 : Color(nsColor: .tertiaryLabelColor))
                .font(.system(size: 16))

            Label(label, systemImage: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .labelColor))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            isSelected
                ? Color(nsColor: .selectedControlColor).opacity(0.25)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { selectedType = value }
    }

    // MARK: - Actions

    private func confirm() {
        onConfirm(selectedType)
        isPresented = false
    }
}
