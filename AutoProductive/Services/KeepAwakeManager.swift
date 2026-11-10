import Combine
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    @Published private(set) var isActive = false
    @Published private(set) var activeUntil: Date?
    @Published private(set) var allowDisplaySleep: Bool
    @Published private(set) var muteAudioWhileRunning: Bool
    @Published private(set) var movePointerSlightly: Bool
    @Published private(set) var isClosedLidEnabled = false
    @Published private(set) var isAuthorizingClosedLid = false
    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("KeepAwakeManager", errorMessage)
            }
        }
    }

    private let defaults: UserDefaults
    private let displaySleepKey = "keepAwakeAllowDisplaySleep.v1"
    private let muteAudioKey = "keepAwakeMuteAudio.v1"
    private let audioMute = KeepAwakeAudioMute()
    private var audioMuteTimer: Timer?
    private var audioMuteFailures = KeepAwakeAudioMute.FailureTracker()
    private let pointerMoveKey = "keepAwakeMovePointerSlightly.v1"
    private let closedLidExplanationKey = "keepAwakeClosedLidExplanation.v1"
    private let closedLidPermissionKey = "keepAwakeClosedLidPermission.v1"
    private let closedLidActiveKey = "keepAwakeClosedLidActive.v1"
    private var closedLidRequest = UUID()
    private var closedLidStartedSession = false
    #if !MODULAR_FEATURES
    private var assertionID: IOPMAssertionID?
    private var displayAssertionID: IOPMAssertionID?
    #endif
    private var assertionComponent: FeatureKeepAwakeAssertions?
    private var expiryTimer: Timer?
    private var pointerTimer: Timer?
    private var pendingPointerReturn: DispatchWorkItem?

    // Lid sleep and display idle are independent. A closed-lid session must
    // not drop display/screensaver protection while the lid is still open.
    private var displayMaySleep: Bool { allowDisplaySleep }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        muteAudioWhileRunning = defaults.bool(forKey: muteAudioKey)
        allowDisplaySleep = defaults.bool(forKey: displaySleepKey)
        movePointerSlightly = defaults.object(forKey: pointerMoveKey) as? Bool ?? true
        if defaults.bool(forKey: closedLidActiveKey) {
            // The exit watchdog normally restores sleep after a crash. Recover
            // again on launch if its write did not complete.
            if (try? ClosedLidPowerControl.isSleepDisabled()) == true {
                do { try ClosedLidPowerControl.disableWithoutPrompt() }
                catch {
                    DiagnosticJournal.shared.recordError("KeepAwakeManager", error); isClosedLidEnabled = true
                    errorMessage = "Closed-lid recovery needs attention: \(error.localizedDescription)"
                }
            }
            if !isClosedLidEnabled { defaults.set(false, forKey: closedLidActiveKey) }
        }
    }

    var status: String {
        if isClosedLidEnabled && !isActive { return "Closed-lid mode is still on — turn it off" }
        guard isActive else { return "Keep Awake is off" }
        if let activeUntil {
            return "Keeping awake until \(activeUntil.formatted(date: .omitted, time: .shortened))"
        }
        return "Keeping awake until turned off"
    }

    func start(for duration: TimeInterval? = nil) {
        if let duration, duration <= 0 {
            errorMessage = "Choose a future end time or a duration greater than zero."
            return
        }
        releaseAssertion()
        do {
            if let bytes = try FeatureComponentDispatcher.toolBytes(id: "tool.keepAwake") {
                let component = try FeatureKeepAwakeAssertions(verifiedBytes: bytes)
                let result = component.start(displayMaySleep: displayMaySleep)
                guard result.succeeded else {
                    syncAudioMute()
                    errorMessage = result.displayError != 0
                        ? "macOS could not keep the display awake (code \(result.displayError))."
                        : "macOS could not start Keep Awake (code \(result.systemError))."
                    return
                }
                assertionComponent = component
            } else {
                #if MODULAR_FEATURES
                syncAudioMute()
                errorMessage = "Install Keep Awake to use it."
                return
                #else
                if !startLegacyAssertions() { return }
                #endif
            }
        } catch FeatureComponentDispatcher.DispatchError.missingComponent {
            syncAudioMute()
            errorMessage = "Install Keep Awake to use it."
            return
        } catch {
            syncAudioMute()
            errorMessage = "Could not load Keep Awake: \(error.localizedDescription)"
            return
        }
        isActive = true
        errorMessage = nil
        syncPointerTimer()
        syncAudioMute()
        if let duration {
            let until = Date().addingTimeInterval(duration)
            activeUntil = until
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
            expiryTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    #if !MODULAR_FEATURES
    private func startLegacyAssertions() -> Bool {
        var identifier = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AutoProductive Keep Awake" as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else {
            syncAudioMute()
            errorMessage = "macOS could not start Keep Awake (code \(result))."
            return false
        }
        assertionID = identifier
        if !displayMaySleep {
            var displayIdentifier = IOPMAssertionID(0)
            let displayResult = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "AutoProductive Keep Display Awake" as CFString, &displayIdentifier)
            guard displayResult == kIOReturnSuccess else {
                releaseAssertion()
                syncAudioMute()
                errorMessage = "macOS could not keep the display awake (code \(displayResult))."
                return false
            }
            displayAssertionID = displayIdentifier
        }
        return true
    }
    #endif

    func start(until endDate: Date) {
        start(for: endDate.timeIntervalSinceNow)
    }

    func setAllowDisplaySleep(_ allowed: Bool) {
        guard allowDisplaySleep != allowed else { return }
        allowDisplaySleep = allowed
        defaults.set(allowed, forKey: displaySleepKey)
        refreshAssertionMode()
    }

    func setMuteAudioWhileRunning(_ enabled: Bool) {
        muteAudioWhileRunning = enabled
        defaults.set(enabled, forKey: muteAudioKey)
        syncAudioMute()
    }

    private func syncAudioMute() {
        audioMuteTimer?.invalidate()
        audioMuteTimer = nil
        audioMuteFailures = .init()
        guard isActive, muteAudioWhileRunning else {
            retryAudioRestore()
            if audioMute.hasPendingRestorations {
                // A disconnected output can return with a new device ID. Keep
                // its original state until it becomes reachable again.
                let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.retryAudioRestore() }
                }
                timer.tolerance = 1
                audioMuteTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            return
        }
        applyAudioMute()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyAudioMute()
            }
        }
        timer.tolerance = 0.2
        audioMuteTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func retryAudioRestore() {
        if audioMute.restore() { clearAudioMuteError() }
        else { errorMessage = "Could not restore an audio output’s previous mute state. Check its sound settings." }
        if !audioMute.hasPendingRestorations {
            audioMuteTimer?.invalidate()
            audioMuteTimer = nil
        }
    }

    private func applyAudioMute() {
        let result = audioMute.apply()
        let shouldWarn = audioMuteFailures.shouldWarn(for: result)
        switch result {
        case .muted, .unavailable:
            // No default output during a route change is temporary; retry on
            // the next tick instead of presenting a persistent error.
            clearAudioMuteError()
        case .failed:
            // A route can briefly expose a device before its mute control is
            // ready. Report persistent failures, not a single transition tick.
            if shouldWarn { errorMessage = "Could not mute the current audio output." }
        }
    }

    private func clearAudioMuteError() {
        let audioErrors = [
            "Could not restore an audio output’s previous mute state. Check its sound settings.",
            "This audio output does not support system mute. Choose another output to mute it during Keep Awake.",
            "Could not mute the current audio output."
        ]
        if let errorMessage, audioErrors.contains(errorMessage) { self.errorMessage = nil }
    }

    func setMovePointerSlightly(_ enabled: Bool) {
        guard movePointerSlightly != enabled else { return }
        movePointerSlightly = enabled
        defaults.set(enabled, forKey: pointerMoveKey)
        syncPointerTimer()
    }

    func setClosedLidEnabled(_ enabled: Bool) {
        guard enabled else { applyClosedLidEnabled(false); return }
        guard !isClosedLidEnabled, !isAuthorizingClosedLid else { return }
        if defaults.bool(forKey: closedLidPermissionKey) || defaults.bool(forKey: closedLidExplanationKey) {
            applyClosedLidEnabled(true)
            return
        }
        PermissionExplanationPresenter.shared.present(
            title: "Keep working with the lid closed",
            message: "macOS normally sleeps when you close the lid. AutoProductive needs administrator approval to change this system-wide sleep setting. Continue may open macOS’s password prompt to install permission limited to turning this setting on and off; your password is handled by macOS. The app restores normal sleep when Keep Awake ends or the app quits. You can remove this permission in Keep Awake settings. Keep your Mac ventilated while using closed-lid mode."
        ) { [weak self] accepted in
            guard accepted, let self else { return }
            self.defaults.set(true, forKey: self.closedLidExplanationKey)
            self.applyClosedLidEnabled(true)
        }
    }

    private func applyClosedLidEnabled(_ enabled: Bool) {
        if !enabled {
            let cancelStartedSession = isAuthorizingClosedLid && closedLidStartedSession
            closedLidRequest = UUID()
            // Keep the in-flight operation occupied until its reply has
            // restored the setting. A new enable must not race that restore.
            disableClosedLid()
            if cancelStartedSession { stop() }
            return
        }
        guard !isClosedLidEnabled, !isAuthorizingClosedLid else { return }
        let startedSession = !isActive
        if startedSession { start() }
        guard isActive else { return }

        let request = UUID()
        closedLidRequest = request
        closedLidStartedSession = startedSession
        isAuthorizingClosedLid = true
        let savedPermission = defaults.bool(forKey: closedLidPermissionKey)
        // Record ownership before the privileged write is submitted, so a
        // crash during that write can be repaired at next launch.
        let sessionDefaults = defaults
        let activeKey = closedLidActiveKey
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var mightOwnSetting = false
            let result = Result<Void, Error> {
                if try ClosedLidPowerControl.isSleepDisabled() {
                    throw ClosedLidPowerControl.Failure("Sleep is already disabled by another app or setting. Turn that off before enabling AutoProductive's closed-lid mode.")
                }
                sessionDefaults.set(true, forKey: activeKey)
                if savedPermission {
                    do {
                        mightOwnSetting = true
                        try ClosedLidPowerControl.enableWithoutPrompt()
                    } catch {
                        DiagnosticJournal.shared.recordError("KeepAwakeManager", error); if (try? ClosedLidPowerControl.isSleepDisabled()) != true {
                            mightOwnSetting = false
                            try ClosedLidPowerControl.installPermission()
                            mightOwnSetting = true
                            try ClosedLidPowerControl.enableWithoutPrompt()
                        }
                    }
                } else {
                    try ClosedLidPowerControl.installPermission()
                    mightOwnSetting = true
                    try ClosedLidPowerControl.enableWithoutPrompt()
                }
                try ClosedLidPowerControl.startExitWatchdog()
            }
            var restoredAfterFailure = true
            if case .failure = result, mightOwnSetting {
                restoredAfterFailure = (try? ClosedLidPowerControl.disableWithoutPrompt()) != nil
                if restoredAfterFailure { try? ClosedLidPowerControl.stopExitWatchdog() }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.closedLidRequest == request else {
                    self.isAuthorizingClosedLid = false
                    self.closedLidStartedSession = false
                    if case .success = result {
                        do {
                            try ClosedLidPowerControl.disableWithoutPrompt()
                            try ClosedLidPowerControl.stopExitWatchdog()
                            self.defaults.set(false, forKey: self.closedLidActiveKey)
                        } catch {
                            self.isClosedLidEnabled = true
                            self.errorMessage = "Could not restore sleep after canceling closed-lid mode: \(error.localizedDescription)"
                        }
                    } else if restoredAfterFailure {
                        self.defaults.set(false, forKey: self.closedLidActiveKey)
                    } else {
                        self.isClosedLidEnabled = true
                        self.errorMessage = "Closed-lid mode could not be canceled. Turn it off to restore normal sleep."
                    }
                    return
                }
                self.isAuthorizingClosedLid = false
                self.closedLidStartedSession = false
                switch result {
                case .success:
                    self.isClosedLidEnabled = true
                    self.refreshAssertionMode()
                    self.defaults.set(true, forKey: self.closedLidPermissionKey)
                    self.defaults.set(true, forKey: self.closedLidActiveKey)
                    self.errorMessage = nil
                    DiagnosticJournal.shared.record("KeepAwake", "Closed-lid mode enabled; SleepDisabled verified on")
                case .failure(let error):
                    if restoredAfterFailure { self.defaults.set(false, forKey: self.closedLidActiveKey) }
                    else { self.isClosedLidEnabled = true }
                    self.errorMessage = "Closed-lid mode: \(error.localizedDescription)"
                    if startedSession { self.stop() }
                }
            }
        }
    }

    func removeClosedLidPermission() {
        guard !isClosedLidEnabled, !isAuthorizingClosedLid else { return }
        isAuthorizingClosedLid = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ClosedLidPowerControl.removePermission() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthorizingClosedLid = false
                switch result {
                case .success:
                    self.defaults.set(false, forKey: self.closedLidPermissionKey)
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = "Could not remove closed-lid permission: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        closedLidRequest = UUID()
        releaseAssertion()
        syncAudioMute()
        disableClosedLid()
    }

    private func disableClosedLid() {
        guard isClosedLidEnabled else { return }
        do {
            try ClosedLidPowerControl.disableWithoutPrompt()
            try ClosedLidPowerControl.stopExitWatchdog()
            isClosedLidEnabled = false
            defaults.set(false, forKey: closedLidActiveKey)
            DiagnosticJournal.shared.record("KeepAwake", "Closed-lid mode disabled; SleepDisabled verified off; recovery disarmed")
            refreshAssertionMode()
            ClosedLidPowerControl.requestSleepIfLidClosed()
        } catch {
            DiagnosticJournal.shared.recordError("KeepAwakeManager", error); errorMessage = "Could not turn off closed-lid mode: \(error.localizedDescription)"
        }
    }

    private func releaseAssertion() {
        assertionComponent?.stop()
        assertionComponent = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        pendingPointerReturn?.cancel()
        pendingPointerReturn = nil
        #if !MODULAR_FEATURES
        if let assertionID { IOPMAssertionRelease(assertionID) }
        assertionID = nil
        if let displayAssertionID { IOPMAssertionRelease(displayAssertionID) }
        displayAssertionID = nil
        #endif
        isActive = false
        activeUntil = nil
    }

    private func refreshAssertionMode() {
        guard isActive else { return }
        let remaining = activeUntil?.timeIntervalSinceNow
        if let remaining {
            if remaining > 0 { start(for: remaining) }
            else { stop() }
        } else {
            start()
        }
    }

    deinit {
        audioMuteTimer?.invalidate()
        audioMute.restore()
        expiryTimer?.invalidate()
        pointerTimer?.invalidate()
        pendingPointerReturn?.cancel()
        #if !MODULAR_FEATURES
        if let assertionID { IOPMAssertionRelease(assertionID) }
        if let displayAssertionID { IOPMAssertionRelease(displayAssertionID) }
        #endif
    }

    private func syncPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        guard isActive, movePointerSlightly, !displayMaySleep, !isClosedLidEnabled else { return }
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.nudgePointerIfIdle() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func nudgePointerIfIdle() {
        guard isActive, movePointerSlightly, !displayMaySleep, !isClosedLidEnabled else { return }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           session["CGSSessionScreenIsLocked"] as? Bool == true { return }
        guard CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved) >= 60,
              let original = CGEvent(source: nil)?.location,
              let bounds = Self.displayBounds(containing: original) else { return }
        let target = CGPoint(x: original.x + (original.x + 2 < bounds.maxX ? 1 : -1), y: original.y)
        guard bounds.contains(target) else { return }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)?
            .post(tap: .cghidEventTap)

        let returnMove = DispatchWorkItem {
            guard let current = CGEvent(source: nil)?.location,
                  abs(current.x - target.x) <= 2,
                  abs(current.y - target.y) <= 2 else { return }
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: original, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        pendingPointerReturn?.cancel()
        pendingPointerReturn = returnMove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: returnMove)
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).map(CGDisplayBounds).first { $0.contains(point) }
    }
}
