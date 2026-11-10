import AppKit

func buttons(in view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let presenter = PermissionExplanationPresenter.shared

    @MainActor func exercise(button title: String, accepted expected: Bool) {
        var response: Bool?
        presenter.present(title: "Permission presentation check", message: "No system permission is requested by this test.") {
            response = $0
        }
        precondition(app.modalWindow == nil, "The explanation must not enter an app-modal loop")
        let panel = app.windows.compactMap { $0 as? NSPanel }.first { $0.contentView.map { !buttons(in: $0).isEmpty } ?? false }
        precondition(panel?.styleMask.contains(.nonactivatingPanel) == true, "Must not activate the main app’s Space")
        precondition(panel?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        precondition(panel?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
        let candidates = app.windows.flatMap { $0.contentView.map { buttons(in: $0) } ?? [] }
        guard let button = candidates.first(where: { $0.title == title }) else {
            fatalError("Missing explanation button: \(title)")
        }
        // Exercise the real native button before the deferred window presentation.
        // The closed alert is never shown on the desktop, and no TCC API is called.
        button.performClick(nil)
        let deadline = Date().addingTimeInterval(1)
        while response == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(response == expected, "\(title) must complete with the correct decision")
        precondition(app.modalWindow == nil, "Dismissing the explanation must leave no modal session")
    }

    exercise(button: "Continue", accepted: true)
    exercise(button: "Not Now", accepted: false)
    print("Passed native permission-window checks: nonblocking presentation, Continue, Not Now, and no leftover modal session.")
}
