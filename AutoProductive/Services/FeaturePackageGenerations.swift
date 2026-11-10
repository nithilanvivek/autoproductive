import CryptoKit
import Foundation

/// Publishes verified package generations atomically. Activation of a package
/// as a usable app feature is a separate step from publishing these bytes.
struct FeaturePackageGenerations {
    private static let lock = NSRecursiveLock()
    enum GenerationError: Error { case invalidSelection, invalidPointer }
    private struct Pointer: Codable {
        let generation: String
        let ids: [String]
        let selection: FeatureSelectionState?
    }
    struct Current {
        let directory: URL
        let packages: [FeaturePackageManifest.Package]
        let selection: FeatureSelectionState?
    }
    enum ComponentLookup {
        case legacy
        case missing
        case verified(Data)
    }

    let root: URL
    let publicKey: Curve25519.Signing.PublicKey
    private let files = FileManager.default

    func publish(_ prepared: FeaturePackageRepository.PreparedPackages, selection: FeatureSelectionState? = nil) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let signed = try FeaturePackageManifest.verify(prepared.signedManifest, publicKey: publicKey)
        let byID = Dictionary(uniqueKeysWithValues: signed.packages.map { ($0.id, $0) })
        let ids = prepared.packages.map(\.id)
        guard Set(ids).count == ids.count,
              selection.map({ $0.selected == Set(ids) }) != false else { throw GenerationError.invalidSelection }
        let source = FeaturePackageStore(directory: prepared.directory)
        for id in ids {
            guard let package = byID[id] else { throw GenerationError.invalidSelection }
            _ = try source.verifiedBytes(for: package)
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = "generation-" + UUID().uuidString
        let target = root.appendingPathComponent(name, isDirectory: true)
        try files.moveItem(at: prepared.directory, to: target)
        do {
            try prepared.signedManifest.write(to: target.appendingPathComponent("manifest.json"), options: [.atomic])
            let pointer = try JSONEncoder().encode(Pointer(generation: name, ids: ids.sorted(), selection: selection))
            // The previous generation remains intact until the new pointer is
            // replaced; a failed or interrupted publish cannot corrupt it.
            try pointer.write(to: root.appendingPathComponent("current.json"), options: [.atomic])
        } catch {
            try? files.removeItem(at: target)
            throw error
        }
    }

    func current() throws -> Current? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let pointerURL = root.appendingPathComponent("current.json")
        guard files.fileExists(atPath: pointerURL.path) else { return nil }
        let pointer = try JSONDecoder().decode(Pointer.self, from: Data(contentsOf: pointerURL))
        let prefix = "generation-"
        guard pointer.generation.hasPrefix(prefix), UUID(uuidString: String(pointer.generation.dropFirst(prefix.count))) != nil,
              Set(pointer.ids).count == pointer.ids.count,
              pointer.selection.map({ $0.selected == Set(pointer.ids) }) != false else { throw GenerationError.invalidPointer }
        let directory = root.appendingPathComponent(pointer.generation, isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try FeaturePackageManifest.verify(data, publicKey: publicKey)
        let byID = Dictionary(uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) })
        let packages = try pointer.ids.map { id in
            guard let package = byID[id] else { throw GenerationError.invalidSelection }
            return package
        }
        return Current(directory: directory, packages: packages, selection: pointer.selection)
    }

    /// Copy the verified bytes while holding the generation lock so cleanup
    /// cannot remove their generation between lookup and read.
    func component(id: String) throws -> ComponentLookup {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let current = try current() else { return .legacy }
        guard let package = current.packages.first(where: { $0.id == id }) else { return .missing }
        return .verified(try FeaturePackageStore(directory: current.directory).verifiedBytes(for: package))
    }

    /// Component execution must obtain bytes through `component(id:)`; direct
    /// readers must finish before this call. Unknown files are left alone.
    @discardableResult
    func discardSupersededGenerations() throws -> Int {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let current = try current() else { return 0 }
        let entries = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var removed = 0
        for entry in entries {
            let name = entry.lastPathComponent
            let prefix = "generation-"
            guard name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
                  entry.standardizedFileURL.path != current.directory.standardizedFileURL.path else { continue }
            try files.removeItem(at: entry)
            removed += 1
        }
        return removed
    }
}
