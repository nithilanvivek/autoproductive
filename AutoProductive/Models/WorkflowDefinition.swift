import Foundation

enum SequenceTrigger: String, Codable, CaseIterable, Identifiable {
    case text, keyboardShortcut, menuBar, siri, touchpad, interval, screenPixel, screenImage, screen
    /// The combined case is retained only for saved workflows.
    static var allCases: [Self] { [.text, .keyboardShortcut, .menuBar, .siri, .touchpad, .interval, .screenPixel, .screenImage] }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "Text Trigger"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .menuBar: "Robot Menu Bar Icon"
        case .siri: "Siri Dialogue"
        case .touchpad: "Touchpad Shortcut"
        case .interval: "Repeated Interval"
        case .screenPixel: "Wait for a Pixel Color"
        case .screenImage: "Wait for an Image"
        case .screen: "Screen Condition"
        }
    }
}

enum WorkflowTrigger: String, Codable, CaseIterable, Identifiable {
    case manual, textExpansion, keyRemap, touchpad, interval, screen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: "Run button or keyboard shortcut"
    case .textExpansion: "Typed phrase"
        case .keyRemap: "Key or mouse button"
        case .touchpad: "Modified two-finger swipe"
        case .interval: "Repeated interval"
        case .screen: "Screen condition becomes true"
        }
    }
}

enum WorkflowAction: String, Codable, CaseIterable, Identifiable {
    case typeText, pressKey, click, movePointer, scroll, wait, openURL, openApp, composeMail
    case window, setClipboard, transformClipboard, pasteClipboard
    case readFile, writeFile, appendFile, copyFile, moveFile, createFolder, trashFile
    case shell, appleScript, prompt, choose, message, notification, screenPixel, screenImage
    case adjustSound, adjustBrightness

    /// Put the actions that supply named values first, preserving every other
    /// action's relative order and its existing persisted raw value.
    static var chooserOrder: [Self] {
        let valueActions: [Self] = [.prompt, .choose, .readFile]
        return valueActions + allCases.filter { !valueActions.contains($0) }
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .composeMail: "Compose an email draft"
        case .typeText: "Type text"
        case .pressKey: "Press a key combination"
        case .click: "Click the mouse"
        case .movePointer: "Move the pointer"
        case .scroll: "Scroll"
        case .wait: "Wait"
        case .openURL: "Open a website or file"
        case .openApp: "Open an application"
        case .window: "Arrange the front window"
        case .setClipboard: "Set clipboard text"
        case .transformClipboard: "Transform clipboard text"
        case .pasteClipboard: "Paste clipboard"
        case .readFile: "Read a text file into {{file}}"
        case .writeFile: "Write a text file"
        case .appendFile: "Append to a text file"
        case .copyFile: "Copy a file or folder"
        case .moveFile: "Move or rename a file"
        case .createFolder: "Create a folder"
        case .trashFile: "Move a file to Trash"
        case .shell: "Run a shell command"
        case .appleScript: "Run AppleScript"
        case .prompt: "Ask for text → {{input}}"
        case .choose: "Show a choice menu → {{choice}}"
        case .message: "Show a message"
        case .notification: "Show a notification"
        case .screenPixel: "Wait for a screen color"
        case .screenImage: "Wait for an image"
        case .adjustSound: "Adjust sound"
        case .adjustBrightness: "Adjust brightness"
        }
    }

    var options: [String] {
        switch self {
        case .window: ["leftHalf", "rightHalf", "maximize", "center", "minimize", "focus", "custom"]
        case .click: ["left", "right", "middle"]
        case .transformClipboard: ["uppercase", "lowercase", "trim", "titleCase", "sortLines", "uniqueLines"]
        case .adjustSound, .adjustBrightness: PercentageAdjustment.allCases.map(\.rawValue)
        default: []
        }
    }
}

struct WorkflowStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var action: WorkflowAction = .typeText
    var text = ""
    var secondaryText = ""
    var option = ""
    var x: Double = 0
    var y: Double = 0
    /// Nil keeps existing click workflows in macOS point coordinates.
    var coordinatesInPixels: Bool? = nil
    var amount: Double = 1
    var duration: Double = 0.25
    var key: KeyboardShortcutDefinition?
    /// Nil preserves existing single-pixel conditions. An empty array is an
    /// unfinished rectangle selection and must not match the entire screen.
    var colorRegions: [ScreenColorRegion]? = nil
    var colorInEveryRegion: Bool? = nil
    var imageSearchScope: ImageSearchScope? = nil
    var imageRegions: [ScreenColorRegion]? = nil
    var matchResizedImages: Bool? = nil

    init(action: WorkflowAction = .typeText, text: String = "", option: String = "", secondaryText: String = "") {
        self.action = action; self.text = text; self.option = option; self.secondaryText = secondaryText
        if [.shell, .appleScript].contains(action) { duration = 60 }
        if [.screenPixel, .screenImage].contains(action) { duration = 5; amount = 10 }
        if action == .screenImage { imageSearchScope = .entireScreen }
        if [.adjustSound, .adjustBrightness].contains(action) { self.option = option.isEmpty ? "set" : option; amount = 50 }
    }
}

struct WorkflowDefinition: Codable, Hashable {
    var trigger: WorkflowTrigger = .manual
    var isEnabled = false
    var appBundleIdentifier = ""
    /// Nil means this workflow predates multiple-app scope support.
    var appBundleIdentifiers: [String]? = nil
    var scopedAppBundleIdentifiers: [String] {
        get { appBundleIdentifiers ?? (appBundleIdentifier.isEmpty ? [] : [appBundleIdentifier]) }
        set { appBundleIdentifiers = AppScope.normalized(newValue); appBundleIdentifier = "" }
    }
    var abbreviation = ""
    var requiresDelimiter = true
    /// Nil preserves the case-sensitive behavior of workflows saved before this option existed.
    var caseSensitive: Bool? = nil
    var matchesCase: Bool { caseSensitive ?? true }
    /// Nil preserves the erase-on-trigger behavior of existing workflows.
    var deleteTriggerText: Bool? = nil
    var shouldDeleteTriggerText: Bool { deleteTriggerText ?? true }
    var inputKey: KeyboardShortcutDefinition?
    var mouseButton: Int = -1
    var gesture = "up"
    var gestureModifiers: ShortcutModifiers = [.control, .option]
    var interval: Double = 5
    var repeatCount = 1
    /// Nil keeps the UTC behaviour of existing automations.
    var dateUTCOffset: String? = nil
    var steps: [WorkflowStep] = [WorkflowStep()]
    /// Nil preserves the single-trigger behavior of existing saved workflows.
    var sequenceTriggers: [SequenceTrigger]? = nil
    var screenCondition: WorkflowStep? = nil
    var screenCheckInterval: Double? = nil
    var pixelCondition: WorkflowStep? = nil
    var imageCondition: WorkflowStep? = nil
    var pixelCheckInterval: Double? = nil
    var imageCheckInterval: Double? = nil
    var screenChecks: [ScreenTriggerCheck] {
        guard let sequenceTriggers else {
            return trigger == .screen ? [ScreenTriggerCheck(trigger: .screen, condition: steps.first, interval: interval)] : []
        }
        return sequenceTriggers.compactMap { trigger in
            switch trigger {
            case .screen: ScreenTriggerCheck(trigger: trigger, condition: screenCondition, interval: screenCheckInterval ?? interval)
            case .screenPixel: ScreenTriggerCheck(trigger: trigger, condition: pixelCondition, interval: pixelCheckInterval ?? 2)
            case .screenImage: ScreenTriggerCheck(trigger: trigger, condition: imageCondition, interval: imageCheckInterval ?? 2)
            default: nil
            }
        }
    }
    var allowsMenuBarRunning: Bool { sequenceTriggers?.contains(.menuBar) ?? true }
    func uses(_ kind: WorkflowTrigger) -> Bool {
        guard let sequenceTriggers else { return trigger == kind }
        switch kind {
        case .textExpansion: return sequenceTriggers.contains(.text)
        case .touchpad: return sequenceTriggers.contains(.touchpad)
        case .interval: return sequenceTriggers.contains(.interval)
        case .screen: return sequenceTriggers.contains { [.screen, .screenPixel, .screenImage].contains($0) }
        case .manual: return sequenceTriggers.contains(.menuBar) || sequenceTriggers.contains(.keyboardShortcut)
        case .keyRemap: return false
        }
    }

    static func template(for kind: AutomationKind) -> Self {
        var value = Self()
        switch kind {
        case .clickingKeyboard:
            value.steps = []
        case .textExpansion:
            value.trigger = .textExpansion; value.abbreviation = "ap-hello"; value.caseSensitive = false
            value.steps = [WorkflowStep(text: "Hello!")]
        case .keyRemap:
            value.trigger = .keyRemap; value.steps = [WorkflowStep(action: .pressKey)]
        case .touchpad:
            value.trigger = .touchpad; value.steps = [WorkflowStep(action: .window, option: "maximize")]
        case .windows: value.steps = [WorkflowStep(action: .window, option: "leftHalf")]
        case .clipboard: value.steps = [WorkflowStep(action: .transformClipboard, option: "uppercase")]
        case .files: value.steps = [WorkflowStep(action: .copyFile)]
        case .script: value.steps = [WorkflowStep(action: .shell)]
        case .dialog: value.steps = [WorkflowStep(action: .prompt, text: "What would you like to enter?")]
        case .screen:
            value.trigger = .screen; value.interval = 2
            value.steps = [WorkflowStep(action: .screenPixel, text: "#FFFFFF"), WorkflowStep(action: .message, text: "Screen condition matched.")]
        default: break
        }
        return value
    }

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw WorkflowError.invalid(message) }
        }
        try require((1...100).contains(repeatCount), "Choose 1–100 repetitions.")
        try require(WorkflowText.utcOffsetSeconds(dateUTCOffset) != nil, "Enter a UTC offset from 00:00 to 14:00, using HH:MM.")
        try require(!steps.isEmpty && steps.count <= 200, "Add 1–200 actions.")
        try require(WorkflowTiming.isValid(interval), "Choose an interval between 0.5 seconds and one day.")
        if let sequenceTriggers { try require(!sequenceTriggers.isEmpty, "Choose at least one trigger.") }
        if uses(.textExpansion) {
            try require(!abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        abbreviation.count <= 64 &&
                        !abbreviation.contains(where: \.isNewline),
                        "Use a typed phrase of 1–64 characters on one line.")
        }
        if uses(.keyRemap) {
            try require(inputKey != nil || (0...4).contains(mouseButton), "Record a source key or choose a mouse button.")
            try require(steps.count == 1 && steps[0].action == .pressKey && steps[0].key != nil, "Choose one destination key combination for remapping.")
            if let inputKey { try require(inputKey.keyCode < 128, "Choose a valid source key.") }
        }
        if uses(.touchpad) {
            try require(!gestureModifiers.isEmpty, "Choose a modifier to keep ordinary scrolling available.")
        }
        if uses(.screen) {
            for check in screenChecks {
                let expected: WorkflowAction? = check.trigger == .screenPixel ? .screenPixel : check.trigger == .screenImage ? .screenImage : nil
                try require(check.condition?.action == .screenPixel || check.condition?.action == .screenImage, "Choose a pixel or image condition for the screen trigger.")
                if let expected { try require(check.condition?.action == expected, "Configure the selected \(check.trigger.title) trigger.") }
                try require(WorkflowTiming.isValid(check.interval), "Choose a screen check interval between 0.5 seconds and one day.")
            }
        }
        for step in steps + (sequenceTriggers != nil ? screenChecks.compactMap(\.condition) : []) {
            try require(step.x.isFinite && step.y.isFinite && step.amount.isFinite && step.duration.isFinite, "Use finite numeric values.")
            try require((0...300).contains(step.duration), "Action waits must be between 0 and 300 seconds.")
            if step.action == .pressKey { try require(step.key != nil, "Record the key to press.") }
            if let key = step.key { try require(key.keyCode < 128, "Choose a valid destination key.") }
            try require(step.text.utf8.count <= 1_048_576 && step.secondaryText.utf8.count <= 1_048_576, "Each action text field is limited to 1 MB.")
            if step.action == .shell || step.action == .appleScript { try require(!step.text.isEmpty, "Enter a script to run.") }
            if step.action == .screenPixel {
                try require(ScreenColor.parse(step.text) != nil, "Enter a color as #RRGGBB.")
                try require((0...255).contains(step.amount), "Pixel tolerance must be 0–255.")
                if let regions = step.colorRegions {
                    try require(!regions.isEmpty && regions.count <= 32, "Select 1–32 screen rectangles.")
                    try require(regions.allSatisfy(\.isValid), "Screen rectangles need finite coordinates and positive width and height.")
                }
            }
            if step.action == .screenImage {
                try ScreenReferenceImage.validate(step.text)
                if step.imageSearchScope == .rectangles {
                    try require(!(step.imageRegions ?? []).isEmpty && (step.imageRegions?.count ?? 0) <= 32,
                                "Select 1–32 screen rectangles to search for the image.")
                    try require(step.imageRegions?.allSatisfy(\.isValid) == true, "Choose valid image search rectangles.")
                }
                try require((0...255).contains(step.amount), "Image tolerance must be 0–255.")
            }
            if [.adjustSound, .adjustBrightness].contains(step.action) {
                try require(PercentageAdjustment(rawValue: step.option) != nil && (0...100).contains(step.amount), "Choose Set, Increase or Decrease and a percentage from 0 to 100.")
            }
        }
    }
}

enum ImageSearchScope: String, Codable, CaseIterable {
    case entireScreen, rectangles
}

struct ScreenTriggerCheck {
    let trigger: SequenceTrigger
    let condition: WorkflowStep?
    let interval: Double
}

struct ScreenTriggerKey: Hashable {
    let automationID: UUID
    let trigger: SequenceTrigger
}

struct ScreenTriggerMatchState {
    private var states: [ScreenTriggerKey: Bool] = [:]

    mutating func record(_ matched: Bool, for key: ScreenTriggerKey) -> (changed: Bool, shouldRun: Bool) {
        let previous = states.updateValue(matched, forKey: key)
        return (previous != matched, matched && previous != true)
    }

    mutating func reset() { states.removeAll() }
}

enum PercentageAdjustment: String, CaseIterable {
    case set, increase, decrease
    var title: String { rawValue.capitalized }
    func applying(_ amount: Double, to current: Double) -> Double {
        let result: Double
        switch self {
        case .set: result = amount
        case .increase: result = current + amount
        case .decrease: result = current - amount
        }
        return min(100, max(0, result))
    }
}

enum WorkflowTiming {
    static let minimum: Double = 0.5
    static let maximum: Double = 86400
    static func isValid(_ value: Double) -> Bool { value.isFinite && (minimum...maximum).contains(value) }
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(maximum, max(minimum, value)) : minimum
    }
    static func nextScreenCheck(after error: Error, now: Date, interval: Double) -> Date {
        error is WorkflowError ? .distantFuture : now.addingTimeInterval(max(5, clamped(interval)))
    }
}

/// Global display points with a top-left origin, matching ScreenCaptureKit.
struct ScreenColorRegion: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isValid: Bool {
        [x, y, width, height, x + width, y + height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    func pixelRect(displayBounds: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        CGRect(x: (x - displayBounds.minX) * Double(imageWidth) / displayBounds.width,
               y: (y - displayBounds.minY) * Double(imageHeight) / displayBounds.height,
               width: width * Double(imageWidth) / displayBounds.width,
               height: height * Double(imageHeight) / displayBounds.height)
    }
}

enum AppScope {
    static func normalized(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func allows(_ frontmostBundleIdentifier: String?, selected identifiers: [String]) -> Bool {
        identifiers.isEmpty || identifiers.contains(frontmostBundleIdentifier ?? "")
    }
}

enum WorkflowError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// Display availability can change without the saved condition becoming invalid.
enum ScreenObservationError: LocalizedError {
    case noDisplays
    case positionOutsideDisplays
    case rectangleOutsideDisplays

    var showsWarning: Bool { if case .noDisplays = self { return false }; return true }

    var errorDescription: String? {
        switch self {
        case .noDisplays: "Screen checking will resume when a display is available."
        case .positionOutsideDisplays: "The saved screen position is outside the connected displays. Reconnect the display or select the position again."
        case .rectangleOutsideDisplays: "A saved screen rectangle is outside the connected displays. Reconnect the display or select the rectangle again."
        }
    }
}

struct ScreenColor: Equatable, Sendable {
    let red: Int, green: Int, blue: Int
    static func parse(_ text: String) -> Self? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }), let rgb = Int(value, radix: 16) else { return nil }
        return Self(red: (rgb >> 16) & 255, green: (rgb >> 8) & 255, blue: rgb & 255)
    }
}

enum WorkflowText {
    static func utcOffsetSeconds(_ value: String?) -> Int? {
        let value = value ?? "+00:00"
        let chars = Array(value)
        guard chars.count == 6, ["+", "-"].contains(chars[0]), chars[3] == ":",
              let hours = Int(String(chars[1...2])), let minutes = Int(String(chars[4...5])),
              (0...14).contains(hours), (0...59).contains(minutes), hours != 14 || minutes == 0 else { return nil }
        return (chars[0] == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
    }

    private static func formatter(utcOffset: String?, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds(utcOffset) ?? 0)!
        formatter.dateFormat = format
        return formatter
    }

    static func dateString(_ date: Date, utcOffset: String?) -> String {
        formatter(utcOffset: utcOffset, format: "dd/MM/yyyy").string(from: date)
    }

    static func timeString(_ date: Date, utcOffset: String?) -> String {
        formatter(utcOffset: utcOffset, format: "hh:mm a").string(from: date)
    }
    static func expand(_ text: String, variables: [String: String]) -> String {
        // One pass prevents inserted user text from being interpreted as another variable.
        let regex = try! NSRegularExpression(pattern: "\\{\\{(input|choice|file|output|clipboard|date)\\}\\}")
        let source = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let name = source.substring(with: match.range(at: 1))
            if let value = variables[name] { result.replaceSubrange(range, with: value) }
        }
        return result
    }
    #if !MODULAR_FEATURES
    static func transform(_ text: String, using operation: String) -> String {
        ClipboardTransform.apply(text, using: operation)
    }
    #endif
}

struct TextTriggerBuffer {
    private(set) var text = ""

    mutating func append(_ characters: String) { text = String((text + characters).suffix(128)) }
    mutating func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    mutating func clear() { text = "" }
}

enum TextTriggerMatcher {
    static func matchLength(
        buffered: String,
        characters: String,
        phrase: String,
        caseSensitive: Bool,
        requiresDelimiter: Bool
    ) -> Int? {
        guard !phrase.isEmpty,
              !requiresDelimiter || characters.allSatisfy({ $0.isWhitespace || $0.isPunctuation }) else { return nil }
        let candidate = requiresDelimiter ? buffered : buffered + characters
        let options: String.CompareOptions = caseSensitive ? [.anchored, .backwards] : [.anchored, .backwards, .caseInsensitive]
        guard let range = candidate.range(of: phrase, options: options),
              range.upperBound == candidate.endIndex,
              !isInsideQuotes(candidate, before: range.lowerBound) else { return nil }
        return candidate[range].count
    }

    private enum Quote { case single, double }

    private static func isInsideQuotes(_ text: String, before end: String.Index) -> Bool {
        var open: Quote?
        var index = text.startIndex
        while index < end {
            let character = text[index]
            let next = text.index(after: index)
            let apostropheInWord = (character == "'" || character == "’") &&
                index > text.startIndex && next < text.endIndex &&
                text[text.index(before: index)].isLetter && text[next].isLetter
            if !apostropheInWord {
                switch character {
                case "'":
                    if open == .single { open = nil } else if open == nil { open = .single }
                case "\"":
                    if open == .double { open = nil } else if open == nil { open = .double }
                case "‘":
                    if open == nil { open = .single }
                case "’":
                    if open == .single { open = nil }
                case "“":
                    if open == nil { open = .double }
                case "”":
                    if open == .double { open = nil }
                default: break
                }
            }
            index = next
        }
        return open != nil
    }
}
