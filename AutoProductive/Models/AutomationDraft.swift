import Foundation

/// An unfinished editor is stored separately from runnable automations.
struct AutomationDraft: Codable, Equatable {
    enum Editor: String, Codable { case sequence, wizard, workflow }
    var editor: Editor
    var kind: AutomationKind
    var originalID: UUID?
    var name: String
    var flow: WorkflowDefinition
    var shortcut: KeyboardShortcutDefinition?
    var page: String?
    var limitToApps: Bool = false
    var appPath: String? = nil
    var recipient: String = ""
    var subject: String = ""
    var message: String = ""
    var appScopes: [String] = []
    var enableTrigger: Bool = true
}

enum AutomationDraftStorage {
    static let key = "automationEditorDraft.v1"
    static func load(defaults: UserDefaults = .standard) -> AutomationDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AutomationDraft.self, from: data)
    }
    static func save(_ draft: AutomationDraft, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key)
    }
    static func clear(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}
