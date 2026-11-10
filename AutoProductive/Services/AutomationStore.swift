import Foundation
import Combine
import CoreGraphics
import AppKit
import ApplicationServices
import IOKit.hidsystem

@MainActor
final class AutomationStore: ObservableObject {
    static let shared = AutomationStore()
    @Published private(set) var automations: [SavedAutomation] = []

    nonisolated static let storageKey = "savedAutomations.v1"
    private static let pendingInputRequestKey = "pendingInputRequest.v1"
    private let defaults: UserDefaults
    private var pendingInputRequest: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pendingInputRequest = defaults.bool(forKey: Self.pendingInputRequestKey)
        migrateTestAutomationsIfNeeded()
        load()
        enforcePermissions()
    }

    private func migrateTestAutomationsIfNeeded() {
        let migrationKey = "testAutomationsMigrated.v1"
        guard Bundle.main.bundleIdentifier == "land.nithi.autoproductive", !defaults.bool(forKey: migrationKey),
              let testDefaults = UserDefaults(suiteName: "land.nithi.autoproductive.test14") else { return }
        do {
            let releaseData = defaults.data(forKey: Self.storageKey)
            let testData = testDefaults.data(forKey: Self.storageKey)
            let release = try releaseData.map { try JSONDecoder().decode([SavedAutomation].self, from: $0) } ?? []
            let test = try testData.map { try JSONDecoder().decode([SavedAutomation].self, from: $0) } ?? []
            if !test.isEmpty {
                let merged = AutomationMigration.merge(release: release, test: test)
                defaults.set(try JSONEncoder().encode(merged), forKey: Self.storageKey)
            }
            defaults.set(true, forKey: migrationKey)
        } catch {
            DiagnosticJournal.shared.recordError("Automation migration", error)
        }
    }

    func automation(id: UUID) -> SavedAutomation? {
        automations.first { $0.id == id }
    }

    func save(_ automation: SavedAutomation) {
        let isNew = !automations.contains { $0.id == automation.id }
        var saved = automation
        if let workflow = automation.workflow, isNew || workflow.isEnabled {
            // Creation and Enable are explicit actions. Re-request when access is missing.
            requestPermissions(for: workflow)
        }
        if let workflow = saved.workflow, workflow.isEnabled, !missingPermissions(for: workflow).isEmpty {
            saved.workflow?.isEnabled = false
        }
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index] = saved
        } else {
            automations.insert(saved, at: 0)
        }
        persist()
    }

    func missingPermissions(for workflow: WorkflowDefinition) -> [String] {
        var missing: [String] = []
        if Self.needsAccessibility(workflow) && !AXIsProcessTrusted() { missing.append(DesktopAutomationService.controlPermissionName) }
        if Self.needsInputMonitoring(workflow) && !CGPreflightListenEventAccess() { missing.append("Input Monitoring") }
        if Self.needsScreenRecording(workflow) && !CGPreflightScreenCaptureAccess() { missing.append("Screen Recording") }
        return missing
    }

    func requestPermissions(for workflow: WorkflowDefinition) {
        let missing = missingPermissions(for: workflow)
        guard !missing.isEmpty else { return }
        explainPermissions(missing) { [weak self] accepted in
            if accepted { self?.requestSystemPermissions(missing) }
        }
    }

    private func requestSystemPermissions(_ missing: [String]) {
        if missing.contains(DesktopAutomationService.controlPermissionName) {
            pendingInputRequest = missing.contains("Input Monitoring")
            defaults.set(pendingInputRequest, forKey: Self.pendingInputRequestKey)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if !AXIsProcessTrusted() {
                PermissionSettings.open(DesktopAutomationService.controlPermissionName)
                objectWillChange.send()
                return
            }
        }
        if missing.contains("Input Monitoring") {
            requestInputMonitoring()
            if !CGPreflightListenEventAccess() {
                objectWillChange.send()
                return
            }
        }
        if missing.contains("Screen Recording") { _ = CGRequestScreenCaptureAccess() }
        objectWillChange.send()
    }

    private func requestInputMonitoring() {
        pendingInputRequest = false
        defaults.set(false, forKey: Self.pendingInputRequestKey)
        // Explicitly request the Input Monitoring entry as recommended by Apple DTS:
        // https://developer.apple.com/forums/thread/828052
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = CGRequestListenEventAccess()
        // A previous request may not show another native alert. Always open the switch.
        PermissionSettings.open("Input Monitoring")
    }

    func requestFinderCutPermissions(completion: @escaping (Bool) -> Void) {
        var missing: [String] = []
        if !AXIsProcessTrusted() { missing.append(DesktopAutomationService.controlPermissionName) }
        if !CGPreflightListenEventAccess() { missing.append("Input Monitoring") }
        guard !missing.isEmpty else { completion(true); return }
        PermissionExplanationPresenter.shared.present(
            title: "Enable Finder file cut and paste",
            message: "AutoProductive recognizes Command-X and Command-V only while Finder is in front. It uses Finder’s own copy and move commands; it does not read file contents. macOS requires Input Monitoring and \(DesktopAutomationService.controlPermissionName) for this shortcut. Continue opens the missing permission in System Settings."
        ) { [weak self] accepted in
            guard accepted, let self else { completion(false); return }
            self.requestSystemPermissions(missing)
            completion(AXIsProcessTrusted() && CGPreflightListenEventAccess())
        }
    }

    private static func needsInputMonitoring(_ workflow: WorkflowDefinition) -> Bool {
        [WorkflowTrigger.textExpansion, .keyRemap, .touchpad].contains(where: { workflow.uses($0) })
    }

    private static func needsAccessibility(_ workflow: WorkflowDefinition) -> Bool {
        needsInputMonitoring(workflow) || workflow.steps.contains {
            [.typeText, .pressKey, .click, .movePointer, .scroll, .window, .pasteClipboard].contains($0.action)
        }
    }

    private static func needsScreenRecording(_ workflow: WorkflowDefinition) -> Bool {
        workflow.uses(.screen) || workflow.steps.contains { [.screenPixel, .screenImage].contains($0.action) }
    }

    private func explainPermissions(_ missing: [String], completion: @escaping (Bool) -> Void) {
        var reasons: [String] = []
        if missing.contains("Input Monitoring") {
            reasons.append("Input Monitoring recognizes the Text Trigger, key remap, or touchpad shortcut you chose. Text Triggers keep only a short in-memory phrase buffer and skip secure input.")
        }
        if missing.contains(DesktopAutomationService.controlPermissionName) {
            reasons.append("\(DesktopAutomationService.controlPermissionName) is a broad macOS permission. AutoProductive uses it to identify editable, non-password fields and carry out the keyboard, mouse, or window actions you configure.")
        }
        if missing.contains("Screen Recording") {
            reasons.append("Screen Recording lets screen-condition automations check the pixels you selected.")
        }
        let nextPermission = missing[0]
        var message = reasons.joined(separator: "\n\n")
            + "\n\nContinue opens \(nextPermission) in System Settings. Turn on AutoProductive there, then return here to enable your automation."
        if nextPermission == "Input Monitoring" || nextPermission == DesktopAutomationService.controlPermissionName {
            message += " If AutoProductive isn’t listed, use the + button to add it."
        }
        PermissionExplanationPresenter.shared.present(
            title: "Why AutoProductive asks for access", message: message, completion: completion)
    }

    func delete(_ automation: SavedAutomation) {
        WorkflowEngine.shared.stop(automation.id)
        automations.removeAll { $0.id == automation.id }
        persist()
    }

    private func load() {
        automations = Self.loadStoredAutomations(defaults: defaults)
    }

    func reload() { load() }

    func enforcePermissions() {
        if pendingInputRequest && NSApp.isActive && AXIsProcessTrusted() {
            if !CGPreflightListenEventAccess() {
                requestInputMonitoring()
            } else {
                pendingInputRequest = false
                defaults.set(false, forKey: Self.pendingInputRequestKey)
            }
        }
        var changed = false
        for index in automations.indices {
            guard let workflow = automations[index].workflow, workflow.isEnabled,
                  !missingPermissions(for: workflow).isEmpty else { continue }
            automations[index].workflow?.isEnabled = false
            changed = true
        }
        if changed { persist() }
        else { objectWillChange.send() }
    }

    func setEnabled(_ automation: SavedAutomation, enabled: Bool) {
        var updated = automation
        updated.isEnabled = enabled
        if !enabled { WorkflowEngine.shared.stop(updated.id) }
        save(updated)
    }

    private func persist() {
        do { defaults.set(try JSONEncoder().encode(automations), forKey: Self.storageKey) }
        catch { DiagnosticJournal.shared.recordError("Automation persistence", error) }
    }

    nonisolated static func loadStoredAutomations(defaults: UserDefaults = .standard) -> [SavedAutomation] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do { return try JSONDecoder().decode([SavedAutomation].self, from: data) }
        catch { DiagnosticJournal.shared.recordError("Automation loading", error); return [] }
    }
}
