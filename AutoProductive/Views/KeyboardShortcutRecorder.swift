import AppKit
import SwiftUI
import IOKit.hidsystem

struct KeyboardShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcutDefinition?
    let existingShortcuts: [KeyboardShortcutDefinition]
    var requiresModifiers = true
    var compact = false
    @State private var isRecording = false
    @State private var capture = KeyRecordingSession()
    @AppStorage("inputMonitoringEnabled.v1") private var inputMonitoringEnabled = true
    @AppStorage("automationPaused.v1") private var automationPaused = false
    @State private var recordingError: String? {
        didSet {
            if let recordingError, recordingError != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("KeyboardShortcutRecorder", recordingError)
            }
        }
    }
    @State private var rating: ShortcutRating?
    @ObservedObject private var bucketShortcuts = FileBucketShortcuts.shared
    private var conflictingShortcuts: [KeyboardShortcutDefinition] {
        existingShortcuts + bucketShortcuts.assignedShortcuts.filter { $0 != shortcut }
    }

    private var recordTitle: String { requiresModifiers ? "Record Shortcut" : "Record Key" }
    private var recordingPrompt: String { requiresModifiers ? "Press a key combination now (Esc to cancel)" : "Press a key or combination now (Esc can be recorded)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isRecording ? recordingPrompt : "\(requiresModifiers ? "Shortcut" : "Key"): \(shortcut?.displayText ?? "None")")
                        .font(.caption)
                        .foregroundStyle(isRecording ? AppPalette.textAccent : .secondary)
                    HStack {
                        Button(isRecording ? "Cancel" : recordTitle) {
                            isRecording ? stopRecording() : startRecording()
                        }
                        .buttonStyle(.bordered)
                        if shortcut != nil && !isRecording {
                            Button("Clear") { shortcut = nil }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                fullRecorder
            }
            if let recordingError { Text(recordingError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .onAppear(perform: refreshRating)
        .onChange(of: shortcut) { _, _ in refreshRating() }
        .onChange(of: existingShortcuts) { _, _ in refreshRating() }
        .onChange(of: inputMonitoringEnabled) { _, enabled in if !enabled { stopRecording() } }
        .onChange(of: automationPaused) { _, paused in if paused { stopRecording() } }
        .onDisappear(perform: stopRecording)
    }

    private var fullRecorder: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 20))
                .foregroundStyle(AppPalette.textAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut?.displayText ?? (requiresModifiers ? "No recorded shortcut" : "No recorded key"))
                    .font(.system(size: 15, weight: .medium, design: shortcut == nil ? .default : .monospaced))
                Text(isRecording ? recordingPrompt : (requiresModifiers ? "Runs the automation when this shortcut is pressed" : "Records a key, with optional modifiers"))
                    .font(.caption)
                    .foregroundStyle(isRecording ? AppPalette.textAccent : .secondary)
            }

            Spacer()

            if shortcut != nil && !isRecording {
                Button("Clear") { shortcut = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Button(isRecording ? "Cancel Recording" : recordTitle) {
                isRecording ? stopRecording() : startRecording()
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? AppPalette.textAccent : nil)
        }
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
        .overlay(alignment: .bottomLeading) {
            if let rating, requiresModifiers {
                ShortcutRatingBadge(rating: rating)
                .offset(y: 33)
            }
        }
        .padding(.bottom, shortcut == nil || !requiresModifiers ? 0 : 36)
    }

    private func refreshRating() {
        rating = requiresModifiers ? shortcut.map { ShortcutAnalyzer.rate($0, comparedWith: conflictingShortcuts) } : nil
    }

    private func startRecording() {
        stopRecording()
        recordingError = nil
        guard inputMonitoringEnabled && !automationPaused else {
            recordingError = "Turn on Input monitoring in the robot menu to select a key or shortcut."
            return
        }
        guard CGPreflightListenEventAccess() else {
            PermissionExplanationPresenter.shared.present(
                title: "Record keys with Input Monitoring",
                message: "Input Monitoring lets the recorder recognize the key you press, including combinations handled by macOS such as Command-Shift-4. Recording runs only while you select Record. Continue opens Input Monitoring in System Settings; allow AutoProductive, then return and select Record again."
            ) { accepted in
                guard accepted else { return }
                _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                _ = CGRequestListenEventAccess()
                PermissionSettings.open("Input Monitoring")
            }
            return
        }
        isRecording = true
        AutomationCaptureCoordination.setRecording(true)
        let started = capture.start { event in
            let definition = KeyboardKeyLabel.definition(for: event)
            DispatchQueue.main.async {
                guard isRecording else { return }
                if requiresModifiers && event.keyCode == 53 { stopRecording(); return }
                if requiresModifiers && (event.keyCode == 51 || event.keyCode == 117) {
                    shortcut = nil; stopRecording(); return
                }
                guard !requiresModifiers || !definition.modifiers.isEmpty else { NSSound.beep(); return }
                if requiresModifiers, let reason = ShortcutAnalyzer.conflictReason(definition, comparedWith: conflictingShortcuts, probeRegistration: true) {
                    recordingError = reason; stopRecording(); return
                }
                shortcut = definition
                stopRecording()
            }
        }
        if !started {
            stopRecording()
            recordingError = "The key recorder could not start. Check Input Monitoring access, then try again."
        }
    }

    private func stopRecording() {
        let wasRecording = isRecording
        capture.stop()
        isRecording = false
        if wasRecording { AutomationCaptureCoordination.setRecording(false) }
    }
}

private struct ShortcutRatingBadge: View {
    let rating: ShortcutRating

    private var color: Color {
        switch rating.level {
        case .blocked: .red
        case .crowded: .orange
        case .fair: .yellow
        case .good: AppPalette.mint
        case .excellent: .green
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Label("\(rating.level.rawValue) · \(rating.score)/100", systemImage: rating.level.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(rating.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
