import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The picker and matcher share ImageIO's installed raster-image decoders.
enum ScreenReferenceImage {
    static let contentTypes: [UTType] = (CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
        .compactMap { UTType($0) }.filter { $0.conforms(to: .image) }

    static func validate(_ path: String) throws {
        // Action paths may be supplied by a preceding prompt/script. Those are
        // checked by load() after expansion, before they can be matched.
        if path.range(of: #"\{\{(input|choice|file|output|clipboard|date)\}\}"#, options: .regularExpression) != nil { return }
        _ = try load(path)
    }

    static func load(_ path: String) throws -> CGImage {
        guard !path.isEmpty else { throw WorkflowError.invalid("Choose a reference image.") }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              contentTypes.contains(where: { $0.identifier == identifier }),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw WorkflowError.invalid("Choose a readable image such as PNG, JPEG, GIF, TIFF or another supported image format.")
        }
        guard image.width > 0, image.height > 0, image.width <= 16384, image.height <= 16384 else {
            throw WorkflowError.invalid("Reference images must be no larger than 16,384 pixels on either side.")
        }
        return image
    }
}
