import CryptoKit
import Foundation

/// Downloads a selection into an isolated staging directory. A caller must
/// validate and activate the executable components before treating this as an
/// installation; staging alone does not change installed features.
struct FeaturePackageRepository {
    enum RepositoryError: LocalizedError {
        case duplicateID, missingPackage(String), incompatibleRelease
        var errorDescription: String? {
            switch self {
            case .duplicateID: "The feature catalogue has duplicate entries."
            case .missingPackage: "A selected feature is unavailable."
            case .incompatibleRelease: "The feature catalogue does not match this app version."
            }
        }
    }
    struct PreparedPackages {
        let directory: URL
        let packages: [FeaturePackageManifest.Package]
        let signedManifest: Data
    }

    let manifestURL: URL
    let publicKey: Curve25519.Signing.PublicKey
    let workingDirectory: URL
    var configuration: URLSessionConfiguration = .ephemeral
    var requiredVersion: String? = nil
    var requiredArchitecture: String? = nil

    private func verifiedCatalogue(_ envelope: Data) throws -> FeaturePackageManifest {
        let manifest = try FeaturePackageManifest.verify(envelope, publicKey: publicKey)
        if let version = requiredVersion {
            let prefix = "/apps/autoproductive/packages/\(version)/" + (requiredArchitecture.map { $0 + "/" } ?? "")
            guard manifest.packages.allSatisfy({ $0.version == version && $0.url.path.hasPrefix(prefix) }) else {
                throw RepositoryError.incompatibleRelease
            }
        }
        return manifest
    }

    /// Return the verified catalogue together with the exact signed bytes, so
    /// an installation can use the same release that the person reviewed.
    func catalogue() async throws -> (manifest: FeaturePackageManifest, signedManifest: Data) {
        let envelope = try await FeaturePackageDownloader.fetch(manifestURL, maximumBytes: 1_000_000, configuration: configuration)
        let manifest = try verifiedCatalogue(envelope)
        return (manifest, envelope)
    }

    func prepare(ids: Set<String>, reviewedManifest: Data? = nil) async throws -> PreparedPackages {
        let envelope: Data
        if let reviewedManifest {
            envelope = reviewedManifest
        } else {
            envelope = try await catalogue().signedManifest
        }
        // Even a caller-supplied snapshot is verified before its URLs or hashes
        // are trusted. An altered or untrusted snapshot cannot install anything.
        let manifest = try verifiedCatalogue(envelope)
        let byID = Dictionary(uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) })
        let packages = try ids.sorted().map { id in
            guard let package = byID[id] else { throw RepositoryError.missingPackage(id) }
            return package
        }
        let staging = workingDirectory.appendingPathComponent("staging-" + UUID().uuidString, isDirectory: true)
        let store = FeaturePackageStore(directory: staging)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for package in packages {
                try Task.checkCancellation()
                let bytes = try await FeaturePackageDownloader.fetch(package.url, maximumBytes: Int(package.size),
                    expectedSize: Int(package.size), configuration: configuration)
                try store.stage(bytes, package: package)
            }
            return PreparedPackages(directory: staging, packages: packages, signedManifest: envelope)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
