import Foundation

/// Tracks finger movement, independently of Natural Scrolling. Momentum cannot
/// start a shortcut; a gesture can fire only once until fingers lift.
struct TouchpadGesture {
    private var x = 0.0, y = 0.0
    private var lastTime = -Double.infinity
    private var fired = false
    private var modifiers: ShortcutModifiers = []

    mutating func reset() { self = Self() }

    mutating func update(x deltaX: Double, y deltaY: Double, inverted: Bool,
                         modifiers: ShortcutModifiers, time: Double,
                         began: Bool, ended: Bool, momentum: Bool) -> String? {
        guard !momentum, !modifiers.isEmpty else { reset(); return nil }
        if began || time - lastTime > 0.25 || self.modifiers != modifiers {
            x = 0; y = 0; fired = false
        }
        self.modifiers = modifiers
        lastTime = time
        defer { if ended { reset() } }
        guard !fired, deltaX.isFinite, deltaY.isFinite else { return nil }
        let sign = inverted ? -1.0 : 1.0
        x += deltaX * sign; y += deltaY * sign
        guard max(abs(x), abs(y)) >= 30 else { return nil }
        fired = true
        return abs(x) > abs(y) ? (x > 0 ? "left" : "right") : (y > 0 ? "up" : "down")
    }
}
