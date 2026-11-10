import Foundation

/// Metadata is shared by the setup and feature-management interfaces. It does
/// not by itself imply that a feature has been downloaded or installed.
enum OptionalTool: String, CaseIterable, Identifiable {
    case keepAwake, audioMixer, fileBucket, dockPreviews, finderCut

    var id: String { rawValue }
    var packageID: String { "tool." + rawValue }
    var title: String {
        switch self {
        case .keepAwake: "Keep Awake"
        case .audioMixer: "Audio Mixer"
        case .fileBucket: "File Bucket"
        case .dockPreviews: "Dock Window Previews"
        case .finderCut: "Cmd X in Finder"
        }
    }
    var explanation: String {
        switch self {
        case .keepAwake: "Keep your Mac awake for as long as you need. You can keep your system awake when the lid is closed as well."
        case .audioMixer: "Adjust the volume of individual apps and boost audio past 100%. Requires macOS 14.2 or later."
        case .fileBucket: "Store files in a window which you can conveniently open from any window and easily add apps by dragging them to the screen edges."
        case .dockPreviews: "Preview and switch between an app’s windows from the Dock."
        case .finderCut: "Cut and move files in Finder with keyboard shortcuts."
        }
    }
}

extension WorkflowAction {
    var packageID: String { "action." + rawValue }
    var featureExplanation: String {
        switch self {
        case .prompt: "Collect text for later actions."
        case .choose: "Let someone choose an option."
        case .readFile: "Use a file’s text in later actions."
        case .typeText: "Insert text into the active app."
        case .pressKey: "Send a keyboard shortcut."
        case .click: "Click at a chosen position."
        case .movePointer: "Move the pointer to a position."
        case .scroll: "Scroll in a chosen direction."
        case .wait: "Pause before the next action."
        case .openURL: "Open a URL or local file."
        case .openApp: "Launch an app."
        case .composeMail: "Prepare an email for review."
        case .window: "Move, resize, or focus a window."
        case .setClipboard: "Put text on the clipboard."
        case .transformClipboard: "Change the clipboard’s text."
        case .pasteClipboard: "Paste the current clipboard."
        case .writeFile: "Create or replace a text file."
        case .appendFile: "Add text to the end of a file."
        case .copyFile: "Copy a file or folder."
        case .moveFile: "Move or rename an item."
        case .createFolder: "Create a folder."
        case .trashFile: "Move an item to the Trash."
        case .shell: "Run a command or script."
        case .appleScript: "Control apps with AppleScript."
        case .message: "Display a message with Continue or Cancel."
        case .notification: "Show a macOS notification with your text."
        case .screenPixel: "Continue when a color appears."
        case .screenImage: "Continue when an image appears."
        case .adjustSound: "Set, increase or decrease output volume."
        case .adjustBrightness: "Set, increase or decrease screen brightness."
        }
    }
}
