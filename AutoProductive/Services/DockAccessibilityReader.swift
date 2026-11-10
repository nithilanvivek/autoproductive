import AppKit
import ApplicationServices

struct DockRunningApp {
    let pid: pid_t
    let names: [String]
    let bundlePath: String?
}

struct DockIconHit {
    let pid: pid_t
    let frame: CGRect
}

struct DockAccessibleWindow {
    let element: AXUIElement
    let title: String
    // Accessibility and ScreenCaptureKit both use top-left display coordinates.
    let frame: CGRect?
    let canClose: Bool
    let windowID: CGWindowID?
}

struct DockWindowInventory {
    let windows: [DockAccessibleWindow]
    let answered: Bool
}

/// AX messages are synchronous IPC. Keep them off the main run loop, including
/// when the Dock or a target app is slow to respond.
enum DockAccessibilityReader {
    static let queue = DispatchQueue(label: "land.nithi.autoproductive.dock-reader", qos: .userInitiated)

    static func hit(at point: CGPoint, primaryTop: CGFloat, dockPID: pid_t,
                    apps: [DockRunningApp]) -> DockIconHit? {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 0.15)
        let deadline = Date().addingTimeInterval(0.5)
        var raw: AXUIElement?
        _ = AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(primaryTop - point.y), &raw)
        var candidate = raw
        for _ in 0..<8 {
            guard Date() < deadline, let element = candidate else { break }
            if let hit = resolve(element, primaryTop: primaryTop, apps: apps) { return hit }
            guard let parent = attribute(element, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            candidate = (parent as! AXUIElement)
        }

        // Some Dock versions return the list rather than its tile. Restrict the
        // fallback to the Dock's hierarchy, with both a time and node budget.
        var pending = [dock]
        var index = 0
        while index < pending.count, index < 160, Date() < deadline {
            let element = pending[index]
            index += 1
            AXUIElementSetMessagingTimeout(element, 0.1)
            if let frame = frame(element) {
                let appKit = CGRect(x: frame.minX, y: primaryTop - frame.maxY,
                                    width: frame.width, height: frame.height)
                if appKit.contains(point), let hit = resolve(element, primaryTop: primaryTop, apps: apps) {
                    return hit
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(max(0, 160 - pending.count)))
            }
        }
        return nil
    }

    private static func resolve(_ element: AXUIElement, primaryTop: CGFloat,
                                apps: [DockRunningApp]) -> DockIconHit? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var path: String?
        if let value = attribute(element, kAXURLAttribute) {
            if let url = value as? URL { path = url.standardizedFileURL.path }
            else if let string = value as? String, let url = URL(string: string) {
                path = url.standardizedFileURL.path
            }
        }
        var app = path.flatMap { path in apps.first { $0.bundlePath == path } }
        if app == nil {
            for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
                guard let label = attribute(element, key) as? String else { continue }
                let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let match = apps.first(where: { $0.names.contains(normalized) }) { app = match; break }
            }
        }
        guard let app, let frame = frame(element) else { return nil }
        return DockIconHit(pid: app.pid, frame: CGRect(x: frame.minX, y: primaryTop - frame.maxY,
                                                      width: frame.width, height: frame.height))
    }

    static func inventory(for pid: pid_t) -> DockWindowInventory {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let listed = attribute(app, kAXWindowsAttribute) as? [AXUIElement]
        var windows = listed ?? []
        // Full-screen/off-Space windows can be absent from AXWindows while the
        // application still exposes its main or focused window explicitly.
        for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let value = attribute(app, key), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = value as! AXUIElement
                if !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
            }
        }
        guard listed != nil || !windows.isEmpty else {
            return DockWindowInventory(windows: [], answered: false)
        }
        var result: [DockAccessibleWindow] = []
        let deadline = Date().addingTimeInterval(2)
        for window in windows {
            guard Date() < deadline else { break }
            AXUIElementSetMessagingTimeout(window, 0.1)
            let role = attribute(window, kAXRoleAttribute) as? String
            guard role == kAXWindowRole else { continue }
            let subrole = attribute(window, kAXSubroleAttribute) as? String
            let minimized = attribute(window, kAXMinimizedAttribute) as? Bool ?? false
            let fullscreen = attribute(window, "AXFullScreen") as? Bool ?? false
            let hasMinimize = button(window, kAXMinimizeButtonAttribute) != nil
            // AXWindow also describes browser popups and framework surfaces.
            // Ordinary documents, full-screen and minimized windows remain;
            // a nonstandard window needs real window chrome to be switchable.
            guard DockWindowMatching.isUserWindow(role: role, subrole: subrole,
                minimized: minimized, fullscreen: fullscreen, canMinimize: hasMinimize) else { continue }
            let bounds = frame(window)
            if let bounds, bounds.width <= 50 || bounds.height <= 50 { continue }
            result.append(DockAccessibleWindow(element: window,
                title: attribute(window, kAXTitleAttribute) as? String ?? "", frame: bounds,
                canClose: button(window, kAXCloseButtonAttribute) != nil,
                windowID: DockWindowCapture.id(of: window)))
        }
        return DockWindowInventory(windows: result, answered: true)
    }

    static func windows(for pid: pid_t) -> [DockAccessibleWindow] { inventory(for: pid).windows }

    static func close(_ window: AXUIElement, completion: @escaping (Bool) -> Void) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier {
            DispatchQueue.main.async {
                guard let id = DockWindowCapture.id(of: window),
                      let native = NSApp.windows.first(where: { $0.windowNumber == Int(id) }) else { completion(false); return }
                native.performClose(nil)
                completion(true)
            }
            return
        }
        queue.async {
            AXUIElementSetMessagingTimeout(window, 0.2)
            let accepted = button(window, kAXCloseButtonAttribute).map {
                AXUIElementPerformAction($0, kAXPressAction as CFString) == .success
            } ?? false
            DispatchQueue.main.async { completion(accepted) }
        }
    }

    private static func button(_ window: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(window, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let button = value as! AXUIElement
        AXUIElementSetMessagingTimeout(button, 0.1)
        return (attribute(button, kAXEnabledAttribute) as? Bool) == false ? nil : button
    }

    static func raise(_ window: AXUIElement, pid: pid_t, completion: ((Bool) -> Void)? = nil) {
        if pid == ProcessInfo.processInfo.processIdentifier {
            // AX dispatches self-targeted setters directly into AppKit. Calling
            // deminiaturize on the IPC queue triggers AppKit's main-thread trap.
            DispatchQueue.main.async {
                guard let id = DockWindowCapture.id(of: window),
                      let native = NSApp.windows.first(where: { $0.windowNumber == Int(id) }) else { completion?(false); return }
                if native.isMiniaturized { native.deminiaturize(nil) }
                native.makeKeyAndOrderFront(nil)
                NSApp.activate()
                completion?(true)
            }
            return
        }
        queue.async {
            AXUIElementSetMessagingTimeout(window, 0.2)
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
            if let completion { DispatchQueue.main.async { completion(result == .success) } }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}
