import CryptoKit
import Foundation

/// A missing generation denotes an existing installation using bundled code.
/// Once a generation exists, missing optional components are reported rather
/// than silently using an unselected feature.
struct FeatureComponentDispatcher {
    enum DispatchError: LocalizedError {
        case missingComponent(String), invalidPublicKey, invalidReply, incompatibleGeneration
        var errorDescription: String? {
            switch self {
            case .missingComponent(let name): "Install the \(name) action to use it."
            case .invalidPublicKey: "The feature signing key is unavailable."
            case .invalidReply: "The clipboard transformation component returned an invalid response."
            case .incompatibleGeneration: "Features need to be updated for this app version."
            }
        }
    }
    private struct Request: Encodable { let text: String; let operation: String }
    private struct Response: Decodable { let text: String }
    private struct WaitRequest: Encodable { let duration: Double }
    private struct ReadFileRequest: Encodable { let path: String }
    private struct FileMutationRequest: Encodable { let path: String; let text: String }
    private struct SystemControlRequest: Encodable { let option: String; let amount: Double }
    private struct SetClipboardRequest: Encodable { let text: String; let pasteboardName: String? }
    struct InputRequest: Encodable {
        var keyCode: UInt32? = nil
        var modifiers: UInt? = nil
        var text: String? = nil
        var x: Double? = nil
        var y: Double? = nil
        var button: String? = nil
        var coordinatesInPixels: Bool? = nil
        var displayScale: Double? = nil
        var displayWidth: Double? = nil
        var displayHeight: Double? = nil
    }
    private struct OpenRequest: Encodable { let value: String; let subject: String; let body: String }
    private struct OpenResponse: Decodable { let url: String }
    struct ScreenWaitPlan: Decodable { let duration: Double; let pollInterval: Double }
    private struct ScriptRequest: Encodable { let script: String }
    struct ScriptPlan: Decodable { let executable: String; let arguments: [String] }
    private struct DialogRequest: Encodable { let title: String; let details: String }
    struct DialogPlan: Decodable { let kind: String; let title: String; let details: String; let choices: [String] }
    struct WindowRequest: Encodable {
        let option: String
        let x: Double
        let y: Double
        let amount: Double
        let heightText: String
        let areaX: Double?
        let areaY: Double?
        let areaWidth: Double?
        let areaHeight: Double?
    }
    struct WindowPlan: Decodable { let kind: String; let x: Double?; let y: Double?; let width: Double?; let height: Double? }
    private struct WaitResponse: Decodable {}

    static func transformClipboard(_ text: String, using operation: String,
                                   generations: FeaturePackageGenerations) async throws -> String {
        let executable: Data
        switch try generations.component(id: "action.transformClipboard") {
        case .legacy:
            #if MODULAR_FEATURES
            throw DispatchError.missingComponent("clipboard transformation")
            #else
            return ClipboardTransform.apply(text, using: operation)
            #endif
        case .missing: throw DispatchError.missingComponent("clipboard transformation")
        case .verified(let bytes): executable = bytes
        }
        let request = try JSONEncoder().encode(Request(text: text, operation: operation))
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: request)
        guard let response = try? JSONDecoder().decode(Response.self, from: output) else {
            throw DispatchError.invalidReply
        }
        return response.text
    }

    private static func activeGenerations() throws -> FeaturePackageGenerations? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(FeatureComponentSupport.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("Features", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("current.json").path) else {
            return nil
        }
        guard let encoded = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bytes = Data(base64Encoded: encoded),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes) else {
            throw DispatchError.invalidPublicKey
        }
        let generations = FeaturePackageGenerations(root: root, publicKey: key)
        #if MODULAR_FEATURES
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let current = try generations.current(), current.packages.allSatisfy({ $0.version == FeatureComponentSupport.componentVersion(for: version) }) else {
            throw DispatchError.incompatibleGeneration
        }
        #endif
        return generations
    }

    static func requireAction(id: String, title: String, generations: FeaturePackageGenerations?) throws {
        guard let generations, let current = try generations.current() else {
            #if MODULAR_FEATURES
            throw DispatchError.missingComponent(title)
            #else
            return
            #endif
        }
        guard current.packages.contains(where: { $0.id == id }) else {
            throw DispatchError.missingComponent(title)
        }
    }

    static func requireAction(id: String, title: String) throws {
        try requireAction(id: id, title: title, generations: activeGenerations())
    }

    static func currentActionIDs() throws -> Set<String> {
        guard let generations = try activeGenerations(), let current = try generations.current() else { return [] }
        return Set(current.packages.map(\.id).filter { $0.hasPrefix("action.") })
    }

    static func toolBytes(id: String, generations: FeaturePackageGenerations?) throws -> Data? {
        guard let generations else { return nil }
        switch try generations.component(id: id) {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent(id)
        case .verified(let bytes): return bytes
        }
    }

    static func toolBytes(id: String) throws -> Data? {
        try toolBytes(id: id, generations: activeGenerations())
    }

    static func transformClipboard(_ text: String, using operation: String) async throws -> String {
        guard let generations = try activeGenerations() else {
            #if MODULAR_FEATURES
            throw DispatchError.missingComponent("clipboard transformation")
            #else
            return ClipboardTransform.apply(text, using: operation)
            #endif
        }
        return try await transformClipboard(text, using: operation, generations: generations)
    }

    static func wait(_ duration: Double, generations: FeaturePackageGenerations?) async throws {
        guard let generations else {
            try await Task.sleep(for: .seconds(duration))
            return
        }
        let executable: Data
        switch try generations.component(id: "action.wait") {
        case .legacy: try await Task.sleep(for: .seconds(duration)); return
        case .missing: throw DispatchError.missingComponent("wait")
        case .verified(let bytes): executable = bytes
        }
        let request = try JSONEncoder().encode(WaitRequest(duration: duration))
        let response = try await FeatureComponentRunner.runVerified(executable: executable, request: request,
            timeout: max(5, duration + 5))
        guard (try? JSONDecoder().decode(WaitResponse.self, from: response)) != nil else {
            throw DispatchError.invalidReply
        }
    }

    static func wait(_ duration: Double) async throws {
        try await wait(duration, generations: activeGenerations())
    }

    /// Nil means no modular installation exists and the legacy action should
    /// run. An empty string is a successful read of an empty file.
    static func readFile(_ path: String, generations: FeaturePackageGenerations?) async throws -> String? {
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action.readFile") {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent("read a text file")
        case .verified(let bytes): executable = bytes
        }
        let request = try JSONEncoder().encode(ReadFileRequest(path: path))
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: request,
            maximumOutputSize: 128 * 1024 * 1024)
        guard let response = try? JSONDecoder().decode(Response.self, from: output) else {
            throw DispatchError.invalidReply
        }
        return response.text
    }

    static func readFile(_ path: String) async throws -> String? {
        try await readFile(path, generations: activeGenerations())
    }

    /// File changes finish once started, matching the legacy synchronous
    /// behavior and avoiding interrupted appends when a workflow is stopped.
    static func mutateFile(action: String, path: String, text: String,
                           generations: FeaturePackageGenerations?) async throws -> Bool {
        guard ["writeFile", "appendFile", "createFolder", "copyFile", "moveFile", "trashFile"].contains(action) else {
            throw DispatchError.missingComponent("file")
        }
        guard let generations else { return false }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return false
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        try Task.checkCancellation()
        let request = try JSONEncoder().encode(FileMutationRequest(path: path, text: text))
        let response = try await FeatureComponentRunner.runVerified(executable: executable, request: request,
            timeout: nil, maximumOutputSize: 4096, maximumRequestSize: 128 * 1024 * 1024,
            cancelRunningProcess: false)
        guard (try? JSONDecoder().decode(WaitResponse.self, from: response)) != nil else {
            throw DispatchError.invalidReply
        }
        try Task.checkCancellation()
        return true
    }

    static func mutateFile(action: String, path: String, text: String) async throws -> Bool {
        try await mutateFile(action: action, path: path, text: text, generations: activeGenerations())
    }

    static func adjustSystem(action: String, option: String, amount: Double,
                             generations: FeaturePackageGenerations?) async throws -> Bool {
        guard ["adjustSound", "adjustBrightness"].contains(action) else { throw DispatchError.missingComponent("system control") }
        guard let generations else { return false }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return false
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        try Task.checkCancellation()
        let request = try JSONEncoder().encode(SystemControlRequest(option: option, amount: amount))
        let response = try await FeatureComponentRunner.runVerified(executable: executable, request: request,
            timeout: nil, maximumOutputSize: 4096, cancelRunningProcess: false)
        guard (try? JSONDecoder().decode(WaitResponse.self, from: response)) != nil else { throw DispatchError.invalidReply }
        try Task.checkCancellation()
        return true
    }

    static func adjustSystem(action: String, option: String, amount: Double) async throws -> Bool {
        try await adjustSystem(action: action, option: option, amount: amount, generations: activeGenerations())
    }

    static func setClipboard(_ text: String, generations: FeaturePackageGenerations?, pasteboardName: String? = nil) async throws -> Bool {
        guard let generations else { return false }
        let executable: Data
        switch try generations.component(id: "action.setClipboard") {
        case .legacy: return false
        case .missing: throw DispatchError.missingComponent("set clipboard text")
        case .verified(let bytes): executable = bytes
        }
        try Task.checkCancellation()
        let request = try JSONEncoder().encode(SetClipboardRequest(text: text, pasteboardName: pasteboardName))
        let response = try await FeatureComponentRunner.runVerified(executable: executable, request: request,
            timeout: nil, maximumOutputSize: 4096, cancelRunningProcess: false)
        guard (try? JSONDecoder().decode(WaitResponse.self, from: response)) != nil else { throw DispatchError.invalidReply }
        try Task.checkCancellation()
        return true
    }

    static func setClipboard(_ text: String) async throws -> Bool {
        try await setClipboard(text, generations: activeGenerations())
    }

    static func inputPlan(action: String, request: InputRequest, generations: FeaturePackageGenerations?) async throws -> FeatureInputPlan? {
        let expected: [String: String] = ["pressKey": "key", "pasteClipboard": "key", "typeText": "unicode",
                                           "click": "click", "movePointer": "move", "scroll": "scroll"]
        guard let kind = expected[action] else { throw DispatchError.missingComponent("input") }
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        let input = try JSONEncoder().encode(request)
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: input,
            maximumOutputSize: 128 * 1024 * 1024)
        guard let plan = try? JSONDecoder().decode(FeatureInputPlan.self, from: output),
              plan.events.allSatisfy({ $0.kind == kind }),
              (action == "typeText" ? plan.events.count <= 1 : plan.events.count == 1) else { throw DispatchError.invalidReply }
        if action == "typeText", (plan.events.first?.text ?? "") != (request.text ?? "") { throw DispatchError.invalidReply }
        try plan.validate()
        return plan
    }

    static func inputPlan(action: String, request: InputRequest) async throws -> FeatureInputPlan? {
        try await inputPlan(action: action, request: request, generations: activeGenerations())
    }

    static func openTarget(action: String, value: String, subject: String = "", body: String = "",
                           generations: FeaturePackageGenerations?) async throws -> URL? {
        guard ["openURL", "openApp", "composeMail"].contains(action) else { throw DispatchError.invalidReply }
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        let request = try JSONEncoder().encode(OpenRequest(value: value, subject: subject, body: body))
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: request)
        guard let response = try? JSONDecoder().decode(OpenResponse.self, from: output),
              let url = URL(string: response.url) else { throw DispatchError.invalidReply }
        let validSchemes = action == "openApp" ? ["file"] : action == "composeMail" ? ["mailto"] : ["https", "http", "file"]
        guard validSchemes.contains(url.scheme?.lowercased() ?? "") else { throw DispatchError.invalidReply }
        return url
    }

    static func openTarget(action: String, value: String, subject: String = "", body: String = "") async throws -> URL? {
        try await openTarget(action: action, value: value, subject: subject, body: body, generations: activeGenerations())
    }

    static func screenWaitPlan(action: String, duration: Double, generations: FeaturePackageGenerations?) async throws -> ScreenWaitPlan? {
        guard ["screenPixel", "screenImage"].contains(action) else { throw DispatchError.invalidReply }
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        let input = try JSONEncoder().encode(WaitRequest(duration: duration))
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: input, maximumOutputSize: 4096)
        guard let plan = try? JSONDecoder().decode(ScreenWaitPlan.self, from: output),
              plan.duration == duration, plan.pollInterval == 0.3 else { throw DispatchError.invalidReply }
        return plan
    }

    static func screenWaitPlan(action: String, duration: Double) async throws -> ScreenWaitPlan? {
        try await screenWaitPlan(action: action, duration: duration, generations: activeGenerations())
    }

    static func scriptPlan(action: String, script: String, generations: FeaturePackageGenerations?) async throws -> ScriptPlan? {
        guard ["shell", "appleScript"].contains(action) else { throw DispatchError.invalidReply }
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        let input = try JSONEncoder().encode(ScriptRequest(script: script))
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: input, maximumOutputSize: 20 * 1024 * 1024)
        guard let plan = try? JSONDecoder().decode(ScriptPlan.self, from: output),
              plan.executable == (action == "shell" ? "/bin/zsh" : "/usr/bin/osascript"),
              plan.arguments == [action == "shell" ? "-c" : "-e", script] else { throw DispatchError.invalidReply }
        return plan
    }

    static func scriptPlan(action: String, script: String) async throws -> ScriptPlan? {
        try await scriptPlan(action: action, script: script, generations: activeGenerations())
    }

    static func dialogPlan(action: String, title: String, details: String, generations: FeaturePackageGenerations?) async throws -> DialogPlan? {
        guard ["prompt", "choose", "message", "notification"].contains(action) else { throw DispatchError.invalidReply }
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action." + action) {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent(action)
        case .verified(let bytes): executable = bytes
        }
        let input = try JSONEncoder().encode(DialogRequest(title: title, details: details))
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: input)
        let expectedChoices = action == "choose" ? details.components(separatedBy: .newlines).filter { !$0.isEmpty } : []
        guard let plan = try? JSONDecoder().decode(DialogPlan.self, from: output), plan.kind == action,
              plan.title == (title.isEmpty ? "AutoProductive" : title),
              plan.details == (action == "choose" ? "Choose an option." : details),
              plan.choices == expectedChoices,
              (action == "choose" ? (1...5).contains(plan.choices.count) : plan.choices.isEmpty) else { throw DispatchError.invalidReply }
        return plan
    }

    static func dialogPlan(action: String, title: String, details: String) async throws -> DialogPlan? {
        try await dialogPlan(action: action, title: title, details: details, generations: activeGenerations())
    }

    static func windowPlan(request: WindowRequest, generations: FeaturePackageGenerations?) async throws -> WindowPlan? {
        guard let generations else { return nil }
        let executable: Data
        switch try generations.component(id: "action.window") {
        case .legacy: return nil
        case .missing: throw DispatchError.missingComponent("arrange window")
        case .verified(let bytes): executable = bytes
        }
        let output = try await FeatureComponentRunner.runVerified(executable: executable, request: JSONEncoder().encode(request), maximumOutputSize: 4096)
        guard let plan = try? JSONDecoder().decode(WindowPlan.self, from: output) else { throw DispatchError.invalidReply }
        if request.option == "focus" || request.option == "minimize" {
            guard plan.kind == request.option else { throw DispatchError.invalidReply }
        } else {
            guard plan.kind == "frame", let x = plan.x, let y = plan.y, let width = plan.width, let height = plan.height,
                  [x, y, width, height].allSatisfy(\.isFinite), width >= 0, height >= 0 else { throw DispatchError.invalidReply }
        }
        return plan
    }

    static func windowPlan(request: WindowRequest) async throws -> WindowPlan? {
        try await windowPlan(request: request, generations: activeGenerations())
    }
}
