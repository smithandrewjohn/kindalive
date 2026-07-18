// AppStatePersistence — save/restore the robot's mood across launches.
//
// The engine snapshot goes to Documents/robot_state.json in the Python
// version-1 format (cross-loadable by the Python `load_state`); UI
// preferences (personality, voice) go to UserDefaults. Conversation is
// session-only, matching the web UI.

import Foundation
import KindaliveKit

enum AppStatePersistence {
    private static let personalityKey = "kindalive.personality"
    private static let voiceKey = "kindalive.voiceOn"

    private static var stateURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("robot_state.json")
    }

    static func storedPersonality() -> String {
        let name = UserDefaults.standard.string(forKey: personalityKey) ?? "default"
        return personalityPresets[name] != nil ? name : "default"
    }

    static func storedVoiceOn() -> Bool {
        UserDefaults.standard.object(forKey: voiceKey) as? Bool ?? true
    }

    static func store(personality: String) {
        UserDefaults.standard.set(personality, forKey: personalityKey)
    }

    static func save(robot: Robot, personality: String, voiceOn: Bool) {
        UserDefaults.standard.set(personality, forKey: personalityKey)
        UserDefaults.standard.set(voiceOn, forKey: voiceKey)
        if let data = try? StateStore.encode(robot.snapshot()) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    /// Restore the saved mood into `robot`. Returns false (leaving the
    /// robot untouched) when there is no saved state or it was saved for
    /// a different personality.
    static func restore(into robot: Robot, personality: String) -> Bool {
        guard storedPersonality() == personality,
              let data = try? Data(contentsOf: stateURL),
              let snapshot = try? StateStore.decode(data),
              (try? robot.restore(snapshot)) != nil
        else {
            return false
        }
        return true
    }
}
