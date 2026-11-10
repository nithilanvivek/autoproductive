import SwiftUI
import AppKit

struct AutomationLibraryView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var siriPresenter: SiriShortcutPresenter
    let editAction: (UUID) -> Void

    @State private var errorTitle = "Couldn’t Run Automation"
    @State private var errorMessage: String?
    @ObservedObject private var engine = WorkflowEngine.shared

    var body: some View {
        ZStack {
            AppBackground()

            if store.automations.isEmpty {
                ContentUnavailableView {
                    Label("No Automations Yet", systemImage: "wand.and.stars.inverse")
                } description: {
                    Text("Create your first automation, then return here to run or edit it.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.automations) { automation in
                            AutomationRow(
                                automation: automation,
                                editAction: { editAction(automation.id) },
                                runAction: { run(automation) },
                                deleteAction: { delete(automation) }
                            )
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 34)
                }
            }
        }
        .navigationTitle("My Automations")
        .safeAreaInset(edge: .bottom) {
            if let message = engine.lastError {
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle").font(.caption)
                    Spacer()
                    if message.contains("Privacy & Security → \(DesktopAutomationService.controlPermissionName)") {
                        Button("Open \(DesktopAutomationService.controlPermissionName) Settings") {
                            PermissionSettings.open(DesktopAutomationService.controlPermissionName)
                        }
                    }
                    Button("Dismiss") { engine.lastError = nil }
                }
                    .padding().background(.regularMaterial)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func run(_ automation: SavedAutomation) {
        do {
            try AutomationRunner.run(automation)
        } catch {
            DiagnosticJournal.shared.recordError("AutomationLibraryView", error); errorTitle = "Couldn’t Run Automation"
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ automation: SavedAutomation) {
        if automation.workflow != nil && !automation.siriEnabled {
            WorkflowEngine.shared.stop(automation.id)
            store.delete(automation)
            AutoProductiveShortcuts.updateAppShortcutParameters()
            return
        }
        siriPresenter.removeShortcutBeforeDeleting(for: automation) { shouldDelete in
            guard shouldDelete else {
                errorTitle = "Siri Shortcut Still Active"
                errorMessage = siriPresenter.errorMessage
                    ?? "Remove the Siri shortcut in Apple’s sheet before deleting this automation."
                return
            }

            WorkflowEngine.shared.stop(automation.id)
            store.delete(automation)
            AutoProductiveShortcuts.updateAppShortcutParameters()
        }
    }
}

private struct AutomationRow: View {
    @EnvironmentObject private var store: AutomationStore
    @ObservedObject private var engine = WorkflowEngine.shared
    let automation: SavedAutomation
    let editAction: () -> Void
    let runAction: () -> Void
    let deleteAction: () -> Void

    @State private var isShowingDeleteConfirmation = false

    private var tint: Color {
        automation.kind == .openApp ? AppPalette.blue : AppPalette.indigo
    }

    private var missingPermissions: [String] {
        automation.workflow.map { store.missingPermissions(for: $0) } ?? []
    }

    private var detail: String {
        if let flow = automation.workflow, let triggers = flow.sequenceTriggers {
            let titles = triggers.map { trigger in
                trigger == .screen ? (flow.screenChecks.first?.condition?.action == .screenImage ? SequenceTrigger.screenImage.title : SequenceTrigger.screenPixel.title) : trigger.title
            }
            return "\(titles.joined(separator: ", ")) · \(flow.steps.count) actions"
        }
        switch automation.kind {
        case .openApp:
            guard let path = automation.appPath else { return "No application selected" }
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case .composeMail:
            return automation.recipient.isEmpty ? "New email draft" : "To \(automation.recipient)"
        default:
            guard let flow = automation.workflow else { return "No saved actions" }
            return "\(flow.trigger.title) · \(flow.steps.count) action\(flow.steps.count == 1 ? "" : "s")"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                SymbolTile(symbol: automation.kind.symbol, color: tint, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(automation.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Group {
                    Button(automation.isEnabled ? "Disable" : "Enable") {
                        store.setEnabled(automation, enabled: !automation.isEnabled)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(automation.isEnabled ? "Disable \(automation.name)" : "Enable \(automation.name)")
                }

                Button("Edit", action: editAction)
                    .buttonStyle(.bordered)

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button(action: runAction) {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(!automation.isEnabled)
            }
            if !missingPermissions.isEmpty || engine.runningIDs.contains(automation.id) {
                HStack {
                    if !missingPermissions.isEmpty {
                        Text("Needs \(missingPermissions.joined(separator: " and "))")
                            .foregroundStyle(.secondary)
                        if let workflow = automation.workflow {
                            Button("Request Access") { store.requestPermissions(for: workflow) }
                                .buttonStyle(.bordered)
                        }
                        Button("Open Settings") { PermissionSettings.open(missingPermissions[0]) }
                            .buttonStyle(.link)
                    }
                    Spacer()
                    if engine.runningIDs.contains(automation.id) {
                        ProgressView().controlSize(.small)
                        Button("Stop") { engine.stop(automation.id) }
                    }
                }
                .font(.caption)
            }
        }
        .padding(16)
        .glassCard()
        .contextMenu {
            Button("Run", action: runAction).disabled(!automation.isEnabled)
            Button("Edit", action: editAction)
            Divider()
            Button("Delete", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
        }
        .alert("Delete “\(automation.name)”?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive, action: deleteAction)
        } message: {
            Text("Its keyboard shortcut will be removed. If it has a Siri phrase, Apple will ask you to remove that phrase before AutoProductive deletes the automation.")
        }
    }
}

enum PermissionSettings {
    static func open(_ permission: String) {
        let pane: String
        switch permission {
        case DesktopAutomationService.controlPermissionName: pane = "Privacy_Accessibility"
        case "Input Monitoring": pane = "Privacy_ListenEvent"
        default: pane = "Privacy_ScreenCapture"
        }
        openPane(pane)
    }

    static func openPane(_ pane: String) {
        let settingsExtension = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            ? "com.apple.settings.PrivacySecurity.extension"
            : "com.apple.preference.security"
        if let url = URL(string: "x-apple.systempreferences:\(settingsExtension)?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
