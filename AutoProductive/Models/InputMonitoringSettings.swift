import Foundation

enum InputMonitoringSettings {
    static let enabledKey = "inputMonitoringEnabled.v1"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func allowsInput(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && !defaults.bool(forKey: "automationPaused.v1")
    }

    static func isAvailable(permissionGranted: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && permissionGranted
    }
}
