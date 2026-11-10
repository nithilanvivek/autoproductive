import AppKit
import SwiftUI

@MainActor
final class ProblemReportCoordinator {
    static let shared = ProblemReportCoordinator()
    private var window: NSWindow?
    func startSession(defaults: UserDefaults = .standard) {
        let previous = defaults.object(forKey: "reporting.lastLaunch.v1") as? Date
        let clean = defaults.bool(forKey: "reporting.cleanExit.v1")
        let lastPresented = defaults.object(forKey: "reporting.lastPresentedCrash.v1") as? Date
        defaults.set(Date(), forKey: "reporting.lastLaunch.v1")
        defaults.set(false, forKey: "reporting.cleanExit.v1")
        DiagnosticJournal.shared.beginSession()
        DiagnosticJournal.shared.record("Lifecycle", "Application launched")
        Task {
            try? await Task.sleep(for: .seconds(3))
            let crash = await Task.detached { CrashDiagnostic.latest() }.value
            if ProcessInfo.processInfo.arguments.contains("--preview-crash-report") {
                show(crash: true, sample: true)
            } else if CrashPromptState.shouldPrompt(previousLaunch: previous, cleanExit: clean, latestCrash: crash?.date, lastPresentedCrash: lastPresented) {
                defaults.set(crash?.date, forKey: "reporting.lastPresentedCrash.v1")
                show(crash: true, diagnostic: crash)
            }
        }
    }
    func markCleanExit(defaults: UserDefaults = .standard) {
        DiagnosticJournal.shared.record("Lifecycle", "Application quit normally")
        defaults.set(true, forKey: "reporting.cleanExit.v1")
    }
    func show(crash: Bool = false, diagnostic: CrashDiagnostic? = nil, sample: Bool = false) {
        MenuBarController.shared.close()
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let model = ProblemReportModel(crash: crash, diagnostic: diagnostic, sample: sample)
        let window = NSWindow(contentViewController: NSHostingController(rootView: ProblemReportView(model: model).tint(AppPalette.textAccent)))
        window.title = crash ? "Send Crash Report" : "Report a Problem"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 440, height: 360)
        window.setContentSize(NSSize(width: 580, height: 520))
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.isReleasedWhenClosed = false
        self.window = window
        model.close = { [weak window] in window?.close() }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
    }
}

@MainActor
final class ProblemReportModel: ObservableObject {
    @Published var report = ProblemReport()
    @Published var details = ""
    @Published var includeDiagnostics = true
    @Published var loading = true
    @Published var sending = false
    @Published var sent = false
    @Published var error: String?
    private var lastAttempt: ProblemReport?
    var close: () -> Void = {}
    init(crash: Bool, diagnostic: CrashDiagnostic?, sample: Bool) {
        report.kind = crash ? "crash" : "bug"
        report.appVersion = "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))"
        report.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        report.test = sample
        if sample {
            details = "AutoProductive report delivery self-test. Synthetic diagnostics only."
            report.crash = "Synthetic crash fixture: no real crash occurred."
            report.diagnostics = "Self-test: report popup, consent, transport and delivery."
            loading = false
        } else {
            Task {
                let found: CrashDiagnostic?
                if let diagnostic { found = diagnostic }
                else if crash { found = await Task.detached { CrashDiagnostic.latest() }.value }
                else { found = nil }
                report.crash = found?.summary ?? (crash ? "No macOS crash file is available yet. The previous session ended unexpectedly." : "")
                report.diagnostics = ProblemReport.redact(DiagnosticJournal.shared.contents(includePrevious: true))
                loading = false
            }
        }
    }
    var payload: ProblemReport {
        var result = report
        result.details = String(details.prefix(10_000))
        if !includeDiagnostics { result.diagnostics = ""; result.crash = "" }
        return result
    }
    var preview: String { "App: \(report.appVersion)\nSystem: \(report.osVersion)\n\n\(payload.crash)\n\n\(payload.diagnostics)" }
    func send() {
        guard !loading, !sending, !sent else { return }
        sending = true; error = nil
        if !report.test {
            report.diagnostics = ProblemReport.redact(DiagnosticJournal.shared.contents(includePrevious: true))
        }
        report.id = payload.deliveryID(after: lastAttempt)
        let value = payload
        lastAttempt = value
        Task {
            do { try await ProblemReportTransport.send(value); sent = true }
            catch {
                DiagnosticJournal.shared.recordError("Report delivery", error)
                self.error = error.localizedDescription
            }
            sending = false
        }
    }
}
