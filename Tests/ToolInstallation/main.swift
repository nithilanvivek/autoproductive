import CryptoKit
import Darwin
import Foundation

final class StubProtocol: URLProtocol {
    static var responses: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let data = Self.responses[url.path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Tests {
    static func main() async throws {
        if let result = FeatureToolValidation.runIfRequested() { exit(result) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = ["tool.finderCut", "tool.fileBucket", "tool.keepAwake", "tool.audioMixer", "tool.dockPreviews"]
        precondition(CommandLine.arguments.count == ids.count + 1)
        let key = Curve25519.Signing.PrivateKey()
        var packages: [FeaturePackageManifest.Package] = []
        for (id, path) in zip(ids, CommandLine.arguments.dropFirst()) {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let url = URL(string: "https://nithi.land/apps/autoproductive/\(id)")!
            packages.append(.init(id: id, version: "1", url: url, sha256: hash, size: Int64(bytes.count)))
            StubProtocol.responses[url.path] = bytes
        }
        let payload = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: packages))
        StubProtocol.responses["/apps/autoproductive/features.json"] = try JSONSerialization.data(withJSONObject: [
            "payload": payload.base64EncodedString(), "signature": key.signature(for: payload).base64EncodedString()])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let repository = FeaturePackageRepository(manifestURL: URL(string: "https://nithi.land/apps/autoproductive/features.json")!,
            publicKey: key.publicKey, workingDirectory: root.appendingPathComponent("staging"), configuration: config)
        let generations = FeaturePackageGenerations(root: root.appendingPathComponent("features"), publicKey: key.publicKey)
        let installer = FeatureInstallationCoordinator(repository: repository, generations: generations)
        try await installer.install(available: Set(ids), chosen: Set(ids), previous: nil)
        guard let first = try generations.current(), Set(first.packages.map(\.id)) == Set(ids), first.selection?.selected == Set(ids) else {
            fatalError("All signed tools must be installed")
        }
        try await installer.install(available: Set(ids), chosen: [], previous: first.selection)
        guard let removed = try generations.current(), removed.packages.isEmpty,
              !FileManager.default.fileExists(atPath: first.directory.path) else {
            fatalError("Removing tools must delete their old package generation")
        }
        print("Passed isolated installation and removal of all five signed tool components.")
    }
}
