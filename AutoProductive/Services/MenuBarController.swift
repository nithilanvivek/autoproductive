import AppKit
import Combine
import SwiftUI

/// A nonactivating panel opens in the current Space, including over full-screen
/// apps, with a curved pointer anchored to the status button's current position.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?
    private var panel: RobotMenuPanel?
    private var hosting: NSHostingView<AnyView>?
    private var content: ((NSSize, CGFloat) -> AnyView)?
    private var anchor: CGRect?
    private var visibleFrame: CGRect?
    private var maximumHeight: CGFloat = 550
    private var fittedHeight: CGFloat?
    private var keepAwakeObserver: AnyCancellable?
    private var automationObserver: AnyCancellable?
    private var globalMouseMonitor: Any?
    private var localMonitor: Any?

    func install(keepAwake: KeepAwakeManager, store: AutomationStore, runtime: AutomationRuntime,
                 content: @escaping (NSSize, CGFloat) -> AnyView) {
        self.content = content
        guard statusItem == nil else { return }
        // Keep triggers synchronized even after the main window is closed.
        automationObserver = store.$automations.sink { runtime.sync($0) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "AutoProductiveRobot"
        item.button?.target = self
        item.button?.action = #selector(toggleMenu(_:))
        statusItem = item
        PermissionExplanationPresenter.shared.closeMenuBar = { [weak self] in self?.close() }
        updateIcon(active: keepAwake.isActive)
        keepAwakeObserver = keepAwake.$isActive.sink { [weak self] active in
            self?.updateIcon(active: active)
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMouseMonitor = nil; localMonitor = nil
    }

    @objc private func toggleMenu(_ button: NSStatusBarButton) {
        guard panel?.isVisible != true else { close(); return }
        guard let window = button.window, let content else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let maximumLayout = MenuBarPopupLayout(anchor: anchor, visibleFrame: visible)
        maximumHeight = maximumLayout.frame.height - MenuBarPopupLayout.pointerHeight
        let layout = MenuBarPopupLayout(anchor: anchor, visibleFrame: visible,
                                        preferredHeight: min(maximumHeight, fittedHeight ?? maximumHeight))
        self.anchor = anchor
        visibleFrame = visible
        let root = menuContent(layout: layout, content: content)
        if let hosting { hosting.rootView = root }
        else {
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: layout.frame.size)
            self.hosting = hosting
            let panel = RobotMenuPanel(contentRect: layout.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = hosting
            self.panel = panel
        }
        guard let panel else { return }
        hosting?.frame = NSRect(origin: .zero, size: layout.frame.size)
        panel.setFrame(layout.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        startDismissalMonitoring()
    }

    private func menuContent(layout: MenuBarPopupLayout, content: (NSSize, CGFloat) -> AnyView) -> AnyView {
        let bodySize = NSSize(width: layout.frame.width, height: layout.frame.height - MenuBarPopupLayout.pointerHeight)
        let shape = RobotMenuBubble(tipX: layout.tipX)
        return AnyView(ZStack {
            AppBackground()
            content(bodySize, maximumHeight).padding(.top, MenuBarPopupLayout.pointerHeight)
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 1))
        .environment(\.controlActiveState, .active))
    }

    func fitContent(height: CGFloat) {
        fittedHeight = height
        // Layout preferences arrive during SwiftUI updates. Defer the native
        // resize, retaining the top anchor and the section's SwiftUI identity.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible,
                  let anchor = self.anchor, let visible = self.visibleFrame, let content = self.content else { return }
            let layout = MenuBarPopupLayout(anchor: anchor, visibleFrame: visible,
                                            preferredHeight: min(self.maximumHeight, max(1, height)))
            guard abs(panel.frame.height - layout.frame.height) > 1 else { return }
            self.hosting?.rootView = self.menuContent(layout: layout, content: content)
            self.hosting?.frame = NSRect(origin: .zero, size: layout.frame.size)
            panel.setFrame(layout.frame, display: true)
        }
    }

    private func startDismissalMonitoring() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.closeIfOutside(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                if event.type == .keyDown {
                    if event.keyCode == 53, self?.panel?.isKeyWindow == true { self?.close(); return true }
                } else { self?.closeIfOutside(event) }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func closeIfOutside(_ event: NSEvent) {
        if event.window === panel { return }
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        if panel?.frame.contains(point) == true { return }
        if let button = statusItem?.button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        close()
    }

    private func updateIcon(active: Bool) {
        let image = MenuBarRobotIcon.image(active: active)
        image.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = image
        statusItem?.button?.setAccessibilityLabel(active ? "AutoProductive, Keep Awake on" : "AutoProductive")
    }
}

private final class RobotMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct RobotMenuBubble: Shape {
    let tipX: CGFloat
    func path(in rect: CGRect) -> Path {
        let top = MenuBarPopupLayout.pointerHeight
        let r = min(18.0, rect.width / 4, max(0, (rect.height - top) / 4))
        let x = tipX, w = rect.width, h = rect.height
        return Path { p in
            p.move(to: CGPoint(x: r, y: top))
            p.addLine(to: CGPoint(x: x - 18, y: top))
            p.addCurve(to: CGPoint(x: x - 7, y: 4), control1: CGPoint(x: x - 12, y: top), control2: CGPoint(x: x - 11, y: 7))
            p.addCurve(to: CGPoint(x: x, y: 0), control1: CGPoint(x: x - 3, y: 0), control2: CGPoint(x: x - 2, y: 0))
            p.addCurve(to: CGPoint(x: x + 7, y: 4), control1: CGPoint(x: x + 2, y: 0), control2: CGPoint(x: x + 3, y: 0))
            p.addCurve(to: CGPoint(x: x + 18, y: top), control1: CGPoint(x: x + 11, y: 7), control2: CGPoint(x: x + 12, y: top))
            p.addLine(to: CGPoint(x: w - r, y: top))
            p.addQuadCurve(to: CGPoint(x: w, y: top + r), control: CGPoint(x: w, y: top))
            p.addLine(to: CGPoint(x: w, y: h - r))
            p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: r, y: h))
            p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: top + r))
            p.addQuadCurve(to: CGPoint(x: r, y: top), control: CGPoint(x: 0, y: top))
            p.closeSubpath()
        }
    }
}

/// Capture the scene-aware action before hosting the menu in AppKit.
struct MenuBarInstallationView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AutomationStore
    @EnvironmentObject private var runtime: AutomationRuntime
    @EnvironmentObject private var backgroundAgent: BackgroundAgentManager
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var keepAwake: KeepAwakeManager
    @AppStorage("hasSeenMenuBarRobotIntroduction") private var hasSeenRobotIntroduction = false
    @State private var showRobotIntroduction = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            AppUpdateManager.shared.start()
            if FileBucket.shared.isAvailable { FileBucketShortcuts.shared.start() }
            MenuBarController.shared.install(keepAwake: keepAwake, store: store, runtime: runtime) { size, maximumHeight in
                AnyView(MenuBarView(popupSize: size, maximumHeight: maximumHeight,
                                    openMainWindow: { openWindow(id: "main") },
                                    contentHeightChanged: { MenuBarController.shared.fitContent(height: $0) })
                    .environmentObject(store)
                    .environmentObject(runtime)
                    .environmentObject(backgroundAgent)
                    .environmentObject(navigation)
                    .environmentObject(keepAwake))
            }
            if !AutoProductiveAppDelegate.isMenuBarAgentLaunch && !hasSeenRobotIntroduction {
                showRobotIntroduction = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !hasSeenRobotIntroduction { showRobotIntroduction = true }
        }
        .alert("Meet the AutoProductive robot", isPresented: $showRobotIntroduction) {
            Button("Got it") { hasSeenRobotIntroduction = true }
        } message: {
            Text("The robot icon in your menu bar belongs to AutoProductive. Click it to access your tools and automations.")
        }
    }
}
