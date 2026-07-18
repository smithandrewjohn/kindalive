// ChemicalImpulse — the unit of change applied to the engine.
// Ports kindalive/engine/impulse.py.

import Foundation

public struct ChemicalImpulse: Sendable, Equatable {
    /// Which chemical to move.
    public let chemical: Chemical
    /// Signed magnitude in [-0.5, +0.5].
    public let delta: Double
    /// 0 = instant spike, >0 = sustained drip over this many seconds.
    public let durationSeconds: Double
    /// For saturation tracking. Impulses with an empty sourceId are
    /// never dampened.
    public let sourceId: String
    /// Human-readable label.
    public let sourceLabel: String

    public init(
        chemical: Chemical,
        delta: Double,
        durationSeconds: Double = 0.0,
        sourceId: String = "",
        sourceLabel: String = ""
    ) {
        self.chemical = chemical
        self.delta = delta
        self.durationSeconds = durationSeconds
        self.sourceId = sourceId
        self.sourceLabel = sourceLabel
    }
}

/// Tracks a sustained impulse that is currently dripping.
public struct ActiveSustainedImpulse: Sendable {
    public let impulse: ChemicalImpulse
    public var remainingSeconds: Double
    public let ratePerSecond: Double

    public init(impulse: ChemicalImpulse, remainingSeconds: Double, ratePerSecond: Double) {
        self.impulse = impulse
        self.remainingSeconds = remainingSeconds
        self.ratePerSecond = ratePerSecond
    }

    public static func from(impulse: ChemicalImpulse) -> ActiveSustainedImpulse {
        ActiveSustainedImpulse(
            impulse: impulse,
            remainingSeconds: impulse.durationSeconds,
            ratePerSecond: impulse.delta / impulse.durationSeconds
        )
    }
}
