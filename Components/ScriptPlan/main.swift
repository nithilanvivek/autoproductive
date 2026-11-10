import Foundation

struct Request: Decodable { let script: String?; let selfTest: Bool? }
struct Response: Encodable { let executable: String; let arguments: [String] }
enum ComponentError: Error { case invalid }
#if ACTION_SHELL
let feature = "action.shell"
let executable = "/bin/zsh"
let option = "-c"
#elseif ACTION_APPLESCRIPT
let feature = "action.appleScript"
let executable = "/usr/bin/osascript"
let option = "-e"
#else
#error("Choose a script action when building this component")
#endif

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 20 * 1024 * 1024 else { throw ComponentError.invalid }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["feature": feature, "api": 1]))
        exit(0)
    }
    guard let script = request.script else { throw ComponentError.invalid }
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(Response(executable: executable, arguments: [option, script])))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Script action failed.\n".utf8))
    exit(1)
}
