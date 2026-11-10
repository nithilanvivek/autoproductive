import AppIntents
import SwiftUI

struct ComposeMailEditorView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @EnvironmentObject private var siriPresenter: SiriShortcutPresenter
    @Environment(\.dismiss) private var dismiss

    private let id: UUID
    private let createdAt: Date
    @State private var name: String
    @State private var recipient: String
    @State private var subject: String
    @State private var message: String
    @State private var keyboardShortcut: KeyboardShortcutDefinition?
    @State private var siriEnabled: Bool
    @State private var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("ComposeMailEditorView", errorMessage)
            }
        }
    }

    init(existing: SavedAutomation? = nil) {
        id = existing?.id ?? UUID()
        createdAt = existing?.createdAt ?? .now
        _name = State(initialValue: existing?.name ?? "")
        _recipient = State(initialValue: existing?.recipient ?? "")
        _subject = State(initialValue: existing?.subject ?? "")
        _message = State(initialValue: existing?.message ?? "")
        _keyboardShortcut = State(initialValue: existing?.keyboardShortcut)
        _siriEnabled = State(initialValue: existing?.siriEnabled ?? true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        EditorShell(
            title: "Compose Mail",
            subtitle: "Prepare a reusable email draft.",
            symbol: AutomationKind.composeMail.symbol,
            color: AppPalette.indigo
        ) {
            VStack(alignment: .leading, spacing: 19) {
                FormSection(title: "Automation Name") {
                    EditorTextField(placeholder: "For example: Weekly Update", text: $name)
                }

                FormSection(title: "To") {
                    EditorTextField(placeholder: "name@example.com (optional)", text: $recipient)
                }

                FormSection(title: "Subject") {
                    EditorTextField(placeholder: "Email subject (optional)", text: $subject)
                }

                FormSection(title: "Message") {
                    TextEditor(text: $message)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 110)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Write your draft…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
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
                VStack(alignment: .leading, spacing: 4) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Label("The email opens as a draft—you stay in control of Send.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .navigationTitle("Compose Mail")
    }

    private func save() {
        if let keyboardShortcut,
           store.automations.contains(where: {
               $0.id != id && $0.keyboardShortcut == keyboardShortcut
           }) {
            errorMessage = "That keyboard shortcut is already used by another automation."
            return
        }

        let automation = makeAutomation(siriEnabled: siriEnabled)
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

    private func makeAutomation(siriEnabled: Bool) -> SavedAutomation {
        SavedAutomation(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .composeMail,
            recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject,
            message: message,
            keyboardShortcut: keyboardShortcut,
            siriEnabled: siriEnabled,
            createdAt: createdAt
        )
    }
}

private struct EditorTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(14)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
    }
}
