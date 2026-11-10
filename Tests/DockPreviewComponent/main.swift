import Foundation

@main struct Tests {
    static func main() throws {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let component = try FeatureDockPreviewCapture(verifiedBytes: bytes)
        guard component.image(of: 0) == nil else { fatalError("Invalid window must not be captured") }
        let same = try FeatureDockPreviewCapture(verifiedBytes: bytes)
        guard same.image(of: 0) == nil else { fatalError("Repeated loading must remain safe") }
        print("Passed signed Dock preview component loading without screen capture.")
    }
}
