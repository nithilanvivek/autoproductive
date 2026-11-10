import AppKit
@preconcurrency import Intents
@preconcurrency import IntentsUI

@MainActor
final class SiriShortcutPresenter: NSObject, ObservableObject {
    private enum SheetOutcome {
        case updated
        case deleted
        case cancelled
    }

    static let openAppActivityType = "land.nithi.autoproductive.open-app"
    static let composeMailActivityType = "land.nithi.autoproductive.compose-mail"
    static let sequenceActivityType = "land.nithi.autoproductive.run-sequence"
    static let supportedActivityTypes = [openAppActivityType, composeMailActivityType, sequenceActivityType]

    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("SiriShortcutPresenter", errorMessage)
            }
        }
    }
    private var completion: ((SheetOutcome) -> Void)?

    func presentAddSheet(for automation: SavedAutomation, completion: (() -> Void)? = nil) {
        errorMessage = nil
        self.completion = { _ in completion?() }

        let activity = NSUserActivity(activityType: Self.activityType(for: automation.kind))
        activity.title = automation.name
        activity.userInfo = ["automationID": automation.id.uuidString]
        activity.requiredUserInfoKeys = ["automationID"]
        activity.suggestedInvocationPhrase = automation.name
        activity.isEligibleForSearch = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(automation.id.uuidString)

        let shortcut = INShortcut(userActivity: activity)

        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { [weak self] voiceShortcuts, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.completion = nil
                    return
                }

                if let existing = voiceShortcuts?.first(where: {
                    $0.shortcut.userActivity?.userInfo?["automationID"] as? String
                        == automation.id.uuidString
                }) {
                    let controller = INUIEditVoiceShortcutViewController(voiceShortcut: existing)
                    controller.delegate = self
                    self.present(controller)
                } else {
                    let controller = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                    controller.delegate = self
                    self.present(controller)
                }
            }
        }
    }

    func removeShortcutBeforeDeleting(
        for automation: SavedAutomation,
        completion: @escaping (Bool) -> Void
    ) {
        errorMessage = nil

        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { [weak self] voiceShortcuts, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }

                guard let existing = voiceShortcuts?.first(where: {
                    $0.shortcut.userActivity?.userInfo?["automationID"] as? String
                        == automation.id.uuidString
                }) else {
                    completion(true)
                    return
                }

                self.completion = { outcome in
                    completion(outcome == .deleted)
                }
                let controller = INUIEditVoiceShortcutViewController(voiceShortcut: existing)
                controller.delegate = self
                self.present(controller)
            }
        }
    }

    private static func activityType(for kind: AutomationKind) -> String {
        switch kind {
        case .openApp: openAppActivityType
        case .composeMail: composeMailActivityType
        default: sequenceActivityType
        }
    }

    private func present(_ controller: NSViewController) {
        let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.contentViewController != nil })

        guard let presenter = window?.contentViewController else {
            errorMessage = "AutoProductive could not present the Add to Siri sheet."
            return
        }
        presenter.presentAsSheet(controller)
    }

    private func finish(
        _ controller: NSViewController,
        outcome: SheetOutcome,
        error: Error? = nil
    ) {
        controller.dismiss(nil)
        errorMessage = error?.localizedDescription
        let completion = completion
        self.completion = nil
        completion?(outcome)
    }
}

extension SiriShortcutPresenter: INUIEditVoiceShortcutViewControllerDelegate {
    nonisolated func editVoiceShortcutViewController(
        _ controller: INUIEditVoiceShortcutViewController,
        didUpdate voiceShortcut: INVoiceShortcut?,
        error: Error?
    ) {
        Task { @MainActor in
            finish(controller, outcome: .updated, error: error)
        }
    }

    nonisolated func editVoiceShortcutViewController(
        _ controller: INUIEditVoiceShortcutViewController,
        didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID
    ) {
        Task { @MainActor in
            finish(controller, outcome: .deleted)
        }
    }

    nonisolated func editVoiceShortcutViewControllerDidCancel(
        _ controller: INUIEditVoiceShortcutViewController
    ) {
        Task { @MainActor in
            finish(controller, outcome: .cancelled)
        }
    }
}

extension SiriShortcutPresenter: INUIAddVoiceShortcutViewControllerDelegate {
    nonisolated func addVoiceShortcutViewController(
        _ controller: INUIAddVoiceShortcutViewController,
        didFinishWith voiceShortcut: INVoiceShortcut?,
        error: Error?
    ) {
        Task { @MainActor in
            finish(controller, outcome: .updated, error: error)
        }
    }

    nonisolated func addVoiceShortcutViewControllerDidCancel(
        _ controller: INUIAddVoiceShortcutViewController
    ) {
        Task { @MainActor in
            finish(controller, outcome: .cancelled)
        }
    }
}
