// ChemicalState — mutable vector of 8 chemical concentrations with
// baselines and half-lives. Ports kindalive/engine/chemicals.py.
//
// All concentrations are clamped to [0.0, 1.0]; baselines to [0.1, 0.5].
// The decay formula is a TRUE half-life:
//     level += (baseline - level) * (1 - 2^(-dt / half_life))

import Foundation

public final class ChemicalState {
    private var levels: [Chemical: Double] = [:]
    private var baselines: [Chemical: Double] = [:]
    private var halfLives: [Chemical: Double] = [:]

    public init(
        baselines: [Chemical: Double]? = nil,
        halfLives: [Chemical: Double]? = nil
    ) {
        for chem in Chemical.allCases {
            let defaults = speciesDefaults[chem]!
            let bl = baselines?[chem] ?? defaults.baseline
            let hl = halfLives?[chem] ?? defaults.halfLife
            self.baselines[chem] = bl
            self.halfLives[chem] = hl
            self.levels[chem] = bl  // start at baseline
        }
    }

    public func get(_ chem: Chemical) -> Double {
        levels[chem]!
    }

    public func set(_ chem: Chemical, _ value: Double) {
        levels[chem] = max(0.0, min(1.0, value))
    }

    public func baseline(_ chem: Chemical) -> Double {
        baselines[chem]!
    }

    public func setBaseline(_ chem: Chemical, _ value: Double) {
        baselines[chem] = max(0.1, min(0.5, value))
    }

    public func halfLife(_ chem: Chemical) -> Double {
        halfLives[chem]!
    }

    /// Clamp all levels to [0.0, 1.0].
    public func clampAll() {
        for chem in Chemical.allCases {
            levels[chem] = max(0.0, min(1.0, levels[chem]!))
        }
    }

    /// Decay a single chemical toward its baseline using true half-life.
    public func applyDecay(_ chem: Chemical, dt: Double) {
        let hl = halfLives[chem]!
        let level = levels[chem]!
        let bl = baselines[chem]!
        let factor = 1.0 - pow(2.0, -dt / hl)
        levels[chem] = level + (bl - level) * factor
    }

    /// Apply decay to all chemicals.
    public func decayAll(dt: Double) {
        for chem in Chemical.allCases {
            applyDecay(chem, dt: dt)
        }
    }

    /// Levels as {lowercase_name: value}, matching Python `as_dict`.
    public func asDict() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: Chemical.allCases.map { ($0.rawValue, levels[$0]!) })
    }

    public func baselinesAsDict() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: Chemical.allCases.map { ($0.rawValue, baselines[$0]!) })
    }

    public func copy() -> ChemicalState {
        let state = ChemicalState()
        state.levels = levels
        state.baselines = baselines
        state.halfLives = halfLives
        return state
    }
}
