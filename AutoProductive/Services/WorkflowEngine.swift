import AppKit
import Combine
import UserNotifications

@MainActor
final class WorkflowEngine: ObservableObject {
    static func openedFileWindowID(_ file: URL, pid: pid_t, windows: [[String: Any]]) -> CGWindowID? {
        let titles = Set([file.lastPathComponent, file.deletingPathExtension().lastPathComponent])
        let matches = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
            ($0[kCGWindowName as String] as? String).map(titles.contains) == true
        }
        guard matches.count == 1 else { return nil }
        return (matches[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }

    static let shared = WorkflowEngine()
    @Published private(set) var runningIDs = Set<UUID>()
    @Published var lastError: String?
    @Published private(set) var lastResult = ""
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var activeProcesses: [UUID: Process] = [:]
    private var activeDialogs: [UUID: WorkflowDialog] = [:]

    func start(_ automation: SavedAutomation) {
        guard automation.isEnabled, !runningIDs.contains(automation.id), let workflow = automation.workflow else { return }
        do { try workflow.validate() } catch {
            DiagnosticJournal.shared.recordError("Workflow validation", error)
            lastError = error.localizedDescription; return
        }
        lastError = nil
        runningIDs.insert(automation.id)
        DiagnosticJournal.shared.record("Workflow", "Started; actions=\(workflow.steps.count); repeat=\(workflow.repeatCount)")
        tasks[automation.id] = Task {
            defer { runningIDs.remove(automation.id); tasks[automation.id] = nil; activeProcesses[automation.id] = nil }
            do {
                var variables: [String: String] = ["date": ISO8601DateFormatter().string(from: .now)]
                for _ in 0..<workflow.repeatCount {
                    for step in workflow.steps {
                        try Task.checkCancellation()
                        if step.text.contains("{{clipboard}}") || step.secondaryText.contains("{{clipboard}}") || step.option.contains("{{clipboard}}") || step.text.contains("AUTOPRODUCTIVE_CLIPBOARD") {
                            variables["clipboard"] = NSPasteboard.general.string(forType: .string) ?? ""
                        }
                        DiagnosticJournal.shared.record("Action", step.action.rawValue)
                        try await execute(step, variables: &variables, id: automation.id)
                        try await Task.sleep(for: .milliseconds(1))
                    }
                }
                lastResult = "Finished \(automation.name)"
                DiagnosticJournal.shared.record("Workflow", "Finished")
            } catch is CancellationError { lastResult = "Stopped \(automation.name)" }
            catch {
                lastError = "\(automation.name): \(error.localizedDescription)"
                DiagnosticJournal.shared.recordError("Workflow", error)
            }
        }
    }

    func stop(_ id: UUID) {
        tasks[id]?.cancel()
        activeDialogs[id]?.cancel()
        if let process = activeProcesses[id], process.isRunning { process.terminate() }
    }

    func stopAll() { for id in Array(tasks.keys) { stop(id) } }

    private func execute(_ original: WorkflowStep, variables: inout [String: String], id: UUID) async throws {
        var step = original
        try FeatureComponentDispatcher.requireAction(id: step.action.packageID, title: step.action.title)
        if step.action == .composeMail { step.option = WorkflowText.expand(step.option, variables: variables) }
        if ![WorkflowAction.shell, .appleScript].contains(step.action) { step.text = WorkflowText.expand(step.text, variables: variables) }
        step.secondaryText = WorkflowText.expand(step.secondaryText, variables: variables)
        #if !MODULAR_FEATURES
        let files = FileManager.default
        #endif
        func url(_ path: String) throws -> URL {
            guard !path.isEmpty else { throw WorkflowError.invalid("Choose a file or folder path.") }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        switch step.action {
        case .adjustSound:
            if try await !FeatureComponentDispatcher.adjustSystem(action: "adjustSound", option: step.option, amount: step.amount) {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try SystemControlService.adjustSound(step)
                #endif
            }
        case .adjustBrightness:
            if try await !FeatureComponentDispatcher.adjustSystem(action: "adjustBrightness", option: step.option, amount: step.amount) {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try SystemControlService.adjustBrightness(step)
                #endif
            }
        case .typeText:
            let request = FeatureComponentDispatcher.InputRequest(text: step.text)
            if let plan = try await FeatureComponentDispatcher.inputPlan(action: "typeText", request: request) {
                try await FeatureInputPlayer.play(plan)
            } else { try await DesktopAutomationService.type(step.text) }
        case .pressKey:
            if let key = step.key {
                let request = FeatureComponentDispatcher.InputRequest(keyCode: key.keyCode, modifiers: key.modifiers.rawValue)
                if let plan = try await FeatureComponentDispatcher.inputPlan(action: "pressKey", request: request) {
                    try await FeatureInputPlayer.play(plan)
                } else { try DesktopAutomationService.press(key) }
            }
        case .click, .movePointer:
            let screen = NSScreen.screens.first
            if step.coordinatesInPixels == true, screen == nil { throw WorkflowError.invalid("No display is available for the pixel click.") }
            let request = FeatureComponentDispatcher.InputRequest(x: step.x, y: step.y, button: step.option,
                coordinatesInPixels: step.coordinatesInPixels, displayScale: screen.map { Double($0.backingScaleFactor) },
                displayWidth: screen.map { Double($0.frame.width) }, displayHeight: screen.map { Double($0.frame.height) })
            if let plan = try await FeatureComponentDispatcher.inputPlan(action: step.action.rawValue, request: request) {
                try await FeatureInputPlayer.play(plan)
            } else { try DesktopAutomationService.pointer(step) }
        case .scroll:
            let request = FeatureComponentDispatcher.InputRequest(x: step.x, y: step.y)
            if let plan = try await FeatureComponentDispatcher.inputPlan(action: "scroll", request: request) {
                try await FeatureInputPlayer.play(plan)
            } else {
                try DesktopAutomationService.requireAccessibility()
                if let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .privateState), units: .pixel, wheelCount: 2, wheel1: Int32(max(-10000, min(10000, step.y))), wheel2: Int32(max(-10000, min(10000, step.x))), wheel3: 0) { DesktopAutomationService.post(event) }
            }
        case .wait: try await FeatureComponentDispatcher.wait(step.duration)
        case .openURL:
            let prepared = try await FeatureComponentDispatcher.openTarget(action: "openURL", value: step.text)
            guard let value = prepared ?? URL(string: step.text), ["https", "http", "file"].contains(value.scheme?.lowercased() ?? "") else {
                throw WorkflowError.invalid("Enter a valid https, http or file URL.")
            }
            try Task.checkCancellation()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let opened = try await NSWorkspace.shared.open(value, configuration: configuration)
            opened.activate()
            if value.isFileURL, AXIsProcessTrusted() {
                // AX can omit windows on another Space. Use the window-server
                // inventory only when the opened app has one unambiguous title
                // for this file, then use the same navigation as Dock previews.
                for _ in 0..<8 {
                    try Task.checkCancellation()
                    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                    if let id = Self.openedFileWindowID(value, pid: opened.processIdentifier, windows: windows) {
                        if let window = await DockSpaceNavigation.shared.navigate(pid: opened.processIdentifier, windowID: id, known: nil) {
                            let raised: Bool = await withCheckedContinuation { continuation in
                                DockAccessibilityReader.raise(window, pid: opened.processIdentifier) { continuation.resume(returning: $0) }
                            }
                            let fronted = DockWindowCapture.front(id, pid: opened.processIdentifier)
                            let activated = opened.activate()
                            DiagnosticJournal.shared.record("Opened window", "Raise=\(raised); front=\(fronted); activation requested=\(activated)")
                        } else {
                            DiagnosticJournal.shared.record("Opened window", "Could not resolve the selected window after Space navigation")
                        }
                        break
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
        case .openApp:
            let prepared = try await FeatureComponentDispatcher.openTarget(action: "openApp", value: step.text)
            let application = try prepared ?? url(step.text)
            try Task.checkCancellation()
            _ = try await NSWorkspace.shared.openApplication(at: application, configuration: .init())
        case .composeMail:
            let prepared = try await FeatureComponentDispatcher.openTarget(action: "composeMail", value: step.text, subject: step.option, body: step.secondaryText)
            var components = URLComponents()
            components.scheme = "mailto"; components.path = step.text
            components.queryItems = [URLQueryItem(name: "subject", value: step.option), URLQueryItem(name: "body", value: step.secondaryText)]
            guard let target = prepared ?? components.url else { throw WorkflowError.invalid("The email draft could not be created.") }
            try Task.checkCancellation()
            guard NSWorkspace.shared.open(target) else { throw WorkflowError.invalid("The email draft could not be created.") }
        case .window: try await DesktopAutomationService.arrangeWindow(step)
        case .setClipboard:
            if try await !FeatureComponentDispatcher.setClipboard(step.text) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(step.text, forType: .string)
            }
        case .transformClipboard:
            let transformed = try await FeatureComponentDispatcher.transformClipboard(NSPasteboard.general.string(forType: .string) ?? "", using: step.option)
            try Task.checkCancellation()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(transformed, forType: .string)
        case .pasteClipboard:
            if let plan = try await FeatureComponentDispatcher.inputPlan(action: "pasteClipboard", request: .init()) {
                try await FeatureInputPlayer.play(plan)
            } else { try DesktopAutomationService.press(.init(keyCode: 9, keyLabel: "V", modifiers: .command)) }
        case .readFile:
            if let value = try await FeatureComponentDispatcher.readFile(step.text) {
                variables["file"] = value
            } else {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                let file = try url(step.text)
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20 * 1024 * 1024 else { throw WorkflowError.invalid("Text-file reads are limited to 20 MB.") }
                variables["file"] = try String(contentsOf: file, encoding: .utf8)
                #endif
            }
        case .writeFile:
            if try await !FeatureComponentDispatcher.mutateFile(action: "writeFile", path: step.text, text: step.secondaryText) {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try step.secondaryText.write(to: url(step.text), atomically: true, encoding: .utf8)
                #endif
            }
        case .appendFile:
            if try await !FeatureComponentDispatcher.mutateFile(action: "appendFile", path: step.text, text: step.secondaryText) {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                let file = try url(step.text)
                if !files.fileExists(atPath: file.path) { try Data().write(to: file) }
                let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: Data(step.secondaryText.utf8))
                #endif
            }
        case .copyFile:
            if try await !FeatureComponentDispatcher.mutateFile(action: "copyFile", path: step.text, text: step.secondaryText) {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try files.copyItem(at: url(step.text), to: url(step.secondaryText))
                #endif
            }
        case .moveFile:
            if try await !FeatureComponentDispatcher.mutateFile(action: "moveFile", path: step.text, text: step.secondaryText) {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try files.moveItem(at: url(step.text), to: url(step.secondaryText))
                #endif
            }
        case .createFolder:
            if try await !FeatureComponentDispatcher.mutateFile(action: "createFolder", path: step.text, text: "") {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try files.createDirectory(at: url(step.text), withIntermediateDirectories: true)
                #endif
            }
        case .trashFile:
            if try await !FeatureComponentDispatcher.mutateFile(action: "trashFile", path: step.text, text: "") {
                #if MODULAR_FEATURES
                throw FeatureComponentDispatcher.DispatchError.missingComponent(step.action.title)
                #else
                try files.trashItem(at: url(step.text), resultingItemURL: nil)
                #endif
            }
        case .shell, .appleScript:
            let plan = try await FeatureComponentDispatcher.scriptPlan(action: step.action.rawValue, script: step.text)
            try Task.checkCancellation()
            variables["output"] = try await runProcess(step, variables: variables, id: id, plan: plan)
        case .notification:
            let plan = try await FeatureComponentDispatcher.dialogPlan(action: "notification", title: step.text, details: step.secondaryText)
            let center = UNUserNotificationCenter.current()
            let permitted = try await center.requestAuthorization(options: [.alert, .sound])
            guard permitted else { throw WorkflowError.invalid("Allow notifications for AutoProductive in System Settings to use this action.") }
            try Task.checkCancellation()
            let content = UNMutableNotificationContent()
            content.title = plan?.title ?? (step.text.isEmpty ? "AutoProductive" : step.text)
            content.body = plan?.details ?? step.secondaryText
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: "autoproductive.workflow.\(UUID().uuidString)", content: content, trigger: nil))
        case .prompt, .choose, .message:
            let plan = try await FeatureComponentDispatcher.dialogPlan(action: step.action.rawValue, title: step.text, details: step.secondaryText)
            try Task.checkCancellation()
            let alert = NSAlert(); alert.messageText = plan?.title ?? (step.text.isEmpty ? "AutoProductive" : step.text)
            alert.informativeText = plan?.details ?? step.secondaryText
            let field = NSTextField(string: ""); field.frame.size = NSSize(width: 320, height: 26)
            if step.action == .prompt { alert.accessoryView = field }
            var choices: [String] = []
            if step.action == .choose {
                choices = plan?.choices ?? step.secondaryText.components(separatedBy: .newlines).filter { !$0.isEmpty }
                guard !choices.isEmpty && choices.count <= 5 else { throw WorkflowError.invalid("A menu needs 1–5 choices, one per line.") }
                alert.informativeText = "Choose an option."
                choices.forEach { alert.addButton(withTitle: $0) }
            } else { alert.addButton(withTitle: "Continue") }
            alert.addButton(withTitle: "Cancel")
            let dialog = WorkflowDialog()
            activeDialogs[id] = dialog
            defer { activeDialogs[id] = nil }
            let response = await dialog.present(alert, input: step.action == .prompt ? field : nil)
            try Task.checkCancellation()
            let count = step.action == .choose ? choices.count : 1
            guard response >= 0 && response < count else { throw CancellationError() }
            if step.action == .prompt { variables["input"] = field.stringValue }
            if step.action == .choose { variables["choice"] = choices[response] }
        case .screenPixel, .screenImage:
            let plan = try await FeatureComponentDispatcher.screenWaitPlan(action: step.action.rawValue, duration: step.duration)
            let deadline = Date().addingTimeInterval(plan?.duration ?? step.duration)
            while !(try await DesktopAutomationService.screenMatches(step)) {
                try Task.checkCancellation()
                guard Date() < deadline else { throw WorkflowError.invalid("The screen condition did not match before its timeout.") }
                try await Task.sleep(for: .seconds(plan?.pollInterval ?? 0.3))
            }
        }
    }

    private func runProcess(_ step: WorkflowStep, variables: [String: String], id: UUID, plan: FeatureComponentDispatcher.ScriptPlan? = nil) async throws -> String {
        // Use temporary files rather than pipes, so a verbose process cannot deadlock.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close(); try? FileManager.default.removeItem(at: outputURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan?.executable ?? (step.action == .appleScript ? "/usr/bin/osascript" : "/bin/zsh"))
        // Scripts are the explicit contents of a saved action; variable values are environment data.
        process.arguments = plan?.arguments ?? (step.action == .appleScript ? ["-e", step.text] : ["-c", step.text])
        process.environment = ProcessInfo.processInfo.environment.merging(Dictionary(uniqueKeysWithValues: variables.map { ("AUTOPRODUCTIVE_" + $0.key.uppercased(), $0.value) })) { _, new in new }
        process.standardOutput = output; process.standardError = output
        activeProcesses[id] = process
        try process.run()
        let deadline = Date().addingTimeInterval(max(1, step.duration))
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                for _ in 0..<10 where process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                if Task.isCancelled { throw CancellationError() }
                throw WorkflowError.invalid("The script exceeded its timeout.")
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
        let text = String(decoding: data.prefix(1_048_576), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw WorkflowError.invalid("Script exited with code \(process.terminationStatus): \(text.prefix(500))") }
        return text
    }
}

/// A key-capable auxiliary panel asks for input without activating the app's
/// main window or moving the user out of their current full-screen Space.
@MainActor
private final class WorkflowDialog: NSObject, NSWindowDelegate {
    private var alert: NSAlert?
    private var panel: WorkflowDialogPanel?
    private var continuation: CheckedContinuation<Int, Never>?

    func present(_ alert: NSAlert, input: NSTextField?) async -> Int {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.alert = alert
            alert.layout()
            let panel = WorkflowDialogPanel(contentRect: alert.window.frame,
                                            styleMask: [.titled, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.contentView = alert.window.contentView
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.level = .modalPanel
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            for (index, button) in alert.buttons.enumerated() {
                button.tag = index
                button.target = self
                button.action = #selector(choose(_:))
            }
            alert.buttons.first?.keyEquivalent = "\r"
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            self.panel = panel
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                            y: frame.midY - panel.frame.height / 2))
            }
            if let input { panel.initialFirstResponder = input }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func choose(_ sender: NSButton) { finish(sender.tag) }
    func cancel() { finish(-1) }
    func windowWillClose(_ notification: Notification) { cancel() }

    private func finish(_ response: Int) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        alert = nil
        continuation.resume(returning: response)
    }
}

private final class WorkflowDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
