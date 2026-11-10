import CoreAudio
import Foundation

/// A tap stays in the signed app process so the existing system-audio
/// permission continues to apply. The library is retained until the tap stops.
final class FeatureAudioMixerLibrary {
    private typealias Create = @convention(c) (UnsafePointer<UInt32>?, Int32, UnsafePointer<CChar>?, Float) -> UnsafeMutableRawPointer?
    private typealias GetGain = @convention(c) (UnsafeMutableRawPointer?) -> Float
    private typealias SetGain = @convention(c) (UnsafeMutableRawPointer?, Float) -> Void
    private typealias Destroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private let library: FeatureToolLibrary
    private let create: Create
    private let getGain: GetGain
    private let setGain: SetGain
    private let destroy: Destroy

    init(verifiedBytes: Data) throws {
        let library = try FeatureToolLibrary.open(verifiedBytes: verifiedBytes, expectedID: "tool.audioMixer", requiredSymbols: [
            "autoproductive_audio_tap_create", "autoproductive_audio_tap_gain", "autoproductive_audio_tap_set_gain", "autoproductive_audio_tap_destroy"])
        create = unsafeBitCast(try library.symbol("autoproductive_audio_tap_create"), to: Create.self)
        getGain = unsafeBitCast(try library.symbol("autoproductive_audio_tap_gain"), to: GetGain.self)
        setGain = unsafeBitCast(try library.symbol("autoproductive_audio_tap_set_gain"), to: SetGain.self)
        destroy = unsafeBitCast(try library.symbol("autoproductive_audio_tap_destroy"), to: Destroy.self)
        self.library = library
    }

    func makeTap(processObjects: [AudioObjectID], outputUID: String, gain: Float) -> (any AudioVolumeEngine)? {
        guard !processObjects.isEmpty, processObjects.count <= 4096 else { return nil }
        let pointer = processObjects.withUnsafeBufferPointer { buffer in
            outputUID.withCString { create(buffer.baseAddress, Int32(buffer.count), $0, gain) }
        }
        guard let pointer else { return nil }
        return Tap(owner: self, pointer: pointer, processObjects: processObjects)
    }

    private final class Tap: AudioVolumeEngine {
        private let owner: FeatureAudioMixerLibrary
        private var pointer: UnsafeMutableRawPointer?
        let processObjects: [AudioObjectID]
        init(owner: FeatureAudioMixerLibrary, pointer: UnsafeMutableRawPointer, processObjects: [AudioObjectID]) {
            self.owner = owner
            self.pointer = pointer
            self.processObjects = processObjects
        }
        var gain: Float {
            get { owner.getGain(pointer) }
            set { if pointer != nil { owner.setGain(pointer, newValue) } }
        }
        func stop() {
            if let pointer { owner.destroy(pointer) }
            pointer = nil
        }
        deinit { stop() }
    }
}
