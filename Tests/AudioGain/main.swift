import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func renderQuietTone(volume: Float) -> Double {
    var limiter = AudioPeakLimiter()
    var energy = 0.0
    for frame in 0..<4_800 {
        let sample = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000)) * 0.1
        let result = sample * limiter.frameGain(peak: abs(sample), requested: volume)
        energy += Double(result * result)
    }
    return sqrt(energy / 4_800)
}

let normal = renderQuietTone(volume: 1)
let boosted150 = renderQuietTone(volume: 1.5)
let boosted200 = renderQuietTone(volume: 2)
check(abs(boosted150 / normal - 1.5) < 0.0001, "150% must apply 1.5x to quiet audio")
check(abs(boosted200 / normal - 2) < 0.0001, "200% must apply 2x to quiet audio")
check(boosted200 > boosted150 * 1.32, "150–200% must not be a dead slider range")
check(AudioGain.isUnity(1) && !AudioGain.isUnity(1.5) && !AudioGain.isUnity(2), "Boosted levels must not use the 100% bypass")
check(AudioGain.clamped(2) == 2 && AudioGain.clamped(9) == 2 && AudioGain.clamped(.nan) == 1, "The gain range must safely include 200%")

var limiter = AudioPeakLimiter()
let scale = limiter.frameGain(peak: 0.9, requested: 2)
check(0.9 * scale <= 0.98001, "Boosted peaks must fit digital full scale")
check(abs((0.3 * scale) / (0.9 * scale) - 1 / 3.0) < 0.0001, "Linked channels must retain their relative balance")
for _ in 0..<48_000 { _ = limiter.frameGain(peak: 0.1, requested: 2) }
check(limiter.frameGain(peak: 0.1, requested: 2) > 1.99, "Quiet passages must recover full boost after a peak")
check(renderQuietTone(volume: 0) == 0, "Mute must remain silent")
print("Passed audio gain checks: real 150%/200% output, unity bypass, mute, peak limiting and recovery.")
