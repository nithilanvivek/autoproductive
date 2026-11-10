import Foundation

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try value() else { fatalError(message) }
    checks += 1
}
try check(ClosedLidPowerControl.sleepDisabled(in: "System-wide power settings:\n SleepDisabled\t1\n"), "Enabled system-wide setting is recognized")
try check(!ClosedLidPowerControl.sleepDisabled(in: "System-wide power settings:\n SleepDisabled 0\n"), "Disabled setting is recognized")
try check(!ClosedLidPowerControl.sleepDisabled(in: "System-wide power settings:\nCurrently in use:\n sleep 1\n"), "An unset global override allows a first activation")
try check(!ClosedLidPowerControl.sleepDisabled(in: "Currently in use:\n sleep 1\n"), "Normal current power settings need no explicit global override")
for invalid in ["", "permission denied", "System-wide power settings:\n SleepDisabled unknown\n"] {
    do { _ = try ClosedLidPowerControl.sleepDisabled(in: invalid); fatalError("Malformed power report must fail") }
    catch { checks += 1 }
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-watchdog-tests-\(UUID())")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
func parent() throws -> Process {
    let value = Process(); value.executableURL = URL(fileURLWithPath: "/bin/sleep"); value.arguments = ["30"]
    try value.run(); return value
}
let oldParent = try parent()
let oldResult = folder.appendingPathComponent("old session $ literal.txt")
let oldWatchdog = try ExitRecoveryWatchdog(parentPID: oldParent.processIdentifier, recoveryExecutable: "/usr/bin/touch", arguments: [oldResult.path])
try oldWatchdog.disarm()
oldParent.terminate(); oldParent.waitUntilExit()
let newParent = try parent()
let newResult = folder.appendingPathComponent("new session ' literal.txt")
let newWatchdog = try ExitRecoveryWatchdog(parentPID: newParent.processIdentifier, recoveryExecutable: "/usr/bin/touch", arguments: [newResult.path])
Thread.sleep(forTimeInterval: 1.2)
try check(!FileManager.default.fileExists(atPath: oldResult.path), "A disarmed old session cannot restore another session's setting when its app exits")
try check(!FileManager.default.fileExists(atPath: newResult.path), "Recovery does not run while the owning process is alive")
newParent.terminate(); newParent.waitUntilExit()
let deadline = Date().addingTimeInterval(4)
while !FileManager.default.fileExists(atPath: newResult.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
try check(FileManager.default.fileExists(atPath: newResult.path), "Active session recovery runs after unexpected parent exit and preserves literal arguments")
try newWatchdog.disarm()
print("\(checks) closed-lid power parsing and recovery checks passed")
