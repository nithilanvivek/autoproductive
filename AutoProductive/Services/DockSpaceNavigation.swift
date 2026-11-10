import AppKit
import ApplicationServices
import Carbon
import OSLog

/// User-initiated window selection can need a Space change before AX exposes
/// the selected window. Use the system's registered shortcut, never assume the
/// default keys, and stop immediately when a requested move changes nothing.
@MainActor
final class DockSpaceNavigation {
    static let shared = DockSpaceNavigation()
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "land.nithi.autoproductive", category: "DockPreviews")
    private typealias Connection = @convention(c) () -> UInt32
    private typealias WindowSpaces = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias HotKey = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private typealias HotKeyEnabled = @convention(c) (Int32) -> Bool

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }
    }

    private static let connection = symbol("CGSMainConnectionID", Connection.self)
    private static let windowSpaces = symbol("CGSCopySpacesForWindows", WindowSpaces.self)
    private static let displaySpaces = symbol("CGSCopyManagedDisplaySpaces", Displays.self)
    private static let hotKey = symbol("CGSGetSymbolicHotKeyValue", HotKey.self)
    private static let hotKeyEnabled = symbol("CGSIsSymbolicHotKeyEnabled", HotKeyEnabled.self)

    private static func route(to id: CGWindowID) -> (distance: Int, visible: Set<UInt64>)? {
        guard let connection, let windowSpaces, let displaySpaces else { return nil }
        let server = connection()
        guard server != 0,
              let memberships = windowSpaces(server, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber],
              let topology = displaySpaces(server)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let rows = topology.map { display -> (spaces: [UInt64], current: UInt64?) in
            let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            let current = ((display["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
            return (spaces, current)
        }
        guard let distance = DockSpaceRoute.distance(targets: Set(memberships.map(\.uint64Value)), displays: rows) else { return nil }
        return (distance, Set(rows.compactMap(\.current)))
    }

    private static func move(right: Bool) -> Bool {
        let shortcut: Int32 = right ? 81 : 79
        guard let hotKey, let hotKeyEnabled, hotKeyEnabled(shortcut), AXIsProcessTrusted() else { return false }
        var options: UInt32 = 0, key: UInt32 = 0, modifiers: UInt32 = 0
        guard hotKey(shortcut, &options, &key, &modifiers) == .success, key <= UInt16.max else { return false }
        let flags = DockSpaceRoute.shortcutFlags(modifiers)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: down) else { return false }
            event.flags = flags
            DesktopAutomationService.post(event)
        }
        return true
    }

    func resolve(pid: pid_t, windowID: CGWindowID?, known: AXUIElement?,
                 completion: @escaping (AXUIElement?) -> Void) {
        task?.cancel()
        task = Task {
            let result = await navigate(pid: pid, windowID: windowID, known: known)
            guard !Task.isCancelled else { return }
            completion(result)
        }
    }

    /// Awaitable variant for workflows which must finish focusing the window
    /// before executing the next action.
    func navigate(pid: pid_t, windowID: CGWindowID?, known: AXUIElement?) async -> AXUIElement? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let fronted = windowID.map { DockWindowCapture.front($0, pid: pid) } ?? false
        if !fronted { app.activate() }
        try? await Task.sleep(for: .milliseconds(180))
        if let windowID {
            var progress = DockSpaceProgress()
            for _ in 0..<12 {
                guard !Task.isCancelled else { return nil }
                guard let before = Self.route(to: windowID) else {
                    logger.notice("Window Space route unavailable")
                    DiagnosticJournal.shared.record("Window Space", "Route unavailable")
                    break
                }
                if before.distance == 0 {
                    DiagnosticJournal.shared.record("Window Space", "Target Space is already visible")
                    break
                }
                guard progress.accept(visible: before.visible, distance: before.distance) else {
                    DiagnosticJournal.shared.record("Window Space", "Stopped because navigation was not progressing")
                    break
                }
                DiagnosticJournal.shared.record("Window Space", "Navigating by \(before.distance) Spaces")
                logger.notice("Selected window is \(abs(before.distance)) Spaces away")
                guard Self.move(right: before.distance > 0) else {
                    logger.notice("Space shortcut is unavailable or disabled")
                    break
                }
                var changed = false
                // Wait for macOS to settle rather than sending a burst of arrows.
                for _ in 0..<24 {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return nil }
                    if let after = Self.route(to: windowID), after.visible != before.visible {
                        changed = true
                        break
                    }
                }
                if !changed {
                    logger.notice("Space move did not change the visible Space")
                    DiagnosticJournal.shared.record("Window Space", "Shortcut did not change the visible Space")
                    break
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
        for _ in 0..<4 {
            guard !Task.isCancelled else { return nil }
            let windows: [DockAccessibleWindow] = await withCheckedContinuation { continuation in
                DockAccessibilityReader.queue.async {
                    continuation.resume(returning: DockAccessibilityReader.windows(for: pid))
                }
            }
            guard !Task.isCancelled else { return nil }
            let exact = windowID.flatMap { id in windows.first { $0.windowID == id }?.element }
                ?? (windowID == nil ? known : nil)
            if let exact { logger.notice("Resolved exact selected window after Space navigation"); return exact }
            try? await Task.sleep(for: .milliseconds(150))
        }
        logger.notice("Selected window could not be resolved after navigation")
        return nil
    }
}
