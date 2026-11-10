import AppKit
import ApplicationServices
import Carbon

/// Exists only during an explicit Record action. Captures before system hotkeys
/// and ignores secure input, synthetic playback and input aimed at other apps.
@MainActor
final class KeyRecordingSession {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((NSEvent) -> Void)?
    private var canSuppress = false

    func start(handler: @escaping (NSEvent) -> Void) -> Bool {
        stop()
        guard CGPreflightListenEventAccess() else { return false }
        self.handler = handler
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<KeyRecordingSession>.fromOpaque(info).takeUnretainedValue().receive(type, event)
            }
        }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        // Accessibility permits consuming the key so a screenshot shortcut does
        // not also open the screenshot tool. Input Monitoring alone still records.
        let options: [CGEventTapOptions] = AXIsProcessTrusted() ? [.defaultTap, .listenOnly] : [.listenOnly]
        for option in options {
            for location: CGEventTapLocation in [.cghidEventTap, .cgSessionEventTap] {
                if let tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap,
                                          options: option, eventsOfInterest: mask,
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) {
                    self.tap = tap
                    canSuppress = option == .defaultTap
                    break
                }
            }
            if tap != nil { break }
        }
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { stop(); return false }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil; handler = nil
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, let handler,
              NSApp.isActive || NSApp.windows.contains(where: \.isKeyWindow),
              !IsSecureEventInputEnabled(),
              event.getIntegerValueField(.eventSourceUserData) != DesktopAutomationService.syntheticEventTag,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              let key = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        handler(key)
        return canSuppress ? nil : Unmanaged.passUnretained(event)
    }
}
