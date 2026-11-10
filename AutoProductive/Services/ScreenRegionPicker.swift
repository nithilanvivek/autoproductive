import AppKit

/// An explicit, temporary screen-selection overlay. It records geometry only;
/// screenshots are taken later by the permission-checked matching service.
@MainActor
final class ScreenRegionPicker {
    static let shared = ScreenRegionPicker()
    enum Mode { case pixel, rectangle, clickPosition }
    private var panels: [NSPanel] = []
    private var completion: ((ScreenColorRegion) -> Void)?
    private weak var previousWindow: NSWindow?
    private var cursorHidden = false
    private var deactivationObserver: NSObjectProtocol?

    func select(mode: Mode, primaryDisplayOnly: Bool = false, completion: @escaping (ScreenColorRegion) -> Void) throws {
        guard panels.isEmpty, !AutomationCaptureCoordination.isRecording else {
            throw WorkflowError.invalid("Finish the current recording or screen selection first.")
        }
        guard !NSScreen.screens.isEmpty else { throw WorkflowError.invalid("No screen is available.") }
        previousWindow = NSApp.keyWindow
        self.completion = completion
        AutomationCaptureCoordination.setRecording(true)
        MenuBarController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = primaryDisplayOnly ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
        for screen in screens {
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .screenSaver
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), mode: mode)
            view.finished = { [weak self] rect in
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.finish(ScreenColorRegion(x: global.minX, y: primaryTop - global.maxY,
                                               width: global.width, height: global.height))
            }
            view.cancelled = { [weak self] in self?.cancel() }
            panel.contentView = view
            panels.append(panel)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            panel.orderFrontRegardless()
            view.updatePointerLocation()
        }
        // A view-drawn crosshair remains stable when other AppKit cursor
        // rectangles try to replace the native cursor during movement.
        NSCursor.hide(); cursorHidden = true
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() { finish(nil) }
    private func finish(_ region: ScreenColorRegion?) {
        guard !panels.isEmpty else { return }
        let callback = completion; completion = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        panels.forEach { $0.orderOut(nil) }; panels.removeAll()
        AutomationCaptureCoordination.setRecording(false)
        previousWindow?.makeKeyAndOrderFront(nil)
        if let region { callback?(region) }
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    let mode: ScreenRegionPicker.Mode
    var finished: ((CGRect) -> Void)?
    var cancelled: (() -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    private var cursorTracking: NSTrackingArea?
    private var pointer: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, mode: ScreenRegionPicker.Mode) { self.mode = mode; super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited, .mouseMoved],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); cursorTracking = area
    }
    func updatePointerLocation() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        setPointer(bounds.contains(point) ? point : nil)
    }
    override func mouseEntered(with event: NSEvent) { updatePointerLocation() }
    override func mouseMoved(with event: NSEvent) { updatePointerLocation() }
    override func mouseExited(with event: NSEvent) { setPointer(nil) }
    private func setPointer(_ point: CGPoint?) {
        for position in [pointer, point].compactMap({ $0 }) {
            setNeedsDisplay(CGRect(x: position.x - 12, y: position.y - 12, width: 24, height: 24))
        }
        pointer = point
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelled?() }
    }
    override func mouseDown(with event: NSEvent) {
        updatePointerLocation()
        start = bounded(event); selection = nil; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        updatePointerLocation()
        guard let start, mode == .rectangle else { return }
        let end = bounded(event)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        if mode == .pixel {
            let point = bounded(event)
            // A one-point box gives the same top-left coordinate convention as rectangles.
            finished?(CGRect(x: min(bounds.maxX - 1, floor(point.x)), y: min(bounds.maxY - 1, floor(point.y)), width: 1, height: 1))
        } else if mode == .clickPosition {
            // A zero-sized point avoids shifting the clicked top-left coordinate
            // by the one-point box used for screen-color selection.
            finished?(CGRect(origin: bounded(event), size: .zero))
        } else {
            let end = bounded(event)
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            if rect.width >= 1 && rect.height >= 1 { finished?(rect) }
        }
        self.start = nil
    }
    private func bounded(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: max(0, min(bounds.maxX, p.x)), y: max(0, min(bounds.maxY, p.y)))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill(); bounds.fill()
        if let selection {
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill(); selection.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 2; border.stroke()
        }
        let text = mode == .rectangle ? "Drag a rectangle · Esc to cancel" : "Click a pixel · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let card = CGRect(x: max(8, (bounds.width - size.width - 24) / 2), y: max(8, bounds.height - 90), width: min(bounds.width - 16, size.width + 24), height: 42)
        NSColor.black.withAlphaComponent(0.85).setFill(); NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
        (text as NSString).draw(in: card.insetBy(dx: 12, dy: 12), withAttributes: attributes)
        if let pointer {
            let crosshair = NSBezierPath()
            crosshair.move(to: CGPoint(x: pointer.x - 9, y: pointer.y))
            crosshair.line(to: CGPoint(x: pointer.x + 9, y: pointer.y))
            crosshair.move(to: CGPoint(x: pointer.x, y: pointer.y - 9))
            crosshair.line(to: CGPoint(x: pointer.x, y: pointer.y + 9))
            NSColor.black.setStroke(); crosshair.lineWidth = 3; crosshair.stroke()
            NSColor.white.setStroke(); crosshair.lineWidth = 1; crosshair.stroke()
        }
    }
}
