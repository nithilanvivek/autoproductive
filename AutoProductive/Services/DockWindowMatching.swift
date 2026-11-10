import Foundation
import CoreGraphics

enum DockWindowMatching {
    /// AppKit uses -1 for windows that have no assigned WindowServer number.
    static func assignedWindowID(_ number: Int) -> CGWindowID? {
        guard let id = CGWindowID(exactly: number), id != 0 else { return nil }
        return id
    }

    /// Title alone is ambiguous (two untitled documents, for example). Prefer
    /// the window's bounds, then use a title only when it identifies one window.
    static func index(title: String, frame: CGRect?, candidates: [(title: String, frame: CGRect?)]) -> Int? {
        let titled = candidates.indices.filter { !title.isEmpty && candidates[$0].title == title }
        // Browser helper surfaces may share a document's frame. Match its
        // actual document title before considering those unnamed surfaces.
        let eligible = titled.isEmpty ? Array(candidates.indices) : titled
        if let frame {
            let distances = eligible.compactMap { index -> (Int, CGFloat)? in
                let candidate = candidates[index]
                guard let other = candidate.frame else { return nil }
                let distance = abs(frame.minX - other.minX) + abs(frame.minY - other.minY)
                    + abs(frame.width - other.width) + abs(frame.height - other.height)
                return distance <= 8 ? (index, distance) : nil
            }
            if let best = distances.min(by: { $0.1 < $1.1 }) { return best.0 }
        }
        return titled.count == 1 ? titled[0] : nil
    }

    static func isUserWindow(role: String?, subrole: String?, minimized: Bool,
                             fullscreen: Bool, canMinimize: Bool) -> Bool {
        guard role == "AXWindow" else { return false }
        if minimized || fullscreen { return true }
        if subrole == "AXStandardWindow" || subrole == "AXFullScreenWindow" { return true }
        return canMinimize && (subrole == nil || subrole == "AXUnknown" || subrole == "AXDialog")
    }

    /// One slot per real AX window. Capture-only helper surfaces are never
    /// promoted into additional windows when the application has answered AX.
    static func captureIndices(windows: [(title: String, frame: CGRect?)],
                               captures: [(title: String, frame: CGRect?)]) -> [Int?] {
        var available = Array(captures.indices)
        return windows.map { window in
            guard let offset = index(title: window.title, frame: window.frame,
                candidates: available.map { captures[$0] }) else { return nil }
            return available.remove(at: offset)
        }
    }

    static func isStandaloneCapture(title: String, appName: String, frame: CGRect,
                                    alpha: Double, isOnScreen: Bool) -> Bool {
        guard alpha > 0, frame.width >= 150, frame.height >= 100,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // Hidden framework shells commonly have only the application's name.
        // An off-Space document keeps its own title even when AXWindows is empty.
        return isOnScreen || title != appName
    }

    static let cardWidth: CGFloat = 220
    static let panelHeight: CGFloat = 206

    static func panelWidth(windowCount: Int, availableWidth: CGFloat) -> CGFloat {
        let content = CGFloat(max(1, windowCount)) * cardWidth + CGFloat(max(0, windowCount - 1)) * 10 + 20
        return min(content, max(100, availableWidth - 16))
    }
}

enum DockSpaceRoute {
    static func shortcutFlags(_ registeredMask: UInt32) -> CGEventFlags {
        let supported: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        return CGEventFlags(rawValue: UInt64(registeredMask)).intersection(supported)
    }

    static func distance(targets: Set<UInt64>, displays: [(spaces: [UInt64], current: UInt64?)]) -> Int? {
        if displays.contains(where: { $0.current.map(targets.contains) == true }) { return 0 }
        for display in displays {
            guard let current = display.current, let origin = display.spaces.firstIndex(of: current) else { continue }
            let candidates = display.spaces.indices.filter { targets.contains(display.spaces[$0]) }
            if let nearest = candidates.min(by: { abs($0 - origin) < abs($1 - origin) }) { return nearest - origin }
        }
        return nil
    }
}

/// Stop navigation if the system revisits a Space or moves farther away.
struct DockSpaceProgress {
    private var visited: Set<Set<UInt64>> = []
    private var previousDistance: Int?

    mutating func accept(visible: Set<UInt64>, distance: Int) -> Bool {
        guard !visited.contains(visible),
              previousDistance.map({ abs(distance) < abs($0) }) ?? true else { return false }
        visited.insert(visible)
        previousDistance = distance
        return true
    }
}
