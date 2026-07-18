// ImpulseValidator — sanitize and validate interpreter-produced impulses.
// Ports kindalive/interpreter/validator.py.
//
// Guided generation on iOS already constrains chemical names and ranges,
// but the Kit-level Robot API shouldn't trust any interpreter — this
// stays in the loop as defense in depth, with the exact Python rules:
// >8 impulses is a hard error, unknown chemicals are skipped, deltas
// clamp to [-0.5, 0.5], durations clamp to [0, 300].

import Foundation

public let maxDelta = 0.5
public let minDelta = -0.5
public let maxDuration = 300.0
public let maxImpulses = 8

/// An unvalidated impulse as produced by an interpreter backend.
public struct RawImpulse: Sendable {
    public var chemical: String
    public var delta: Double
    public var durationSeconds: Double
    public var sourceId: String
    public var sourceLabel: String

    public init(
        chemical: String,
        delta: Double,
        durationSeconds: Double = 0.0,
        sourceId: String = "",
        sourceLabel: String = ""
    ) {
        self.chemical = chemical
        self.delta = delta
        self.durationSeconds = durationSeconds
        self.sourceId = sourceId
        self.sourceLabel = sourceLabel
    }
}

/// Validate and convert raw impulses. Individual impulses with unknown
/// chemical names are skipped (not fatal); structural problems throw.
public func validateRawImpulses(_ raw: [RawImpulse]) throws -> [ChemicalImpulse] {
    guard raw.count <= maxImpulses else {
        throw KindaliveError.validation(
            "Too many impulses: \(raw.count) (max \(maxImpulses))"
        )
    }
    var impulses: [ChemicalImpulse] = []
    for item in raw {
        guard let chemical = Chemical.from(string: item.chemical) else {
            continue  // skip unknown chemicals rather than failing the batch
        }
        guard item.delta.isFinite else {
            throw KindaliveError.validation("'delta' is not a number")
        }
        let delta = max(minDelta, min(maxDelta, item.delta))
        let duration = item.durationSeconds.isFinite
            ? max(0.0, min(maxDuration, item.durationSeconds))
            : 0.0
        impulses.append(
            ChemicalImpulse(
                chemical: chemical,
                delta: delta,
                durationSeconds: duration,
                sourceId: item.sourceId,
                sourceLabel: item.sourceLabel
            )
        )
    }
    return impulses
}
