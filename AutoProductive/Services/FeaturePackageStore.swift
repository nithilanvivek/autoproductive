import Foundation

/// Holds verified package bytes separately from the application bundle. The
/// package installer must not mark a feature usable until it has also installed
/// and validated the feature's actual executable component.
struct FeaturePackageStore {
    enum StoreError: Error {
        case invalidIdentifier, invalidContent, notRegularFile
    }

    let directory: URL
    private let files = FileManager.default

    private func packageURL(id: String) throws -> URL {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, ["tool", "action"].contains(String(parts[0])),
              !parts[1].isEmpty, parts[1].count <= 80,
              parts[1].unicodeScalars.allSatisfy({
                  $0.isASCII && CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).contains($0)
              }) else { throw StoreError.invalidIdentifier }
        return directory.appendingPathComponent(id + ".package", isDirectory: false)
    }

    /// Writes atomically so a failed download or verification never destroys a
    /// previously verified copy. Call only with metadata from a signed manifest.
    func stage(_ bytes: Data, package: FeaturePackageManifest.Package) throws {
        let url = try packageURL(id: package.id)
        guard FeaturePackageManifest.verifyPackage(bytes, matches: package) else { throw StoreError.invalidContent }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: url, options: [.atomic])
    }

    /// Verify again when reading because files may have changed after download.
    func verifiedBytes(for package: FeaturePackageManifest.Package) throws -> Data {
        let url = try packageURL(id: package.id)
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StoreError.notRegularFile }
        guard (attributes[.size] as? NSNumber)?.int64Value == package.size else { throw StoreError.invalidContent }
        // Keep a private snapshot: a memory-mapped file could change after its
        // hash is checked but before its bytes are executed.
        let bytes = try Data(contentsOf: url)
        guard FeaturePackageManifest.verifyPackage(bytes, matches: package) else { throw StoreError.invalidContent }
        return bytes
    }

    func remove(id: String) throws {
        let url = try packageURL(id: id)
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }
}
