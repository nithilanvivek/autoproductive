import AppKit
import Combine
import CoreAudio

struct AudioMixerApp: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let processObjects: [AudioObjectID]
    let bundleIdentifier: String?

    var volumeHelp: String {
        if bundleIdentifier == "systemsoundserverd" {
            return "Controls shared macOS alert and interface sounds across apps. 100% is the original volume."
        }
        if bundleIdentifier == "com.apple.systempreferences" {
            return "Controls this app's audio. Alert previews and volume feedback use System Sounds."
        }
        return processObjects.isEmpty ? "Start audio in this app to adjust its volume." : "0–200%. 100% is the original volume."
    }
}

/// A process tap is created only after the user changes an app's volume.
/// At 100% the tap is removed so the app plays through macOS unchanged.
@MainActor
final class AppAudioMixer: ObservableObject {
    static let shared = AppAudioMixer()

    @Published private(set) var apps: [AudioMixerApp] = []
    @Published private(set) var volumes: [pid_t: Double] = [:]
    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("AppAudioMixer", errorMessage)
            }
        }
    }

    private var timer: Timer?
    private var engines: [pid_t: any AudioVolumeEngine] = [:]
    private var outputUID: String?
    private var helperOwners: [pid_t: pid_t] = [:]
    private var helperResolution: Task<Void, Never>?
    private var lastHelperResolution = Date.distantPast
    private let component: FeatureAudioMixerLibrary?
    let isAvailable: Bool

    private init() {
        var loaded: FeatureAudioMixerLibrary?
        var available = true
        var loadError: String?
        do {
            if let bytes = try FeatureComponentDispatcher.toolBytes(id: "tool.audioMixer") {
                loaded = try FeatureAudioMixerLibrary(verifiedBytes: bytes)
            } else {
                #if MODULAR_FEATURES
                available = false
                #endif
            }
        } catch FeatureComponentDispatcher.DispatchError.missingComponent {
            available = false
        } catch {
            available = false
            loadError = error.localizedDescription
        }
        component = loaded
        isAvailable = available
        errorMessage = loadError
    }

    func start() {
        guard isAvailable, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        helperResolution?.cancel()
        helperResolution = nil
        helperOwners.removeAll()
        for engine in engines.values { engine.stop() }
        engines.removeAll()
    }

    func volume(for pid: pid_t) -> Double { volumes[pid] ?? 1 }

    func setVolume(_ value: Double, for app: AudioMixerApp) {
        guard isAvailable else { return }
        let volume = AudioGain.clamped(value)
        volumes[app.id] = volume
        if AudioGain.isUnity(volume) {
            engines.removeValue(forKey: app.id)?.stop()
            return
        }
        guard !app.processObjects.isEmpty else { return }
        if let engine = engines[app.id] {
            engine.gain = Float(volume)
            return
        }
        guard let outputUID = Self.defaultOutputUID() else {
            errorMessage = "No audio output is available."
            return
        }
        guard #available(macOS 14.2, *) else {
            volumes[app.id] = 1
            errorMessage = "App volume controls require macOS 14.2 or later."
            return
        }
        let engine: (any AudioVolumeEngine)?
        if let component {
            engine = component.makeTap(processObjects: app.processObjects, outputUID: outputUID, gain: Float(volume))
        } else {
            #if MODULAR_FEATURES
            engine = nil
            #else
            engine = ProcessVolumeTap(processObjects: app.processObjects, outputUID: outputUID, gain: Float(volume))
            #endif
        }
        guard let engine else {
            volumes[app.id] = 1
            errorMessage = "Could not control \(app.name). Check System Audio Recording permission, then try again."
            return
        }
        engines[app.id] = engine
        errorMessage = nil
    }

    private func refresh() {
        let newUID = Self.defaultOutputUID()
        if newUID != outputUID {
            // Taps target one physical output. Hand sound back immediately
            // when the user changes speakers or headphones.
            for engine in engines.values { engine.stop() }
            engines.removeAll()
            volumes.removeAll()
            outputUID = newUID
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var audioObjects: [pid_t: [AudioObjectID]] = [:]
        var systemSounds: [pid_t: [AudioObjectID]] = [:]
        var hasUnownedAudio = false
        for object in Self.processObjects() {
            guard let pid: pid_t = Self.property(object, kAudioProcessPropertyPID), pid > 0, pid != ownPID else { continue }
            let identifier: CFString? = Self.property(object, kAudioProcessPropertyBundleID)
            let bundleID = identifier.map { $0 as String }
            // Alert previews and UI feedback share a system-wide audio service;
            // attributing it to Settings would also mute other applications' alerts.
            if bundleID == "systemsoundserverd" {
                systemSounds[pid, default: []].append(object)
                continue
            }
            let directOwner = running.first { $0.processIdentifier == pid }
                ?? running.filter { app in
                    guard let bundleID, let appID = app.bundleIdentifier else { return false }
                    return bundleID == appID || bundleID.hasPrefix(appID + ".")
                }.max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
            hasUnownedAudio = hasUnownedAudio || directOwner == nil
            let owner = directOwner ?? running.first { $0.processIdentifier == helperOwners[pid] }
            if let owner { audioObjects[owner.processIdentifier, default: []].append(object) }
        }
        if hasUnownedAudio, helperResolution == nil, Date().timeIntervalSince(lastHelperResolution) > 10 {
            lastHelperResolution = Date()
            let pids = running.map(\.processIdentifier)
            helperResolution = Task { [weak self] in
                let owners = await Task.detached(priority: .utility) { AudioHelperResolver.owners(for: pids) }.value
                guard !Task.isCancelled, let self else { return }
                self.helperOwners = owners
                self.helperResolution = nil
                self.refresh()
            }
        }
        let applicationRows = running.filter { $0.processIdentifier != ownPID }.compactMap { app -> AudioMixerApp? in
            guard let name = app.localizedName else { return nil }
            let icon = app.icon ?? NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 32, height: 32))
            return AudioMixerApp(id: app.processIdentifier, name: name, icon: icon,
                                 processObjects: (audioObjects[app.processIdentifier] ?? []).sorted(),
                                 bundleIdentifier: app.bundleIdentifier)
        }
        let systemRows = systemSounds.map { pid, objects in
            AudioMixerApp(id: pid, name: "System Sounds",
                          icon: NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)
                              ?? NSImage(size: NSSize(width: 32, height: 32)),
                          processObjects: objects.sorted(), bundleIdentifier: "systemsoundserverd")
        }
        apps = (applicationRows + systemRows).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let valid = Set(apps.map(\.id))
        for pid in Array(engines.keys) where !valid.contains(pid) {
            engines.removeValue(forKey: pid)?.stop()
        }
        for pid in Array(volumes.keys) where !valid.contains(pid) { volumes.removeValue(forKey: pid) }
        for app in apps {
            if let engine = engines[app.id], engine.processObjects != app.processObjects {
                engines.removeValue(forKey: app.id)?.stop()
            }
            let volume = volume(for: app.id)
            if engines[app.id] == nil, !app.processObjects.isEmpty, !AudioGain.isUnity(volume) {
                setVolume(volume, for: app)
            }
        }
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address,
                                             0, nil, &bytes) == noErr else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &bytes, &result) == noErr else { return [] }
        return result
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var bytes = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, value) == noErr else { return nil }
        return value.move()
    }

    private static func defaultOutputUID() -> String? {
        guard let device: AudioObjectID = property(AudioObjectID(kAudioObjectSystemObject),
                                                    kAudioHardwarePropertyDefaultOutputDevice), device != 0,
              let uid: CFString = property(device, kAudioDevicePropertyDeviceUID) else { return nil }
        return uid as String
    }
}

#if !MODULAR_FEATURES
@available(macOS 14.2, *)
private final class ProcessVolumeTap: AudioVolumeEngine {
    private final class RenderState {
        var limiter: AudioPeakLimiter
        init(sampleRate: Double) { limiter = AudioPeakLimiter(sampleRate: sampleRate) }
    }
    private final class Gain {
        private var bits: Int32
        init(_ value: Float) { bits = Int32(bitPattern: value.bitPattern) }
        var value: Float {
            get { Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &bits))) }
            set {
                let replacement = Int32(bitPattern: newValue.bitPattern)
                while true {
                    let current = OSAtomicAdd32Barrier(0, &bits)
                    if OSAtomicCompareAndSwap32Barrier(current, replacement, &bits) { return }
                }
            }
        }
    }

    private let box: Gain
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    let processObjects: [AudioObjectID]

    var gain: Float {
        get { box.value }
        set { box.value = newValue }
    }

    init?(processObjects: [AudioObjectID], outputUID: String, gain: Float) {
        self.processObjects = processObjects
        box = Gain(gain)
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != 0 else {
            DiagnosticJournal.shared.recordErrorMessage("Audio mixer", "Create process tap failed; status=\(tapStatus)")
            return nil
        }

        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AutoProductive Audio Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        let aggregateStatus = AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID)
        guard aggregateStatus == noErr,
              aggregateID != 0 else {
            DiagnosticJournal.shared.recordErrorMessage("Audio mixer", "Create aggregate device failed; status=\(aggregateStatus)")
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
            return nil
        }
        var rate = 48_000.0
        var rateSize = UInt32(MemoryLayout<Double>.size)
        var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(aggregateID, &rateAddress, 0, nil, &rateSize, &rate)
        let state = RenderState(sampleRate: rate)
        let level = box
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { _, input, _, output, _ in
            let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(output)
            guard let source = sourceBuffers.last(where: { $0.mData != nil && $0.mNumberChannels > 0 }),
                  let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return }
            let inputChannels = Int(source.mNumberChannels)
            let sourceFrames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * inputChannels)
            let gain = level.value
            let maxFrames = destinationBuffers.reduce(0) { count, buffer in
                guard buffer.mNumberChannels > 0 else { return count }
                return max(count, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels)))
            }
            for frame in 0..<maxFrames {
                var peak: Float = 0
                if frame < sourceFrames {
                    for channel in 0..<inputChannels {
                        let sample = samples[frame * inputChannels + channel]
                        if sample.isFinite { peak = max(peak, abs(sample)) }
                    }
                }
                let frameGain = state.limiter.frameGain(peak: peak, requested: gain)
                var outputOffset = 0
                for buffer in destinationBuffers {
                    let channels = Int(buffer.mNumberChannels)
                    guard channels > 0, let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                        outputOffset += channels
                        continue
                    }
                    let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                    guard frame < frames else { outputOffset += channels; continue }
                    for channel in 0..<channels {
                        let sourceChannel = outputOffset + channel
                        let sample: Float
                        if frame >= sourceFrames {
                            sample = 0
                        } else if sourceChannel < inputChannels {
                            sample = samples[frame * inputChannels + sourceChannel]
                        } else if inputChannels == 1 && sourceChannel == 1 {
                            sample = samples[frame]
                        } else {
                            sample = 0
                        }
                        destination[frame * channels + channel] = sample.isFinite ? sample * frameGain : 0
                    }
                    outputOffset += channels
                }
            }
        })
        guard ioStatus == noErr, ioProc != nil else {
            DiagnosticJournal.shared.recordErrorMessage("Audio mixer", "Create audio callback failed; status=\(ioStatus)")
            stop()
            return nil
        }
        let startStatus = AudioDeviceStart(aggregateID, ioProc)
        guard startStatus == noErr else {
            DiagnosticJournal.shared.recordErrorMessage("Audio mixer", "Start audio device failed; status=\(startStatus)")
            stop()
            return nil
        }
    }

    func stop() {
        if let ioProc, aggregateID != 0 { AudioDeviceStop(aggregateID, ioProc) }
        if let ioProc, aggregateID != 0 { AudioDeviceDestroyIOProcID(aggregateID, ioProc) }
        ioProc = nil
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID); tapID = 0 }
    }

    deinit { stop() }
}
#endif
