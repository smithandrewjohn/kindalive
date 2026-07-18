// Cross-chemical interaction rules. Ports kindalive/engine/interactions.py.
//
// Equilibrium principle: every interaction term vanishes when the relevant
// chemical is at its baseline, so the all-baseline resting state is a true
// fixed point. All rules read from a snapshot taken before any mutation,
// making them order-independent within a sub-step. Clamping to [0, 1]
// happens AFTER all rules run in a sub-step, not between individual rules.

import Foundation

// Interaction coefficients (per second, before the seed's interactionScale)
let kCortisolSerotonin = 0.03        // excess cortisol erodes serotonin
let kGabaAdrenaline = 0.15           // GABA damps adrenaline's excess
let kTestosteroneAdrenaline = 0.015  // excess testosterone amplifies adrenaline
let kAdrenalineGaba = 0.30           // adrenaline's excess inhibits GABA toward a floor
let kOxytocinCortisol = 0.30         // oxytocin relieves cortisol's excess

// Adrenaline keeps inhibiting GABA only until GABA reaches this fraction of
// its baseline, so a burst of arousal can't fully strip the brake.
let gabaInhibitionFloorFrac = 0.5

// Baseline drift thresholds for cortisol (chronic stress / recovery).
let cortisolDriftUpThreshold = 0.7
let cortisolDriftDownThreshold = 0.15

/// Apply all cross-chemical interaction rules for one sub-step.
public func applyInteractions(_ state: ChemicalState, dt: Double, scale: Double = 1.0) {
    // Snapshot all levels before any mutations.
    let cortisol = state.get(.cortisol)
    let serotonin = state.get(.serotonin)
    let gaba = state.get(.gaba)
    let adrenaline = state.get(.adrenaline)
    let testosterone = state.get(.testosterone)
    let oxytocin = state.get(.oxytocin)

    // Excess of a chemical above its own baseline (0 when at/below rest).
    let cortisolExcess = max(0.0, cortisol - state.baseline(.cortisol))
    let adrenalineExcess = max(0.0, adrenaline - state.baseline(.adrenaline))
    let testosteroneExcess = max(0.0, testosterone - state.baseline(.testosterone))
    let gabaFloor = gabaInhibitionFloorFrac * state.baseline(.gaba)

    // Rule 1: excess cortisol erodes serotonin.
    let dSerotonin = -cortisolExcess * kCortisolSerotonin * scale * dt

    // Rule 2: GABA dampens adrenaline's excess toward baseline.
    // Rule 4: excess testosterone amplifies adrenaline.
    let dAdrenaline = -gaba * kGabaAdrenaline * adrenalineExcess * scale * dt
        + testosteroneExcess * kTestosteroneAdrenaline * scale * dt

    // Rule 3: adrenaline's excess inhibits GABA, but only the portion
    // above the floor.
    let dGaba = -adrenalineExcess * kAdrenalineGaba
        * max(0.0, gaba - gabaFloor) * scale * dt

    // Rule 5: oxytocin relieves cortisol's excess.
    let dCortisol = -oxytocin * kOxytocinCortisol * cortisolExcess * scale * dt

    state.set(.serotonin, serotonin + dSerotonin)
    state.set(.adrenaline, adrenaline + dAdrenaline)
    state.set(.gaba, gaba + dGaba)
    state.set(.cortisol, cortisol + dCortisol)

    // Rule 6: sustained high cortisol raises cortisol baseline (chronic stress).
    if cortisol > cortisolDriftUpThreshold {
        state.setBaseline(.cortisol, state.baseline(.cortisol) + 0.001 * dt)
    }

    // Rule 7: sustained low cortisol lowers cortisol baseline (recovery).
    if cortisol < cortisolDriftDownThreshold {
        state.setBaseline(.cortisol, state.baseline(.cortisol) - 0.0005 * dt)
    }
}
