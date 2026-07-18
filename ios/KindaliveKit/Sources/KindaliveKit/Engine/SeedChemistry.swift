// SeedChemistry — configurable baseline neurochemistry for a robot.
// Ports kindalive/engine/seed_chemistry.py.
//
// Three-layer model: Species Defaults → Seed Chemistry → Runtime Drift.

import Foundation

public struct SeedChemistry: Sendable {
    public var baselines: [Chemical: Double]
    public var halfLifeMultipliers: [Chemical: Double]
    public var interactionScale: Double

    public init(
        baselines: [Chemical: Double] = [:],
        halfLifeMultipliers: [Chemical: Double] = [:],
        interactionScale: Double = 1.0
    ) {
        self.baselines = baselines
        self.halfLifeMultipliers = halfLifeMultipliers
        self.interactionScale = interactionScale
    }

    /// All 8 chemicals at species default baselines.
    public static func fromSpeciesDefaults() -> SeedChemistry {
        SeedChemistry(
            baselines: Dictionary(
                uniqueKeysWithValues: Chemical.allCases.map { ($0, speciesDefaults[$0]!.baseline) }
            )
        )
    }

    /// The half-life for a chemical, applying any multiplier.
    public func effectiveHalfLife(_ chem: Chemical) -> Double {
        speciesDefaults[chem]!.halfLife * (halfLifeMultipliers[chem] ?? 1.0)
    }
}
