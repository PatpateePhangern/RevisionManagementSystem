import Foundation

/// Converts human-readable duration strings to/from a canonical `Int64` seconds
/// representation suitable for storage in `AttemptMO.durationInSeconds`.
///
/// **Supported input formats**
/// | Example input   | Seconds |
/// |-----------------|---------|
/// | `1h 30m`        | 5 400   |
/// | `90m`           | 5 400   |
/// | `1:30:00`       | 5 400   |
/// | `45m 15s`       | 2 715   |
/// | `2h`            | 7 200   |
/// | `30s`           | 30      |
/// | `1h30m`         | 5 400   |
struct DurationParser {

    // MARK: - Parse

    /// Parses an arbitrary duration string into total seconds, or nil if
    /// the string cannot be understood.
    nonisolated static func parse(_ input: String) -> Int64? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // ── Try HH:MM:SS or MM:SS ────────────────────────────────────────────
        if let colonResult = parseColonFormat(s) { return colonResult }

        // ── Try component shorthand (1h 30m 15s) ───────────────────────────
        if let shortResult = parseShorthandFormat(s) { return shortResult }

        return nil
    }

    // MARK: - Format

    /// Converts total seconds to a compact human-readable string.
    /// - 5 400 → "1h 30m"
    /// - 90  → "1m 30s"
    /// - 3 600 → "1h"
    /// - 30 → "30s"
    nonisolated static func format(_ totalSeconds: Int64) -> String {
        guard totalSeconds > 0 else { return "0s" }

        let hours   = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if hours   > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 { parts.append("\(seconds)s") }

        return parts.joined(separator: " ")
    }

    // MARK: - Private helpers

    /// Handles `HH:MM:SS` and `MM:SS`.
    nonisolated private static func parseColonFormat(_ s: String) -> Int64? {
        let components = s.split(separator: ":", omittingEmptySubsequences: false)
        switch components.count {
        case 3:
            guard let h = Int64(components[0].trimmingCharacters(in: .whitespaces)),
                  let m = Int64(components[1].trimmingCharacters(in: .whitespaces)),
                  let sec = Int64(components[2].trimmingCharacters(in: .whitespaces)),
                  m < 60, sec < 60 else { return nil }
            return h * 3600 + m * 60 + sec
        case 2:
            guard let m = Int64(components[0].trimmingCharacters(in: .whitespaces)),
                  let sec = Int64(components[1].trimmingCharacters(in: .whitespaces)),
                  sec < 60 else { return nil }
            return m * 60 + sec
        default:
            return nil
        }
    }

    /// Handles `1h 30m`, `90m`, `45m 15s`, `2h`, `30s`, `1h30m`.
    nonisolated private static func parseShorthandFormat(_ s: String) -> Int64? {
        var total: Int64 = 0
        var matched = false

        // Order matters — hours then minutes then seconds.
        let patterns: [(pattern: String, factor: Int64)] = [
            (#"(\d+)\s*h(?:ours?)?"#, 3600),
            (#"(\d+)\s*m(?:in(?:utes?)?)?"#, 60),
            (#"(\d+)\s*s(?:ec(?:onds?)?)?"#, 1),
        ]

        for (pattern, factor) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                        options: .caseInsensitive) else { continue }
            let range = NSRange(s.startIndex..., in: s)
            if let match = regex.firstMatch(in: s, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: s),
               let value = Int64(s[r]) {
                total  += value * factor
                matched = true
            }
        }

        return matched ? total : nil
    }
}
