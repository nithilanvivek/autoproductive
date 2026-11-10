import AppKit
import AppIntents
import SwiftUI
import UniformTypeIdentifiers

struct OpenAppEditorView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @EnvironmentObject private var siriPresenter: SiriShortcutPresenter
    @Environment(\.dismiss) private var dismiss

    private let id: UUID
    private let createdAt: Date
    @State private var name: String
    @State private var appPath: String?
    @State private var keyboardShortcut: KeyboardShortcutDefinition?
    @State private var siriEnabled: Bool
    @State private var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("OpenAppEditorView", errorMessage)
            }
        }
    }

    init(existing: SavedAutomation? = nil) {
        id = existing?.id ?? UUID()
        createdAt = existing?.createdAt ?? .now
        _name = State(initialValue: existing?.name ?? "")
        _appPath = State(initialValue: existing?.appPath)
        _keyboardShortcut = State(initialValue: existing?.keyboardShortcut)
        _siriEnabled = State(initialValue: existing?.siriEnabled ?? true)
    }

    private var selectedAppName: String? {
        appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }

    private var selectedAppIcon: NSImage? {
        guard let appPath else { return nil }
        return NSWorkspace.shared.icon(forFile: appPath)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appPath != nil
    }

    var body: some View {
        EditorShell(
            title: "Open App",
            subtitle: "Choose an application to launch.",
            symbol: AutomationKind.openApp.symbol,
            color: AppPalette.blue
        ) {
            VStack(alignment: .leading, spacing: 22) {
                FormSection(title: "Automation Name") {
                    TextField("For example: Start Writing", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(14)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                }

                FormSection(title: "Application") {
                    Button(action: chooseApplication) {
                        HStack(spacing: 14) {
                            Group {
                                if let selectedAppIcon {
                                    Image(nsImage: selectedAppIcon)
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    Image(systemName: "app.dashed")
                                        .font(.system(size: 23))
                                        .foregroundStyle(AppPalette.blue)
                                }
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedAppName ?? "Choose an application")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(appPath ?? "Select any .app installed on this Mac")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            Text("Choose…")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppPalette.blue)
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }

                FormSection(title: "Keyboard Shortcut") {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyboardShortcutRecorder(
                            shortcut: $keyboardShortcut,
                            existingShortcuts: store.automations
                                .filter { $0.id != id }
                                .compactMap(\.keyboardShortcut)
                        )

                        HStack(spacing: 12) {
                            Image(systemName: "bolt.horizontal.circle.fill")
                                .font(.system(size: 21))
                                .foregroundStyle(AppPalette.mint)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("AutoProductive Menu Bar Agent")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Start the robot icon and shortcuts at login.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { backgroundAgent.isEnabled },
                                set: { backgroundAgent.setEnabled($0) }
                            ))
                            .labelsHidden()
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))

                        if let agentError = backgroundAgent.errorMessage {
                            Label(agentError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                FormSection(title: "Siri & Shortcuts") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, AppPalette.indigo)
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Add a Siri Phrase")
                                    .font(.system(size: 15, weight: .medium))
                                Text("Show Apple’s confirmation sheet after saving.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Toggle("Add a Siri Phrase", isOn: $siriEnabled)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                        }

                        if let siriError = siriPresenter.errorMessage {
                            Label(siriError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                }
            }
        } footer: {
            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Automation", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .navigationTitle("Open App")
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            appPath = url.path
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = "Open \(url.deletingPathExtension().lastPathComponent)"
            }
        }
    }

    private func save() {
        if let keyboardShortcut,
           store.automations.contains(where: {
               $0.id != id && $0.keyboardShortcut == keyboardShortcut
           }) {
            errorMessage = "That keyboard shortcut is already used by another automation."
            return
        }

        let automation = SavedAutomation(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .openApp,
            appPath: appPath,
            keyboardShortcut: keyboardShortcut,
            siriEnabled: siriEnabled,
            createdAt: createdAt
        )
        store.save(automation)
        AutoProductiveShortcuts.updateAppShortcutParameters()
        if siriEnabled {
            siriPresenter.presentAddSheet(for: automation) {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}
