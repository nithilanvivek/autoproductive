import Foundation
import Darwin

private struct Request: Decodable {
    let operation: String
    let folder: String
    let legacyFolder: String?
    let source: String?
    let permanent: Bool?
}
private struct Response: Encodable { let items: [String]?; let error: String? }
private enum StorageError: Error { case invalidRequest }
private let featureID = strdup("tool.fileBucket")!

private func uniqueDestination(_ name: String, in folder: URL) -> URL {
    let original = folder.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: original.path) else { return original }
    let base = original.deletingPathExtension().lastPathComponent
    let ext = original.pathExtension
    for number in 2...10_000 {
        let stem = folder.appendingPathComponent("\(base) \(number)")
        let candidate = ext.isEmpty ? stem : stem.appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    let fallback = folder.appendingPathComponent(UUID().uuidString)
    return ext.isEmpty ? fallback : fallback.appendingPathExtension(ext)
}

private func run(_ request: Request) throws -> Response {
    guard !request.folder.isEmpty else { throw StorageError.invalidRequest }
    let files = FileManager.default
    let folder = URL(fileURLWithPath: request.folder, isDirectory: true)
    switch request.operation {
    case "list":
        if let legacyPath = request.legacyFolder, !legacyPath.isEmpty {
            let legacy = URL(fileURLWithPath: legacyPath, isDirectory: true)
            if files.fileExists(atPath: legacy.path) {
                if !files.fileExists(atPath: folder.path) { try files.moveItem(at: legacy, to: folder) }
                else {
                    for source in try files.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
                        try files.moveItem(at: source, to: uniqueDestination(source.lastPathComponent, in: folder))
                    }
                    try files.removeItem(at: legacy)
                }
            }
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let items = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return Response(items: items.map(\.path), error: nil)
    case "copy":
        guard let sourcePath = request.source, !sourcePath.isEmpty else { throw StorageError.invalidRequest }
        let source = URL(fileURLWithPath: sourcePath)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try files.copyItem(at: source, to: uniqueDestination(source.lastPathComponent, in: folder))
        return Response(items: nil, error: nil)
    case "remove":
        guard let sourcePath = request.source, !sourcePath.isEmpty else { throw StorageError.invalidRequest }
        let item = URL(fileURLWithPath: sourcePath)
        guard item.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { throw StorageError.invalidRequest }
        if request.permanent == true { try files.removeItem(at: item) }
        else { try files.trashItem(at: item, resultingItemURL: nil) }
        return Response(items: nil, error: nil)
    default: throw StorageError.invalidRequest
    }
}

@_cdecl("autoproductive_tool_api_version")
public func toolAPIVersion() -> Int32 { 1 }
@_cdecl("autoproductive_tool_feature_id")
public func toolFeatureID() -> UnsafePointer<CChar>? { UnsafePointer(featureID) }
@_cdecl("autoproductive_file_bucket_request")
public func fileBucketRequest(_ bytes: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let bytes else { return nil }
    let response: Response
    do {
        let request = try JSONDecoder().decode(Request.self, from: Data(String(cString: bytes).utf8))
        response = try run(request)
    } catch { response = Response(items: nil, error: error.localizedDescription) }
    guard let result = try? JSONEncoder().encode(response), let text = String(data: result, encoding: .utf8) else { return nil }
    return strdup(text)
}
@_cdecl("autoproductive_file_bucket_free")
public func fileBucketFree(_ bytes: UnsafeMutablePointer<CChar>?) { free(bytes) }
