import CryptoKit
import Darwin
import Foundation

final class ReleaseStub: URLProtocol {
    static var responses: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let data = Self.responses[url.path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Tests {
    static func main() async throws {
        if let result = FeatureToolValidation.runIfRequested() { exit(result) }
        guard FeatureComponentSupport.componentVersion(for: "1.3-test") == "1.1",
              FeatureComponentSupport.componentVersion(for: "1.4-test") == "1.1",
              FeatureComponentSupport.componentVersion(for: "1.5-test") == "1.1",
              FeatureComponentSupport.componentVersion(for: "1.7-test") == "1.6-test",
              FeatureComponentSupport.componentVersion(for: "1.0") == "1.0-release",
              FeatureComponentSupport.componentVersion(for: "1.2") == "1.2",
              FeatureComponentSupport.componentVersion(for: "1.3") == "1.3" else {
            fatalError("Test-only component version mapping is incorrect")
        }
        let release = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let version = CommandLine.arguments[2]
        let architecture = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : nil
        let suffix = architecture.map { "/\($0)" } ?? ""
        let plistData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: plist["SUPublicEDKey"] as! String)!)
        let envelope = try Data(contentsOf: release.appendingPathComponent("releases/\(version)\(suffix)/features.json"))
        let manifest = try FeaturePackageManifest.verify(envelope, publicKey: key)
        let manifestURL = URL(string: "https://nithi.land/apps/autoproductive/releases/\(version)\(suffix)/features.json")!
        ReleaseStub.responses[manifestURL.path] = envelope
        for package in manifest.packages {
            ReleaseStub.responses[package.url.path] = try Data(contentsOf: release.appendingPathComponent("packages/\(version)\(suffix)/\(package.id).package"))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        if ProcessInfo.processInfo.environment["AUTOPRODUCTIVE_TEST_LIVE_RELEASE"] != "1" {
            config.protocolClasses = [ReleaseStub.self]
        }
        let repository = FeaturePackageRepository(manifestURL: manifestURL, publicKey: key,
            workingDirectory: root.appendingPathComponent("staging"), configuration: config, requiredVersion: version, requiredArchitecture: architecture)
        let generations = FeaturePackageGenerations(root: root.appendingPathComponent("features"), publicKey: key)
        let installer = FeatureInstallationCoordinator(repository: repository, generations: generations)
        let expected = FeatureComponentSupport.actionIDs.union(FeatureComponentSupport.toolIDs)
        let setup = try await FeatureInstallationSession.begin(installer: installer, expected: expected, previous: nil)
        let initialSelection: Set<String> = ["action.wait", "tool.finderCut"]
        try await setup.install(initialSelection)
        guard let initial = try generations.current(), initial.selection?.selected == initialSelection,
              Set(initial.packages.map(\.id)) == initialSelection else {
            fatalError("Fresh installation included unselected features")
        }
        let installAll = try await FeatureInstallationSession.begin(installer: installer, expected: expected, previous: initial.selection)
        try await installAll.install(expected)
        guard let all = try generations.current(), all.selection?.selected == expected else { fatalError("Full installation failed") }
        guard try await FeatureComponentDispatcher.transformClipboard("z\na", using: "sortLines", generations: generations) == "a\nz" else {
            fatalError("Installed clipboard action failed")
        }
        try await FeatureComponentDispatcher.wait(0.01, generations: generations)
        let keep: Set<String> = ["action.wait", "tool.finderCut"]
        let management = try await FeatureInstallationSession.begin(installer: installer, expected: expected, previous: all.selection)
        try await management.install(keep)
        guard let reduced = try generations.current(), reduced.selection?.selected == keep,
              Set(reduced.packages.map(\.id)) == keep, !FileManager.default.fileExists(atPath: all.directory.path) else {
            fatalError("Removing unselected packages failed")
        }
        print("Passed real \(version) catalogue installation, action execution and feature removal in isolated storage.")
    }
}
