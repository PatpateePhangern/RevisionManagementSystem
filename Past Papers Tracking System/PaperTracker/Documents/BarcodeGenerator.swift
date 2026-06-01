import CoreImage
import AppKit

/// Generates Code-128 barcode images and deterministic ID strings.
struct BarcodeGenerator {

    // MARK: - Barcode ID

    /// Derives a compact, filesystem-safe shortcode from a subject name.
    /// "P2 Mathematics" → "P2MATH"
    /// "Chemistry"       → "CHEMI"
    nonisolated static func subjectShortcode(from name: String) -> String {
        let words = name
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { $0.uppercased().filter { $0.isLetter || $0.isNumber } }

        guard !words.isEmpty else { return String(name.uppercased().filter({ $0.isLetter || $0.isNumber }).prefix(8)) }

        if words.count == 1 {
            return String(words[0].prefix(6))
        }
        return String(words[0].prefix(4)) + String(words[1].prefix(4))
    }

    /// Constructs the canonical human-readable barcode string.
    /// Example: "P2MATH-2025-05-ATT2"
    nonisolated static func buildBarcodeID(
        subjectName: String,
        normalizedSeries: String,
        attemptNumber: Int16
    ) -> String {
        let code = subjectShortcode(from: subjectName)
        return "\(code)-\(normalizedSeries)-ATT\(attemptNumber)"
    }

    // MARK: - Image generation

    /// Generates a Code-128 barcode NSImage suitable for print-resolution output.
    ///
    /// Uses integer-factor scaling to preserve crisp bar edges without anti-aliasing
    /// (equivalent to CGInterpolationQuality.none for raster output).
    nonisolated static func generateImage(for value: String, scaleFactor: CGFloat = 3.0) -> NSImage? {
        guard let ascii = value.data(using: .ascii) else { return nil }

        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(ascii, forKey: "inputMessage")
        filter.setValue(0.0, forKey: "inputQuietSpace")    // no embedded quiet zone; we add our own margins
        filter.setValue(7.0, forKey: "inputBarcodeHeight") // raw module height; scaled below

        guard let rawCI = filter.outputImage else { return nil }

        // Integer scale prevents sub-pixel blurring on the thin bars.
        let scaled = rawCI.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
