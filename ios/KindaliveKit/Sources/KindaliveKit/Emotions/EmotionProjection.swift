// EmotionProjection — derive emotions from chemical state.
// Ports kindalive/emotions/projection.py.
//
// Emotions are computed, never stored. Each is a weighted linear
// combination of chemical levels, clamped to [0.0, 1.0]. The weight
// tables here mirror EMOTION_WEIGHTS in the Python module, which stays
// authoritative (same convention as the TOML config mirrors).

import Foundation

/// One weighted term in an emotion's linear combination.
///
/// If `inverted` is true, the term contributes the *deficit* relative to
/// the chemical's baseline: `max(0, baseline - level)`. Used for sadness,
/// which activates on the absence of positive chemicals — only when they
/// fall BELOW the robot's resting level, not whenever they are under 1.0.
public struct EmotionTerm: Sendable {
    public let chemical: Chemical
    public let weight: Double
    public let inverted: Bool

    public init(_ chemical: Chemical, _ weight: Double, inverted: Bool = false) {
        self.chemical = chemical
        self.weight = weight
        self.inverted = inverted
    }

    public func evaluate(_ state: ChemicalState) -> Double {
        let level = state.get(chemical)
        if inverted {
            let deficit = max(0.0, state.baseline(chemical) - level)
            return weight * deficit
        }
        return weight * level
    }
}

/// Mirrors EMOTION_WEIGHTS in kindalive/emotions/projection.py.
public let emotionWeights: [(emotion: String, terms: [EmotionTerm])] = [
    ("happiness", [
        EmotionTerm(.dopamine, 0.35),
        EmotionTerm(.serotonin, 0.35),
        EmotionTerm(.endorphins, 0.15),
        EmotionTerm(.oxytocin, 0.15),
        EmotionTerm(.cortisol, -0.20),
    ]),
    ("excitement", [
        EmotionTerm(.adrenaline, 0.45),
        EmotionTerm(.dopamine, 0.35),
        EmotionTerm(.testosterone, 0.20),
    ]),
    ("anger", [
        EmotionTerm(.testosterone, 0.35),
        EmotionTerm(.cortisol, 0.35),
        EmotionTerm(.adrenaline, 0.30),
        EmotionTerm(.gaba, -0.30),
    ]),
    ("calm", [
        EmotionTerm(.gaba, 0.45),
        EmotionTerm(.serotonin, 0.35),
        EmotionTerm(.oxytocin, 0.20),
        EmotionTerm(.adrenaline, -0.25),
        EmotionTerm(.cortisol, -0.15),
    ]),
    ("bonding", [
        EmotionTerm(.oxytocin, 0.50),
        EmotionTerm(.serotonin, 0.30),
        EmotionTerm(.endorphins, 0.20),
    ]),
    ("anxiety", [
        EmotionTerm(.cortisol, 0.40),
        EmotionTerm(.adrenaline, 0.35),
        EmotionTerm(.testosterone, 0.25),
        EmotionTerm(.gaba, -0.35),
        EmotionTerm(.serotonin, -0.15),
    ]),
    ("sadness", [
        EmotionTerm(.cortisol, 0.60),
        EmotionTerm(.dopamine, 0.50, inverted: true),
        EmotionTerm(.serotonin, 0.40, inverted: true),
        EmotionTerm(.oxytocin, 0.40, inverted: true),
    ]),
    ("euphoria", [
        EmotionTerm(.dopamine, 0.30),
        EmotionTerm(.endorphins, 0.30),
        EmotionTerm(.adrenaline, 0.20),
        EmotionTerm(.oxytocin, 0.20),
    ]),
]

private func clamp01(_ value: Double) -> Double {
    max(0.0, min(1.0, value))
}

/// Stateless projection from ChemicalState to EmotionVector.
public enum EmotionProjection {
    public static func compute(_ state: ChemicalState) -> EmotionVector {
        var values: [String: Double] = [:]
        for (emotion, terms) in emotionWeights {
            let raw = terms.reduce(0.0) { $0 + $1.evaluate(state) }
            values[emotion] = clamp01(raw)
        }
        return EmotionVector(
            happiness: values["happiness"]!,
            excitement: values["excitement"]!,
            anger: values["anger"]!,
            calm: values["calm"]!,
            bonding: values["bonding"]!,
            anxiety: values["anxiety"]!,
            sadness: values["sadness"]!,
            euphoria: values["euphoria"]!
        )
    }
}
