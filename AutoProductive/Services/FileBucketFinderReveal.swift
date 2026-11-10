import AppKit
import ApplicationServices

@MainActor
enum FileBucketFinderReveal {
    private static var task: Task<Void, Never>?

    static func reveal(_ url: URL, bucket: FileBucket) {
        guard FileManager.default.fileExists(atPath: url.path) else { bucket.refresh(); return }
        task?.cancel()
        bucket.hideWindow()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        guard AXIsProcessTrusted(), let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return }
        let folder = url.deletingLastPathComponent().standardizedFileURL
        task = Task {
            // Finder creates/reuses its folder window asynchronously. Resolve the
            // exact folder before using the same Space navigation as Dock previews.
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let target: DockAccessibleWindow? = await withCheckedContinuation { continuation in
                    DockAccessibilityReader.queue.async {
                        let windows = DockAccessibilityReader.windows(for: finder.processIdentifier)
                        let exact = windows.first { window in
                            var document: CFTypeRef?
                            guard AXUIElementCopyAttributeValue(window.element, kAXDocumentAttribute as CFString, &document) == .success,
                                  let path = document as? String, let candidate = URL(string: path) else { return false }
                            return candidate.standardizedFileURL == folder
                        }
                        let named = windows.filter { $0.title == folder.lastPathComponent }
                        continuation.resume(returning: exact ?? (named.count == 1 ? named.first : nil))
                    }
                }
                guard let target else { continue }
                DockSpaceNavigation.shared.resolve(pid: finder.processIdentifier, windowID: target.windowID, known: target.element) { window in
                    if let window { DockAccessibilityReader.raise(window, pid: finder.processIdentifier) }
                    else { bucket.reportError("Finder opened the folder, but its Space could not be reached. Check the Move left/right a space shortcuts in System Settings.") }
                }
                return
            }
            bucket.reportError("Finder opened the folder, but its window could not be identified. Try Show in Finder again.")
        }
    }
}
