import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
func envelope(_ manifest: FeaturePackageManifest, signingKey: Curve25519.Signing.PrivateKey = key) throws -> Data {
    let payload = try JSONEncoder().encode(manifest)
    let signature = try signingKey.signature(for: payload)
    return try JSONSerialization.data(withJSONObject: ["payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()])
}
let file = Data("sample package".utf8)
let hash = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
func package(_ id: String = "tool.keepAwake", url: String = "https://nithi.land/apps/autoproductive/test.zip", size: Int64 = Int64(file.count), sha: String? = nil) -> FeaturePackageManifest.Package {
    .init(id: id, version: "1", url: URL(string: url)!, sha256: sha ?? hash, size: size)
}
let good = FeaturePackageManifest(format: 1, packages: [package()])
let signed = try envelope(good)
let verified = try FeaturePackageManifest.verify(signed, publicKey: key.publicKey)
check(verified.packages.count == 1, "Valid signed manifest accepted")
check(FeaturePackageManifest.verifyPackage(file, matches: verified.packages[0]), "Matching package accepted")
check(!FeaturePackageManifest.verifyPackage(Data("sample packagE".utf8), matches: verified.packages[0]), "Altered content rejected")
check(!FeaturePackageManifest.verifyPackage(file + Data([0]), matches: verified.packages[0]), "Wrong length rejected")
check((try? FeaturePackageManifest.verify(signed, publicKey: Curve25519.Signing.PrivateKey().publicKey)) == nil, "Wrong signing key rejected")
let badHost = FeaturePackageManifest(format: 1, packages: [package(url: "https://example.com/apps/autoproductive/test.zip")])
check((try? FeaturePackageManifest.verify(envelope(badHost), publicKey: key.publicKey)) == nil, "Untrusted host rejected")
let duplicate = FeaturePackageManifest(format: 1, packages: [package(), package()])
check((try? FeaturePackageManifest.verify(envelope(duplicate), publicKey: key.publicKey)) == nil, "Duplicate package IDs rejected")
let wrongHash = FeaturePackageManifest(format: 1, packages: [package(sha: "not-a-hash")])
check((try? FeaturePackageManifest.verify(envelope(wrongHash), publicKey: key.publicKey)) == nil, "Invalid digest rejected")
let oversized = FeaturePackageManifest(format: 1, packages: [package(size: 513 * 1024 * 1024)])
check((try? FeaturePackageManifest.verify(envelope(oversized), publicKey: key.publicKey)) == nil, "Oversized package rejected")
let traversal = FeaturePackageManifest(format: 1, packages: [package(url: "https://nithi.land/apps/autoproductive/%2e%2e/escape")])
check((try? FeaturePackageManifest.verify(envelope(traversal), publicKey: key.publicKey)) == nil, "Encoded path traversal rejected")
print("Passed \(checks) signed feature manifest checks.")
