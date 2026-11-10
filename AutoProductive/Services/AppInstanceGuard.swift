import AppKit
import Darwin

/// Claim ownership before any listener, menu scene, or audio tap is initialized.
@MainActor
final class AppInstanceGuard {
    static let showMainWindow = Notification.Name((Bundle.main.bundleIdentifier ?? "land.nithi.autoproductive") + ".show-main-window")
    private let descriptor: Int32

    init() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier
        let olderCopy = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && $0.processIdentifier < ownPID && !$0.isTerminated
        }
        if olderCopy { Self.forwardLaunchAndExit() }

        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(FeatureComponentSupport.supportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        descriptor = Darwin.open(folder.appendingPathComponent("instance.lock").path,
                                 O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            Self.forwardLaunchAndExit()
        }
    }

    private static func forwardLaunchAndExit() -> Never {
        if !ProcessInfo.processInfo.arguments.contains("--menu-bar-agent") {
            DistributedNotificationCenter.default().postNotificationName(showMainWindow,
                object: nil, userInfo: nil, deliverImmediately: true)
        }
        exit(EXIT_SUCCESS)
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }
}
