import CoreGraphics
import Foundation
import OSLog

/// A bounded coarse-to-fine search for a fully visible, proportionally resized
/// reference. Search and verification stay inside the chosen screen rectangle.
enum ScaledImageMatcher {
    private static let logger = Logger(subsystem: "land.nithi.autoproductive", category: "ScreenTriggers")
    static let minimumScale = 0.1
    struct Match { let frame: CGRect; let error: Double }
    private struct Sample { let x: Double, y: Double, r: Double, g: Double, b: Double }

    static func find(_ reference: PixelImage, in screen: PixelImage, area: CGRect, tolerance: Int) throws -> Match? {
        guard reference.width >= 2, reference.height >= 2,
              reference.pixels.count == reference.width * reference.height * 4,
              screen.pixels.count == screen.width * screen.height * 4,
              [area.minX, area.minY, area.maxX, area.maxY].allSatisfy(\.isFinite) else { return nil }
        let bounds = area.intersection(CGRect(x: 0, y: 0, width: screen.width, height: screen.height))
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        // A small detailed reference can collapse to only a few coarse pixels
        // on a Retina display. Retain about 48 pixels along its longer edge,
        // while bounding the search canvas and preserving the cheaper path for
        // large references such as full-screen screenshots.
        let screenEdge = Double(max(screen.width, screen.height))
        let referenceEdge = Double(max(reference.width, reference.height))
        let coarseEdge = min(800.0, max(400.0, 48.0 * screenEdge / referenceEdge))
        let ratio = min(1.0, coarseEdge / screenEdge)
        let small = resized(screen, ratio: ratio)
        let coarseSamples = samples(reference, side: 7)
        let fineSamples = samples(reference, side: 11)
        guard coarseSamples.count >= 8, fineSamples.count >= 24 else { return nil }
        let coarseArea = CGRect(x: bounds.minX * ratio, y: bounds.minY * ratio, width: bounds.width * ratio, height: bounds.height * ratio)
        var candidates: [Match] = []
        let maxScale = min(2.0, bounds.width / Double(reference.width), bounds.height / Double(reference.height))
        guard maxScale >= minimumScale else { return nil }
        var scale = minimumScale
        while scale <= maxScale + 0.0001 {
            try Task.checkCancellation()
            // Downsampling removes detail; compare with a similarly filtered
            // reference instead of sampling the original sharp pixels.
            let scaledCoarseSamples = scale < 1 ? samples(resizedReference(reference, ratio: scale * ratio), side: 7) : coarseSamples
            let width = Double(reference.width) * scale * ratio, height = Double(reference.height) * scale * ratio
            let lastX = Int(floor(coarseArea.maxX - width)), lastY = Int(floor(coarseArea.maxY - height))
            let firstX = Int(ceil(coarseArea.minX)), firstY = Int(ceil(coarseArea.minY))
            if firstX <= lastX && firstY <= lastY {
                for y in stride(from: firstY, through: lastY, by: 2) {
                    try Task.checkCancellation()
                    for x in stride(from: firstX, through: lastX, by: 2) {
                        let frame = CGRect(x: Double(x), y: Double(y), width: width, height: height)
                        let coarseLimit = scale < 1 ? 50.0 : 38.0
                        let error = score(small, frame: frame, samples: scaledCoarseSamples, stopAt: coarseLimit)
                        guard error < coarseLimit else { continue }
                        let full = CGRect(x: Double(x) / ratio, y: Double(y) / ratio, width: width / ratio, height: height / ratio)
                        insert(Match(frame: full, error: error), into: &candidates, separation: 4 / ratio)
                    }
                }
            }
            scale += scale < 0.3 ? 0.0125 : 0.025
        }
        let verification = samples(reference, side: 47)
        // Try the strongest coarse candidates first and return as soon as one
        // passes the same dense verification. Refining every candidate before
        // checking any of them adds seconds for large reference images.
        for candidate in candidates {
            try Task.checkCancellation()
            var best = candidate
            best = refine(best, screen: screen, reference: reference, bounds: bounds, samples: fineSamples,
                          sampleSide: 11, positionRadius: 2 / ratio, positionStep: 1 / ratio, scaleRadius: 0.025, scaleStep: 0.005)
            try Task.checkCancellation()
            best = refine(best, screen: screen, reference: reference, bounds: bounds, samples: fineSamples,
                          sampleSide: 11, positionRadius: 0.75 / ratio, positionStep: max(0.5, 0.125 / ratio), scaleRadius: 0.005, scaleStep: 0.0005)
            let limit = Double(tolerance)
            var match = best
            for pass in 0..<2 {
                let scale = match.frame.width / Double(reference.width)
                let verification = scale < 1 ? samples(resizedReference(reference, ratio: scale), side: 47) : verification
                let measured = score(screen, frame: match.frame, samples: verification, stopAt: limit * 2)
                var outliers = 0
                if measured <= limit {
                    for sample in verification {
                        let value = rgb(screen, x: match.frame.minX + sample.x * match.frame.width - 0.5,
                                        y: match.frame.minY + sample.y * match.frame.height - 0.5)
                        if max(abs(value.0 - sample.r), abs(value.1 - sample.g), abs(value.2 - sample.b)) > max(12, limit * 2) { outliers += 1 }
                    }
                    if Double(outliers) <= Double(verification.count) * 0.1 { return Match(frame: match.frame, error: measured) }
                }
                guard pass == 0, best.error <= max(15, limit) else { break }
                // Sparse samples can favor a slightly wrong scale on sharp
                // patterns. Let dense samples recover the surrounding scale
                // interval, retaining the same strict final checks.
                match = refine(match, screen: screen, reference: reference, bounds: bounds, samples: samples(reference, side: 31),
                               sampleSide: 31, positionRadius: 2.5, positionStep: 0.5, scaleRadius: 0.03, scaleStep: 0.001)
            }
        }
        return nil
    }

    private static func insert(_ match: Match, into values: inout [Match], separation: Double) {
        if let index = values.firstIndex(where: {
            abs($0.frame.minX - match.frame.minX) < separation && abs($0.frame.minY - match.frame.minY) < separation &&
            // Keep nearby candidates at meaningfully different scales. A
            // slightly smaller image can score better on the coarse samples
            // while the correct larger candidate is needed for refinement.
            abs($0.frame.width - match.frame.width) < separation * 0.5
        }) {
            if match.error < values[index].error { values[index] = match }
        } else { values.append(match) }
        values.sort { $0.error < $1.error }
        if values.count > 16 { values.removeLast() }
    }

    private static func refine(_ initial: Match, screen: PixelImage, reference: PixelImage, bounds: CGRect, samples: [Sample],
                               sampleSide: Int, positionRadius: Double, positionStep: Double, scaleRadius: Double, scaleStep: Double) -> Match {
        let initialScale = initial.frame.width / Double(reference.width)
        // Refinement explores a narrow scale range. Filter once for this
        // candidate, rather than resizing a large reference at every step.
        let largeReference = max(reference.width, reference.height) > 512
        let cachedSamples = initialScale < 1 && largeReference ? Self.samples(resizedReference(reference, ratio: initialScale), side: sampleSide) : samples
        var best = Match(frame: initial.frame, error: score(screen, frame: initial.frame, samples: samples, stopAt: 256))
        for scale in stride(from: max(minimumScale, initialScale - scaleRadius), through: min(2, initialScale + scaleRadius), by: scaleStep) {
            if Task.isCancelled { return best }
            let samples = scale < 1 && !largeReference ? Self.samples(resizedReference(reference, ratio: scale), side: sampleSide) : cachedSamples
            for y in stride(from: initial.frame.minY - positionRadius, through: initial.frame.minY + positionRadius, by: positionStep) {
                for x in stride(from: initial.frame.minX - positionRadius, through: initial.frame.minX + positionRadius, by: positionStep) {
                    let frame = CGRect(x: x, y: y, width: Double(reference.width) * scale, height: Double(reference.height) * scale)
                    guard bounds.contains(frame) else { continue }
                    let error = score(screen, frame: frame, samples: samples, stopAt: best.error)
                    if error < best.error { best = Match(frame: frame, error: error) }
                }
            }
        }
        return best
    }

    private static func samples(_ image: PixelImage, side: Int) -> [Sample] {
        var values: [Sample] = []
        for y in 0..<side {
            for x in 0..<side {
                let nx = (Double(x) + 0.5) / Double(side), ny = (Double(y) + 0.5) / Double(side)
                let px = min(image.width - 1, Int(nx * Double(image.width))), py = min(image.height - 1, Int(ny * Double(image.height)))
                guard image.pixels[(py * image.width + px) * 4 + 3] >= 230 else { continue }
                let value = rgb(image, x: nx * Double(image.width) - 0.5, y: ny * Double(image.height) - 0.5)
                values.append(Sample(x: nx, y: ny, r: value.0, g: value.1, b: value.2))
            }
        }
        return values
    }

    private static func score(_ image: PixelImage, frame: CGRect, samples: [Sample], stopAt: Double) -> Double {
        guard !samples.isEmpty else { return 256 }
        var error = 0.0
        for (index, sample) in samples.enumerated() {
            let value = rgb(image, x: frame.minX + sample.x * frame.width - 0.5, y: frame.minY + sample.y * frame.height - 0.5)
            error += (abs(value.0 - sample.r) + abs(value.1 - sample.g) + abs(value.2 - sample.b)) / 3
            // Only stop when even zero error for all remaining samples cannot win.
            if error > stopAt * Double(samples.count) { return 256 }
            if index == 7 && error / 8 > max(45, stopAt * 2) { return 256 }
        }
        return error / Double(samples.count)
    }

    private static func rgb(_ image: PixelImage, x: Double, y: Double) -> (Double, Double, Double) {
        let x = max(0, min(Double(image.width - 1), x)), y = max(0, min(Double(image.height - 1), y))
        let left = Int(x), top = Int(y), right = min(image.width - 1, left + 1), bottom = min(image.height - 1, top + 1)
        let fx = x - Double(left), fy = y - Double(top)
        let a = (top * image.width + left) * 4, b = (top * image.width + right) * 4
        let c = (bottom * image.width + left) * 4, d = (bottom * image.width + right) * 4
        func channel(_ k: Int) -> Double {
            (Double(image.pixels[a + k]) * (1 - fx) + Double(image.pixels[b + k]) * fx) * (1 - fy) +
            (Double(image.pixels[c + k]) * (1 - fx) + Double(image.pixels[d + k]) * fx) * fy
        }
        return (channel(0), channel(1), channel(2))
    }

    private static func resizedReference(_ image: PixelImage, ratio: Double) -> PixelImage {
        guard ratio < 1, let provider = CGDataProvider(data: Data(image.pixels) as CFData),
              let cg = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return image }
        let w = max(2, Int((Double(image.width) * ratio).rounded())), h = max(2, Int((Double(image.height) * ratio).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let result = ctx.makeImage() else { return image }
        return PixelImage(result) ?? image
    }

    private static func resized(_ image: PixelImage, ratio: Double) -> PixelImage {
        guard ratio < 1 else { return image }
        let width = max(1, Int(ceil(Double(image.width) * ratio))), height = max(1, Int(ceil(Double(image.height) * ratio)))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = rgb(image, x: (Double(x) + 0.5) / ratio - 0.5, y: (Double(y) + 0.5) / ratio - 0.5)
                let index = (y * width + x) * 4
                pixels[index] = UInt8(value.0.rounded()); pixels[index + 1] = UInt8(value.1.rounded()); pixels[index + 2] = UInt8(value.2.rounded())
            }
        }
        return PixelImage(width: width, height: height, pixels: pixels)
    }
}
