import CryptoKit
import Foundation

/// The signed bytes are verified before they are decoded or used to select a
/// package. Release keys belong outside the repository; only a public key is
/// embedded in a shipping app.
struct SignedFeatureManifest: Decodable {
    let payload: String
    let signature: String
}

struct FeaturePackageManifest: Codable {
    struct Package: Codable {
        let id: String
        let version: String
        let url: URL
        let sha256: String
        let size: Int64
    }

    let format: Int
    let packages: [Package]

    enum ManifestError: Error {
        case invalidEnvelope, invalidSignature, unsupportedFormat, invalidPackage
    }

    static func verify(_ data: Data, publicKey: Curve25519.Signing.PublicKey) throws -> FeaturePackageManifest {
        guard data.count <= 1_000_000,
              let envelope = try? JSONDecoder().decode(SignedFeatureManifest.self, from: data),
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              payload.count <= 700_000 else { throw ManifestError.invalidEnvelope }
        guard publicKey.isValidSignature(signature, for: payload) else { throw ManifestError.invalidSignature }
        let manifest = try JSONDecoder().decode(Self.self, from: payload)
        guard manifest.format == 1 else { throw ManifestError.unsupportedFormat }
        guard manifest.packages.count <= 256 else { throw ManifestError.invalidPackage }
        var ids = Set<String>()
        for package in manifest.packages {
            let parts = package.id.split(separator: ".", omittingEmptySubsequences: false)
            let path = URLComponents(url: package.url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
            guard parts.count == 2, ["tool", "action"].contains(String(parts[0])),
                  !parts[1].isEmpty, parts[1].count <= 80,
                  parts[1].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).contains($0) && $0.isASCII }),
                  ids.insert(package.id).inserted,
                  !package.version.isEmpty, package.version.count <= 80,
                  package.url.scheme?.lowercased() == "https", package.url.host?.lowercased() == "nithi.land",
                  package.url.port == nil, package.url.user == nil, package.url.password == nil,
                  package.url.query == nil, package.url.fragment == nil,
                  path.hasPrefix("/apps/autoproductive/"),
                  path.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/")).contains($0) }),
                  !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }),
                  package.size > 0, package.size <= 512 * 1024 * 1024,
                  package.sha256.count == 64,
                  package.sha256.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }) else {
                throw ManifestError.invalidPackage
            }
        }
        return manifest
    }

    static func verifyPackage(_ data: Data, matches package: Package) -> Bool {
        guard data.count == package.size else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == package.sha256
    }
}
