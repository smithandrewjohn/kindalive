// Interpreter-layer tests, mirroring tests/test_interpreter/
// (test_validator.py, test_fallback_rules.py, test_prompt_builder.py).

import Foundation
import XCTest
@testable import KindaliveKit

final class ValidatorTests: XCTestCase {
    func testValidImpulsesPassThrough() throws {
        let impulses = try validateRawImpulses([
            RawImpulse(chemical: "dopamine", delta: 0.3),
            RawImpulse(chemical: "CORTISOL", delta: -0.2, durationSeconds: 60),
        ])
        XCTAssertEqual(impulses.count, 2)
        XCTAssertEqual(impulses[0].chemical, .dopamine)
        XCTAssertEqual(impulses[1].chemical, .cortisol)
        XCTAssertEqual(impulses[1].durationSeconds, 60)
    }

    func testTooManyImpulsesThrows() {
        let nine = (0..<9).map { _ in RawImpulse(chemical: "dopamine", delta: 0.1) }
        XCTAssertThrowsError(try validateRawImpulses(nine))
    }

    func testUnknownChemicalIsSkippedNotFatal() throws {
        let impulses = try validateRawImpulses([
            RawImpulse(chemical: "caffeine", delta: 0.4),
            RawImpulse(chemical: "gaba", delta: 0.2),
        ])
        XCTAssertEqual(impulses.map(\.chemical), [.gaba])
    }

    func testDeltaAndDurationClamp() throws {
        let impulses = try validateRawImpulses([
            RawImpulse(chemical: "dopamine", delta: 0.9),
            RawImpulse(chemical: "serotonin", delta: -0.8, durationSeconds: 900),
        ])
        XCTAssertEqual(impulses[0].delta, 0.5)
        XCTAssertEqual(impulses[1].delta, -0.5)
        XCTAssertEqual(impulses[1].durationSeconds, 300)
    }

    func testNonFiniteDeltaThrows() {
        XCTAssertThrowsError(try validateRawImpulses([
            RawImpulse(chemical: "dopamine", delta: .nan),
        ]))
    }
}

final class FallbackTests: XCTestCase {
    func testFallbackIsSingleCortisolNudge() async {
        let interpreter = FallbackInterpreter(reason: "model unavailable")
        let context = RobotContext(
            personalityName: "default", affinity: 1.0,
            dominantEmotion: "calm", chemicalSummary: ""
        )
        let result = await interpreter.interpret(UserText(summary: "hi"), context: context)
        XCTAssertEqual(result.path, .fallback)
        XCTAssertEqual(result.reply, "")
        XCTAssertEqual(result.errorMessage, "model unavailable")
        XCTAssertEqual(result.impulses.count, 1)
        XCTAssertEqual(result.impulses[0].chemical, .cortisol)
        XCTAssertEqual(result.impulses[0].delta, 0.05)
        XCTAssertEqual(result.impulses[0].sourceId, "fallback:freeform")
    }
}

final class RobotContextTests: XCTestCase {
    func testChemicalSummaryTopFourByDeviation() {
        let state = ChemicalState()
        state.set(.adrenaline, 0.95)   // deviation 0.45
        state.set(.dopamine, 0.05)     // deviation 0.45 (tie → declaration order)
        state.set(.serotonin, 0.5)     // deviation 0.0
        let emotions = EmotionProjection.compute(state)
        let context = RobotContext.build(
            personality: "cheerful", affinity: 1.2,
            emotions: emotions, chemicals: state
        )
        XCTAssertEqual(context.personalityName, "cheerful")
        XCTAssertEqual(context.affinity, 1.2)
        // dopamine declared before adrenaline, so the tie keeps that order.
        XCTAssertTrue(context.chemicalSummary.hasPrefix("dopamine=0.05, adrenaline=0.95"))
        XCTAssertEqual(context.chemicalSummary.components(separatedBy: ", ").count, 4)
    }

    func testTurnPromptContainsStateAndText() {
        let context = RobotContext(
            personalityName: "anxious", affinity: 1.5,
            dominantEmotion: "anxiety", chemicalSummary: "cortisol=0.80"
        )
        let prompt = InterpreterInstructions.turnPrompt(context: context, text: "the cat is missing")
        XCTAssertTrue(prompt.contains("personality: anxious"))
        XCTAssertTrue(prompt.contains("dominant mood: anxiety"))
        XCTAssertTrue(prompt.contains("cortisol=0.80"))
        XCTAssertTrue(prompt.contains("Owner says: the cat is missing"))
    }

    func testInstructionsKeepCalibrationAndDropJsonRules() {
        let text = InterpreterInstructions.text
        XCTAssertTrue(text.contains("I won the lottery"))
        XCTAssertTrue(text.contains("ONE consolidated set"))
        XCTAssertTrue(text.contains("DEFAULT TO 0"))
        // Guided generation replaced the JSON-format rules entirely.
        XCTAssertFalse(text.contains("JSON FORMAT REQUIREMENTS"))
        XCTAssertFalse(text.contains("markdown code fences"))
    }
}
