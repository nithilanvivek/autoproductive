import CoreGraphics
import Darwin

private let featureID = strdup("tool.dockPreviews")!

@_cdecl("autoproductive_tool_api_version")
public func toolAPIVersion() -> Int32 { 1 }
@_cdecl("autoproductive_tool_feature_id")
public func toolFeatureID() -> UnsafePointer<CChar>? { UnsafePointer(featureID) }
@_cdecl("autoproductive_dock_capture_image")
public func captureImage(_ id: UInt32) -> UnsafeMutableRawPointer? {
    guard id != 0, let image = DockWindowCapture.image(of: id) else { return nil }
    return Unmanaged.passRetained(image).toOpaque()
}
