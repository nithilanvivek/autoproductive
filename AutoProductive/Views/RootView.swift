import SwiftUI

enum AppRoute: Hashable {
    case create
    case createOpenApp
    case createMail
    case createWorkflow(AutomationKind)
    case library
    case powerTools
    case edit(UUID)
}

struct RootView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var path: [AppRoute] = []
    #if MODULAR_FEATURES
    @StateObject private var featureGate = FeatureSetupGate()
    @State private var managingFeatures = false
    #endif

    var body: some View {
        #if MODULAR_FEATURES
        Group {
            if let environment = featureGate.environment {
                if featureGate.needsInitialSetup {
                    FeatureInstallationView(installer: environment.installer, previous: nil,
                                            onFinished: { try ApplicationRelauncher.restart(prepareForRestart: AutoProductiveAppDelegate.prepareForRestart) }, onCancel: nil)
                } else if featureGate.needsFeatureRefresh, let selection = featureGate.selection {
                    FeatureRefreshView(installer: environment.installer, previous: selection)
                } else if featureGate.needsArchitectureThinning, let selection = featureGate.selection {
                    FeatureRefreshView(installer: environment.installer, previous: selection, refreshPackages: false)
                } else {
                    navigationContent
                        .task {
                            if await featureGate.hasNewFeatures() { managingFeatures = true }
                        }
                        .sheet(isPresented: $managingFeatures) {
                            FeatureInstallationView(installer: environment.installer, previous: featureGate.selection,
                                onFinished: { try ApplicationRelauncher.restart(prepareForRestart: AutoProductiveAppDelegate.prepareForRestart) }, onCancel: { managingFeatures = false })
                        }
                }
            } else {
                ContentUnavailableView("Feature Setup Unavailable", systemImage: "exclamationmark.triangle",
                    description: Text(featureGate.errorMessage ?? "Could not open feature setup."))
            }
        }
        #else
        navigationContent
        #endif
    }

    private var navigationContent: some View {
        NavigationStack(path: $path) {
            HomeView(
                createAction: { path.append(.create) },
                editAction: { path.append(.library) },
                powerToolsAction: { path.append(.powerTools) },
                featuresAction: featureAction
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .create:
                    NewAutomationView(
                    openAppAction: { path.append(.createWorkflow(.openApp)) },
                    composeMailAction: { path.append(.createWorkflow(.composeMail)) },
                        workflowAction: { path.append(.createWorkflow($0)) }
                    )
                case .createOpenApp:
                    OpenAppEditorView()
                case .createMail:
                    ComposeMailEditorView()
                case .createWorkflow(let kind):
                    if kind == .keyRemap { AutomationWizardView(kind: kind) }
                    else { SequenceEditorView() }
                case .library:
                    AutomationLibraryView(editAction: { path.append(.edit($0)) })
                case .powerTools:
                    PowerToolsView()
                case .edit(let id):
                    if let automation = store.automation(id: id) {
                        if automation.kind == .keyRemap {
                            WorkflowEditorView(kind: automation.kind, existing: automation)
                        } else {
                            SequenceEditorView(existing: automation)
                        }
                    } else {
                        ContentUnavailableView(
                            "Automation Not Found",
                            systemImage: "questionmark.folder",
                            description: Text("It may have been deleted.")
                        )
                    }
                }
            }
        }
        .background(MenuBarInstallationView())
        .tint(AppPalette.blue)
        .onAppear {
            followMenuRequest()
            if AutoProductiveAppDelegate.isMenuBarAgentLaunch {
                DispatchQueue.main.async {
                    NSApp.windows.first(where: { $0.title == "AutoProductive" })?.orderOut(nil)
                }
            }
        }
        .onReceive(navigation.$request) { _ in followMenuRequest() }
    }

    private func followMenuRequest() {
        guard let request = navigation.request else { return }
        path = request.route.map { [$0] } ?? []
    }

    private var featureAction: (() -> Void)? {
        #if MODULAR_FEATURES
        return { managingFeatures = true }
        #else
        return nil
        #endif
    }
}

#if MODULAR_FEATURES
@MainActor private final class FeatureSetupGate: ObservableObject {
    let environment: FeatureInstallationEnvironment?
    let selection: FeatureSelectionState?
    let needsInitialSetup: Bool
    let needsFeatureRefresh: Bool
    let needsArchitectureThinning: Bool
    let errorMessage: String?

    init() {
        do {
            let environment = try FeatureInstallationEnvironment.live()
            let current = try environment.installer.generations.current()
            if let current, current.selection == nil { throw FeaturePackageGenerations.GenerationError.invalidSelection }
            let thinningNeeded = try current != nil && AppArchitectureThinner.canReplace() && AppArchitectureThinner.needsThinning()
            self.environment = environment
            selection = current?.selection
            needsInitialSetup = current == nil
            needsFeatureRefresh = current?.packages.contains(where: { $0.version != environment.componentVersion }) ?? false
            needsArchitectureThinning = thinningNeeded
            errorMessage = nil
        } catch {
            environment = nil
            selection = nil
            needsInitialSetup = false
            needsFeatureRefresh = false
            needsArchitectureThinning = false
            errorMessage = error.localizedDescription
        }
    }

    func hasNewFeatures() async -> Bool {
        guard let environment, let selection else { return false }
        let expected = Set(OptionalTool.allCases.map(\.packageID)).union(WorkflowAction.allCases.map(\.packageID))
        guard let session = try? await FeatureInstallationSession.begin(installer: environment.installer,
                                                                        expected: expected, previous: selection) else { return false }
        return !session.newFeatures.isEmpty
    }
}
#endif
