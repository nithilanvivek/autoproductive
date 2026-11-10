import Foundation
import CoreGraphics

precondition(DockWindowMatching.assignedWindowID(-1) == nil, "Unassigned AppKit windows must not trap during preview filtering")
precondition(DockWindowMatching.assignedWindowID(0) == nil)
precondition(DockWindowMatching.assignedWindowID(Int.max) == nil)
precondition(DockWindowMatching.assignedWindowID(42) == 42)

let first = CGRect(x: 10, y: 30, width: 800, height: 600)
let second = CGRect(x: 100, y: 60, width: 800, height: 600)
let sameTitles: [(title: String, frame: CGRect?)] = [("Untitled", first), ("Untitled", second)]
precondition(DockWindowMatching.index(title: "Untitled", frame: second, candidates: sameTitles) == 1,
             "Two equally named windows must resolve to the selected window by bounds")
precondition(DockWindowMatching.index(title: "Untitled", frame: nil, candidates: sameTitles) == nil,
             "An ambiguous title must not raise an arbitrary window")
precondition(DockWindowMatching.index(title: "", frame: first, candidates: [("", first), ("", second)]) == 0,
             "Untitled surfaces must match by bounds")
precondition(DockWindowMatching.index(title: "Document", frame: nil, candidates: [("Document", nil)]) == 0)
let many = (0..<10).map { (title: "Document \($0)", frame: Optional(CGRect(x: $0 * 30, y: 0, width: 500, height: 300))) }
for index in many.indices {
    precondition(DockWindowMatching.index(title: many[index].title, frame: many[index].frame, candidates: many) == index)
}
let chromeCaptures: [(title: String, frame: CGRect?)] = [
    ("", first), ("Google Chrome", first), ("New tab", first), ("", second), ("Google Chrome", second)]
let chrome = DockWindowMatching.captureIndices(windows: [("New tab", first)], captures: chromeCaptures)
precondition(chrome.count == 1 && chrome[0] == 2,
             "One Chrome AX window must select its document image without adding internal capture surfaces")
let chat = DockWindowMatching.captureIndices(windows: [("Conversation", second)],
    captures: [("ChatGPT", second), ("Conversation", second), ("", first)])
precondition(chat.count == 1 && chat[0] == 1)
precondition(DockWindowMatching.captureIndices(windows: [("Minimized", nil)], captures: []).count == 1,
             "A minimized real window stays listed without a capturable image")
precondition(DockWindowMatching.isUserWindow(role: "AXWindow", subrole: "AXStandardWindow",
    minimized: false, fullscreen: false, canMinimize: true))
precondition(!DockWindowMatching.isUserWindow(role: "AXWindow", subrole: "AXUnknown",
    minimized: false, fullscreen: false, canMinimize: false), "Internal browser shells must be excluded")
precondition(DockWindowMatching.isUserWindow(role: "AXWindow", subrole: "AXUnknown",
    minimized: true, fullscreen: false, canMinimize: false))
precondition(DockWindowMatching.panelWidth(windowCount: 10, availableWidth: 800) == 784)
precondition(DockWindowMatching.panelWidth(windowCount: 1, availableWidth: 800) == 240)
precondition(DockWindowMatching.panelWidth(windowCount: 2, availableWidth: 800) == 470)
precondition(DockWindowMatching.panelHeight < 220)
precondition(DockWindowMatching.isStandaloneCapture(title: "Document", appName: "Chrome", frame: first,
    alpha: 1, isOnScreen: false), "A full-screen document on another Space must survive an empty AX list")
precondition(!DockWindowMatching.isStandaloneCapture(title: "Chrome", appName: "Chrome", frame: first,
    alpha: 1, isOnScreen: false), "An off-screen application shell must stay excluded")
precondition(!DockWindowMatching.isStandaloneCapture(title: "Document", appName: "Chrome", frame: first,
    alpha: 0, isOnScreen: true), "Transparent helper surfaces are not document windows")
print("Passed Dock checks: real Chrome/ChatGPT window inventory, helper exclusion, minimized windows, distinct matching, and compact horizontal sizing.")

let desktops: [(spaces: [UInt64], current: UInt64?)] = [([1, 2, 3, 4], 2)]
precondition(DockSpaceRoute.distance(targets: [4], displays: desktops) == 2)
precondition(DockSpaceRoute.distance(targets: [1], displays: desktops) == -1)
precondition(DockSpaceRoute.distance(targets: [2], displays: desktops) == 0)
precondition(DockSpaceRoute.distance(targets: [99], displays: desktops) == nil)
precondition(DockSpaceRoute.distance(targets: [8], displays: [([1, 2], 1), ([7, 8], 8)]) == 0)
var progress = DockSpaceProgress()
precondition(progress.accept(visible: [1], distance: -3))
precondition(progress.accept(visible: [2], distance: -2))
precondition(!progress.accept(visible: [1], distance: -3), "Stop when Space navigation cycles")
var noProgress = DockSpaceProgress()
precondition(noProgress.accept(visible: [1], distance: 2))
precondition(!noProgress.accept(visible: [2], distance: 3), "Stop when a Space switch moves farther away")
print("Passed exact-window Space routing checks: forward, backward, visible, unavailable and other-display visibility.")
let arrowFlags = DockSpaceRoute.shortcutFlags(0x840000)
precondition(arrowFlags.contains(.maskControl) && arrowFlags.contains(.maskSecondaryFn),
             "Space arrows must retain both Control and Fn from the registered shortcut")
precondition(DockSpaceRoute.shortcutFlags(0x920000) == [.maskCommand, .maskShift, .maskSecondaryFn])
print("Passed Space shortcut modifier checks, including the Control/Fn regression.")
