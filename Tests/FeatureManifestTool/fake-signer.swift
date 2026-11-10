import CryptoKit
import Foundation

@main struct FakeSigner {
    static func main() throws {
        guard let keyPath = ProcessInfo.processInfo.environment["AUTOPRODUCTIVE_TEST_KEY_PATH"] else { exit(2) }
        let keyURL = URL(fileURLWithPath: keyPath)
        if CommandLine.arguments.last == "--make-key" {
            let key = Curve25519.Signing.PrivateKey()
            try key.rawRepresentation.write(to: keyURL, options: [.atomic])
            print(key.publicKey.rawRepresentation.base64EncodedString())
        } else {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
            let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments.last!))
            print(try key.signature(for: bytes).base64EncodedString())
        }
    }
}
