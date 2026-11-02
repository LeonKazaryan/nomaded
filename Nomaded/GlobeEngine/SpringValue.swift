import Foundation

/// Spring feel in the same terms as SwiftUI's `.spring(response:dampingFraction:)`,
/// so engine motion can mirror the `Motion` tokens.
struct SpringParameters: Sendable {
    /// Roughly how long one oscillation takes, in seconds.
    var response: Double
    /// 1 = no overshoot, lower = bouncier.
    var dampingRatio: Double
}

/// A value animated by a damped spring, stepped once per frame. Unlike a fixed-duration
/// animation it keeps its velocity when retargeted, so motion never jerks when the
/// user interrupts it.
struct SpringValue: Sendable {
    var value: Double
    var velocity: Double = 0
    var target: Double

    init(_ value: Double) {
        self.value = value
        self.target = value
    }

    var isSettled: Bool {
        abs(value - target) < 1e-4 && abs(velocity) < 1e-3
    }

    mutating func snap() {
        value = target
        velocity = 0
    }

    mutating func step(_ deltaTime: Double, _ parameters: SpringParameters) {
        let stiffness = pow(2 * .pi / parameters.response, 2)
        let damping = 4 * .pi * parameters.dampingRatio / parameters.response
        // Small fixed substeps keep stiff springs stable through dropped frames.
        var remaining = deltaTime
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240)
            velocity += (-stiffness * (value - target) - damping * velocity) * h
            value += velocity * h
            remaining -= h
        }
        if isSettled { snap() }
    }
}
