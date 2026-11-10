import AppKit
import Carbon
import ApplicationServices
import OSLog

/// A bounded, in-memory event filter. Typed text is never persisted or logged.
@MainActor
final class InputAutomationMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var automations: [SavedAutomation] = []
    private var textBuffer = TextTriggerBuffer()
    private var lastTextTarget: AXUIElement?
    private var activeRemaps: [Int: KeyboardShortcutDefinition] = [:]
    private var consumedKeys = Set<Int>()
    private var lastApp: pid_t = 0
    private var gesture = TouchpadGesture()
    private var lastGestureDiagnostic = Date.distantPast
    private var expansionTask: Task<Void, Never>?
    private var finderCutEnabled = false
    #if !MODULAR_FEATURES
    private var finderCutChangeCount: Int?
    #endif
    private var finderCutComponent: FeatureFinderCut?
    private let logger = Logger(subsystem: "land.nithi.autoproductive", category: "TextTriggers")
    private var textState = ""
    private var activationObserver: NSObjectProtocol?
    private var preparedTextApplications = Set<pid_t>()
    var isRecording = false
    private(set) var needsPermissionRetry = false

    func sync(_ values: [SavedAutomation], finderCutEnabled: Bool = false) throws {
        stop()
        needsPermissionRetry = false
        self.finderCutEnabled = finderCutEnabled
        var toolError: Error?
        if finderCutEnabled {
            do {
                if let bytes = try FeatureComponentDispatcher.toolBytes(id: "tool.finderCut") {
                    finderCutComponent = try FeatureFinderCut(verifiedBytes: bytes)
                } else {
                    #if MODULAR_FEATURES
                    self.finderCutEnabled = false
                    #endif
                }
            } catch FeatureComponentDispatcher.DispatchError.missingComponent {
                // Removing this optional tool must not stop unrelated triggers.
                self.finderCutEnabled = false
            } catch {
                self.finderCutEnabled = false
                toolError = error
            }
        }
        automations = values.filter { value in
            guard let flow = value.workflow, flow.isEnabled else { return false }
            return [WorkflowTrigger.textExpansion, .keyRemap, .touchpad].contains(where: { flow.uses($0) })
        }
        guard !automations.isEmpty || self.finderCutEnabled else {
            if let toolError { throw toolError }
            return
        }
        needsPermissionRetry = true
        try DesktopAutomationService.requireAccessibility()
        guard CGPreflightListenEventAccess() else {
            needsPermissionRetry = true
            throw WorkflowError.invalid("Allow AutoProductive in System Settings → Privacy & Security → Input Monitoring before Text Triggers, remaps, or touchpad shortcuts can run.")
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<InputAutomationMonitor>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw WorkflowError.invalid("The input monitor could not start. Check \(DesktopAutomationService.controlPermissionName) and Input Monitoring permissions, then enable the trigger again.")
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        needsPermissionRetry = false
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareTextApplication() }
        }
        prepareTextApplication()
        if let toolError { throw toolError }
    }

    func stopExpansion() { expansionTask?.cancel(); expansionTask = nil }

    func stop() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        preparedTextApplications.removeAll()
        stopExpansion()
        finderCutComponent?.reset()
        finderCutComponent = nil
        #if !MODULAR_FEATURES
        finderCutChangeCount = nil
        #endif
        for key in activeRemaps.values {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key.keyCode), keyDown: false) {
                event.flags = DesktopAutomationService.flags(for: key.modifiers)
                DesktopAutomationService.post(event)
            }
        }
        activeRemaps.removeAll(); consumedKeys.removeAll(); clearTypedContext()
        gesture.reset()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            clearTypedContext(); return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == DesktopAutomationService.syntheticEventTag { return Unmanaged.passUnretained(event) }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isMouse = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].contains(type)
        let inputID = isMouse ? 1000 + Int(event.getIntegerValueField(.mouseEventButtonNumber)) : code
        let up = [.keyUp, .leftMouseUp, .rightMouseUp, .otherMouseUp].contains(type)
        // Always finish an existing remap even if focus/modifiers changed while held.
        if up, let destination = activeRemaps.removeValue(forKey: inputID) {
            emitRemap(destination, down: false); return nil
        }
        if type == .keyUp, consumedKeys.remove(code) != nil { return nil }
        guard !isRecording, !IsSecureEventInputEnabled() else { clearTypedContext(); return Unmanaged.passUnretained(event) }
        let app = NSWorkspace.shared.frontmostApplication
        if finderCutEnabled, type == .keyDown,
           let app, app.bundleIdentifier == "com.apple.finder",
           !isEditableFinderField(in: app),
           event.flags.contains(.maskCommand),
           !event.flags.contains(.maskAlternate),
           !event.flags.contains(.maskControl),
           !event.flags.contains(.maskShift) {
            let component = finderCutComponent
            let decision: Int
            if let component {
                let count = code == 9 && component.hasPendingCut ? NSPasteboard.general.changeCount : 0
                let shouldInspect = code == 9 && component.matches(changeCount: count)
                decision = component.decide(key: code,
                    changeCount: count,
                    hasFiles: shouldInspect && Self.pasteboardHasFiles)
            } else {
                #if MODULAR_FEATURES
                decision = 0
                #else
                if code == 7 {
                    finderCutChangeCount = nil; decision = 1
                } else if code == 9, let count = finderCutChangeCount,
                          count == NSPasteboard.general.changeCount, Self.pasteboardHasFiles {
                    finderCutChangeCount = nil; decision = 2
                } else {
                    if code == 8 { finderCutChangeCount = nil }
                    decision = 0
                }
                #endif
            }
            if decision == 1 && code == 7 { // Command-X copies Finder's selected files and marks this clipboard generation for moving.
                consumedKeys.insert(code)
                DispatchQueue.main.async {
                    try? DesktopAutomationService.press(.init(keyCode: 8, keyLabel: "C", modifiers: .command))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let hasFiles = Self.pasteboardHasFiles
                        let count = NSPasteboard.general.changeCount
                        if let component { component.mark(changeCount: count, hasFiles: hasFiles) }
                        else {
                            #if !MODULAR_FEATURES
                            self.finderCutChangeCount = hasFiles ? count : nil
                            #endif
                        }
                    }
                }
                return nil
            }
            if decision == 2 && code == 9 {
                consumedKeys.insert(code)
                DispatchQueue.main.async {
                    try? DesktopAutomationService.press(.init(keyCode: 9, keyLabel: "V", modifiers: [.command, .option]))
                }
                return nil
            }
        }
        if lastApp != app?.processIdentifier { clearTypedContext(); lastApp = app?.processIdentifier ?? 0 }
        let eligible = automations.filter {
            AppScope.allows(app?.bundleIdentifier, selected: $0.workflow?.scopedAppBundleIdentifiers ?? $0.scopedAppBundleIdentifiers)
        }
        let modifiers = Self.modifiers(event.flags)
        if !up, type != .scrollWheel, let mapping = eligible.first(where: { automation in
            guard let flow = automation.workflow, flow.uses(.keyRemap) else { return false }
            if isMouse { return flow.mouseButton == inputID - 1000 }
            return flow.inputKey?.keyCode == UInt32(code) && flow.inputKey?.modifiers == modifiers
        }), let destination = mapping.workflow?.steps.first?.key {
            activeRemaps[inputID] = destination
            emitRemap(destination, down: true); clearTypedContext(); return nil
        }
        if type == .scrollWheel {
            guard let scroll = NSEvent(cgEvent: event), scroll.hasPreciseScrollingDeltas else {
                return Unmanaged.passUnretained(event)
            }
            let candidates = eligible.filter { $0.workflow?.uses(.touchpad) == true && $0.workflow?.gestureModifiers == modifiers && !modifiers.isEmpty }
            guard !candidates.isEmpty else { gesture.reset(); return Unmanaged.passUnretained(event) }
            let direction = gesture.update(x: scroll.scrollingDeltaX, y: scroll.scrollingDeltaY,
                                           inverted: scroll.isDirectionInvertedFromDevice,
                                           modifiers: modifiers, time: scroll.timestamp,
                                           began: scroll.phase.contains(.began),
                                           ended: !scroll.phase.intersection([.ended, .cancelled]).isEmpty,
                                           momentum: !scroll.momentumPhase.isEmpty)
            if let direction {
                if let automation = candidates.first(where: { $0.workflow?.gesture == direction }) {
                    DiagnosticJournal.shared.record("Touchpad", "Matched configured swipe")
                    Task { WorkflowEngine.shared.start(automation) }
                } else if Date().timeIntervalSince(lastGestureDiagnostic) > 10 {
                    lastGestureDiagnostic = Date()
                    DiagnosticJournal.shared.record("Touchpad", "Modified swipe direction did not match: \(direction)")
                }
            }
            // Reserve this modifier combination during the swipe, including
            // momentum, rather than allowing the same gesture to scroll a page.
            return nil
        }
        if isMouse { clearTypedContext(); return Unmanaged.passUnretained(event) }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard modifiers.intersection([.command, .option, .control]).isEmpty else {
            clearTypedContext(); return Unmanaged.passUnretained(event)
        }
        let textTriggers = eligible.filter { $0.workflow?.uses(.textExpansion) == true }
        guard !textTriggers.isEmpty, let app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let textTarget = focusedEditableTextElement(in: app) else {
            clearTypedContext()
            return Unmanaged.passUnretained(event)
        }
        reportTextState("listening in an editable field")
        if let lastTextTarget, !CFEqual(lastTextTarget, textTarget) { textBuffer.clear() }
        lastTextTarget = textTarget
        // A plain Backspace edits the same bounded phrase context. Navigation,
        // modified deletion, focus changes and mouse clicks still invalidate it.
        if code == 51 {
            textBuffer.deleteBackward()
            return Unmanaged.passUnretained(event)
        }
        guard let characters = NSEvent(cgEvent: event)?.characters, !characters.isEmpty,
              !characters.unicodeScalars.contains(where: { $0.value >= 0xF700 && $0.value <= 0xF8FF }),
              ![117, 53].contains(code) else {
            clearTypedContext(); return Unmanaged.passUnretained(event)
        }
        for automation in textTriggers {
            guard let flow = automation.workflow else { continue }
            guard let matchedLength = TextTriggerMatcher.matchLength(
                buffered: textBuffer.text, characters: characters, phrase: flow.abbreviation,
                caseSensitive: flow.matchesCase, requiresDelimiter: flow.requiresDelimiter
            ) else { continue }
            let count = matchedLength - (flow.requiresDelimiter ? 0 : characters.count)
            reportTextState("matched a saved trigger")
            let insertsText = flow.steps.count == 1 && flow.steps[0].action == .typeText
            let deletePhrase = flow.shouldDeleteTriggerText
            let suppressCurrentKey = deletePhrase || insertsText
            if suppressCurrentKey { consumedKeys.insert(code) }
            clearTypedContext()
            expansionTask?.cancel()
            expansionTask = Task {
                do {
                    if deletePhrase || insertsText {
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                              let currentTarget = focusedEditableTextElement(in: app),
                              CFEqual(currentTarget, textTarget) else { return }
                    }
                    if deletePhrase {
                        for _ in 0..<max(0, count) { try DesktopAutomationService.press(.init(keyCode: 51, keyLabel: "Delete", modifiers: [])) }
                    }
                    if insertsText {
                        let template = flow.steps[0].text
                        let started = Date()
                        var variables = ["date": WorkflowText.dateString(started, utcOffset: flow.dateUTCOffset),
                                         "time": WorkflowText.timeString(started, utcOffset: flow.dateUTCOffset)]
                        if template.contains("{{clipboard}}") { variables["clipboard"] = NSPasteboard.general.string(forType: .string) ?? "" }
                        let replacement = WorkflowText.expand(template, variables: variables)
                        let output = deletePhrase
                            ? replacement + (flow.requiresDelimiter ? characters : "")
                            : characters + replacement
                        try await DesktopAutomationService.type(output)
                    } else {
                        WorkflowEngine.shared.start(automation)
                    }
                } catch is CancellationError { }
                catch { DiagnosticJournal.shared.recordError("InputAutomationMonitor", error); WorkflowEngine.shared.lastError = error.localizedDescription }
            }
            return suppressCurrentKey ? nil : Unmanaged.passUnretained(event)
        }
        textBuffer.append(characters)
        return Unmanaged.passUnretained(event)
    }

    private static var pasteboardHasFiles: Bool {
        NSPasteboard.general.pasteboardItems?.contains { $0.types.contains(.fileURL) } == true
    }

    private func isEditableFinderField(in app: NSRunningApplication) -> Bool {
        focusedEditableTextElement(in: app) != nil
    }

    private func clearTypedContext() {
        textBuffer.clear()
        lastTextTarget = nil
    }

    /// Fail closed when the focused app cannot identify an editable text target.
    private func focusedEditableTextElement(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        var fallbackResult: AXError?
        if focusResult != .success || focusedValue == nil {
            // Some native/web hosts don't publish focus on their application
            // element, although the system-wide focus element remains available.
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.05)
            var systemFocus: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &systemFocus)
            fallbackResult = result
            if result == .success,
               let systemFocus, CFGetTypeID(systemFocus) == AXUIElementGetTypeID() {
                let candidate = systemFocus as! AXUIElement
                var owner: pid_t = 0
                if AXUIElementGetPid(candidate, &owner) == .success,
                   owner == app.processIdentifier,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    focusedValue = systemFocus
                }
            }
        }
        guard let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            reportTextState("focused field unavailable (app \(focusResult.rawValue), system \(fallbackResult?.rawValue ?? 0))")
            return nil
        }
        let focused = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.05)
        guard !isSecureTextElement(focused) else { return nil }
        if isEditableTextElement(focused) { return focused }

        // Web-style editors may focus a child inside a contenteditable container.
        // The editable ancestor is explicit accessibility metadata, not a guess
        // based on the containing app or whether a key produced characters.
        var ancestorValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXEditableAncestorAttribute as CFString, &ancestorValue) == .success,
           let ancestorValue, CFGetTypeID(ancestorValue) == AXUIElementGetTypeID() {
            let ancestor = ancestorValue as! AXUIElement
            AXUIElementSetMessagingTimeout(ancestor, 0.05)
            if isSecureTextElement(ancestor) { return nil }
            if isEditableTextElement(ancestor) { return ancestor }
        }
        // Some web accessibility bridges focus a child and omit EditableAncestor.
        // Walk only its nearby parents, accepting explicit editable metadata or
        // a writable value; never search unrelated fields in the window.
        var child = focused
        for _ in 0..<6 {
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue, CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            let parent = parentValue as! AXUIElement
            if CFEqual(child, parent) { break }
            AXUIElementSetMessagingTimeout(parent, 0.05)
            if isSecureTextElement(parent) { return nil }
            if isEditableTextElement(parent) { return parent }
            child = parent
        }
        var focusedRole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &focusedRole)
        reportTextState("focused element is not an editable field (\(focusedRole as? String ?? "unknown role"))")
        return nil
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        var subroleValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success &&
            subroleValue as? String == kAXSecureTextFieldSubrole
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }
        func bool(_ attribute: String) -> Bool? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? Bool
        }
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXGroupRole, "AXWebArea"].contains(role) else { return false }
        var isSettable = DarwinBoolean(false)
        let valueSettable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable) == .success && isSettable.boolValue
        return EditableTextPolicy.allows(role: role, editable: bool(kAXIsEditableAttribute), valueSettable: valueSettable,
                                        readOnly: bool("AXReadOnly"), enabled: bool(kAXEnabledAttribute), secure: isSecureTextElement(element))
    }

    private func reportTextState(_ state: String) {
        guard state != textState else { return }
        textState = state
        // State only: no typed text, field contents, app names or trigger names.
        logger.notice("Text trigger state: \(state, privacy: .public)")
    }

    private func prepareTextApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              automations.contains(where: { $0.workflow?.uses(.textExpansion) == true &&
                  AppScope.allows(app.bundleIdentifier, selected: $0.workflow?.scopedAppBundleIdentifiers ?? $0.scopedAppBundleIdentifiers) }),
              !preparedTextApplications.contains(app.processIdentifier) else { return }
        if preparedTextApplications.count >= 32 { preparedTextApplications.removeAll() }
        preparedTextApplications.insert(app.processIdentifier)
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        // Electron exposes web fields lazily. Its documented assistive-client
        // handshake requests the tree before the first typed character arrives.
        // Unsupported native apps simply return attributeUnsupported.
        // https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md
        let result = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result == .success { reportTextState("web accessibility tree requested") }
    }

    private func emitRemap(_ destination: KeyboardShortcutDefinition, down: Bool) {
        if let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: CGKeyCode(destination.keyCode), keyDown: down) {
            event.flags = DesktopAutomationService.flags(for: destination.modifiers)
            DesktopAutomationService.post(event)
        }
    }

    private static func modifiers(_ flags: CGEventFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}
