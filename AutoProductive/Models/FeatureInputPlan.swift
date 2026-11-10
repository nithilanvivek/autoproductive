import Foundation

/// Components describe input; the main app validates and posts it so existing
/// accessibility permissions and the synthetic-input tag stay with the app.
struct FeatureInputPlan: Codable {
    struct Event: Codable {
        let kind: String
        var keyCode: UInt32? = nil
        var modifiers: UInt? = nil
        var text: String? = nil
        var x: Double? = nil
        var y: Double? = nil
        var button: String? = nil
    }
    let events: [Event]

    func validate() throws {
        guard events.count <= 1_000_000 else { throw PlanError.invalid }
        for event in events {
            switch event.kind {
            case "key":
                guard let code = event.keyCode, code <= UInt16.max,
                      let flags = event.modifiers, flags <= 15 else { throw PlanError.invalid }
            case "unicode":
                guard let text = event.text, !text.isEmpty, text.utf16.count <= 20 * 1024 * 1024 else { throw PlanError.invalid }
            case "click", "move":
                guard let x = event.x, let y = event.y, x.isFinite, y.isFinite,
                      abs(x) <= 100_000, abs(y) <= 100_000,
                      ["left", "right", "middle"].contains(event.button ?? "") else { throw PlanError.invalid }
            case "scroll":
                guard let x = event.x, let y = event.y, x.isFinite, y.isFinite,
                      (-10_000...10_000).contains(x), (-10_000...10_000).contains(y) else { throw PlanError.invalid }
            default: throw PlanError.invalid
            }
        }
    }
    enum PlanError: LocalizedError {
        case invalid
        var errorDescription: String? { "The input component returned an invalid action." }
    }
}
