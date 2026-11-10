import CryptoKit
import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
defer { try? FileManager.default.removeItem(at: root) }
let store = FeaturePackageStore(directory: root)
let bytes = Data("original package".utf8)
func hash(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
func package(_ id: String = "tool.audioMixer", _ data: Data = bytes) -> FeaturePackageManifest.Package {
    .init(id: id, version: "1", url: URL(string: "https://nithi.land/apps/autoproductive/package")!, sha256: hash(data), size: Int64(data.count))
}
var checks = 0
func check(_ passed: @autoclosure () -> Bool, _ description: String) {
    checks += 1
    if !passed() { fatalError(description) }
}
let metadata = package()
try store.stage(bytes, package: metadata)
check((try? store.verifiedBytes(for: metadata)) == bytes, "Verified package is stored and read")
let bad = Data(repeating: 0, count: bytes.count)
check((try? store.stage(bad, package: metadata)) == nil, "Corrupt download is rejected")
check((try? store.verifiedBytes(for: metadata)) == bytes, "Failed update preserves old package")
check((try? store.stage(bytes, package: package("tool.../escape"))) == nil, "Unsafe identifier is rejected")
let url = root.appendingPathComponent("tool.audioMixer.package")
try bad.write(to: url)
check((try? store.verifiedBytes(for: metadata)) == nil, "Changed file is rejected when read")
try store.remove(id: metadata.id)
check(!FileManager.default.fileExists(atPath: url.path), "Remove deletes package")
print("Passed \(checks) feature package storage checks.")
