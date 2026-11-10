import Foundation

@main struct Tests {
    static func main() throws {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let component = try FeatureAudioMixerLibrary(verifiedBytes: bytes)
        guard component.makeTap(processObjects: [], outputUID: "unused", gain: 1) == nil,
              component.makeTap(processObjects: Array(repeating: 1, count: 4097), outputUID: "unused", gain: 1) == nil else {
            fatalError("Invalid process lists must not create an audio tap")
        }
        let library = try FeatureToolLibrary.open(verifiedBytes: bytes, expectedID: "tool.audioMixer")
        typealias Create = @convention(c) (UnsafePointer<UInt32>?, Int32, UnsafePointer<CChar>?, Float) -> UnsafeMutableRawPointer?
        let create = unsafeBitCast(try library.symbol("autoproductive_audio_tap_create"), to: Create.self)
        var object: UInt32 = 1
        let invalid = withUnsafePointer(to: &object) { ptr in
            "unused".withCString { uid in create(ptr, 1, uid, .nan) }
        }
        guard invalid == nil else { fatalError("Invalid gain must not create an audio tap") }
        print("Passed signed audio component loading and input checks without changing audio.")
    }
}
