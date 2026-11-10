import Foundation
import CryptoKit

struct ProblemReport: Codable, Sendable, Equatable {
    var schema = 1
    var id = UUID().uuidString
    var kind = "bug"
    var details = ""
    var diagnostics = ""
    var crash = ""
    var appVersion = ""
    var osVersion = ""
    var test = false
    static let recipient = "nithilanvivek@gmail.com"

    static func isCrashDiagnostic(_ data: Data) -> Bool {
        guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { return false }
        let payload = text.firstIndex(of: "\n").map { String(text[text.index(after: $0)...]) } ?? text
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            ?? (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
        if let object {
            guard object["procName"] as? String == "AutoProductive" || object["app_name"] as? String == "AutoProductive" else { return false }
            let exception = object["exception"] as? [String: Any] ?? [:]
            let signal = exception["signal"] as? String ?? ""
            if ["SIGTERM", "SIGINT", "SIGHUP"].contains(signal) { return false }
            let termination = object["termination"] as? [String: Any] ?? [:]
            if termination["namespace"] as? String == "SIGNAL",
               let code = termination["code"] as? Int, [1, 2, 15].contains(code) { return false }
            return exception["type"] != nil || !termination.isEmpty
        }
        let lines = text.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.hasPrefix("Process:") && $0.contains("AutoProductive") }),
              let exception = lines.first(where: { $0.hasPrefix("Exception Type:") }) else { return false }
        return !["SIGTERM", "SIGINT", "SIGHUP"].contains(where: exception.contains)
    }

    func deliveryID(after previous: Self?) -> String {
        previous == nil || previous == self ? id : UUID().uuidString
    }

    static func crashDate(_ data: Data) -> Date? {
        guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { return nil }
        var candidates: [String] = []
        let sections = [text, text.components(separatedBy: .newlines).first ?? "", text.firstIndex(of: "\n").map { String(text[text.index(after: $0)...]) } ?? ""]
        for section in sections {
            if let object = (try? JSONSerialization.jsonObject(with: Data(section.utf8))) as? [String: Any] {
                for key in ["captureTime", "timestamp"] { if let value = object[key] as? String { candidates.append(value) } }
            }
        }
        if let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("Date/Time:") }) {
            candidates.append(String(line.dropFirst("Date/Time:".count)).trimmingCharacters(in: .whitespaces))
        }
        for value in candidates {
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: value) { return date }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            for pattern in ["yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss Z"] {
                formatter.dateFormat = pattern
                if let date = formatter.date(from: value) { return date }
            }
        }
        return nil
    }

    static func redact(_ text: String, limit: Int = 160_000) -> String {
        var value = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        for (pattern, replacement) in [
            (#"/Users/[^/\s\"<>]+"#, "/Users/[user]"),
            (#"(?i)\b(?:re_|sk-)[A-Za-z0-9_-]{12,}"#, "[redacted key]"),
            (#"(?i)Bearer\s+[A-Za-z0-9._~-]+"#, "Bearer [redacted]")
        ] {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        var result = String(value.prefix(limit))
        while result.utf8.count > limit { result.removeLast() }
        return result
    }

    /// Keep symbolication data, exception and stack frames; omit paths, account
    /// identifiers, command arguments and the raw macOS diagnostic metadata.
    static func crashSummary(_ data: Data) -> String {
        guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { return "Crash report could not be decoded." }
        let payload = text.firstIndex(of: "\n").map { String(text[text.index(after: $0)...]) } ?? text
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            ?? (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
        if let object {
            guard object["procName"] as? String == "AutoProductive" || object["app_name"] as? String == "AutoProductive" else { return "The diagnostic file is not an AutoProductive crash report." }
            var safe: [String: Any] = [:]
            for key in ["app_version", "build_version", "procName", "procLaunch", "captureTime", "osVersion", "exception", "termination", "faultingThread", "translated"] { safe[key] = object[key] }
            safe["threads"] = (object["threads"] as? [[String: Any]])?.prefix(32).map { thread in
                var result: [String: Any] = [:]
                result["triggered"] = thread["triggered"]
                result["frames"] = (thread["frames"] as? [[String: Any]])?.prefix(80).map { frame in
                    frame.filter { ["imageOffset", "imageIndex", "symbol", "symbolLocation"].contains($0.key) }
                }
                return result
            }
            safe["usedImages"] = (object["usedImages"] as? [[String: Any]])?.prefix(500).map { image in
                image.filter { ["name", "uuid", "arch", "base", "size"].contains($0.key) }
            }
            if let result = try? JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys]), let value = String(data: result, encoding: .utf8) { return redact(value, limit: 200_000) }
        }
        let lines = text.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.hasPrefix("Process:") && $0.contains("AutoProductive") }) else { return "The diagnostic file is not an AutoProductive crash report." }
        var stack = false
        return redact(lines.filter { line in
            if line.hasPrefix("Thread ") { stack = line.contains("Crashed:") }
            if line.hasPrefix("Binary Images:") { stack = false }
            return stack || ["Process:", "Version:", "Code Type:", "OS Version:", "Exception Type:", "Exception Codes:", "Termination Reason:", "Triggered by Thread:"].contains(where: line.hasPrefix)
        }.joined(separator: "\n"), limit: 200_000)
    }
}

struct ReportChallenge: Codable, Sendable {
    let token: String
    let difficulty: Int
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func solve() throws -> String {
        guard (1...22).contains(difficulty), token.utf8.count <= 1024 else { throw ReportError.failed("The reporting service returned an invalid response.") }
        for nonce in 0..<30_000_000 {
            if nonce % 4096 == 0 { try Task.checkCancellation() }
            let bytes = Array(SHA256.hash(data: Data("\(token):\(nonce)".utf8)))
            if (0..<difficulty).allSatisfy({ bytes[$0 >> 3] & (128 >> ($0 & 7)) == 0 }) { return String(nonce) }
        }
        throw ReportError.failed("Could not verify the report. Please try again.")
    }
}
enum ReportError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
}

struct CrashPromptState {
    static func shouldPrompt(previousLaunch: Date?, cleanExit: Bool, latestCrash: Date?, lastPresentedCrash: Date? = nil) -> Bool {
        guard !cleanExit, let previousLaunch, let latestCrash, latestCrash >= previousLaunch else { return false }
        return lastPresentedCrash.map { latestCrash > $0 } ?? true
    }
}
