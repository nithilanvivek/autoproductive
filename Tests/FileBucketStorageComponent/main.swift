import Foundation

@main struct Tests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let bucket = root.appendingPathComponent("bucket", isDirectory: true)
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        let source = root.appendingPathComponent("source.txt")
        try "original ✓".write(to: source, atomically: true, encoding: .utf8)
        for _ in 0..<5 {
            let tool = try FeatureFileBucketStorage(verifiedBytes: bytes)
            _ = try tool.list(folder: bucket, legacyFolder: nil)
        }
        let tool = try FeatureFileBucketStorage(verifiedBytes: bytes)
        try tool.copy(source: source, folder: bucket)
        try tool.copy(source: source, folder: bucket)
        let items = try tool.list(folder: bucket, legacyFolder: nil)
        guard Set(items.map(\.lastPathComponent)) == ["source 2.txt", "source.txt"],
              try String(contentsOf: source, encoding: .utf8) == "original ✓" else { fatalError("Copies or names changed") }
        try tool.remove(item: items[0], folder: bucket, permanent: true)
        guard !FileManager.default.fileExists(atPath: items[0].path) else { fatalError("Bucket copy not removed") }
        do { try tool.remove(item: source, folder: bucket, permanent: true); fatalError("Outside file must not be deleted") } catch {}
        guard FileManager.default.fileExists(atPath: source.path) else { fatalError("Source outside bucket was removed") }
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try "legacy".write(to: legacy.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
        let migrated = try tool.list(folder: bucket, legacyFolder: legacy)
        guard migrated.count == 2, !FileManager.default.fileExists(atPath: legacy.path) else { fatalError("Legacy bucket migration failed") }
        print("Passed signed File Bucket storage, duplicate names, removal boundary, and migration checks.")
    }
}
