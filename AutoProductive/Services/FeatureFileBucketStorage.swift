import Foundation
import Darwin

/// The tool's storage implementation runs in a verified, same-team library in
/// the app process, retaining the app's access to user-selected files.
@MainActor
final class FeatureFileBucketStorage {
    private typealias RequestFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias FreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private struct Request: Encodable { let operation: String; let folder: String; let legacyFolder: String?; let source: String?; let permanent: Bool? }
    private struct Response: Decodable { let items: [String]?; let error: String? }
    private struct ToolError: LocalizedError { let message: String; var errorDescription: String? { message } }
    private let library: FeatureToolLibrary
    private let requestFunction: RequestFunction
    private let freeFunction: FreeFunction

    init(verifiedBytes: Data) throws {
        let library = try FeatureToolLibrary.open(verifiedBytes: verifiedBytes, expectedID: "tool.fileBucket", requiredSymbols: ["autoproductive_file_bucket_request", "autoproductive_file_bucket_free"])
        requestFunction = unsafeBitCast(try library.symbol("autoproductive_file_bucket_request"), to: RequestFunction.self)
        freeFunction = unsafeBitCast(try library.symbol("autoproductive_file_bucket_free"), to: FreeFunction.self)
        self.library = library
    }

    private func call(_ request: Request) throws -> Response {
        let data = try JSONEncoder().encode(request)
        guard let input = String(data: data, encoding: .utf8),
              let output = input.withCString({ requestFunction($0) }) else { throw ToolError(message: "File Bucket could not process the request.") }
        defer { freeFunction(output) }
        let length = strnlen(output, 32 * 1024 * 1024)
        guard length < 32 * 1024 * 1024 else { throw ToolError(message: "File Bucket's response was too large.") }
        let response = try JSONDecoder().decode(Response.self, from: Data(bytes: output, count: length))
        if let error = response.error { throw ToolError(message: error) }
        return response
    }

    func list(folder: URL, legacyFolder: URL?) throws -> [URL] {
        let result = try call(Request(operation: "list", folder: folder.path, legacyFolder: legacyFolder?.path, source: nil, permanent: nil))
        guard let items = result.items else { throw ToolError(message: "File Bucket did not return its items.") }
        return items.map { URL(fileURLWithPath: $0) }
    }
    func copy(source: URL, folder: URL) throws {
        _ = try call(Request(operation: "copy", folder: folder.path, legacyFolder: nil, source: source.path, permanent: nil))
    }
    func remove(item: URL, folder: URL, permanent: Bool) throws {
        _ = try call(Request(operation: "remove", folder: folder.path, legacyFolder: nil, source: item.path, permanent: permanent))
    }
}
