import ApplicationServices
import CoreGraphics
import Darwin
import Carbon

/// Optional macOS window-server bridges. Resolve symbols at runtime so a system
/// without them continues through ScreenCaptureKit rather than failing to load.
/// These read images only after the normal Screen Recording permission check.
enum DockWindowCapture {
    static let queue = DispatchQueue(label: "land.nithi.autoproductive.dock-capture", qos: .userInitiated)

    private typealias WindowNumber = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Capture = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
    private typealias ProcessNumber = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias BringForward = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError

    private static func lookup<T>(_ name: String, as type: T.Type) -> T? {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }

    private static let windowNumber = lookup("_AXUIElementGetWindow", as: WindowNumber.self)
    private static let connection = lookup("CGSMainConnectionID", as: Connection.self)
    private static let capture = lookup("CGSHWCaptureWindowList", as: Capture.self)
    private static let processNumber = lookup("GetProcessForPID", as: ProcessNumber.self)
    private static let bringForward = lookup("_SLPSSetFrontProcessWithOptions", as: BringForward.self)

    static func front(_ windowID: CGWindowID, pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), let processNumber, let bringForward else { return false }
        var process = ProcessSerialNumber()
        guard processNumber(pid, &process) == noErr else { return false }
        return bringForward(&process, windowID, 0x200) == .success
    }

    static func id(of window: AXUIElement) -> CGWindowID? {
        var number: UInt32 = 0
        guard let windowNumber, windowNumber(window, &number) == .success, number != 0 else { return nil }
        return number
    }

    #if MODULAR_FEATURES
    private static let component: FeatureDockPreviewCapture? = {
        guard let bytes = try? FeatureComponentDispatcher.toolBytes(id: "tool.dockPreviews") else { return nil }
        return try? FeatureDockPreviewCapture(verifiedBytes: bytes)
    }()
    static var isAvailable: Bool { component != nil }
    static func image(of windowID: CGWindowID) -> CGImage? { component?.image(of: windowID) }
    #else
    static var isAvailable: Bool { true }
    static func image(of windowID: CGWindowID) -> CGImage? {
        guard CGPreflightScreenCaptureAccess(), let capture, let connection else { return nil }
        let connectionID = connection()
        guard connectionID != 0 else { return nil }
        var number = UInt32(windowID)
        // Request the window's backing image at full resolution, without the
        // display's clip shape (which can hide windows on other Spaces).
        let flags: UInt32 = 0x900
        guard let owned = capture(connectionID, &number, 1, flags) else { return nil }
        let objects = owned.takeRetainedValue() as [AnyObject]
        guard let object = objects.first, CFGetTypeID(object) == CGImage.typeID else { return nil }
        let original = object as! CGImage
        guard original.width > 1, original.height > 1 else { return nil }
        let ratio = min(1, 480 / Double(max(original.width, original.height)))
        let width = max(1, Int(Double(original.width) * ratio))
        let height = max(1, Int(Double(original.height) * ratio))
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.interpolationQuality = .medium
        bitmap.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap.makeImage()
    }
    #endif
}
