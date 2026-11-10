import AppKit

/// Converts observations to saved actions. It never posts or changes input.
struct MacroRecordingBuffer {
    private(set) var actions: [WorkflowStep] = []
    private var previousTime: TimeInterval?
    static let maximumActions = 198

    /// Returns true when the explicit stop key or the action limit ends capture.
    mutating func observe(_ event: CGEvent, isOwnEvent: Bool, secureInput: Bool,
                          playbackTag: Int64) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != playbackTag else { return false }
        let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
        if event.type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == 53,
           modifiers == [.maskControl, .maskAlternate] { return true }
        guard !isOwnEvent, !secureInput else { return false }

        var step: WorkflowStep
        switch event.type {
        case .keyDown:
            guard let key = NSEvent(cgEvent: event) else { return false }
            step = WorkflowStep(action: .pressKey)
            step.key = KeyboardKeyLabel.definition(for: key)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            step = WorkflowStep(action: .click, option: event.type == .rightMouseDown ? "right" : event.type == .otherMouseDown ? "middle" : "left")
            step.x = event.location.x; step.y = event.location.y
        case .scrollWheel:
            guard let scroll = NSEvent(cgEvent: event) else { return false }
            step = WorkflowStep(action: .scroll)
            step.x = scroll.scrollingDeltaX; step.y = scroll.scrollingDeltaY
        default: return false
        }
        guard actions.count < Self.maximumActions else { return true }
        let time = TimeInterval(event.timestamp) / 1_000_000_000
        if let previousTime, time - previousTime >= 0.1 {
            var delay = WorkflowStep(action: .wait)
            delay.duration = min(300, time - previousTime)
            actions.append(delay)
        }
        previousTime = time
        actions.append(step)
        return actions.count >= Self.maximumActions
    }
}
