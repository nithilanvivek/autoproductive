import Foundation

struct Request: Decodable { let text: String?; let operation: String?; let selfTest: Bool? }
struct Response: Encodable { let text: String }

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 20 * 1024 * 1024 else { throw ComponentError.inputTooLarge }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: Data(#"{"feature":"action.transformClipboard","api":1}"#.utf8))
        exit(0)
    }
    guard let text = request.text, let operation = request.operation else { throw ComponentError.invalidInput }
    let result = ClipboardTransform.apply(text, using: operation)
    let output = try JSONEncoder().encode(Response(text: result))
    try FileHandle.standardOutput.write(contentsOf: output)
} catch {
    // Do not print the request or clipboard contents to diagnostics.
    try? FileHandle.standardError.write(contentsOf: Data("Clipboard transformation failed.\n".utf8))
    exit(1)
}

enum ComponentError: Error { case inputTooLarge, invalidInput }
