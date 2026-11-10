import Foundation

enum SequenceCreationStage: String, CaseIterable, Identifiable {
    case triggers = "Trigger", actions = "Actions", scope = "App scope", permissions = "Permissions"
    var id: String { rawValue }
    static func stages(needsPermissions: Bool) -> [Self] {
        [.triggers, .actions, .scope] + (needsPermissions ? [.permissions] : [])
    }
}

enum SequenceDefinition {
    static func editing(_ automation: SavedAutomation?) -> WorkflowDefinition {
        guard let automation else {
            var flow = WorkflowDefinition()
            flow.isEnabled = true; flow.sequenceTriggers = [.menuBar]; flow.steps = []
            flow.caseSensitive = false; flow.requiresDelimiter = false
            return flow
        }
        var flow = automation.workflow ?? WorkflowDefinition()
        if flow.sequenceTriggers != nil {
            if automation.siriEnabled && flow.sequenceTriggers?.contains(.siri) != true { flow.sequenceTriggers?.append(.siri) }
            return splitScreenTrigger(flow)
        }
        var triggers: [SequenceTrigger] = [.menuBar]
        if automation.siriEnabled { triggers.append(.siri) }
        if automation.keyboardShortcut != nil { triggers.append(.keyboardShortcut) }
        switch flow.trigger {
        case .textExpansion: triggers.append(.text)
        case .touchpad: triggers.append(.touchpad)
        case .interval: triggers.append(.interval)
        case .screen:
            triggers.append(.screen)
            flow.screenCondition = flow.steps.first
            flow.steps = Array(flow.steps.dropFirst())
        default: break
        }
        if automation.workflow == nil {
            flow.isEnabled = automation.isEnabled
            flow.scopedAppBundleIdentifiers = automation.scopedAppBundleIdentifiers
            if automation.kind == .openApp { flow.steps = [WorkflowStep(action: .openApp, text: automation.appPath ?? "")] }
            if automation.kind == .composeMail {
                var draft = WorkflowStep(action: .composeMail, text: automation.recipient, option: automation.subject)
                draft.secondaryText = automation.message; flow.steps = [draft]
            }
        }
        flow.sequenceTriggers = triggers
        return splitScreenTrigger(flow)
    }

    private static func splitScreenTrigger(_ original: WorkflowDefinition) -> WorkflowDefinition {
        var flow = original
        guard flow.sequenceTriggers?.contains(.screen) == true else { return flow }
        let image = flow.screenCondition?.action == .screenImage
        let trigger: SequenceTrigger = image ? .screenImage : .screenPixel
        var seen = Set<SequenceTrigger>()
        flow.sequenceTriggers = flow.sequenceTriggers?.map { $0 == .screen ? trigger : $0 }.filter { seen.insert($0).inserted }
        if image {
            flow.imageCondition = flow.imageCondition ?? flow.screenCondition
            flow.imageCheckInterval = flow.imageCheckInterval ?? flow.screenCheckInterval ?? flow.interval
        } else {
            flow.pixelCondition = flow.pixelCondition ?? flow.screenCondition
            flow.pixelCheckInterval = flow.pixelCheckInterval ?? flow.screenCheckInterval ?? flow.interval
        }
        flow.screenCondition = nil; flow.screenCheckInterval = nil
        return flow
    }

    static func validate(_ flow: WorkflowDefinition, shortcut: KeyboardShortcutDefinition?) throws {
        try flow.validate()
        if flow.sequenceTriggers?.contains(.keyboardShortcut) == true && shortcut == nil {
            throw WorkflowError.invalid("Record the keyboard shortcut or turn off that trigger.")
        }
        for step in flow.steps {
            switch step.action {
            case .typeText:
                guard !step.text.isEmpty else { throw WorkflowError.invalid("Enter the text to type.") }
            case .openApp, .openURL, .readFile, .writeFile, .appendFile, .copyFile, .moveFile, .createFolder, .trashFile:
                guard !step.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw WorkflowError.invalid("Choose the application, website or file path for \(step.action.title).")
                }
                if [.copyFile, .moveFile].contains(step.action) && step.secondaryText.isEmpty {
                    throw WorkflowError.invalid("Choose the destination path.")
                }
            case .choose:
                let choices = step.secondaryText.components(separatedBy: .newlines).filter { !$0.isEmpty }
                guard (1...5).contains(choices.count) else { throw WorkflowError.invalid("Enter one to five choices, one per line.") }
            default: break
            }
        }
    }
}
