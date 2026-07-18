// StateStore — save/load robot state, byte-compatible with the Python
// persistence format (kindalive/persistence/state_store.py, version 1).
//
// A state file produced by this code is loadable by the Python
// `load_state`, and vice versa. Note the same asymmetry as Python:
// `half_lives` are written for readability but are derived from the seed
// on load; the saturation window and conversation are not persisted.

import Foundation

public struct SeedSnapshot: Codable, Sendable {
    public var baselines: [String: Double]
    public var interactionScale: Double
    /// Present only when non-empty, matching Python `SeedChemistry.to_dict`.
    public var halfLifeMultipliers: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case baselines
        case interactionScale = "interaction_scale"
        case halfLifeMultipliers = "half_life_multipliers"
    }

    public init(seed: SeedChemistry) {
        baselines = Dictionary(
            uniqueKeysWithValues: seed.baselines.map { ($0.key.rawValue, $0.value) }
        )
        interactionScale = seed.interactionScale
        halfLifeMultipliers = seed.halfLifeMultipliers.isEmpty
            ? nil
            : Dictionary(
                uniqueKeysWithValues: seed.halfLifeMultipliers.map { ($0.key.rawValue, $0.value) }
            )
    }

    public func toSeed() -> SeedChemistry {
        var seed = SeedChemistry.fromSpeciesDefaults()
        for (name, value) in baselines {
            if let chem = Chemical.from(string: name) {
                seed.baselines[chem] = value
            }
        }
        for (name, value) in halfLifeMultipliers ?? [:] {
            if let chem = Chemical.from(string: name) {
                seed.halfLifeMultipliers[chem] = value
            }
        }
        seed.interactionScale = interactionScale
        return seed
    }
}

public struct SustainedSnapshot: Codable, Sendable {
    public var chemical: String
    public var delta: Double
    public var durationSeconds: Double
    public var sourceId: String
    public var sourceLabel: String
    public var remainingSeconds: Double
    public var ratePerSecond: Double

    enum CodingKeys: String, CodingKey {
        case chemical
        case delta
        case durationSeconds = "duration_seconds"
        case sourceId = "source_id"
        case sourceLabel = "source_label"
        case remainingSeconds = "remaining_seconds"
        case ratePerSecond = "rate_per_second"
    }
}

public struct EngineSnapshot: Codable, Sendable {
    public var version: Int
    public var levels: [String: Double]
    public var baselines: [String: Double]
    public var halfLives: [String: Double]
    public var seed: SeedSnapshot
    public var sustainedImpulses: [SustainedSnapshot]

    enum CodingKeys: String, CodingKey {
        case version
        case levels
        case baselines
        case halfLives = "half_lives"
        case seed
        case sustainedImpulses = "sustained_impulses"
    }
}

public enum StateStore {
    /// Serialize engine state, mirroring Python `serialize_engine`.
    public static func serialize(_ engine: NeurochemicalEngine) -> EngineSnapshot {
        let state = engine.state
        let halfLives = Dictionary(
            uniqueKeysWithValues: Chemical.allCases.map { ($0.rawValue, state.halfLife($0)) }
        )
        let sustained = engine.activeSustainedImpulses.map { active in
            SustainedSnapshot(
                chemical: active.impulse.chemical.rawValue,
                delta: active.impulse.delta,
                durationSeconds: active.impulse.durationSeconds,
                sourceId: active.impulse.sourceId,
                sourceLabel: active.impulse.sourceLabel,
                remainingSeconds: active.remainingSeconds,
                ratePerSecond: active.ratePerSecond
            )
        }
        return EngineSnapshot(
            version: 1,
            levels: state.asDict(),
            baselines: state.baselinesAsDict(),
            halfLives: halfLives,
            seed: SeedSnapshot(seed: engine.seed),
            sustainedImpulses: sustained
        )
    }

    /// Restore engine state in place, mirroring Python `deserialize_engine`:
    /// levels, baselines (drift survives), and sustained impulses.
    public static func restore(_ snapshot: EngineSnapshot, into engine: NeurochemicalEngine) throws {
        guard snapshot.version == 1 else {
            throw KindaliveError.unknownStateVersion(snapshot.version)
        }
        for (name, level) in snapshot.levels {
            if let chem = Chemical.from(string: name) {
                engine.state.set(chem, level)
            }
        }
        for (name, baseline) in snapshot.baselines {
            if let chem = Chemical.from(string: name) {
                engine.state.setBaseline(chem, baseline)
            }
        }
        engine.sustained = snapshot.sustainedImpulses.map { snap in
            ActiveSustainedImpulse(
                impulse: ChemicalImpulse(
                    chemical: Chemical.from(string: snap.chemical) ?? .cortisol,
                    delta: snap.delta,
                    durationSeconds: snap.durationSeconds,
                    sourceId: snap.sourceId,
                    sourceLabel: snap.sourceLabel
                ),
                remainingSeconds: snap.remainingSeconds,
                ratePerSecond: snap.ratePerSecond
            )
        }
    }

    /// Encode to pretty, key-sorted JSON (diffable, like the Python dump).
    public static func encode(_ snapshot: EngineSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> EngineSnapshot {
        try JSONDecoder().decode(EngineSnapshot.self, from: data)
    }

    public static func save(_ engine: NeurochemicalEngine, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encode(serialize(engine)).write(to: url, options: .atomic)
    }

    public static func load(into engine: NeurochemicalEngine, from url: URL) throws {
        let data = try Data(contentsOf: url)
        try restore(decode(data), into: engine)
    }
}
