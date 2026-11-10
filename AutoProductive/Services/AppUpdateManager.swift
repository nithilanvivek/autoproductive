import AppKit
import Combine
import Sparkle
import UserNotifications

/// Sparkle verifies the update signature before extraction.
/// The app's own calendar scheduler keeps the check at 5 p.m. local time.
@MainActor
final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdateManager()

    @Published private(set) var availableVersion: String?
    @Published private(set) var availableDisplayVersion: String?
    private let defaults = UserDefaults.standard
    private let lastCheckKey = "updates.lastScheduledCheck.v1"
    private let availableKey = "updates.availableVersion.v1"
    private let displayKey = "updates.availableDisplayVersion.v1"
    private let skippedKey = "updates.skippedVersion.v1"
    private let notifiedKey = "updates.notifiedVersion.v1"
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false
    private var scheduledCheckInProgress = false
    private lazy var userDriver = CancelableUpdateDriver(hostBundle: .main, delegate: nil)
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)

    override private init() {
        super.init()
        var pending = defaults.string(forKey: availableKey)
        if let version = pending,
           let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           SUStandardVersionComparator.default.compareVersion(installed, toVersion: version) != .orderedAscending {
            defaults.removeObject(forKey: availableKey)
            pending = nil
        }
        availableVersion = pending == defaults.string(forKey: skippedKey) ? nil : pending
        availableDisplayVersion = availableVersion == nil ? nil : defaults.string(forKey: displayKey)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        do { try updater.start() }
        catch { DiagnosticJournal.shared.recordError("Start updater", error); isStarted = false; return }
        updater.automaticallyChecksForUpdates = false
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        schedule()
    }

    func checkNow() {
        guard isStarted else { return }
        updater.checkForUpdates()
    }

    func skip() {
        guard let version = availableVersion else { return }
        defaults.set(version, forKey: skippedKey)
        availableVersion = nil
    }

    private func schedule(retryAfterFailure: Bool = false) {
        timer?.invalidate()
        guard isStarted else { return }
        let now = Date()
        let last = defaults.object(forKey: lastCheckKey) as? Date
        let target = retryAfterFailure ? now.addingTimeInterval(15 * 60) : UpdateSchedule.nextCheck(after: now, lastSuccessfulCheck: last)
        timer = Timer.scheduledTimer(withTimeInterval: max(0.1, target.timeIntervalSince(now)), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkOnSchedule() }
        }
    }

    private func checkOnSchedule() {
        guard !updater.sessionInProgress else { schedule(retryAfterFailure: true); return }
        scheduledCheckInProgress = true
        updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.versionString
        defaults.set(version, forKey: availableKey)
        defaults.set(item.displayVersionString, forKey: displayKey)
        guard version != defaults.string(forKey: skippedKey) else { return }
        availableVersion = version
        availableDisplayVersion = item.displayVersionString
        guard scheduledCheckInProgress, defaults.string(forKey: notifiedKey) != version else { return }
        let displayVersion = item.displayVersionString
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                let content = UNMutableNotificationContent()
                content.title = "AutoProductive update available"
                content.body = "Version \(displayVersion) is ready to install."
                do {
                    try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "autoproductive.update.\(version)", content: content, trigger: nil))
                    self.defaults.set(version, forKey: self.notifiedKey)
                } catch {
                    DiagnosticJournal.shared.recordError("Update notification", error)
                }
            }
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        // A manual check must not erase a skipped version's remembered state.
        guard scheduledCheckInProgress else { return }
        availableVersion = nil
        defaults.removeObject(forKey: availableKey)
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip {
            defaults.set(item.versionString, forKey: skippedKey)
            availableVersion = nil
        } else if choice == .install {
            availableVersion = nil
            defaults.removeObject(forKey: availableKey)
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard scheduledCheckInProgress else { return }
        scheduledCheckInProgress = false
        // Sparkle reports no update as SUNoUpdateError, which is still a
        // completed check. Network and signature errors should be retried.
        let nsError = error as NSError?
        let noUpdate = nsError?.domain == SUSparkleErrorDomain && nsError?.code == Int(SUError.noUpdateError.rawValue)
        let succeeded = error == nil || noUpdate
        if succeeded { defaults.set(Date(), forKey: lastCheckKey) }
        schedule(retryAfterFailure: !succeeded)
    }
}

/// Sparkle's ready-to-install callback supports cancellation without skipping
/// the version. Keep its standard driver for all other update stages.
@MainActor private final class CancelableUpdateDriver: SPUStandardUserDriver {
    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        guard let reason, reason.int32Value == SPUNoUpdateFoundReason.onLatestVersion.rawValue ||
                reason.int32Value == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue else {
            super.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
            return
        }
        let alert = NSAlert()
        alert.messageText = "You’re up to date!"
        alert.informativeText = "No updates are available."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
        acknowledgement()
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Ready to install"
        alert.informativeText = "Install the update and reopen AutoProductive, or cancel and update later."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        let result = alert.runModal()
        reply(result == .alertFirstButtonReturn ? .install : .skip)
    }
}
