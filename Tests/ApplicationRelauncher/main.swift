import Foundation

@main struct Tests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let opener = root.appendingPathComponent("open-test")
        try "#!/bin/sh\nprintf '%s' \"$1\" > \"$AUTOPRODUCTIVE_TEST_MARKER\"\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: opener.path)
        let target = Process()
        target.executableURL = URL(fileURLWithPath: "/bin/sleep")
        target.arguments = ["0.3"]
        try target.run()
        let marker = root.appendingPathComponent("opened")
        let bundle = root.appendingPathComponent("Test App.app").path
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", ApplicationRelauncher.waitScript, "test", String(target.processIdentifier), bundle, opener.path]
        helper.environment = ProcessInfo.processInfo.environment.merging(["AUTOPRODUCTIVE_TEST_MARKER": marker.path]) { _, new in new }
        try helper.run()
        target.waitUntilExit()
        helper.waitUntilExit()
        guard helper.terminationStatus == 0, try String(contentsOf: marker, encoding: .utf8) == bundle else {
            fatalError("Relaunch helper did not wait for the previous process and pass the bundle path")
        }
        try FileManager.default.removeItem(at: marker)
        let stuck = Process()
        stuck.executableURL = URL(fileURLWithPath: "/bin/sleep")
        stuck.arguments = ["30"]
        try stuck.run()
        let fallback = Process()
        fallback.executableURL = URL(fileURLWithPath: "/bin/sh")
        fallback.arguments = ["-c", ApplicationRelauncher.waitScript, "test", String(stuck.processIdentifier), bundle, opener.path]
        fallback.environment = helper.environment
        try fallback.run()
        stuck.waitUntilExit()
        fallback.waitUntilExit()
        guard stuck.terminationReason == .uncaughtSignal, fallback.terminationStatus == 0,
              try String(contentsOf: marker, encoding: .utf8) == bundle else {
            fatalError("Relaunch fallback did not stop and reopen the test process")
        }
        print("Passed normal and stalled restart-helper checks.")
    }
}
