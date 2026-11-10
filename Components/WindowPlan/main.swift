import Foundation
import CoreGraphics

struct Request: Decodable {
    let selfTest: Bool?
    let option: String?
    let x: Double?
    let y: Double?
    let amount: Double?
    let heightText: String?
    let areaX: Double?
    let areaY: Double?
    let areaWidth: Double?
    let areaHeight: Double?
}
struct Response: Encodable { let kind: String; let x: Double?; let y: Double?; let width: Double?; let height: Double? }
enum ComponentError: Error { case invalid }

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 1024 * 1024 else { throw ComponentError.invalid }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: Data(#"{"feature":"action.window","api":1}"#.utf8))
        exit(0)
    }
    guard let option = request.option else { throw ComponentError.invalid }
    if option == "focus" || option == "minimize" {
        try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(Response(kind: option, x: nil, y: nil, width: nil, height: nil)))
        exit(0)
    }
    guard let x = request.areaX, let y = request.areaY, let width = request.areaWidth, let height = request.areaHeight,
          [x,y,width,height].allSatisfy(\.isFinite), width >= 0, height >= 0 else { throw ComponentError.invalid }
    var frame = CGRect(x: x, y: y, width: width, height: height)
    switch option {
    case "leftHalf": frame.size.width /= 2
    case "rightHalf": frame.origin.x += width / 2; frame.size.width /= 2
    case "center": frame = frame.insetBy(dx: width * 0.15, dy: height * 0.15)
    case "custom":
        guard let customX = request.x, let customY = request.y, let customWidth = request.amount,
              customX.isFinite, customY.isFinite, customWidth.isFinite else { throw ComponentError.invalid }
        frame = CGRect(x: customX, y: customY, width: max(100, customWidth), height: max(100, Double(request.heightText ?? "") ?? 600))
    default: break
    }
    let result = Response(kind: "frame", x: Double(frame.origin.x), y: Double(frame.origin.y), width: Double(frame.width), height: Double(frame.height))
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Window action failed.\n".utf8))
    exit(1)
}
