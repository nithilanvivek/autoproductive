import AppKit
import Combine
import ApplicationServices
import OSLog
import IOKit.hidsystem

@MainActor
final class AutomationRuntime: ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var inputMonitoringEnabled = false
    private let defaults: UserDefaults
    private var allValues: [SavedAutomation] = []
    private var isActive = true
    private var isRecording = false
    private let hotKeys = HotKeyManager()
    private let input = InputAutomationMonitor()
    private var timer: Timer?
    private var screenCheck: Task<Void, Never>?
    private var nextRuns: [UUID: Date] = [:]
    private var nextScreenChecks: [ScreenTriggerKey: Date] = [:]
    private var screenState = ScreenTriggerMatchState()
    private var checkID = UUID()
    private var values: [SavedAutomation] = []
    private var recordingObserver: NSObjectProtocol?
    private var pauseObserver: NSObjectProtocol?
    private var distributedObserver: NSObjectProtocol?
    private var stopObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var lastInputError: String?
    private var lastScreenError: String?
    private let screenLogger = Logger(subsystem: "land.nithi.autoproductive", category: "ScreenTriggers")
    @Published private(set) var finderCutEnabled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPaused = defaults.bool(forKey: "automationPaused.v1")
        inputMonitoringEnabled = InputMonitoringSettings.isAvailable(permissionGranted: CGPreflightListenEventAccess(), in: defaults)
        finderCutEnabled = defaults.bool(forKey: "finderCutEnabled.v1")
        recordingObserver = NotificationCenter.default.addObserver(forName: .automationRecordingChanged, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.isRecording = notification.object as? Bool ?? false
                self?.input.isRecording = notification.object as? Bool ?? false
            }
        }
        pauseObserver = NotificationCenter.default.addObserver(forName: .automationPauseRequested, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        stopObserver = DistributedNotificationCenter.default().addObserver(forName: .automationStopRequested, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.input.stopExpansion()
                WorkflowEngine.shared.stopAll()
            }
        }
        distributedObserver = DistributedNotificationCenter.default().addObserver(forName: .automationRecordingChanged, object: nil, queue: .main) { note in
            NotificationCenter.default.post(name: .automationRecordingChanged, object: note.object as? String == "started")
        }
        appActivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let permitted = CGPreflightListenEventAccess()
                let shouldListen = InputMonitoringSettings.isAvailable(permissionGranted: permitted, in: self.defaults)
                if shouldListen != self.inputMonitoringEnabled || (self.input.needsPermissionRetry && AXIsProcessTrusted() && permitted) {
                    self.sync(self.allValues, active: self.isActive)
                    NotificationCenter.default.post(name: .inputMonitoringChanged, object: nil)
                }
            }
        }
    }

    func sync(_ automations: [SavedAutomation], active: Bool = true) {
        allValues = automations; isActive = active
        isPaused = defaults.bool(forKey: "automationPaused.v1")
        inputMonitoringEnabled = InputMonitoringSettings.isAvailable(permissionGranted: CGPreflightListenEventAccess(), in: defaults)
        if isPaused { WorkflowEngine.shared.stopAll() }
        timer?.invalidate(); screenCheck?.cancel(); screenCheck = nil; checkID = UUID()
        nextRuns.removeAll(); nextScreenChecks.removeAll(); screenState.reset()
        // A screen warning belongs to the previous set of enabled checks.
        // Disabling or editing its automation must not leave it on screen;
        // an enabled condition that is still invalid reports again on its next check.
        if let lastScreenError, WorkflowEngine.shared.lastError == lastScreenError {
            WorkflowEngine.shared.lastError = nil
        }
        lastScreenError = nil
        values = active && !isPaused ? automations.filter(\.isEnabled) : []
        let inputValues = inputMonitoringEnabled ? values : []
        hotKeys.sync(with: inputValues, includeEmergency: active)
        do {
            try input.sync(inputValues, finderCutEnabled: finderCutEnabled && active && inputMonitoringEnabled && !isPaused)
            if WorkflowEngine.shared.lastError == lastInputError { WorkflowEngine.shared.lastError = nil }
            lastInputError = nil
        } catch {
            DiagnosticJournal.shared.recordError("Input monitoring", error)
            lastInputError = error.localizedDescription
            WorkflowEngine.shared.lastError = lastInputError
        }
        timer = Timer.scheduledTimer(withTimeInterval: WorkflowTiming.minimum, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func setFinderCutEnabled(_ enabled: Bool) {
        finderCutEnabled = enabled
        defaults.set(enabled, forKey: "finderCutEnabled.v1")
        sync(allValues, active: isActive)
    }

    func setInputMonitoringEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: InputMonitoringSettings.enabledKey)
        inputMonitoringEnabled = enabled && CGPreflightListenEventAccess()
        if enabled && !inputMonitoringEnabled {
            PermissionExplanationPresenter.shared.present(
                title: "Enable Input Monitoring",
                message: "Input Monitoring lets AutoProductive recognize the keyboard and mouse input used by your automations. Continue to allow access in System Settings."
            ) { accepted in
                guard accepted else { return }
                _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                _ = CGRequestListenEventAccess()
                if !CGPreflightListenEventAccess() { PermissionSettings.open("Input Monitoring") }
            }
        }
        if !enabled { input.stopExpansion() }
        if inputMonitoringEnabled && isPaused { resume(); return }
        sync(allValues, active: isActive)
        NotificationCenter.default.post(name: .inputMonitoringChanged, object: nil)
    }

    private func tick() {
        let captureActive = AutomationCaptureCoordination.isRecording
        if captureActive != isRecording {
            isRecording = captureActive; input.isRecording = captureActive
            hotKeys.setRecording(captureActive)
        }
        if defaults.bool(forKey: "automationPaused.v1") != isPaused
            || InputMonitoringSettings.isAvailable(permissionGranted: CGPreflightListenEventAccess(), in: defaults) != inputMonitoringEnabled {
            sync(allValues, active: isActive); return
        }
        guard !isRecording, !isPaused else { return }
        var checks: [(SavedAutomation, ScreenTriggerCheck)] = []
        for automation in values {
            guard let flow = automation.workflow else { continue }
            let now = Date()
            guard AppScope.allows(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, selected: flow.scopedAppBundleIdentifiers) else { continue }
            if flow.uses(.interval), nextRuns[automation.id].map({ $0 <= now }) ?? true {
                nextRuns[automation.id] = now.addingTimeInterval(WorkflowTiming.clamped(flow.interval))
                WorkflowEngine.shared.start(automation)
            }
            if screenCheck == nil {
                for check in flow.screenChecks {
                    let key = ScreenTriggerKey(automationID: automation.id, trigger: check.trigger)
                    if nextScreenChecks[key].map({ $0 <= now }) ?? true {
                        nextScreenChecks[key] = now.addingTimeInterval(WorkflowTiming.clamped(check.interval))
                        checks.append((automation, check))
                    }
                }
            }
        }
        guard screenCheck == nil else { return }
        guard !checks.isEmpty else { return }
        let currentID = UUID(); checkID = currentID
        screenCheck = Task {
            defer { if checkID == currentID { screenCheck = nil } }
            for (automation, check) in checks {
                guard !Task.isCancelled, let step = check.condition else { continue }
                let key = ScreenTriggerKey(automationID: automation.id, trigger: check.trigger)
                do {
                    let started = Date()
                    let matched = try await DesktopAutomationService.screenMatches(step)
                    guard !Task.isCancelled, checkID == currentID else { return }
                    if WorkflowEngine.shared.lastError == lastScreenError { WorkflowEngine.shared.lastError = nil }
                    lastScreenError = nil
                    let transition = screenState.record(matched, for: key)
                    screenLogger.debug("Screen check matched=\(matched) elapsed=\(Date().timeIntervalSince(started))s")
                    if transition.changed {
                        screenLogger.info("Screen condition matched=\(matched) elapsed=\(Date().timeIntervalSince(started))s")
                        DiagnosticJournal.shared.record("Screen", "Matched=\(matched); elapsed=\(Date().timeIntervalSince(started))s")
                    }
                    if transition.shouldRun { WorkflowEngine.shared.start(automation) }
                } catch is CancellationError {
                    return
                } catch {
                    if (error as? ScreenObservationError)?.showsWarning != false {
                        lastScreenError = "\(automation.name): \(error.localizedDescription)"
                        WorkflowEngine.shared.lastError = lastScreenError
                    }
                    let native = error as NSError
                    screenLogger.error("Screen check failed: \(native.domain, privacy: .public) code=\(native.code)")
                    DiagnosticJournal.shared.recordError("Screen", error, context: "trigger=\(check.trigger.rawValue)")
                    // Invalid settings require editing, but a temporary capture
                    // failure (for example during a Space switch) must recover.
                    nextScreenChecks[key] = WorkflowTiming.nextScreenCheck(after: error, now: .now, interval: check.interval)
                }
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        screenCheck?.cancel(); screenCheck = nil
        hotKeys.sync(with: [], includeEmergency: false); input.stop()
        WorkflowEngine.shared.stopAll()
    }

    func stopAllActions() {
        input.stopExpansion()
        WorkflowEngine.shared.stopAll()
        DistributedNotificationCenter.default().postNotificationName(.automationStopRequested, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func pause() {
        defaults.set(true, forKey: "automationPaused.v1")
        isPaused = true
        stop()
        NotificationCenter.default.post(name: .inputMonitoringChanged, object: nil)
    }

    func resume() {
        defaults.set(false, forKey: "automationPaused.v1")
        sync(allValues, active: isActive)
        NotificationCenter.default.post(name: .inputMonitoringChanged, object: nil)
    }
}

enum AutomationCaptureCoordination {
    private static var defaults: UserDefaults { UserDefaults(suiteName: Bundle.main.bundleIdentifier ?? "land.nithi.autoproductive") ?? .standard }
    static var isRecording: Bool { defaults.double(forKey: "inputCaptureUntil.v1") > Date().timeIntervalSince1970 }
    static func setRecording(_ active: Bool) {
        defaults.set(active ? Date().timeIntervalSince1970 + 300 : 0, forKey: "inputCaptureUntil.v1")
        NotificationCenter.default.post(name: .automationRecordingChanged, object: active)
        DistributedNotificationCenter.default().postNotificationName(.automationRecordingChanged, object: active ? "started" : "stopped", userInfo: nil, deliverImmediately: true)
    }
}

extension Notification.Name {
    static let automationRecordingChanged = Notification.Name("AutoProductiveRecordingChanged")
    static let automationStopRequested = Notification.Name("AutoProductiveStopRequested")
    static let automationPauseRequested = Notification.Name("AutoProductivePauseRequested")
    static let inputMonitoringChanged = Notification.Name("AutoProductiveInputMonitoringChanged")
}
