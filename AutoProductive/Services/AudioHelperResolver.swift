import Foundation

enum AudioHelperResolver {
    /// Shared XPC binaries (including WebKit and Quick Look) have generic bundle
    /// IDs. Resolve their actual launching app from live service memberships,
    /// never from a helper name that could also belong to another application.
    static func owners(for applicationPIDs: [Int32]) -> [Int32: Int32] {
        var memberships: [Int32: Set<Int32>] = [:]
        for pid in applicationPIDs {
            guard let description = description(for: pid) else { continue }
            memberships[pid] = AudioProcessOwnership.serviceHelpers(in: description)
        }
        return AudioProcessOwnership.unambiguousOwners(memberships)
    }

    private static func description(for pid: Int32) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "pid/\(pid)"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: deadline)
        defer { deadline.cancel() }
        var data = Data()
        while let chunk = try? output.fileHandleForReading.read(upToCount: 16_384), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 2_000_000 { process.terminate(); return nil }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
