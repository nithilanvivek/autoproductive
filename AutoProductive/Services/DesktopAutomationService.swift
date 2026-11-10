import AppKit
import ApplicationServices
import ScreenCaptureKit
import OSLog

@MainActor
enum DesktopAutomationService {
    private static let screenLogger = Logger(subsystem: "land.nithi.autoproductive", category: "ScreenTriggers")
    private static var captureSizes: [CGDirectDisplayID: CGSize] = [:]
    static let syntheticEventTag: Int64 = 0x415550524F
    static var controlPermissionName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            ? "Device Control and Data Access" : "Accessibility"
    }

    static func requireAccessibility() throws {
        guard AXIsProcessTrusted() else {
            throw WorkflowError.invalid("Allow AutoProductive in System Settings → Privacy & Security → \(controlPermissionName), then enable the trigger again.")
        }
    }

    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        event.post(tap: .cghidEventTap)
    }

    static func flags(for modifiers: ShortcutModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    static func press(_ key: KeyboardShortcutDefinition) throws {
        try requireAccessibility()
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: CGKeyCode(key.keyCode), keyDown: down) else { continue }
            event.flags = flags(for: key.modifiers)
            post(event)
        }
    }

    static func type(_ text: String) async throws {
        try requireAccessibility()
        // Keep complete graphemes together, including emoji and non-Latin scripts.
        for (index, character) in text.enumerated() {
            try Task.checkCancellation()
            if index.isMultiple(of: 32) { try await Task.sleep(for: .milliseconds(2)) }
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                post(event)
            }
        }
    }

    static func pointer(_ step: WorkflowStep) throws {
        try requireAccessibility()
        let point: CGPoint
        if step.coordinatesInPixels == true {
            guard let primaryScreen = NSScreen.screens.first else {
                throw WorkflowError.invalid("No display is available for the pixel click.")
            }
            let scale = primaryScreen.backingScaleFactor
            guard step.x >= 0, step.y >= 0,
                  step.x < primaryScreen.frame.width * scale,
                  step.y < primaryScreen.frame.height * scale else {
                throw WorkflowError.invalid("The pixel coordinate is outside the primary display.")
            }
            point = CGPoint(x: step.x / scale, y: step.y / scale)
        } else {
            point = CGPoint(x: step.x, y: step.y)
        }
        let button: CGMouseButton = step.option == "right" ? .right : step.option == "middle" ? .center : .left
        let down: CGEventType = button == .right ? .rightMouseDown : button == .center ? .otherMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : button == .center ? .otherMouseUp : .leftMouseUp
        for type in step.action == .movePointer ? [.mouseMoved] : [down, up] {
            if let event = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState), mouseType: type, mouseCursorPosition: point, mouseButton: button) { post(event) }
        }
    }

    static func arrangeWindow(_ step: WorkflowStep) async throws {
        try requireAccessibility()
        guard let app = NSWorkspace.shared.frontmostApplication else { throw WorkflowError.invalid("No active application.") }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &rawWindow) == .success,
              let rawWindow, CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            throw WorkflowError.invalid("The active app does not expose a movable window.")
        }
        let window = rawWindow as! AXUIElement
        func request(area: CGRect?) -> FeatureComponentDispatcher.WindowRequest {
            .init(option: step.option, x: step.x, y: step.y, amount: step.amount, heightText: step.secondaryText,
                  areaX: area.map { Double($0.origin.x) }, areaY: area.map { Double($0.origin.y) },
                  areaWidth: area.map { Double($0.width) }, areaHeight: area.map { Double($0.height) })
        }
        if step.option == "focus" || step.option == "minimize" {
            _ = try await FeatureComponentDispatcher.windowPlan(request: request(area: nil))
            try Task.checkCancellation()
        }
        if step.option == "focus" { app.activate(); AXUIElementPerformAction(window, kAXRaiseAction as CFString); return }
        if step.option == "minimize" {
            try set(window, kAXMinimizedAttribute, kCFBooleanTrue); return
        }
        var rawPosition: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition)
        var current = CGPoint.zero
        if let rawPosition, CFGetTypeID(rawPosition) == AXValueGetTypeID() { AXValueGetValue(rawPosition as! AXValue, .cgPoint, &current) }
        // AX uses top-left global coordinates; NSScreen uses bottom-left coordinates.
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screen = NSScreen.screens.first { screen in
            CGRect(x: screen.frame.minX, y: desktopTop - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height).contains(current)
        } ?? NSScreen.main
        guard let screen else { throw WorkflowError.invalid("No screen is available.") }
        let visible = screen.visibleFrame
        let area = CGRect(x: visible.minX, y: desktopTop - visible.maxY, width: visible.width, height: visible.height)
        var frame = area
        if let plan = try await FeatureComponentDispatcher.windowPlan(request: request(area: area)) {
            frame = CGRect(x: plan.x!, y: plan.y!, width: plan.width!, height: plan.height!)
        } else {
            switch step.option {
            case "leftHalf": frame.size.width /= 2
            case "rightHalf": frame.origin.x += area.width / 2; frame.size.width /= 2
            case "center": frame = area.insetBy(dx: area.width * 0.15, dy: area.height * 0.15)
            case "custom": frame = CGRect(x: step.x, y: step.y, width: max(100, step.amount), height: max(100, Double(step.secondaryText) ?? 600))
            default: break
            }
        }
        try Task.checkCancellation()
        var size = frame.size; var position = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &position) else { return }
        try set(window, kAXSizeAttribute, sizeValue)
        try set(window, kAXPositionAttribute, pointValue)
    }

    private static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) throws {
        guard AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success else {
            throw WorkflowError.invalid("This app does not allow that window operation.")
        }
    }

    static func screenMatches(_ step: WorkflowStep) async throws -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            throw WorkflowError.invalid("Allow AutoProductive in System Settings → Privacy & Security → Screen & System Audio Recording before using screen conditions.")
        }
        guard step.amount.isFinite, (0...255).contains(step.amount) else {
            throw WorkflowError.invalid("Color tolerance must be between 0 and 255.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays.filter { $0.frame.width > 0 && $0.frame.height > 0 && !$0.frame.isInfinite && !$0.frame.isNull }
        guard !displays.isEmpty else { throw ScreenObservationError.noDisplays }
        if step.action == .screenImage, let scope = step.imageSearchScope {
            let reference = try ScreenReferenceImage.load(step.text)
            guard let template = PixelImage(reference) else { throw WorkflowError.invalid("The reference image could not be read.") }
            var areas: [CGDirectDisplayID: (SCDisplay, [CGRect])] = [:]
            if scope == .entireScreen {
                for display in displays { areas[display.displayID] = (display, [display.frame]) }
            } else {
                let regions = step.imageRegions ?? []
                guard !regions.isEmpty, regions.count <= 32, regions.allSatisfy(\.isValid) else {
                    throw WorkflowError.invalid("Select valid screen rectangles to search for the image.")
                }
                for region in regions {
                    guard let display = displays.first(where: { $0.frame.contains(region.rect) }) else {
                        throw ScreenObservationError.rectangleOutsideDisplays
                    }
                    if areas[display.displayID] == nil { areas[display.displayID] = (display, []) }
                    areas[display.displayID]?.1.append(region.rect)
                }
            }
            for (display, rectangles) in areas.values {
                try Task.checkCancellation()
                let image = try await capture(display, content: content)
                guard let pixels = PixelImage(image) else { throw WorkflowError.invalid("The display image could not be read.") }
                let rects = rectangles.map { rect in
                    ScreenColorRegion(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                        .pixelRect(displayBounds: display.frame, imageWidth: image.width, imageHeight: image.height)
                }
                let scan = Task.detached(priority: .utility) {
                    for rect in rects {
                        if try pixels.finds(template, tolerance: Int(step.amount), in: rect, allowResize: step.matchResizedImages != false) { return true }
                    }
                    return false
                }
                if try await withTaskCancellationHandler(operation: { try await scan.value }, onCancel: { scan.cancel() }) { return true }
            }
            return false
        }
        if step.action == .screenPixel, let regions = step.colorRegions {
            guard let target = ScreenColor.parse(step.text), !regions.isEmpty, regions.count <= 32,
                  regions.allSatisfy(\.isValid) else { throw WorkflowError.invalid("Select valid screen rectangles and a color as #RRGGBB.") }
            var grouped: [CGDirectDisplayID: (SCDisplay, [ScreenColorRegion])] = [:]
            for region in regions {
                guard let display = displays.first(where: { $0.frame.contains(region.rect) }) else {
                    throw ScreenObservationError.rectangleOutsideDisplays
                }
                if grouped[display.displayID] == nil { grouped[display.displayID] = (display, []) }
                grouped[display.displayID]?.1.append(region)
            }
            let requireEvery = step.colorInEveryRegion == true
            for (display, selections) in grouped.values {
                try Task.checkCancellation()
                let image = try await capture(display, content: content)
                guard let pixels = PixelImage(image) else { throw WorkflowError.invalid("The display image could not be read.") }
                let rects = selections.map { $0.pixelRect(displayBounds: display.frame, imageWidth: image.width, imageHeight: image.height) }
                let scan = Task.detached(priority: .utility) {
                    try pixels.matchesColor(target, in: rects, tolerance: Int(step.amount), requireEvery: requireEvery)
                }
                let matched = try await withTaskCancellationHandler(operation: { try await scan.value }, onCancel: { scan.cancel() })
                if requireEvery && !matched { return false }
                if !requireEvery && matched { return true }
            }
            return requireEvery
        }
        guard step.x.isFinite, step.y.isFinite, step.amount.isFinite else {
            throw WorkflowError.invalid("Use finite screen coordinates and tolerance.")
        }
        let display = displays.first { display in
            CGRect(x: display.frame.minX, y: display.frame.minY, width: display.frame.width, height: display.frame.height).contains(CGPoint(x: step.x, y: step.y))
        }
        guard let display else { throw ScreenObservationError.positionOutsideDisplays }
        let image = try await capture(display, content: content)
        let point = CGPoint(x: (step.x - display.frame.minX) * Double(image.width) / display.frame.width,
                            y: (step.y - display.frame.minY) * Double(image.height) / display.frame.height)
        if step.action == .screenPixel {
            guard let target = ScreenColor.parse(step.text), let pixels = PixelImage(image) else { return false }
            return try pixels.containsColor(target, in: CGRect(x: floor(point.x), y: floor(point.y), width: 1, height: 1), tolerance: Int(step.amount))
        }
        // Compare a reference image at a chosen screen position, with sampled color tolerance.
        let referenceImage = try ScreenReferenceImage.load(step.text)
        guard let screenPixels = PixelImage(image), let template = PixelImage(referenceImage) else { return false }
        let tolerance = max(0, min(255, Int(step.amount)))
        return try await Task.detached(priority: .utility) {
            if step.option == "search" { return try screenPixels.finds(template, tolerance: tolerance, allowResize: step.matchResizedImages != false) }
            return screenPixels.matches(template, x: Int(point.x), y: Int(point.y), tolerance: tolerance)
        }.value
    }

    private static func capture(_ display: SCDisplay, content: SCShareableContent) async throws -> CGImage {
        // SCDisplay dimensions are points; the stream output dimensions are
        // pixels. Preserve Retina detail rather than downsampling the screen.
        let tintApps = content.applications.filter { $0.bundleIdentifier == "org.herf.Flux" }
        let filter = SCContentFilter(display: display, excludingApplications: tintApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let size = ScreenCaptureSizing.pixels(points: CGSize(width: display.width, height: display.height), scale: Double(filter.pointPixelScale))
        configuration.width = Int(size.width); configuration.height = Int(size.height)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        // Normalize #RRGGBB comparisons to sRGB, rather than the monitor's profile.
        // ScreenCaptureKit reads composited content before display gamma changes.
        configuration.colorSpaceName = CGColorSpace.sRGB
        if #available(macOS 15.0, *) { configuration.captureDynamicRange = .SDR }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let captured = CGSize(width: image.width, height: image.height)
        if captureSizes[display.displayID] != captured {
            screenLogger.info("Capture dimensions points=\(display.width)x\(display.height) pixels=\(image.width)x\(image.height)")
            captureSizes[display.displayID] = captured
        }
        return image
    }
}
