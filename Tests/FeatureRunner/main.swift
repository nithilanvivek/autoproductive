import CryptoKit
import Foundation

@main struct Tests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let package = FeaturePackageManifest.Package(id: "action.transformClipboard", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/clipboard")!, sha256: hash, size: Int64(bytes.count))
        let store = FeaturePackageStore(directory: root)
        try store.stage(bytes, package: package)
        let request = try JSONSerialization.data(withJSONObject: ["text": "Straße", "operation": "uppercase"])
        let output = try await FeatureComponentRunner.run(package: package, store: store, request: request)
        let result = try JSONSerialization.jsonObject(with: output) as! [String: String]
        guard result["text"] == "STRASSE" else { fatalError("Component response was incorrect") }
        try Data(repeating: 0, count: bytes.count).write(to: root.appendingPathComponent("action.transformClipboard.package"))
        do {
            _ = try await FeatureComponentRunner.run(package: package, store: store, request: request)
            fatalError("Altered component must not run")
        } catch FeaturePackageStore.StoreError.invalidContent {}
        print("Passed hardened host component execution and altered-package checks.")
    }
}
