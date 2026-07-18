// MoodPalette — the valence-family color palette shared with the web UI.
// Hex values mirror CHEMICAL_COLORS / EMOTION_COLORS in
// kindalive/expression/web_ui.py (docs/design/color-palette-review.md).

import Foundation

public enum MoodPalette {
    /// Default mood accent (calm teal) used before any emotion dominates.
    public static let defaultMoodColor = "#4FB7A6"

    public static let chemicalColors: [Chemical: String] = [
        .dopamine:     "#E6A23C",  // warm amber — reward
        .serotonin:    "#4FB7A6",  // muted teal — wellbeing
        .oxytocin:     "#7FB3D9",  // dusty sky — bonding
        .testosterone: "#D96B2C",  // burnt orange — drive
        .cortisol:     "#C4513F",  // rust red — stress
        .adrenaline:   "#E8526B",  // hot coral — arousal
        .endorphins:   "#E8C36B",  // pale straw — pleasure
        .gaba:         "#5682B5",  // slate blue — calm
    ]

    public static let emotionColors: [String: String] = [
        "happiness":  "#E6A23C",
        "excitement": "#D96B2C",
        "anger":      "#C4513F",
        "calm":       "#4FB7A6",
        "bonding":    "#7FB3D9",
        "anxiety":    "#B892D1",
        "sadness":    "#6B87A8",
        "euphoria":   "#C678DD",
    ]

    /// Mood accent for a dominant emotion (falls back to the calm teal).
    public static func color(forEmotion name: String) -> String {
        emotionColors[name] ?? defaultMoodColor
    }
}
