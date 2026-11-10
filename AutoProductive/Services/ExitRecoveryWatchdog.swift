import Foundation

/// One recovery process per active session. Disarming removes its authority to
/// restore the setting, including if another app takes over before our app exits.
final class ExitRecoveryWatchdog {
    private let marker: URL
    private let process: Process

    init(parentPID: Int32 = getpid(), recoveryExecutable: String, arguments: [String]) throws {
        marker = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-recovery-\(UUID().uuidString)")
        try Data().write(to: marker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Paths and arguments are positional parameters, never shell source.
        process.arguments = ["-c", """
        marker=$1; parent=$2; shift 2
        while /bin/kill -0 "$parent" 2>/dev/null; do
            [ -f "$marker" ] || exit 0
            /bin/sleep 1
        done
        [ -f "$marker" ] || exit 0
        "$@" >/dev/null 2>&1
        /bin/rm -f "$marker"
        """, "autoproductive-recovery", marker.path, String(parentPID), recoveryExecutable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { try? FileManager.default.removeItem(at: marker); throw error }
    }

    func disarm() throws {
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        if process.isRunning { process.terminate() }
    }
}
