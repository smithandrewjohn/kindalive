// EmotionVector — the 8-emotion output of the projection layer.
// Ports kindalive/emotions/emotion_vector.py.

import Foundation

public struct EmotionVector: Sendable, Equatable {
    public let happiness: Double
    public let excitement: Double
    public let anger: Double
    public let calm: Double
    public let bonding: Double
    public let anxiety: Double
    public let sadness: Double
    public let euphoria: Double

    /// Declaration order matches the Python dataclass so `dominant()` and
    /// `topN()` break ties identically (Python dict iteration order).
    public static let names = [
        "happiness", "excitement", "anger", "calm",
        "bonding", "anxiety", "sadness", "euphoria",
    ]

    public init(
        happiness: Double, excitement: Double, anger: Double, calm: Double,
        bonding: Double, anxiety: Double, sadness: Double, euphoria: Double
    ) {
        self.happiness = happiness
        self.excitement = excitement
        self.anger = anger
        self.calm = calm
        self.bonding = bonding
        self.anxiety = anxiety
        self.sadness = sadness
        self.euphoria = euphoria
    }

    /// Ordered (name, value) pairs in declaration order.
    public var orderedValues: [(name: String, value: Double)] {
        [
            ("happiness", happiness), ("excitement", excitement),
            ("anger", anger), ("calm", calm),
            ("bonding", bonding), ("anxiety", anxiety),
            ("sadness", sadness), ("euphoria", euphoria),
        ]
    }

    public func asDict() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: orderedValues.map { ($0.name, $0.value) })
    }

    /// (name, value) of the highest emotion. Ties resolve to the first
    /// in declaration order, matching Python `max` over a dict.
    public func dominant() -> (name: String, value: Double) {
        var best = orderedValues[0]
        for entry in orderedValues.dropFirst() where entry.value > best.value {
            best = entry
        }
        return best
    }

    /// Top N emotions sorted by value descending; ties keep declaration
    /// order (Python `sorted` is stable).
    public func topN(_ n: Int = 3) -> [(name: String, value: Double)] {
        let indexed = orderedValues.enumerated()
        let sorted = indexed.sorted {
            $0.element.value != $1.element.value
                ? $0.element.value > $1.element.value
                : $0.offset < $1.offset
        }
        return sorted.prefix(n).map { $0.element }
    }
}
