import Foundation
import Carbon

enum ShortcutRatingLevel: String {
    case blocked = "Blocked"
    case crowded = "Crowded"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    var symbol: String {
        switch self {
        case .blocked: "xmark.octagon.fill"
        case .crowded: "exclamationmark.triangle.fill"
        case .fair: "circle.lefthalf.filled"
        case .good: "checkmark.circle.fill"
        case .excellent: "sparkles"
        }
    }
}

struct ShortcutRating {
    let level: ShortcutRatingLevel
    let score: Int
    let detail: String
}

enum ShortcutAnalyzer {
    static func rate(
        _ shortcut: KeyboardShortcutDefinition,
        comparedWith existingShortcuts: [KeyboardShortcutDefinition]
    ) -> ShortcutRating {
        if let reason = conflictReason(shortcut, comparedWith: existingShortcuts) {
            return ShortcutRating(level: .blocked, score: 0, detail: reason)
        }

        let modifierCount = shortcut.modifiers.rawValue.nonzeroBitCount
        let key = shortcut.keyLabel.uppercased()
        let commonCommandKeys: Set<String> = [
            "A", "C", "F", "H", "M", "N", "O", "P", "Q", "S", "V", "W", "X", "Z", "⇥", "Space"
        ]

        if shortcut.modifiers == .command && commonCommandKeys.contains(key) {
            return ShortcutRating(
                level: .crowded,
                score: 25,
                detail: "A standard app shortcut used widely across macOS. Choose more modifiers."
            )
        }

        if modifierCount == 1 {
            return ShortcutRating(
                level: .fair,
                score: 55,
                detail: "Easy to remember, but a single modifier has a higher collision risk."
            )
        }

        if modifierCount == 2 {
            return ShortcutRating(
                level: .good,
                score: 82,
                detail: "Low collision risk and still comfortable to press."
            )
        }

        return ShortcutRating(
            level: .excellent,
            score: 96,
            detail: "Very unlikely to conflict with system or application shortcuts."
        )
    }

    static func conflictReason(
        _ shortcut: KeyboardShortcutDefinition,
        comparedWith existingShortcuts: [KeyboardShortcutDefinition],
        probeRegistration: Bool = false
    ) -> String? {
        if existingShortcuts.contains(where: { $0.keyCode == shortcut.keyCode && $0.modifiers == shortcut.modifiers }) {
            return "That shortcut already belongs to another AutoProductive automation."
        }
        if shortcut.keyCode == 47 && shortcut.modifiers == [.control, .option, .command] {
            return "This is AutoProductive’s emergency pause shortcut."
        }
        var raw: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&raw) == noErr, let entries = raw?.takeRetainedValue() as? [[String: Any]] {
            for entry in entries {
                guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                      let code = entry[kHISymbolicHotKeyCode as String] as? NSNumber,
                      let flags = entry[kHISymbolicHotKeyModifiers as String] as? NSNumber else { continue }
                if code.uint32Value == shortcut.keyCode && modifiers(fromCarbon: flags.uint32Value) == shortcut.modifiers {
                    return "This combination is enabled in macOS Keyboard Shortcuts settings. Choose another."
                }
            }
        }
        let character = keyCharacter(shortcut.keyCode)
        if !character.isEmpty {
            // Only inspect domains explicitly listed by App Shortcuts settings.
            // Sweeping every preference domain can trigger unrelated privacy
            // prompts (for example Music) even when requesting just this key.
            let configuredApps = CFPreferencesCopyValue("com.apple.custommenu.apps" as CFString, "com.apple.universalaccess" as CFString,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
            let domains = configuredApps + [UserDefaults.globalDomain]
            for domain in Set(domains) {
                if let bindings = CFPreferencesCopyValue("NSUserKeyEquivalents" as CFString, domain as CFString,
                                                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: String] {
                    for (command, equivalent) in bindings where matches(equivalent, character: character, modifiers: shortcut.modifiers) {
                        return "Already assigned to “\(command)” in App Shortcuts (\(domain == UserDefaults.globalDomain ? "All Applications" : domain))."
                    }
                }
            }
            if let services = CFPreferencesCopyValue("NSServicesStatus" as CFString, "pbs" as CFString,
                                                    kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: [String: Any]] {
                for entry in services.values {
                    if let equivalent = entry["key_equivalent"] as? String,
                       matches(equivalent, character: character, modifiers: shortcut.modifiers) {
                        return "This combination is assigned to a service in Keyboard Shortcuts settings."
                    }
                }
            }
        }
        if probeRegistration {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, carbonModifiers(shortcut.modifiers),
                EventHotKeyID(signature: 0x41555054, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
            if let reference { UnregisterEventHotKey(reference) }
            if status == eventHotKeyExistsErr { return "Another running app already registered this global shortcut. Choose another." }
            if status != noErr { return "macOS cannot register this shortcut (error \(status)). Choose another combination." }
        }
        return nil
    }

    static func matches(_ equivalent: String, character: String, modifiers: ShortcutModifiers) -> Bool {
        var value = equivalent[...]
        var required: ShortcutModifiers = []
        while let first = value.first {
            switch first {
            case "@": required.insert(.command)
            case "^": required.insert(.control)
            case "~": required.insert(.option)
            case "$": required.insert(.shift)
            default:
                let key = String(value)
                if key.count == 1 && key != key.lowercased() { required.insert(.shift) }
                return required == modifiers && key.lowercased() == character.lowercased()
            }
            value = value.dropFirst()
        }
        return false
    }

    private static func keyCharacter(_ code: UInt32) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return "" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let result = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKey, characters.count, &length, &characters)
        return result == noErr ? String(utf16CodeUnits: characters, count: length) : ""
    }

    static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func modifiers(fromCarbon flags: UInt32) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags & UInt32(cmdKey) != 0 { result.insert(.command) }
        if flags & UInt32(controlKey) != 0 { result.insert(.control) }
        if flags & UInt32(optionKey) != 0 { result.insert(.option) }
        if flags & UInt32(shiftKey) != 0 { result.insert(.shift) }
        return result
    }
}
