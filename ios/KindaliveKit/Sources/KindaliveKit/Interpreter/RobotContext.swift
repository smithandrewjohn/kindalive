// RobotContext — snapshot of robot state passed to the interpreter.
// Ports the RobotContext dataclass + PromptBuilder.build_context in
// kindalive/interpreter/prompt_builder.py.

import Foundation

public struct RobotContext: Sendable {
    public let personalityName: String
    public let affinity: Double
    public let dominantEmotion: String
    /// Top 4 chemicals by deviation from 0.5, e.g.
    /// "adrenaline=0.62, dopamine=0.55, gaba=0.31, cortisol=0.28".
    public let chemicalSummary: String

    public init(
        personalityName: String,
        affinity: Double,
        dominantEmotion: String,
        chemicalSummary: String
    ) {
        self.personalityName = personalityName
        self.affinity = affinity
        self.dominantEmotion = dominantEmotion
        self.chemicalSummary = chemicalSummary
    }

    /// Mirrors PromptBuilder.build_context: dominant emotion + the top 4
    /// chemicals by |level − 0.5| (most "interesting"), ties keeping
    /// chemical declaration order like Python's stable sort.
    public static func build(
        personality: String,
        affinity: Double,
        emotions: EmotionVector,
        chemicals: ChemicalState
    ) -> RobotContext {
        let ordered = Chemical.allCases.map { ($0.rawValue, chemicals.get($0)) }
        let byDeviation = ordered.enumerated().sorted {
            let d0 = abs($0.element.1 - 0.5)
            let d1 = abs($1.element.1 - 0.5)
            return d0 != d1 ? d0 > d1 : $0.offset < $1.offset
        }
        let summary = byDeviation.prefix(4)
            .map { "\($0.element.0)=" + String(format: "%.2f", $0.element.1) }
            .joined(separator: ", ")
        return RobotContext(
            personalityName: personality,
            affinity: affinity,
            dominantEmotion: emotions.dominant().name,
            chemicalSummary: summary
        )
    }
}
