import Foundation

enum AudioGain {
    static let maximum: Double = 2

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), maximum) : 1
    }

    static func isUnity(_ value: Double) -> Bool { abs(value - 1) < 0.0001 }
}

#if !MODULAR_FEATURES
/// A linked-channel peak limiter. Quiet audio receives the full requested gain;
/// only peaks that would exceed digital full scale reduce the frame's gain.
struct AudioPeakLimiter {
    private var attenuation: Float = 1
    private let recovery: Float

    init(sampleRate: Double = 48_000) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        recovery = Float(1 - exp(-1 / (rate * 0.1)))
    }

    mutating func frameGain(peak: Float, requested: Float) -> Float {
        guard requested > 1 else { attenuation = 1; return requested }
        let boosted = peak * requested
        let allowed: Float = boosted > 0.98 ? 0.98 / boosted : 1
        if allowed < attenuation { attenuation = allowed }
        else { attenuation += (allowed - attenuation) * recovery }
        return requested * attenuation
    }
}
#endif
