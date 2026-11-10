import AppKit
import Foundation

enum AutomationRunError: LocalizedError {
    case missingAutomation
    case missingApplication
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .missingAutomation:
            "That saved automation could not be found."
        case .missingApplication:
            "Choose an application before running this automation."
        case .invalidEmail:
            "The email draft could not be created."
        }
    }
}

@MainActor
enum AutomationRunner {
    static func run(_ automation: SavedAutomation) throws {
        guard automation.isEnabled else { throw WorkflowError.invalid("Enable this automation before running it.") }
        if let workflow = automation.workflow {
            try workflow.validate()
            WorkflowEngine.shared.start(automation)
            return
        }
        switch automation.kind {
        case .openApp:
            guard let path = automation.appPath, !path.isEmpty else {
                throw AutomationRunError.missingApplication
            }
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )

        case .composeMail:
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = automation.recipient

            var queryItems: [URLQueryItem] = []
            if !automation.subject.isEmpty {
                queryItems.append(URLQueryItem(name: "subject", value: automation.subject))
            }
            if !automation.message.isEmpty {
                queryItems.append(URLQueryItem(name: "body", value: automation.message))
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems

            guard let url = components.url, NSWorkspace.shared.open(url) else {
                throw AutomationRunError.invalidEmail
            }
        default:
            guard let workflow = automation.workflow else { throw WorkflowError.invalid("This automation has no saved actions.") }
            try workflow.validate()
            WorkflowEngine.shared.start(automation)
        }
    }
}
