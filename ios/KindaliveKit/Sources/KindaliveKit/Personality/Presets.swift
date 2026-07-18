// Personality presets — named bundles of SeedChemistry + affinity defaults.
// Ports kindalive/personality/presets.py.

import Foundation

public struct PersonalityPreset: Sendable {
    public let baselines: [Chemical: Double]
    public let halfLifeMultipliers: [Chemical: Double]
    public let interactionScale: Double
    public let defaultAffinity: Double
}

/// Preset names in menu order.
public let personalityNames = ["default", "cheerful", "stoic", "anxious"]

public let personalityPresets: [String: PersonalityPreset] = [
    "default": PersonalityPreset(
        baselines: [:],
        halfLifeMultipliers: [:],
        interactionScale: 1.0,
        defaultAffinity: 1.0
    ),
    "cheerful": PersonalityPreset(
        baselines: [.serotonin: 0.6, .dopamine: 0.4, .endorphins: 0.3, .gaba: 0.45],
        halfLifeMultipliers: [:],
        interactionScale: 1.0,
        defaultAffinity: 1.2
    ),
    "stoic": PersonalityPreset(
        baselines: [.gaba: 0.6, .serotonin: 0.5, .adrenaline: 0.08, .cortisol: 0.15],
        halfLifeMultipliers: [.adrenaline: 0.7, .cortisol: 0.8],
        interactionScale: 0.7,
        defaultAffinity: 0.6
    ),
    "anxious": PersonalityPreset(
        baselines: [.cortisol: 0.35, .gaba: 0.25, .adrenaline: 0.15, .serotonin: 0.4],
        halfLifeMultipliers: [.cortisol: 1.5, .gaba: 1.3],
        interactionScale: 1.3,
        defaultAffinity: 1.5
    ),
]

/// Build a SeedChemistry from a named preset. Mirrors Python `get_seed`:
/// starts from species defaults, applies the preset's overrides.
public func getSeed(_ personality: String) throws -> SeedChemistry {
    guard let preset = personalityPresets[personality] else {
        throw KindaliveError.unknownPersonality(personality)
    }
    var seed = SeedChemistry.fromSpeciesDefaults()
    for (chem, value) in preset.baselines {
        seed.baselines[chem] = value
    }
    seed.halfLifeMultipliers = preset.halfLifeMultipliers
    seed.interactionScale = preset.interactionScale
    return seed
}

/// Default affinity multiplier for a personality (unknown → default's).
public func getDefaultAffinity(_ personality: String) -> Double {
    (personalityPresets[personality] ?? personalityPresets["default"]!).defaultAffinity
}

public enum KindaliveError: Error, CustomStringConvertible {
    case unknownPersonality(String)
    case unknownStateVersion(Int)
    case validation(String)

    public var description: String {
        switch self {
        case .unknownPersonality(let name):
            return "Unknown personality: \(name). Available: \(personalityNames)"
        case .unknownStateVersion(let version):
            return "Unknown state version: \(version)"
        case .validation(let message):
            return "Validation error: \(message)"
        }
    }
}
