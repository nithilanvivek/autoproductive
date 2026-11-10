import CoreAudio
import Foundation

/// Restores each output's prior state, including outputs selected during a session.
final class KeepAwakeAudioMute {
    struct Device: Equatable { let id: AudioObjectID; let uid: String }
    enum ApplyResult { case muted, unavailable, failed }
    struct FailureTracker {
        private var consecutiveFailures = 0
        mutating func shouldWarn(for result: ApplyResult) -> Bool {
            guard result == .failed else { consecutiveFailures = 0; return false }
            consecutiveFailures += 1
            return consecutiveFailures >= 3
        }
    }
    struct Access {
        var output: () -> Device?
        var uid: (AudioObjectID) -> String?
        var deviceWithUID: (String) -> Device?
        var mute: (AudioObjectID) -> UInt32?
        var setMute: (AudioObjectID, UInt32) -> Bool
    }
    private let access: Access
    private var originals: [String: (Device, UInt32)] = [:]
    init(access: Access = .system) { self.access = access }

    var hasPendingRestorations: Bool { !originals.isEmpty }

    @discardableResult func apply() -> ApplyResult {
        guard let device = access.output() else { return .unavailable }
        guard let mute = access.mute(device.id) else { return .failed }
        if let (_, original) = originals[device.uid] {
            // A reconnect can give the same device a different Core Audio ID.
            originals[device.uid] = (device, original)
        } else {
            originals[device.uid] = (device, mute)
        }
        return mute == 1 || access.setMute(device.id, 1) ? .muted : .failed
    }

    @discardableResult func restore() -> Bool {
        var success = true
        for (uid, (device, original)) in originals {
            // Numeric IDs can be reused or change on reconnect. Keep an absent
            // device pending and retry later; never write to a different UID.
            let connected = access.uid(device.id) == uid ? device : access.deviceWithUID(uid)
            guard let connected, access.uid(connected.id) == uid else { continue }
            if access.mute(connected.id) == original || access.setMute(connected.id, original) {
                originals.removeValue(forKey: uid)
            } else { success = false }
        }
        return success
    }

    fileprivate static func uid(_ id: AudioObjectID) -> String? {
        let value: CFString? = read(id, selector: kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
        return value as String?
    }

    fileprivate static func read<T>(_ id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.move()
    }
}

extension KeepAwakeAudioMute.Access {
    static let system = Self(output: {
        guard let id: AudioObjectID = KeepAwakeAudioMute.read(AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal),
            id != 0, let uid = KeepAwakeAudioMute.uid(id) else { return nil }
        return .init(id: id, uid: uid)
    }, uid: { KeepAwakeAudioMute.uid($0) }, deviceWithUID: { uid in
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var qualifier = uid as CFString
        var id = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), UnsafeRawPointer(pointer), &size, &id)
        }
        guard status == noErr,
            id != 0, KeepAwakeAudioMute.uid(id) == uid else { return nil }
        return .init(id: id, uid: uid)
    }, mute: { id in
        KeepAwakeAudioMute.read(id, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }, setMute: { id, mute in
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value = mute
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    })
}
