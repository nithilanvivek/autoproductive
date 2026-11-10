import Foundation

/// Runs the same app as a per-user LaunchAgent at login, so its menu bar panel
/// and shortcut listener share one process. A system LaunchDaemon has no GUI session.
@MainActor
final class BackgroundAgentManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("BackgroundAgentManager", errorMessage)
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let preferenceKey = "menuBarAgentEnabled.v1"
    private let loginChoiceKey = "menuBarLoginChoiceMade.v1"
    private let label = (Bundle.main.bundleIdentifier ?? "land.nithi.autoproductive") + ".menu-bar-agent"
    private let legacyLabel = (Bundle.main.bundleIdentifier ?? "land.nithi.autoproductive") + ".agent"

    init() {
        if defaults.bool(forKey: loginChoiceKey) && defaults.bool(forKey: preferenceKey) {
            setEnabled(true)
        } else {
            // Earlier builds installed the agent before asking. Remove that
            // registration until the person accepts the first-launch request.
            if !defaults.bool(forKey: loginChoiceKey) { try? stopAndRemove() }
            isEnabled = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try install()
            } else {
                try stopAndRemove()
            }
            defaults.set(enabled, forKey: preferenceKey)
            if enabled { defaults.set(true, forKey: loginChoiceKey) }
            isEnabled = enabled
        } catch {
            DiagnosticJournal.shared.recordError("BackgroundAgentManager", error); errorMessage = error.localizedDescription
            isEnabled = FileManager.default.fileExists(atPath: Self.agentPlistURL.path)
        }
    }

    private func install() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw AgentError.executableMissing
        }
        try FileManager.default.createDirectory(
            at: Self.agentPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path, "--menu-bar-agent"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 2
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: Self.agentPlistURL, options: .atomic)
        removeLegacyAgent()
        // The current app already owns the menu bar and shortcut listener.
        // launchd loads this job at the next login, avoiding a second live icon.
    }

    private func stopAndRemove() throws {
        if FileManager.default.fileExists(atPath: Self.agentPlistURL.path) {
            try FileManager.default.removeItem(at: Self.agentPlistURL)
        }
        _ = runLaunchctl(["bootout", "\(launchDomain)/\(label)"])
        removeLegacyAgent()
    }

    private func removeLegacyAgent() {
        _ = runLaunchctl(["bootout", "\(launchDomain)/\(legacyLabel)"])
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist")
        try? FileManager.default.removeItem(at: legacyURL)
    }

    private var launchDomain: String { "gui/\(getuid())" }

    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                DiagnosticJournal.shared.recordErrorMessage("Background agent", "launchctl failed; status=\(process.terminationStatus)")
            }
            return process.terminationStatus
        } catch {
            DiagnosticJournal.shared.recordError("Background agent", error)
            return -1
        }
    }

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Bundle.main.bundleIdentifier ?? "land.nithi.autoproductive").menu-bar-agent.plist")
    }
}

private enum AgentError: LocalizedError {
    case executableMissing
    var errorDescription: String? { "AutoProductive could not locate its app executable." }
}
