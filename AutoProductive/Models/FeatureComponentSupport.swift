import Foundation

enum FeatureComponentSupport {
    /// The 1.3-test UI uses the unchanged, signed 1.1 components.
    static func componentVersion(for appVersion: String) -> String {
        if appVersion == "1.0" { return "1.0-release" }
        if appVersion == "1.7-test" { return "1.6-test" }
        return ["1.3-test", "1.4-test", "1.5-test"].contains(appVersion) ? "1.1" : appVersion
    }

    static var supportDirectoryName: String {
        Bundle.main.bundleIdentifier == "land.nithi.autoproductive.test14" ? "AutoProductive 1.4 Test" : "AutoProductive"
    }
    static let toolIDs: Set<String> = ["tool.finderCut", "tool.fileBucket", "tool.keepAwake", "tool.audioMixer", "tool.dockPreviews"]
    // Component coverage is still being verified in the experimental modular
    // build; inclusion here is not a claim of release readiness.
    static let actionIDs: Set<String> = [
        "action.transformClipboard", "action.wait", "action.readFile", "action.writeFile",
        "action.appendFile", "action.createFolder", "action.copyFile", "action.moveFile", "action.trashFile",
        "action.adjustSound", "action.adjustBrightness", "action.setClipboard", "action.pressKey", "action.pasteClipboard",
        "action.typeText", "action.click", "action.movePointer", "action.scroll", "action.openURL", "action.openApp", "action.composeMail",
        "action.screenPixel", "action.screenImage", "action.shell", "action.appleScript", "action.prompt", "action.choose", "action.message", "action.notification", "action.window"
    ]

    static func requiredToolSymbols(_ id: String) -> [String]? {
        switch id {
        case "tool.finderCut": ["autoproductive_finder_cut_reset", "autoproductive_finder_cut_mark", "autoproductive_finder_cut_decide", "autoproductive_finder_cut_pending", "autoproductive_finder_cut_matches"]
        case "tool.fileBucket": ["autoproductive_file_bucket_request", "autoproductive_file_bucket_free"]
        case "tool.keepAwake": ["autoproductive_keep_awake_start", "autoproductive_keep_awake_stop", "autoproductive_keep_awake_system_assertion", "autoproductive_keep_awake_display_assertion"]
        case "tool.audioMixer": ["autoproductive_audio_tap_create", "autoproductive_audio_tap_gain", "autoproductive_audio_tap_set_gain", "autoproductive_audio_tap_destroy"]
        case "tool.dockPreviews": ["autoproductive_dock_capture_image"]
        default: nil
        }
    }
}
