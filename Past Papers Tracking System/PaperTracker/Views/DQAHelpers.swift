import Foundation
import AppKit

// MARK: - Gregorian date formatters
// Prevents the Thai Buddhist-Era year (e.g., 2569) appearing when the system
// locale is set to Thailand.  Always lock DQA date output to en_GB + Gregorian.

extension DateFormatter {

    /// Returns a DateFormatter with en_GB locale, Gregorian calendar, and the
    /// given dateStyle / timeStyle.
    static func dqaGregorian(dateStyle: DateFormatter.Style,
                             timeStyle: DateFormatter.Style = .none) -> DateFormatter {
        let f = DateFormatter()
        f.locale    = Locale(identifier: "en_GB")
        f.calendar  = Calendar(identifier: .gregorian)
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        return f
    }

    /// Returns a DateFormatter with en_GB locale, Gregorian calendar, and the
    /// given dateFormat string.
    static func dqaGregorianFormat(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_GB")
        f.calendar   = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }
}

// MARK: - Question label display conversion

/// Converts the stored internal page-range token to a human-readable string.
///
/// Examples:
///   `"Q3 [pp.8-11]"` → `"Q3 Pages 8–11"`
///   `"Q1 [p.4]"`     → `"Q1 Page 4"`
///
/// Non-matching labels are returned unchanged.
func dqaDisplayLabel(_ raw: String) -> String {
    var result = raw

    // Multi-page range: [pp.X-Y]  →  (Pages X–Y)
    if let re = try? NSRegularExpression(pattern: #"\[pp\.(\d+)-(\d+)\]"#) {
        var offset = 0
        let ns      = result as NSString
        let matches = re.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let s   = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let e   = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let rep = "(Pages \(s)–\(e))"
            let adj = NSRange(location: m.range.location + offset, length: m.range.length)
            result  = (result as NSString).replacingCharacters(in: adj, with: rep)
            offset += rep.count - m.range.length
        }
    }

    // Single page: [p.X]  →  (Page X)
    if let re = try? NSRegularExpression(pattern: #"\[p\.(\d+)\]"#) {
        var offset = 0
        let ns      = result as NSString
        let matches = re.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let p   = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let rep = "(Page \(p))"
            let adj = NSRange(location: m.range.location + offset, length: m.range.length)
            result  = (result as NSString).replacingCharacters(in: adj, with: rep)
            offset += rep.count - m.range.length
        }
    }

    return result
}
