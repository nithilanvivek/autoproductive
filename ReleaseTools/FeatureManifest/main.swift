import CryptoKit
import Darwin
import Foundation

/// Builds the public catalogue from already-built components. Sparkle's
/// sign_update reads the release key from Keychain; this program never reads or
/// prints the private key. Immutable versioned URLs keep reviewed downloads valid.
@main struct FeatureManifestTool {
    struct Envelope: Encodable { let payload: String; let signature: String }
    enum Failure: Error { case arguments, version, invalidPackage, signing, invalidPublicKey }

    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Could not prepare the signed feature catalogue.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        guard CommandLine.arguments.count == 7 else { throw Failure.arguments }
        let version = CommandLine.arguments[1]
        let architecture = CommandLine.arguments[2]
        guard ["arm64", "x86_64"].contains(architecture) else { throw Failure.arguments }
        guard !version.isEmpty, version.count <= 80,
              version.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._")).contains($0) }),
              version != ".", version != ".." else { throw Failure.version }
        let packagesDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[4])
        let signer = URL(fileURLWithPath: CommandLine.arguments[5])
        guard let publicBytes = Data(base64Encoded: CommandLine.arguments[6]),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicBytes) else { throw Failure.invalidPublicKey }
        let ids = FeatureComponentSupport.toolIDs.union(FeatureComponentSupport.actionIDs).sorted()
        var packages: [FeaturePackageManifest.Package] = []
        for id in ids {
            let file = packagesDirectory.appendingPathComponent(id + ".package")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0, size <= 512 * 1024 * 1024 else {
                throw Failure.invalidPackage
            }
            let bytes = try Data(contentsOf: file)
            guard bytes.count == size else { throw Failure.invalidPackage }
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let url = URL(string: "https://nithi.land/apps/autoproductive/packages/\(version)/\(architecture)/\(id).package")!
            packages.append(.init(id: id, version: version, url: url, sha256: digest, size: size))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(FeaturePackageManifest(format: 1, packages: packages))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-catalogue-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try payload.write(to: temporary, options: [.atomic])
        let process = Process()
        let pipe = Pipe()
        process.executableURL = signer
        process.arguments = ["--account", "land.nithi.autoproductive", "-p", temporary.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let signatureBytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, signatureBytes.count < 4096,
              let signature = String(data: signatureBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let decodedSignature = Data(base64Encoded: signature), publicKey.isValidSignature(decodedSignature, for: payload) else {
            throw Failure.signing
        }
        let envelope = try encoder.encode(Envelope(payload: payload.base64EncodedString(), signature: signature))
        _ = try FeaturePackageManifest.verify(envelope, publicKey: publicKey)
        // A hard link in the destination directory publishes a complete file
        // atomically and fails if a release catalogue already exists.
        let pending = output.deletingLastPathComponent().appendingPathComponent(".catalogue-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pending) }
        try envelope.write(to: pending, options: [.withoutOverwriting])
        try FileManager.default.linkItem(at: pending, to: output)
        print("Prepared a signed catalogue for \(packages.count) components, version \(version).")
    }
}
