import Foundation

struct Request: Decodable { let title: String?; let details: String?; let selfTest: Bool? }
struct Response: Encodable { let kind: String; let title: String; let details: String; let choices: [String] }
enum ComponentError: Error { case invalid }
#if ACTION_PROMPT
let kind = "prompt"
#elseif ACTION_CHOOSE
let kind = "choose"
#elseif ACTION_MESSAGE
let kind = "message"
#elseif ACTION_NOTIFICATION
let kind = "notification"
#else
#error("Choose a dialog action when building this component")
#endif

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 20 * 1024 * 1024 else { throw ComponentError.invalid }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["feature": "action." + kind, "api": 1]))
        exit(0)
    }
    guard let title = request.title, let details = request.details else { throw ComponentError.invalid }
    let choices = kind == "choose" ? details.components(separatedBy: .newlines).filter { !$0.isEmpty } : []
    if kind == "choose", choices.isEmpty || choices.count > 5 { throw ComponentError.invalid }
    let response = Response(kind: kind, title: title.isEmpty ? "AutoProductive" : title,
                            details: kind == "choose" ? "Choose an option." : details, choices: choices)
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(response))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Dialog action failed.\n".utf8))
    exit(1)
}
