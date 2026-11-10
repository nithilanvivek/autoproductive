import AppKit
import Foundation

struct Request: Decodable { let text: String?; let pasteboardName: String?; let selfTest: Bool? }
enum ComponentError: Error { case invalidInput, unavailable }
do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 20 * 1024 * 1024 else { throw ComponentError.invalidInput }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: Data(#"{"feature":"action.setClipboard","api":1}"#.utf8))
        exit(0)
    }
    guard let text = request.text else { throw ComponentError.invalidInput }
    let pasteboard = request.pasteboardName.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else { throw ComponentError.unavailable }
    try FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Clipboard action failed.\n".utf8))
    exit(1)
}
