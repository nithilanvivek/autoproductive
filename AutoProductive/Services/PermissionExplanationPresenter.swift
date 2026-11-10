import AppKit
import SwiftUI

/// The app's explanation is modeless. Native permission requests run only after
/// Continue, outside the SwiftUI control's event/update transaction.
@MainActor
final class PermissionExplanationPresenter: NSObject, NSWindowDelegate {
    static let shared = PermissionExplanationPresenter()

    weak var menuBarWindow: NSWindow?
    var closeMenuBar: (() -> Void)?
    private var alert: NSAlert?
    private var panel: ExplanationPanel?
    private var completion: ((Bool) -> Void)?

    func present(title: String, message: String, completion: @escaping (Bool) -> Void) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let continueButton = alert.addButton(withTitle: "Continue")
        continueButton.target = self
        continueButton.action = #selector(continueRequest)
        continueButton.keyEquivalent = "\r"
        let cancelButton = alert.addButton(withTitle: "Not Now")
        cancelButton.target = self
        cancelButton.action = #selector(cancelRequest)
        cancelButton.keyEquivalent = "\u{1b}"
        alert.layout()
        let panel = ExplanationPanel(contentRect: alert.window.frame,
                                     styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = alert.window.contentView
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        self.panel = panel
        self.alert = alert
        self.completion = completion

        if let closeMenuBar { closeMenuBar() }
        else if let menuBarWindow, menuBarWindow.isVisible { menuBarWindow.close() }
        DispatchQueue.main.async { [weak self, weak alert] in
            guard let self, alert != nil, self.alert === alert else { return }
            guard let panel = self.panel else { return }
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
            }
            // Join the current Space without activating the main app's desktop.
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func continueRequest() { finish(accepted: true) }
    @objc private func cancelRequest() { finish(accepted: false) }
    func cancelPendingRequest() { finish(accepted: false) }

    func windowWillClose(_ notification: Notification) { finish(accepted: false) }

    private func finish(accepted: Bool) {
        guard alert != nil else { return }
        let completion = completion
        self.completion = nil
        self.alert = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        DispatchQueue.main.async { completion?(accepted) }
    }
}

/// Keep a weak reference to the actual menu panel, rather than guessing which
/// key window belongs to the menu popover when a permission action is selected.
struct MenuBarWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowReaderView() }
    func updateNSView(_ nsView: NSView, context: Context) { }

    private final class WindowReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { PermissionExplanationPresenter.shared.menuBarWindow = window }
        }
    }
}

private final class ExplanationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
