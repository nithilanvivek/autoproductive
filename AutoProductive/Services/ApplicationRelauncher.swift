import AppKit
import Foundation

enum ApplicationRelauncher {
    static let waitScript = """
        count=0
        while /bin/kill -0 "$1" 2>/dev/null && [ "$count" -lt 50 ]; do
          /bin/sleep 0.1
          count=$((count + 1))
        done
        # SwiftUI can defer AppKit termination while a setup sheet is open.
        # Restart is explicitly requested, so finish closing this app if the
        # normal termination request has not completed.
        if /bin/kill -0 "$1" 2>/dev/null; then
          /bin/kill -TERM "$1" 2>/dev/null || true
          count=0
          while /bin/kill -0 "$1" 2>/dev/null && [ "$count" -lt 100 ]; do
            /bin/sleep 0.1
            count=$((count + 1))
          done
        fi
        if ! /bin/kill -0 "$1" 2>/dev/null; then
          if [ -n "$4" ]; then /bin/rm -rf -- "$4"; fi
          "$3" "$2"
        fi
        """
    /// A separate short-lived process waits for the current instance to exit
    /// before asking Launch Services to reopen the same application bundle.
    @MainActor static func restart(prepareForRestart: () -> Void) throws {
        let bundle = Bundle.main.bundleURL
        let oldBundle = try AppArchitectureThinner.prepareAndSwap(bundle: bundle)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", waitScript, "autoproductive-reopen", String(ProcessInfo.processInfo.processIdentifier),
                            bundle.path, "/usr/bin/open", oldBundle?.path ?? ""]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do { try helper.run() }
        catch {
            if let oldBundle { try AppArchitectureThinner.rollback(bundle: bundle, oldBundle: oldBundle) }
            throw error
        }
        prepareForRestart()
        NSApp.terminate(nil)
    }
}
