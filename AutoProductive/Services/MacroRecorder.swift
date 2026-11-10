import AppKit
import Carbon
import Observation

@Observable @MainActor
final class MacroRecorder {
    private(set) var isRecording = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buffer = MacroRecordingBuffer()

    func start() throws {
        guard InputMonitoringSettings.allowsInput() else {
            throw WorkflowError.invalid("Turn on Input monitoring in the robot menu before using input capture.")
        }
        guard !AutomationCaptureCoordination.isRecording || isRecording else {
            throw WorkflowError.invalid("Finish the current screen selection before recording keys and clicks.")
        }
        finishRecording()
        try DesktopAutomationService.requireAccessibility()
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        guard CGPreflightListenEventAccess() else { throw WorkflowError.invalid("Enable AutoProductive in Input Monitoring settings, then start recording again.") }
        buffer = MacroRecordingBuffer()
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            if let info {
                MainActor.assumeIsolated {
                    Unmanaged<MacroRecorder>.fromOpaque(info).takeUnretainedValue().receive(type, event)
                }
            }
            // This is a passive listener: never replace, consume, or repost a key.
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                         options: .listenOnly, eventsOfInterest: mask, callback: callback,
                                         userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw WorkflowError.invalid("The recorder could not start. Check Input Monitoring access, then try again.")
        }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRecording = true
        WorkflowEngine.shared.stopAll()
        AutomationCaptureCoordination.setRecording(true)
    }

    func stop() -> [WorkflowStep] {
        finishRecording()
        let result = buffer.actions; buffer = MacroRecordingBuffer(); return result
    }

    private func finishRecording() {
        let wasRecording = isRecording
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil; isRecording = false
        if wasRecording { AutomationCaptureCoordination.setRecording(false) }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isRecording, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard isRecording else { return }
        guard InputMonitoringSettings.allowsInput() else { finishRecording(); return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
        let targetWindow = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        let ownWindow = type != .keyDown && targetWindow > 0 && NSApp.windows.contains { Int64($0.windowNumber) == targetWindow }
        let isOwnEvent = targetPID == Int64(ownPID) || ownWindow
            || (targetPID == 0 && NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID)
        if buffer.observe(event, isOwnEvent: isOwnEvent, secureInput: IsSecureEventInputEnabled(),
                          playbackTag: DesktopAutomationService.syntheticEventTag) { finishRecording() }
    }
}
