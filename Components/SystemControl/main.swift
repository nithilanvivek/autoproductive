import Foundation
import CoreGraphics
import CoreAudio
import AudioToolbox
import Darwin

struct Request: Decodable { let option: String?; let amount: Double?; let selfTest: Bool? }
#if ACTION_SOUND
let feature = "action.adjustSound"
#elseif ACTION_BRIGHTNESS
let feature = "action.adjustBrightness"
#else
#error("Choose a system control when building this component")
#endif

enum ComponentError: Error { case invalidInput, unavailable }

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 4096 else { throw ComponentError.invalidInput }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["feature": feature, "api": 1]))
        exit(0)
    }
    guard let operation = request.option, let amount = request.amount, amount.isFinite,
          (0...100).contains(amount), ["set", "increase", "decrease"].contains(operation) else { throw ComponentError.invalidInput }
    #if ACTION_SOUND
    var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var device = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &device) == noErr, device != 0 else { throw ComponentError.unavailable }
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var old: Float32 = 0, volumeSize = UInt32(MemoryLayout<Float32>.size)
    if operation != "set" {
        guard AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &volumeSize, &old) == noErr else { throw ComponentError.unavailable }
    }
    let current = Double(old) * 100
    guard operation == "set" || (current.isFinite && (0...100).contains(current)) else { throw ComponentError.unavailable }
    let target = min(100, max(0, operation == "set" ? amount : operation == "increase" ? current + amount : current - amount))
    var value = Float32(target / 100)
    guard AudioHardwareServiceSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr else { throw ComponentError.unavailable }
    #elseif ACTION_BRIGHTNESS
    typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL),
          let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else { throw ComponentError.unavailable }
    defer { dlclose(handle) }
    let display = CGMainDisplayID()
    var current: Float = 0
    if operation != "set" {
        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              unsafeBitCast(getSymbol, to: Getter.self)(display, &current) == 0 else { throw ComponentError.unavailable }
    }
    let old = Double(current) * 100
    guard operation == "set" || (old.isFinite && (0...100).contains(old)) else { throw ComponentError.unavailable }
    let target = min(100, max(0, operation == "set" ? amount : operation == "increase" ? old + amount : old - amount))
    guard unsafeBitCast(setSymbol, to: Setter.self)(display, Float(target / 100)) == 0 else { throw ComponentError.unavailable }
    #endif
    try FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("System control action failed.\n".utf8))
    exit(1)
}
