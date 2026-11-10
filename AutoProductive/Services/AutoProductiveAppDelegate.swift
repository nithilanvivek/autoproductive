import AppKit
import UserNotifications

@MainActor
final class AutoProductiveAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var reopenObserver: NSObjectProtocol?
    static var isMenuBarAgentLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--menu-bar-agent")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        ProblemReportCoordinator.shared.startSession()
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppInstanceGuard.showMainWindow, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.showMainWindow() }
        }
        if Self.isMenuBarAgentLaunch {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                             withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Self.showMainWindow()
        return true
    }

    private static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "AutoProductive" || $0.title == "My Automations" }) {
            Self.restoreCompactFrameIfNeeded(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    static func restoreCompactFrameIfNeeded(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame
        guard window.frame.width > min(1_400, available.width * 0.85) ||
              window.frame.height > min(1_000, available.height * 0.85) else { return }
        let size = NSSize(width: min(1_080, available.width), height: min(740, available.height))
        window.setContentSize(size)
        window.center()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.prepareForRestart()
    }

    static func prepareForRestart() {
        ScreenRegionPicker.shared.cancel()
        KeepAwakeManager.shared.stop()
        AppAudioMixer.shared.stop()
        ProblemReportCoordinator.shared.markCleanExit()
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard SiriShortcutPresenter.supportedActivityTypes.contains(userActivity.activityType) else { return false }
        guard let idString = userActivity.userInfo?["automationID"] as? String,
              let id = UUID(uuidString: idString),
              let automation = AutomationStore.loadStoredAutomations().first(where: { $0.id == id }) else {
            DiagnosticJournal.shared.recordErrorMessage("Siri invocation", "Shortcut activity did not identify an existing automation")
            return false
        }

        do {
            try AutomationRunner.run(automation)
            return true
        } catch {
            DiagnosticJournal.shared.recordError("Siri invocation", error)
            return false
        }
    }
}
