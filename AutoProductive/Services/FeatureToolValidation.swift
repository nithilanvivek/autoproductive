import Darwin
import Foundation

/// Tool compatibility is checked in a separate copy of the signed app process.
/// This avoids registering two versions of a Swift library in the running app.
enum FeatureToolValidation {
    static let argument = "--autoproductive-validate-tool"
    enum ValidationError: Error { case invalid, timedOut }

    /// Call before starting SwiftUI. Test hosts can call the same entry point.
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.count > 1, arguments[1] == argument else { return nil }
        guard arguments.count == 4, let symbols = FeatureComponentSupport.requiredToolSymbols(arguments[2]) else { return 1 }
        do {
            let url = URL(fileURLWithPath: arguments[3])
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size > 0, size <= 512 * 1024 * 1024 else { return 1 }
            _ = try FeatureToolLibrary.open(verifiedBytes: Data(contentsOf: url), expectedID: arguments[2], requiredSymbols: symbols)
            return 0
        } catch { return 1 }
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var process: Process?
        var cancelled = false
        var timedOut = false
        func stop(timeout: Bool = false) {
            lock.lock()
            if timeout { timedOut = true } else { cancelled = true }
            let running = process
            lock.unlock()
            if let running, running.isRunning {
                running.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    if running.isRunning { kill(running.processIdentifier, SIGKILL) }
                }
            }
        }
        func register(_ value: Process) -> Bool {
            lock.lock(); defer { lock.unlock() }
            process = value
            return cancelled || timedOut
        }
        func flags() -> (Bool, Bool) {
            lock.lock(); defer { lock.unlock() }
            return (cancelled, timedOut)
        }
    }

    static func validate(bytes: Data, id: String) async throws {
        let state = State()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-tool-check-" + UUID().uuidString, isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    do {
                        guard FeatureComponentSupport.requiredToolSymbols(id) != nil else { throw ValidationError.invalid }
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        let file = directory.appendingPathComponent("component.dylib")
                        try bytes.write(to: file, options: [.atomic])
                        if state.flags().0 { throw CancellationError() }
                        let process = Process()
                        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
                        process.arguments = [argument, id, file.path]
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = FileHandle.nullDevice
                        process.standardError = FileHandle.nullDevice
                        try process.run()
                        if state.register(process) { process.terminate() }
                        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                        timer.schedule(deadline: .now() + 15)
                        timer.setEventHandler { state.stop(timeout: true) }
                        timer.resume()
                        defer { timer.cancel() }
                        process.waitUntilExit()
                        let (cancelled, timedOut) = state.flags()
                        if cancelled { throw CancellationError() }
                        if timedOut { throw ValidationError.timedOut }
                        guard process.terminationStatus == 0 else { throw ValidationError.invalid }
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { state.stop() }
    }
}
