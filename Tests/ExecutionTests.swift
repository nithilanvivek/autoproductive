import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct ExecutionTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("autoproductive-execution-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = WorkflowEngine.shared
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message); checks += 1
        }
        let targetFile = URL(fileURLWithPath: "/tmp/example.txt")
        func window(_ id: Int, _ pid: Int, _ name: String, _ layer: Int = 0) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
             kCGWindowName as String: name, kCGWindowLayer as String: layer]
        }
        expect(WorkflowEngine.openedFileWindowID(targetFile, pid: 10, windows: [window(1, 10, "example.txt"), window(2, 11, "example.txt")]) == 1, "Find the opened document only in its owning app")
        expect(WorkflowEngine.openedFileWindowID(targetFile, pid: 10, windows: [window(1, 10, "example.txt"), window(2, 10, "example")]) == nil, "Do not guess between same-name document windows")
        expect(WorkflowEngine.openedFileWindowID(targetFile, pid: 10, windows: [window(3, 10, "example.txt", 3), window(4, 10, "example-other.txt")]) == nil, "Ignore panels and partial title matches")
        func step(_ action: WorkflowAction, _ text: String, _ other: String = "") -> WorkflowStep {
            var step = WorkflowStep(action: action, text: text); step.secondaryText = other; return step
        }
        func run(_ steps: [WorkflowStep]) async -> SavedAutomation {
            var flow = WorkflowDefinition(); flow.isEnabled = true; flow.steps = steps
            let automation = SavedAutomation(name: "Execution test", kind: .workflow, workflow: flow)
            engine.start(automation)
            while engine.runningIDs.contains(automation.id) { try? await Task.sleep(for: .milliseconds(10)) }
            return automation
        }
        let original = root.appendingPathComponent("original.txt").path
        let copied = root.appendingPathComponent("copy.txt").path
        let moved = root.appendingPathComponent("renamed.txt").path
        let output = root.appendingPathComponent("result.txt").path
        let marker = root.appendingPathComponent("must-not-exist").path
        let literal = "Unicode ✓ 🌏 $(touch \(marker)) {{output}}"
        _ = await run([
            step(.writeFile, original, literal), step(.appendFile, original, "\nnext"),
            step(.copyFile, original, copied), step(.moveFile, copied, moved),
            step(.readFile, moved), step(.shell, "printf '%s' \"$AUTOPRODUCTIVE_FILE\""),
            step(.writeFile, output, "{{output}}")
        ])
        expect(engine.lastError == nil, "The file-and-command workflow should finish")
        expect(try String(contentsOfFile: output, encoding: .utf8) == literal + "\nnext", "Scripts receive literal variable values through their environment")
        expect(!FileManager.default.fileExists(atPath: marker), "Input must never become executable command substitution")
        expect(!FileManager.default.fileExists(atPath: copied), "Move must remove the old path")
        _ = await run([step(.copyFile, original, moved)])
        expect(engine.lastError != nil, "Copy must report existing destinations instead of overwriting")
        _ = await run([step(.shell, "exit 19")])
        expect(engine.lastError?.contains("19") == true, "Script failures must be visible")
        var timeout = step(.shell, "while :; do :; done"); timeout.duration = 1
        _ = await run([timeout])
        expect(engine.lastError?.contains("timeout") == true, "Commands must stop at their configured timeout")
        var flow = WorkflowDefinition(); flow.isEnabled = true; var delay = WorkflowStep(action: .wait); delay.duration = 5
        flow.steps = [delay, step(.writeFile, marker, "should not run")]
        let cancelled = SavedAutomation(name: "Cancel test", kind: .workflow, workflow: flow)
        engine.start(cancelled); try await Task.sleep(for: .milliseconds(50)); engine.stop(cancelled.id)
        while engine.runningIDs.contains(cancelled.id) { try await Task.sleep(for: .milliseconds(10)) }
        expect(!FileManager.default.fileExists(atPath: marker), "Cancel must prevent subsequent actions")
        expect(engine.lastResult.contains("Stopped"), "Cancellation must be distinguishable from success")
        var disabled = cancelled
        disabled.id = UUID(); disabled.isEnabled = false
        engine.start(disabled)
        expect(!engine.runningIDs.contains(disabled.id), "Disabled automations never start, even through direct engine calls")
        let screen = PixelImage(width: 3, height: 2, pixels: [0,0,0,255, 255,0,0,255, 0,0,0,255, 0,0,0,255, 0,255,0,255, 0,0,0,255])
        let template = PixelImage(width: 1, height: 2, pixels: [255,0,0,255, 0,255,0,255])
        expect(try screen.firstMatch(template, tolerance: 0) == CGPoint(x: 1, y: 0), "Find the complete template at an offset")
        expect(!screen.matches(template, x: 0, y: 0, tolerance: 0), "Reject a false match")
        expect(!screen.matches(template, x: 3, y: 0, tolerance: 0), "Reject image bounds overflow")
        let transparent = PixelImage(width: 1, height: 1, pixels: [255,255,255,0])
        expect(try screen.firstMatch(transparent, tolerance: 0) == nil, "An empty transparent template must not trigger")
        let red = ScreenColor(red: 255, green: 0, blue: 0)
        expect(try screen.containsColor(red, in: CGRect(x: 1, y: 0, width: 1, height: 2), tolerance: 0), "Rectangle search finds a single colored pixel inside the range")
        expect(try !screen.containsColor(red, in: CGRect(x: 0, y: 1, width: 3, height: 1), tolerance: 0), "A matching color outside the chosen rectangle does not trigger")
        expect(try !screen.containsColor(red, in: CGRect(x: 3, y: 0, width: 1, height: 1), tolerance: 0), "Rectangle search never reads outside the image")
        expect(try screen.containsColor(ScreenColor(red: 250, green: 4, blue: 3), in: CGRect(x: 1, y: 0, width: 1, height: 1), tolerance: 5), "Color tolerance includes every RGB channel")
        expect(try !screen.containsColor(ScreenColor(red: 250, green: 6, blue: 3), in: CGRect(x: 1, y: 0, width: 1, height: 1), tolerance: 5), "Any channel outside tolerance rejects the pixel")
        expect(try screen.containsColor(ScreenColor(red: 0, green: 255, blue: 0), in: CGRect(x: 0, y: 0, width: 3, height: 2), tolerance: 0), "Scan includes the bottom row without coarse sampling")
        let hitAndMiss = [CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 1, y: 0, width: 1, height: 1)]
        expect(try screen.matchesColor(red, in: hitAndMiss, tolerance: 0, requireEvery: false), "Any rectangle may contain the color")
        expect(try !screen.matchesColor(red, in: hitAndMiss, tolerance: 0, requireEvery: true), "Every mode rejects a rectangle without the color")
        expect(try screen.matchesColor(red, in: [hitAndMiss[1], CGRect(x: 1, y: 0, width: 2, height: 2)], tolerance: 0, requireEvery: true), "Every mode accepts only when each rectangle contains the color")
        expect(try !screen.matchesColor(red, in: [], tolerance: 0, requireEvery: true), "No rectangles cannot vacuously satisfy every mode")
        let cancelledScan = Task.detached { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return try screen.containsColor(red, in: CGRect(x: 0, y: 0, width: 3, height: 2), tolerance: 0)
        }
        do { _ = try await cancelledScan.value; preconditionFailure("Cancelled screen scanning must stop") }
        catch is CancellationError { checks += 1 }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let palette = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        palette.setFillColor(CGColor(colorSpace: srgb, components: [0.2, 0.4, 0.6, 1])!)
        palette.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let normalized = PixelImage(palette.makeImage()!)!
        expect(try normalized.containsColor(ScreenColor(red: 51, green: 102, blue: 153), in: CGRect(x: 0, y: 0, width: 2, height: 2), tolerance: 1), "sRGB capture normalization preserves hexadecimal color values")
        expect(ScreenReferenceImage.contentTypes.contains(.png) && ScreenReferenceImage.contentTypes.contains(.jpeg), "The reference picker includes PNG and JPEG")
        expect(!ScreenReferenceImage.contentTypes.contains(.json) && ScreenReferenceImage.contentTypes.allSatisfy { $0.conforms(to: .image) }, "The picker excludes JSON and other non-image types")
        for format in [UTType.png, .jpeg] {
            let url = root.appendingPathComponent("reference." + format.preferredFilenameExtension!)
            let destination = CGImageDestinationCreateWithURL(url as CFURL, format.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, palette.makeImage()!, nil)
            expect(CGImageDestinationFinalize(destination), "Create a real reference image fixture")
            let loaded = try ScreenReferenceImage.load(url.path)
            expect(loaded.width == 2 && loaded.height == 2, "Compatible reference images decode")
            var imageFlow = WorkflowDefinition(); imageFlow.steps = [WorkflowStep(action: .screenImage, text: url.path)]
            try imageFlow.validate(); checks += 1
        }
        let wrongImage = root.appendingPathComponent("not-an-image.json")
        try Data(#"{"not":"an image"}"#.utf8).write(to: wrongImage)
        let renamedImage = root.appendingPathComponent("not-an-image.png")
        try FileManager.default.copyItem(at: wrongImage, to: renamedImage)
        let brokenImage = root.appendingPathComponent("broken.png")
        try Data([137,80,78,71,13,10,26,10]).write(to: brokenImage)
        let folderImage = root.appendingPathComponent("folder.png")
        try FileManager.default.createDirectory(at: folderImage, withIntermediateDirectories: false)
        for rejected in [wrongImage, renamedImage, brokenImage, folderImage, root.appendingPathComponent("missing.png")] {
            do { _ = try ScreenReferenceImage.load(rejected.path); preconditionFailure("Invalid image must be rejected") }
            catch { checks += 1 }
            var invalidFlow = WorkflowDefinition(); invalidFlow.steps = [WorkflowStep(action: .screenImage, text: rejected.path)]
            do { try invalidFlow.validate(); preconditionFailure("An invalid pasted reference must not be saved") }
            catch { checks += 1 }
        }
        try ScreenReferenceImage.validate("{{input}}/reference.png"); checks += 1
        let rows = Data([255,0,0,255, 0,255,0,255])
        let topBottom = CGImage(width: 1, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                               space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: CGDataProvider(data: rows as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let oriented = PixelImage(topBottom)!
        expect(ScreenCaptureSizing.pixels(points: CGSize(width: 1408, height: 881), scale: 2) == CGSize(width: 2816, height: 1762), "Retina captures retain backing pixels for small-image detection")
        expect(ScreenCaptureSizing.pixels(points: CGSize(width: 1920, height: 1080), scale: 1) == CGSize(width: 1920, height: 1080), "Standard displays retain their native capture dimensions")
        expect(ScreenCaptureSizing.pixels(points: CGSize(width: 800, height: 600), scale: .nan) == CGSize(width: 800, height: 600), "An unavailable capture scale uses finite dimensions")
        expect(try oriented.containsColor(red, in: CGRect(x: 0, y: 0, width: 1, height: 1), tolerance: 0), "Capture normalization retains the top-left row convention")
        expect(try screen.firstMatch(template, tolerance: 0, in: CGRect(x: 0, y: 0, width: 1, height: 2)) == nil, "Image search excludes matches outside the selected rectangle")
        expect(try screen.firstMatch(template, tolerance: 0, in: CGRect(x: 1, y: 0, width: 1, height: 1)) == nil, "The complete image must fit in the rectangle")
        expect(try screen.firstMatch(template, tolerance: 0, in: CGRect(x: 1, y: 0, width: 1, height: 2)) == CGPoint(x: 1, y: 0), "Image search includes a match at rectangle boundaries")
        let patternContext = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 256,
                                       space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<8 {
            for x in 0..<8 {
                patternContext.setFillColor(CGColor(colorSpace: srgb, components: [CGFloat((x * 37 + y * 13) % 255) / 255, CGFloat((y * 43 + x * 11) % 255) / 255, CGFloat((x * 17 + y * 53) % 255) / 255, 1])!)
                patternContext.fill(CGRect(x: x * 8, y: y * 5, width: 8, height: 5))
            }
        }
        let patternCG = patternContext.makeImage()!, pattern = PixelImage(patternCG)!
        let sceneContext = CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 640,
                                     space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sceneContext.setFillColor(CGColor(colorSpace: srgb, components: [0.08, 0.08, 0.08, 1])!)
        sceneContext.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        sceneContext.interpolationQuality = .high
        sceneContext.draw(patternCG, in: CGRect(x: 40, y: 30, width: 48, height: 30))
        let resizedScene = PixelImage(sceneContext.makeImage()!)!
        expect(try resizedScene.finds(pattern, tolerance: 10, allowResize: true), "Detect a proportionally reduced image embedded in a larger screen")
        expect(try !resizedScene.finds(pattern, tolerance: 10, allowResize: false), "Original-size mode does not silently scale the reference")
        expect(try !resizedScene.finds(pattern, tolerance: 0, allowResize: true), "Zero tolerance remains strict even with resized-image matching enabled")
        expect(try !resizedScene.finds(pattern, tolerance: 10, in: CGRect(x: 100, y: 0, width: 60, height: 100), allowResize: true), "Resized matching stays inside the chosen rectangle")
        let unrelated = PixelImage(width: 160, height: 100, pixels: Array(repeating: [UInt8(12), 12, 12, 255], count: 160 * 100).flatMap { $0 })
        expect(try !unrelated.finds(pattern, tolerance: 10, allowResize: true), "A resized search rejects an unrelated plain screen")
        let enlargedReferenceContext = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 1280,
                                                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        enlargedReferenceContext.interpolationQuality = .none
        enlargedReferenceContext.draw(patternCG, in: CGRect(x: 0, y: 0, width: 320, height: 200))
        sceneContext.setFillColor(CGColor(colorSpace: srgb, components: [0.08, 0.08, 0.08, 1])!)
        sceneContext.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        sceneContext.draw(patternCG, in: CGRect(x: 40, y: 30, width: 64, height: 40))
        let thumbnailScene = PixelImage(sceneContext.makeImage()!)!, largeReference = PixelImage(enlargedReferenceContext.makeImage()!)!
        expect(try thumbnailScene.finds(largeReference, tolerance: 10, allowResize: true), "Recognize a Finder-sized preview at 20% of reference size")
        // Small, detailed references must survive the coarse search on a real
        // Retina-sized scene, not just the small canvases above.
        let detailedContext = CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 640,
                                         space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let detailedPalette: [[CGFloat]] = [[0.05,0.05,0.08,1], [1,0.25,0.05,1], [0,0.8,0.3,1],
                                    [0.1,0.15,0.7,1], [1,0.85,0,1], [0.9,0.9,0.95,1]]
        var patternSeed: UInt32 = 20261103
        for y in 0..<12 {
            for x in 0..<16 {
                patternSeed = patternSeed &* 1664525 &+ 1013904223
                detailedContext.setFillColor(CGColor(colorSpace: srgb, components: detailedPalette[Int(patternSeed >> 16) % detailedPalette.count])!)
                detailedContext.fill(CGRect(x: x * 10, y: y * 10, width: 10, height: 10))
            }
        }
        let detailedCG = detailedContext.makeImage()!, detailed = PixelImage(detailedCG)!
        let retinaContext = CGContext(data: nil, width: 2816, height: 1762, bitsPerComponent: 8, bytesPerRow: 2816 * 4,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        retinaContext.interpolationQuality = .high
        for scale in [1.5, 2.0] {
            retinaContext.setFillColor(CGColor(gray: 1, alpha: 1))
            retinaContext.fill(CGRect(x: 0, y: 0, width: 2816, height: 1762))
            retinaContext.draw(detailedCG, in: CGRect(x: 1288, y: 700, width: 160 * scale, height: 120 * scale))
            let retinaScene = PixelImage(retinaContext.makeImage()!)!
            expect(try retinaScene.finds(detailed, tolerance: 10, allowResize: true), "Detailed reference enlarged to \(scale) on a Retina-sized screen matches")
            expect(try !retinaScene.finds(detailed, tolerance: 0, allowResize: true), "Detailed resized image still requires nonzero tolerance")
        }
        let sharpURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/detailed-screen-pattern.png")
        let sharpCG = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(sharpURL as CFURL, nil)!, 0, nil)!
        let sharpReference = PixelImage(sharpCG)!
        for scale in [0.5, 0.75] {
            retinaContext.setFillColor(CGColor(gray: 1, alpha: 1))
            retinaContext.fill(CGRect(x: 0, y: 0, width: 2816, height: 1762))
            retinaContext.draw(sharpCG, in: CGRect(x: 1288, y: 700, width: 160 * scale, height: 120 * scale))
            let retinaScene = PixelImage(retinaContext.makeImage()!)!
            expect(try retinaScene.finds(sharpReference, tolerance: 10, allowResize: true), "Detailed image reduced to \(scale) on a Retina-sized screen matches")
            expect(try !retinaScene.finds(sharpReference, tolerance: 10, in: CGRect(x: 0, y: 0, width: 600, height: 600), allowResize: true), "Reduced image is not matched outside its region")
        }
        retinaContext.setFillColor(CGColor(gray: 1, alpha: 1))
        retinaContext.fill(CGRect(x: 0, y: 0, width: 2816, height: 1762))
        retinaContext.draw(sharpCG, in: CGRect(x: 1290, y: 702, width: 320, height: 240))
        let offsetScene = PixelImage(retinaContext.makeImage()!)!
        expect(try offsetScene.finds(sharpReference, tolerance: 10, allowResize: true), "A detailed 200% image matches when shifted between coarse search positions")
        let largeSharpContext = CGContext(data: nil, width: 960, height: 720, bitsPerComponent: 8, bytesPerRow: 960 * 4,
                                          space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        largeSharpContext.interpolationQuality = .none
        largeSharpContext.draw(sharpCG, in: CGRect(x: 0, y: 0, width: 960, height: 720))
        let largeSharpCG = largeSharpContext.makeImage()!, largeSharp = PixelImage(largeSharpCG)!
        retinaContext.setFillColor(CGColor(gray: 1, alpha: 1))
        retinaContext.fill(CGRect(x: 0, y: 0, width: 2816, height: 1762))
        retinaContext.draw(largeSharpCG, in: CGRect(x: 1290, y: 702, width: 192, height: 144))
        expect(try PixelImage(retinaContext.makeImage()!)!.finds(largeSharp, tolerance: 10, allowResize: true), "A large detailed reference matches its reduced preview")
        var controlValue = 80.0
        let controls = SystemControlService.Access(read: { controlValue }, write: { controlValue = $0; return true })
        var adjustment = WorkflowStep(action: .adjustSound, option: "increase"); adjustment.amount = 30
        try SystemControlService.apply(adjustment, access: controls, label: "test volume")
        expect(controlValue == 100, "Volume increments stop at 100%")
        adjustment.option = "decrease"; adjustment.amount = 40
        try SystemControlService.apply(adjustment, access: controls, label: "test volume")
        expect(controlValue == 60, "Decrease subtracts percentage points")
        adjustment.option = "set"; adjustment.amount = 15
        try SystemControlService.apply(adjustment, access: controls, label: "test brightness")
        expect(controlValue == 15, "Set ignores the previous value")
        let unsupported = SystemControlService.Access(read: { nil }, write: { _ in false })
        do { try SystemControlService.apply(adjustment, access: unsupported, label: "test control"); preconditionFailure("Unsupported controls must report failure") }
        catch { checks += 1 }
        adjustment.option = "increase"
        do { try SystemControlService.apply(adjustment, access: unsupported, label: "test control"); preconditionFailure("Relative controls require a readable current level") }
        catch { checks += 1 }

        let pasteboard = NSPasteboard.general
        let savedPasteboard = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            let items = savedPasteboard.map { entries in
                let item = NSPasteboardItem(); for (type, data) in entries { item.setData(data, forType: type) }; return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        let tokenText = "Clipboard ✓ with {{file}} and $(not-a-command)"
        _ = await run([step(.setClipboard, tokenText), step(.writeFile, root.appendingPathComponent("clip.txt").path, "{{clipboard}}"), step(.readFile, root.appendingPathComponent("clip.txt").path), step(.writeFile, root.appendingPathComponent("chained.txt").path, "{{file}}")])
        expect(engine.lastError == nil, "Clipboard → file → read → file actions chain successfully")
        expect(try String(contentsOf: root.appendingPathComponent("chained.txt"), encoding: .utf8) == tokenText, "Inserted clipboard/file content is not recursively expanded or executed")
        for operation in ["uppercase", "lowercase", "trim", "titleCase", "sortLines", "uniqueLines"] {
            let input = " beta\nalpha\nalpha "
            _ = await run([step(.setClipboard, input), WorkflowStep(action: .transformClipboard, option: operation)])
            expect(pasteboard.string(forType: .string) == WorkflowText.transform(input, using: operation), "Clipboard transformation executes: \(operation)")
        }
        let dateFile = root.appendingPathComponent("date.txt")
        _ = await run([step(.writeFile, dateFile.path, "{{date}}")])
        let outputDate = try String(contentsOf: dateFile, encoding: .utf8)
        expect(outputDate.range(of: #"^\d{2}/\d{2}/\d{4}$"#, options: .regularExpression) != nil, "Date variables use day/month/year at execution time")
        let timeFile = root.appendingPathComponent("time.txt")
        _ = await run([step(.writeFile, timeFile.path, "{{time}}")])
        let outputTime = try String(contentsOf: timeFile, encoding: .utf8)
        expect(outputTime.range(of: #"^\d{2}:\d{2} (AM|PM)$"#, options: .regularExpression) != nil, "Time variables expand at execution time in 12-hour format")
        let unicodeFolder = root.appendingPathComponent("folder ✓")
        _ = await run([step(.createFolder, unicodeFolder.path), step(.writeFile, unicodeFolder.appendingPathComponent("one.txt").path, "one"), step(.copyFile, unicodeFolder.path, root.appendingPathComponent("folder copy").path)])
        expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("folder copy/one.txt").path), "Folder actions copy nested contents and Unicode paths")
        _ = await run([step(.appleScript, "return \"AppleScript ✓\""), step(.writeFile, output, "{{output}}")])
        expect(try String(contentsOfFile: output, encoding: .utf8).contains("AppleScript ✓"), "AppleScript output feeds the next action")
        let unicodeScriptInput = "தமிழ் ✓ 🌟\nquotes: \" ' $() \\ and a final newline\n"
        let unicodeScriptFile = root.appendingPathComponent("applescript-input.txt")
        try unicodeScriptInput.write(to: unicodeScriptFile, atomically: true, encoding: .utf8)
        _ = await run([step(.readFile, unicodeScriptFile.path), step(.appleScript, #"do shell script "printf '%s' \"$AUTOPRODUCTIVE_FILE\"" without altering line endings"#), step(.writeFile, output, "{{output}}")])
        expect(try String(contentsOfFile: output, encoding: .utf8) == unicodeScriptInput + "\n", "AppleScript environment example preserves Unicode, literal punctuation and line endings")
        _ = await run([step(.readFile, root.appendingPathComponent("missing.txt").path), step(.writeFile, marker, "must not run")])
        expect(engine.lastError != nil && !FileManager.default.fileExists(atPath: marker), "A failed action stops all subsequent actions")
        var repeated = WorkflowDefinition(); repeated.isEnabled = true; repeated.repeatCount = 3
        repeated.steps = [step(.appendFile, root.appendingPathComponent("repeat.txt").path, "x")]
        let repeatRecord = SavedAutomation(name: "Repeat fixture", kind: .sequence, workflow: repeated)
        engine.start(repeatRecord)
        while engine.runningIDs.contains(repeatRecord.id) { try await Task.sleep(for: .milliseconds(10)) }
        expect(try String(contentsOf: root.appendingPathComponent("repeat.txt"), encoding: .utf8) == "xxx", "Repeat count executes the ordered action list exactly three times")
        let journal = DiagnosticJournal(folder: root.appendingPathComponent("journal"))
        journal.beginSession(); journal.record("Action", "readFile"); journal.beginSession(); journal.record("Action", "writeFile")
        expect(journal.contents(includePrevious: true).contains("readFile") && journal.contents(includePrevious: false).contains("writeFile"), "Crash diagnostics retain the previous session separately")
        journal.recordError("Screen", ScreenObservationError.positionOutsideDisplays, context: "trigger=screenPixel")
        expect(journal.contents(includePrevious: false).contains("Reconnect the display") && journal.contents(includePrevious: false).contains("domain="), "Report logs retain the actionable error cause, category and native metadata")
        journal.recordError("Workflow", WorkflowError.invalid("Script exited with code 7: private stdout and clipboard data"))
        expect(journal.contents(includePrevious: false).contains("Script exited with code 7") && !journal.contents(includePrevious: false).contains("private stdout"), "Script failure diagnostics retain exit status while excluding private script output")
        journal.recordErrorMessage("File Bucket", "\(NSHomeDirectory())/Documents/file\nBearer private-bearer-token")
        expect(!journal.contents(includePrevious: false).contains(NSHomeDirectory()) && !journal.contents(includePrevious: false).contains("private-bearer-token"), "Error logging redacts credentials and home paths before writing local logs")
        let reportAttempt = ProblemReport()
        expect(reportAttempt.deliveryID(after: reportAttempt) == reportAttempt.id, "An unchanged report retry preserves delivery idempotency")
        var changedReport = reportAttempt; changedReport.details = "Added context after a failed send"
        expect(changedReport.deliveryID(after: reportAttempt) != reportAttempt.id, "Editing a failed report starts a new delivery revision")
        journal.record("State", String(repeating: "older event ", count: 14_000))
        journal.recordErrorMessage("Latest failure", "Retain this newest error")
        journal.beginSession(); journal.recordErrorMessage("Current failure", "Also retain the current session")
        let boundedDiagnostics = ProblemReport.redact(journal.contents(includePrevious: true))
        expect(boundedDiagnostics.utf8.count <= 160_000 && boundedDiagnostics.contains("Retain this newest error") && boundedDiagnostics.contains("Also retain the current session"), "Report byte limits preserve recent errors from both sessions")
        let privateText = "\(NSHomeDirectory())/Documents/a.txt /Users/someone/file Bearer secret-token re_abcdefghijklmnopqrstuvwxyz"
        let redacted = ProblemReport.redact(privateText)
        expect(!redacted.contains(NSHomeDirectory()) && !redacted.contains("someone") && !redacted.contains("secret-token") && !redacted.contains("re_abc"), "Report redaction removes home names and credential patterns")
        expect(ProblemReport.redact(String(repeating: "🌏", count: 100), limit: 31).utf8.count <= 31, "Report byte limits retain valid Unicode")
        let crashFixture: [String: Any] = ["procName":"AutoProductive", "procPath":"/Users/private/App", "userID":501, "exception":["type":"EXC_BAD_ACCESS"], "threads":[["triggered":true,"frames":[["symbol":"testSymbol","imageIndex":0,"imageOffset":123,"private":"hidden"]]]], "usedImages":[["name":"AutoProductive","uuid":"fixture-symbol-uuid","path":"/Users/private/App"]]]
        let crashData = try JSONSerialization.data(withJSONObject: crashFixture)
        let summary = ProblemReport.crashSummary(crashData)
        expect(summary.contains("testSymbol") && summary.contains("fixture-symbol-uuid") && summary.contains("EXC_BAD_ACCESS"), "Crash reports preserve exception, stack symbols and symbolication UUIDs")
        expect(!summary.contains("procPath") && !summary.contains("private") && !summary.contains("userID"), "Crash summaries omit account metadata and file paths")
        expect(!CrashPromptState.shouldPrompt(previousLaunch: nil, cleanExit: false, latestCrash: Date()), "Installing reporting does not prompt about unrelated old crashes")
        expect(!CrashPromptState.shouldPrompt(previousLaunch: Date(), cleanExit: true, latestCrash: .distantPast), "Clean sessions do not prompt repeatedly")
        expect(!CrashPromptState.shouldPrompt(previousLaunch: Date(), cleanExit: false, latestCrash: nil), "A missing clean-exit marker alone is not evidence of a crash")
        let launch = Date(timeIntervalSince1970: 1000), crashTime = Date(timeIntervalSince1970: 1010)
        expect(CrashPromptState.shouldPrompt(previousLaunch: launch, cleanExit: false, latestCrash: crashTime), "A new confirmed crash offers a report")
        expect(!CrashPromptState.shouldPrompt(previousLaunch: launch, cleanExit: true, latestCrash: crashTime), "A normal quit does not prompt on relaunch")
        expect(!CrashPromptState.shouldPrompt(previousLaunch: launch, cleanExit: false, latestCrash: crashTime, lastPresentedCrash: crashTime), "A report already presented and dismissed does not return")
        expect(CrashPromptState.shouldPrompt(previousLaunch: launch, cleanExit: false, latestCrash: crashTime, lastPresentedCrash: launch), "A newer crash can still offer a report")
        expect(ProblemReport.isCrashDiagnostic(crashData), "Real exception diagnostics remain eligible")
        let normalTermination = try JSONSerialization.data(withJSONObject: ["procName":"AutoProductive", "exception":["type":"EXC_CRASH", "signal":"SIGTERM"]])
        expect(!ProblemReport.isCrashDiagnostic(normalTermination), "Controlled SIGTERM restarts do not masquerade as crashes")
        let normalSignalCode = try JSONSerialization.data(withJSONObject: ["procName":"AutoProductive", "termination":["namespace":"SIGNAL", "code":15]])
        expect(!ProblemReport.isCrashDiagnostic(normalSignalCode), "Normal termination codes are excluded even without an exception signal")
        let timedCrash = Data(#"{"procName":"AutoProductive","captureTime":"2026-11-01 19:32:09.8145 +0530"}"#.utf8)
        let recordedDate = ProblemReport.crashDate(timedCrash)
        expect(recordedDate != nil, "macOS crash timestamps decode independently of delayed file writes")
        expect(!CrashPromptState.shouldPrompt(previousLaunch: recordedDate!.addingTimeInterval(6), cleanExit: true, latestCrash: recordedDate), "Delayed crash-file creation does not make an older crash prompt after a clean session")
        let challenge = ReportChallenge(token: "synthetic-challenge", difficulty: 4)
        let nonce = try challenge.solve()
        expect(!nonce.isEmpty, "The native reporting client solves its verification without an embedded key")

        print("Passed \(checks) actual execution, file, command, cancellation and image-matching checks.")
    }
}
