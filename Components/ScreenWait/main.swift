import Foundation

struct Request: Decodable { let duration: Double?; let selfTest: Bool? }
struct Response: Encodable { let duration: Double; let pollInterval: Double }
enum ComponentError: Error { case invalid }
#if ACTION_SCREEN_PIXEL
let feature = "action.screenPixel"
#elseif ACTION_SCREEN_IMAGE
let feature = "action.screenImage"
#else
#error("Choose a screen-wait action when building this component")
#endif

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 4096 else { throw ComponentError.invalid }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["feature": feature, "api": 1]))
        exit(0)
    }
    guard let duration = request.duration, duration.isFinite, (0...300).contains(duration) else { throw ComponentError.invalid }
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(Response(duration: duration, pollInterval: 0.3)))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Screen wait action failed.\n".utf8))
    exit(1)
}
