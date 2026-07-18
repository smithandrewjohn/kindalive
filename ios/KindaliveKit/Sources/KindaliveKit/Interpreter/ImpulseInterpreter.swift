// ImpulseInterpreter — the protocol every interpreter backend implements,
// plus the result telemetry the UI surfaces.
//
// Mirrors the Python LLMInterpreter's last_path/last_error/last_reply
// telemetry as a value type. Deliberate deviation from Python: there is
// no "cache" path — the on-device model has no per-call cost, so the
// impulse cache was dropped (Python bypasses it mid-conversation anyway).

import Foundation

public enum InterpreterPath: String, Sendable {
    case llm
    case fallback
}

public struct InterpreterResult: Sendable {
    /// The robot's spoken line ("" = silent).
    public let reply: String
    /// Validated impulses ready to apply to the engine.
    public let impulses: [ChemicalImpulse]
    /// Which path produced this result.
    public let path: InterpreterPath
    /// Human-readable error when path == .fallback ("" otherwise).
    public let errorMessage: String

    public init(
        reply: String,
        impulses: [ChemicalImpulse],
        path: InterpreterPath,
        errorMessage: String = ""
    ) {
        self.reply = reply
        self.impulses = impulses
        self.path = path
        self.errorMessage = errorMessage
    }
}

public protocol ImpulseInterpreter {
    /// Interpret an owner paragraph in the robot's current context.
    /// Implementations must not throw — on any failure they return a
    /// `.fallback` result (see FallbackInterpreter).
    func interpret(_ event: UserText, context: RobotContext) async -> InterpreterResult
}
