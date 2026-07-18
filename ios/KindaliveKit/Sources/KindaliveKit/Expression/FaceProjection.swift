// FaceProjection — derive a 12-muscle facial expression from chemical state.
// Ports kindalive/expression/face.py.
//
// A second projection from ChemicalState, parallel to EmotionProjection:
// each muscle is a weighted linear combination of chemicals, clamped to
// [0.0, 1.0]. The weight tables mirror FACE_WEIGHTS in the Python module,
// which stays authoritative.

import Foundation

/// One weighted term contributing to a facial muscle. `inverted` mirrors
/// EmotionTerm semantics — a face only "frowns from sadness" when
/// dopamine/serotonin fall below the robot's resting level.
public struct FaceTerm: Sendable {
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

/// Mirrors FACE_WEIGHTS in kindalive/expression/face.py.
public let faceWeights: [(muscle: String, terms: [FaceTerm])] = [
    ("brow_inner_raise", [
        FaceTerm(.cortisol, 0.40),
        FaceTerm(.dopamine, 0.35, inverted: true),
        FaceTerm(.serotonin, 0.25, inverted: true),
        FaceTerm(.gaba, -0.10),
    ]),
    ("brow_outer_raise", [
        FaceTerm(.adrenaline, 0.50),
        FaceTerm(.dopamine, 0.20),
        FaceTerm(.gaba, -0.10),
    ]),
    ("brow_lower", [
        FaceTerm(.testosterone, 0.35),
        FaceTerm(.cortisol, 0.30),
        FaceTerm(.adrenaline, 0.20),
        FaceTerm(.gaba, -0.20),
        FaceTerm(.serotonin, -0.10),
    ]),
    ("eyelid_upper_raise", [
        FaceTerm(.adrenaline, 0.55),
        FaceTerm(.cortisol, 0.25),
        FaceTerm(.dopamine, 0.15),
        FaceTerm(.gaba, -0.20),
    ]),
    ("eyelid_lower_tighten", [
        FaceTerm(.cortisol, 0.35),
        FaceTerm(.testosterone, 0.25),
        FaceTerm(.adrenaline, 0.20),
        FaceTerm(.gaba, -0.15),
    ]),
    ("cheek_raise", [
        FaceTerm(.dopamine, 0.45),
        FaceTerm(.endorphins, 0.30),
        FaceTerm(.oxytocin, 0.20),
        FaceTerm(.cortisol, -0.20),
    ]),
    ("nose_wrinkle", [
        FaceTerm(.testosterone, 0.30),
        FaceTerm(.cortisol, 0.30),
        FaceTerm(.adrenaline, 0.15),
        FaceTerm(.gaba, -0.20),
    ]),
    ("lip_corner_pull", [
        FaceTerm(.dopamine, 0.40),
        FaceTerm(.endorphins, 0.30),
        FaceTerm(.serotonin, 0.20),
        FaceTerm(.oxytocin, 0.15),
        FaceTerm(.cortisol, -0.25),
    ]),
    ("lip_corner_depress", [
        FaceTerm(.cortisol, 0.45),
        FaceTerm(.dopamine, 0.35, inverted: true),
        FaceTerm(.serotonin, 0.25, inverted: true),
        FaceTerm(.endorphins, -0.15),
    ]),
    ("jaw_open", [
        FaceTerm(.adrenaline, 0.40),
        FaceTerm(.dopamine, 0.25),
        FaceTerm(.endorphins, 0.15),
        FaceTerm(.gaba, -0.15),
        FaceTerm(.cortisol, -0.10),
    ]),
    ("lip_pucker", [
        FaceTerm(.oxytocin, 0.50),
        FaceTerm(.endorphins, 0.20),
        FaceTerm(.cortisol, -0.10),
    ]),
    ("lip_press", [
        FaceTerm(.testosterone, 0.35),
        FaceTerm(.cortisol, 0.25),
        FaceTerm(.gaba, 0.15),
        FaceTerm(.endorphins, -0.10),
    ]),
]

private func clamp01(_ value: Double) -> Double {
    max(0.0, min(1.0, value))
}

/// Stateless projection from ChemicalState to FaceState.
public enum FaceProjection {
    public static func compute(_ state: ChemicalState) -> FaceState {
        var values: [String: Double] = [:]
        for (muscle, terms) in faceWeights {
            let raw = terms.reduce(0.0) { $0 + $1.evaluate(state) }
            values[muscle] = clamp01(raw)
        }
        return FaceState(
            browInnerRaise: values["brow_inner_raise"]!,
            browOuterRaise: values["brow_outer_raise"]!,
            browLower: values["brow_lower"]!,
            eyelidUpperRaise: values["eyelid_upper_raise"]!,
            eyelidLowerTighten: values["eyelid_lower_tighten"]!,
            cheekRaise: values["cheek_raise"]!,
            noseWrinkle: values["nose_wrinkle"]!,
            lipCornerPull: values["lip_corner_pull"]!,
            lipCornerDepress: values["lip_corner_depress"]!,
            jawOpen: values["jaw_open"]!,
            lipPucker: values["lip_pucker"]!,
            lipPress: values["lip_press"]!
        )
    }
}

/// Convenience function — `FaceProjection.compute(state)`.
public func projectFace(_ state: ChemicalState) -> FaceState {
    FaceProjection.compute(state)
}
