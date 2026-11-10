import Foundation

struct Request: Decodable { let path: String?; let selfTest: Bool? }
struct Response: Encodable { let text: String }
do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 1024 * 1024 else { throw ComponentError.invalidInput }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: Data(#"{"feature":"action.readFile","api":1}"#.utf8))
        exit(0)
    }
    guard let path = request.path, !path.isEmpty else { throw ComponentError.invalidInput }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 20 * 1024 * 1024 else { throw ComponentError.invalidInput }
    let text = try String(contentsOf: url, encoding: .utf8)
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(Response(text: text)))
} catch {
    // Do not include a user's path or file content in diagnostics.
    try? FileHandle.standardError.write(contentsOf: Data("Text file could not be read.\n".utf8))
    exit(1)
}

enum ComponentError: Error { case invalidInput }
