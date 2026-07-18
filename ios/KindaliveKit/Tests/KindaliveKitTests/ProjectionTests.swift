// Emotion/face projection and seed-chemistry behavior tests, mirroring
// tests/test_emotion_projection.py, test_face.py, test_seed_chemistry.py.

import Foundation
import XCTest
@testable import KindaliveKit

final class SeedChemistryTests: XCTestCase {
    func testSpeciesDefaultsCoverAllChemicals() {
        let seed = SeedChemistry.fromSpeciesDefaults()
        XCTAssertEqual(seed.baselines.count, Chemical.allCases.count)
        XCTAssertEqual(seed.interactionScale, 1.0)
    }

    func testPresetOverridesApply() throws {
        let cheerful = try getSeed("cheerful")
        XCTAssertEqual(cheerful.baselines[.serotonin], 0.6)
        XCTAssertEqual(cheerful.baselines[.dopamine], 0.4)
        XCTAssertEqual(cheerful.baselines[.cortisol], 0.2)  // untouched species default
        XCTAssertEqual(getDefaultAffinity("cheerful"), 1.2)

        let stoic = try getSeed("stoic")
        XCTAssertEqual(stoic.interactionScale, 0.7)
        XCTAssertEqual(stoic.effectiveHalfLife(.adrenaline), 180.0 * 0.7, accuracy: 1e-12)

        let anxious = try getSeed("anxious")
        XCTAssertEqual(anxious.effectiveHalfLife(.cortisol), 3600.0 * 1.5, accuracy: 1e-12)
        XCTAssertEqual(getDefaultAffinity("anxious"), 1.5)
    }

    func testUnknownPersonalityThrows() {
        XCTAssertThrowsError(try getSeed("grumpy"))
    }
}

final class EmotionProjectionTests: XCTestCase {
    func testDefaultStateIsNeutral() {
        // Mirrors test_default_state_is_neutral: at species baselines the
        // dominant emotion is calm, and sadness is exactly zero-driven
        // (inverted terms vanish at baseline).
        let state = ChemicalState()
        let emotions = EmotionProjection.compute(state)
        XCTAssertEqual(emotions.dominant().name, "calm")
        XCTAssertGreaterThan(emotions.calm, emotions.sadness)
        XCTAssertGreaterThan(emotions.calm, emotions.anger)
    }

    func testDopamineSpikesRaiseHappiness() {
        let state = ChemicalState()
        let before = EmotionProjection.compute(state).happiness
        state.set(.dopamine, 0.9)
        let after = EmotionProjection.compute(state).happiness
        XCTAssertGreaterThan(after, before)
    }

    func testSadnessRequiresDeficitBelowBaseline() {
        let state = ChemicalState()
        let atBaseline = EmotionProjection.compute(state).sadness
        state.set(.dopamine, 0.05)
        state.set(.serotonin, 0.1)
        let depleted = EmotionProjection.compute(state).sadness
        XCTAssertGreaterThan(depleted, atBaseline)
    }

    func testDominantAndTopNOrdering() {
        let vector = EmotionVector(
            happiness: 0.9, excitement: 0.4, anger: 0.1, calm: 0.9,
            bonding: 0.2, anxiety: 0.0, sadness: 0.0, euphoria: 0.5
        )
        // Tie between happiness and calm — declaration order wins.
        XCTAssertEqual(vector.dominant().name, "happiness")
        XCTAssertEqual(vector.topN(3).map(\.name), ["happiness", "calm", "euphoria"])
    }
}

final class FaceProjectionTests: XCTestCase {
    func testNeutralFaceIsRelaxed() {
        let state = ChemicalState()
        let face = FaceProjection.compute(state)
        // At baseline the inverted-term muscles get no deficit input.
        XCTAssertLessThan(face.browInnerRaise, 0.3)
        XCTAssertLessThan(face.lipCornerDepress, 0.3)
    }

    func testDopamineSmiles() {
        let state = ChemicalState()
        state.set(.dopamine, 0.9)
        state.set(.endorphins, 0.7)
        let face = FaceProjection.compute(state)
        XCTAssertGreaterThan(face.lipCornerPull, face.lipCornerDepress)
        XCTAssertGreaterThan(face.cheekRaise, 0.3)
    }

    func testFaceGeometryModes() {
        var muscles = Dictionary(uniqueKeysWithValues: FaceState.muscleNames.map { ($0, 0.0) })
        muscles["lip_corner_pull"] = 0.8
        let happy = FaceGeometry(muscles: muscles, blink: 0.0)
        XCTAssertTrue(happy.happyEyes)
        XCTAssertFalse(happy.mouthOpen)

        muscles["jaw_open"] = 0.6
        let open = FaceGeometry(muscles: muscles, blink: 0.0)
        XCTAssertTrue(open.mouthOpen)

        let blinking = FaceGeometry(muscles: muscles, blink: 1.0)
        XCTAssertFalse(blinking.happyEyes)
        XCTAssertEqual(blinking.openK, 0.0, accuracy: 1e-12)
    }
}
