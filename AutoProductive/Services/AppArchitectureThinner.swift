import Foundation
import Darwin

/// Prepares a separately verified copy before atomically replacing the bundle.
/// Each slice retains Apple's code signature; never rewrite a running binary.
enum AppArchitectureThinner {
    enum ThinningError: LocalizedError {
        case invalidBundle, unsupportedArchitecture, toolFailed(String), swapFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .invalidBundle: return "The application cannot be updated in its current location. Move it to Applications and try again."
            case .unsupportedArchitecture: return "This processor is not supported."
            case .toolFailed(let message): return "Couldn’t prepare the app for this Mac: \(message)"
            case .swapFailed: return "Couldn’t replace the app. Move it to a writable Applications folder and try again."
            }
        }
    }

    static func fatFiles(in bundle: URL) throws -> [URL] {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: contents, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw ThinningError.invalidBundle
        }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let handle = try FileHandle(forReadingFrom: url)
            let prefix = try handle.read(upToCount: 4) ?? Data()
            try handle.close()
            if [[0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
                [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]].contains(Array(prefix)) {
                result.append(url)
            }
        }
        return result
    }

    static func needsThinning(bundle: URL = Bundle.main.bundleURL) throws -> Bool {
        try !fatFiles(in: bundle).isEmpty
    }

    /// Disk images and Gatekeeper-translocated downloads can be read-only.
    /// The app remains usable as a universal binary until it is moved somewhere
    /// writable; feature installation must not be blocked by this optimization.
    static func canReplace(bundle: URL = Bundle.main.bundleURL) -> Bool {
        let parent = bundle.deletingLastPathComponent()
        var info = statfs()
        guard statfs(parent.path, &info) == 0, (UInt32(info.f_flags) & UInt32(MNT_RDONLY)) == 0 else { return false }
        return access(parent.path, W_OK) == 0
    }

    /// Returns the old bundle's temporary location, for removal after exit.
    static func prepareAndSwap(bundle: URL = Bundle.main.bundleURL, architecture: String = FeatureArchitecture.current) throws -> URL? {
        guard ["arm64", "x86_64"].contains(architecture) else { throw ThinningError.unsupportedArchitecture }
        guard bundle.isFileURL, bundle.pathExtension == "app", !bundle.hasDirectoryPath || bundle.lastPathComponent.hasSuffix(".app") else { throw ThinningError.invalidBundle }
        guard try needsThinning(bundle: bundle) else { return nil }
        guard canReplace(bundle: bundle) else { return nil }
        let staged = bundle.deletingLastPathComponent().appendingPathComponent(".AutoProductive-architecture-\(UUID().uuidString).app", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.copyItem(at: bundle, to: staged)
            for file in try fatFiles(in: staged) {
                let temp = file.deletingLastPathComponent().appendingPathComponent(".thin-\(UUID().uuidString)")
                try thin(file, architecture: architecture).write(to: temp)
                let permissions = try fm.attributesOfItem(atPath: file.path)[.posixPermissions]
                if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path) }
                guard Darwin.rename(temp.path, file.path) == 0 else { throw ThinningError.swapFailed(errno) }
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            guard renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, bundle.path, UInt32(RENAME_SWAP)) == 0 else {
                throw ThinningError.swapFailed(errno)
            }
            return staged
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }

    /// Read the universal Mach-O container directly, so installation does not
    /// depend on Xcode or the Command Line Tools being installed on the Mac.
    private static func thin(_ file: URL, architecture: String) throws -> Data {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count >= 8 else { throw ThinningError.toolFailed("invalid binary") }
        let magic = Array(data.prefix(4))
        let little = magic == [0xbe, 0xba, 0xfe, 0xca] || magic == [0xbf, 0xba, 0xfe, 0xca]
        let is64 = magic == [0xca, 0xfe, 0xba, 0xbf] || magic == [0xbf, 0xba, 0xfe, 0xca]
        func integer(_ offset: Int, _ count: Int) throws -> UInt64 {
            guard offset >= 0, count > 0, offset <= data.count - count else { throw ThinningError.toolFailed("invalid binary") }
            let bytes = Array(data[offset..<(offset + count)])
            return (little ? Array(bytes.reversed()) : bytes).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        let count = try integer(4, 4)
        let stride = is64 ? 32 : 20
        guard count <= 128, count <= UInt64((data.count - 8) / stride) else { throw ThinningError.toolFailed("invalid binary") }
        let cpu: UInt64 = architecture == "arm64" ? 0x0100000c : 0x01000007
        let subtype: UInt64 = architecture == "arm64" ? 0 : 3
        for i in 0..<Int(count) {
            let base = 8 + i * stride
            let type = try integer(base, 4)
            let sub = try integer(base + 4, 4) & 0x00ffffff
            guard type == cpu && sub == subtype else { continue }
            let offset = try integer(base + 8, is64 ? 8 : 4)
            let size = try integer(base + (is64 ? 16 : 12), is64 ? 8 : 4)
            guard offset <= UInt64(data.count), size <= UInt64(data.count) - offset, size > 0 else { throw ThinningError.toolFailed("invalid binary slice") }
            return data.subdata(in: Int(offset)..<Int(offset + size))
        }
        throw ThinningError.toolFailed("missing \(architecture) slice")
    }

    static func rollback(bundle: URL, oldBundle: URL) throws {
        guard renameatx_np(AT_FDCWD, oldBundle.path, AT_FDCWD, bundle.path, UInt32(RENAME_SWAP)) == 0 else {
            throw ThinningError.swapFailed(errno)
        }
        try FileManager.default.removeItem(at: oldBundle)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ThinningError.toolFailed(URL(fileURLWithPath: executable).lastPathComponent) }
    }
}
