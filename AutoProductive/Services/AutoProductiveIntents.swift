import AppIntents
import Foundation

struct AutomationEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "AutoProductive Automation")
    static var defaultQuery = AutomationEntityQuery()

    let id: UUID
    let name: String
    let kind: AutomationKind

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "Run with AutoProductive",
            image: .init(systemName: kind.symbol)
        )
    }
}

struct AutomationEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AutomationEntity] {
        availableAutomations()
            .filter { identifiers.contains($0.id) }
            .map(AutomationEntity.init)
    }

    func suggestedEntities() async throws -> [AutomationEntity] {
        availableAutomations().map(AutomationEntity.init)
    }

    private func availableAutomations() -> [SavedAutomation] {
        AutomationStore.loadStoredAutomations()
    }
}

private extension AutomationEntity {
    init(_ automation: SavedAutomation) {
        id = automation.id
        name = automation.name
        kind = automation.kind
    }
}

struct RunAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "Run an Automation"
    static var description = IntentDescription("Runs a saved AutoProductive automation.")
    static var openAppWhenRun = false

    @Parameter(title: "Automation")
    var automation: AutomationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$automation)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let savedAutomation = AutomationStore.loadStoredAutomations()
            .first(where: { $0.id == automation.id }) else {
            throw AutomationRunError.missingAutomation
        }

        try await MainActor.run {
            try AutomationRunner.run(savedAutomation)
        }

        return .result(dialog: "Running \(automation.name)")
    }
}

struct AutoProductiveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunAutomationIntent(),
            phrases: [
                "Run \(\.$automation) with \(.applicationName)",
                "Start \(\.$automation) with \(.applicationName)"
            ],
            shortTitle: "Run an Automation",
            systemImageName: "wand.and.stars"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .blue }
}
