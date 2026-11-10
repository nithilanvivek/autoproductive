import CryptoKit
import Foundation

@main struct Tests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let hash = SHA256.hash(data: libraryBytes).map { String(format: "%02x", $0) }.joined()
        let package = FeaturePackageManifest.Package(id: "tool.example", version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/tool")!, sha256: hash, size: Int64(libraryBytes.count))
        let store = FeaturePackageStore(directory: root)
        try store.stage(libraryBytes, package: package)
        let tool = try FeatureToolLibrary(verifiedBytes: store.verifiedBytes(for: package))
        typealias Function = @convention(c) () -> Int32
        let function = unsafeBitCast(try tool.symbol("autoproductive_test_value"), to: Function.self)
        guard function() == 42 else { fatalError("Signed tool did not execute") }
        do { _ = try tool.symbol("unknown_function"); fatalError("Missing symbols must fail") } catch FeatureToolLibrary.LoadError.missingSymbol {}
        let unmatched = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        do { _ = try FeatureToolLibrary(verifiedBytes: unmatched); fatalError("A different signing team must fail library validation") } catch FeatureToolLibrary.LoadError.invalidLibrary {}
        print("Passed verified tool loading and hardened library-validation checks.")
    }
}
