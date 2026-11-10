import CoreGraphics
import Foundation

/// Screen capture remains inside AutoProductive so it uses the app's existing
/// screen-recording permission; the component only supplies the capture code.
final class FeatureDockPreviewCapture {
    private typealias Capture = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
    private let library: FeatureToolLibrary
    private let capture: Capture

    init(verifiedBytes: Data) throws {
        let library = try FeatureToolLibrary.open(verifiedBytes: verifiedBytes, expectedID: "tool.dockPreviews",
                                                  requiredSymbols: ["autoproductive_dock_capture_image"])
        capture = unsafeBitCast(try library.symbol("autoproductive_dock_capture_image"), to: Capture.self)
        self.library = library
    }

    func image(of id: CGWindowID) -> CGImage? {
        guard let pointer = capture(id) else { return nil }
        return Unmanaged<CGImage>.fromOpaque(pointer).takeRetainedValue()
    }
}
