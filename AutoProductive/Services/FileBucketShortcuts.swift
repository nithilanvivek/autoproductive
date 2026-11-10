import AppKit
import Carbon
import Combine

@MainActor
final class FileBucketShortcuts: ObservableObject {
    static let shared = FileBucketShortcuts()
    @Published private(set) var settings = FileBucketShortcutSettings.load()
    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("FileBucketShortcuts", errorMessage)
            }
        }
    }
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var recordingObserver: NSObjectProtocol?
    private var inputMonitoringObserver: NSObjectProtocol?
    private var selectionTask: Task<Void, Never>?
    private var started = false
    private static let signature: OSType = 0x41555042 // AUPB

    var assignedShortcuts: [KeyboardShortcutDefinition] {
        [settings.openEnabled ? settings.open : nil, settings.addEnabled ? settings.add : nil].compactMap { $0 }
    }

    func start() {
        guard !started else { return }
        started = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<FileBucketShortcuts>.fromOpaque(data).takeUnretainedValue().handle(event)
            }
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        recordingObserver = NotificationCenter.default.addObserver(forName: .automationRecordingChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
        inputMonitoringObserver = NotificationCenter.default.addObserver(forName: .inputMonitoringChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
        register()
    }

    func update(_ value: FileBucketShortcutSettings) {
        settings = value
        value.save()
        errorMessage = nil
        register()
    }

    private func register() {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll()
        guard InputMonitoringSettings.allowsInput(), !AutomationCaptureCoordination.isRecording else { return }
        for (id, shortcut) in [(UInt32(1), settings.openEnabled ? settings.open : nil), (UInt32(2), settings.addEnabled ? settings.add : nil)] {
            guard let shortcut else { continue }
            var flags: UInt32 = 0
            if shortcut.modifiers.contains(.command) { flags |= UInt32(cmdKey) }
            if shortcut.modifiers.contains(.option) { flags |= UInt32(optionKey) }
            if shortcut.modifiers.contains(.control) { flags |= UInt32(controlKey) }
            if shortcut.modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.keyCode, flags, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
            if result == noErr, let reference { references.append(reference) }
            else { errorMessage = "The File Bucket shortcut \(shortcut.displayText) is already in use. Record another combination." }
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var key = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr,
              key.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        guard InputMonitoringSettings.allowsInput(), !AutomationCaptureCoordination.isRecording else { return noErr }
        DispatchQueue.main.async { [weak self] in
            if key.id == 1 { MenuBarController.shared.close(); FileBucket.shared.toggleWindow() }
            else if key.id == 2 { self?.addFinderSelection() }
        }
        return noErr
    }

    private func addFinderSelection() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        guard selectionTask == nil else { return }
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let permitted = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
        if permitted { readFinderSelection() }
        else {
            PermissionExplanationPresenter.shared.present(title: "Copy Finder selections to File Bucket",
                message: "AutoProductive needs Automation access to Finder to get the files and folders you select when you press this shortcut. It copies those items into File Bucket. Continue lets macOS ask for Finder access.") { [weak self] accepted in
                    if accepted { self?.readFinderSelection() }
                }
        }
    }

    private func readFinderSelection() {
        selectionTask = Task {
            defer { selectionTask = nil }
            do {
                let urls = try await FinderSelectionReader.selectedURLs()
                guard !urls.isEmpty else { throw WorkflowError.invalid("Select files or folders in Finder first.") }
                FileBucket.shared.importURLs(urls)
                errorMessage = nil
            } catch { DiagnosticJournal.shared.recordError("FileBucketShortcuts", error); errorMessage = error.localizedDescription }
            MenuBarController.shared.close()
            FileBucket.shared.showWindow()
        }
    }
}

private enum FinderSelectionReader {
    static func selectedURLs() async throws -> [URL] {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close(); try? FileManager.default.removeItem(at: outputURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Fixed script, JSON transport: spaces, quotes, Unicode and newlines in
        // filenames are data. No selection is copied through the clipboard.
        process.arguments = ["-l", "JavaScript", "-e", "JSON.stringify(Application('Finder').selection().map(item => item.url()))"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                throw WorkflowError.invalid("Finder did not respond. Try the shortcut again.")
            }
            try await Task.sleep(for: .milliseconds(75))
        }
        guard process.terminationStatus == 0 else { throw WorkflowError.invalid("Could not read Finder’s selection. Allow AutoProductive to control Finder in Privacy & Security → Automation, then try again.") }
        return try FileBucketShortcutSettings.selectionURLs(from: Data(contentsOf: outputURL))
    }
}
