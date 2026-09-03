import Foundation

/// Pure state machine for JKL shuttle input.
/// Feed it key transitions plus the engine's current rate; it answers with the rate command to apply.
/// Ramp position is derived from the engine's actual rate, so pausing from the control bar
/// naturally resets the ramp without extra bookkeeping.
struct ShuttleController {
    enum Key: String {
        case j, k, l
    }

    enum Command: Equatable {
        case pause
        case setRate(Float)
    }

    static let defaultRampSteps: [Float] = [1, 2, 4, 8]
    static let defaultSlowRate: Float = 0.25

    var rampSteps: [Float]
    var slowRate: Float
    private var heldKeys: Set<Key> = []

    init(rampSteps: [Float] = ShuttleController.defaultRampSteps, slowRate: Float = ShuttleController.defaultSlowRate) {
        self.rampSteps = rampSteps
        self.slowRate = slowRate
    }

    mutating func keyDown(_ key: Key, isRepeat: Bool, currentRate: Float) -> Command? {
        // Auto-repeat from holding a key must not walk the ramp; only distinct taps do.
        guard !isRepeat else { return nil }
        heldKeys.insert(key)
        switch key {
        case .k:
            return .pause
        case .l:
            return heldKeys.contains(.k)
                ? .setRate(slowRate)
                : .setRate(Self.rampedRate(from: currentRate, forward: true, steps: rampSteps))
        case .j:
            return heldKeys.contains(.k)
                ? .setRate(-slowRate)
                : .setRate(Self.rampedRate(from: currentRate, forward: false, steps: rampSteps))
        }
    }

    mutating func keyUp(_ key: Key) -> Command? {
        heldKeys.remove(key)
        switch key {
        case .k:
            // Releasing K while J or L is still down ends slow-motion rather than jumping to full speed.
            return heldKeys.isDisjoint(with: [.j, .l]) ? nil : .pause
        case .j, .l:
            return heldKeys.contains(.k) ? .pause : nil
        }
    }

    /// Next ramp speed when tapping L (forward) or J (reverse) given the current signed rate.
    /// Any rate that is stopped, in the opposite direction, or below 1x restarts the ramp at 1x.
    static func rampedRate(from currentRate: Float, forward: Bool, steps: [Float] = defaultRampSteps) -> Float {
        let speedInDirection = forward ? currentRate : -currentRate
        guard speedInDirection > 0 else { return forward ? 1 : -1 }
        let next = steps.first { $0 > speedInDirection + 0.001 } ?? steps.last ?? 1
        return forward ? next : -next
    }

    /// Title-bar label for a signed rate, or nil when paused or at normal forward speed.
    static func speedLabel(for rate: Float) -> String? {
        guard rate != 0, abs(rate - 1) > 0.001 else { return nil }
        let arrow = rate > 0 ? "▶" : "◀"
        return "\(arrow) \(formattedMagnitude(rate))×"
    }

    static func formattedMagnitude(_ rate: Float) -> String {
        let magnitude = abs(rate)
        return magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(magnitude)
    }
}
