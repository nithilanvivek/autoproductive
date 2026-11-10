import SwiftUI

/// The host supplies the coordinator so setup can be tested with an isolated
/// catalogue and storage location. A successful installation is reported only
/// after the verified generation has been published.
struct FeatureInstallationView: View {
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @AppStorage("menuBarLoginChoiceMade.v1") private var loginChoiceMade = false
    @AppStorage("firstSetupLoginPromptSeen.v2") private var loginPromptSeen = false
    let installer: FeatureInstallationCoordinator
    let previous: FeatureSelectionState?
    let onFinished: () throws -> Void
    let onCancel: (() -> Void)?

    @State private var session: FeatureInstallationSession?
    @State private var isLoading = true
    @State private var isInstalling = false
    @State private var completed = false
    @State private var completionWarning: String?
    @State private var isRestarting = false
    @State private var message: String?
    @State private var installTask: Task<Void, Never>?
    @State private var draftSelection: Set<String>?
    @State private var startAtLogin = false

    private var expected: Set<String> {
        Set(OptionalTool.allCases.map(\.packageID)).union(WorkflowAction.allCases.map(\.packageID))
    }

    var body: some View {
        Group {
            if completed {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("Features installed").font(.title.bold())
                    Text("Your choices are saved on this Mac.").foregroundStyle(.secondary)
                    Text("Restart AutoProductive to activate tool changes.").foregroundStyle(.secondary)
                    if !AppArchitectureThinner.canReplace() {
                        Text("To reduce app storage, move AutoProductive to Applications and open it from there.").foregroundStyle(.secondary)
                    }
                    if let completionWarning { Text(completionWarning).foregroundStyle(.orange) }
                    Button(isRestarting ? "Restarting…" : "Restart AutoProductive") {
                        isRestarting = true
                        do { try onFinished() }
                        catch { isRestarting = false; completionWarning = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(isRestarting)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing the feature list…")
                    if let onCancel { Button("Cancel", action: onCancel) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isInstalling {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Installing your selected features…")
                    Text("Your previous selection stays in place until installation succeeds.")
                        .foregroundStyle(.secondary)
                    Button("Cancel Installation") { installTask?.cancel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session {
                Group {
                if previous != nil && !session.newFeatures.isEmpty {
                    newFeaturesChecklist(session)
                } else {
                FeatureSetupView(initialSelection: .init(packageIDs: draftSelection ?? session.initiallySelected),
                                 packageSizes: session.sizes, newFeatureIDs: session.newFeatures,
                                 startAtLogin: previous == nil && !loginChoiceMade ? $startAtLogin : nil, install: { selection in
                    install(selection.packageIDs, using: session)
                }, cancel: onCancel)
                }
                }
                .overlay(alignment: .top) {
                    if let message {
                        Text(message).foregroundStyle(.red).padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Couldn’t load the feature list").font(.title2.bold())
                    if let message { Text(message).foregroundStyle(.secondary) }
                    HStack {
                        if let onCancel { Button("Cancel", action: onCancel) }
                        Button("Try Again") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 440)
        .task { await load() }
        .onDisappear { installTask?.cancel() }
    }

    private func newFeaturesChecklist(_ session: FeatureInstallationSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose new features").font(.title.bold())
            Text("Select the new tools and actions you want to install. You can add them later.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(OptionalTool.allCases.filter { session.newFeatures.contains($0.packageID) }) { tool in
                        newFeatureRow(id: tool.packageID, title: tool.title, description: tool.explanation, session: session)
                    }
                    ForEach(WorkflowAction.chooserOrder.filter { session.newFeatures.contains($0.packageID) }) { action in
                        newFeatureRow(id: action.packageID, title: action.title, description: action.featureExplanation, session: session)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if let onCancel { Button("Later", action: onCancel) }
                Spacer()
                Button("Continue") { install(draftSelection ?? session.initiallySelected, using: session) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
    }

    private func newFeatureRow(id: String, title: String, description: String, session: FeatureInstallationSession) -> some View {
        Toggle(isOn: Binding(get: { (draftSelection ?? session.initiallySelected).contains(id) }, set: { selected in
            var selection = draftSelection ?? session.initiallySelected
            if selected { selection.insert(id) } else { selection.remove(id) }
            draftSelection = selection
        })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description).font(.callout).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .glassCard()
    }

    @MainActor private func load() async {
        isLoading = true
        message = nil
        do {
            session = try await FeatureInstallationSession.begin(installer: installer, expected: expected, previous: previous)
        } catch is CancellationError {
            return
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor private func install(_ selection: Set<String>, using session: FeatureInstallationSession) {
        guard !isInstalling else { return }
        draftSelection = selection
        isInstalling = true
        message = nil
        installTask = Task { @MainActor in
            do {
                try await session.install(selection)
                applyFirstLoginChoice()
                completed = true
            } catch is CancellationError {
                message = "Installation cancelled. Your previous selection is unchanged."
            } catch FeatureInstallationCoordinator.InstallationError.cleanupFailed {
                // Publishing has already succeeded; do not claim that the old
                // choices remain active just because old files could not be removed.
                completionWarning = "Your features were installed, but old feature files could not be removed."
                applyFirstLoginChoice()
                completed = true
            } catch {
                message = error.localizedDescription
            }
            isInstalling = false
            installTask = nil
        }
    }

    @MainActor private func applyFirstLoginChoice() {
        guard previous == nil, !loginChoiceMade else { return }
        backgroundAgent.setEnabled(startAtLogin)
        if backgroundAgent.isEnabled == startAtLogin, backgroundAgent.errorMessage == nil {
            loginChoiceMade = true
            loginPromptSeen = true
        } else {
            completionWarning = backgroundAgent.errorMessage ?? "Start at Login could not be changed. You can choose it after restarting."
        }
    }
}
