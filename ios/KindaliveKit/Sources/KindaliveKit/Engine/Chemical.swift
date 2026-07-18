// Chemical — the 8 neurochemicals in the simulation.
//
// Ports kindalive/engine/chemicals.py (Chemical + SPECIES_DEFAULTS).
// Raw values are the lowercase strings used in LLM-facing interfaces
// and JSON serialization, matching the Python enum values.

import Foundation

public enum Chemical: String, CaseIterable, Codable, Hashable, Sendable {
    case dopamine
    case serotonin
    case oxytocin
    case testosterone
    case cortisol
    case adrenaline
    case endorphins
    case gaba

    /// Case-insensitive lookup by name, mirroring `Chemical.from_string`.
    public static func from(string name: String) -> Chemical? {
        Chemical(rawValue: name.lowercased())
    }
}

/// Species-default baseline and half-life (seconds) for one chemical.
public struct ChemicalDefaults: Sendable {
    public let baseline: Double
    public let halfLife: Double
}

/// The "generic robot" values — mirrors SPECIES_DEFAULTS in chemicals.py.
public let speciesDefaults: [Chemical: ChemicalDefaults] = [
    .dopamine:     ChemicalDefaults(baseline: 0.3, halfLife: 1200.0),   // 20 min
    .serotonin:    ChemicalDefaults(baseline: 0.5, halfLife: 14400.0),  // 4 hrs
    .oxytocin:     ChemicalDefaults(baseline: 0.2, halfLife: 1800.0),   // 30 min
    .testosterone: ChemicalDefaults(baseline: 0.3, halfLife: 7200.0),   // 2 hrs
    .cortisol:     ChemicalDefaults(baseline: 0.2, halfLife: 3600.0),   // 1 hr
    .adrenaline:   ChemicalDefaults(baseline: 0.1, halfLife: 180.0),    // 3 min
    .endorphins:   ChemicalDefaults(baseline: 0.2, halfLife: 1800.0),   // 30 min
    .gaba:         ChemicalDefaults(baseline: 0.4, halfLife: 3600.0),   // 1 hr
]
