// Robot — top-level integration class. Ports kindalive/robot.py.
//
// Wires together the neurochemical engine, emotion/face projections,
// personality, and the interpreter pipeline. External code should use
// this class, not NeurochemicalEngine directly.

import Foundation

/// How many chat messages of history to keep (each exchange is 2: the
/// owner's line + the robot's reply). Kept even so the trimmed history
/// always starts on a user turn.
public let maxConversationMessages = 40

/// Max per-chemical offset from baseline applied to a fresh robot
/// (mirrors RESET_JITTER in the web UI).
public let resetJitter = 0.22

public struct ConversationMessage: Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public final class Robot {
    public let personality: String
    public let affinity: Double

    let engine: NeurochemicalEngine
    private let interpreter: ImpulseInterpreter?

    public private(set) var lastImpulses: [ChemicalImpulse] = []
    public private(set) var lastReply = ""
    public private(set) var lastPath: InterpreterPath?
    public private(set) var lastError = ""
    private var conversationStorage: [ConversationMessage] = []

    public init(
        personality: String = "default",
        seed: SeedChemistry? = nil,
        clock: Clock? = nil,
        interpreter: ImpulseInterpreter? = nil
    ) throws {
        self.personality = personality
        let effectiveSeed = try seed ?? getSeed(personality)
        self.engine = NeurochemicalEngine(clock: clock ?? ManualClock(), seed: effectiveSeed)
        self.affinity = getDefaultAffinity(personality)
        self.interpreter = interpreter
    }

    // MARK: - Input pipeline

    /// Inject impulses directly into the engine (bypasses the interpreter).
    public func receiveImpulses(_ impulses: [ChemicalImpulse]) {
        lastImpulses = impulses
        engine.applyImpulses(impulses)
    }

    /// Full pipeline: paragraph → interpreter → impulses → engine.
    /// Returns the impulses that were applied.
    @discardableResult
    public func process(text: String) async -> [ChemicalImpulse] {
        let event = UserText(summary: text)
        let context = buildContext()
        let result: InterpreterResult
        if let interpreter {
            result = await interpreter.interpret(event, context: context)
        } else {
            result = await FallbackInterpreter().interpret(event, context: context)
        }

        lastImpulses = result.impulses
        lastReply = result.path == .llm ? result.reply : ""
        lastPath = result.path
        lastError = result.errorMessage
        engine.applyImpulses(result.impulses)

        // Remember the exchange only when the model actually answered,
        // so a fallback/outage doesn't poison the thread.
        if result.path == .llm {
            rememberTurn(userText: text, reply: result.reply)
        }
        return result.impulses
    }

    // MARK: - Conversation memory

    /// Append one exchange. The assistant turn is stored as a compact
    /// JSON object matching the Python format, so persisted transcripts
    /// stay comparable across implementations.
    private func rememberTurn(userText: String, reply: String) {
        conversationStorage.append(ConversationMessage(role: .user, content: userText))
        let impulseParts = lastImpulses.map {
            "{\"chemical\": \"\($0.chemical.rawValue)\", \"delta\": \(($0.delta * 1000).rounded(.toNearestOrEven) / 1000)}"
        }
        let assistant = "{\"reply\": \(jsonString(reply)), \"impulses\": [\(impulseParts.joined(separator: ", "))]}"
        conversationStorage.append(ConversationMessage(role: .assistant, content: assistant))
        if conversationStorage.count > maxConversationMessages {
            conversationStorage.removeFirst(conversationStorage.count - maxConversationMessages)
        }
    }

    private func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        guard let data, let wrapped = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(wrapped.dropFirst().dropLast())  // strip the [ ]
    }

    /// The session conversation history (oldest first).
    public var conversation: [ConversationMessage] {
        conversationStorage
    }

    /// Forget the discussion thread (keeps chemical state).
    public func resetConversation() {
        conversationStorage = []
    }

    /// The most recent exchanges as (userText, reply) pairs, for seeding
    /// a fresh model session with a recap.
    public func recentExchanges(_ n: Int) -> [(userText: String, reply: String)] {
        var exchanges: [(String, String)] = []
        var index = 0
        while index + 1 < conversationStorage.count {
            let user = conversationStorage[index]
            let assistant = conversationStorage[index + 1]
            if user.role == .user, assistant.role == .assistant {
                let reply = (try? JSONSerialization.jsonObject(
                    with: Data(assistant.content.utf8)
                ) as? [String: Any])?["reply"] as? String ?? ""
                exchanges.append((user.content, reply))
            }
            index += 2
        }
        return Array(exchanges.suffix(n))
    }

    // MARK: - State access

    public func currentEmotions() -> EmotionVector {
        EmotionProjection.compute(engine.state)
    }

    public func currentChemicals() -> ChemicalState {
        engine.state
    }

    public func currentFace() -> FaceState {
        FaceProjection.compute(engine.state)
    }

    public func currentVoiceParams() -> VoiceParams {
        VoiceParams(emotions: currentEmotions())
    }

    /// Build a context snapshot for the interpreter.
    public func buildContext() -> RobotContext {
        RobotContext.build(
            personality: personality,
            affinity: affinity,
            emotions: currentEmotions(),
            chemicals: engine.state
        )
    }

    // MARK: - Simulation

    /// Advance the simulation by dt seconds. Also advances the clock so
    /// time-dependent features (saturation windows, sustained impulses)
    /// work correctly.
    public func advance(dt: Double) {
        if let manual = engine.clock as? ManualClock {
            manual.advance(seconds: dt)
        }
        engine.advance(dt: dt)
    }

    /// Nudge each chemical a little off its baseline for a fresh start
    /// (ports _jostle_chemistry in the web UI).
    public func jostle<G: RandomNumberGenerator>(
        jitter: Double = resetJitter,
        using generator: inout G
    ) {
        let state = engine.state
        for chem in Chemical.allCases {
            let base = state.baseline(chem)
            let offset = Double.random(in: -jitter...jitter, using: &generator)
            state.set(chem, max(0.0, min(1.0, base + offset)))
        }
    }

    public func jostle(jitter: Double = resetJitter) {
        var generator = SystemRandomNumberGenerator()
        jostle(jitter: jitter, using: &generator)
    }

    // MARK: - Persistence

    public func snapshot() -> EngineSnapshot {
        StateStore.serialize(engine)
    }

    public func restore(_ snapshot: EngineSnapshot) throws {
        try StateStore.restore(snapshot, into: engine)
    }
}
