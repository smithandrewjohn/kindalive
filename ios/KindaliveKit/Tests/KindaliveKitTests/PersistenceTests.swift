// Persistence tests, mirroring tests/test_persistence.py — plus the
// cross-language gate: decoding a real Python `serialize_engine()` dump.

import Foundation
import XCTest
@testable import KindaliveKit

final class PersistenceTests: XCTestCase {
    func testDecodePythonSampleAndRestore() throws {
        // persistence_sample.json is written by the Python engine
        // (anxious preset, drifted state, one live sustained impulse).
        let snapshot: EngineSnapshot = try loadFixture("persistence_sample")
        XCTAssertEqual(snapshot.version, 1)

        let engine = NeurochemicalEngine(clock: ManualClock(), seed: snapshot.seed.toSeed())
        try StateStore.restore(snapshot, into: engine)

        assertChemicalsEqual(
            engine.state.asDict(), snapshot.levels,
            accuracy: 1e-12, context: "restored levels"
        )
        assertChemicalsEqual(
            engine.state.baselinesAsDict(), snapshot.baselines,
            accuracy: 1e-12, context: "restored baselines"
        )
        XCTAssertEqual(
            engine.activeSustainedImpulses.count,
            snapshot.sustainedImpulses.count
        )
        if let active = engine.activeSustainedImpulses.first,
           let expected = snapshot.sustainedImpulses.first {
            XCTAssertEqual(active.impulse.chemical.rawValue, expected.chemical)
            XCTAssertEqual(active.remainingSeconds, expected.remainingSeconds, accuracy: 1e-12)
            XCTAssertEqual(active.ratePerSecond, expected.ratePerSecond, accuracy: 1e-12)
        } else if !snapshot.sustainedImpulses.isEmpty {
            XCTFail("sustained impulse not restored")
        }

        // The anxious seed's half-life multipliers must survive the trip.
        XCTAssertEqual(
            engine.state.halfLife(.cortisol), 3600.0 * 1.5, accuracy: 1e-9
        )
    }

    func testRoundTripEncodeDecode() throws {
        let clock = ManualClock()
        let engine = NeurochemicalEngine(clock: clock, seed: try getSeed("stoic"))
        engine.applyImpulses([
            ChemicalImpulse(chemical: .dopamine, delta: 0.3, sourceId: "t:1"),
            ChemicalImpulse(chemical: .gaba, delta: 0.2, durationSeconds: 90.0),
        ])
        clock.advance(seconds: 10)
        engine.advance(dt: 10)

        let data = try StateStore.encode(StateStore.serialize(engine))
        let decoded = try StateStore.decode(data)

        let restored = NeurochemicalEngine(clock: ManualClock(), seed: decoded.seed.toSeed())
        try StateStore.restore(decoded, into: restored)

        assertChemicalsEqual(
            restored.state.asDict(), engine.state.asDict(),
            accuracy: 1e-12, context: "round-trip levels"
        )
        XCTAssertEqual(
            restored.activeSustainedImpulses.count,
            engine.activeSustainedImpulses.count
        )
        XCTAssertEqual(restored.seed.interactionScale, 0.7)
    }

    func testUnknownVersionThrows() throws {
        var snapshot = StateStore.serialize(NeurochemicalEngine())
        snapshot.version = 2
        let engine = NeurochemicalEngine()
        XCTAssertThrowsError(try StateStore.restore(snapshot, into: engine))
    }

    func testSnakeCaseWireFormat() throws {
        let engine = NeurochemicalEngine(seed: try getSeed("anxious"))
        let data = try StateStore.encode(StateStore.serialize(engine))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // The exact keys Python's serialize_engine writes.
        XCTAssertEqual(
            Set(object.keys),
            ["version", "levels", "baselines", "half_lives", "seed", "sustained_impulses"]
        )
        let seed = try XCTUnwrap(object["seed"] as? [String: Any])
        XCTAssertNotNil(seed["interaction_scale"])
        XCTAssertNotNil(seed["half_life_multipliers"])
    }
}
