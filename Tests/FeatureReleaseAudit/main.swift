import CryptoKit
import Darwin
import Foundation

@main struct Tests {
    struct SelfTest: Decodable { let feature: String; let api: Int }
    static func main() async throws {
        if let result = FeatureToolValidation.runIfRequested() { exit(result) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let info = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as! [String: Any]
        guard let encoded = plist["SUPublicEDKey"] as? String, let keyBytes = Data(base64Encoded: encoded) else { fatalError("Missing public key") }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
        let version = CommandLine.arguments[3]
        let architecture = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : nil
        let suffix = architecture.map { "/\($0)" } ?? ""
        let catalogue = try FeaturePackageManifest.verify(Data(contentsOf: root.appendingPathComponent("releases/\(version)\(suffix)/features.json")), publicKey: key)
        let expected = FeatureComponentSupport.actionIDs.union(FeatureComponentSupport.toolIDs)
        guard Set(catalogue.packages.map(\.id)) == expected, catalogue.packages.allSatisfy({ $0.version == version }) else { fatalError("Release catalogue is incomplete or for another version") }
        for item in catalogue.packages {
            let local = root.appendingPathComponent("packages/\(item.version)\(suffix)/\(item.id).package")
            let bytes = try Data(contentsOf: local)
            guard FeaturePackageManifest.verifyPackage(bytes, matches: item) else { fatalError("Package digest or size failed") }
            if item.id.hasPrefix("tool.") {
                try await FeatureToolValidation.validate(bytes: bytes, id: item.id)
            } else {
                let result = try await FeatureComponentRunner.runVerified(executable: bytes, request: Data(#"{"selfTest":true}"#.utf8), timeout: 10, maximumOutputSize: 4096)
                let response = try JSONDecoder().decode(SelfTest.self, from: result)
                guard response.api == 1, response.feature == item.id else { fatalError("Package identity failed") }
            }
        }
        print("Passed signed release catalogue, package hashes and compatibility checks for \(catalogue.packages.count) components.")
    }
}
