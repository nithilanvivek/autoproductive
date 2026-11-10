import SwiftUI

struct AutoProductiveApp: App {
    private let instanceGuard = AppInstanceGuard()
    @NSApplicationDelegateAdaptor(AutoProductiveAppDelegate.self) private var appDelegate
    @StateObject private var store = AutomationStore.shared
    @StateObject private var runtime = AutomationRuntime.shared
    @StateObject private var backgroundAgent = BackgroundAgentManager()
    @StateObject private var navigation = AppNavigation()
    @StateObject private var keepAwake = KeepAwakeManager.shared
    @StateObject private var siriPresenter = SiriShortcutPresenter()
    @StateObject private var fileBucket = FileBucket.shared
    @StateObject private var dockPreview = DockPreviewManager.shared

    var body: some Scene {
        Window("AutoProductive", id: "main") {
            RootView()
                .tint(AppPalette.textAccent)
                .environmentObject(store)
                .environmentObject(backgroundAgent)
                .environmentObject(siriPresenter)
                .environmentObject(runtime)
                .environmentObject(navigation)
                .environmentObject(keepAwake)
                .environmentObject(fileBucket)
                .environmentObject(dockPreview)
                .frame(minWidth: 480, minHeight: 360)
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.title == "AutoProductive" }) {
                            AutoProductiveAppDelegate.restoreCompactFrameIfNeeded(window)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.enforcePermissions()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 680)
        Window("Keep Awake", id: "keep-awake") {
            KeepAwakeSettingsView()
                .tint(AppPalette.textAccent)
                .environmentObject(keepAwake)
        }
        .windowStyle(.hiddenTitleBar)
        Window("Audio Mixer", id: "audio-mixer") {
            AudioMixerView().tint(AppPalette.textAccent)
        }
        .defaultSize(width: 670, height: 500)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("File Bucket") { fileBucket.showWindow() }
                    .disabled(!fileBucket.isAvailable)
            }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) {
                Button("Report a Problem…") { ProblemReportCoordinator.shared.show() }
            }
            CommandGroup(replacing: .appTermination) {
                Button("Hide to Menu Bar") {
                    MenuBarController.shared.close()
                    PermissionExplanationPresenter.shared.cancelPendingRequest()
                    for window in NSApp.windows {
                        window.orderOut(nil)
                    }
                    NSApp.setActivationPolicy(.accessory)
                }
                .keyboardShortcut("q")
            }
            CommandMenu("Automation") {
                Button("Stop All Running Actions") { runtime.stopAllActions() }
                    .keyboardShortcut(".", modifiers: [.command, .option])
            }
        }
    }
}
