import SwiftUI

/// Existing choices are refreshed before starting listeners or optional tools,
/// so an updated app never executes components from an older app version.
struct FeatureRefreshView: View {
    let installer: FeatureInstallationCoordinator
    let previous: FeatureSelectionState
    var refreshPackages = true
    @State private var working = true
    @State private var message: String?
    @State private var readyToRestart = false

    private var expected: Set<String> {
        Set(OptionalTool.allCases.map(\.packageID)).union(WorkflowAction.allCases.map(\.packageID))
    }

    var body: some View {
        VStack(spacing: 16) {
            if working { ProgressView() }
            else { Image(systemName: readyToRestart ? "checkmark.circle" : "exclamationmark.triangle").font(.largeTitle) }
            Text(working ? (refreshPackages ? "Updating your installed features…" : "Preparing AutoProductive for this Mac…") : (readyToRestart ? "Ready to restart" : "Couldn’t finish setup"))
                .font(.title2.bold())
            Text(message ?? "Your feature choices and automations will be kept on this Mac.")
                .foregroundStyle(.secondary)
            if !working {
                if readyToRestart {
                    Button("Restart AutoProductive") { restart() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Try Again") { Task { await refresh() } }.buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .task { await refresh() }
    }

    @MainActor private func refresh() async {
        guard !readyToRestart else { return }
        working = true
        message = nil
        do {
            if refreshPackages {
                let session = try await FeatureInstallationSession.begin(installer: installer, expected: expected, previous: previous)
                try await session.refreshSelected()
            }
            readyToRestart = true
            working = false
            restart()
        } catch FeatureInstallationCoordinator.InstallationError.cleanupFailed {
            readyToRestart = true
            working = false
            message = "Your features were updated, but old feature files could not be removed."
        } catch {
            working = false
            message = error.localizedDescription
        }
    }

    @MainActor private func restart() {
        do { try ApplicationRelauncher.restart(prepareForRestart: AutoProductiveAppDelegate.prepareForRestart) }
        catch { message = error.localizedDescription }
    }
}
