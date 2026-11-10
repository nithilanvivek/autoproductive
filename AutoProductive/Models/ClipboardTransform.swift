#if !MODULAR_FEATURES
import Foundation

/// Kept independent of the app UI so the transformation can be built as an
/// optional component and exercised with the same Unicode behavior.
enum ClipboardTransform {
    static func apply(_ text: String, using operation: String) -> String {
        switch operation {
        case "uppercase": text.uppercased()
        case "lowercase": text.lowercased()
        case "trim": text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "titleCase": text.capitalized
        case "sortLines": text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        case "uniqueLines": { var seen = Set<String>(); return text.components(separatedBy: .newlines).filter { seen.insert($0).inserted }.joined(separator: "\n") }()
        default: text
        }
    }
}
#endif
