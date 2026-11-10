import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct KeyboardShortcutDefinition: Codable, Hashable, Sendable {
    let keyCode: UInt32
    let keyLabel: String
    let modifiers: ShortcutModifiers

    var displayText: String {
        modifiers.symbols + keyLabel
    }
}

enum AutomationKind: String, Codable, CaseIterable, Identifiable {
    case sequence
    case openApp
    case composeMail
    case workflow, clickingKeyboard, textExpansion, keyRemap, windows, clipboard, files, script, dialog, screen, touchpad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequence: "Trigger a Sequence of Actions"
        case .openApp: "Open App"
        case .composeMail: "Compose Mail"
        case .workflow: "Custom Event Sequence"
        case .clickingKeyboard: "Clicking + Keyboard"
        case .textExpansion: "Text Trigger"
        case .keyRemap: "Remap Keys"
        case .windows: "Arrange Windows"
        case .clipboard: "Clipboard Tools"
        case .files: "Files & Folders"
        case .script: "Run a Script"
        case .dialog: "Forms & Menus"
        case .screen: "Screen Conditions"
        case .touchpad: "Touchpad Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .sequence: "Choose triggers, then run any combination of actions in order"
        case .openApp: "Launch any application on your Mac"
        case .composeMail: "Prepare an email in your default mail app"
        case .workflow: "Combine typing, clicks, scrolling and delays"
        case .clickingKeyboard: "Build screen clicks, typed text and shortcuts step by step"
        case .textExpansion: "Type a phrase to insert text or run an action"
        case .keyRemap: "Give a key or mouse button a new action or shorten long keyboard commands."
        case .windows: "Move, resize, focus and minimize windows"
        case .clipboard: "Transform, copy and paste text"
        case .files: "Read, write, copy and organize local files"
        case .script: "Run shell commands or AppleScript"
        case .dialog: "Ask for input and show custom choices"
        case .screen: "Run when a pixel or image appears"
        case .touchpad: "Trigger actions with modified two-finger swipes"
        }
    }

    var symbol: String {
        switch self {
        case .sequence: "bolt.horizontal.circle.fill"
        case .openApp: "square.grid.2x2.fill"
        case .composeMail: "envelope.fill"
        case .workflow: "keyboard"
        case .clickingKeyboard: "cursorarrow.click.2"
        case .textExpansion: "text.word.spacing"
        case .keyRemap: "arrow.triangle.swap"
        case .windows: "macwindow.on.rectangle"
        case .clipboard: "doc.on.clipboard"
        case .files: "folder.fill"
        case .script: "terminal.fill"
        case .dialog: "rectangle.and.pencil.and.ellipsis"
        case .screen: "viewfinder"
        case .touchpad: "hand.draw.fill"
        }
    }

    var tintName: String {
        switch self {
        case .openApp: "blue"
        case .composeMail: "indigo"
        default: "blue"
        }
    }
}

struct SavedAutomation: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: AutomationKind
    var appPath: String?
    var recipient: String
    var subject: String
    var message: String
    var keyboardShortcut: KeyboardShortcutDefinition?
    var appScopeBundleIdentifier: String
    /// Nil means this automation predates multiple-app scope support.
    var appScopeBundleIdentifiers: [String]?
    var scopedAppBundleIdentifiers: [String] {
        get { appScopeBundleIdentifiers ?? (appScopeBundleIdentifier.isEmpty ? [] : [appScopeBundleIdentifier]) }
        set { appScopeBundleIdentifiers = AppScope.normalized(newValue); appScopeBundleIdentifier = "" }
    }
    var siriEnabled: Bool
    var createdAt: Date
    var workflow: WorkflowDefinition?
    private var enabled = true
    var isEnabled: Bool {
        get { workflow?.isEnabled ?? enabled }
        set { enabled = newValue; workflow?.isEnabled = newValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: AutomationKind,
        appPath: String? = nil,
        recipient: String = "",
        subject: String = "",
        message: String = "",
        keyboardShortcut: KeyboardShortcutDefinition? = nil,
        appScopeBundleIdentifier: String = "",
        appScopeBundleIdentifiers: [String]? = nil,
        siriEnabled: Bool = false,
        createdAt: Date = .now,
        workflow: WorkflowDefinition? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.appPath = appPath
        self.recipient = recipient
        self.subject = subject
        self.message = message
        self.keyboardShortcut = keyboardShortcut
        self.appScopeBundleIdentifier = appScopeBundleIdentifier
        self.appScopeBundleIdentifiers = appScopeBundleIdentifiers
        self.siriEnabled = siriEnabled
        self.createdAt = createdAt
        self.workflow = workflow
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, appPath, recipient, subject, message
        case keyboardShortcut, appScopeBundleIdentifier, appScopeBundleIdentifiers, siriEnabled, createdAt, workflow, enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(AutomationKind.self, forKey: .kind)
        appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        recipient = try container.decodeIfPresent(String.self, forKey: .recipient) ?? ""
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        keyboardShortcut = try container.decodeIfPresent(KeyboardShortcutDefinition.self, forKey: .keyboardShortcut)
        appScopeBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appScopeBundleIdentifier) ?? ""
        appScopeBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .appScopeBundleIdentifiers)
        siriEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriEnabled) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        workflow = try container.decodeIfPresent(WorkflowDefinition.self, forKey: .workflow)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}
