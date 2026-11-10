import Foundation

struct Request: Decodable { let value: String?; let subject: String?; let body: String?; let selfTest: Bool? }
struct Response: Encodable { let url: String }
enum ComponentError: Error { case invalid }
#if ACTION_OPEN_URL
let feature = "action.openURL"
#elseif ACTION_OPEN_APP
let feature = "action.openApp"
#elseif ACTION_COMPOSE_MAIL
let feature = "action.composeMail"
#else
#error("Choose an open action when building this component")
#endif

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 20 * 1024 * 1024 else { throw ComponentError.invalid }
    let request = try JSONDecoder().decode(Request.self, from: input)
    if request.selfTest == true {
        try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["feature": feature, "api": 1]))
        exit(0)
    }
    guard let value = request.value else { throw ComponentError.invalid }
    let url: URL
    #if ACTION_OPEN_URL
    guard let parsed = URL(string: value), ["https", "http", "file"].contains(parsed.scheme?.lowercased() ?? "") else { throw ComponentError.invalid }
    url = parsed
    #elseif ACTION_OPEN_APP
    guard !value.isEmpty else { throw ComponentError.invalid }
    url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    #else
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = value
    components.queryItems = [URLQueryItem(name: "subject", value: request.subject ?? ""), URLQueryItem(name: "body", value: request.body ?? "")]
    guard let parsed = components.url else { throw ComponentError.invalid }
    url = parsed
    #endif
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(Response(url: url.absoluteString)))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Open action failed.\n".utf8))
    exit(1)
}
