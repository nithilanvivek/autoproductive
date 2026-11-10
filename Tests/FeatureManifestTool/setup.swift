import Foundation

@main struct Setup {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for id in FeatureComponentSupport.actionIDs.union(FeatureComponentSupport.toolIDs) {
            try Data(id.utf8).write(to: folder.appendingPathComponent(id + ".package"))
        }
    }
}
