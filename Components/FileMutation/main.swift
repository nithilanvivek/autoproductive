import Foundation

struct Request: Decodable { let path: String?; let text: String?; let selfTest: Bool? }
#if ACTION_WRITE
let feature = "action.writeFile"
#elseif ACTION_APPEND
let feature = "action.appendFile"
#elseif ACTION_CREATE_FOLDER
let feature = "action.createFolder"
#elseif ACTION_COPY
let feature = "action.copyFile"
#elseif ACTION_MOVE
let feature = "action.moveFile"
#elseif ACTION_TRASH
let feature = "action.trashFile"
#else
#error("Choose one file operation when building this component")
#endif

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 128 * 1024 * 1024 else { throw ComponentError.invalidInput }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        let output = try JSONSerialization.data(withJSONObject: ["feature": feature, "api": 1])
        try FileHandle.standardOutput.write(contentsOf: output)
        exit(0)
    }
    guard let path = request.path, !path.isEmpty, let text = request.text else { throw ComponentError.invalidInput }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    #if ACTION_WRITE
    try text.write(to: url, atomically: true, encoding: .utf8)
    #elseif ACTION_APPEND
    if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    #elseif ACTION_CREATE_FOLDER
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    #elseif ACTION_COPY
    guard !text.isEmpty else { throw ComponentError.invalidInput }
    let destination = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
    try FileManager.default.copyItem(at: url, to: destination)
    #elseif ACTION_MOVE
    guard !text.isEmpty else { throw ComponentError.invalidInput }
    let destination = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
    try FileManager.default.moveItem(at: url, to: destination)
    #elseif ACTION_TRASH
    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    #endif
    try FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("File action failed.\n".utf8))
    exit(1)
}

enum ComponentError: Error { case invalidInput }
