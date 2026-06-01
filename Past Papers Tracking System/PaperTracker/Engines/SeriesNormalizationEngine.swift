import Foundation

/// Converts diverse exam-series strings into a canonical YYYY-MM index key.
struct SeriesNormalizationEngine {

    // MARK: - Public API

    /// Returns "YYYY-MM" or nil if neither a year nor a month can be extracted.
    nonisolated static func normalize(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Fast path: already in YYYY-MM form.
        if matchesISO(s) { return s }

        guard let year = extractYear(from: s) else { return nil }
        guard let month = extractMonth(from: s) else { return nil }
        return "\(year)-\(month)"
    }

    /// Converts "2025-05" → "May/Jun 2025", "2025-06" → "May/Jun 2025",
    /// "2024-10" → "Oct/Nov 2024", "2024-11" → "Oct/Nov 2024",
    /// and so on for other months.
    /// Also handles CS compound keys: "2025-05-P1V2" → "May/Jun 2025 · P1 · V2".
    nonisolated static func displayName(from normalized: String) -> String {
        // maxSplits: 2 → at most three substrings; "YYYY-MM-P#V#" gives exactly three.
        let parts = normalized.split(separator: "-", maxSplits: 2)
        if parts.count == 3,
           let suffix = parts.last,
           suffix.hasPrefix("P"),
           let vIdx = suffix.firstIndex(of: "V") {
            let base        = "\(parts[0])-\(parts[1])"
            let baseName    = displayName(from: base)
            let paperStr    = String(suffix[suffix.index(after: suffix.startIndex)..<vIdx])
            let variantStr  = String(suffix[suffix.index(after: vIdx)...])
            return "\(baseName) · P\(paperStr) · V\(variantStr)"
        }
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return normalized }
        // Cambridge paired sessions: May/Jun and Oct/Nov share the same display label.
        let names = ["", "January", "February", "March", "April",
                     "May/June", "May/June",           // 05 and 06
                     "July", "August", "September",
                     "Oct/Nov", "Oct/Nov",           // 10 and 11
                     "December"]
        return "\(names[m]) \(parts[0])"
    }

    /// Builds a compound normalized key for CS variant papers.
    /// `baseSeries` must already be in "YYYY-MM" form.
    /// Returns "YYYY-MM-P#V#" — e.g. "2025-05-P1V2".
    nonisolated static func normalizeCSVariant(
        baseSeries: String,
        paperNumber: Int,
        variantNumber: Int
    ) -> String {
        "\(baseSeries)-P\(paperNumber)V\(variantNumber)"
    }

    // MARK: - Private helpers

    nonisolated private static func matchesISO(_ s: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func extractYear(from s: String) -> String? {
        // Prefer explicit 4-digit year.
        let fourDigit = #"\b(20\d{2})\b"#
        if let r = s.range(of: fourDigit, options: .regularExpression),
           let capture = captureGroup(1, in: s, pattern: fourDigit) {
            _ = r
            return capture
        }
        // Accept apostrophe-shorthand or bare 2-digit: "'25" or " 25".
        let twoDigit = #"(?:^|\s|')[''']?(\d{2})\b"#
        if let yy = captureGroup(1, in: s, pattern: twoDigit) {
            return "20\(yy)"
        }
        return nil
    }

    nonisolated private static func extractMonth(from s: String) -> String? {
        let lower = s.lowercased()
        // Ordered most-specific first to prevent prefix collisions (e.g. "jun" vs "jul").
        // Cambridge paired-session shorthands must appear BEFORE the individual month
        // patterns so they are matched first.
        let table: [(String, String)] = [
            // ── Cambridge paired session compounds ───────────────────────────
            // May/June and any variant  →  canonical month 05 (May)
            (#"may[/\-]jun(?:e)?\b|m[/\-]j\b"#,   "05"),
            // Oct/Nov and any variant   →  canonical month 10 (October)
            (#"oct[/\-]nov\b|o[/\-]n\b"#,          "10"),
            // ── Individual months ────────────────────────────────────────────
            (#"\bjanuary\b|\bjan\b"#,   "01"),
            (#"\bfebruary\b|\bfeb\b"#,  "02"),
            (#"\bmarch\b|\bmar\b"#,     "03"),
            (#"\bapril\b|\bapr\b"#,     "04"),
            (#"\bmay\b"#,               "05"),
            (#"\bjune\b|\bjun\b"#,      "06"),
            (#"\bjuly\b|\bjul\b"#,      "07"),
            (#"\baugust\b|\baug\b"#,    "08"),
            (#"\bseptember\b|\bsept\b|\bsep\b"#, "09"),
            (#"\boctober\b|\boct\b"#,   "10"),
            (#"\bnovember\b|\bnov\b"#,  "11"),
            (#"\bdecember\b|\bdec\b"#,  "12"),
            // Single-letter shorthand used in exam board notation.
            (#"\bm\b"#,  "05"),   // M = May
            (#"\bo\b"#,  "10"),   // O = October
            (#"\bn\b"#,  "11"),   // N = November
        ]
        for (pattern, month) in table {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return month
            }
        }
        return nil
    }

    // MARK: - Paired-month search helper

    /// Returns all normalized series keys that are equivalent to `normalized` for
    /// search purposes. Cambridge paired sessions mean months 05 ↔ 06 and 10 ↔ 11
    /// are treated as the same exam session.
    ///
    /// Example: "2025-05" → ["2025-05", "2025-06"]
    nonisolated static func equivalentKeys(for normalized: String) -> [String] {
        let parts = normalized.split(separator: "-", maxSplits: 2)
        guard parts.count == 2, let m = Int(parts[1]) else { return [normalized] }
        let year = String(parts[0])
        switch m {
        case 5:  return ["\(year)-05", "\(year)-06"]
        case 6:  return ["\(year)-05", "\(year)-06"]
        case 10: return ["\(year)-10", "\(year)-11"]
        case 11: return ["\(year)-10", "\(year)-11"]
        default: return [normalized]
        }
    }

    // MARK: - Regex utility

    nonisolated private static func captureGroup(_ group: Int, in s: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: s) else { return nil }
        return String(s[r])
    }
}
