// NeurochemicalEngine — core simulation loop.
// Ports kindalive/engine/neurochemical_engine.py.
//
// Manages chemical state, applies impulses (instant + sustained), runs
// decay + interactions with sub-stepping for numerical stability.
// Per-sub-step order is load-bearing:
//   (1) sustained drips → (2) decay → (3) interactions → (4) clamp.

import Foundation

/// Sub-step ceiling for numerical stability.
public let maxSubStep = 0.5  // seconds

/// Saturation sliding window.
public let saturationWindow = 300.0  // 5 minutes
public let saturationDampening = 0.3

public final class NeurochemicalEngine {
    public let state: ChemicalState
    public let seed: SeedChemistry
    public let clock: Clock

    var sustained: [ActiveSustainedImpulse] = []
    private var saturation: [String: [Double]] = [:]

    public init(clock: Clock? = nil, seed: SeedChemistry? = nil) {
        self.clock = clock ?? ManualClock()
        let effectiveSeed = seed ?? SeedChemistry.fromSpeciesDefaults()
        self.seed = effectiveSeed

        let halfLives = Dictionary(
            uniqueKeysWithValues: Chemical.allCases.map {
                ($0, effectiveSeed.effectiveHalfLife($0))
            }
        )
        self.state = ChemicalState(baselines: effectiveSeed.baselines, halfLives: halfLives)
    }

    /// The sustained impulses currently dripping (read-only view).
    public var activeSustainedImpulses: [ActiveSustainedImpulse] {
        sustained
    }

    // MARK: - Impulse application

    public func applyImpulse(_ impulse: ChemicalImpulse) {
        let effectiveDelta = applySaturation(impulse)
        if impulse.durationSeconds > 0 {
            // Create sustained impulse with saturation-adjusted delta.
            let adjusted = ChemicalImpulse(
                chemical: impulse.chemical,
                delta: effectiveDelta,
                durationSeconds: impulse.durationSeconds,
                sourceId: impulse.sourceId,
                sourceLabel: impulse.sourceLabel
            )
            sustained.append(.from(impulse: adjusted))
        } else {
            let level = state.get(impulse.chemical)
            state.set(impulse.chemical, level + effectiveDelta)
        }
    }

    public func applyImpulses(_ impulses: [ChemicalImpulse]) {
        for imp in impulses {
            applyImpulse(imp)
        }
    }

    /// Apply saturation dampening and return the effective delta.
    private func applySaturation(_ impulse: ChemicalImpulse) -> Double {
        guard !impulse.sourceId.isEmpty else {
            return impulse.delta
        }
        let now = clock.now()
        let key = impulse.sourceId

        // Prune old entries outside the sliding window.
        var timestamps = (saturation[key] ?? []).filter { now - $0 < saturationWindow }
        let count = timestamps.count
        let factor = 1.0 / (1.0 + Double(count) * saturationDampening)
        timestamps.append(now)
        saturation[key] = timestamps

        return impulse.delta * factor
    }

    // MARK: - Simulation advancement

    /// Advance the simulation by dt seconds. Internally sub-steps at
    /// `maxSubStep` for stability.
    public func advance(dt: Double) {
        precondition(dt >= 0, "dt must be >= 0, got \(dt)")
        var remaining = dt
        while remaining > 1e-9 {
            let step = min(remaining, maxSubStep)
            subStep(step)
            remaining -= step
        }
    }

    private func subStep(_ dt: Double) {
        // 1. Apply sustained impulse drips. Sustained drips do NOT
        //    re-saturate per tick.
        var stillActive: [ActiveSustainedImpulse] = []
        for var active in sustained {
            let dripDt = min(dt, active.remainingSeconds)
            if dripDt > 0 {
                let dripAmount = active.ratePerSecond * dripDt
                let level = state.get(active.impulse.chemical)
                state.set(active.impulse.chemical, level + dripAmount)
                active.remainingSeconds -= dripDt
                if active.remainingSeconds > 1e-9 {
                    stillActive.append(active)
                }
            }
        }
        sustained = stillActive

        // 2. Decay all chemicals toward baseline.
        state.decayAll(dt: dt)

        // 3. Cross-chemical interactions.
        applyInteractions(state, dt: dt, scale: seed.interactionScale)

        // 4. Clamp everything to [0, 1].
        state.clampAll()
    }
}
