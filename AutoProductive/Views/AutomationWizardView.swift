import AppKit
import AppIntents
import SwiftUI
import UniformTypeIdentifiers

struct AutomationWizardView: View {
    @EnvironmentObject private var store: AutomationStore
    @Environment(\.dismiss) private var dismiss

    let kind: AutomationKind
    @State private var page: AutomationWizardStage
    @State private var name: String
    @State private var flow: WorkflowDefinition
    @State private var appPath: String?
    @State private var recipient = ""
    @State private var subject = ""
    @State private var message = ""
    @State private var shortcut: KeyboardShortcutDefinition?
    @State private var limitToApp = false
    @State private var appScopes: [String] = []
    @State private var enableTrigger = true
    @State private var errorMessage: String?
    @State private var newAction: WorkflowAction = .typeText

    private var primaryAction: WorkflowAction { flow.steps.first?.action ?? .typeText }
    private var pages: [AutomationWizardPage] { AutomationWizardPlan.pages(for: kind, primaryAction: primaryAction) }
    private var pageIndex: Int { pages.firstIndex { $0.id == page } ?? 0 }
    private var supportsScope: Bool { AutomationWizardPlan.supportsAppScope(trigger: flow.trigger, shortcut: shortcut) }
    private var hasDedicatedScopePage: Bool { pages.contains { $0.id == .scope } }
    private var hasRunOptionsPage: Bool { pages.contains { $0.id == .runOptions } }
    private var scopedApps: [String] { supportsScope && limitToApp ? appScopes : [] }
    private var primaryStep: Binding<WorkflowStep> {
        Binding(get: { flow.steps.first ?? WorkflowStep() }, set: { step in
            if flow.steps.isEmpty { flow.steps = [step] } else { flow.steps[0] = step }
        })
    }
    private var actionSteps: Binding<[WorkflowStep]> {
        Binding(get: { kind == .screen || kind == .dialog ? Array(flow.steps.dropFirst()) : flow.steps },
                set: { steps in
            if (kind == .screen || kind == .dialog), let first = flow.steps.first { flow.steps = [first] + steps }
            else { flow.steps = steps }
        })
    }

    init(kind: AutomationKind) {
        self.kind = kind
        _name = State(initialValue: kind.title)
        var initialFlow = WorkflowDefinition.template(for: kind)
        if kind == .textExpansion {
            initialFlow.abbreviation = ""
            initialFlow.requiresDelimiter = false
            initialFlow.caseSensitive = false
        }
        _flow = State(initialValue: initialFlow)
        _page = State(initialValue: AutomationWizardPlan.pages(for: kind, primaryAction: initialFlow.steps.first?.action ?? .typeText)[0].id)
    }

    var body: some View {
        EditorShell(
            title: kind.title,
            subtitle: "Step \(pageIndex + 1) of \(pages.count): \(pages[pageIndex].title)",
            symbol: kind.symbol,
            color: kind == .composeMail ? AppPalette.indigo : AppPalette.blue
        ) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button {
                            errorMessage = nil
                            page = pages[index].id
                        } label: {
                            Text("\(index + 1)  \(pages[index].title)")
                                .font(.system(size: 12, weight: index == pageIndex ? .semibold : .regular))
                                .foregroundStyle(index == pageIndex ? AppPalette.blue : .secondary)
                                .lineLimit(2).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(index == pageIndex ? AppPalette.blue.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Go to \(pages[index].title)")
                        .accessibilityValue(index == pageIndex ? "Current step" : "")
                    }
                }
                Group {
                    switch page {
                    case .application: applicationPage
                    case .recipient: recipientPage
                    case .mailMessage: mailMessagePage
                    case .phrase, .sourceInput, .gesture: triggerPage
                    case .destinationKey: destinationPage
                    case .gestureModifiers: gestureModifiersPage
                    case .windowLayout: primaryDetailsPage(title: "How should the front window be arranged?")
                    case .operation, .scriptLanguage, .dialogType: operationPage
                    case .details: primaryDetailsPage(title: detailsTitle)
                    case .condition: conditionPage
                    case .monitoring: monitoringPage
                    case .followUp: followUpPage
                    case .actions: actionPage
                    case .runOptions: runOptionsPage
                    case .scope: scopePage
                    case .review: reviewPage
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                if pageIndex > 0 {
                    Button("Back") { errorMessage = nil; page = pages[pageIndex - 1].id }
                }
                if pageIndex < pages.count - 1 {
                    Button("Continue", action: advance)
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Save Automation", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .navigationTitle("New \(kind.title)")
        .onAppear { restoreDraft() }
        .onChange(of: name) { _, _ in saveDraft() }
        .onChange(of: flow) { _, _ in saveDraft() }
        .onChange(of: page) { _, _ in saveDraft() }
        .onChange(of: shortcut) { _, _ in saveDraft() }
        .onChange(of: appPath) { _, _ in saveDraft() }
        .onChange(of: recipient) { _, _ in saveDraft() }
        .onChange(of: subject) { _, _ in saveDraft() }
        .onChange(of: message) { _, _ in saveDraft() }
        .onChange(of: limitToApp) { _, _ in saveDraft() }
        .onChange(of: appScopes) { _, _ in saveDraft() }
        .onChange(of: enableTrigger) { _, _ in saveDraft() }
    }

    private var applicationPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which application should open?").font(.title2.weight(.semibold))
            Button("Choose Application…") { chooseApplication { appPath = $0.path } }
            if let appPath {
                Label(URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent,
                      systemImage: "app")
                Text(appPath).font(.caption).foregroundStyle(.secondary)
            }
            Text("Choose an app from Applications. Set its optional keyboard shortcut on the next screen.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var recipientPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who is the email for?").font(.title2.weight(.semibold))
            TextField("Recipient email (optional)", text: $recipient).textFieldStyle(.roundedBorder)
            Text("Leave this blank to choose a recipient later. This automation prepares a draft in your default mail app; you send it yourself.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var mailMessagePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should the draft say?").font(.title2.weight(.semibold))
            TextField("Subject (optional)", text: $subject).textFieldStyle(.roundedBorder)
            Text("Message").font(.headline)
            TextEditor(text: $message).frame(minHeight: 150)
                .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var destinationPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What key should it send instead?").font(.title2.weight(.semibold))
            KeyboardShortcutRecorder(shortcut: primaryStep.key, existingShortcuts: [], requiresModifiers: false)
            Text("Record one key or a key combination. Disabling this automation restores the original input.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var gestureModifiersPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which keys should you hold while swiping?").font(.title2.weight(.semibold))
            HStack {
                modifierToggle("Control", modifier: .control)
                modifierToggle("Option", modifier: .option)
                modifierToggle("Shift", modifier: .shift)
                modifierToggle("Command", modifier: .command)
            }
            Text("Choose at least one modifier so ordinary two-finger scrolling keeps working. Swipe direction follows your Mac’s scrolling setting.")
                .font(.callout).foregroundStyle(flow.gestureModifiers.isEmpty ? Color.red : Color.secondary)
        }
    }

    private func modifierToggle(_ title: String, modifier: ShortcutModifiers) -> some View {
        Toggle(title, isOn: Binding(
            get: { flow.gestureModifiers.contains(modifier) },
            set: { if $0 { flow.gestureModifiers.insert(modifier) } else { flow.gestureModifiers.remove(modifier) } }
        )).toggleStyle(.checkbox)
    }

    private var operationPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .script ? "What kind of script will run?" : kind == .dialog ? "What should the form ask or show?" : "What should this automation do?")
                .font(.title2.weight(.semibold))
            operationPicker
            Text(kind == .script ? "Enter the code and execution timeout on the next screen." :
                    kind == .dialog ? "Next, write the question, choices or message." :
                    kind == .files ? "Next, choose the files and paths for this operation." :
                    primaryAction == .pasteClipboard ? "Paste the current clipboard into the frontmost app. No text configuration is needed." :
                    "Next, configure the text or transformation.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var operationPicker: some View {
        Picker(kind == .script ? "Script type" : "Operation", selection: Binding(
            get: { primaryAction }, set: { setPrimaryAction($0) }
        )) {
            ForEach(AutomationWizardPlan.primaryActions(for: kind)) { Text($0.title).tag($0) }
        }
    }

    private func setPrimaryAction(_ action: WorkflowAction) {
        guard primaryAction != action else { return }
        primaryStep.wrappedValue = WorkflowStep(action: action, option: action.options.first ?? "")
        if kind == .dialog && action == .message { flow.steps = Array(flow.steps.prefix(1)) }
    }

    private var detailsTitle: String {
        switch kind {
        case .script: "What code should run?"
        case .files: "Which files or folders should it use?"
        case .dialog: primaryAction == .message ? "What message should appear?" : "What should the form say?"
        default: "How should the clipboard text change?"
        }
    }

    private func primaryDetailsPage(title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            WorkflowStepEditor(step: primaryStep, remove: {}, move: { _ in },
                               showsActionPicker: false, showsActionControls: false)
        }
    }

    private var conditionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should AutoProductive watch for?").font(.title2.weight(.semibold))
            operationPicker
            WorkflowStepEditor(step: primaryStep, remove: {}, move: { _ in },
                               showsActionPicker: false, showsActionControls: false, showsWaitTimeout: false)
        }
    }

    private var monitoringPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How often should it check the screen?").font(.title2.weight(.semibold))
            intervalField
            Text("The response runs once when the condition changes from unmatched to matched. Screen Recording permission is needed to inspect the pixel or image.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var followUpPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How should it use the answer?").font(.title2.weight(.semibold))
            Toggle("Run actions after the form is answered", isOn: Binding(
                get: { flow.steps.count > 1 },
                set: { enabled in
                    if enabled && flow.steps.count == 1 {
                        flow.steps.append(WorkflowStep(text: primaryAction == .choose ? "{{choice}}" : "{{input}}"))
                    } else if !enabled { flow.steps = Array(flow.steps.prefix(1)) }
                }
            ))
            if flow.steps.count > 1 {
                Text(primaryAction == .choose ? "Use {{choice}} in an action to insert the selected answer." : "Use {{input}} in an action to insert the entered text.")
                    .font(.callout).foregroundStyle(.secondary)
                actionPage
            } else {
                Text("The form will display on its own. Turn this on to pass the answer into more actions.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var intervalField: some View {
        TriggerIntervalField(title: "Every", seconds: $flow.interval)
    }

    private var runOptionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind == .openApp ? "How should you launch it?" : "How should this automation run?")
                .font(.title2.weight(.semibold))
            if kind != .openApp && kind != .composeMail {
                Picker("Run", selection: $flow.trigger) {
                    Text("On demand").tag(WorkflowTrigger.manual)
                    Text("At a repeated interval").tag(WorkflowTrigger.interval)
                }
                if flow.trigger == .interval { intervalField }
                Stepper("Repeat the actions \(flow.repeatCount) time\(flow.repeatCount == 1 ? "" : "s") per run",
                        value: $flow.repeatCount, in: 1...100)
            }
            Text("Optional keyboard shortcut").font(.headline)
            KeyboardShortcutRecorder(shortcut: $shortcut, existingShortcuts: store.automations.compactMap(\.keyboardShortcut))
            Text("You can always run the automation from the robot menu or My Automations.")
                .font(.caption).foregroundStyle(.secondary)
            if supportsScope && !hasDedicatedScopePage {
                Divider()
                scopePage
            }
        }
    }

    private var triggerSummary: String {
        switch flow.trigger {
        case .manual: shortcut.map { "Keyboard shortcut \($0.displayText), or Run" } ?? "Run in the robot menu or My Automations"
        case .textExpansion: "Typing “\(flow.abbreviation)”"
        case .keyRemap: flow.mouseButton >= 0 ? "Mouse button \(flow.mouseButton + 1)" : flow.inputKey?.displayText ?? "Unrecorded key"
        case .touchpad: "\(flow.gestureModifiers.symbols) + two-finger swipe \(flow.gesture)"
        case .interval: "Every \(flow.interval.formatted()) seconds"
        case .screen: "Screen condition, checked every \(flow.interval.formatted()) seconds"
        }
    }

    @ViewBuilder private var triggerPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .textExpansion ? "What should you type?" : kind == .keyRemap ? "Which key or button should change?" : "Which two-finger swipe should run the action?")
                .font(.title2.weight(.semibold))
            if kind == .textExpansion {
                TextField("For example: Open Settings", text: $flow.abbreviation)
                    .textFieldStyle(.roundedBorder)
                Text("Type this phrase into an editable text field in another app to run the action on the next screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Case matters", isOn: Binding(
                    get: { flow.matchesCase },
                    set: { flow.caseSensitive = $0 }
                ))
                Toggle("Delete the typed phrase when triggered", isOn: Binding(
                    get: { flow.shouldDeleteTriggerText },
                    set: { flow.deleteTriggerText = $0 }
                ))
                Toggle("Wait for a space or punctuation after the phrase", isOn: $flow.requiresDelimiter)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Tip", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.blue)
                    Text("If you want to type this without triggering the action, put the phrase in single or double quotes, then delete the quotes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else if kind == .keyRemap {
                Text("Choose the source key or mouse button.")
                    .foregroundStyle(.secondary)
                Picker("Source", selection: $flow.mouseButton) {
                    Text("Keyboard key").tag(-1)
                    Text("Left mouse button").tag(0)
                    Text("Right mouse button").tag(1)
                    Text("Middle mouse button").tag(2)
                    Text("Mouse button 4").tag(3)
                    Text("Mouse button 5").tag(4)
                }
                if flow.mouseButton == -1 {
                    KeyboardShortcutRecorder(shortcut: $flow.inputKey, existingShortcuts: [], requiresModifiers: false)
                }
            } else if kind == .touchpad {
                Picker("Two-finger swipe", selection: $flow.gesture) {
                    ForEach(["up", "down", "left", "right"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Text("Choose which direction to swipe. Pick the keys to hold on the next screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var clickingKeyboardActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add steps in the order they should run. Each step clicks a screen coordinate, types text, or presses a key or shortcut.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if flow.steps.isEmpty {
                Text("No steps yet. Add the first action below.")
                    .foregroundStyle(.secondary)
            }
            ForEach($flow.steps) { $step in
                ClickKeyboardStepEditor(
                    step: $step,
                    number: (flow.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1,
                    canMoveUp: flow.steps.first?.id != step.id,
                    canMoveDown: flow.steps.last?.id != step.id,
                    move: { offset in
                        guard let index = flow.steps.firstIndex(where: { $0.id == step.id }),
                              flow.steps.indices.contains(index + offset) else { return }
                        flow.steps.swapAt(index, index + offset)
                    },
                    remove: { flow.steps.removeAll { $0.id == step.id } }
                )
            }
            Menu {
                Button("Click a screen coordinate", systemImage: "cursorarrow.click.2") {
                    var step = WorkflowStep(action: .click, option: "left")
                    step.coordinatesInPixels = true
                    step.x = -1
                    step.y = -1
                    flow.steps.append(step)
                }
                Button("Type text", systemImage: "textformat") {
                    flow.steps.append(WorkflowStep(action: .typeText))
                }
                Button("Press a key or shortcut", systemImage: "keyboard") {
                    flow.steps.append(WorkflowStep(action: .pressKey))
                }
            } label: {
                Label(flow.steps.isEmpty ? "Add First Step" : "Add Next Step", systemImage: "plus")
            }
            .disabled(flow.steps.count >= 200)
            Text("Click coordinates use physical pixels from the top-left of the primary display. Actions run in the order shown.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .workflow || kind == .clickingKeyboard ? "Build the steps in order" : "What should happen next?")
                .font(.title2.weight(.semibold))
            if kind == .clickingKeyboard {
                clickingKeyboardActions
            } else {
                ForEach(actionSteps) { $step in
                    WorkflowStepEditor(
                        step: $step,
                        remove: { flow.steps.removeAll { $0.id == step.id } },
                        move: { offset in
                            if let index = flow.steps.firstIndex(where: { $0.id == step.id }),
                               flow.steps.indices.contains(index + offset),
                               index + offset >= (kind == .screen || kind == .dialog ? 1 : 0) {
                                flow.steps.swapAt(index, index + offset)
                            }
                        }
                    )
                }
                HStack {
                    Picker("Next action", selection: $newAction) {
                        ForEach(WorkflowAction.chooserOrder) { action in
                            Text(action.title).tag(action).disabled(!FeatureAvailability.action(action))
                        }
                    }
                    Button("Add Action") {
                        flow.steps.append(WorkflowStep(action: newAction, option: newAction.options.first ?? ""))
                    }
                    .disabled(flow.steps.count >= 200 || !FeatureAvailability.action(newAction))
                }
                if kind == .textExpansion {
                    Text("For “Open Settings”, choose Open an application and select System Settings.app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var scopePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should it work?")
                .font(.title2.weight(.semibold))
            Text("By default, it works in every app. You can select several apps where its trigger should work.")
                .foregroundStyle(.secondary)
            Toggle("Only when selected apps are frontmost", isOn: $limitToApp)
            if limitToApp {
                AppScopeSelectionView(identifiers: $appScopes, emptyLabel: "No apps selected yet", allowsAllApps: false)
                Text("The menu bar Run button still works anywhere; this limit applies to automatic triggers and keyboard shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var reviewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name and check your automation")
                .font(.title2.weight(.semibold))
            TextField("Automation name", text: $name)
                .textFieldStyle(.roundedBorder)
            if !hasRunOptionsPage && kind != .keyRemap {
                DisclosureGroup("Optional keyboard shortcut") {
                    KeyboardShortcutRecorder(shortcut: $shortcut,
                        existingShortcuts: store.automations.compactMap(\.keyboardShortcut), compact: true)
                }
            }
            if kind != .openApp && kind != .composeMail && supportsScope {
                Toggle("Enable the trigger when saved", isOn: $enableTrigger)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Starts with: \(triggerSummary)")
                Text("Action: \(kind == .keyRemap ? "Send \(flow.steps.first?.key?.displayText ?? "unrecorded key")" : kind == .openApp ? "Open application" : kind == .composeMail ? "Compose mail" : flow.steps.map { $0.action.title }.joined(separator: " → "))")
                if kind == .clickingKeyboard {
                    ForEach(Array(flow.steps.enumerated()), id: \.element.id) { index, step in
                        Text("\(index + 1). \(stepSummary(step))")
                    }
                    Label("Clicking and keyboard playback need \(DesktopAutomationService.controlPermissionName) permission to control other apps.",
                          systemImage: "hand.raised")
                    Button("Open \(DesktopAutomationService.controlPermissionName) Settings") {
                        PermissionSettings.open(DesktopAutomationService.controlPermissionName)
                    }
                }
                if supportsScope { Text("App scope: \(scopedApps.isEmpty ? "All apps" : scopedApps.joined(separator: ", "))") }
                if kind != .keyRemap, let shortcut { Text("Keyboard shortcut: \(shortcut.displayText)") }
                if kind == .openApp, let appPath { Text("Application: \(appPath)") }
                if kind == .composeMail {
                    Text("To: \(recipient.isEmpty ? "Choose in the mail app" : recipient)")
                    Text("Subject: \(subject.isEmpty ? "None" : subject)")
                }
                if kind != .openApp && kind != .composeMail && kind != .keyRemap { Text("Repeat: \(flow.repeatCount)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func chooseApplication(_ selected: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { selected(url) }
    }

    private func advance() {
        do {
            try validateCurrentPage()
            errorMessage = nil
            page = pages[pageIndex + 1].id
        } catch { DiagnosticJournal.shared.recordError("AutomationWizardView", error); errorMessage = error.localizedDescription }
    }

    private func validateCurrentPage() throws {
        switch page {
        case .application:
            guard appPath != nil else { throw WorkflowError.invalid("Choose an application to open.") }
        case .phrase:
            guard !flow.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  flow.abbreviation.count <= 64, !flow.abbreviation.contains(where: \.isNewline) else {
                throw WorkflowError.invalid("Use a typed phrase of 1–64 characters on one line.")
            }
        case .sourceInput:
            guard flow.mouseButton >= 0 || flow.inputKey != nil else {
                throw WorkflowError.invalid("Record the key that should be remapped.")
            }
        case .gestureModifiers:
            guard !flow.gestureModifiers.isEmpty else {
                throw WorkflowError.invalid("Choose at least one modifier to keep ordinary scrolling available.")
            }
        case .destinationKey, .details, .windowLayout, .condition:
            try validateActions([primaryStep.wrappedValue])
        case .actions:
            if kind == .clickingKeyboard { try validateClickingKeyboardSteps() }
            else { try validateActions(actionSteps.wrappedValue) }
        case .followUp:
            if flow.steps.count > 1 { try validateActions(actionSteps.wrappedValue) }
        case .monitoring, .runOptions:
            guard flow.interval.isFinite && (0.5...86400).contains(flow.interval) else {
                throw WorkflowError.invalid("Choose an interval between 0.5 seconds and one day.")
            }
            if page == .runOptions { try validateScope() }
        case .scope: try validateScope()
        default: break
        }
    }

    private func validateScope() throws {
        if supportsScope && limitToApp && appScopes.isEmpty {
            throw WorkflowError.invalid("Choose at least one app or turn off the app limit.")
        }
    }

    private func validateActions(_ steps: [WorkflowStep]) throws {
        var validation = WorkflowDefinition()
        validation.steps = steps
        try validation.validate()
        for step in steps {
            switch step.action {
            case .openApp, .readFile, .writeFile, .appendFile, .copyFile, .moveFile, .createFolder, .trashFile:
                guard !step.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw WorkflowError.invalid(step.action == .openApp ? "Choose the application to open." : "Choose a file or folder path.")
                }
                if step.action == .copyFile || step.action == .moveFile {
                    guard !step.secondaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw WorkflowError.invalid("Choose the destination path.")
                    }
                }
            case .prompt, .message, .choose, .notification:
                guard !step.text.isEmpty || !step.secondaryText.isEmpty else {
                    throw WorkflowError.invalid("Enter the question or message to display.")
                }
                if step.action == .choose {
                    let choices = step.secondaryText.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    guard (1...5).contains(choices.count) else {
                        throw WorkflowError.invalid("Enter one to five choices, one per line.")
                    }
                }
            default: break
            }
        }
    }

    private func validateClickingKeyboardSteps() throws {
        guard !flow.steps.isEmpty else { throw WorkflowError.invalid("Add at least one click, typing, or key step.") }
        for (index, step) in flow.steps.enumerated() {
            switch step.action {
            case .click:
                guard step.x.isFinite && step.y.isFinite else {
                    throw WorkflowError.invalid("Step \(index + 1): enter valid X and Y coordinates.")
                }
                if step.coordinatesInPixels == true {
                    guard let screen = NSScreen.screens.first,
                          step.x >= 0, step.y >= 0,
                          step.x < screen.frame.width * screen.backingScaleFactor,
                          step.y < screen.frame.height * screen.backingScaleFactor else {
                        throw WorkflowError.invalid("Step \(index + 1): choose a pixel coordinate on the primary display.")
                    }
                }
            case .typeText:
                guard !step.text.isEmpty else { throw WorkflowError.invalid("Step \(index + 1): enter text to type.") }
            case .pressKey:
                guard step.key != nil else { throw WorkflowError.invalid("Step \(index + 1): record a key or shortcut.") }
            default:
                throw WorkflowError.invalid("Step \(index + 1): choose a click, typing, or key action.")
            }
        }
    }

    private func stepSummary(_ step: WorkflowStep) -> String {
        switch step.action {
        case .click: "\(step.option.capitalized) click at (\(step.x.formatted()), \(step.y.formatted())) \(step.coordinatesInPixels == true ? "pixels" : "points")"
        case .typeText: "Type \(step.text.prefix(40))\(step.text.count > 40 ? "…" : "")"
        case .pressKey: "Press \(step.key?.displayText ?? "unrecorded key")"
        default: step.action.title
        }
    }

    private func save() {
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { throw WorkflowError.invalid("Give the automation a name.") }
            try validateScope()
            if let shortcut, store.automations.contains(where: {
                $0.keyboardShortcut?.keyCode == shortcut.keyCode &&
                $0.keyboardShortcut?.modifiers == shortcut.modifiers
            }) {
                throw WorkflowError.invalid("That keyboard shortcut belongs to another automation.")
            }
            var automation: SavedAutomation
            if kind == .openApp {
                guard let appPath else { throw WorkflowError.invalid("Choose an application to open.") }
                automation = SavedAutomation(name: trimmedName, kind: kind, appPath: appPath,
                                             keyboardShortcut: shortcut,
                                             appScopeBundleIdentifiers: scopedApps)
            } else if kind == .composeMail {
                automation = SavedAutomation(name: trimmedName, kind: kind, recipient: recipient,
                                             subject: subject, message: message, keyboardShortcut: shortcut,
                                             appScopeBundleIdentifiers: scopedApps)
            } else {
                var savedFlow = flow
                if kind == .clickingKeyboard { try validateClickingKeyboardSteps() }
                try validateActions(savedFlow.steps)
                savedFlow.isEnabled = enableTrigger
                savedFlow.scopedAppBundleIdentifiers = scopedApps
                if savedFlow.trigger == .textExpansion,
                   store.automations.contains(where: {
                       $0.workflow?.trigger == .textExpansion &&
                       $0.workflow?.abbreviation.localizedCaseInsensitiveCompare(savedFlow.abbreviation) == .orderedSame
                   }) {
                    throw WorkflowError.invalid("That typed phrase is already in use.")
                }
                try savedFlow.validate()
                if savedFlow.steps.contains(where: { $0.action == .openApp && $0.text.isEmpty }) {
                    throw WorkflowError.invalid("Choose the application that the action should open.")
                }
                automation = SavedAutomation(name: trimmedName, kind: kind, keyboardShortcut: kind == .keyRemap ? nil : shortcut,
                                             workflow: savedFlow)
            }
            store.save(automation)
            AutomationDraftStorage.clear()
            if kind == .openApp || kind == .composeMail {
                AutoProductiveShortcuts.updateAppShortcutParameters()
            }
            dismiss()
        } catch {
            DiagnosticJournal.shared.recordError("AutomationWizardView", error); errorMessage = error.localizedDescription
        }
    }

    private func restoreDraft() {
        guard let draft = AutomationDraftStorage.load(), draft.editor == .wizard, draft.kind == kind else { return }
        name = draft.name; flow = draft.flow; shortcut = draft.shortcut
        appPath = draft.appPath; recipient = draft.recipient; subject = draft.subject; message = draft.message
        limitToApp = draft.limitToApps; appScopes = draft.appScopes; enableTrigger = draft.enableTrigger
        if let saved = draft.page.flatMap(AutomationWizardStage.init(rawValue:)), pages.contains(where: { $0.id == saved }) { page = saved }
    }

    private func saveDraft() {
        AutomationDraftStorage.save(AutomationDraft(editor: .wizard, kind: kind, originalID: nil, name: name,
            flow: flow, shortcut: shortcut, page: page.rawValue, limitToApps: limitToApp, appPath: appPath,
            recipient: recipient, subject: subject, message: message, appScopes: appScopes, enableTrigger: enableTrigger))
    }
}

private struct ClickKeyboardStepEditor: View {
    @Binding var step: WorkflowStep
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step \(number)").font(.headline)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "arrow.up") }
                    .disabled(!canMoveUp).help("Move step up")
                Button { move(1) } label: { Image(systemName: "arrow.down") }
                    .disabled(!canMoveDown).help("Move step down")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .help("Remove step")
            }
            Picker("Action", selection: $step.action) {
                Text("Click a coordinate").tag(WorkflowAction.click)
                Text("Type text").tag(WorkflowAction.typeText)
                Text("Press a key or shortcut").tag(WorkflowAction.pressKey)
            }
            switch step.action {
            case .click:
                HStack {
                    TextField("X", value: $step.x, format: .number)
                    TextField("Y", value: $step.y, format: .number)
                    Picker("Mouse button", selection: $step.option) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                        Text("Middle").tag("middle")
                    }
                }
                .textFieldStyle(.roundedBorder)
                Text("Replace X and Y with the pixel coordinates to click. Both are required.")
                    .font(.caption).foregroundStyle(.secondary)
            case .typeText:
                TextEditor(text: $step.text)
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 7))
            case .pressKey:
                KeyboardShortcutRecorder(shortcut: $step.key, existingShortcuts: [], requiresModifiers: false, compact: true)
                Text("Record one key, such as Return, or a combination such as Command–C.")
                    .font(.caption).foregroundStyle(.secondary)
            default: EmptyView()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: step.action) { _, action in
            step.text = ""
            step.key = nil
            step.option = action == .click ? "left" : ""
            step.coordinatesInPixels = action == .click ? true : nil
            if action == .click { step.x = -1; step.y = -1 }
        }
    }
}
