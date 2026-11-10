import CryptoKit
import Foundation

/// Production locations are kept in one place so setup, management and action
/// dispatch use the same trusted key and the same local feature generation.
struct FeatureInstallationEnvironment {
    enum ConfigurationError: LocalizedError {
        case missingSigningKey, invalidVersion, unsupportedArchitecture
        var errorDescription: String? {
            switch self {
            case .missingSigningKey: "The feature signing key is unavailable."
            case .invalidVersion: "The app version is unavailable for feature installation."
            case .unsupportedArchitecture: "This Mac's processor is not supported."
            }
        }
    }

    let installer: FeatureInstallationCoordinator
    let componentVersion: String

    static func live(bundle: Bundle = .main, fileManager: FileManager = .default) throws -> Self {
        guard let encoded = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bytes = Data(base64Encoded: encoded),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes) else {
            throw ConfigurationError.missingSigningKey
        }
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty, version.count <= 80, version != ".", version != "..",
              version.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._")).contains($0) }) else {
            throw ConfigurationError.invalidVersion
        }
        let architecture = FeatureArchitecture.current
        let componentVersion = FeatureComponentSupport.componentVersion(for: version)
        guard ["arm64", "x86_64"].contains(architecture) else { throw ConfigurationError.unsupportedArchitecture }
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            .appendingPathComponent(FeatureComponentSupport.supportDirectoryName, isDirectory: true)
        let generations = FeaturePackageGenerations(root: support.appendingPathComponent("Features", isDirectory: true),
                                                     publicKey: publicKey)
        let repository = FeaturePackageRepository(
            manifestURL: URL(string: "https://nithi.land/apps/autoproductive/releases/\(componentVersion)/\(architecture)/features.json")!,
            publicKey: publicKey, workingDirectory: support.appendingPathComponent("Feature Staging", isDirectory: true), requiredVersion: componentVersion, requiredArchitecture: architecture)
        return Self(installer: FeatureInstallationCoordinator(repository: repository, generations: generations), componentVersion: componentVersion)
    }

    func currentSelection() throws -> FeatureSelectionState? {
        try installer.generations.current()?.selection
    }
}
