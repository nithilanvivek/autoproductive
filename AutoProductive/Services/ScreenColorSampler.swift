import AppKit

/// Use the system magnifier, whose session spans windows and displays until
/// selection or Escape. Do not end sampling when the editor loses focus.
@MainActor
final class ScreenColorSampler {
    static let shared = ScreenColorSampler()
    private var sampler: NSColorSampler?
    private var recordingLease: Timer?

    func select(completion: @escaping (ScreenColor) -> Void) throws {
        guard sampler == nil, !AutomationCaptureCoordination.isRecording else {
            throw WorkflowError.invalid("Finish the current recording or screen selection first.")
        }
        let sampler = NSColorSampler()
        self.sampler = sampler
        AutomationCaptureCoordination.setRecording(true)
        recordingLease = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { AutomationCaptureCoordination.setRecording(true) }
        }
        MenuBarController.shared.close()
        sampler.show { [weak self] color in
            // NSColorSampler's handler is documented to run on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recordingLease?.invalidate(); self.recordingLease = nil
                self.sampler = nil
                AutomationCaptureCoordination.setRecording(false)
                if let rgb = color?.usingColorSpace(.sRGB) {
                    completion(ScreenColor(red: Self.channel(rgb.redComponent),
                                           green: Self.channel(rgb.greenComponent),
                                           blue: Self.channel(rgb.blueComponent)))
                }
            }
        }
    }

    private static func channel(_ value: CGFloat) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
}
