import Foundation
import CryptoKit
import Darwin

final class StubProtocol: URLProtocol {
    static var responses: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let data = Self.responses[url.path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Tests {
    @MainActor static func main() async throws {
        if let result = FeatureToolValidation.runIfRequested() { exit(result) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let key = Curve25519.Signing.PrivateKey()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let package = FeaturePackageManifest.Package(id: "tool.finderCut", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/finderCut")!, sha256: digest, size: Int64(bytes.count))
        let payload = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: [package]))
        let envelope = try JSONSerialization.data(withJSONObject: ["payload": payload.base64EncodedString(), "signature": key.signature(for: payload).base64EncodedString()])
        StubProtocol.responses = ["/apps/autoproductive/features.json": envelope, "/apps/autoproductive/finderCut": bytes]
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let generations = FeaturePackageGenerations(root: root.appendingPathComponent("features"), publicKey: key.publicKey)
        let repository = FeaturePackageRepository(manifestURL: URL(string: "https://nithi.land/apps/autoproductive/features.json")!, publicKey: key.publicKey, workingDirectory: root.appendingPathComponent("staging"), configuration: config)
        let incomplete = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let incompleteDigest = SHA256.hash(data: incomplete).map { String(format: "%02x", $0) }.joined()
        let incompletePackage = FeaturePackageManifest.Package(id: package.id, version: "2", url: package.url, sha256: incompleteDigest, size: Int64(incomplete.count))
        let incompletePayload = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: [incompletePackage]))
        let incompleteEnvelope = try JSONSerialization.data(withJSONObject: ["payload": incompletePayload.base64EncodedString(), "signature": key.signature(for: incompletePayload).base64EncodedString()])
        StubProtocol.responses = ["/apps/autoproductive/features.json": incompleteEnvelope, "/apps/autoproductive/finderCut": incomplete]
        do {
            try await FeatureInstallationCoordinator(repository: repository, generations: generations).install(available: [package.id], chosen: [package.id], previous: nil)
            fatalError("Incomplete tool was installed")
        } catch FeatureInstallationCoordinator.InstallationError.componentIncompatible { }
        guard try generations.current() == nil else { fatalError("Invalid tool must not create a generation") }
        StubProtocol.responses = ["/apps/autoproductive/features.json": envelope, "/apps/autoproductive/finderCut": bytes]
        try await FeatureInstallationCoordinator(repository: repository, generations: generations).install(available: [package.id], chosen: [package.id], previous: nil)
        let installed = try FeatureComponentDispatcher.toolBytes(id: package.id, generations: generations)!
        let tool = try FeatureFinderCut(verifiedBytes: installed)
        guard tool.decide(key: 7, changeCount: 0, hasFiles: false) == 1, !tool.hasPendingCut else { fatalError("Cut should start a copy") }
        tool.mark(changeCount: 4, hasFiles: true)
        guard tool.hasPendingCut, !tool.matches(changeCount: 5), tool.matches(changeCount: 4), tool.decide(key: 9, changeCount: 4, hasFiles: true) == 2,
              !tool.hasPendingCut, tool.decide(key: 9, changeCount: 4, hasFiles: true) == 0 else { fatalError("Matching paste should move once") }
        tool.mark(changeCount: 4, hasFiles: true)
        guard tool.decide(key: 9, changeCount: 5, hasFiles: true) == 0 else { fatalError("Changed clipboard must not move") }
        _ = tool.decide(key: 8, changeCount: 5, hasFiles: false)
        guard !tool.hasPendingCut else { fatalError("Copy clears pending cut") }
        tool.mark(changeCount: 4, hasFiles: false)
        guard !tool.hasPendingCut else { fatalError("Non-file clipboard must not be marked") }
        tool.mark(changeCount: 7, hasFiles: true); tool.reset()
        guard !tool.hasPendingCut else { fatalError("Stopping listener clears state") }
        let updated = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let updatedDigest = SHA256.hash(data: updated).map { String(format: "%02x", $0) }.joined()
        let updatedPackage = FeaturePackageManifest.Package(id: package.id, version: "2", url: package.url, sha256: updatedDigest, size: Int64(updated.count))
        let updatedPayload = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: [updatedPackage]))
        let updatedEnvelope = try JSONSerialization.data(withJSONObject: ["payload": updatedPayload.base64EncodedString(), "signature": key.signature(for: updatedPayload).base64EncodedString()])
        StubProtocol.responses = ["/apps/autoproductive/features.json": updatedEnvelope, "/apps/autoproductive/finderCut": updated]
        let previous = try generations.current()?.selection
        try await FeatureInstallationCoordinator(repository: repository, generations: generations).install(available: [package.id], chosen: [package.id], previous: previous)
        guard try FeatureComponentDispatcher.toolBytes(id: package.id, generations: generations) == updated else { fatalError("New version was not installed") }
        do { _ = try FeatureFinderCut(verifiedBytes: updated); fatalError("Do not load two versions in one process") }
        catch FeatureToolLibrary.LoadError.restartRequired { }
        StubProtocol.responses = ["/apps/autoproductive/features.json": incompleteEnvelope, "/apps/autoproductive/finderCut": incomplete]
        do {
            try await FeatureInstallationCoordinator(repository: repository, generations: generations).install(available: [package.id], chosen: [package.id], previous: nil)
            fatalError("Incomplete tool was installed")
        } catch FeatureInstallationCoordinator.InstallationError.componentIncompatible { }
        guard try FeatureComponentDispatcher.toolBytes(id: package.id, generations: generations) == updated else { fatalError("Failed install replaced working tool") }
        print("Passed signed Finder Command-X state checks without sending input.")
    }
}
