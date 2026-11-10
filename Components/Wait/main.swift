import Foundation

struct Request: Decodable { let duration: Double?; let selfTest: Bool? }
do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 1024 else { throw ComponentError.invalidInput }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: Data(#"{"feature":"action.wait","api":1}"#.utf8))
        exit(0)
    }
    guard let duration = request.duration, duration.isFinite, (0...300).contains(duration) else { throw ComponentError.invalidInput }
    Thread.sleep(forTimeInterval: duration)
    try FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Wait action failed.\n".utf8))
    exit(1)
}

enum ComponentError: Error { case invalidInput }
