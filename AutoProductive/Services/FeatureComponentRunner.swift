import Foundation
import Darwin

/// Executes a previously verified package as a separate process. Input and
/// output travel through pipes; clipboard contents are never written to disk.
struct FeatureComponentRunner {
    enum RunnerError: LocalizedError {
        case tooLarge, failed, timedOut
        var errorDescription: String? {
            switch self {
            case .tooLarge: "The action's input or output is too large."
            case .failed: "The feature component could not complete the action. Check its inputs and permissions."
            case .timedOut: "The feature component took too long to respond."
            }
        }
    }
    static let maximumDataSize = 20 * 1024 * 1024

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

    static func run(package: FeaturePackageManifest.Package, store: FeaturePackageStore,
                    request: Data, timeout: TimeInterval = 20, maximumOutputSize: Int = maximumDataSize) async throws -> Data {
        try await runVerified(executable: store.verifiedBytes(for: package), request: request,
                              timeout: timeout, maximumOutputSize: maximumOutputSize)
    }

    /// The caller must have verified these bytes against signed metadata.
    static func runVerified(executable: Data, request: Data, timeout: TimeInterval? = 20,
                            maximumOutputSize: Int = maximumDataSize, maximumRequestSize: Int = maximumDataSize,
                            cancelRunningProcess: Bool = true) async throws -> Data {
        guard maximumRequestSize > 0, maximumRequestSize <= 128 * 1024 * 1024,
              request.count <= maximumRequestSize else { throw RunnerError.tooLarge }
        guard maximumOutputSize > 0, maximumOutputSize <= 128 * 1024 * 1024 else { throw RunnerError.tooLarge }
        let state = State()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-component-" + UUID().uuidString, isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: folder) }
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                            attributes: [.posixPermissions: 0o700])
                        let path = folder.appendingPathComponent("component")
                        try executable.write(to: path, options: [.atomic])
                        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
                        if state.flags().0 { throw CancellationError() }
                        let process = Process()
                        let input = Pipe(), output = Pipe()
                        process.executableURL = path
                        process.standardInput = input
                        process.standardOutput = output
                        process.standardError = FileHandle.nullDevice
                        try process.run()
                        if state.register(process) { process.terminate() }
                        let timer: DispatchSourceTimer?
                        if let timeout {
                            let active = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                            active.schedule(deadline: .now() + max(1, timeout))
                            active.setEventHandler { state.stop(timeout: true) }
                            active.resume()
                            timer = active
                        } else { timer = nil }
                        defer { timer?.cancel() }
                        do {
                            try input.fileHandleForWriting.write(contentsOf: request)
                            try input.fileHandleForWriting.close()
                        } catch {
                            if process.isRunning { process.terminate() }
                            process.waitUntilExit()
                            let (cancelled, timedOut) = state.flags()
                            if cancelled { throw CancellationError() }
                            if timedOut { throw RunnerError.timedOut }
                            throw error
                        }
                        var reply = Data()
                        while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                            guard chunk.count <= maximumOutputSize - reply.count else {
                                if process.isRunning { process.terminate() }
                                process.waitUntilExit()
                                throw RunnerError.tooLarge
                            }
                            reply.append(chunk)
                        }
                        process.waitUntilExit()
                        let (cancelled, timedOut) = state.flags()
                        if cancelled { throw CancellationError() }
                        if timedOut { throw RunnerError.timedOut }
                        guard process.terminationStatus == 0 else { throw RunnerError.failed }
                        continuation.resume(returning: reply)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { if cancelRunningProcess { state.stop() } }
    }
}
