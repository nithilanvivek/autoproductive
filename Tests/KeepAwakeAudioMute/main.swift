import CoreAudio

var current: UInt32? = 1
var values: [UInt32: UInt32] = [1: 0, 2: 1]
var uids = [UInt32(1): "speakers", UInt32(2): "headphones"]
var failWrites = false
let mute = KeepAwakeAudioMute(access: .init(output: {
    guard let current, let uid = uids[current] else { return nil }
    return .init(id: current, uid: uid)
}, uid: { uids[$0] }, deviceWithUID: { uid in
    uids.first(where: { $0.value == uid }).map { .init(id: $0.key, uid: uid) }
}, mute: { values[$0] }, setMute: { id, value in
    guard !failWrites else { return false }
    values[id] = value; return true
}))
precondition(mute.apply() == .muted && values[1] == 1)
precondition(mute.apply() == .muted) // Must not overwrite the original state on repeated polling.
current = 2
precondition(mute.apply() == .muted && values[2] == 1)
precondition(mute.restore() && values[1] == 0 && values[2] == 1)
current = 1
precondition(mute.apply() == .muted)
uids[1] = "different-device-reusing-id"
precondition(mute.restore() && mute.hasPendingRestorations && values[1] == 1, "An absent device is deferred; a reused ID is never changed")
current = nil
precondition(mute.apply() == .unavailable, "A transient missing output is not a mute failure")
uids[3] = "speakers"; values[3] = 1
precondition(mute.restore() && values[3] == 0 && values[1] == 1 && !mute.hasPendingRestorations,
             "Restore the original mute state to the same device after it reconnects under a new ID")
current = 3
precondition(mute.apply() == .muted && values[3] == 1)
uids.removeValue(forKey: 3); uids[4] = "speakers"; values[4] = 0; current = 4
precondition(mute.apply() == .muted && values[4] == 1)
precondition(mute.restore() && values[4] == 0, "A reconnect while active retains the first original mute state")
precondition(mute.apply() == .muted)
failWrites = true
precondition(!mute.restore() && mute.hasPendingRestorations, "A real write failure remains visible and retryable")
failWrites = false
precondition(mute.restore() && values[4] == 0 && !mute.hasPendingRestorations)
var warnings = KeepAwakeAudioMute.FailureTracker()
precondition(!warnings.shouldWarn(for: .failed) && !warnings.shouldWarn(for: .failed))
precondition(!warnings.shouldWarn(for: .muted), "A recovered route change must not show a warning")
precondition(!warnings.shouldWarn(for: .failed) && !warnings.shouldWarn(for: .failed))
precondition(warnings.shouldWarn(for: .failed), "A persistent mute failure must still be reported")
precondition(!warnings.shouldWarn(for: .unavailable) && !warnings.shouldWarn(for: .failed),
             "A missing output resets the transient failure count")
print("Passed Keep Awake mute checks: original state, route changes, reconnects, deferred restoration, ID reuse, and write failures.")
