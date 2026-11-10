import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit
import SwiftUI
import OSLog

struct DockWindowPreview: Identifiable {
    let id: String
    let title: String
    var image: NSImage?
    let accessibilityWindow: AXUIElement?
    let frame: CGRect?
    let canClose: Bool
    let windowID: CGWindowID?
}

@MainActor
final class DockPreviewManager: ObservableObject {
    static let shared = DockPreviewManager()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String? {
        didSet {
            if let errorMessage, errorMessage != oldValue {
                DiagnosticJournal.shared.recordErrorMessage("DockPreviewManager", errorMessage)
            }
        }
    }
    @Published private(set) var previews: [DockWindowPreview] = []
    @Published private(set) var appName = ""
    @Published private(set) var closingIDs = Set<String>()

    private var hoverTimer: Timer?
    private var panel: NSPanel?
    private var hoverTask: Task<Void, Never>?
    private var currentPID: pid_t?
    private var hoveredPID: pid_t?
    private var hideTask: DispatchWorkItem?
    private var hitTestInFlight = false
    private var iconFrame: CGRect?
    private let logger = Logger(subsystem: "land.nithi.autoproductive", category: "DockPreviews")
    private var lastDiagnostic = ""
    private var imageCache: [CGWindowID: NSImage] = [:]
    private var cachedWindowOrder: [CGWindowID] = []
    private var contextClickMonitor: Any?
    private var contextMenuSuppressedUntil = Date.distantPast
    private var contextMenuSuppressed = false

    private func diagnose(_ message: String) {
        guard message != lastDiagnostic else { return }
        lastDiagnostic = message
        logger.notice("\(message, privacy: .public)")
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "dockPreviewsEnabled.v1") && DockWindowCapture.isAvailable
        if isEnabled { start() }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: "dockPreviewsEnabled.v1")
            stop()
            return
        }
        guard DockWindowCapture.isAvailable else {
            errorMessage = "Install Dock Window Previews to use it."
            return
        }
        requestPermissionsIfNeeded { [weak self] ready in
            guard ready, let self else { return }
            self.isEnabled = true
            UserDefaults.standard.set(true, forKey: "dockPreviewsEnabled.v1")
            self.start()
        }
    }

    private func requestPermissionsIfNeeded(completion: @escaping (Bool) -> Void) {
        guard !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() else { completion(true); return }
        let nextPermission = !AXIsProcessTrusted() ? DesktopAutomationService.controlPermissionName : "Screen Recording"
        PermissionExplanationPresenter.shared.present(
            title: "Enable Dock window previews",
            message: "AutoProductive reads the Dock icon under your pointer and captures thumbnails of that app’s windows. macOS requires \(DesktopAutomationService.controlPermissionName) and Screen Recording. Captures remain on this Mac. Continue opens \(nextPermission) in System Settings."
        ) { [weak self] accepted in
            guard accepted, let self else { completion(false); return }
            if !AXIsProcessTrusted() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                if !AXIsProcessTrusted() {
                    PermissionSettings.open(DesktopAutomationService.controlPermissionName)
                    self.errorMessage = "Allow the missing permissions in System Settings, then turn Dock previews on again."
                    completion(false)
                    return
                }
            }
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
                PermissionSettings.open("Screen Recording")
            }
            let ready = AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
            if !ready { self.errorMessage = "Allow both permissions in System Settings, then turn Dock previews on again." }
            completion(ready)
        }
    }

    private func start() {
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: "dockPreviewsEnabled.v1")
            stop()
            errorMessage = "Dock previews need \(DesktopAutomationService.controlPermissionName) and Screen Recording."
            return
        }
        guard hoverTimer == nil else { return }
        errorMessage = nil
        diagnose("Dock previews started; control and screen capture access granted")
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMove() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        contextClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return }
            MainActor.assumeIsolated { self?.suppressForContextMenu() }
        }
    }

    private func stop() {
        if let contextClickMonitor { NSEvent.removeMonitor(contextClickMonitor) }
        contextClickMonitor = nil
        contextMenuSuppressed = false
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverTask?.cancel()
        hoveredPID = nil
        hidePanel()
    }

    private func handleMouseMove() {
        let point = NSEvent.mouseLocation
        if NSEvent.modifierFlags.contains(.control) || NSEvent.pressedMouseButtons & 2 != 0 {
            suppressForContextMenu()
            return
        }
        if contextMenuSuppressed {
            if Date() < contextMenuSuppressedUntil || hasOpenDockMenu() { return }
            contextMenuSuppressed = false
        }
        if panel?.frame.contains(point) == true {
            hideTask?.cancel()
            hideTask = nil
            return
        }
        // Keep the active hover stable while the pointer remains in its tile.
        if hoveredPID != nil, iconFrame?.insetBy(dx: -3, dy: -3).contains(point) == true {
            hideTask?.cancel()
            hideTask = nil
            return
        }
        guard isNearDockEdge(point) else {
            hoveredPID = nil
            iconFrame = nil
            hoverTask?.cancel()
            scheduleHide()
            return
        }
        guard !hitTestInFlight else { return }
        guard let dockPID = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" })?.processIdentifier,
              let top = NSScreen.screens.first?.frame.maxY else {
            diagnose("Dock process is unavailable")
            return
        }
        hitTestInFlight = true
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }.map { app in
            DockRunningApp(pid: app.processIdentifier, names: [app.localizedName,
                app.bundleURL?.deletingPathExtension().lastPathComponent].compactMap { $0?.lowercased() },
                bundlePath: app.bundleURL?.standardizedFileURL.path)
        }
        DockAccessibilityReader.queue.async { [weak self] in
            let hit = DockAccessibilityReader.hit(at: point, primaryTop: top, dockPID: dockPID, apps: apps)
            DispatchQueue.main.async {
                guard let self else { return }
                self.hitTestInFlight = false
                guard self.isEnabled, !self.contextMenuSuppressed, self.isNearDockEdge(NSEvent.mouseLocation),
                      hypot(NSEvent.mouseLocation.x - point.x, NSEvent.mouseLocation.y - point.y) < 24 else { return }
                guard let hit, let application = NSRunningApplication(processIdentifier: hit.pid) else {
                    self.diagnose("Pointer near Dock; no running application tile resolved")
                    self.hoveredPID = nil
                    self.iconFrame = nil
                    self.hoverTask?.cancel()
                    self.scheduleHide()
                    return
                }
                self.diagnose("Resolved a running application Dock tile")
                self.hideTask?.cancel()
                self.hideTask = nil
                if self.hoveredPID == hit.pid { return }
                self.hidePanel()
                self.hoveredPID = hit.pid
                self.currentPID = hit.pid
                self.iconFrame = hit.frame
                self.hoverTask?.cancel()
                self.hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await self?.showPreviews(for: application, beside: hit.frame)
                }
            }
        }
    }

    private func isNearDockEdge(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        switch orientation {
        case "left": return point.x < screen.frame.minX + 180
        case "right": return point.x > screen.frame.maxX - 180
        default: return point.y < screen.frame.minY + 180
        }
    }

    private func showPreviews(for application: NSRunningApplication, beside icon: CGRect) async {
        let pid = application.processIdentifier
        let inventory: DockWindowInventory = await withCheckedContinuation { continuation in
            DockAccessibilityReader.queue.async {
                continuation.resume(returning: DockAccessibilityReader.inventory(for: pid))
            }
        }
        guard !Task.isCancelled, currentPID == pid else { return }
        do {
            // Include windows on other Spaces and those hidden with the app.
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            // SwiftUI retains closed scene windows and their backing surfaces.
            // For our own process, AppKit can identify which document windows
            // are actually open instead of treating those surfaces as documents.
            let ownWindows = pid == ProcessInfo.processInfo.processIdentifier ? NSApp.windows.filter {
                !($0 is NSPanel) && ($0.isVisible || $0.isMiniaturized)
            } : nil
            let ownIDs = ownWindows.map { Set($0.compactMap { DockWindowMatching.assignedWindowID($0.windowNumber) }) }
            let windows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
                    && $0.frame.width > 50 && $0.frame.height > 50
                    && (ownIDs?.contains($0.windowID) ?? true)
            }
            guard !Task.isCancelled, currentPID == pid else { return }
            let accessible = inventory.windows.filter { window in
                guard let ownWindows else { return true }
                if let id = window.windowID { return ownIDs?.contains(id) == true }
                return ownWindows.contains { $0.title == window.title }
            }
            let matches = DockWindowMatching.captureIndices(
                windows: accessible.map { ($0.title, $0.frame) },
                captures: windows.map { ($0.title ?? "", $0.frame) })
            var entries: [DockWindowPreview] = []
            var captureByEntry: [String: SCWindow] = [:]
            if !accessible.isEmpty {
                // AX is the list of real windows; ScreenCaptureKit only supplies
                // images. Unioning both lists admitted browser/UI helper surfaces.
                for (index, window) in accessible.enumerated() {
                    let capture = window.windowID.flatMap { id in windows.first { $0.windowID == id } }
                        ?? matches[index].map { windows[$0] }
                    let id = window.windowID.map { "window-\($0)" } ?? "ax-\(index)"
                    entries.append(DockWindowPreview(id: id,
                        title: window.title.isEmpty ? application.localizedName ?? "Window" : window.title,
                        image: window.windowID.flatMap { imageCache[$0] }, accessibilityWindow: window.element, frame: window.frame,
                        canClose: window.canClose, windowID: window.windowID))
                    if let capture { captureByEntry[id] = capture }
                }
            } else {
                // AX can return an empty list for a full-screen window on a
                // different Space. Corroborate fallback surfaces with the window
                // server, excluding transparent and unnamed framework shells.
                let serverWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                let alphaByID = Dictionary(uniqueKeysWithValues: serverWindows.compactMap { info -> (CGWindowID, Double)? in
                    guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                          let alpha = info[kCGWindowAlpha as String] as? Double else { return nil }
                    return (id, alpha)
                })
                for window in windows where DockWindowMatching.isStandaloneCapture(
                    title: window.title ?? "", appName: application.localizedName ?? "",
                    frame: window.frame, alpha: alphaByID[window.windowID] ?? 0, isOnScreen: window.isOnScreen) {
                    let id = "sc-\(window.windowID)"
                    entries.append(DockWindowPreview(id: id, title: window.title!, image: imageCache[window.windowID],
                        accessibilityWindow: nil, frame: window.frame, canClose: true, windowID: window.windowID))
                    captureByEntry[id] = window
                }
            }
            // AX may describe only the current Space even though more document
            // windows exist. Add named, nontransparent WindowServer documents,
            // deduplicating by exact ID rather than counting capture surfaces.
            let serverList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            var knownIDs = Set(entries.compactMap(\.windowID))
            for info in serverList {
                guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      let id = info[kCGWindowNumber as String] as? CGWindowID,
                      ownIDs?.contains(id) != false,
                      !knownIDs.contains(id),
                      let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
                let title = info[kCGWindowName as String] as? String ?? ""
                guard DockWindowMatching.isStandaloneCapture(title: title,
                    appName: application.localizedName ?? "", frame: frame,
                    alpha: info[kCGWindowAlpha as String] as? Double ?? 0,
                    isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false) else { continue }
                let unidentified = entries.filter { $0.windowID == nil }
                if DockWindowMatching.index(title: title, frame: frame,
                    candidates: unidentified.map { ($0.title, $0.frame) }) != nil { continue }
                let entryID = "window-\(id)"
                entries.append(DockWindowPreview(id: entryID, title: title, image: imageCache[id],
                    accessibilityWindow: nil, frame: frame, canClose: true, windowID: id))
                knownIDs.insert(id)
                if let surface = windows.first(where: { $0.windowID == id }) { captureByEntry[entryID] = surface }
            }
            guard !entries.isEmpty else {
                diagnose("Hovered app has no previewable windows")
                hidePanel()
                return
            }
            previews = entries
            appName = application.localizedName ?? "Windows"
            showPanel(beside: icon)
            diagnose("Preview panel shown with \(entries.count) windows")
            var captured = 0
            for entry in entries {
                guard !Task.isCancelled, currentPID == pid else { return }
                var result: CGImage?
                if let id = entry.windowID {
                    result = await withCheckedContinuation { continuation in
                        DockWindowCapture.queue.async {
                            continuation.resume(returning: DockWindowCapture.image(of: id))
                        }
                    }
                }
                // Public fallback when the optional window-server bridge is
                // unavailable. Match the exact window number before geometry.
                if result == nil, let window = captureByEntry[entry.id] {
                    let config = SCStreamConfiguration()
                    let ratio = min(1, 480 / max(window.frame.width, window.frame.height, 1))
                    config.width = max(1, Int(window.frame.width * ratio))
                    config.height = max(1, Int(window.frame.height * ratio))
                    config.showsCursor = false
                    config.capturesAudio = false
                    do {
                        result = try await SCScreenshotManager.captureImage(
                            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                    } catch {
                        DiagnosticJournal.shared.recordError("Dock thumbnail capture", error)
                        let code = (error as NSError).code
                        diagnose("ScreenCaptureKit thumbnail unavailable (code \(code))")
                    }
                }
                guard !Task.isCancelled, currentPID == pid else { return }
                if let result, let index = previews.firstIndex(where: { $0.id == entry.id }) {
                    let image = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
                    previews[index].image = image
                    if let id = entry.windowID {
                        imageCache[id] = image
                        cachedWindowOrder.removeAll { $0 == id }
                        cachedWindowOrder.append(id)
                        while cachedWindowOrder.count > 24 {
                            imageCache.removeValue(forKey: cachedWindowOrder.removeFirst())
                        }
                    }
                    captured += 1
                }
            }
            errorMessage = nil
            diagnose("Thumbnail capture finished: \(captured) images for \(entries.count) windows")
        } catch {
            guard !Task.isCancelled, currentPID == pid else { return }
            errorMessage = "Could not load Dock previews: \(error.localizedDescription)"
            diagnose("ScreenCaptureKit window enumeration failed")
        }
    }

    private func showPanel(beside icon: CGRect) {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(icon) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = DockWindowMatching.panelWidth(windowCount: previews.count, availableWidth: visible.width)
        let height = min(DockWindowMatching.panelHeight, visible.height - 16)
        var x = icon.midX - width / 2
        var y = icon.maxY + 8
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        if orientation == "left" { x = icon.maxX + 8; y = icon.midY - height / 2 }
        if orientation == "right" { x = icon.minX - width - 8; y = icon.midY - height / 2 }
        x = min(max(x, visible.minX), visible.maxX - width)
        y = min(max(y, visible.minY), visible.maxY - height)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let panel = self.panel ?? NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered, defer: false)
        // Dock context menus use the popup-menu level and must stay above previews.
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DockPreviewPanelView(manager: self))
        panel.title = "Dock window previews"
        panel.identifier = NSUserInterfaceItemIdentifier("dock-window-previews")
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func activate(_ preview: DockWindowPreview) {
        guard let pid = currentPID, NSRunningApplication(processIdentifier: pid) != nil else { return }
        DockSpaceNavigation.shared.resolve(pid: pid, windowID: preview.windowID, known: preview.accessibilityWindow) { [weak self] window in
            if let window { DockAccessibilityReader.raise(window, pid: pid) }
            else { self?.errorMessage = "Could not focus the selected window. Check that moving between Spaces is enabled in Keyboard Shortcuts." }
        }
        hidePanel()
    }

    func close(_ preview: DockWindowPreview) {
        guard let pid = currentPID, preview.canClose, !closingIDs.contains(preview.id) else { return }
        closingIDs.insert(preview.id)
        DockSpaceNavigation.shared.resolve(pid: pid, windowID: preview.windowID, known: preview.accessibilityWindow) { [weak self] window in
            guard let self else { return }
            guard let window else {
                self.closingIDs.remove(preview.id)
                self.errorMessage = "Could not reach this window’s close button."
                return
            }
            self.closeResolved(preview, window: window, pid: pid)
        }
    }

    private func closeResolved(_ preview: DockWindowPreview, window: AXUIElement, pid: pid_t) {
        DockAccessibilityReader.close(window) { [weak self] accepted in
            guard let self else { return }
            guard accepted else {
                self.closingIDs.remove(preview.id)
                self.errorMessage = "This window could not be closed."
                return
            }
            // Keep the entry until AX confirms it has gone. A native save/cancel
            // sheet may leave the window open after accepting the close request.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                let inventory = await withCheckedContinuation { continuation in
                    DockAccessibilityReader.queue.async {
                        continuation.resume(returning: DockAccessibilityReader.inventory(for: pid))
                    }
                }
                guard let self, self.currentPID == pid else { return }
                self.closingIDs.remove(preview.id)
                let stillOpen = inventory.windows.contains { CFEqual($0.element, window) }
                if inventory.answered, !stillOpen {
                    self.previews.removeAll { entry in
                        entry.accessibilityWindow.map { CFEqual($0, window) } ?? (entry.id == preview.id)
                    }
                    if self.previews.isEmpty { self.hidePanel() }
                    else if let icon = self.iconFrame { self.showPanel(beside: icon) }
                } else if let application = NSRunningApplication(processIdentifier: pid) {
                    // If the application asks whether to save, let its own sheet
                    // handle that decision. Never send a global Command-W.
                    application.activate()
                    self.hidePanel()
                }
            }
        }
    }

    private func scheduleHide() {
        guard panel?.isVisible == true, hideTask == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hideTask = nil
            self?.hidePanel()
        }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func hidePanel() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        currentPID = nil
        hoveredPID = nil
        iconFrame = nil
        previews = []
        closingIDs.removeAll()
    }

    private func suppressForContextMenu() {
        contextMenuSuppressed = true
        contextMenuSuppressedUntil = Date().addingTimeInterval(0.4)
        hoverTask?.cancel()
        hoveredPID = nil; currentPID = nil; iconFrame = nil
        hidePanel()
    }

    private func hasOpenDockMenu() -> Bool {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return false }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == dock.processIdentifier &&
            (info[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.popUpMenuWindow))
        }
    }
}

private struct DockPreviewPanelView: View {
    @ObservedObject var manager: DockPreviewManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(manager.appName) · \(manager.previews.count)")
                .font(.headline).lineLimit(1)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(manager.previews) { preview in
                        VStack(alignment: .leading, spacing: 5) {
                            Button { manager.activate(preview) } label: {
                                Group {
                                    if let image = preview.image {
                                        Image(nsImage: image).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "macwindow").font(.system(size: 32))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: DockWindowMatching.cardWidth, height: 130)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                .clipped()
                            }
                            .buttonStyle(.plain)
                            .help("Show \(preview.title)")
                            .overlay(alignment: .topTrailing) {
                                Button { manager.close(preview) } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white).frame(width: 22, height: 22)
                                        .background(.black.opacity(0.65), in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                                .disabled(!preview.canClose || manager.closingIDs.contains(preview.id))
                                .opacity(preview.canClose ? 1 : 0.4)
                                .accessibilityLabel("Close \(preview.title)")
                                .help("Close this window")
                            }
                            Text(preview.title).lineLimit(1).font(.caption)
                                .frame(width: DockWindowMatching.cardWidth, alignment: .leading)
                        }
                        .frame(width: DockWindowMatching.cardWidth)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
