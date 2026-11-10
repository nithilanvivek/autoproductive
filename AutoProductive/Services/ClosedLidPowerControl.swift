import Foundation
import IOKit.pwr_mgt

enum ClosedLidPowerControl {
    private static let rulePath = "/private/etc/sudoers.d/autoproductive-clamshell"
    private static let pmset = "/usr/bin/pmset"
    private static let watchdogLock = NSLock()
    private static var watchdog: ExitRecoveryWatchdog?

    static func isSleepDisabled() throws -> Bool {
        let output = try run(pmset, ["-g"])
        return try sleepDisabled(in: output)
    }

    static func sleepDisabled(in output: String) throws -> Bool {
        // pmset omits the global setting on machines where it was never set.
        guard output.contains("System-wide power settings:") || output.contains("Currently in use:") else {
            throw Failure("macOS did not return its power settings.")
        }
        guard let line = output.split(separator: "\n").first(where: { $0.split(whereSeparator: \.isWhitespace).first == "SleepDisabled" }) else { return false }
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else { throw Failure("macOS returned an unrecognized SleepDisabled value.") }
        return fields[1] == "1"
    }

    static func enableWithoutPrompt() throws {
        _ = try run("/usr/bin/sudo", ["-n", pmset, "disablesleep", "1"])
        guard try isSleepDisabled() else { throw Failure("macOS did not enable closed-lid mode.") }
    }

    static func disableWithoutPrompt() throws {
        _ = try run("/usr/bin/sudo", ["-n", pmset, "disablesleep", "0"])
        guard try !isSleepDisabled() else { throw Failure("macOS did not turn closed-lid mode off.") }
    }

    static func installPermission() throws {
        let uid = getuid()
        let rule = "#\(uid) ALL=(root) NOPASSWD: \(pmset) disablesleep 1, \(pmset) disablesleep 0"
        let command = "set -eu; p='\(rulePath)'; t=$(/usr/bin/mktemp \(rulePath).XXXXXXXX); trap '/bin/rm -f \"$t\"' EXIT; /usr/bin/printf '%s\\n' '\(rule)' > \"$t\"; /bin/chmod 0440 \"$t\"; /usr/sbin/chown root:wheel \"$t\"; /usr/sbin/visudo -c -f \"$t\" >/dev/null; /bin/mv -f \"$t\" \"$p\""
        try authorize(command)
    }

    static func removePermission() throws {
        try authorize("/bin/rm -f '\(rulePath)'")
    }

    static func startExitWatchdog() throws {
        watchdogLock.lock()
        defer { watchdogLock.unlock() }
        guard watchdog == nil else { return }
        watchdog = try ExitRecoveryWatchdog(recoveryExecutable: "/usr/bin/sudo", arguments: ["-n", pmset, "disablesleep", "0"])
    }

    static func stopExitWatchdog() throws {
        watchdogLock.lock()
        defer { watchdogLock.unlock() }
        try watchdog?.disarm()
        watchdog = nil
    }

    /// Clearing disablesleep does not replay a lid-close event. If the lid is
    /// already shut and macOS says it should cause sleep, request that sleep.
    /// External-display mode is left to macOS.
    static func requestSleepIfLidClosed() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard property("AppleClamshellState", of: service) == true else { return }

        for _ in 0..<6 {
            if (try? isSleepDisabled()) == true { return }
            if property("AppleClamshellCausesSleep", of: service) == true {
                let domain = IOPMFindPowerManagement(kIOMainPortDefault)
                guard domain != 0 else { return }
                let result = IOPMSleepSystem(domain)
                IOServiceClose(domain)
                if result == kIOReturnSuccess { return }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private static func property(_ name: String, of service: io_service_t) -> Bool? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    private static func authorize(_ command: String) throws {
        let quoted = "\"" + command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        _ = try run("/usr/bin/osascript", ["-e", "do shell script \(quoted) with administrator privileges"])
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw Failure(message.isEmpty ? "\(URL(fileURLWithPath: executable).lastPathComponent) failed (\(process.terminationStatus))." : message)
        }
        return message
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
