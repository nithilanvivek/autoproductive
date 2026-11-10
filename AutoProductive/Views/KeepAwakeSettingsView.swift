import SwiftUI

struct KeepAwakeSettingsView: View {
    @EnvironmentObject private var keepAwake: KeepAwakeManager
    @State private var hours = 1
    @State private var minutes = 0
    @State private var endTime = Date().addingTimeInterval(60 * 60)

    private var duration: TimeInterval {
        TimeInterval(hours * 60 + minutes) * 60
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    SymbolTile(symbol: "moon.stars.fill", color: AppPalette.indigo, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep Awake").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(keepAwake.status).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(keepAwake.isActive ? "Stop Keep Awake" : "Start Keep Awake") {
                        keepAwake.isActive ? keepAwake.stop() : keepAwake.start()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("For a duration").font(.headline)
                    HStack {
                        Stepper("Hours: \(hours)", value: $hours, in: 0...168)
                        Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                    }
                    Button("Start for \(hours)h \(minutes)m") { keepAwake.start(for: duration) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(duration <= 0)
                }
                .padding(20)
                .glassCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Until an end time").font(.headline)
                    DatePicker("End time", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                    Button("Start until end time") { keepAwake.start(until: endTime) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(endTime <= Date())
                }
                .padding(20)
                .glassCard()

                HStack {
                    Button("Infinite (until turned off)") { keepAwake.start() }
                    Spacer()
                }
                Toggle("Allow display to sleep", isOn: Binding(
                    get: { keepAwake.allowDisplaySleep },
                    set: { keepAwake.setAllowDisplaySleep($0) }
                ))
                Text("Off by default. Leave unchecked to keep the display awake and prevent the automatic screensaver while Keep Awake runs.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Mute audio while running", isOn: Binding(
                    get: { keepAwake.muteAudioWhileRunning },
                    set: { keepAwake.setMuteAudioWhileRunning($0) }
                ))
                Text("Restores each output’s previous mute state when Keep Awake stops.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Move pointer slightly every 5 minutes", isOn: Binding(
                    get: { keepAwake.movePointerSlightly },
                    set: { keepAwake.setMovePointerSlightly($0) }
                ))
                Text("On by default. Pointer movement pauses when Allow display to sleep is on, while closed-lid mode is enabled, or while the screen is locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Keep awake with the lid closed", isOn: Binding(
                    get: { keepAwake.isClosedLidEnabled },
                    set: { keepAwake.setClosedLidEnabled($0) }
                ))
                .disabled(keepAwake.isAuthorizingClosedLid)

                Text("Closed-lid mode changes a system-wide power setting so work continues with the lid shut. Your display-sleep choice still applies while the lid is open. On first use, macOS asks for an administrator password to allow only the on/off commands. The setting turns off when the session ends. Heat or battery protection may still put the Mac to sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Remove closed-lid admin permission…") { keepAwake.removeClosedLidPermission() }
                    .disabled(keepAwake.isClosedLidEnabled || keepAwake.isAuthorizingClosedLid)

                if keepAwake.isAuthorizingClosedLid {
                    ProgressView("Waiting for administrator approval…")
                }

                if let errorMessage = keepAwake.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
            }
            .padding(28)
        }
        .frame(width: 570, height: 750)
    }
}
