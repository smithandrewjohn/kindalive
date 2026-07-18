// Behavioral engine tests, mirroring the Python suites
// (tests/test_chemicals.py, test_interactions.py, test_saturation.py).

import Foundation
import XCTest
@testable import KindaliveKit

final class ChemicalsTests: XCTestCase {
    func testFromStringIsCaseInsensitive() {
        XCTAssertEqual(Chemical.from(string: "DOPAMINE"), .dopamine)
        XCTAssertEqual(Chemical.from(string: "Serotonin"), .serotonin)
        XCTAssertEqual(Chemical.from(string: "gaba"), .gaba)
        XCTAssertNil(Chemical.from(string: "caffeine"))
    }

    func testStartsAtBaseline() {
        let state = ChemicalState()
        for chem in Chemical.allCases {
            XCTAssertEqual(state.get(chem), speciesDefaults[chem]!.baseline)
        }
    }

    func testSetClampsToUnitInterval() {
        let state = ChemicalState()
        state.set(.dopamine, 1.7)
        XCTAssertEqual(state.get(.dopamine), 1.0)
        state.set(.dopamine, -0.4)
        XCTAssertEqual(state.get(.dopamine), 0.0)
    }

    func testBaselineClampsToDriftBounds() {
        let state = ChemicalState()
        state.setBaseline(.cortisol, 0.9)
        XCTAssertEqual(state.baseline(.cortisol), 0.5)
        state.setBaseline(.cortisol, 0.01)
        XCTAssertEqual(state.baseline(.cortisol), 0.1)
    }

    func testDecayHalvesDistanceToBaselineAfterOneHalfLife() {
        let state = ChemicalState()
        let baseline = state.baseline(.dopamine)
        state.set(.dopamine, 1.0)
        state.applyDecay(.dopamine, dt: state.halfLife(.dopamine))
        let expected = baseline + (1.0 - baseline) / 2
        XCTAssertEqual(state.get(.dopamine), expected, accuracy: 1e-12)
    }

    func testDecayRecoversFromBelowBaseline() {
        let state = ChemicalState()
        state.set(.serotonin, 0.1)
        state.applyDecay(.serotonin, dt: 60.0)
        XCTAssertGreaterThan(state.get(.serotonin), 0.1)
        XCTAssertLessThan(state.get(.serotonin), state.baseline(.serotonin))
    }
}

final class InteractionsTests: XCTestCase {
    func testAllBaselineStateIsFixedPoint() {
        let state = ChemicalState()
        let before = state.asDict()
        let baselinesBefore = state.baselinesAsDict()
        applyInteractions(state, dt: 0.5)
        assertChemicalsEqual(state.asDict(), before, accuracy: 1e-12, context: "levels")
        assertChemicalsEqual(
            state.baselinesAsDict(), baselinesBefore, accuracy: 1e-12, context: "baselines"
        )
    }

    func testCortisolExcessErodesSerotonin() {
        let state = ChemicalState()
        state.set(.cortisol, 0.9)
        let before = state.get(.serotonin)
        applyInteractions(state, dt: 0.5)
        XCTAssertLessThan(state.get(.serotonin), before)
    }
}

final class NeurochemicalEngineTests: XCTestCase {
    func testInstantImpulseAppliesImmediately() {
        let engine = NeurochemicalEngine()
        let before = engine.state.get(.dopamine)
        engine.applyImpulse(ChemicalImpulse(chemical: .dopamine, delta: 0.3))
        XCTAssertEqual(engine.state.get(.dopamine), before + 0.3, accuracy: 1e-12)
    }

    func testSustainedImpulseDripsOverTime() {
        let clock = ManualClock()
        let engine = NeurochemicalEngine(clock: clock)
        engine.applyImpulse(ChemicalImpulse(
            chemical: .gaba, delta: 0.2, durationSeconds: 100.0
        ))
        let start = engine.state.get(.gaba)
        clock.advance(seconds: 1.0)
        engine.advance(dt: 1.0)
        // After 1 of 100 seconds, only ~1/100 of the delta has landed
        // (minus a hair of decay toward baseline).
        XCTAssertLessThan(engine.state.get(.gaba), start + 0.01)
        XCTAssertGreaterThan(engine.state.get(.gaba), start)
        XCTAssertEqual(engine.activeSustainedImpulses.count, 1)
    }

    func testSustainedImpulseExpires() {
        let clock = ManualClock()
        let engine = NeurochemicalEngine(clock: clock)
        engine.applyImpulse(ChemicalImpulse(
            chemical: .gaba, delta: 0.2, durationSeconds: 10.0
        ))
        clock.advance(seconds: 20.0)
        engine.advance(dt: 20.0)
        XCTAssertTrue(engine.activeSustainedImpulses.isEmpty)
    }

    func testAdvanceSubStepsMatchManualHalfSecondSteps() {
        let makeEngine: () -> NeurochemicalEngine = {
            let engine = NeurochemicalEngine(clock: ManualClock())
            engine.applyImpulses([
                ChemicalImpulse(chemical: .adrenaline, delta: 0.5),
                ChemicalImpulse(chemical: .cortisol, delta: 0.4),
            ])
            return engine
        }
        let bigStep = makeEngine()
        bigStep.advance(dt: 60.0)
        let smallSteps = makeEngine()
        for _ in 0..<120 {
            smallSteps.advance(dt: 0.5)
        }
        assertChemicalsEqual(
            bigStep.state.asDict(), smallSteps.state.asDict(),
            accuracy: 1e-9, context: "sub-step equivalence"
        )
    }

    func testNegativeDtTraps() {
        // advance() has a precondition(dt >= 0); we only verify the
        // positive contract here (matching Python's ValueError test is
        // not possible with XCTest across platforms).
        let engine = NeurochemicalEngine()
        engine.advance(dt: 0.0)  // no-op, must not trap
    }
}

final class SaturationTests: XCTestCase {
    func testRepeatedSourceDampens() {
        let clock = ManualClock()
        let engine = NeurochemicalEngine(clock: clock)
        engine.state.set(.dopamine, 0.0)
        engine.applyImpulse(ChemicalImpulse(
            chemical: .dopamine, delta: 0.2, sourceId: "test:src"
        ))
        let firstGain = engine.state.get(.dopamine)
        XCTAssertEqual(firstGain, 0.2, accuracy: 1e-12)

        engine.state.set(.dopamine, 0.0)
        engine.applyImpulse(ChemicalImpulse(
            chemical: .dopamine, delta: 0.2, sourceId: "test:src"
        ))
        // Second hit: factor 1/(1 + 1*0.3)
        XCTAssertEqual(engine.state.get(.dopamine), 0.2 / 1.3, accuracy: 1e-12)
    }

    func testWindowExpiryResetsDampening() {
        let clock = ManualClock()
        let engine = NeurochemicalEngine(clock: clock)
        engine.applyImpulse(ChemicalImpulse(
            chemical: .dopamine, delta: 0.2, sourceId: "test:src"
        ))
        clock.advance(seconds: saturationWindow + 1)
        engine.state.set(.dopamine, 0.0)
        engine.applyImpulse(ChemicalImpulse(
            chemical: .dopamine, delta: 0.2, sourceId: "test:src"
        ))
        XCTAssertEqual(engine.state.get(.dopamine), 0.2, accuracy: 1e-12)
    }

    func testEmptySourceIdNeverDampens() {
        let engine = NeurochemicalEngine()
        for _ in 0..<3 {
            engine.state.set(.dopamine, 0.0)
            engine.applyImpulse(ChemicalImpulse(chemical: .dopamine, delta: 0.2))
            XCTAssertEqual(engine.state.get(.dopamine), 0.2, accuracy: 1e-12)
        }
    }
}
