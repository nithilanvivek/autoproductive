import CryptoKit
import Foundation

@main struct Tests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("valid feature".utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let package = FeaturePackageManifest.Package(id: "tool.keepAwake", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/keepAwake")!, sha256: hash, size: Int64(data.count))
        let manifest = try JSONEncoder().encode(FeaturePackageManifest(format: 1, packages: [package]))
        let envelope = try JSONSerialization.data(withJSONObject: ["payload": manifest.base64EncodedString(), "signature": key.signature(for: manifest).base64EncodedString()])
        let store = FeaturePackageGenerations(root: root.appendingPathComponent("published"), publicKey: key.publicKey)
        let staging = root.appendingPathComponent("stage")
        try FeaturePackageStore(directory: staging).stage(data, package: package)
        let choice = try FeatureSelectionState.newInstallation(available: [package.id, "action.wait"], selected: [package.id])
        try store.publish(.init(directory: staging, packages: [package], signedManifest: envelope), selection: choice)
        guard let initial = try store.current(), initial.packages.map(\.id) == [package.id],
              initial.selection == choice,
              try FeaturePackageStore(directory: initial.directory).verifiedBytes(for: package) == data else { fatalError("Published generation missing") }
        let badStage = root.appendingPathComponent("bad-stage")
        try FeaturePackageStore(directory: badStage).stage(data, package: package)
        let wrongChoice = try FeatureSelectionState.newInstallation(available: [package.id], selected: [])
        do { try store.publish(.init(directory: badStage, packages: [package], signedManifest: envelope), selection: wrongChoice); fatalError("Mismatched selection accepted") } catch FeaturePackageGenerations.GenerationError.invalidSelection {}
        try Data(repeating: 0, count: data.count).write(to: badStage.appendingPathComponent(package.id + ".package"))
        do { try store.publish(.init(directory: badStage, packages: [package], signedManifest: envelope)); fatalError("Corrupt generation accepted") } catch FeaturePackageStore.StoreError.invalidContent {}
        guard let afterFailure = try store.current(), afterFailure.directory.path == initial.directory.path else { fatalError("Failed publication replaced working generation") }
        let nextStage = root.appendingPathComponent("next-stage")
        try FeaturePackageStore(directory: nextStage).stage(data, package: package)
        try store.publish(.init(directory: nextStage, packages: [package], signedManifest: envelope), selection: choice)
        let unrelated = store.root.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        guard try store.discardSupersededGenerations() == 1,
              !FileManager.default.fileExists(atPath: initial.directory.path),
              FileManager.default.fileExists(atPath: unrelated.path),
              try store.current() != nil else { fatalError("Cleanup must remove only the superseded generation") }
        let pointer = store.root.appendingPathComponent("current.json")
        try Data(#"{"generation":"generation-../../escape","ids":[]}"#.utf8).write(to: pointer)
        do { _ = try store.current(); fatalError("Unsafe pointer accepted") } catch FeaturePackageGenerations.GenerationError.invalidPointer {}
        print("Passed verified generation, atomic replacement and pointer checks.")
    }
}
