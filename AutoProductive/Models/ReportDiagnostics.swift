import Foundation

/// A bounded local journal of app states. Never record user text, file contents,
/// automation names, scripts, window titles or keypresses here.
final class DiagnosticJournal: @unchecked Sendable {
    static let shared = DiagnosticJournal(folder: ProcessInfo.processInfo.environment["AUTOPRODUCTIVE_DIAGNOSTICS_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) })
    private let lock = NSLock()
    private let folder: URL
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier == "land.nithi.autoproductive.test14" ? "AutoProductive 1.4 Test/Diagnostics" : "AutoProductive/Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }
    func beginSession() {
        lock.lock(); defer { lock.unlock() }
        let current = folder.appendingPathComponent("current.log"), previous = folder.appendingPathComponent("previous.log")
        if FileManager.default.fileExists(atPath: current.path) {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: current, to: previous)
        }
    }
    func record(_ category: String, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        let url = folder.appendingPathComponent("current.log")
        let line = "\(ISO8601DateFormatter().string(from: .now)) [\(category)] \(message)\n"
        var data = (try? Data(contentsOf: url)) ?? Data()
        data.append(Data(line.utf8))
        if data.count > 128_000 { data = Data(data.suffix(96_000)) }
        try? data.write(to: url, options: .atomic)
    }
    func recordError(_ category: String, _ error: Error, context: String = "") {
        let native = error as NSError
        recordErrorMessage(category, "\(context.isEmpty ? "" : context + "; ")domain=\(native.domain); code=\(native.code); \(native.localizedDescription)")
    }
    func recordErrorMessage(_ category: String, _ message: String) {
        record(category, "ERROR: " + Self.safeErrorMessage(message))
    }
    static func safeErrorMessage(_ message: String) -> String {
        // A script's stderr/stdout may contain arbitrary private data. Keep its
        // exit status, but never include the captured script output in reports.
        var safe = message
        if let exit = safe.range(of: #"Script exited with code -?\d+"#, options: .regularExpression) {
            safe = String(safe[..<exit.upperBound]) + "; script output excluded"
        }
        return ProblemReport.redact(safe, limit: 2_000)
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
    func contents(includePrevious: Bool) -> String {
        lock.lock(); defer { lock.unlock() }
        return (includePrevious ? ["current.log", "previous.log"] : ["current.log"]).compactMap { name in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
            let value = String(decoding: data.suffix(includePrevious ? 75_000 : 150_000), as: UTF8.self)
            return "--- \(name) ---\n\(value)"
        }.joined(separator: "\n")
    }
}

struct CrashDiagnostic: Sendable {
    let date: Date
    let summary: String
    static func latest(in directory: URL? = nil) -> Self? {
        let folder = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])) ?? []
        let candidates: [(URL, Date)] = files.compactMap { url in
            guard url.lastPathComponent.hasPrefix("AutoProductive"), ["ips", "crash"].contains(url.pathExtension),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 8 * 1024 * 1024,
                  let date = values.contentModificationDate else { return nil }
            return (url, date)
        }
        for (url, _) in candidates.sorted(by: { $0.1 > $1.1 }) {
            guard let data = try? Data(contentsOf: url), ProblemReport.isCrashDiagnostic(data),
                  let date = ProblemReport.crashDate(data) else { continue }
            return Self(date: date, summary: ProblemReport.crashSummary(data))
        }
        return nil
    }
}
