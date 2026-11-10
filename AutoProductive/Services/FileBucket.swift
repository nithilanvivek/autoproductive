import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileBucket: ObservableObject {
    static let shared = FileBucket()

    @Published private(set) var items: [URL] = []
    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("FileBucket", errorMessage)
            }
        }
    }
    @Published private(set) var edgeDropEnabled: Bool
    @Published private(set) var permanentlyDeleteOnRemove: Bool

    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var edgePanels: [NSPanel] = []
    private var hideTask: DispatchWorkItem?
    private var dragTimer: Timer?
    private var lastIdleDragChange = 0
    private var mouseWasDown = false
    private var panelScreen: NSScreen?
    private let storageOverride: URL?
    private let defaults: UserDefaults
    private let storageComponent: FeatureFileBucketStorage?
    let isAvailable: Bool
    private var bucketPanel: NSPanel?

    var folderURL: URL {
        storageOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier == "land.nithi.autoproductive.test14" ? "AutoProductive 1.4 Test/File Bucket" : "AutoProductive/File Bucket", isDirectory: true)
    }

    private var legacyFolderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier == "land.nithi.autoproductive.test14" ? "AutoProductive 1.4 Test/File Shelf" : "AutoProductive/File Shelf", isDirectory: true)
    }

    init(folderURL: URL? = nil, startMonitoring: Bool = true, defaults: UserDefaults = .standard,
         storageComponentOverride: FeatureFileBucketStorage? = nil) {
        var component = storageComponentOverride
        var available = true
        var loadError: String?
        if folderURL == nil && component == nil {
            do {
                if let bytes = try FeatureComponentDispatcher.toolBytes(id: "tool.fileBucket") {
                    component = try FeatureFileBucketStorage(verifiedBytes: bytes)
                } else {
                    #if MODULAR_FEATURES
                    available = false
                    #endif
                }
            } catch FeatureComponentDispatcher.DispatchError.missingComponent {
                available = false
            } catch {
                available = false
                loadError = error.localizedDescription
            }
        }
        storageComponent = component
        isAvailable = available
        storageOverride = folderURL
        self.defaults = defaults
        edgeDropEnabled = defaults.object(forKey: "fileBucketEdgeDropEnabled.v1") as? Bool
            ?? defaults.object(forKey: "fileShelfEdgeDropEnabled.v1") as? Bool
            ?? true
        permanentlyDeleteOnRemove = defaults.bool(forKey: "fileBucketPermanentlyDeleteOnRemove.v1")
        if available {
            refresh()
            if edgeDropEnabled && startMonitoring { startEdgeMonitoring() }
        } else { errorMessage = loadError }
    }

    func toggleWindow() {
        guard isAvailable else { return }
        if bucketPanel?.isVisible == true { bucketPanel?.orderOut(nil) }
        else { showWindow() }
    }

    func showWindow() {
        guard isAvailable else { return }
        refresh()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 650, height: 500)
        if bucketPanel == nil {
            let panel = FileBucketPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "File Bucket"
            panel.identifier = NSUserInterfaceItemIdentifier("file-bucket")
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: FileBucketView().tint(AppPalette.textAccent))
            bucketPanel = panel
        }
        guard let panel = bucketPanel else { return }
        panel.minSize = NSSize(width: min(360, available.width), height: min(280, available.height))
        let size = NSSize(width: min(panel.frame.width, available.width), height: min(panel.frame.height, available.height))
        panel.setFrame(NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hideWindow() { bucketPanel?.orderOut(nil) }
    func reportError(_ message: String) { errorMessage = message }

    func setEdgeDropEnabled(_ enabled: Bool) {
        edgeDropEnabled = enabled
        defaults.set(enabled, forKey: "fileBucketEdgeDropEnabled.v1")
        if enabled && isAvailable { startEdgeMonitoring() }
        else { stopEdgeMonitoring() }
    }

    func refresh() {
        guard isAvailable else { return }
        do {
            if let storageComponent {
                items = try storageComponent.list(folder: folderURL, legacyFolder: storageOverride == nil ? legacyFolderURL : nil)
            } else {
                #if MODULAR_FEATURES
                throw FileBucketComponentError.notInstalled
                #else
                try migrateLegacyFiles()
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                items = try FileManager.default.contentsOfDirectory(at: folderURL,
                    includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                #endif
            }
            errorMessage = nil
        } catch {
            DiagnosticJournal.shared.recordError("FileBucket", error); errorMessage = error.localizedDescription
        }
    }

    func importURLs(_ urls: [URL]) {
        guard isAvailable else { return }
        do {
            #if !MODULAR_FEATURES
            if storageComponent == nil { try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true) }
            #endif
            for source in urls where source.isFileURL {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                if let storageComponent { try storageComponent.copy(source: source, folder: folderURL) }
                else {
                    #if MODULAR_FEATURES
                    throw FileBucketComponentError.notInstalled
                    #else
                    try FileManager.default.copyItem(at: source, to: uniqueDestination(for: source.lastPathComponent))
                    #endif
                }
            }
            refresh()
        } catch {
            DiagnosticJournal.shared.recordError("FileBucket", error); errorMessage = "Could not add file to File Bucket: \(error.localizedDescription)"
        }
    }

    func remove(_ url: URL) {
        guard isAvailable else { return }
        do {
            guard url.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL else { return }
            if let storageComponent { try storageComponent.remove(item: url, folder: folderURL, permanent: permanentlyDeleteOnRemove) }
            else {
                #if MODULAR_FEATURES
                throw FileBucketComponentError.notInstalled
                #else
                if permanentlyDeleteOnRemove { try FileManager.default.removeItem(at: url) }
                else {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                }
                #endif
            }
            refresh()
        } catch {
            DiagnosticJournal.shared.recordError("FileBucket", error); errorMessage = "Could not remove file from File Bucket: \(error.localizedDescription)"
        }
    }

    func setPermanentlyDeleteOnRemove(_ enabled: Bool) {
        permanentlyDeleteOnRemove = enabled
        defaults.set(enabled, forKey: "fileBucketPermanentlyDeleteOnRemove.v1")
    }

    #if !MODULAR_FEATURES
    private func uniqueDestination(for name: String) -> URL {
        let original = folderURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        for number in 2...10_000 {
            let stem = folderURL.appendingPathComponent("\(base) \(number)")
            let candidate = ext.isEmpty ? stem : stem.appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let fallback = folderURL.appendingPathComponent(UUID().uuidString)
        return ext.isEmpty ? fallback : fallback.appendingPathExtension(ext)
    }

    private func migrateLegacyFiles() throws {
        let manager = FileManager.default
        guard storageOverride == nil else { return }
        guard manager.fileExists(atPath: legacyFolderURL.path) else { return }
        if !manager.fileExists(atPath: folderURL.path) {
            try manager.moveItem(at: legacyFolderURL, to: folderURL)
            return
        }
        for source in try manager.contentsOfDirectory(at: legacyFolderURL,
                                                      includingPropertiesForKeys: nil) {
            try manager.moveItem(at: source, to: uniqueDestination(for: source.lastPathComponent))
        }
        try manager.removeItem(at: legacyFolderURL)
    }
    #endif

    private func startEdgeMonitoring() {
        guard dragTimer == nil else { return }
        lastIdleDragChange = NSPasteboard(name: .drag).changeCount
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollDrag() }
        }
        dragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in self?.handleMouse(event.type) }
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in self?.handleMouse(event.type) }
            return event
        }
    }

    private func stopEdgeMonitoring() {
        if let globalDragMonitor { NSEvent.removeMonitor(globalDragMonitor) }
        if let localDragMonitor { NSEvent.removeMonitor(localDragMonitor) }
        globalDragMonitor = nil
        localDragMonitor = nil
        dragTimer?.invalidate(); dragTimer = nil
        hidePanels()
    }

    private func handleMouse(_ type: NSEvent.EventType) {
        if type == .leftMouseUp { scheduleHide(after: 0.4) }
        else { pollDrag() }
    }

    private func pollDrag() {
        guard edgeDropEnabled else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            lastIdleDragChange = pasteboard.changeCount
            if mouseWasDown { scheduleHide(after: 0.4) }
            mouseWasDown = false
            return
        }
        mouseWasDown = true
        guard pasteboard.changeCount != lastIdleDragChange,
              !Self.fileURLs(from: pasteboard).isEmpty else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else { return }
        if let cardFrame = FileBucketDropLayout.cardFrame(pointer: pointer, screen: screen.frame) {
            hideTask?.cancel()
            if panelScreen != screen { hidePanels() }
            showDropCard(frame: cardFrame, screen: screen)
        } else if !edgePanels.contains(where: { $0.frame.insetBy(dx: -24, dy: -24).contains(pointer) }) {
            hidePanels()
        }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return urls }
        return (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
    }

    nonisolated static func fileURL(from item: Any?) -> URL? {
        let url: URL?
        if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
        else if let value = item as? URL { url = value }
        else if let value = item as? String { url = URL(string: value) }
        else { url = nil }
        return url?.isFileURL == true ? url : nil
    }

    private func showDropCard(frame: NSRect, screen: NSScreen) {
        if let panel = edgePanels.first {
            panel.setFrame(frame, display: true)
            return
        }
        panelScreen = screen
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FileBucketEdgeDropView(bucket: self)
        panel.orderFrontRegardless()
        edgePanels = [panel]
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hidePanels() }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hidePanels() {
        edgePanels.forEach { $0.orderOut(nil) }
        edgePanels.removeAll()
        panelScreen = nil
    }
}

private enum FileBucketComponentError: LocalizedError {
    case notInstalled
    var errorDescription: String? { "Install File Bucket to use it." }
}

private final class FileBucketEdgeDropView: NSView {
    private weak var bucket: FileBucket?
    init(bucket: FileBucket) {
        self.bucket = bucket
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
        toolTip = "Drop files here to copy them into File Bucket"
        setAccessibilityElement(true)
        setAccessibilityLabel("Add to File Bucket. Release to store a local copy.")
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill(); card.fill()
        NSColor.separatorColor.setStroke(); card.lineWidth = 1; card.stroke()
        let icon = NSBezierPath()
        icon.move(to: NSPoint(x: 18, y: 51)); icon.line(to: NSPoint(x: 23, y: 29))
        icon.curve(to: NSPoint(x: 45, y: 29), controlPoint1: NSPoint(x: 30, y: 25), controlPoint2: NSPoint(x: 38, y: 25))
        icon.line(to: NSPoint(x: 50, y: 51))
        icon.appendOval(in: NSRect(x: 18, y: 47, width: 32, height: 8))
        icon.move(to: NSPoint(x: 22, y: 51))
        icon.curve(to: NSPoint(x: 46, y: 51), controlPoint1: NSPoint(x: 22, y: 73), controlPoint2: NSPoint(x: 46, y: 73))
        NSColor.controlAccentColor.setStroke(); icon.lineWidth = 2; icon.stroke()
        ("Add to File Bucket" as NSString).draw(at: NSPoint(x: 64, y: 47), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        ("Release to store a copy" as NSString).draw(at: NSPoint(x: 64, y: 28), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileBucket.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !FileBucket.fileURLs(from: sender.draggingPasteboard).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = FileBucket.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        bucket?.importURLs(urls)
        return true
    }
}

private final class FileBucketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
