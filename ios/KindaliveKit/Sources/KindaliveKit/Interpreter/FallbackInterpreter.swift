// FallbackInterpreter — the offline path when no language model is
// available. Ports kindalive/interpreter/fallback_rules.py.
//
// It does not interpret the paragraph — it just nudges cortisol up a
// little so the robot flinches rather than goes numb.

import Foundation

/// The single fallback impulse: a small cortisol nudge.
public let fallbackImpulses = [
    ChemicalImpulse(
        chemical: .cortisol,
        delta: 0.05,
        sourceId: "fallback:freeform",
        sourceLabel: "LLM unavailable — generic stress nudge"
    ),
]

public struct FallbackInterpreter: ImpulseInterpreter {
    /// Why the model is unavailable, surfaced in the status line.
    public let reason: String

    public init(reason: String = "no language model") {
        self.reason = reason
    }

    public func interpret(_ event: UserText, context: RobotContext) async -> InterpreterResult {
        InterpreterResult(
            reply: "",
            impulses: fallbackImpulses,
            path: .fallback,
            errorMessage: reason
        )
    }
}
