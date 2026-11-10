#if !MODULAR_FEATURES
import AppKit
import AudioToolbox
import CoreAudio

@MainActor
enum SystemControlService {
    struct Access {
        var read: () -> Double?
        var write: (Double) -> Bool
    }

    static func apply(_ step: WorkflowStep, access: Access, label: String) throws {
        guard let operation = PercentageAdjustment(rawValue: step.option), step.amount.isFinite,
              (0...100).contains(step.amount) else { throw WorkflowError.invalid("Choose a percentage from 0 to 100.") }
        let current: Double
        if operation == .set { current = 0 }
        else {
            guard let value = access.read(), value.isFinite, (0...100).contains(value) else {
                throw WorkflowError.invalid("The current \(label) could not be read on this device.")
            }
            current = value
        }
        guard access.write(operation.applying(step.amount, to: current)) else {
            throw WorkflowError.invalid("This device does not support changing \(label) from an app.")
        }
    }

    static func adjustSound(_ step: WorkflowStep) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { throw WorkflowError.invalid("No sound output device is available.") }
        // The virtual main volume handles both main and channel-based controls,
        // preserving relative channel balance. Capture the output once per action.
        try apply(step, access: Access(read: {
            var property = volumeAddress
            var value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            guard AudioHardwareServiceGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value) * 100
        }, write: { percentage in
            var property = volumeAddress
            var value = Float32(percentage / 100)
            return AudioHardwareServiceSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
        }), label: "sound output volume")
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func adjustBrightness(_ step: WorkflowStep) throws {
        let display = CGMainDisplayID()
        try apply(step, access: Access(read: {
            var value: Float = 0
            if let get = BrightnessBridge.get, get(display, &value) == 0 { return Double(value) * 100 }
            return nil
        }, write: { percentage in
            let value = Float(percentage / 100)
            if let set = BrightnessBridge.set, set(display, value) == 0 { return true }
            return false
        }), label: "display brightness")
    }
}

/// Apple Silicon needs DisplayServices for hardware brightness. Resolve these
/// symbols at runtime so unsupported systems fail without simulating a dim overlay.
private enum BrightnessBridge {
    typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
    static let get: Get? = symbol("DisplayServicesGetBrightness", as: Get.self)
    static let set: Set? = symbol("DisplayServicesSetBrightness", as: Set.self)
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let value = dlsym(handle, name) else { return nil }
        return unsafeBitCast(value, to: T.self)
    }
}
#endif
