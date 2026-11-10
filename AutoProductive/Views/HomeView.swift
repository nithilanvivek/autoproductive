import SwiftUI
import ServiceManagement

struct HomeView: View {
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @ObservedObject private var updates = AppUpdateManager.shared
    @AppStorage("menuBarIntroductionDismissed.v1") private var menuBarIntroductionDismissed = false
    @AppStorage("menuBarLoginChoiceMade.v1") private var menuBarLoginChoiceMade = false
    @AppStorage("firstSetupLoginPromptSeen.v2") private var firstSetupLoginPromptSeen = false
    @State private var showLoginRequest = false
    @State private var loginRequestError: String?
    let createAction: () -> Void
    let editAction: () -> Void
    let powerToolsAction: () -> Void
    var featuresAction: (() -> Void)? = nil

    var body: some View {
      GeometryReader { geometry in
        ZStack {
            AppBackground()

            ScrollView {
              VStack(spacing: 0) {
                Spacer(minLength: 20)

                SymbolTile(symbol: "wand.and.stars", color: AppPalette.blue, size: 56)
                    .padding(.bottom, 12)

                Text("AutoProductive")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.2)

                Text("What would you like to do?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 22)

                if let version = updates.availableVersion {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Update available").font(.headline)
                            Text("Version \(updates.availableDisplayVersion ?? version) is ready to install.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install") { updates.checkNow() }.buttonStyle(.borderedProminent)
                        Button("Skip") { updates.skip() }.buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(AppPalette.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 16)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    if let featuresAction {
                        Button(action: featuresAction) {
                            Label("Install/Delete Features", systemImage: "square.stack.3d.up")
                        }
                    }
                    Button { updates.checkNow() } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { ProblemReportCoordinator.shared.show() } label: {
                        Label("Report Bug / Give Feedback", systemImage: "bubble.left.and.bubble.right")
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { FileBucket.shared.showWindow() } label: {
                        Label { Text("Open File Bucket") } icon: {
                            BucketIcon().frame(width: 16, height: 16)
                        }
                    }
                    .disabled(!FileBucket.shared.isAvailable)
                    .help(FileBucket.shared.isAvailable ? "Open File Bucket" : "Install File Bucket to use it.")
                    Button(action: powerToolsAction) {
                        Label("Open Tools", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.bordered)
                .tint(AppPalette.textAccent)
                .padding(14)
                .frame(maxWidth: 760)
                .glassCard()
                .padding(.bottom, 20)

                (geometry.size.width < 700 ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))) {
                    HomeActionCard(
                        title: "Create New Automation",
                        subtitle: "Build a new workflow from simple actions.",
                        symbol: "plus",
                        illustration: "CreateAutomation",
                        color: AppPalette.blue,
                        action: createAction
                    )

                    HomeActionCard(
                        title: "Edit Existing",
                        subtitle: store.automations.isEmpty
                            ? "Your saved automations will appear here."
                            : "Manage \(store.automations.count) saved automation\(store.automations.count == 1 ? "" : "s").",
                        symbol: "slider.horizontal.3",
                        illustration: "EditAutomation",
                        color: AppPalette.indigo,
                        action: editAction
                    )
                }
                .frame(maxWidth: 760)

                Spacer()

                VStack(spacing: 4) {
                    Text("Automate the repetitive. Keep the creative.")
                        .font(.footnote.weight(.medium))
                    Text("AutoProductive uses zero trackers, zero accounts, and zero cloud telemetry. We respect your privacy.")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, geometry.size.width < 700 ? 24 : 46)
            .frame(minHeight: geometry.size.height)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if !menuBarIntroductionDismissed {
                    HStack(spacing: 12) {
                        MenuBarRobotIcon(active: false)
                            .frame(width: 32, height: 32)
                            .background(AppPalette.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New: robot-head icon in your menu bar")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Click it to run automations and control Keep Awake without opening this app.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Got it") { menuBarIntroductionDismissed = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)
                    .glassCard()
                }
                if menuBarLoginChoiceMade && !backgroundAgent.isEnabled {
                    HStack(spacing: 12) {
                        Image(systemName: "menubar.rectangle")
                            .frame(width: 32, height: 32)
                            .foregroundStyle(AppPalette.textAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Want the robot menu and automation triggers ready after login?")
                                .font(.system(size: 13, weight: .semibold))
                            Text("They work whenever you open AutoProductive. Start at Login makes them available automatically after a restart.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Start at Login") {
                            backgroundAgent.setEnabled(true)
                            if !backgroundAgent.isEnabled {
                                loginRequestError = backgroundAgent.errorMessage ?? "Start at Login could not be enabled."
                            }
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .glassCard()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .toolbar(.hidden)
        .onAppear {
            if !firstSetupLoginPromptSeen && !AutoProductiveAppDelegate.isMenuBarAgentLaunch {
                if backgroundAgent.isEnabled { firstSetupLoginPromptSeen = true }
                else { showLoginRequest = true }
            }
        }
        .alert("Start AutoProductive at Login?", isPresented: $showLoginRequest) {
            Button("Start at Login") {
                backgroundAgent.setEnabled(true)
                if backgroundAgent.isEnabled { menuBarLoginChoiceMade = true; firstSetupLoginPromptSeen = true }
                else { loginRequestError = backgroundAgent.errorMessage ?? "Start at Login could not be enabled." }
            }
            Button("Not Now", role: .cancel) {
                backgroundAgent.setEnabled(false)
                menuBarLoginChoiceMade = true
                firstSetupLoginPromptSeen = true
            }
        } message: {
            Text("Allow AutoProductive Menu Bar Agent to start when you sign in, so the robot icon and automation triggers work without reopening the app. You can change this later in the menu bar.")
        }
        .alert("Start at Login could not be enabled", isPresented: Binding(
            get: { loginRequestError != nil },
            set: { if !$0 { loginRequestError = nil } }
        )) {
            Button("OK", role: .cancel) { loginRequestError = nil }
        } message: {
            Text(loginRequestError ?? "")
        }
      }
    }
}

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let illustration: String
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SymbolTile(symbol: symbol, color: color, size: 44)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.quaternary, in: Circle())
                }

                Image(illustration)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .padding(.horizontal, 8)
                    .shadow(color: color.opacity(0.22), radius: 22, y: 10)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
            .glassCard()
            .scaleEffect(isHovering ? 1.018 : 1)
            .shadow(color: color.opacity(isHovering ? 0.14 : 0), radius: 26, y: 14)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
