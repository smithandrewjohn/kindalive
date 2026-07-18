// VoiceParams — map the current mood to TTS rate/pitch.
// Ports _voice_params in kindalive/expression/web_ui.py.
//
// More arousal (excitement/anxiety/anger) → faster; more positive valence
// (happiness/euphoria over sadness/anxiety) → higher pitch. The returned
// rate is a Web-Speech-style 1.0-centered multiplier in [0.8, 1.3]; the
// app maps it onto AVSpeechUtterance's absolute 0-1 scale.

import Foundation

public struct VoiceParams: Sendable, Equatable {
    /// 1.0-centered speech-rate multiplier in [0.8, 1.3].
    public let rate: Double
    /// Pitch multiplier in [0.7, 1.4].
    public let pitch: Double

    public init(emotions: EmotionVector) {
        let arousal = emotions.excitement + emotions.anxiety + emotions.anger
        let valence = emotions.happiness + emotions.euphoria
            - emotions.sadness - emotions.anxiety
        let rawRate = max(0.8, min(1.3, 1.0 + 0.35 * min(1.0, arousal)))
        let rawPitch = max(0.7, min(1.4, 1.0 + 0.30 * max(-1.0, min(1.0, valence))))
        // Python rounds to 2 decimals with banker's rounding.
        rate = (rawRate * 100).rounded(.toNearestOrEven) / 100
        pitch = (rawPitch * 100).rounded(.toNearestOrEven) / 100
    }
}
