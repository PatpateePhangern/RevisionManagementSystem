import Foundation

/// Helper for extracting paper number and variant from a normalised series string.
/// CS series format: "YYYY-MM-P#V#"  (e.g. "2025-05-P1V2")
/// Non-CS series format: "YYYY-MM"    (e.g. "2025-05") — returns nil for both.
struct SeriesFilterHelper {

    /// Returns "P1", "P2", etc. from a normalised series, or nil if no paper component exists.
    static func paperLabel(from normalized: String) -> String? {
        guard let n = paperNumber(from: normalized) else { return nil }
        return "P\(n)"
    }

    /// Returns "V1", "V2", etc. from a normalised series, or nil if no variant component exists.
    static func variantLabel(from normalized: String) -> String? {
        guard let n = variantNumber(from: normalized) else { return nil }
        return "V\(n)"
    }

    /// Extracts the integer paper number from "YYYY-MM-P#V#". Returns nil if absent.
    static func paperNumber(from normalized: String) -> Int? {
        let parts = normalized.split(separator: "-", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        let suffix = String(parts[2])
        guard suffix.hasPrefix("P"),
              let vIdx = suffix.firstIndex(of: "V") else { return nil }
        let pStr = String(suffix[suffix.index(after: suffix.startIndex)..<vIdx])
        return Int(pStr)
    }

    /// Extracts the integer variant number from "YYYY-MM-P#V#". Returns nil if absent.
    static func variantNumber(from normalized: String) -> Int? {
        let parts = normalized.split(separator: "-", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        let suffix = String(parts[2])
        guard suffix.hasPrefix("P"),
              let vIdx = suffix.firstIndex(of: "V") else { return nil }
        let vStr = String(suffix[suffix.index(after: vIdx)...])
        return Int(vStr)
    }
}
