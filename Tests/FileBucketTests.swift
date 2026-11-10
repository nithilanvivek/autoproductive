import AppKit
import SwiftUI

// This suite exercises storage and drop geometry. The actual native content is
// compiled by the app build and checked in the running panel, not instantiated here.
struct FileBucketView: View { var body: some View { EmptyView() } }

@main struct FileBucketTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.txt")
        try "bucket test".write(to: source, atomically: true, encoding: .utf8)
        let suite = "land.nithi.autoproductive.bucket-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bucket = FileBucket(folderURL: root.appendingPathComponent("bucket"), startMonitoring: false, defaults: defaults)
        precondition(!bucket.permanentlyDeleteOnRemove, "Removal must default to Trash")
        bucket.importURLs([source, source])
        precondition(bucket.items.count == 2 && bucket.errorMessage == nil)
        let contents = try String(contentsOf: source, encoding: .utf8)
        precondition(contents == "bucket test")
        precondition(Set(bucket.items.map(\.lastPathComponent)) == ["original.txt", "original 2.txt"])
        precondition(FileBucket.fileURL(from: source.absoluteString) == source)
        precondition(FileBucket.fileURL(from: source.dataRepresentation) == source)
        precondition(FileBucket.fileURL(from: "https://example.com/file") == nil)
        let storedCopy = bucket.items[0]
        bucket.setPermanentlyDeleteOnRemove(true)
        let restored = FileBucket(folderURL: root.appendingPathComponent("bucket"), startMonitoring: false, defaults: defaults)
        precondition(restored.permanentlyDeleteOnRemove, "The explicit removal choice persists")
        bucket.remove(source)
        precondition(FileManager.default.fileExists(atPath: source.path), "Outside files cannot be removed")
        bucket.remove(storedCopy)
        precondition(!FileManager.default.fileExists(atPath: storedCopy.path) && bucket.items.count == 1)
        if CommandLine.arguments.count > 1 {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let component = try FeatureFileBucketStorage(verifiedBytes: bytes)
            let modular = FileBucket(folderURL: root.appendingPathComponent("modular-bucket"), startMonitoring: false,
                                     defaults: defaults, storageComponentOverride: component)
            modular.importURLs([source, source])
            precondition(Set(modular.items.map(\.lastPathComponent)) == ["original.txt", "original 2.txt"])
            modular.setPermanentlyDeleteOnRemove(true)
            modular.remove(source)
            precondition(FileManager.default.fileExists(atPath: source.path), "Component must not remove outside files")
            modular.remove(modular.items[0])
            precondition(modular.items.count == 1)
        }
        let originalAfterRemoval = try String(contentsOf: source, encoding: .utf8)
        precondition(originalAfterRemoval == "bucket test", "Removing the stored copy preserves the original")
        bucket.setPermanentlyDeleteOnRemove(false)
        precondition(!FileBucket(folderURL: root.appendingPathComponent("bucket"), startMonitoring: false, defaults: defaults).permanentlyDeleteOnRemove)
        let sourceFolder = root.appendingPathComponent("folder/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let nestedOriginal = sourceFolder.appendingPathComponent("child.txt")
        try "nested folder test".write(to: nestedOriginal, atomically: true, encoding: .utf8)
        bucket.importURLs([sourceFolder.deletingLastPathComponent(), sourceFolder.deletingLastPathComponent()])
        precondition(bucket.items.count == 3 && bucket.errorMessage == nil)
        for name in ["folder", "folder 2"] {
            let copy = bucket.folderURL.appendingPathComponent("\(name)/nested/child.txt")
            let nestedCopy = try String(contentsOf: copy, encoding: .utf8)
            precondition(nestedCopy == "nested folder test", "Folder imports preserve nested content and resolve collisions")
        }
        bucket.setPermanentlyDeleteOnRemove(true)
        bucket.remove(bucket.folderURL.appendingPathComponent("folder"))
        let preservedNestedOriginal = try String(contentsOf: nestedOriginal, encoding: .utf8)
        precondition(preservedNestedOriginal == "nested folder test" && bucket.items.count == 2)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([source as NSURL])
        precondition(FileBucket.fileURLs(from: pasteboard) == [source])
        pasteboard.clearContents()
        pasteboard.setPropertyList([source.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        precondition(FileBucket.fileURLs(from: pasteboard) == [source])
        for screen in [CGRect(x: 0, y: 0, width: 320, height: 240),
                       CGRect(x: 0, y: 0, width: 1024, height: 768),
                       CGRect(x: -1920, y: 100, width: 1920, height: 1080)] {
            let points = [CGPoint(x: screen.minX + 1, y: screen.midY), CGPoint(x: screen.maxX - 1, y: screen.midY),
                          CGPoint(x: screen.midX, y: screen.minY + 1), CGPoint(x: screen.midX, y: screen.maxY - 1),
                          CGPoint(x: screen.minX + 1, y: screen.maxY - 1)]
            for point in points {
                guard let card = FileBucketDropLayout.cardFrame(pointer: point, screen: screen) else { fatalError("Missing edge card") }
                precondition(screen.contains(card) && card.contains(point), "Card and drop point must stay on the active screen")
                precondition(card.width <= 236 && card.height <= 88)
            }
            precondition(FileBucketDropLayout.cardFrame(pointer: CGPoint(x: screen.midX, y: screen.midY), screen: screen) == nil)
        }
        print("Passed File Bucket file/folder copying, nested content, collisions, removal defaults/persistence, permanent removal, original preservation and drag URL format checks.")
    }
}
