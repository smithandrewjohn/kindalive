// Robot integration tests with a mock interpreter, mirroring
// tests/test_integration.py and test_interpreter/test_full_pipeline.py.

import Foundation
import XCTest
@testable import KindaliveKit

/// Scripted interpreter for tests — returns queued results in order.
final class MockInterpreter: ImpulseInterpreter {
    var results: [InterpreterResult]
    private(set) var receivedEvents: [UserText] = []
    private(set) var receivedContexts: [RobotContext] = []

    init(results: [InterpreterResult]) {
        self.results = results
    }

    func interpret(_ event: UserText, context: RobotContext) async -> InterpreterResult {
        receivedEvents.append(event)
        receivedContexts.append(context)
        return results.isEmpty ? InterpreterResult(
            reply: "", impulses: [], path: .llm
        ) : results.removeFirst()
    }
}

final class RobotTests: XCTestCase {
    func testTextToFacePayloadChain() async throws {
        // Mirrors test_text_to_face_payload_chain: text → interpreter →
        // impulses → ChemicalState → EmotionVector + FaceState.
        let mock = MockInterpreter(results: [
            InterpreterResult(
                reply: "Oh wow, that's huge!",
                impulses: [
                    ChemicalImpulse(chemical: .dopamine, delta: 0.5, sourceId: "t:win"),
                    ChemicalImpulse(chemical: .adrenaline, delta: 0.4, sourceId: "t:win"),
                ],
                path: .llm
            ),
        ])
        let robot = try Robot(personality: "default", clock: ManualClock(), interpreter: mock)
        let impulses = await robot.process(text: "I won the lottery")

        XCTAssertEqual(impulses.count, 2)
        XCTAssertEqual(robot.lastReply, "Oh wow, that's huge!")
        XCTAssertEqual(robot.lastPath, .llm)
        XCTAssertGreaterThan(robot.currentChemicals().get(.dopamine), 0.7)

        let emotions = robot.currentEmotions()
        XCTAssertGreaterThan(emotions.excitement, emotions.sadness)

        let face = robot.currentFace()
        XCTAssertGreaterThan(face.lipCornerPull, face.lipCornerDepress)
        XCTAssertGreaterThan(face.eyelidUpperRaise, 0.2)

        // The interpreter saw the robot's mood context.
        XCTAssertEqual(mock.receivedContexts.first?.personalityName, "default")
        XCTAssertFalse(mock.receivedContexts.first?.chemicalSummary.isEmpty ?? true)
    }

    func testLlmTurnsAreRememberedFallbackTurnsAreNot() async throws {
        let mock = MockInterpreter(results: [
            InterpreterResult(
                reply: "Nice.",
                impulses: [ChemicalImpulse(chemical: .dopamine, delta: 0.2)],
                path: .llm
            ),
            InterpreterResult(
                reply: "",
                impulses: fallbackImpulses,
                path: .fallback,
                errorMessage: "model down"
            ),
        ])
        let robot = try Robot(clock: ManualClock(), interpreter: mock)

        await robot.process(text: "good day")
        XCTAssertEqual(robot.conversation.count, 2)
        XCTAssertEqual(robot.conversation[0].role, .user)
        XCTAssertEqual(robot.conversation[0].content, "good day")
        XCTAssertTrue(robot.conversation[1].content.contains("\"reply\": \"Nice.\""))

        await robot.process(text: "still there?")
        XCTAssertEqual(robot.conversation.count, 2)  // fallback not remembered
        XCTAssertEqual(robot.lastPath, .fallback)
        XCTAssertEqual(robot.lastReply, "")
        XCTAssertEqual(robot.lastError, "model down")

        let exchanges = robot.recentExchanges(3)
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0].userText, "good day")
        XCTAssertEqual(exchanges[0].reply, "Nice.")
    }

    func testConversationBoundedToMaxMessages() async throws {
        let turns = 30
        let mock = MockInterpreter(results: (0..<turns).map { i in
            InterpreterResult(reply: "r\(i)", impulses: [], path: .llm)
        })
        let robot = try Robot(clock: ManualClock(), interpreter: mock)
        for i in 0..<turns {
            await robot.process(text: "turn \(i)")
        }
        XCTAssertEqual(robot.conversation.count, maxConversationMessages)
        // Trimmed history starts on a user turn.
        XCTAssertEqual(robot.conversation.first?.role, .user)
        XCTAssertEqual(robot.conversation.first?.content, "turn \(turns - maxConversationMessages / 2)")
    }

    func testNoInterpreterUsesFallback() async throws {
        let robot = try Robot(clock: ManualClock())
        let before = robot.currentChemicals().get(.cortisol)
        await robot.process(text: "anything")
        XCTAssertEqual(robot.lastPath, .fallback)
        XCTAssertEqual(robot.currentChemicals().get(.cortisol), before + 0.05, accuracy: 1e-9)
        XCTAssertTrue(robot.conversation.isEmpty)
    }

    func testAdvanceDecaysTowardBaseline() async throws {
        let robot = try Robot(clock: ManualClock())
        robot.receiveImpulses([ChemicalImpulse(chemical: .adrenaline, delta: 0.5)])
        let spiked = robot.currentChemicals().get(.adrenaline)
        robot.advance(dt: 600)
        XCTAssertLessThan(robot.currentChemicals().get(.adrenaline), spiked)
    }

    func testJostleStaysPlausibleAndDeterministicWithSeededRng() throws {
        // A tiny deterministic RNG so the test is reproducible.
        struct Xorshift: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                return state
            }
        }
        let robot = try Robot(clock: ManualClock())
        var rng = Xorshift(state: 0x9E3779B97F4A7C15)
        robot.jostle(using: &rng)
        for chem in Chemical.allCases {
            let level = robot.currentChemicals().get(chem)
            let base = robot.currentChemicals().baseline(chem)
            XCTAssertGreaterThanOrEqual(level, 0.0)
            XCTAssertLessThanOrEqual(level, 1.0)
            XCTAssertLessThanOrEqual(abs(level - base), resetJitter + 1e-12)
        }
    }

    func testResetConversationKeepsChemistry() async throws {
        let mock = MockInterpreter(results: [
            InterpreterResult(
                reply: "hey",
                impulses: [ChemicalImpulse(chemical: .dopamine, delta: 0.3)],
                path: .llm
            ),
        ])
        let robot = try Robot(clock: ManualClock(), interpreter: mock)
        await robot.process(text: "hello")
        let dopamine = robot.currentChemicals().get(.dopamine)
        robot.resetConversation()
        XCTAssertTrue(robot.conversation.isEmpty)
        XCTAssertEqual(robot.currentChemicals().get(.dopamine), dopamine)
    }
}
