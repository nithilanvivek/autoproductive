import AppKit
import AppIntents
import SwiftUI
import UniformTypeIdentifiers

struct WorkflowEditorView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = WorkflowEngine.shared
    private let id: UUID
    private let createdAt: Date
    private let kind: AutomationKind
    private let original: SavedAutomation?
    @State private var name: String
    @State private var flow: WorkflowDefinition
    @State private var shortcut: KeyboardShortcutDefinition?
    @State private var error: String?

    init(kind: AutomationKind, existing: SavedAutomation? = nil) {
        self.kind = kind; original = existing
        id = existing?.id ?? UUID(); createdAt = existing?.createdAt ?? .now
        _name = State(initialValue: existing?.name ?? kind.title)
        _flow = State(initialValue: existing?.workflow ?? .template(for: kind))
        _shortcut = State(initialValue: existing?.keyboardShortcut)
    }

    var body: some View {
        EditorShell(title: kind.title, subtitle: kind.subtitle, symbol: kind.symbol, color: AppPalette.blue) {
            VStack(alignment: .leading, spacing: 22) {
                FormSection(title: "Automation Name") { TextField("Give this automation a name", text: $name).textFieldStyle(.roundedBorder) }
                FormSection(title: "When to Run") {
                    Picker("Trigger", selection: $flow.trigger) {
                        ForEach(WorkflowTrigger.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                    Toggle(flow.trigger == .keyRemap ? "Enable this remap" : "Enable automatic trigger and keyboard shortcut", isOn: $flow.isEnabled)
                    Text("You can always use Run in My Automations. Automatic triggers start only when enabled.")
                        .font(.caption).foregroundStyle(.secondary)
                    triggerFields
                }
                if flow.trigger != .keyRemap {
                    FormSection(title: "Keyboard Shortcut") {
                        KeyboardShortcutRecorder(shortcut: $shortcut, existingShortcuts: store.automations.filter { $0.id != id }.compactMap(\.keyboardShortcut))
                    }
                }
                FormSection(title: "Application Scope") {
                    AppScopeSelectionView(identifiers: Binding(
                        get: { flow.scopedAppBundleIdentifiers },
                        set: { flow.scopedAppBundleIdentifiers = $0 }
                    ))
                    Text("Automatic triggers run while any selected app is in front. Leave the list empty for all apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                FormSection(title: "Actions") {
                    Stepper("Repeat \(flow.repeatCount) time\(flow.repeatCount == 1 ? "" : "s")", value: $flow.repeatCount, in: 1...100)
                    ForEach($flow.steps) { $step in
                        WorkflowStepEditor(step: $step, remove: { flow.steps.removeAll { $0.id == step.id } }, move: { offset in
                            if let index = flow.steps.firstIndex(where: { $0.id == step.id }), flow.steps.indices.contains(index + offset) { flow.steps.swapAt(index, index + offset) }
                        })
                    }
                    Menu("Add Another Action", systemImage: "plus") {
                        ForEach(WorkflowAction.chooserOrder) { action in
                            Button(action.title) { flow.steps.append(WorkflowStep(action: action, option: action.options.first ?? "")) }
                                .disabled(!FeatureAvailability.action(action))
                        }
                    }.disabled(flow.steps.count >= 200)
                    WorkflowVariableHelp(dateUTCOffset: $flow.dateUTCOffset)
                }
                FormSection(title: "Background & Permissions") {
                    Toggle("Start AutoProductive Menu Bar Agent at login", isOn: Binding(get: { backgroundAgent.isEnabled }, set: { backgroundAgent.setEnabled($0) }))
                    Text("Global Text Triggers, remaps, touchpad shortcuts and input recording ask for Input Monitoring; actions that control other apps also need \(DesktopAutomationService.controlPermissionName). Screen conditions need Screen & System Audio Recording. AutoProductive keeps only a short in-memory phrase buffer for Text Triggers.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("\(DesktopAutomationService.controlPermissionName) Settings") { openSettings("Privacy_Accessibility") }
                        Button("Input Monitoring") { openSettings("Privacy_ListenEvent") }
                        Button("Screen Recording") { openSettings("Privacy_ScreenCapture") }
                    }.font(.caption)
                    if let message = backgroundAgent.errorMessage { Text(message).font(.caption).foregroundStyle(.red) }
                }
            }
        } footer: {
            HStack {
                VStack(alignment: .leading) {
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("Saved locally on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Automation", action: save).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(kind.title)
    }

    @ViewBuilder private var triggerFields: some View {
        switch flow.trigger {
        case .manual: EmptyView()
        case .textExpansion:
            TextField("Typed phrase, e.g. Open Settings", text: $flow.abbreviation).textFieldStyle(.roundedBorder)
            Toggle("Case matters", isOn: Binding(
                get: { flow.matchesCase },
                set: { flow.caseSensitive = $0 }
            ))
            Toggle("Delete the typed phrase when triggered", isOn: Binding(
                get: { flow.shouldDeleteTriggerText },
                set: { flow.deleteTriggerText = $0 }
            ))
            Toggle("Expand after Space, Return or punctuation", isOn: $flow.requiresDelimiter)
            Text("Type the phrase in an editable text field. It pauses in secure input fields.").font(.caption).foregroundStyle(.secondary)
        case .keyRemap:
            Picker("Source", selection: $flow.mouseButton) {
                Text("Keyboard key").tag(-1)
                Text("Left mouse button").tag(0); Text("Right mouse button").tag(1)
                Text("Middle mouse button").tag(2); Text("Mouse button 4").tag(3); Text("Mouse button 5").tag(4)
            }
            if flow.mouseButton == -1 { KeyboardShortcutRecorder(shortcut: $flow.inputKey, existingShortcuts: [], requiresModifiers: false) }
            Text("Choose one Press a key combination action as the destination. Disable the trigger to restore the original input.").font(.caption).foregroundStyle(.secondary)
        case .touchpad:
            Picker("Two-finger swipe direction", selection: $flow.gesture) { ForEach(["up", "down", "left", "right"], id: \.self) { Text($0.capitalized).tag($0) } }
            HStack { ForEach(modifierChoices, id: \.0) { label, modifier in
                Toggle(label, isOn: Binding(get: { flow.gestureModifiers.contains(modifier) }, set: { if $0 { flow.gestureModifiers.insert(modifier) } else { flow.gestureModifiers.remove(modifier) } })).toggleStyle(.checkbox)
            } }
            Text("Hold these modifiers while swiping with two fingers. Uses macOS continuous scroll events; direction follows the scroll direction setting. Three- and four-finger system gestures remain managed by macOS.")
                .font(.caption).foregroundStyle(flow.gestureModifiers.isEmpty ? Color.red : Color.secondary)
        case .interval, .screen:
            TriggerIntervalField(title: "Check every", seconds: $flow.interval)
            if flow.trigger == .screen { Text("Start with a pixel or image condition. Actions run once when the condition changes from unmatched to matched.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var modifierChoices: [(String, ShortcutModifiers)] { [("Control", .control), ("Option", .option), ("Shift", .shift), ("Command", .command)] }
    private func openSettings(_ pane: String) { PermissionSettings.openPane(pane) }
    private func save() {
        do {
            try flow.validate()
            if flow.trigger != .keyRemap, let shortcut, store.automations.contains(where: { $0.id != id && $0.keyboardShortcut?.keyCode == shortcut.keyCode && $0.keyboardShortcut?.modifiers == shortcut.modifiers }) {
                throw WorkflowError.invalid("That keyboard shortcut belongs to another automation.")
            }
            var automation = SavedAutomation(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                                            keyboardShortcut: flow.trigger == .keyRemap ? nil : shortcut, siriEnabled: original?.siriEnabled ?? false, createdAt: createdAt, workflow: flow)
            automation.appPath = original?.appPath
            store.save(automation); AutoProductiveShortcuts.updateAppShortcutParameters(); dismiss()
        } catch { DiagnosticJournal.shared.recordError("WorkflowEditorView", error); self.error = error.localizedDescription }
    }
}

struct WorkflowStepEditor: View {
    @Binding var step: WorkflowStep
    @State private var referenceImageError: String?
    @State private var clickSelectionError: String?
    let remove: () -> Void
    let move: (Int) -> Void
    var allowedActions = WorkflowAction.chooserOrder
    var showsActionPicker = true
    var showsActionControls = true
    var showsWaitTimeout = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsActionPicker || showsActionControls {
                HStack {
                    if showsActionPicker {
                        Picker("Action", selection: $step.action) {
                            ForEach(allowedActions) { action in
                                Text(action.title).tag(action).disabled(!FeatureAvailability.action(action))
                            }
                        }
                    }
                    if showsActionControls {
                        Button { move(-1) } label: { Image(systemName: "arrow.up") }.help("Move action up")
                        Button { move(1) } label: { Image(systemName: "arrow.down") }.help("Move action down")
                        Button(role: .destructive, action: remove) { Image(systemName: "trash") }.help("Remove action")
                    }
                }
            }
            if !FeatureAvailability.action(step.action) {
                Text("Install this action in Install/Delete Features to run it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !step.action.options.isEmpty {
                Picker("Operation", selection: $step.option) { ForEach(step.action.options, id: \.self) {
                    Text([WorkflowAction.adjustSound, .adjustBrightness].contains(step.action) ? PercentageAdjustment(rawValue: $0)?.title ?? $0 : $0).tag($0)
                } }
            }
            fields
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: step.action) { _, action in
            step.option = action.options.first ?? ""
            step.text = ""
            step.secondaryText = ""
            step.key = nil
            step.colorRegions = nil
            step.colorInEveryRegion = nil
            step.imageRegions = nil; step.imageSearchScope = action == .screenImage ? .entireScreen : nil
            if action == .screenPixel { step.text = "#FFFFFF"; step.amount = 10; step.duration = 5 }
            if [.adjustSound, .adjustBrightness].contains(action) { step.amount = 50 }
        }
    }
    @ViewBuilder private var fields: some View {
        switch step.action {
        case .composeMail:
            TextField("Recipient (optional)", text: $step.text).textFieldStyle(.roundedBorder)
            TextField("Subject (optional)", text: $step.option).textFieldStyle(.roundedBorder)
            textArea("Message", text: $step.secondaryText)
        case .pressKey: KeyboardShortcutRecorder(shortcut: $step.key, existingShortcuts: [], requiresModifiers: false)
        case .click, .movePointer, .scroll:
            coordinates
            if step.action == .click {
                Toggle("Coordinates are physical pixels on the primary display", isOn: Binding(
                    get: { step.coordinatesInPixels == true },
                    set: { step.coordinatesInPixels = $0 }
                ))
                Button("Record click position…", systemImage: "scope") { recordClickPosition() }
                    .help("Click once on the primary display to record its pixel coordinates. Press Esc to cancel.")
                if let clickSelectionError { Text(clickSelectionError).font(.caption).foregroundStyle(.red) }
            }
            Text(step.action == .scroll ? "Horizontal and vertical distance in pixels." :
                    step.coordinatesInPixels == true ? "Pixels from the top-left of the primary display." :
                    "Screen coordinates in points, measured from the top-left of the main screen.")
                .font(.caption).foregroundStyle(.secondary)
        case .wait: number("Seconds", value: $step.duration)
        case .window:
            if step.option == "custom" { coordinates; number("Width", value: $step.amount); TextField("Height", text: $step.secondaryText).textFieldStyle(.roundedBorder) }
        case .transformClipboard, .pasteClipboard: EmptyView()
        case .copyFile, .moveFile:
            path("Source", text: $step.text); path("Destination", text: $step.secondaryText, save: true)
        case .writeFile, .appendFile:
            path("File path", text: $step.text, save: true); textArea("Contents", text: $step.secondaryText)
        case .readFile, .trashFile, .createFolder, .openApp:
            path(step.action == .openApp ? "Application path" : "File or folder path", text: $step.text, save: step.action == .createFolder)
        case .shell, .appleScript:
            textArea(step.action == .shell ? "Shell command" : "AppleScript", text: $step.text); number("Timeout (seconds)", value: $step.duration)
        case .notification:
            TextField("Notification title (optional)", text: $step.text).textFieldStyle(.roundedBorder)
            textArea("Notification text", text: $step.secondaryText)
            Text("Use variables such as {{input}}, {{choice}}, or {{file}} from earlier actions.")
                .font(.caption).foregroundStyle(.secondary)
        case .prompt, .choose, .message:
            TextField("Title or question", text: $step.text).textFieldStyle(.roundedBorder)
            textArea(step.action == .choose ? "Choices, one per line (up to five)" : "Additional message", text: $step.secondaryText)
            if step.action == .message {
                Text("Cancel stops the sequence. Continue continues the sequence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .screenPixel:
            ScreenColorConditionEditor(step: $step)
            if showsWaitTimeout { number("Wait timeout (seconds)", value: $step.duration) }
        case .screenImage:
            path("Reference image", text: $step.text)
            if let referenceImageError { Text(referenceImageError).font(.caption).foregroundStyle(.red) }
            ScreenImageSearchEditor(step: $step)
            number("Color tolerance (0–255)", value: $step.amount)
            if showsWaitTimeout { number("Wait timeout (seconds)", value: $step.duration) }
        case .adjustSound, .adjustBrightness:
            number(step.option == "set" ? "Set to (%)" : "Change by (percentage points)", value: $step.amount)
            Text(step.action == .adjustSound ? "Adjusts the Mac’s default sound output from 0–100%." : "Adjusts the main display’s brightness from 0–100%, when supported by the display.")
                .font(.caption).foregroundStyle(.secondary)
        default: textArea(step.action == .openURL ? "https://… or file://…" : "Text to use", text: $step.text)
        }
    }
    private func recordClickPosition() {
        clickSelectionError = nil
        guard let screen = NSScreen.screens.first else { clickSelectionError = "No screen is available."; return }
        let scale = screen.backingScaleFactor
        let pixels = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        do {
            try ScreenRegionPicker.shared.select(mode: .clickPosition, primaryDisplayOnly: true) { point in
                step.x = max(0, min(pixels.width - 1, floor((point.x - screen.frame.minX) * scale)))
                step.y = max(0, min(pixels.height - 1, floor(point.y * scale)))
                step.coordinatesInPixels = true
            }
        } catch {
            DiagnosticJournal.shared.recordError("Click position", error)
            clickSelectionError = error.localizedDescription
        }
    }
    private var coordinates: some View { HStack { number("X", value: $step.x); number("Y", value: $step.y) } }
    private func number(_ label: String, value: Binding<Double>) -> some View { HStack { Text(label).font(.caption); TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder) } }
    private func textArea(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption).foregroundStyle(.secondary); TextEditor(text: text).font(.system(.body, design: .monospaced)).frame(minHeight: 65).padding(6).background(.background, in: RoundedRectangle(cornerRadius: 6)) }
    }
    private func path(_ label: String, text: Binding<String>, save: Bool = false) -> some View {
        HStack {
            TextField(label, text: text).textFieldStyle(.roundedBorder)
            Button("Choose…") {
                if save {
                    let panel = NSSavePanel(); panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { text.wrappedValue = url.path }
                } else {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
                    if step.action == .openApp {
                        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
                        panel.allowedContentTypes = [.application]
                        panel.canChooseDirectories = false
                    }
                    if step.action == .screenImage {
                        panel.allowedContentTypes = ScreenReferenceImage.contentTypes
                        panel.allowsOtherFileTypes = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                    }
                    if panel.runModal() == .OK, let url = panel.url {
                        if step.action == .screenImage {
                            do { _ = try ScreenReferenceImage.load(url.path); referenceImageError = nil }
                            catch { DiagnosticJournal.shared.recordError("WorkflowEditorView", error); referenceImageError = error.localizedDescription; return }
                        }
                        text.wrappedValue = url.path
                    }
                }
            }
        }
    }
}
