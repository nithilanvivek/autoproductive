import CoreAudio
import Foundation
import Darwin

@available(macOS 14.2, *)
private final class ProcessVolumeTap {
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
            stop()
            return nil
        }
        let startStatus = AudioDeviceStart(aggregateID, ioProc)
        guard startStatus == noErr else {
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

private let featureID = strdup("tool.audioMixer")!

@_cdecl("autoproductive_tool_api_version")
public func toolAPIVersion() -> Int32 { 1 }
@_cdecl("autoproductive_tool_feature_id")
public func toolFeatureID() -> UnsafePointer<CChar>? { UnsafePointer(featureID) }
@_cdecl("autoproductive_audio_tap_create")
public func createAudioTap(_ processes: UnsafePointer<UInt32>?, _ count: Int32,
                           _ output: UnsafePointer<CChar>?, _ gain: Float) -> UnsafeMutableRawPointer? {
    guard #available(macOS 14.2, *), let processes, count > 0, count <= 4096,
          let output, strnlen(output, 4096) < 4096, let uid = String(validatingUTF8: output), !uid.isEmpty,
          gain.isFinite, gain >= 0, gain <= 2 else { return nil }
    let ids = Array(UnsafeBufferPointer(start: processes, count: Int(count)))
    guard let tap = ProcessVolumeTap(processObjects: ids, outputUID: uid, gain: gain) else { return nil }
    return Unmanaged.passRetained(tap).toOpaque()
}
@_cdecl("autoproductive_audio_tap_gain")
public func getAudioTapGain(_ pointer: UnsafeMutableRawPointer?) -> Float {
    guard #available(macOS 14.2, *), let pointer else { return 1 }
    return Unmanaged<ProcessVolumeTap>.fromOpaque(pointer).takeUnretainedValue().gain
}
@_cdecl("autoproductive_audio_tap_set_gain")
public func setAudioTapGain(_ pointer: UnsafeMutableRawPointer?, _ gain: Float) {
    guard #available(macOS 14.2, *), let pointer, gain.isFinite, gain >= 0, gain <= 2 else { return }
    Unmanaged<ProcessVolumeTap>.fromOpaque(pointer).takeUnretainedValue().gain = gain
}
@_cdecl("autoproductive_audio_tap_destroy")
public func destroyAudioTap(_ pointer: UnsafeMutableRawPointer?) {
    guard #available(macOS 14.2, *), let pointer else { return }
    Unmanaged<ProcessVolumeTap>.fromOpaque(pointer).release()
}
