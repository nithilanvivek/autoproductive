import AppKit
import AppIntents
import SwiftUI

struct SequenceEditorView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var siriPresenter: SiriShortcutPresenter
    @Environment(\.dismiss) private var dismiss
    let original: SavedAutomation?
    @State private var flow: WorkflowDefinition
    @State private var name: String
    @State private var shortcut: KeyboardShortcutDefinition?
    @State private var page: SequenceCreationStage = .triggers
    @State private var limitToApps: Bool
    @State private var error: String?

    init(existing: SavedAutomation? = nil) {
        original = existing
        let initial = SequenceDefinition.editing(existing)
        _flow = State(initialValue: initial)
        _name = State(initialValue: existing?.name ?? "New Sequence")
        _shortcut = State(initialValue: existing?.keyboardShortcut)
        _limitToApps = State(initialValue: !initial.scopedAppBundleIdentifiers.isEmpty)
    }

    private var missing: [String] { store.missingPermissions(for: flow) }
    private var pages: [SequenceCreationStage] { SequenceCreationStage.stages(needsPermissions: !missing.isEmpty) }
    private var pageIndex: Int { pages.firstIndex(of: page) ?? 0 }
    private var existingShortcuts: [KeyboardShortcutDefinition] {
        store.automations.filter { $0.id != original?.id }.compactMap(\.keyboardShortcut)
    }
    private func selected(_ trigger: SequenceTrigger) -> Bool { flow.sequenceTriggers?.contains(trigger) == true }
    private func selection(_ trigger: SequenceTrigger) -> Binding<Bool> {
        Binding(get: { selected(trigger) }, set: { enabled in
            var triggers = flow.sequenceTriggers ?? []
            if enabled && !triggers.contains(trigger) { triggers.append(trigger) }
            if !enabled { triggers.removeAll { $0 == trigger } }
            flow.sequenceTriggers = triggers
            if trigger == .screenPixel && enabled && flow.pixelCondition == nil {
                flow.pixelCondition = WorkflowStep(action: .screenPixel, text: "#FFFFFF")
                flow.pixelCheckInterval = 2
            }
            if trigger == .screenImage && enabled && flow.imageCondition == nil {
                flow.imageCondition = WorkflowStep(action: .screenImage)
                flow.imageCheckInterval = 2
            }
        })
    }

    var body: some View {
        EditorShell(title: AutomationKind.sequence.title,
                    subtitle: "Step \(pageIndex + 1) of \(pages.count): \(page.rawValue)",
                    symbol: AutomationKind.sequence.symbol, color: AppPalette.blue) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    ForEach(Array(pages.enumerated()), id: \.element) { index, stage in
                        Button { page = stage; error = nil } label: {
                            Text("\(index + 1)  \(stage.rawValue)")
                                .font(.system(size: 12, weight: stage == page ? .semibold : .regular))
                                .foregroundStyle(stage == page ? AppPalette.blue : .secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(stage == page ? AppPalette.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(stage == page ? "Current step" : "")
                    }
                }
                switch page {
                case .triggers: triggersPage
                case .actions: actionsPage
                case .scope: scopePage
                case .permissions: permissionsPage
                }
            }
        } footer: {
            HStack {
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Spacer()
                if pageIndex > 0 { Button("Back") { page = pages[pageIndex - 1]; error = nil } }
                if pageIndex < pages.count - 1 {
                    Button("Continue") { advance() }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(original == nil ? "Create Automation" : "Save Automation", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .navigationTitle(original == nil ? "New Sequence" : "Edit Sequence")
        .onChange(of: missing) { _, value in
            if value.isEmpty && page == .permissions { page = .scope }
        }
    }

    private var triggersPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Automation name", text: $name).textFieldStyle(.roundedBorder)
            Text("What should start this sequence?").font(.title2.weight(.semibold))
            Text("Choose one or more. Any selected trigger runs the same actions in order.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(SequenceTrigger.allCases) { trigger in
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(trigger.title, isOn: selection(trigger)).toggleStyle(.checkbox)
                    if selected(trigger) { triggerFields(trigger).padding(.leading, 22) }
                }
            }
        }
    }

    @ViewBuilder private func triggerFields(_ trigger: SequenceTrigger) -> some View {
        switch trigger {
        case .text:
            TextField("Typed phrase, for example Open Settings", text: $flow.abbreviation).textFieldStyle(.roundedBorder)
            Toggle("Case matters", isOn: Binding(get: { flow.matchesCase }, set: { flow.caseSensitive = $0 }))
            Toggle("Delete the phrase when triggered", isOn: Binding(get: { flow.shouldDeleteTriggerText }, set: { flow.deleteTriggerText = $0 }))
            Toggle("Wait for a space or punctuation after the phrase", isOn: $flow.requiresDelimiter)
            Label("If you want to type this without triggering the action, put the phrase in single or double quotes, then delete the quotes.", systemImage: "lightbulb")
                .font(.caption).foregroundStyle(.secondary)
        case .keyboardShortcut:
            KeyboardShortcutRecorder(shortcut: $shortcut, existingShortcuts: existingShortcuts)
        case .menuBar:
            Text("Run it using the robot icon in the menu bar.").font(.caption).foregroundStyle(.secondary)
        case .siri:
            Text("After saving, choose a phrase in the Add to Siri dialogue. Say that phrase to Siri to run this sequence.")
                .font(.caption).foregroundStyle(.secondary)
            if let siriError = siriPresenter.errorMessage {
                Text(siriError).font(.caption).foregroundStyle(.red)
            }
        case .touchpad:
            Picker("Two-finger swipe", selection: $flow.gesture) {
                ForEach(["up", "down", "left", "right"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            HStack {
                modifier("Control", .control); modifier("Option", .option)
                modifier("Shift", .shift); modifier("Command", .command)
            }
            Text("Hold at least one modifier while swiping so ordinary scrolling stays available.")
                .font(.caption).foregroundStyle(flow.gestureModifiers.isEmpty ? Color.red : Color.secondary)
        case .interval:
            interval("Run every", seconds: $flow.interval)
        case .screenPixel, .screenImage:
            let image = trigger == .screenImage
            let condition = image ? Binding($flow.imageCondition) : Binding($flow.pixelCondition)
            if let condition {
                WorkflowStepEditor(step: condition, remove: {}, move: { _ in },
                                   showsActionPicker: false, showsActionControls: false, showsWaitTimeout: false)
            }
            interval("Check every", seconds: Binding(get: { image ? flow.imageCheckInterval ?? 2 : flow.pixelCheckInterval ?? 2 }, set: {
                if image { flow.imageCheckInterval = $0 } else { flow.pixelCheckInterval = $0 }
            }))
            Text("Runs once when the condition changes from unmatched to matched.").font(.caption).foregroundStyle(.secondary)
        case .screen: EmptyView()
        }
    }

    private func modifier(_ title: String, _ modifier: ShortcutModifiers) -> some View {
        Toggle(title, isOn: Binding(get: { flow.gestureModifiers.contains(modifier) }, set: {
            if $0 { flow.gestureModifiers.insert(modifier) } else { flow.gestureModifiers.remove(modifier) }
        })).toggleStyle(.checkbox)
    }

    private func interval(_ title: String, seconds: Binding<Double>) -> some View {
        TriggerIntervalField(title: title, seconds: seconds)
    }

    private var actionsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should happen, in order?").font(.title2.weight(.semibold))
            ForEach($flow.steps) { $step in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Action \((flow.steps.firstIndex { $0.id == step.id } ?? 0) + 1)").font(.headline)
                    WorkflowStepEditor(step: $step, remove: { flow.steps.removeAll { $0.id == step.id } }, move: { offset in
                        if let index = flow.steps.firstIndex(where: { $0.id == step.id }), flow.steps.indices.contains(index + offset) {
                            flow.steps.swapAt(index, index + offset)
                        }
                    })
                }
            }
            Menu(flow.steps.isEmpty ? "Add First Action" : "Add Another Action", systemImage: "plus") {
                ForEach(WorkflowAction.chooserOrder) { action in
                    Button(action.title) { flow.steps.append(WorkflowStep(action: action, option: action.options.first ?? "")) }
                        .disabled(!FeatureAvailability.action(action))
                }
            }.disabled(flow.steps.count >= 200)
            Stepper("Repeat the sequence \(flow.repeatCount) time\(flow.repeatCount == 1 ? "" : "s")", value: $flow.repeatCount, in: 1...100)
            WorkflowVariableHelp()
        }
    }

    private var scopePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should the triggers work?").font(.title2.weight(.semibold))
            Toggle("Only when selected apps are frontmost", isOn: $limitToApps)
            if limitToApps {
                AppScopeSelectionView(identifiers: Binding(get: { flow.scopedAppBundleIdentifiers }, set: { flow.scopedAppBundleIdentifiers = $0 }),
                                      emptyLabel: "Select one or more apps", allowsAllApps: false)
            } else { Text("All apps (default)").foregroundStyle(.secondary) }
            Text("Automatic triggers and keyboard shortcuts use this limit. The robot menu Run button can still run it anywhere.")
                .font(.caption).foregroundStyle(.secondary)
            Text(missing.isEmpty ? "The automation will be enabled when created." : "The automation will stay disabled until the required permissions are granted.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow the access this sequence needs").font(.title2.weight(.semibold))
            ForEach(missing, id: \.self) { permission in
                Label(permission, systemImage: "hand.raised")
            }
            Text("Request Access explains why, then Continue opens the relevant macOS permission setting. You can also save now; this automation will remain disabled until access is granted.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Request Access") { store.requestPermissions(for: flow) }
            Button("Check Again") { store.enforcePermissions() }
        }
    }

    private func advance() {
        do {
            if page == .triggers { try validateTriggers() }
            if page == .actions { try SequenceDefinition.validate(flow, shortcut: selected(.keyboardShortcut) ? shortcut : nil) }
            if page == .scope { try validateScope() }
            error = nil; page = pages[min(pageIndex + 1, pages.count - 1)]
        } catch { DiagnosticJournal.shared.recordError("SequenceEditorView", error); self.error = error.localizedDescription }
    }

    private func validateTriggers() throws {
        var draft = flow
        draft.steps = [WorkflowStep(action: .wait)]
        try draft.validate()
        if selected(.keyboardShortcut) {
            guard let shortcut else { throw WorkflowError.invalid("Record the keyboard shortcut.") }
            if let conflict = ShortcutAnalyzer.conflictReason(shortcut, comparedWith: existingShortcuts) {
                throw WorkflowError.invalid(conflict)
            }
        }
    }

    private func validateScope() throws {
        if limitToApps && flow.scopedAppBundleIdentifiers.isEmpty {
            throw WorkflowError.invalid("Select at least one app or turn off the app limit.")
        }
    }

    private func save() {
        do {
            try validateTriggers(); try validateScope()
            try SequenceDefinition.validate(flow, shortcut: selected(.keyboardShortcut) ? shortcut : nil)
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkflowError.invalid("Give the automation a name.") }
            if flow.uses(.textExpansion), store.automations.contains(where: {
                $0.id != original?.id && $0.workflow?.uses(.textExpansion) == true &&
                $0.workflow?.abbreviation.localizedCaseInsensitiveCompare(flow.abbreviation) == .orderedSame
            }) { throw WorkflowError.invalid("That typed phrase is already used by another automation.") }
            var saved = original ?? SavedAutomation(name: name, kind: .sequence)
            saved.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            saved.keyboardShortcut = selected(.keyboardShortcut) ? shortcut : nil
            saved.siriEnabled = selected(.siri)
            var definition = flow
            definition.isEnabled = original?.isEnabled ?? true
            if !limitToApps { definition.scopedAppBundleIdentifiers = [] }
            saved.workflow = definition
            if let original, original.siriEnabled && !saved.siriEnabled {
                siriPresenter.removeShortcutBeforeDeleting(for: original) { removed in
                    if removed { persist(saved) }
                }
            } else { persist(saved) }
        } catch { DiagnosticJournal.shared.recordError("SequenceEditorView", error); self.error = error.localizedDescription }
    }

    private func persist(_ saved: SavedAutomation) {
        store.save(saved)
        AutoProductiveShortcuts.updateAppShortcutParameters()
        if saved.siriEnabled {
            siriPresenter.presentAddSheet(for: saved) { dismiss() }
        } else { dismiss() }
    }
}
