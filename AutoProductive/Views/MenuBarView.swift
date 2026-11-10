import AppKit
import SwiftUI

private enum RobotMenuSection: String, CaseIterable, Identifiable {
    case keepAwake = "Keep Awake"
    case automations = "Existing Automations"
    case audio = "Audio Mixer"
    case controls = "Quick Controls"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .keepAwake: "moon.stars.fill"
        case .automations: "bolt.fill"
        case .audio: "speaker.wave.2"
        case .controls: "slider.horizontal.3"
        }
    }
}

private struct RobotMenuHeights: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct MenuBarRobotIcon: View {
    let active: Bool

    var body: some View {
        Image(nsImage: Self.image(active: active))
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .accessibilityLabel(active ? "AutoProductive, Keep Awake on" : "AutoProductive")
    }

    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            let ink = active ? NSColor.systemRed : NSColor.labelColor
            ink.setStroke()
            ink.setFill()
            let head = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 16, height: 12), xRadius: 3, yRadius: 3)
            head.lineWidth = 1.6
            head.stroke()
            NSBezierPath(ovalIn: NSRect(x: 6, y: 9, width: 2, height: 2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12, y: 9, width: 2, height: 2)).fill()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 5.5, width: 6, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(rect: NSRect(x: 9.25, y: 15, width: 1.5, height: 2.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 8.75, y: 17, width: 2.5, height: 2.5)).fill()
            return true
        }
        image.isTemplate = !active
        return image
    }
}

struct MenuBarView: View {
    let popupSize: NSSize
    let maximumHeight: CGFloat
    let openMainWindow: () -> Void
    let contentHeightChanged: (CGFloat) -> Void
    let isPowerTools: Bool
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var runtime: AutomationRuntime
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var keepAwake: KeepAwakeManager
    @ObservedObject private var engine = WorkflowEngine.shared
    @ObservedObject private var bucket = FileBucket.shared
    @ObservedObject private var dockPreview = DockPreviewManager.shared
    @ObservedObject private var audioMixer = AppAudioMixer.shared
    @ObservedObject private var updates = AppUpdateManager.shared

    @State private var showCustomTime = false
    @State private var customMode = 0
    @State private var customHours = 1
    @State private var customMinutes = 0
    @State private var endTime = Date().addingTimeInterval(60 * 60)
    @State private var finderCutPermissionMessage: String?
    @State private var section: RobotMenuSection = .keepAwake

    init(popupSize: NSSize, maximumHeight: CGFloat,
         openMainWindow: @escaping () -> Void, contentHeightChanged: @escaping (CGFloat) -> Void,
         isPowerTools: Bool = false) {
        self.popupSize = popupSize
        self.maximumHeight = maximumHeight
        self.openMainWindow = openMainWindow
        self.contentHeightChanged = contentHeightChanged
        self.isPowerTools = isPowerTools
    }

    private var sections: [RobotMenuSection] {
        let choices: [RobotMenuSection] = isPowerTools ? [.keepAwake, .controls, .audio] : RobotMenuSection.allCases
        return choices.filter { item in
            switch item {
            case .keepAwake: return FeatureAvailability.tool("tool.keepAwake")
            case .audio: return audioMixer.isAvailable
            default: return true
            }
        }
    }

    private var sequences: [SavedAutomation] { store.automations.filter { $0.kind != .keyRemap } }
    private var remaps: [SavedAutomation] { store.automations.filter { $0.kind == .keyRemap } }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                header
                if !isPowerTools { inputMonitoringControl }
                if !isPowerTools, let version = updates.availableVersion {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update available").font(.caption.weight(.semibold))
                            Text("Version \(updates.availableDisplayVersion ?? version)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install") { MenuBarController.shared.close(); updates.checkNow() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("Skip") { updates.skip() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(8)
                    .background(AppPalette.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                }
            }.background(heightReader("header"))
            sectionPicker.background(heightReader("picker"))
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    if !isPowerTools, section != .controls, let error = engine.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    sectionContent
                }
                .frame(width: max(0, popupSize.width - 24))
                .background(heightReader("content"))
            }
            .id(section)
            .frame(maxHeight: .infinity)
            Divider()
            footer.fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .background(heightReader("footer"))
        }
        .padding(12)
        .frame(width: popupSize.width, height: popupSize.height)
        .background {
            if !isPowerTools { MenuBarWindowReader().frame(width: 0, height: 0) }
        }
        .onPreferenceChange(RobotMenuHeights.self) { sizes in
            guard !isPowerTools else { return }
            guard ["header", "picker", "content", "footer"].allSatisfy({ (sizes[$0] ?? 0) > 0 }) else { return }
            contentHeightChanged(sizes.values.reduce(0, +) + 66)
        }
        .onAppear {
            if !sections.contains(section) { section = sections.first ?? .controls }
            audioMixer.start()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .accessibilityLabel("AutoProductive logo")
            Text(isPowerTools ? "Power Tools" : "AutoProductive")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 1)
    }

    @ViewBuilder private var sectionPicker: some View {
        if maximumHeight < 400 {
            Picker("Section", selection: $section) {
                ForEach(sections) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.menu)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: isPowerTools ? 3 : 2), spacing: 6) {
                ForEach(sections) { item in
                    Button { section = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 12, weight: section == item ? .semibold : .regular))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(section == item ? AppPalette.blue.opacity(0.2) : .white.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityValue(section == item ? "Selected" : "")
                }
            }
        }
    }

    private func heightReader(_ key: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: RobotMenuHeights.self, value: [key: geometry.size.height])
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .keepAwake: keepAwakeCard
        case .automations:
            sequencesCard
            remapsCard
        case .audio: audioMixerCard
        case .controls: controlsCard
        }
    }

    private var keepAwakeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Keep Awake", systemImage: "moon.stars.fill").font(.headline)
                    Spacer()
                    Button(keepAwake.isActive ? "Stop" : "Start") {
                        keepAwake.isActive ? keepAwake.stop() : keepAwake.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(keepAwake.isActive ? .red : AppPalette.blue)
                    .accessibilityLabel(keepAwake.isActive ? "Stop Keep Awake" : "Start Keep Awake")
                }
                Text(keepAwake.status).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    preset("30m", duration: 30 * 60)
                    preset("1h", duration: 60 * 60)
                    preset("2h", duration: 2 * 60 * 60)
                    preset("∞", duration: nil)
                }
                HStack {
                    Button("Custom duration…") {
                        customMode = 0
                        showCustomTime = true
                    }
                    Button("End time…") {
                        customMode = 1
                        endTime = Date().addingTimeInterval(60 * 60)
                        showCustomTime = true
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppPalette.blue)
                if showCustomTime {
                    VStack(alignment: .leading, spacing: 9) {
                        Picker("Time type", selection: $customMode) {
                            Text("Duration").tag(0)
                            Text("End time").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        if customMode == 0 {
                            HStack {
                                Stepper("\(customHours) hr", value: $customHours, in: 0...168)
                                Stepper("\(customMinutes) min", value: $customMinutes, in: 0...59)
                            }
                            Button("Start for \(customHours)h \(customMinutes)m") {
                                keepAwake.start(for: TimeInterval(customHours * 60 + customMinutes) * 60)
                            }
                            .disabled(customHours == 0 && customMinutes == 0)
                        } else {
                            DatePicker("Until", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                            Button("Start until selected time") { keepAwake.start(until: endTime) }
                                .disabled(endTime <= Date())
                        }
                    }
                    .padding(.top, 8)
                    .controlSize(.small)
                }
                Divider()
                optionToggle("Allow display to sleep", systemImage: "display", value: Binding(
                    get: { keepAwake.allowDisplaySleep },
                    set: { keepAwake.setAllowDisplaySleep($0) }
                ))
                .help("Off by default. Leave unchecked to keep the display awake and prevent the automatic screensaver while Keep Awake runs.")
                optionToggle("Mute audio while running", systemImage: "speaker.slash.fill", value: Binding(
                    get: { keepAwake.muteAudioWhileRunning },
                    set: { keepAwake.setMuteAudioWhileRunning($0) }
                ))
                optionToggle("Move pointer slightly", systemImage: "cursorarrow.motionlines", value: Binding(
                    get: { keepAwake.movePointerSlightly },
                    set: { keepAwake.setMovePointerSlightly($0) }
                ))
                optionToggle("Keep going with lid closed", systemImage: "laptopcomputer", value: Binding(
                    get: { keepAwake.isClosedLidEnabled },
                    set: { keepAwake.setClosedLidEnabled($0) }
                ))
                .disabled(keepAwake.isAuthorizingClosedLid)
                if keepAwake.isAuthorizingClosedLid {
                    ProgressView("Waiting for administrator approval…").font(.caption)
                }
                if let error = keepAwake.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var sequencesCard: some View {
        automationCard(title: AutomationKind.sequence.title, symbol: AutomationKind.sequence.symbol,
                       values: sequences, kind: .sequence,
                       emptyMessage: "Choose text, a keyboard shortcut or another trigger, then add actions to run in order.")
    }

    private var remapsCard: some View {
        automationCard(title: AutomationKind.keyRemap.title, symbol: AutomationKind.keyRemap.symbol,
                       values: remaps, kind: .keyRemap,
                       emptyMessage: "Give a key or mouse button a new action or shorten long keyboard commands.")
    }

    private func automationCard(title: String, symbol: String, values: [SavedAutomation],
                                kind: AutomationKind, emptyMessage: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Label(title, systemImage: symbol).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { show(.createWorkflow(kind)) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain)
                        .help("Create \(title)")
                        .accessibilityLabel("Create \(title)")
                }
                if values.isEmpty {
                    Text(emptyMessage).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(values) { automation in
                    HStack(spacing: 6) {
                        if kind != .keyRemap {
                            Button {
                                if engine.runningIDs.contains(automation.id) { engine.stop(automation.id) }
                                else { run(automation) }
                            } label: {
                                Image(systemName: engine.runningIDs.contains(automation.id) ? "stop.fill" : "play.fill")
                                    .frame(width: 20, height: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(!automation.isEnabled && !engine.runningIDs.contains(automation.id))
                            .help(engine.runningIDs.contains(automation.id) ? "Stop \(automation.name)" : "Run \(automation.name)")
                            .accessibilityLabel(engine.runningIDs.contains(automation.id) ? "Stop \(automation.name)" : "Play \(automation.name)")
                        }
                        Button {
                            if kind == .keyRemap { show(.edit(automation.id)) }
                            else { run(automation) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(automation.name).lineLimit(1)
                                Text(menuSummary(automation)).font(.caption2)
                                    .foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(kind == .keyRemap ? "Edit \(automation.name)" : "Run \(automation.name)")
                        .accessibilityLabel(kind == .keyRemap ? "Edit \(automation.name)" : "Run \(automation.name)")
                        Toggle("Enable \(automation.name)", isOn: Binding(
                            get: { automation.isEnabled }, set: { store.setEnabled(automation, enabled: $0) }
                        )).labelsHidden().controlSize(.mini)
                        Button { show(.edit(automation.id)) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.plain)
                            .help("Edit \(automation.name)")
                            .accessibilityLabel("Edit \(automation.name)")
                        if automation.workflow != nil && !automation.siriEnabled {
                            Button(role: .destructive) { store.delete(automation) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .help("Delete \(automation.name)")
                                .accessibilityLabel("Delete \(automation.name)")
                        } else {
                            Button { show(.library) } label: { Image(systemName: "ellipsis.circle") }
                                .buttonStyle(.plain)
                                .help("Manage \(automation.name) in the app")
                                .accessibilityLabel("Manage \(automation.name) in the app")
                        }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func menuSummary(_ automation: SavedAutomation) -> String {
        if automation.kind == .keyRemap, let flow = automation.workflow {
            let input = flow.mouseButton >= 0 ? "Mouse button \(flow.mouseButton + 1)" : flow.inputKey?.displayText ?? "Key"
            return "\(input) → \(flow.steps.first?.key?.displayText ?? "Key")"
        }
        let flow = automation.workflow
        let savedTriggers: [SequenceTrigger]
        if let triggers = flow?.sequenceTriggers {
            savedTriggers = triggers
        } else {
            var triggers: [SequenceTrigger] = []
            switch flow?.trigger {
            case .textExpansion: triggers.append(.text)
            case .touchpad: triggers.append(.touchpad)
            case .interval: triggers.append(.interval)
            case .screen: triggers.append(.screen)
            default: break
            }
            if automation.keyboardShortcut != nil { triggers.append(.keyboardShortcut) }
            savedTriggers = triggers.isEmpty ? [.menuBar] : triggers
        }
        let triggers = savedTriggers.map { trigger in
            switch trigger {
            case .text: return "Text: \(flow?.abbreviation ?? "")"
            case .keyboardShortcut: return automation.keyboardShortcut?.displayText ?? trigger.title
            case .screen: return flow?.screenChecks.first?.condition?.action == .screenImage ? SequenceTrigger.screenImage.title : SequenceTrigger.screenPixel.title
            default: return trigger.title
            }
        }
        return triggers.joined(separator: " · ")
    }

    private var inputMonitoringControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Input monitoring", systemImage: "keyboard")
                    .font(.system(size: 12))
                Spacer()
                NativeInputMonitoringSwitch(isOn: Binding(
                    get: { runtime.inputMonitoringEnabled && !runtime.isPaused },
                    set: { runtime.setInputMonitoringEnabled($0) }
                ))
                .fixedSize()
            }
            if runtime.isPaused {
                Text("Automation triggers are paused. Turn on Input monitoring to resume.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .help("Allow keyboard and mouse input to trigger and be used in enabled automations after the required permissions are granted. Ordinary typing is not saved.")
    }

    private var controlsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Quick Controls", systemImage: "slider.horizontal.3").font(.headline)
                if isPowerTools {
                    Text("Input monitoring: \(runtime.inputMonitoringEnabled && !runtime.isPaused ? "On" : "Off"). Change this in the robot menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Stop all running actions") { runtime.stopAllActions() }
                    .disabled(engine.runningIDs.isEmpty)
                Button("Report a Problem…") { ProblemReportCoordinator.shared.show() }
                if bucket.isAvailable { Button {
                    MenuBarController.shared.close()
                    bucket.showWindow()
                } label: {
                    HStack { BucketIcon().frame(width: 16, height: 16); Text("Open File Bucket (\(bucket.items.count))") }
                } }
                if DockWindowCapture.isAvailable { optionToggle("Dock window previews", systemImage: "dock.rectangle", value: Binding(
                    get: { dockPreview.isEnabled }, set: { dockPreview.setEnabled($0) }))
                if let error = dockPreview.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.secondary)
                } }
                if FeatureAvailability.tool("tool.finderCut") { Toggle("Finder Command-X", isOn: Binding(get: { runtime.finderCutEnabled }, set: { enabled in
                    if !enabled {
                        runtime.setFinderCutEnabled(false)
                        finderCutPermissionMessage = nil
                    } else {
                        store.requestFinderCutPermissions { ready in
                            if ready {
                                runtime.setFinderCutEnabled(true)
                                finderCutPermissionMessage = nil
                            } else {
                                finderCutPermissionMessage = "Allow Input Monitoring and \(DesktopAutomationService.controlPermissionName), then enable this again."
                            }
                        }
                    }
                }))
                .toggleStyle(.checkbox)
                if let finderCutPermissionMessage {
                    Text(finderCutPermissionMessage).font(.caption2).foregroundStyle(.secondary)
                } }
                optionToggle("Start at login", systemImage: "menubar.rectangle", value: Binding(
                    get: { backgroundAgent.isEnabled },
                    set: { backgroundAgent.setEnabled($0) }
                ))
                Text("AutoProductive Menu Bar Agent keeps the robot icon and automation triggers available.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let error = backgroundAgent.errorMessage ?? engine.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
        }
    }

    private var audioMixerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Audio Mixer", systemImage: "speaker.wave.2").font(.headline)
                if audioMixer.apps.isEmpty {
                    Text("No other apps are open.")
                        .foregroundStyle(.secondary)
                }
                ForEach(audioMixer.apps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .lineLimit(app.bundleIdentifier == "systemsoundserverd" ? 2 : 1)
                                .help("\(app.name): \(app.volumeHelp)")
                            if app.processObjects.isEmpty { Text("No audio").font(.caption2).foregroundStyle(.secondary) }
                        }.frame(width: 76, alignment: .leading)
                        Slider(value: Binding(
                            get: { audioMixer.volume(for: app.id) },
                            set: { audioMixer.setVolume($0, for: app) }), in: 0...AudioGain.maximum, step: 0.01)
                            .disabled(app.processObjects.isEmpty)
                            .tint(audioMixer.volume(for: app.id) > 1 ? .orange : AppPalette.blue)
                            .accessibilityLabel("\(app.name) volume")
                            .help(app.volumeHelp)
                        AppVolumeField(app: app, mixer: audioMixer)
                    }
                }
                if let error = audioMixer.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Open App") { show() }
                Button("New Automation") { show(.create) }
                Spacer()
                Button("Quit Completely") {
                    backgroundAgent.setEnabled(false)
                    if !backgroundAgent.isEnabled { NSApp.terminate(nil) }
                }
            }
            Text("AutoProductive uses zero trackers, zero accounts, and zero cloud telemetry. We respect your privacy.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func preset(_ title: String, duration: TimeInterval?) -> some View {
        Button(title) { keepAwake.start(for: duration) }
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .tint(AppPalette.blue)
            .accessibilityLabel(duration == nil ? "Keep awake until turned off" : "Keep awake for \(title)")
    }

    private func optionToggle(_ title: String, systemImage: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Label(title, systemImage: systemImage).font(.system(size: 12))
        }
        .controlSize(.small)
        .tint(AppPalette.blue)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: max(0, popupSize.width - 48), alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppPalette.blue.opacity(0.14), lineWidth: 1)
            }
    }

    private func show(_ route: AppRoute? = nil) {
        MenuBarController.shared.close()
        navigation.open(route)
        NSApp.setActivationPolicy(.regular)
        openMainWindow()
        NSApp.activate()
    }

    private func run(_ automation: SavedAutomation) {
        do { try AutomationRunner.run(automation) }
        catch { DiagnosticJournal.shared.recordError("MenuBarView", error); engine.lastError = error.localizedDescription }
    }

}

/// Leaves switch sizing, materials and interaction animations to AppKit.
private struct NativeInputMonitoringSwitch: NSViewRepresentable {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }

    func makeNSView(context: Context) -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .regular
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setAccessibilityLabel("Input monitoring")
        control.setAccessibilityHelp("Allow keyboard and mouse input to trigger and be used in automations.")
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .vertical)
        control.sizeToFit()
        return control
    }

    func updateNSView(_ control: NSSwitch, context: Context) {
        context.coordinator.isOn = $isOn
        control.isEnabled = isEnabled
        let state: NSControl.StateValue = isOn ? .on : .off
        if control.state != state { control.state = state }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSwitch, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func changed(_ sender: NSSwitch) { isOn.wrappedValue = sender.state == .on }
    }
}
