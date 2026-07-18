// Generable types for the on-device interpreter.
//
// Guided generation replaces the entire JSON-repair layer of the Python
// interpreter (_extract_json_payload / _sanitize_json_quirks): the model
// emits these typed values directly, with chemical names constrained to
// the enum and delta/duration constrained to their valid ranges by the
// framework itself.

import Foundation
import FoundationModels

@Generable
enum GeneratedChemical: String, CaseIterable {
    case dopamine, serotonin, oxytocin, testosterone
    case cortisol, adrenaline, endorphins, gaba
}

@Generable
struct GeneratedImpulse {
    @Guide(description: "Which neurochemical to move")
    var chemical: GeneratedChemical

    @Guide(
        description: "Signed intensity: 0.05 barely noticeable, 0.20 clearly felt, 0.35 strong, 0.50 life-changing; negative for losses/depletion",
        .range(-0.5...0.5)
    )
    var delta: Double

    @Guide(
        description: "0 for discrete events (the default); greater than 0 only for ambient conditions like steady rain (300) or a sunny afternoon (180)",
        .range(0.0...300.0)
    )
    var durationSeconds: Double
}

@Generable
struct RobotTurn {
    @Guide(description: "One short spoken sentence, about 3-14 plain words, colored by the robot's current mood; empty string if there is genuinely nothing to say")
    var reply: String

    @Guide(description: "0 to 8 impulses — ONE consolidated set for the whole paragraph, 2-4 chemicals for most events", .maximumCount(8))
    var impulses: [GeneratedImpulse]
}
