import Darwin
import Foundation
import CryptoKit

/// Loads only bytes already verified against the signed feature manifest. The
/// hardened runtime additionally requires the library's code-signing team to
/// match the host; library validation is not disabled.
final class FeatureToolLibrary {
    enum LoadError: LocalizedError {
        case invalidLibrary, missingSymbol, restartRequired
        var errorDescription: String? {
            switch self {
            case .invalidLibrary: "The tool component could not be loaded on this Mac."
            case .missingSymbol: "The tool component does not provide the required interface."
            case .restartRequired: "Restart AutoProductive before loading a different version of this tool."
            }
        }
    }
    private let directory: URL
    private let handle: UnsafeMutableRawPointer
    private static let cacheLock = NSLock()
    private static var loaded: [String: (digest: Data, library: FeatureToolLibrary)] = [:]

    /// Swift classes must not be registered twice under the same names. Keep one
    /// loaded copy per tool for this process, and refuse a different version
    /// until the caller can validate/install it in a separate process.
    static func open(verifiedBytes: Data, expectedID: String, requiredSymbols: [String] = []) throws -> FeatureToolLibrary {
        let digest = Data(SHA256.hash(data: verifiedBytes))
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = loaded[expectedID] {
            guard existing.digest == digest else { throw LoadError.restartRequired }
            for symbol in requiredSymbols { _ = try existing.library.symbol(symbol) }
            return existing.library
        }
        let library = try FeatureToolLibrary(verifiedBytes: verifiedBytes)
        try library.validateInterface(expectedID: expectedID)
        for symbol in requiredSymbols { _ = try library.symbol(symbol) }
        loaded[expectedID] = (digest, library)
        return library
    }

    init(verifiedBytes: Data) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-tool-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let file = directory.appendingPathComponent("tool.dylib")
            try verifiedBytes.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            guard let handle = dlopen(file.path, RTLD_NOW | RTLD_LOCAL) else { throw LoadError.invalidLibrary }
            self.directory = directory
            self.handle = handle
            // The mapped library remains available through its handle; the
            // private copy need not persist on disk for the life of the app.
            try? FileManager.default.removeItem(at: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func symbol(_ name: String) throws -> UnsafeMutableRawPointer {
        guard let value = dlsym(handle, name) else { throw LoadError.missingSymbol }
        return value
    }

    func validateInterface(expectedID: String) throws {
        typealias Version = @convention(c) () -> Int32
        typealias Identifier = @convention(c) () -> UnsafePointer<CChar>?
        let version = unsafeBitCast(try symbol("autoproductive_tool_api_version"), to: Version.self)
        let identifier = unsafeBitCast(try symbol("autoproductive_tool_feature_id"), to: Identifier.self)
        guard version() == 1, let value = identifier(), strnlen(value, 128) < 128,
              String(validatingUTF8: value) == expectedID else { throw LoadError.invalidLibrary }
    }

    deinit {
        dlclose(handle)
        try? FileManager.default.removeItem(at: directory)
    }
}
