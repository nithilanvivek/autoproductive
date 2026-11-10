import CoreGraphics
import Foundation

enum ScreenCaptureSizing {
    static func pixels(points: CGSize, scale: Double) -> CGSize {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        return CGSize(width: max(1, (points.width * scale).rounded()),
                      height: max(1, (points.height * scale).rounded()))
    }
}

struct PixelImage: Sendable {
    let width: Int, height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard rendered else { return nil }
        self.init(width: width, height: height, pixels: bytes)
    }

    func matchesColor(_ target: ScreenColor, in rects: [CGRect], tolerance: Int, requireEvery: Bool) throws -> Bool {
        guard !rects.isEmpty else { return false }
        for rect in rects {
            let found = try containsColor(target, in: rect, tolerance: tolerance)
            if requireEvery && !found { return false }
            if !requireEvery && found { return true }
        }
        return requireEvery
    }

    /// Scan every pixel, rather than sampling and missing a small colored item.
    func containsColor(_ target: ScreenColor, in rect: CGRect, tolerance: Int) throws -> Bool {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, !rect.isEmpty,
              pixels.count == width * height * 4 else { return false }
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull, !clipped.isEmpty else { return false }
        let left = Int(floor(clipped.minX)), right = Int(ceil(clipped.maxX))
        let top = Int(floor(clipped.minY)), bottom = Int(ceil(clipped.maxY))
        let tolerance = max(0, min(255, tolerance))
        for y in top..<bottom {
            try Task.checkCancellation()
            for x in left..<right {
                let offset = (y * width + x) * 4
                if abs(Int(pixels[offset]) - target.red) <= tolerance,
                   abs(Int(pixels[offset + 1]) - target.green) <= tolerance,
                   abs(Int(pixels[offset + 2]) - target.blue) <= tolerance { return true }
            }
        }
        return false
    }

    func matches(_ reference: Self, x: Int, y: Int, tolerance: Int) -> Bool {
        guard x >= 0, y >= 0, x + reference.width <= width, y + reference.height <= height,
              reference.pixels.count == reference.width * reference.height * 4,
              pixels.count == width * height * 4 else { return false }
        for row in 0..<reference.height {
            for column in 0..<reference.width {
                let r = (row * reference.width + column) * 4
                if reference.pixels[r + 3] < 26 { continue }
                let p = ((y + row) * width + x + column) * 4
                for channel in 0..<3 where abs(Int(pixels[p + channel]) - Int(reference.pixels[r + channel])) > tolerance { return false }
            }
        }
        return true
    }

    func firstMatch(_ reference: Self, tolerance: Int, in region: CGRect? = nil) throws -> CGPoint? {
        guard reference.width > 0, reference.height > 0, reference.width <= width, reference.height <= height,
              reference.pixels.count == reference.width * reference.height * 4,
              pixels.count == width * height * 4 else { return nil }
        guard let firstAnchor = stride(from: 0, to: reference.pixels.count, by: 4).first(where: { reference.pixels[$0 + 3] >= 26 }) else { return nil }
        // A single dark anchor matches large areas of a dark desktop, causing
        // many expensive full-image comparisons. Add a few differently colored
        // opaque samples; each is an exact necessary condition for a match.
        var choices: [Int] = [firstAnchor]
        for row in 0..<5 {
            for column in 0..<5 {
                let x = min(reference.width - 1, (2 * column + 1) * reference.width / 10)
                let y = min(reference.height - 1, (2 * row + 1) * reference.height / 10)
                let index = (y * reference.width + x) * 4
                if reference.pixels[index + 3] >= 26 && !choices.contains(index) { choices.append(index) }
            }
        }
        var anchors = [firstAnchor]
        while anchors.count < 4, let next = choices.filter({ !anchors.contains($0) }).max(by: { a, b in
            func separation(_ index: Int) -> Int {
                anchors.map { existing in
                    (0..<3).map { abs(Int(reference.pixels[index + $0]) - Int(reference.pixels[existing + $0])) }.reduce(0, +)
                }.min() ?? 0
            }
            return separation(a) < separation(b)
        }) {
            let distinct = anchors.allSatisfy { existing in (0..<3).contains { reference.pixels[existing + $0] != reference.pixels[next + $0] } }
            guard distinct else { break }
            anchors.append(next)
        }
        let area = region ?? CGRect(x: 0, y: 0, width: width, height: height)
        guard [area.minX, area.minY, area.maxX, area.maxY].allSatisfy(\.isFinite), !area.isEmpty else { return nil }
        let clipped = area.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        let left = Int(ceil(clipped.minX)), top = Int(ceil(clipped.minY))
        let right = Int(floor(clipped.maxX)) - reference.width, bottom = Int(floor(clipped.maxY)) - reference.height
        guard left <= right, top <= bottom else { return nil }
        let anchorTests = anchors.map { index in
            (offset: ((index / 4) / reference.width * width + (index / 4) % reference.width) * 4,
             red: Int(reference.pixels[index]), green: Int(reference.pixels[index + 1]), blue: Int(reference.pixels[index + 2]))
        }
        for y in top...bottom {
            try Task.checkCancellation()
            for x in left...right {
                var possible = true
                let base = (y * width + x) * 4
                for anchor in anchorTests {
                    let p = base + anchor.offset
                    if abs(Int(pixels[p]) - anchor.red) > tolerance ||
                       abs(Int(pixels[p + 1]) - anchor.green) > tolerance ||
                       abs(Int(pixels[p + 2]) - anchor.blue) > tolerance { possible = false; break }
                }
                if !possible { continue }
                if matches(reference, x: x, y: y, tolerance: tolerance) { return CGPoint(x: x, y: y) }
            }
        }
        return nil
    }

    func finds(_ reference: Self, tolerance: Int, in region: CGRect? = nil, allowResize: Bool) throws -> Bool {
        if try firstMatch(reference, tolerance: tolerance, in: region) != nil { return true }
        guard allowResize else { return false }
        return try ScaledImageMatcher.find(reference, in: self,
            area: region ?? CGRect(x: 0, y: 0, width: width, height: height), tolerance: tolerance) != nil
    }
}
