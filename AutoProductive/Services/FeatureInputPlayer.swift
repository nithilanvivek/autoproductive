import AppKit
import ApplicationServices

@MainActor
enum FeatureInputPlayer {
    /// Kept in the app process so synthetic input uses the same accessibility
    /// permission and event tag as existing automations.
    static func play(_ plan: FeatureInputPlan) async throws {
        try plan.validate()
        try DesktopAutomationService.requireAccessibility()
        for event in plan.events {
            try Task.checkCancellation()
            switch event.kind {
            case "key":
                let modifiers = ShortcutModifiers(rawValue: event.modifiers!)
                for down in [true, false] {
                    if let key = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                                         virtualKey: CGKeyCode(event.keyCode!), keyDown: down) {
                        key.flags = DesktopAutomationService.flags(for: modifiers)
                        DesktopAutomationService.post(key)
                    }
                }
            case "unicode":
                for (characterIndex, character) in event.text!.enumerated() {
                    try Task.checkCancellation()
                    if characterIndex.isMultiple(of: 32) { try await Task.sleep(for: .milliseconds(2)) }
                    let units = Array(String(character).utf16)
                    for down in [true, false] {
                        if let key = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 0, keyDown: down) {
                            key.flags = []
                            key.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                            DesktopAutomationService.post(key)
                        }
                    }
                }
            case "click", "move":
                let point = CGPoint(x: event.x!, y: event.y!)
                let button: CGMouseButton = event.button == "right" ? .right : event.button == "middle" ? .center : .left
                let down: CGEventType = button == .right ? .rightMouseDown : button == .center ? .otherMouseDown : .leftMouseDown
                let up: CGEventType = button == .right ? .rightMouseUp : button == .center ? .otherMouseUp : .leftMouseUp
                for kind in event.kind == "move" ? [CGEventType.mouseMoved] : [down, up] {
                    if let mouse = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState), mouseType: kind, mouseCursorPosition: point, mouseButton: button) {
                        DesktopAutomationService.post(mouse)
                    }
                }
            case "scroll":
                if let scroll = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .privateState), units: .pixel,
                                        wheelCount: 2, wheel1: Int32(event.y!), wheel2: Int32(event.x!), wheel3: 0) {
                    DesktopAutomationService.post(scroll)
                }
            default: throw FeatureInputPlan.PlanError.invalid
            }
        }
    }
}
