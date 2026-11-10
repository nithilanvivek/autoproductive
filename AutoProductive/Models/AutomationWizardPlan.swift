import Foundation

enum AutomationWizardStage: String, Hashable {
    case application, recipient, mailMessage, phrase, sourceInput, destinationKey
    case gesture, gestureModifiers, windowLayout, operation, scriptLanguage, dialogType
    case details, followUp, condition, monitoring, actions, runOptions, scope, review
}

struct AutomationWizardPage: Identifiable, Equatable {
    let id: AutomationWizardStage
    let title: String
}

enum AutomationWizardPlan {
    static func pages(for kind: AutomationKind, primaryAction: WorkflowAction) -> [AutomationWizardPage] {
        let steps: [(AutomationWizardStage, String)]
        switch kind {
        case .sequence:
            steps = [(.phrase, "Trigger"), (.actions, "Actions"), (.scope, "App scope"), (.review, "Review")]
        case .openApp:
            steps = [(.application, "Application"), (.runOptions, "Launch options"), (.review, "Review")]
        case .composeMail:
            steps = [(.recipient, "Recipient"), (.mailMessage, "Message"), (.runOptions, "Run options"), (.review, "Review")]
        case .textExpansion:
            steps = [(.phrase, "Typed phrase"), (.actions, "Response"), (.scope, "Apps"), (.review, "Review")]
        case .keyRemap:
            steps = [(.sourceInput, "Source input"), (.destinationKey, "New key"), (.scope, "Apps"), (.review, "Review")]
        case .touchpad:
            steps = [(.gesture, "Swipe"), (.gestureModifiers, "Modifiers"), (.actions, "Response"), (.scope, "Apps"), (.review, "Review")]
        case .windows:
            steps = [(.windowLayout, "Window layout"), (.runOptions, "Run options"), (.review, "Review")]
        case .clipboard:
            steps = [(.operation, "Clipboard action")]
                + (primaryAction == .pasteClipboard ? [] : [(.details, "Text options")])
                + [(.runOptions, "Run options"), (.review, "Review")]
        case .files:
            steps = [(.operation, "File operation"), (.details, "Files & paths"), (.runOptions, "Run options"), (.review, "Review")]
        case .script:
            steps = [(.scriptLanguage, "Script type"), (.details, "Script"), (.runOptions, "Run options"), (.review, "Review")]
        case .dialog:
            steps = [(.dialogType, "Form type"), (.details, "Content")]
                + (primaryAction == .message ? [] : [(.followUp, "Use the answer")])
                + [(.runOptions, "Run options"), (.review, "Review")]
        case .screen:
            steps = [(.condition, "Condition"), (.monitoring, "Detection"), (.actions, "Response"), (.scope, "Apps"), (.review, "Review")]
        case .workflow, .clickingKeyboard:
            steps = [(.actions, "Build sequence"), (.runOptions, "Run options"), (.review, "Review")]
        }
        return steps.map { AutomationWizardPage(id: $0.0, title: $0.1) }
    }

    static func primaryActions(for kind: AutomationKind) -> [WorkflowAction] {
        switch kind {
        case .clipboard: [.setClipboard, .transformClipboard, .pasteClipboard]
        case .files: [.readFile, .writeFile, .appendFile, .copyFile, .moveFile, .createFolder, .trashFile]
        case .script: [.shell, .appleScript]
        case .dialog: [.prompt, .choose, .message]
        case .screen: [.screenPixel, .screenImage]
        case .windows: [.window]
        default: WorkflowAction.allCases
        }
    }

    static func supportsAppScope(trigger: WorkflowTrigger, shortcut: KeyboardShortcutDefinition?) -> Bool {
        trigger != .manual || shortcut != nil
    }
}
