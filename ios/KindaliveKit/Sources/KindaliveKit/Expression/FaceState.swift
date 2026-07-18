// FaceState — a 12-parameter snapshot of facial muscle activations.
// Ports the FaceState dataclass in kindalive/expression/face.py.
//
// Parameter names are derived from FACS Action Units so the same vector
// can drive the LED face, a physical robot face, or a blendshape model.

import Foundation

public struct FaceState: Sendable, Equatable {
    public let browInnerRaise: Double      // AU1  — sadness, concern
    public let browOuterRaise: Double      // AU2  — surprise, fear
    public let browLower: Double           // AU4  — anger, focus
    public let eyelidUpperRaise: Double    // AU5  — alertness, surprise
    public let eyelidLowerTighten: Double  // AU7  — anger, anxiety
    public let cheekRaise: Double          // AU6  — Duchenne joy
    public let noseWrinkle: Double         // AU9  — disgust, anger
    public let lipCornerPull: Double       // AU12 — smile
    public let lipCornerDepress: Double    // AU15 — frown
    public let jawOpen: Double             // AU26 — surprise, laughter
    public let lipPucker: Double           // AU18 — affection, concern
    public let lipPress: Double            // AU24 — restraint, anger

    /// snake_case muscle names in declaration order — the wire format
    /// shared with the Python FaceState and the JS renderer.
    public static let muscleNames = [
        "brow_inner_raise", "brow_outer_raise", "brow_lower",
        "eyelid_upper_raise", "eyelid_lower_tighten", "cheek_raise",
        "nose_wrinkle", "lip_corner_pull", "lip_corner_depress",
        "jaw_open", "lip_pucker", "lip_press",
    ]

    public init(
        browInnerRaise: Double, browOuterRaise: Double, browLower: Double,
        eyelidUpperRaise: Double, eyelidLowerTighten: Double, cheekRaise: Double,
        noseWrinkle: Double, lipCornerPull: Double, lipCornerDepress: Double,
        jawOpen: Double, lipPucker: Double, lipPress: Double
    ) {
        self.browInnerRaise = browInnerRaise
        self.browOuterRaise = browOuterRaise
        self.browLower = browLower
        self.eyelidUpperRaise = eyelidUpperRaise
        self.eyelidLowerTighten = eyelidLowerTighten
        self.cheekRaise = cheekRaise
        self.noseWrinkle = noseWrinkle
        self.lipCornerPull = lipCornerPull
        self.lipCornerDepress = lipCornerDepress
        self.jawOpen = jawOpen
        self.lipPucker = lipPucker
        self.lipPress = lipPress
    }

    /// Ordered (snake_case name, value) pairs matching Python `as_dict`.
    public var orderedValues: [(name: String, value: Double)] {
        [
            ("brow_inner_raise", browInnerRaise),
            ("brow_outer_raise", browOuterRaise),
            ("brow_lower", browLower),
            ("eyelid_upper_raise", eyelidUpperRaise),
            ("eyelid_lower_tighten", eyelidLowerTighten),
            ("cheek_raise", cheekRaise),
            ("nose_wrinkle", noseWrinkle),
            ("lip_corner_pull", lipCornerPull),
            ("lip_corner_depress", lipCornerDepress),
            ("jaw_open", jawOpen),
            ("lip_pucker", lipPucker),
            ("lip_press", lipPress),
        ]
    }

    public func asDict() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: orderedValues.map { ($0.name, $0.value) })
    }

    /// Top-n most-activated muscles, sorted descending; ties keep
    /// declaration order (Python `sorted` is stable).
    public func topN(_ n: Int = 3) -> [(name: String, value: Double)] {
        let sorted = orderedValues.enumerated().sorted {
            $0.element.value != $1.element.value
                ? $0.element.value > $1.element.value
                : $0.offset < $1.offset
        }
        return sorted.prefix(n).map { $0.element }
    }
}
