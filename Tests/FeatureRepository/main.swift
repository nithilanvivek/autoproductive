import CryptoKit
import Foundation

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
        let payloadBytes = Data("feature contents".utf8)
        let digest = SHA256.hash(data: payloadBytes).map { String(format: "%02x", $0) }.joined()
        let package = FeaturePackageManifest.Package(id: "tool.keepAwake", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/keepAwake.pkg")!, sha256: digest, size: Int64(payloadBytes.count))
        let manifest = FeaturePackageManifest(format: 1, packages: [package])
        let data = try JSONEncoder().encode(manifest)
        let envelope = try JSONSerialization.data(withJSONObject: ["payload": data.base64EncodedString(), "signature": key.signature(for: data).base64EncodedString()])
        StubProtocol.responses = ["/apps/autoproductive/features.json": envelope, "/apps/autoproductive/keepAwake.pkg": payloadBytes]
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let repo = FeaturePackageRepository(manifestURL: URL(string: "https://nithi.land/apps/autoproductive/features.json")!, publicKey: key.publicKey, workingDirectory: root, configuration: config)
        let reviewed = try await repo.catalogue()
        guard reviewed.manifest.packages.first?.size == Int64(payloadBytes.count) else { fatalError("Reviewed size must be signed") }
        var restricted = repo
        restricted.requiredVersion = "2"
        do { _ = try await restricted.catalogue(); fatalError("A different app version's catalogue must be rejected") }
        catch FeaturePackageRepository.RepositoryError.incompatibleRelease { }
        let result = try await repo.prepare(ids: ["tool.keepAwake"])
        let actual = try FeaturePackageStore(directory: result.directory).verifiedBytes(for: package)
        guard actual == payloadBytes else { fatalError("Signed selected package should be staged") }
        StubProtocol.responses["/apps/autoproductive/features.json"] = Data("changed".utf8)
        let reviewedResult = try await repo.prepare(ids: [package.id], reviewedManifest: reviewed.signedManifest)
        guard reviewedResult.signedManifest == envelope else { fatalError("Install must use the reviewed catalogue") }
        try FileManager.default.removeItem(at: reviewedResult.directory)
        do { _ = try await repo.prepare(ids: [package.id], reviewedManifest: Data("invalid".utf8)); fatalError("An invalid reviewed catalogue must fail") } catch FeaturePackageManifest.ManifestError.invalidEnvelope { }
        StubProtocol.responses["/apps/autoproductive/features.json"] = envelope
        do { _ = try await repo.prepare(ids: ["tool.nonexistent"]); fatalError("Missing packages must fail") } catch FeaturePackageRepository.RepositoryError.missingPackage {}
        StubProtocol.responses["/apps/autoproductive/keepAwake.pkg"] = Data(repeating: 0, count: payloadBytes.count)
        do { _ = try await repo.prepare(ids: ["tool.keepAwake"]); fatalError("Corrupt data must fail") } catch FeaturePackageStore.StoreError.invalidContent {}
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard remaining.count == 1, remaining[0].standardizedFileURL.path == result.directory.standardizedFileURL.path else { fatalError("Failure must remove temporary staging") }
        print("Passed feature repository selection, verification and cleanup checks.")
    }
}
