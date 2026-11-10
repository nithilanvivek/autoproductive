import AppKit
import SwiftUI

struct AudioMixerView: View {
    @ObservedObject private var mixer = AppAudioMixer.shared

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 14) {
                Text("Audio Mixer").font(.largeTitle.bold())
                Text("All open apps are listed. Adjust audio from 0–200%; “No audio” means macOS has no audio stream available to control for that app; it does not refer to open windows. At 100%, sound passes through macOS normally.")
                    .foregroundStyle(.secondary)
                Text("System Sounds controls shared macOS alerts and interface feedback, including Sound settings previews. These sounds are separate from each app's own audio.")
                    .font(.callout).foregroundStyle(.secondary)
                if mixer.apps.isEmpty {
                    ContentUnavailableView("No other apps are open", systemImage: "speaker.wave.2",
                                           description: Text("Open an app to see it here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(mixer.apps) { app in
                                HStack(spacing: 12) {
                                    Image(nsImage: app.icon).resizable().frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name).lineLimit(1).help(app.volumeHelp)
                                        if app.processObjects.isEmpty { Text("No audio").font(.caption).foregroundStyle(.secondary) }
                                    }.frame(width: 145, alignment: .leading)
                                    Slider(value: Binding(
                                        get: { mixer.volume(for: app.id) },
                                        set: { mixer.setVolume($0, for: app) }), in: 0...AudioGain.maximum, step: 0.01)
                                        .disabled(app.processObjects.isEmpty)
                                        .tint(mixer.volume(for: app.id) > 1 ? .orange : AppPalette.blue)
                                        .help(app.volumeHelp)
                                    AppVolumeField(app: app, mixer: mixer)
                                }
                                .padding(10)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                if let error = mixer.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
                Text("Adjusting an app may ask for System Audio Recording access. AutoProductive processes sound locally and does not save it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { mixer.start() }
    }
}

struct AppVolumeField: View {
    let app: AudioMixerApp
    @ObservedObject var mixer: AppAudioMixer

    var body: some View {
        HStack(spacing: 2) {
            TextField("Volume", value: Binding<Int>(
                get: { Int((mixer.volume(for: app.id) * 100).rounded()) },
                set: { mixer.setVolume(Double(max(0, min(Int(AudioGain.maximum * 100), $0))) / 100, for: app) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 42)
            .disabled(app.processObjects.isEmpty)
            .accessibilityLabel("\(app.name) volume percentage")
            .help("Enter a volume from 0–200%.")
            Text("%")
        }
    }
}
