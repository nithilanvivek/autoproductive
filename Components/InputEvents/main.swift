import Foundation

struct Request: Decodable {
    let selfTest: Bool?
    let keyCode: UInt32?
    let modifiers: UInt?
    let text: String?
    let x: Double?
    let y: Double?
    let button: String?
    let coordinatesInPixels: Bool?
    let displayScale: Double?
    let displayWidth: Double?
    let displayHeight: Double?
}
enum ComponentError: Error { case invalid }
#if ACTION_PRESS_KEY
let feature = "action.pressKey"
#elseif ACTION_PASTE
let feature = "action.pasteClipboard"
#elseif ACTION_TYPE_TEXT
let feature = "action.typeText"
#elseif ACTION_CLICK
let feature = "action.click"
#elseif ACTION_MOVE_POINTER
let feature = "action.movePointer"
#elseif ACTION_SCROLL
let feature = "action.scroll"
#else
#error("Choose an input action when building this component")
#endif

do {
    let bytes = FileHandle.standardInput.readDataToEndOfFile()
    guard bytes.count <= 20 * 1024 * 1024 else { throw ComponentError.invalid }
    let request = try JSONDecoder().decode(Request.self, from: bytes)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["feature": feature, "api": 1]))
        exit(0)
    }
    var events: [FeatureInputPlan.Event] = []
    #if ACTION_PRESS_KEY
    guard let code = request.keyCode, let modifiers = request.modifiers else { throw ComponentError.invalid }
    events = [.init(kind: "key", keyCode: code, modifiers: modifiers)]
    #elseif ACTION_PASTE
    events = [.init(kind: "key", keyCode: 9, modifiers: 1)]
    #elseif ACTION_TYPE_TEXT
    guard let text = request.text else { throw ComponentError.invalid }
    events = text.isEmpty ? [] : [.init(kind: "unicode", text: text)]
    #elseif ACTION_CLICK || ACTION_MOVE_POINTER
    guard var x = request.x, var y = request.y, x.isFinite, y.isFinite else { throw ComponentError.invalid }
    if request.coordinatesInPixels == true {
        guard let scale = request.displayScale, let width = request.displayWidth, let height = request.displayHeight,
              scale.isFinite, scale > 0, x >= 0, y >= 0, x < width * scale, y < height * scale else { throw ComponentError.invalid }
        x /= scale; y /= scale
    }
    let button = ["left", "right", "middle"].contains(request.button ?? "") ? request.button! : "left"
    #if ACTION_CLICK
    events = [.init(kind: "click", x: x, y: y, button: button)]
    #else
    events = [.init(kind: "move", x: x, y: y, button: button)]
    #endif
    #elseif ACTION_SCROLL
    guard let x = request.x, let y = request.y, x.isFinite, y.isFinite else { throw ComponentError.invalid }
    events = [.init(kind: "scroll", x: max(-10_000, min(10_000, x)), y: max(-10_000, min(10_000, y)))]
    #endif
    let plan = FeatureInputPlan(events: events)
    try plan.validate()
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(plan))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Input action failed.\n".utf8))
    exit(1)
}
