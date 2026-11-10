import Foundation
import AppKit
import ApplicationServices

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try value() else { fatalError(message) }
    checks += 1
}
func rejects(_ flow: WorkflowDefinition, _ message: String) {
    do { try flow.validate(); fatalError(message) } catch { checks += 1 }
}

let inputSettingsSuite = "land.nithi.autoproductive.tests.input." + UUID().uuidString
let inputSettings = UserDefaults(suiteName: inputSettingsSuite)!
try check(InputMonitoringSettings.allowsInput(in: inputSettings), "Input monitoring defaults on without requiring a saved toggle preference")
try check(!InputMonitoringSettings.isAvailable(permissionGranted: false, in: inputSettings), "Input monitoring is off until permission is granted")
try check(InputMonitoringSettings.isAvailable(permissionGranted: true, in: inputSettings), "Input monitoring becomes available when permission is granted")
inputSettings.set(false, forKey: InputMonitoringSettings.enabledKey)
try check(!InputMonitoringSettings.isAvailable(permissionGranted: true, in: inputSettings), "An explicit off setting persists even with permission")
try check(!InputMonitoringSettings.allowsInput(in: inputSettings), "The shared switch disables input-dependent features")
inputSettings.set(true, forKey: InputMonitoringSettings.enabledKey)
try check(InputMonitoringSettings.allowsInput(in: inputSettings), "Input monitoring can be resumed without changing automations")
inputSettings.set(true, forKey: "automationPaused.v1")
try check(!InputMonitoringSettings.allowsInput(in: inputSettings) && InputMonitoringSettings.isEnabled(in: inputSettings), "Emergency pause blocks input while preserving the selected input preference")
inputSettings.set(false, forKey: "automationPaused.v1")
try check(InputMonitoringSettings.allowsInput(in: inputSettings), "Releasing emergency pause restores the selected input policy")
inputSettings.removePersistentDomain(forName: inputSettingsSuite)

try check(EditableTextPolicy.allows(role: kAXTextAreaRole, editable: true, valueSettable: false, readOnly: nil, enabled: true, secure: false), "Explicit editable text areas need not expose AXValue setters")
for role in [kAXTextFieldRole, kAXTextAreaRole, kAXGroupRole, "AXWebArea"] {
    try check(EditableTextPolicy.allows(role: role, editable: nil, valueSettable: true, readOnly: nil, enabled: true, secure: false), "Writable native and web editor roles accept text triggers")
    try check(!EditableTextPolicy.allows(role: role, editable: nil, valueSettable: false, readOnly: nil, enabled: true, secure: false), "Roles alone do not establish editability")
}
for denied in [(false, false, false), (true, true, false), (true, false, true)] {
    try check(!EditableTextPolicy.allows(role: kAXTextAreaRole, editable: true, valueSettable: true, readOnly: denied.1, enabled: denied.0, secure: denied.2), "Disabled, read-only and secure editors stay excluded")
}

for screen in [CGRect(x: 0, y: 0, width: 320, height: 240),
               CGRect(x: 0, y: 0, width: 1408, height: 826),
               CGRect(x: -1920, y: 100, width: 1920, height: 1055)] {
    for x in [screen.minX + 18, screen.midX, screen.maxX - 18] {
        let anchor = CGRect(x: x - 10, y: screen.maxY + 2, width: 20, height: 22)
        let layout = MenuBarPopupLayout(anchor: anchor, visibleFrame: screen)
        try check(screen.contains(layout.frame), "Menu fits small and offset displays at both screen edges")
        try check(abs(layout.frame.maxY - screen.maxY) < 0.1, "Pointer sits directly below the menu bar")
        if x == screen.midX {
            try check(abs(layout.frame.midX - anchor.midX) < 0.1 && abs(layout.tipX - layout.frame.width / 2) < 0.1,
                      "Menu and curved pointer center on the status icon whenever space permits")
        }
    }
}

let menuScreen = CGRect(x: 0, y: 0, width: 1408, height: 826)
let menuAnchor = CGRect(x: 690, y: 828, width: 20, height: 22)
let compactMenu = MenuBarPopupLayout(anchor: menuAnchor, visibleFrame: menuScreen, preferredHeight: 200)
try check(compactMenu.frame.height == 210 && compactMenu.frame.maxY == menuScreen.maxY,
          "Compact section height keeps the pointer anchored and removes unused body space")
let largeMenu = MenuBarPopupLayout(anchor: menuAnchor, visibleFrame: menuScreen, preferredHeight: 2000)
try check(menuScreen.contains(largeMenu.frame), "Long sections still fit the available display")

let bucketSuite = "land.nithi.autoproductive.shortcuts-tests.\(UUID().uuidString)"
let bucketDefaults = UserDefaults(suiteName: bucketSuite)!
defer { bucketDefaults.removePersistentDomain(forName: bucketSuite) }
var bucketKeys = FileBucketShortcutSettings.load(defaults: bucketDefaults)
try check(bucketKeys.openEnabled && bucketKeys.addEnabled && bucketKeys.add == nil, "File Bucket shortcuts start enabled; adding waits for an explicit recorded key")
try check(bucketKeys.open?.keyCode == 3 && bucketKeys.open?.modifiers == [.command, .option], "Open File Bucket defaults to Command-Option-F")
bucketKeys.open = nil
bucketKeys.add = .init(keyCode: 8, keyLabel: "C", modifiers: [.command, .control])
bucketKeys.addEnabled = false
bucketKeys.save(defaults: bucketDefaults)
try check(FileBucketShortcutSettings.load(defaults: bucketDefaults) == bucketKeys, "Changed, disabled and cleared File Bucket keys persist")
let unusualFile = URL(fileURLWithPath: "/tmp/folder/space \"quote\"\n日本語.txt")
let selectionData = try JSONEncoder().encode([unusualFile.absoluteString, "https://example.com/file"])
try check(try FileBucketShortcutSettings.selectionURLs(from: selectionData) == [unusualFile], "Finder JSON preserves unusual filenames and accepts only file URLs")

let legacy = Data("""
[{"id":"11111111-1111-1111-1111-111111111111","name":"Original app","kind":"openApp","appPath":"/Applications/Notes.app"},
 {"id":"22222222-2222-2222-2222-222222222222","name":"Original draft","kind":"composeMail","recipient":"user@example.com"}]
""".utf8)
let old = try JSONDecoder().decode([SavedAutomation].self, from: legacy)
let shiftedEight = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift, .command],
    timestamp: 0, windowNumber: 0, context: nil, characters: "*", charactersIgnoringModifiers: "*", isARepeat: false, keyCode: 28)!
let recordedEight = KeyboardKeyLabel.definition(for: shiftedEight)
try check(recordedEight.keyLabel == shiftedEight.characters(byApplyingModifiers: [])?.uppercased(), "Record the unshifted layout key")
try check(recordedEight.keyLabel != "*" && recordedEight.modifiers == [.shift, .command] && recordedEight.keyCode == 28,
          "Shift is a modifier, not part of the base key label")
let screenshotKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift, .command],
    timestamp: 0, windowNumber: 0, context: nil, characters: "$", charactersIgnoringModifiers: "$", isARepeat: false, keyCode: 21)!
try check(KeyboardKeyLabel.definition(for: screenshotKey).keyCode == 21 && KeyboardKeyLabel.definition(for: screenshotKey).modifiers == [.shift, .command],
          "A remap destination preserves screenshot key code and modifiers")
let escapeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
try check(KeyboardKeyLabel.definition(for: escapeKey).displayText == "⎋", "Escape remains a recordable remap key")
try check(old.count == 2 && old[0].workflow == nil && old[1].recipient == "user@example.com", "Legacy automations must remain readable")
try check(old[0].scopedAppBundleIdentifiers.isEmpty, "Old automations default to all apps")
var scoped = SavedAutomation(name: "Scoped", kind: .openApp, appScopeBundleIdentifier: "com.apple.TextEdit")
try check(scoped.scopedAppBundleIdentifiers == ["com.apple.TextEdit"], "Existing single-app scope remains active")
scoped.scopedAppBundleIdentifiers = ["com.apple.TextEdit", "com.apple.Safari", "com.apple.TextEdit"]
let restoredScope = try JSONDecoder().decode(SavedAutomation.self, from: JSONEncoder().encode(scoped))
try check(restoredScope.scopedAppBundleIdentifiers == ["com.apple.TextEdit", "com.apple.Safari"], "Multiple app scopes persist without duplicates")
try check(AppScope.allows("com.apple.Safari", selected: restoredScope.scopedAppBundleIdentifiers), "Either selected app allows an automation")
try check(!AppScope.allows("com.google.Chrome", selected: restoredScope.scopedAppBundleIdentifiers), "Other apps do not allow a scoped automation")
try check(AppScope.allows("com.google.Chrome", selected: []), "Empty app scope allows every app")
var legacyFlow = WorkflowDefinition.template(for: .workflow)
legacyFlow.appBundleIdentifier = "com.apple.TextEdit"
let decodedLegacyFlow = try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(legacyFlow))
try check(decodedLegacyFlow.scopedAppBundleIdentifiers == ["com.apple.TextEdit"], "Existing workflow scope remains active")
legacyFlow.scopedAppBundleIdentifiers = ["com.apple.Safari", "com.apple.TextEdit"]
try check(legacyFlow.appBundleIdentifier.isEmpty && legacyFlow.scopedAppBundleIdentifiers.count == 2,
          "New workflow scope replaces the legacy single-app field")
for kind in AutomationKind.allCases where ![.openApp, .composeMail].contains(kind) {
    let value = SavedAutomation(name: kind.title, kind: kind, workflow: .template(for: kind))
    let decoded = try JSONDecoder().decode(SavedAutomation.self, from: JSONEncoder().encode(value))
    try check(decoded == value, "Every automation kind must round-trip with trigger settings and action order")
}
var clickSequence = WorkflowDefinition.template(for: .clickingKeyboard)
var coordinateClick = WorkflowStep(action: .click, option: "left")
coordinateClick.x = 125; coordinateClick.y = 240
coordinateClick.coordinatesInPixels = true
var shortcutStep = WorkflowStep(action: .pressKey)
shortcutStep.key = .init(keyCode: 8, keyLabel: "C", modifiers: .command)
clickSequence.steps = [coordinateClick, WorkflowStep(action: .typeText, text: "hello"), shortcutStep]
let savedClickSequence = SavedAutomation(name: "Click and type", kind: .clickingKeyboard, workflow: clickSequence)
let restoredClickSequence = try JSONDecoder().decode(SavedAutomation.self, from: JSONEncoder().encode(savedClickSequence))
try check(restoredClickSequence.workflow?.steps == clickSequence.steps, "Click, typing and shortcut steps retain their order and settings")
var flow = WorkflowDefinition.template(for: .workflow)
try flow.validate()
flow.repeatCount = 0; rejects(flow, "Reject zero repeats")
flow.repeatCount = 101; rejects(flow, "Bound repeating workflows")
flow.repeatCount = 1; flow.interval = .infinity; rejects(flow, "Reject infinite intervals")
flow.interval = 1; flow.steps = []; rejects(flow, "Reject empty workflows")
flow.steps = Array(repeating: WorkflowStep(), count: 201); rejects(flow, "Bound action counts")
flow = .template(for: .textExpansion); flow.abbreviation = ""; rejects(flow, "Reject empty text trigger")
flow.abbreviation = "Open Settings"; try flow.validate()
flow.steps = [WorkflowStep(action: .openApp, text: "/System/Applications/System Settings.app")]
try flow.validate()
try check(!flow.matchesCase, "New text triggers ignore case unless requested")
flow.caseSensitive = true
try check(flow.matchesCase, "Text trigger case preference persists")
try check(flow.shouldDeleteTriggerText, "Existing text triggers keep deleting the typed phrase")
flow.deleteTriggerText = false
let keepPhrase = try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(flow))
try check(!keepPhrase.shouldDeleteTriggerText, "Keep-phrase choice survives persistence")
try check(TextTriggerMatcher.matchLength(buffered: "Open Pytho", characters: "n", phrase: "Open Python", caseSensitive: false, requiresDelimiter: false) == 11,
          "Unquoted phrases trigger on the final character")
try check(TextTriggerMatcher.matchLength(buffered: "'Open Pytho", characters: "n", phrase: "Open Python", caseSensitive: false, requiresDelimiter: false) == nil,
          "Single quotes escape an immediate text trigger")
try check(TextTriggerMatcher.matchLength(buffered: "\"Open Pytho", characters: "n", phrase: "Open Python", caseSensitive: false, requiresDelimiter: false) == nil,
          "Double quotes escape an immediate text trigger")
try check(TextTriggerMatcher.matchLength(buffered: "“Open Pytho", characters: "n", phrase: "Open Python", caseSensitive: false, requiresDelimiter: false) == nil,
          "Smart quotes escape an immediate text trigger")
try check(TextTriggerMatcher.matchLength(buffered: "'Open Python", characters: " ", phrase: "Open Python", caseSensitive: false, requiresDelimiter: true) == nil,
          "Single quotes escape a delimiter-based text trigger")
try check(TextTriggerMatcher.matchLength(buffered: "\"Open Python", characters: " ", phrase: "Open Python", caseSensitive: false, requiresDelimiter: true) == nil,
          "Double quotes escape a delimiter-based text trigger")
try check(TextTriggerMatcher.matchLength(buffered: "Open Python", characters: " ", phrase: "Open Python", caseSensitive: false, requiresDelimiter: true) == 11,
          "Unquoted phrases still trigger after a delimiter")
try check(TextTriggerMatcher.matchLength(buffered: "\"elsewhere\" Open Pytho", characters: "n", phrase: "Open Python", caseSensitive: false, requiresDelimiter: false) == 11,
          "Closed earlier quotes do not block later phrases")
try check(TextTriggerMatcher.matchLength(buffered: "I'm Open Pytho", characters: "n", phrase: "Open Python", caseSensitive: false, requiresDelimiter: false) == 11,
          "An apostrophe inside a word does not open a quote")
for quote in ["", "'", "\"", "‘", "“"] {
    var typed = TextTriggerBuffer()
    for character in quote + "Open Pythp" { typed.append(String(character)) }
    typed.deleteBackward()
    typed.append("o")
    let immediate = TextTriggerMatcher.matchLength(buffered: typed.text, characters: "n",
        phrase: "Open Python", caseSensitive: false, requiresDelimiter: false)
    try check(immediate == (quote.isEmpty ? 11 : nil), "Corrected typo preserves quote protection: \(quote)")
    typed.append("n")
    let delimited = TextTriggerMatcher.matchLength(buffered: typed.text, characters: " ",
        phrase: "Open Python", caseSensitive: false, requiresDelimiter: true)
    try check(delimited == (quote.isEmpty ? 11 : nil), "Corrected delimiter trigger preserves quote protection: \(quote)")
}
var corrected = TextTriggerBuffer()
corrected.append("Open Pyth👩🏽‍💻")
corrected.deleteBackward()
corrected.append("o")
try check(TextTriggerMatcher.matchLength(buffered: corrected.text, characters: "n", phrase: "Open Python",
    caseSensitive: true, requiresDelimiter: false) == 11, "Backspace removes a complete Unicode character")
corrected.clear()
corrected.deleteBackward()
try check(TextTriggerMatcher.matchLength(buffered: corrected.text, characters: "on", phrase: "Open Python",
    caseSensitive: false, requiresDelimiter: false) == nil, "Cleared focus context cannot complete an earlier phrase")
flow = .template(for: .keyRemap); rejects(flow, "Reject incomplete mappings")
flow.inputKey = .init(keyCode: 0, keyLabel: "A", modifiers: []);
flow.steps[0].key = .init(keyCode: 11, keyLabel: "B", modifiers: []); try flow.validate()
flow = .template(for: .touchpad); flow.gestureModifiers = []; rejects(flow, "Do not hijack ordinary scrolling")
flow = .template(for: .screen); flow.steps[0].text = "#12345Z"; rejects(flow, "Reject malformed screen colors")
flow = .template(for: .screen)
let legacyColorJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(flow.steps[0])) as! [String: Any]
try check(legacyColorJSON["colorRegions"] == nil, "Single pixel workflows keep their existing serialized shape")
let legacyColor = try JSONDecoder().decode(WorkflowStep.self, from: JSONSerialization.data(withJSONObject: legacyColorJSON))
try check(legacyColor.colorRegions == nil && legacyColor.x == 0, "Old screen conditions remain single pixels")
flow.steps[0].colorRegions = []; rejects(flow, "An unfinished rectangle must not match the full display")
flow.steps[0].colorRegions = [ScreenColorRegion(x: -900, y: 40, width: 20, height: 30)]
flow.steps[0].colorInEveryRegion = true
try flow.validate()
let restoredRegions = try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(flow))
try check(restoredRegions == flow, "Rectangle coordinates and every-region matching persist")
let scaledRegion = flow.steps[0].colorRegions![0].pixelRect(displayBounds: CGRect(x: -1000, y: 0, width: 1000, height: 600), imageWidth: 2000, imageHeight: 1200)
try check(scaledRegion == CGRect(x: 200, y: 80, width: 40, height: 60), "Offset Retina displays map rectangle points to physical pixels")
for invalidRegion in [ScreenColorRegion(x: 0, y: 0, width: 0, height: 1),
                      ScreenColorRegion(x: 0, y: 0, width: 1, height: -1),
                      ScreenColorRegion(x: .nan, y: 0, width: 1, height: 1),
                      ScreenColorRegion(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 1)] {
    flow.steps[0].colorRegions = [invalidRegion]; rejects(flow, "Reject empty, inverted, nonfinite or overflowing rectangles")
}
flow.steps[0].colorRegions = Array(repeating: ScreenColorRegion(x: 0, y: 0, width: 1, height: 1), count: 33)
rejects(flow, "Bound the number of regions per check")
for invalidInterval in [1e-10, 0, -1, Double.infinity, Double.nan, 86401] {
    flow = .template(for: .screen); flow.interval = invalidInterval
    rejects(flow, "Reject unsupported polling intervals")
    try check(WorkflowTiming.isValid(WorkflowTiming.clamped(invalidInterval)), "Runtime and field clamp unsupported polling values")
}
flow = .template(for: .screen); flow.interval = 0.5; try flow.validate()
try check(WorkflowTiming.isValid(0.5) && WorkflowTiming.isValid(86400), "Polling supports both documented boundaries")
flow = .template(for: .workflow); flow.steps[0].action = .pressKey; rejects(flow, "Key actions require a recorded key")
try check(WorkflowText.expand("Hi {{input}} / {{clipboard}} / {{date}}", variables: ["input":"{{clipboard}}", "clipboard":"✓ 🌏", "date":"today"]) == "Hi {{clipboard}} / ✓ 🌏 / today", "Expansion must be one pass and Unicode safe")
try check(WorkflowText.expand("{{unknown}}", variables: [:]) == "{{unknown}}", "Unknown tokens remain literal")
try check(WorkflowText.transform(" a\n", using: "trim") == "a", "Trim whitespace")
try check(WorkflowText.transform("a\na\nb", using: "uniqueLines") == "a\nb", "Stable deduplication")
try check(WorkflowText.transform("z\na", using: "sortLines") == "a\nz", "Sort lines")
try check(WorkflowText.transform("Straße", using: "uppercase") == "STRASSE", "Unicode case transformation")
try check(ScreenColor.parse("#12ABef") == ScreenColor(red:18,green:171,blue:239), "Parse RGB colors")
// Creation routes must ask for real configuration and preserve stable page IDs
// when selecting an operation changes the number of pages.
for kind in AutomationKind.allCases {
    let actions = [.clipboard, .dialog].contains(kind)
        ? AutomationWizardPlan.primaryActions(for: kind)
        : [WorkflowDefinition.template(for: kind).steps.first?.action ?? .typeText]
    for action in actions {
        let route = AutomationWizardPlan.pages(for: kind, primaryAction: action)
        try check(!route.isEmpty && route.last?.id == .review, "Every creator ends with review: \(kind)")
        try check(Set(route.map(\.id)).count == route.count, "Navigation IDs are unique: \(kind)")
        try check(route.allSatisfy { !$0.title.isEmpty }, "Every page has a progress label: \(kind)")
    }
}
let launchRoute = AutomationWizardPlan.pages(for: .openApp, primaryAction: .openApp)
try check(launchRoute.first?.id == .application && launchRoute.count == 3,
          "App creation starts with a choice, without an empty trigger or scope page")
let keyRoute = AutomationWizardPlan.pages(for: .keyRemap, primaryAction: .pressKey).map(\.id)
try check(keyRoute.firstIndex(of: .sourceInput)! < keyRoute.firstIndex(of: .destinationKey)!,
          "Remapping configures the original input before its replacement")
let screenRoute = AutomationWizardPlan.pages(for: .screen, primaryAction: .screenPixel).map(\.id)
try check(screenRoute.first == .condition && screenRoute.contains(.monitoring) && screenRoute.contains(.actions),
          "Screen creation separates detection from the response")
let pasteRoute = AutomationWizardPlan.pages(for: .clipboard, primaryAction: .pasteClipboard).map(\.id)
let setRoute = AutomationWizardPlan.pages(for: .clipboard, primaryAction: .setClipboard).map(\.id)
try check(!pasteRoute.contains(.details) && setRoute.contains(.details),
          "Pasting skips text entry while setting clipboard text requires it")
try check(pasteRoute[pasteRoute.firstIndex(of: .runOptions)! - 1] == .operation &&
          setRoute[setRoute.firstIndex(of: .runOptions)! - 1] == .details,
          "Back navigation follows the chosen clipboard operation")
for action in [WorkflowAction.prompt, .choose, .message] {
    let route = AutomationWizardPlan.pages(for: .dialog, primaryAction: action).map(\.id)
    try check(route.contains(.followUp) == (action != .message),
              "Only forms with an answer offer answer-dependent actions")
    try check(route.first == .dialogType && route.contains(.details) && route.contains(.runOptions),
              "Changing form type retains its content and run configuration stages")
}
let exampleShortcut = KeyboardShortcutDefinition(keyCode: 0, keyLabel: "A", modifiers: [.command, .option])
try check(!AutomationWizardPlan.supportsAppScope(trigger: .manual, shortcut: nil),
          "Run-only automations do not collect an unused app restriction")
try check(AutomationWizardPlan.supportsAppScope(trigger: .manual, shortcut: exampleShortcut),
          "Assigning a hotkey enables app restrictions")
for trigger in WorkflowTrigger.allCases where trigger != .manual {
    try check(AutomationWizardPlan.supportsAppScope(trigger: trigger, shortcut: nil),
              "Automatic trigger supports app restrictions: \(trigger)")
}
var sequence = SequenceDefinition.editing(nil)
sequence.sequenceTriggers = [.text, .keyboardShortcut, .menuBar, .interval, .screen]
sequence.abbreviation = "Open Python"
sequence.screenCondition = WorkflowStep(action: .screenPixel, text: "#ffffff")
sequence.screenCheckInterval = 3
var tooFastScreen = sequence; tooFastScreen.screenCheckInterval = 1e-10
rejects(tooFastScreen, "A sequence's independent screen polling interval has the same minimum")
sequence.steps = [WorkflowStep(action: .openApp, text: "/Applications/Python.app"), WorkflowStep(action: .wait)]
try SequenceDefinition.validate(sequence, shortcut: exampleShortcut)
try check(sequence.uses(.textExpansion) && sequence.uses(.screen) && sequence.uses(.interval) && sequence.uses(.manual), "Selected triggers are alternatives on one sequence")
try check(!sequence.uses(.keyRemap) && !sequence.uses(.touchpad), "Unselected triggers stay inactive")
let restoredSequence = try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(sequence))
try check(restoredSequence == sequence, "Multiple triggers, condition and action order persist")
var siriSequence = sequence
siriSequence.sequenceTriggers = [.siri]
try SequenceDefinition.validate(siriSequence, shortcut: nil)
let siriRecord = SavedAutomation(name: "Voice sequence", kind: .sequence, siriEnabled: true, workflow: siriSequence)
let restoredSiri = try JSONDecoder().decode(SavedAutomation.self, from: JSONEncoder().encode(siriRecord))
try check(restoredSiri.workflow?.sequenceTriggers == [.siri] && restoredSiri.siriEnabled, "Siri-only sequences persist without an unrelated keyboard or menu trigger")
var legacySiriRecord = siriRecord
legacySiriRecord.workflow?.sequenceTriggers = [.text]
let editingSiri = SequenceDefinition.editing(legacySiriRecord)
try check(editingSiri.sequenceTriggers == [.text, .siri] && editingSiri.steps == siriSequence.steps, "Editing an existing Siri phrase retains it and the ordered response actions")
sequence.sequenceTriggers = []; rejects(sequence, "At least one trigger is required")
sequence.sequenceTriggers = [.screen]; sequence.screenCondition = nil; rejects(sequence, "Screen trigger requires its own condition")
sequence.sequenceTriggers = [.menuBar]; sequence.screenCondition = WorkflowStep(action: .screenPixel, text: "invalid")
try sequence.validate()
try check(SequenceCreationStage.stages(needsPermissions: false) == [.triggers, .actions, .scope], "Already granted permissions do not add a step")
try check(SequenceCreationStage.stages(needsPermissions: true).last == .permissions, "Missing permissions append the fourth step")
var disabledApp = old[0]
disabledApp.isEnabled = false
let restoredDisabledApp = try JSONDecoder().decode(SavedAutomation.self, from: JSONEncoder().encode(disabledApp))
try check(!restoredDisabledApp.isEnabled && old[1].isEnabled, "Legacy app/mail defaults stay enabled and new disabled state persists")
let convertedApp = SequenceDefinition.editing(restoredDisabledApp)
try check(!convertedApp.isEnabled && convertedApp.steps.first?.action == .openApp, "Editing an old app launcher preserves its disabled state and action")
let convertedMail = SequenceDefinition.editing(old[1])
try check(convertedMail.steps.first?.action == .composeMail && convertedMail.steps.first?.text == "user@example.com", "Mail drafts remain available as sequence actions")
let screenAutomation = SavedAutomation(name: "screen", kind: .screen, workflow: .template(for: .screen))
let convertedScreen = SequenceDefinition.editing(screenAutomation)
try check(convertedScreen.pixelCondition?.action == .screenPixel && convertedScreen.sequenceTriggers?.contains(.screenPixel) == true && convertedScreen.steps.count == 1 && convertedScreen.steps[0].action == .message, "Legacy screen condition becomes a separate pixel trigger without changing response actions")
try check(!SequenceTrigger.allCases.contains(.screen) && SequenceTrigger.allCases.contains(.screenPixel) && SequenceTrigger.allCases.contains(.screenImage), "Pixel and image are separate visible triggers")
var splitScreen = SequenceDefinition.editing(nil)
splitScreen.sequenceTriggers = [.screenPixel, .screenImage]
splitScreen.pixelCondition = WorkflowStep(action: .screenPixel, text: "#FFFFFF")
splitScreen.imageCondition = WorkflowStep(action: .screenImage, text: "{{input}}")
splitScreen.pixelCheckInterval = 0.5; splitScreen.imageCheckInterval = 7
splitScreen.steps = [WorkflowStep(action: .wait)]
try splitScreen.validate()
try check(splitScreen.uses(.screen) && splitScreen.screenChecks.count == 2 && splitScreen.screenChecks.map(\.interval) == [0.5, 7], "Both screen triggers retain independent polling intervals")
try check(Set(splitScreen.screenChecks.map { ScreenTriggerKey(automationID: screenAutomation.id, trigger: $0.trigger) }).count == 2, "Match state and scheduling keys do not collide between screen triggers")
var screenTransitions = ScreenTriggerMatchState()
let imageKey = ScreenTriggerKey(automationID: screenAutomation.id, trigger: .screenImage)
let pixelKey = ScreenTriggerKey(automationID: screenAutomation.id, trigger: .screenPixel)
try check(!screenTransitions.record(false, for: imageKey).shouldRun, "An absent image does not run the automation")
try check(screenTransitions.record(true, for: imageKey).shouldRun, "An image appearing starts the automation")
try check(!screenTransitions.record(true, for: imageKey).shouldRun, "A continuously visible image does not repeat")
try check(screenTransitions.record(true, for: pixelKey).shouldRun, "Screen trigger states remain independent")
try check(!screenTransitions.record(false, for: imageKey).shouldRun, "Hiding the image resets it without running")
try check(screenTransitions.record(true, for: imageKey).shouldRun, "An image reappearing runs the automation again")
screenTransitions.reset()
try check(screenTransitions.record(true, for: imageKey).shouldRun, "Restarting screen checks clears old match state")
try check(try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(splitScreen)) == splitScreen, "Both screen conditions persist independently")
splitScreen.imageCondition = splitScreen.pixelCondition; rejects(splitScreen, "Image trigger cannot contain a pixel condition")
splitScreen.imageCondition = nil; rejects(splitScreen, "Each selected trigger requires its own settings")
var legacyImage = WorkflowDefinition(); legacyImage.sequenceTriggers = [.screen]
legacyImage.screenCondition = WorkflowStep(action: .screenImage, text: "/reference.png")
legacyImage.screenCheckInterval = 9; legacyImage.steps = [WorkflowStep(action: .wait)]
let splitImage = SequenceDefinition.editing(SavedAutomation(name: "Legacy image", kind: .sequence, workflow: legacyImage))
try check(splitImage.sequenceTriggers == [.screenImage] && splitImage.imageCondition == legacyImage.screenCondition && splitImage.imageCheckInterval == 9, "Old image triggers keep their condition and timing in the new editor")
try check(PercentageAdjustment.increase.applying(25, to: 90) == 100 && PercentageAdjustment.decrease.applying(30, to: 10) == 0, "Relative adjustments clamp at both percentage boundaries")
try check(PercentageAdjustment.set.applying(65, to: 5) == 65, "Set is an absolute percentage")
for action in [WorkflowAction.adjustSound, .adjustBrightness] {
    var adjustment = WorkflowDefinition(); adjustment.steps = [WorkflowStep(action: action)]
    try adjustment.validate()
    adjustment.steps[0].amount = 101; rejects(adjustment, "Control percentages cannot exceed 100")
    adjustment.steps[0].amount = 10; adjustment.steps[0].option = "bad"; rejects(adjustment, "Unknown adjustment modes are rejected")
}
try check(ShortcutAnalyzer.matches("@^a", character: "a", modifiers: [.command, .control]), "App shortcut modifier notation matches current keyboard characters")
try check(!ShortcutAnalyzer.matches("@^A", character: "a", modifiers: [.command, .control]), "Uppercase app equivalents require Shift")
try check(ShortcutAnalyzer.matches("@^A", character: "a", modifiers: [.command, .control, .shift]), "Shift app shortcuts are detected")
let relabeledShortcut = KeyboardShortcutDefinition(keyCode: exampleShortcut.keyCode, keyLabel: "Different label", modifiers: exampleShortcut.modifiers)
try check(ShortcutAnalyzer.conflictReason(exampleShortcut, comparedWith: [relabeledShortcut]) != nil, "Duplicate shortcut checks use keycode and modifiers, not a display label")
let retryStart = Date(timeIntervalSince1970: 1000)
try check(WorkflowTiming.nextScreenCheck(after: ScreenObservationError.noDisplays, now: retryStart, interval: 2) == retryStart.addingTimeInterval(5), "Unavailable displays retry instead of suspending the condition permanently")
try check(WorkflowTiming.nextScreenCheck(after: ScreenObservationError.positionOutsideDisplays, now: retryStart, interval: 10) == retryStart.addingTimeInterval(10), "Disconnected display coordinates recover without changing the saved automation")
try check(WorkflowTiming.nextScreenCheck(after: WorkflowError.invalid("invalid reference"), now: retryStart, interval: 2) == .distantFuture, "Invalid saved inputs still require correction")
try check(!ScreenObservationError.noDisplays.showsWarning && ScreenObservationError.rectangleOutsideDisplays.showsWarning, "Temporary display absence is quiet while missing saved regions remain actionable")
var swipe = TouchpadGesture()
let swipeModifiers: ShortcutModifiers = [.control, .option]
try check(swipe.update(x: 0, y: -12, inverted: true, modifiers: swipeModifiers, time: 1, began: true, ended: false, momentum: false) == nil, "Small finger movement does not fire a shortcut")
try check(swipe.update(x: 0, y: -22, inverted: true, modifiers: swipeModifiers, time: 1.05, began: false, ended: false, momentum: false) == "up", "Natural scrolling is normalized to finger direction")
try check(swipe.update(x: 0, y: -60, inverted: true, modifiers: swipeModifiers, time: 1.1, began: false, ended: false, momentum: false) == nil, "One swipe fires only once")
try check(swipe.update(x: 0, y: -60, inverted: true, modifiers: swipeModifiers, time: 1.2, began: false, ended: false, momentum: true) == nil, "Momentum cannot start a second shortcut")
try check(swipe.update(x: 0, y: 35, inverted: false, modifiers: swipeModifiers, time: 2, began: true, ended: false, momentum: false) == "up", "Traditional scrolling has the same finger direction")
try check(swipe.update(x: 0, y: 35, inverted: false, modifiers: [], time: 3, began: true, ended: false, momentum: false) == nil, "Ordinary unmodified scrolling never triggers")
try check(swipe.update(x: -40, y: 2, inverted: true, modifiers: swipeModifiers, time: 4, began: true, ended: true, momentum: false) == "left", "Horizontal swipe uses its dominant axis")
try check(swipe.update(x: 0, y: -35, inverted: false, modifiers: swipeModifiers, time: 4.1, began: true, ended: false, momentum: false) == "down", "Finger lift permits a new gesture immediately")
let hostDescription = """
pid/100 = {
  environment = {
    999 - com.apple.WebKit.GPU.fake
  }
  services = {
    200 - com.apple.WebKit.GPU.1234
    201 - com.apple.WebKit.WebContent.5678
    0 - com.apple.WebKit.GPU
    300 (pe) com.apple.quicklook.QuickLookUIService
    301 - com.example.OtherApp.AudioHelper
    -1 - com.example.Invalid
    invalid - com.example.Invalid
    302 - com.example.Malformed extra
  }
  service stubs = {
    888 - com.apple.WebKit.GPU.stub
  }
}
"""
try check(AudioProcessOwnership.serviceHelpers(in: hostDescription) == [200, 201, 300, 301], "Live service PIDs include WebKit, Quick Look and other helpers, excluding metadata, stubs and invalid rows")
try check(AudioProcessOwnership.serviceHelpers(in: "service stubs = {\n300 - com.apple.quicklook.QuickLookUIService\n}").isEmpty, "A generic helper name alone does not establish ownership")
let hosts = AudioProcessOwnership.unambiguousOwners([100: [200,201,300,301], 101: [201,202,301]])
try check(hosts == [200:100,202:101,300:100], "Ambiguous WebKit and generic helpers are excluded instead of muting another app")
let recorderPlaybackTag: Int64 = 0x415054455354
func recordedKey(_ code: CGKeyCode, down: Bool = true, time: Double = 1, flags: CGEventFlags = []) -> CGEvent {
    let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: code, keyDown: down)!
    event.flags = flags
    event.timestamp = UInt64(time * 1_000_000_000)
    return event
}
var recording = MacroRecordingBuffer()
let oneKey = recordedKey(12)
try check(!recording.observe(oneKey, isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag), "One observed physical key keeps recording active")
_ = recording.observe(recordedKey(12, down: false), isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag)
try check(recording.actions.count == 1 && recording.actions[0].key?.keyCode == 12, "Key up never creates a second recorded key action")
try check(oneKey.type == .keyDown && oneKey.flags.isEmpty && oneKey.getIntegerValueField(.keyboardEventKeycode) == 12 && oneKey.timestamp == 1_000_000_000, "Observing a key leaves its original type, flags, keycode and time unchanged")
_ = recording.observe(recordedKey(0, time: 2), isOwnEvent: true, secureInput: false, playbackTag: recorderPlaybackTag)
_ = recording.observe(recordedKey(0, time: 3), isOwnEvent: false, secureInput: true, playbackTag: recorderPlaybackTag)
let playbackKey = recordedKey(0, time: 4)
playbackKey.setIntegerValueField(.eventSourceUserData, value: recorderPlaybackTag)
_ = recording.observe(playbackKey, isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag)
try check(recording.actions.count == 1, "Own-app, secure and synthetic playback input is excluded")
_ = recording.observe(recordedKey(36, time: 5), isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag)
try check(recording.actions.count == 3 && recording.actions[1].action == .wait && recording.actions[1].duration == 4 && recording.actions[2].key?.keyCode == 36, "Recorded input retains inter-event waits without counting ignored input")
let stopKey = recordedKey(53, time: 6, flags: [.maskControl, .maskAlternate])
try check(recording.observe(stopKey, isOwnEvent: true, secureInput: true, playbackTag: recorderPlaybackTag) && recording.actions.count == 3, "The physical stop shortcut works in own/secure contexts and is never saved")
let syntheticStop = recordedKey(53, flags: [.maskControl, .maskAlternate])
syntheticStop.setIntegerValueField(.eventSourceUserData, value: recorderPlaybackTag)
try check(!recording.observe(syntheticStop, isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag) && recording.actions.count == 3, "Synthetic playback cannot stop recording or add an action")
var modifierRecording = MacroRecordingBuffer()
_ = modifierRecording.observe(recordedKey(53, flags: [.maskControl, .maskAlternate, .maskShift]), isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag)
try check(modifierRecording.actions.count == 1 && modifierRecording.actions[0].key?.modifiers == [.control, .option, .shift], "Other Escape combinations remain recordable with their modifiers")
var mouseRecording = MacroRecordingBuffer()
let mouse = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: CGPoint(x: 120, y: 80), mouseButton: .right)!
_ = mouseRecording.observe(mouse, isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag)
try check(mouseRecording.actions.count == 1 && mouseRecording.actions[0].action == .click && mouseRecording.actions[0].option == "right" && mouseRecording.actions[0].x == 120 && mouseRecording.actions[0].y == 80, "Mouse observations retain button and global point coordinates")
var boundedRecording = MacroRecordingBuffer()
var limitReached = false
for _ in 0..<MacroRecordingBuffer.maximumActions {
    limitReached = boundedRecording.observe(recordedKey(12), isOwnEvent: false, secureInput: false, playbackTag: recorderPlaybackTag)
}
try check(limitReached && boundedRecording.actions.count == MacroRecordingBuffer.maximumActions, "Recording stops at its action limit without waiting for another key")
let componentIDs = OptionalTool.allCases.map(\.packageID) + WorkflowAction.allCases.map(\.packageID)
try check(Set(componentIDs).count == componentIDs.count, "Each optional feature has a unique package identifier")
try check(componentIDs.allSatisfy { $0.hasPrefix("tool.") || $0.hasPrefix("action.") }, "Triggers are not optional packages")
try check(FeatureComponentSupport.actionIDs == Set(WorkflowAction.allCases.map(\.packageID)), "Every workflow action has a component path")
print("Passed \(checks) model, persistence, validation, creator, sequence and shortcut checks.")
