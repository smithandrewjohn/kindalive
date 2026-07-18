// SpeechCoordinator — spoken replies with mood-mapped voice and
// word-boundary lip sync.
//
// The exact analogue of the web UI's Web Speech wiring:
//   didStart                     → face.setSpeaking(true)
//   willSpeakRangeOfSpeechString → face.mouthPulse()   (word boundary)
//   didFinish / didCancel        → face.setSpeaking(false)
//
// Rate mapping caveat: Kit's VoiceParams returns a Web-Speech-style
// 1.0-centered multiplier (0.8-1.3), but AVSpeechUtterance.rate is an
// absolute 0-1 scale centered at AVSpeechUtteranceDefaultSpeechRate —
// so the multiplier scales the default rate. pitchMultiplier takes the
// 0.7-1.4 value directly (its valid range is 0.5-2.0). TTS output needs
// no permissions and no gesture priming (a Web Speech quirk).

import AVFoundation
import Foundation
import KindaliveKit

final class SpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private weak var faceModel: FaceRenderModel?

    /// Mirrors the web UI's 🔊 toggle.
    var voiceOn = true

    init(faceModel: FaceRenderModel) {
        self.faceModel = faceModel
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func speak(_ text: String, emotions: EmotionVector) {
        guard voiceOn, !text.isEmpty else { return }
        stop()
        try? AVAudioSession.sharedInstance().setActive(true)

        let params = VoiceParams(emotions: emotions)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(params.rate)
        utterance.pitchMultiplier = Float(params.pitch)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate (lip sync)

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        faceModel?.setSpeaking(true)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        faceModel?.mouthPulse()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        faceModel?.setSpeaking(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        faceModel?.setSpeaking(false)
    }
}
