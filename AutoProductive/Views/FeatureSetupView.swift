import SwiftUI

/// Setup collects choices only. Its caller must install the selected components
/// successfully before considering setup complete.
struct FeatureSetupView: View {
    struct Selection {
        var tools = Set(OptionalTool.allCases)
        var actions = Set(WorkflowAction.allCases)

        init() {}

        init(packageIDs: Set<String>) {
            tools = Set(OptionalTool.allCases.filter { packageIDs.contains($0.packageID) })
            actions = Set(WorkflowAction.allCases.filter { packageIDs.contains($0.packageID) })
        }
        var packageIDs: Set<String> {
            Set(tools.map(\.packageID)).union(actions.map(\.packageID))
        }
    }

    let install: (Selection) -> Void
    let cancel: (() -> Void)?
    let packageSizes: [String: Int64]
    let newFeatureIDs: Set<String>
    let startAtLogin: Binding<Bool>?
    @State private var step = 0
    @State private var selection: Selection

    init(initialSelection: Selection = Selection(), packageSizes: [String: Int64] = [:], newFeatureIDs: Set<String> = [], startAtLogin: Binding<Bool>? = nil, install: @escaping (Selection) -> Void, cancel: (() -> Void)?) {
        self.install = install
        self.cancel = cancel
        self.packageSizes = packageSizes
        self.newFeatureIDs = newFeatureIDs
        self.startAtLogin = startAtLogin
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("STEP \(step + 1) OF 4")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(index == step ? AppPalette.blue : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 6)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: introduction
                    case 1: tools
                    case 2: actions
                    default: review
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                } else if let cancel {
                    Button("Cancel", action: cancel)
                }
                Spacer()
                if step < 3 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Installation") { install(selection) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 440)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to AutoProductive").font(.largeTitle.bold())
            Text("Use this installation guide to select the features you’ll use. Only the selected feature components will be downloaded, saving storage.")
            Text("You can install more features later.")
                .foregroundStyle(.secondary)
            Image("WelcomeThumbnail")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 540)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .accessibilityLabel("AutoProductive productivity tools")
        }.padding(.top, 32)
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which tools would you use?").font(.title.bold())
            Text("Choose any tools you want. You can change these choices later.").foregroundStyle(.secondary)
            ForEach(OptionalTool.allCases) { tool in
                Toggle(isOn: binding(for: tool)) {
                    HStack(alignment: .center, spacing: 14) {
                        toolIcon(tool)
                            .frame(width: 42, height: 42)
                            .background(AppPalette.blue.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(tool.title).font(.headline)
                                if newFeatureIDs.contains(tool.packageID) { Text("New").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.textAccent) }
                            }
                            Text(tool.explanation).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(InstallerToolToggleStyle(title: tool.title))
                .padding(12)
                .glassCard()
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which actions would you like to automate?").font(.title.bold())
            Text("Select actions to install. All triggers are included automatically.").foregroundStyle(.secondary)
            HStack {
                Button("Select All") { selection.actions = Set(WorkflowAction.allCases) }
                Button("Clear") { selection.actions.removeAll() }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), alignment: .leading, spacing: 12) {
                ForEach(WorkflowAction.chooserOrder) { action in
                    Toggle(isOn: binding(for: action)) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(action.title).font(.headline)
                                if newFeatureIDs.contains(action.packageID) { Text("New").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.textAccent) }
                            }
                            Text(action.featureExplanation).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(InstallerToolToggleStyle(title: action.title, scale: 1.2))
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    .padding(10)
                    .glassCard()
                }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to install").font(.title.bold())
            Text("Review your choices before starting.").foregroundStyle(.secondary)
            Text("Tools: \(selection.tools.count) of \(OptionalTool.allCases.count)")
            Text("Actions: \(selection.actions.count) of \(WorkflowAction.allCases.count)")
            Text("All triggers included")
            if selection.packageIDs.allSatisfy({ packageSizes[$0] != nil }) {
                let bytes = selection.packageIDs.reduce(Int64(0)) { $0 + (packageSizes[$1] ?? 0) }
                Text("Download size: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
            } else {
                Text("Download size unavailable").foregroundStyle(.secondary)
            }
            Text("You can add features later.").foregroundStyle(.secondary)
            if let startAtLogin {
                Toggle(isOn: startAtLogin) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start AutoProductive at login")
                        Text("Keep the robot menu and automation triggers available when you sign in. You can change this later.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.top, 8)
            }
        }
    }

    private func binding(for tool: OptionalTool) -> Binding<Bool> {
        Binding(get: { selection.tools.contains(tool) }, set: { selected in
            if selected { selection.tools.insert(tool) } else { selection.tools.remove(tool) }
        })
    }

    private func binding(for action: WorkflowAction) -> Binding<Bool> {
        Binding(get: { selection.actions.contains(action) }, set: { selected in
            if selected { selection.actions.insert(action) } else { selection.actions.remove(action) }
        })
    }

    @ViewBuilder private func toolIcon(_ tool: OptionalTool) -> some View {
        switch tool {
        case .keepAwake: Image(systemName: "moon.zzz.fill")
        case .audioMixer: Image(systemName: "speaker.wave.2.fill")
        case .fileBucket: BucketIcon().frame(width: 23, height: 23)
        case .dockPreviews:
            ZStack(alignment: .topTrailing) {
                Image(systemName: "dock.rectangle").font(.system(size: 21))
                Image(systemName: "rectangle.fill").font(.system(size: 10)).offset(x: 4, y: -5)
            }
        case .finderCut: Image(systemName: "command")
        }
    }
}

private struct InstallerToolToggleStyle: ToggleStyle {
    let title: String
    var scale: CGFloat = 1.35

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .accessibilityLabel(title)
                .toggleStyle(.checkbox)
                .scaleEffect(scale)
                .frame(width: 25, height: 32)
            configuration.label
                .contentShape(Rectangle())
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
