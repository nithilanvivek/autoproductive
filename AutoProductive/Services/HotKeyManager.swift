import Carbon
import Foundation
import AppKit
import Combine

@MainActor
final class HotKeyManager: ObservableObject {
    private var eventHandler: EventHandlerRef?
    private var hotKeyReferences: [EventHotKeyRef] = []
    private var automationByHotKeyID: [UInt32: SavedAutomation] = [:]
    private var currentAutomations: [SavedAutomation] = []
    private var recordingObserver: NSObjectProtocol?
    private var isRecording = false
    private var emergencyEnabled = true

    func setRecording(_ recording: Bool) {
        isRecording = recording
        sync(with: currentAutomations, includeEmergency: emergencyEnabled)
    }

    init() {
        installEventHandler()
        recordingObserver = NotificationCenter.default.addObserver(forName: .automationRecordingChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isRecording = note.object as? Bool ?? false
                self.sync(with: self.currentAutomations, includeEmergency: self.emergencyEnabled)
            }
        }
    }

    deinit {
        hotKeyReferences.forEach { UnregisterEventHotKey($0) }
        if let recordingObserver { NotificationCenter.default.removeObserver(recordingObserver) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func sync(with automations: [SavedAutomation], includeEmergency: Bool = true) {
        unregisterAll()
        currentAutomations = automations
        emergencyEnabled = includeEmergency
        if includeEmergency {
            var reference: EventHotKeyRef?
            if RegisterEventHotKey(47, UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: Self.signature, id: UInt32.max), GetApplicationEventTarget(), 0, &reference) == noErr,
               let reference { hotKeyReferences.append(reference) }
        }
        guard !isRecording else { return }

        let configured = automations.filter { $0.keyboardShortcut != nil }

        for (index, automation) in configured.enumerated() {
            guard let shortcut = automation.keyboardShortcut else { continue }

            let hotKeyID = UInt32(index + 1)
            let carbonID = EventHotKeyID(
                signature: Self.signature,
                id: hotKeyID
            )
            var reference: EventHotKeyRef?

            let status = RegisterEventHotKey(
                shortcut.keyCode,
                carbonModifiers(for: shortcut.modifiers),
                carbonID,
                GetApplicationEventTarget(),
                UInt32(kEventHotKeyExclusive),
                &reference
            )

            if status == noErr, let reference {
                hotKeyReferences.append(reference)
                automationByHotKeyID[hotKeyID] = automation
            } else {
                DiagnosticJournal.shared.recordErrorMessage("Hotkey", "Global shortcut registration failed; status=\(status)")
                WorkflowEngine.shared.lastError = "The shortcut for \(automation.name) could not be registered. Choose a different combination."
            }
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            return MainActor.assumeIsolated { manager.handle(event: event) }
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        if hotKeyID.id == UInt32.max {
            NotificationCenter.default.post(name: .automationPauseRequested, object: nil)
            return noErr
        }
        guard
              let automation = automationByHotKeyID[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async {
            let scopes = automation.workflow?.scopedAppBundleIdentifiers ?? automation.scopedAppBundleIdentifiers
            guard AppScope.allows(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, selected: scopes) else { return }
            do { try AutomationRunner.run(automation) }
            catch { DiagnosticJournal.shared.recordError("HotKeyManager", error); WorkflowEngine.shared.lastError = error.localizedDescription }
        }
        return noErr
    }

    private func unregisterAll() {
        hotKeyReferences.forEach { UnregisterEventHotKey($0) }
        hotKeyReferences.removeAll()
        automationByHotKeyID.removeAll()
    }

    private func carbonModifiers(for modifiers: ShortcutModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static let signature: OSType = 0x41555052 // "AUPR"
}
