// RobotViewModel — the app's orchestrator, mirroring the web UI's
// AppState: owns the Robot, ticks the simulation at 10 Hz (scaled by the
// 1×/10×/60× time-speed control, same ManualClock + scaled-dt pattern as
// the web UI), pushes face targets, and runs the send pipeline.

import Foundation
import KindaliveKit
import Observation

struct SpeedOption: Identifiable {
    let label: String
    let value: Double
    var id: Double { value }
}

let speedOptions = [
    SpeedOption(label: "1×", value: 1.0),
    SpeedOption(label: "10×", value: 10.0),
    SpeedOption(label: "60×", value: 60.0),
]

private let refreshHz = 10.0

@MainActor
@Observable
final class RobotViewModel {
    private(set) var personality = "default"
    var speed = 1.0
    var voiceOn = true {
        didSet { speech.voiceOn = voiceOn }
    }

    private(set) var robot: Robot
    private(set) var lastReply = ""
    private(set) var statusLine = ""
    private(set) var isProcessing = false

    // Live projections, refreshed every tick for the bar panels.
    private(set) var chemicalLevels: [Chemical: Double] = [:]
    private(set) var emotions: EmotionVector

    let faceModel = FaceRenderModel()
    private let speech: SpeechCoordinator
    private var interpreter: FoundationModelInterpreter
    private var lastTick = Date().timeIntervalSinceReferenceDate
    private var tickTask: Task<Void, Never>?

    /// Status badge for the header: "Apple Intelligence" when the
    /// on-device model is live, otherwise the unavailability reason.
    var modelStatus: String {
        interpreter.availabilityNotice.isEmpty
            ? "Apple Intelligence"
            : "offline — \(interpreter.availabilityNotice)"
    }

    var dominantEmotion: (name: String, value: Double) {
        emotions.dominant()
    }

    var topEmotions: [(name: String, value: Double)] {
        emotions.topN(3).filter { $0.value > 0.05 }
    }

    var moodColorHex: String {
        MoodPalette.color(forEmotion: emotions.dominant().name)
    }

    init() {
        let storedPersonality = AppStatePersistence.storedPersonality()
        personality = storedPersonality
        voiceOn = AppStatePersistence.storedVoiceOn()
        interpreter = FoundationModelInterpreter()
        // Robot creation only throws for unknown personality names.
        let robot = (try? Robot(
            personality: storedPersonality,
            clock: ManualClock(),
            interpreter: interpreter
        )) ?? (try! Robot(clock: ManualClock(), interpreter: interpreter))
        self.robot = robot
        emotions = robot.currentEmotions()
        speech = SpeechCoordinator(faceModel: faceModel)
        speech.voiceOn = voiceOn

        if !AppStatePersistence.restore(into: robot, personality: storedPersonality) {
            robot.jostle()
        }
        refreshProjections()
        interpreter.prewarm()
        startTicking()
    }

    // MARK: - Simulation loop

    private func startTicking() {
        tickTask?.cancel()
        lastTick = Date().timeIntervalSinceReferenceDate
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / refreshHz))
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date().timeIntervalSinceReferenceDate
        let dt = max(0, now - lastTick)
        lastTick = now
        robot.advance(dt: dt * speed)
        refreshProjections()
    }

    private func refreshProjections() {
        let state = robot.currentChemicals()
        chemicalLevels = Dictionary(
            uniqueKeysWithValues: Chemical.allCases.map { ($0, state.get($0)) }
        )
        emotions = robot.currentEmotions()
        faceModel.setTargets(
            face: robot.currentFace(),
            moodColorHex: moodColorHex,
            moodIntensity: emotions.dominant().value
        )
    }

    // MARK: - Send pipeline

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let impulses = await robot.process(text: trimmed)
        refreshProjections()

        let quoted = "\u{201C}\(trimmed)\u{201D}"
        switch robot.lastPath {
        case .llm:
            let parts = impulses.map {
                String(format: "%@ %+.2f", $0.chemical.rawValue, $0.delta)
            }
            let effect = parts.isEmpty ? "no impulses" : parts.joined(separator: ", ")
            statusLine = "\(quoted) — LLM OK → \(effect)"
        case .fallback:
            statusLine = "\(quoted) — FALLBACK — \(robot.lastError)"
        case .none:
            statusLine = quoted
        }

        lastReply = robot.lastReply
        if !lastReply.isEmpty {
            speech.speak(lastReply, emotions: robot.currentEmotions())
        }
        save()
    }

    // MARK: - Header actions

    /// Rebuild the robot with fresh, slightly random chemistry and a
    /// fresh conversation + model session. Keeps speed/voice settings.
    func reset() {
        speech.stop()
        interpreter.resetConversation()
        rebuildRobot(personality: personality)
    }

    func setPersonality(_ name: String) {
        guard name != personality, personalityPresets[name] != nil else { return }
        personality = name
        speech.stop()
        interpreter.resetConversation()
        rebuildRobot(personality: name)
        AppStatePersistence.store(personality: name)
    }

    private func rebuildRobot(personality: String) {
        guard let fresh = try? Robot(
            personality: personality,
            clock: ManualClock(),
            interpreter: interpreter
        ) else { return }
        fresh.jostle()
        robot = fresh
        lastReply = ""
        statusLine = ""
        refreshProjections()
        save()
    }

    // MARK: - Persistence

    func save() {
        AppStatePersistence.save(robot: robot, personality: personality, voiceOn: voiceOn)
    }
}
