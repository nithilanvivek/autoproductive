import AppKit

enum KeyboardKeyLabel {
    static func definition(for event: NSEvent) -> KeyboardShortcutDefinition {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 115: "↖",
            116: "⇞", 117: "⌦", 119: "↘", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        // charactersIgnoringModifiers still includes Shift. Translate the physical
        // key with no modifiers so ⇧⌘8 is not displayed as ⇧⌘*.
        let base = event.characters(byApplyingModifiers: [])?.uppercased()
        let label = special[event.keyCode] ?? (base?.isEmpty == false ? base! : "Key \(event.keyCode)")
        return .init(keyCode: UInt32(event.keyCode), keyLabel: label, modifiers: modifiers)
    }
}
