import CryptoKit
import Foundation
import AppKit

final class StubProtocol: URLProtocol {
    static var responses: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let data = Self.responses[url.path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Tests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let generations = FeaturePackageGenerations(root: root.appendingPathComponent("features"), publicKey: key.publicKey)
        #if MODULAR_FEATURES
        do {
            try FeatureComponentDispatcher.requireAction(id: "action.openURL", title: "Open a website or file", generations: generations)
            fatalError("Actions must not run before modular setup")
        } catch FeatureComponentDispatcher.DispatchError.missingComponent { }
        do {
            _ = try await FeatureComponentDispatcher.transformClipboard("private", using: "uppercase", generations: generations)
            fatalError("Uninstalled action must not use a bundled fallback")
        } catch FeatureComponentDispatcher.DispatchError.missingComponent { }
        #else
        try FeatureComponentDispatcher.requireAction(id: "action.openURL", title: "Open a website or file", generations: generations)
        let legacy = try await FeatureComponentDispatcher.transformClipboard("Straße", using: "uppercase", generations: generations)
        guard legacy == "STRASSE" else { fatalError("Existing users must retain bundled behavior") }
        #endif
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let package = FeaturePackageManifest.Package(id: "action.transformClipboard", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/clipboard")!, sha256: digest, size: Int64(bytes.count))
        let waitBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let waitDigest = SHA256.hash(data: waitBytes).map { String(format: "%02x", $0) }.joined()
        let waitPackage = FeaturePackageManifest.Package(id: "action.wait", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/wait")!, sha256: waitDigest, size: Int64(waitBytes.count))
        let readBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let readDigest = SHA256.hash(data: readBytes).map { String(format: "%02x", $0) }.joined()
        let readPackage = FeaturePackageManifest.Package(id: "action.readFile", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/readFile")!, sha256: readDigest, size: Int64(readBytes.count))
        let mutations = try zip(["writeFile", "appendFile", "createFolder", "copyFile", "moveFile", "trashFile"], CommandLine.arguments[4...9]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let controls = try zip(["adjustSound", "adjustBrightness"], CommandLine.arguments[10...11]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let clipBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[12]))
        let clipHash = SHA256.hash(data: clipBytes).map { String(format: "%02x", $0) }.joined()
        let clipPackage = FeaturePackageManifest.Package(id: "action.setClipboard", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/setClipboard")!, sha256: clipHash, size: Int64(clipBytes.count))
        let inputActions = try zip(["pressKey", "pasteClipboard", "typeText", "click", "movePointer", "scroll"], CommandLine.arguments[13...18]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let openActions = try zip(["openURL", "openApp", "composeMail"], CommandLine.arguments[19...21]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let screenActions = try zip(["screenPixel", "screenImage"], CommandLine.arguments[22...23]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let scriptActions = try zip(["shell", "appleScript"], CommandLine.arguments[24...25]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let dialogActions = try zip(["prompt", "choose", "message"], CommandLine.arguments[26...28]).map { name, path in
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return (FeaturePackageManifest.Package(id: "action." + name, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/" + name)!, sha256: hash, size: Int64(bytes.count)), bytes)
        }
        let windowBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[29]))
        let windowHash = SHA256.hash(data: windowBytes).map { String(format: "%02x", $0) }.joined()
        let windowPackage = FeaturePackageManifest.Package(id: "action.window", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/window")!, sha256: windowHash, size: Int64(windowBytes.count))
        let allPackages = mutations + controls + inputActions + openActions + screenActions + scriptActions + dialogActions + [(windowPackage, windowBytes)]
        let payload = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: [package, waitPackage, readPackage, clipPackage] + allPackages.map(\.0)))
        let envelope = try JSONSerialization.data(withJSONObject: ["payload": payload.base64EncodedString(), "signature": key.signature(for: payload).base64EncodedString()])
        StubProtocol.responses = ["/apps/autoproductive/features.json": envelope,
                                  "/apps/autoproductive/clipboard": bytes,
                                  "/apps/autoproductive/wait": waitBytes,
                                  "/apps/autoproductive/readFile": readBytes,
                                  "/apps/autoproductive/setClipboard": clipBytes]
        for (item, data) in allPackages { StubProtocol.responses[item.url.path] = data }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let repository = FeaturePackageRepository(manifestURL: URL(string: "https://nithi.land/apps/autoproductive/features.json")!,
            publicKey: key.publicKey, workingDirectory: root.appendingPathComponent("staging"), configuration: config)
        let installer = FeatureInstallationCoordinator(repository: repository, generations: generations)
        let allIDs = Set([package.id, waitPackage.id, readPackage.id, clipPackage.id] + allPackages.map { $0.0.id })
        do {
            try await installer.install(available: ["tool.notImplemented"], chosen: ["tool.notImplemented"], previous: nil)
            fatalError("Unimplemented feature must not be presented as installed")
        } catch FeatureInstallationCoordinator.InstallationError.componentNotImplemented {}
        let review = try await FeatureInstallationSession.begin(installer: installer, expected: allIDs, previous: nil)
        guard review.initiallySelected == allIDs, review.newFeatures.isEmpty,
              try review.downloadSize(for: allIDs) == ([package, waitPackage, readPackage, clipPackage] + allPackages.map(\.0)).reduce(0, { $0 + $1.size }) else {
            fatalError("Initial review must include every feature and its signed download size")
        }
        do { _ = try review.downloadSize(for: ["action.unknown"]); fatalError("Unknown selection must fail") }
        catch FeatureInstallationSession.SessionError.unknownChoice { }
        let olderSelection = FeatureSelectionState.migrateExisting(currentFeatureIDs: [waitPackage.id])
        let upgraded = try await FeatureInstallationSession.begin(installer: installer, expected: allIDs, previous: olderSelection)
        guard upgraded.initiallySelected == [waitPackage.id], upgraded.newFeatures == allIDs.subtracting([waitPackage.id]) else {
            fatalError("New features must be offered without selecting them automatically")
        }
        try await upgraded.refreshSelected()
        guard let refreshed = try generations.current()?.selection,
              refreshed.selected == [waitPackage.id], refreshed.newFeatures(in: allIDs) == allIDs.subtracting([waitPackage.id]) else {
            fatalError("Refreshing existing packages must preserve choices and leave new features for review")
        }
        do {
            _ = try await FeatureInstallationSession.begin(installer: installer, expected: allIDs.union(["action.unavailable"]), previous: nil)
            fatalError("Incomplete catalogue must not be shown as ready")
        } catch FeatureInstallationSession.SessionError.unavailable { }
        StubProtocol.responses["/apps/autoproductive/features.json"] = Data("changed after review".utf8)
        try await review.install(allIDs)
        StubProtocol.responses["/apps/autoproductive/features.json"] = envelope
        guard try generations.current()?.selection?.selected == allIDs else { fatalError("Selections and packages must activate together") }
        try FeatureComponentDispatcher.requireAction(id: "action.wait", title: "Wait", generations: generations)
        do {
            try FeatureComponentDispatcher.requireAction(id: "action.future", title: "Future action", generations: generations)
            fatalError("Unselected action should not run")
        } catch FeatureComponentDispatcher.DispatchError.missingComponent {}
        let result = try await FeatureComponentDispatcher.transformClipboard("z\na", using: "sortLines", generations: generations)
        guard result == "a\nz" else { fatalError("Installed action did not run") }
        let boardName = "land.nithi.autoproductive.test." + UUID().uuidString
        let board = NSPasteboard(name: NSPasteboard.Name(boardName))
        defer { board.releaseGlobally() }
        guard try await FeatureComponentDispatcher.setClipboard("Clipboard ✓", generations: generations, pasteboardName: boardName),
              board.string(forType: .string) == "Clipboard ✓" else { fatalError("Set clipboard component failed") }
        let keyPlan = try await FeatureComponentDispatcher.inputPlan(action: "pressKey", request: .init(keyCode: 12, modifiers: 3), generations: generations)
        guard keyPlan?.events.first?.keyCode == 12, keyPlan?.events.first?.modifiers == 3 else { fatalError("Key plan changed") }
        let pastePlan = try await FeatureComponentDispatcher.inputPlan(action: "pasteClipboard", request: .init(), generations: generations)
        guard pastePlan?.events.first?.keyCode == 9, pastePlan?.events.first?.modifiers == 1 else { fatalError("Paste plan changed") }
        let typePlan = try await FeatureComponentDispatcher.inputPlan(action: "typeText", request: .init(text: "A🙂"), generations: generations)
        guard typePlan?.events.map(\.text) == ["A🙂"] else { fatalError("Unicode plan changed") }
        let clickPlan = try await FeatureComponentDispatcher.inputPlan(action: "click", request: .init(x: 100, y: 200, button: "right", coordinatesInPixels: true, displayScale: 2, displayWidth: 800, displayHeight: 600), generations: generations)
        guard clickPlan?.events.first?.x == 50, clickPlan?.events.first?.y == 100, clickPlan?.events.first?.button == "right" else { fatalError("Pixel click plan changed") }
        let movePlan = try await FeatureComponentDispatcher.inputPlan(action: "movePointer", request: .init(x: 10, y: 20, button: "left"), generations: generations)
        guard movePlan?.events.first?.kind == "move" else { fatalError("Pointer plan changed") }
        let scrollPlan = try await FeatureComponentDispatcher.inputPlan(action: "scroll", request: .init(x: 20_000, y: -20_000), generations: generations)
        guard scrollPlan?.events.first?.x == 10_000, scrollPlan?.events.first?.y == -10_000 else { fatalError("Scroll clamp changed") }
        let web = try await FeatureComponentDispatcher.openTarget(action: "openURL", value: "https://example.com/test", generations: generations)
        guard web?.absoluteString == "https://example.com/test" else { fatalError("Website URL changed") }
        let application = try await FeatureComponentDispatcher.openTarget(action: "openApp", value: "/Applications/Test App.app", generations: generations)
        guard application?.path == "/Applications/Test App.app" else { fatalError("Application path changed") }
        let mail = try await FeatureComponentDispatcher.openTarget(action: "composeMail", value: "a@example.com", subject: "Hello ✓", body: "Line 1\nLine 2", generations: generations)
        let mailParts = mail.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        guard mailParts?.scheme == "mailto", mailParts?.queryItems?.first(where: { $0.name == "subject" })?.value == "Hello ✓" else { fatalError("Email draft changed") }
        do { _ = try await FeatureComponentDispatcher.openTarget(action: "openURL", value: "javascript:alert(1)", generations: generations); fatalError("Unsafe URL accepted") } catch FeatureComponentRunner.RunnerError.failed {}
        for action in ["screenPixel", "screenImage"] {
            let plan = try await FeatureComponentDispatcher.screenWaitPlan(action: action, duration: 5, generations: generations)
            guard plan?.duration == 5, plan?.pollInterval == 0.3 else { fatalError("Screen wait settings changed") }
        }
        let command = "printf '%s' \"$AUTOPRODUCTIVE_INPUT\""
        let shellPlan = try await FeatureComponentDispatcher.scriptPlan(action: "shell", script: command, generations: generations)
        guard shellPlan?.executable == "/bin/zsh", shellPlan?.arguments == ["-c", command] else { fatalError("Shell command changed") }
        let applePlan = try await FeatureComponentDispatcher.scriptPlan(action: "appleScript", script: "return 1", generations: generations)
        guard applePlan?.executable == "/usr/bin/osascript", applePlan?.arguments == ["-e", "return 1"] else { fatalError("AppleScript changed") }
        let message = try await FeatureComponentDispatcher.dialogPlan(action: "message", title: "Hello", details: "Details", generations: generations)
        guard message?.title == "Hello", message?.details == "Details", message?.choices.isEmpty == true else { fatalError("Message changed") }
        let choice = try await FeatureComponentDispatcher.dialogPlan(action: "choose", title: "", details: "One\nTwo", generations: generations)
        guard choice?.title == "AutoProductive", choice?.choices == ["One", "Two"] else { fatalError("Choice menu changed") }
        let prompt = try await FeatureComponentDispatcher.dialogPlan(action: "prompt", title: "Name?", details: "", generations: generations)
        guard prompt?.kind == "prompt", prompt?.choices.isEmpty == true else { fatalError("Prompt changed") }
        let windowRequest = FeatureComponentDispatcher.WindowRequest(option: "rightHalf", x: 0, y: 0, amount: 0, heightText: "", areaX: 100, areaY: 20, areaWidth: 1000, areaHeight: 800)
        let windowPlan = try await FeatureComponentDispatcher.windowPlan(request: windowRequest, generations: generations)
        guard windowPlan?.kind == "frame", windowPlan?.x == 600, windowPlan?.y == 20, windowPlan?.width == 500, windowPlan?.height == 800 else { fatalError("Window placement changed") }
        try await FeatureComponentDispatcher.wait(0.01, generations: generations)
        let textFile = root.appendingPathComponent("sample.txt")
        try "Text ✓".write(to: textFile, atomically: true, encoding: .utf8)
        let text = try await FeatureComponentDispatcher.readFile(textFile.path, generations: generations)
        guard text == "Text ✓" else { fatalError("Read file component did not return file text") }
        let folder = root.appendingPathComponent("nested/folder")
        guard try await FeatureComponentDispatcher.mutateFile(action: "createFolder", path: folder.path, text: "", generations: generations) else { fatalError("Create folder fell back") }
        let written = folder.appendingPathComponent("written.txt")
        guard try await FeatureComponentDispatcher.mutateFile(action: "writeFile", path: written.path, text: "A✓", generations: generations),
              try await FeatureComponentDispatcher.mutateFile(action: "appendFile", path: written.path, text: " B", generations: generations),
              try String(contentsOf: written, encoding: .utf8) == "A✓ B" else { fatalError("File mutation components failed") }
        let copied = folder.appendingPathComponent("copy.txt")
        let moved = folder.appendingPathComponent("moved.txt")
        guard try await FeatureComponentDispatcher.mutateFile(action: "copyFile", path: written.path, text: copied.path, generations: generations),
              try await FeatureComponentDispatcher.mutateFile(action: "moveFile", path: copied.path, text: moved.path, generations: generations),
              !FileManager.default.fileExists(atPath: copied.path),
              try String(contentsOf: moved, encoding: .utf8) == "A✓ B" else { fatalError("Copy or move components failed") }
        for name in ["adjustSound", "adjustBrightness"] {
            do {
                _ = try await FeatureComponentDispatcher.adjustSystem(action: name, option: "invalid", amount: 50, generations: generations)
                fatalError("Invalid system adjustment must fail without touching hardware")
            } catch FeatureComponentRunner.RunnerError.failed {}
        }
        let waiting = Task { try await FeatureComponentDispatcher.wait(30, generations: generations) }
        try await Task.sleep(for: .milliseconds(300))
        waiting.cancel()
        do { try await waiting.value; fatalError("Cancelled wait must stop") } catch is CancellationError {}
        let current = try generations.current()!
        try Data(repeating: 0, count: bytes.count).write(to: current.directory.appendingPathComponent(package.id + ".package"))
        do {
            _ = try await FeatureComponentDispatcher.transformClipboard("private", using: "uppercase", generations: generations)
            fatalError("Altered executable must not run or fall back")
        } catch FeaturePackageStore.StoreError.invalidContent {}
        let previous = try generations.current()?.selection
        let management = try await FeatureInstallationSession.begin(installer: installer, expected: allIDs, previous: previous)
        guard management.initiallySelected == allIDs, management.newFeatures.isEmpty else { fatalError("Existing feature choices must be restored") }
        try await installer.install(available: allIDs, chosen: [waitPackage.id], previous: previous)
        guard !FileManager.default.fileExists(atPath: current.directory.path) else { fatalError("Removed features must release the previous generation") }
        do {
            _ = try await FeatureComponentDispatcher.transformClipboard("private", using: "uppercase", generations: generations)
            fatalError("Removed action must not fall back to bundled code")
        } catch FeatureComponentDispatcher.DispatchError.missingComponent {}
        try await FeatureComponentDispatcher.wait(0.01, generations: generations)
        let inFlight = Task { try await FeatureComponentDispatcher.wait(0.75, generations: generations) }
        try await Task.sleep(for: .milliseconds(300))
        let beforeRemoval = try generations.current()!
        try await installer.install(available: allIDs, chosen: [], previous: beforeRemoval.selection)
        try await inFlight.value
        guard !FileManager.default.fileExists(atPath: beforeRemoval.directory.path) else { fatalError("Old generation was not removed") }
        do { try await FeatureComponentDispatcher.wait(0.01, generations: generations); fatalError("Deleted wait action still ran") }
        catch FeatureComponentDispatcher.DispatchError.missingComponent {}
        let stable = try generations.current()!
        let mislabeled = FeaturePackageManifest.Package(id: waitPackage.id, version: "2", url: waitPackage.url, sha256: digest, size: Int64(bytes.count))
        let badPayload = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: [mislabeled]))
        StubProtocol.responses["/apps/autoproductive/features.json"] = try JSONSerialization.data(withJSONObject: ["payload": badPayload.base64EncodedString(), "signature": key.signature(for: badPayload).base64EncodedString()])
        StubProtocol.responses["/apps/autoproductive/wait"] = bytes
        do {
            try await installer.install(available: [waitPackage.id], chosen: [waitPackage.id], previous: stable.selection)
            fatalError("Mislabeled component must not activate")
        } catch FeatureInstallationCoordinator.InstallationError.componentIncompatible {}
        guard try generations.current()?.directory.path == stable.directory.path else { fatalError("Failed self-test must retain previous generation") }
        print("Passed signed download, activation, dispatch, cancellation, tamper rejection, and removal checks.")
    }
}
