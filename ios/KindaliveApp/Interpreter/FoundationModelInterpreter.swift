// FoundationModelInterpreter — the on-device replacement for the Python
// LLMInterpreter, backed by Apple's Foundation Models framework.
//
// Differences from the Python pipeline, by design:
// - Guided generation (RobotTurn) replaces JSON extraction/sanitizing.
// - No impulse cache: on-device inference is free, and Python bypasses
//   the cache mid-conversation anyway.
// - Conversation memory lives in the LanguageModelSession transcript,
//   not in replayed prompt history. On context overflow (the on-device
//   model's window is small) the session is rebuilt with a short recap
//   of recent exchanges and the turn is retried once.
// - When the model is unavailable (ineligible device, Apple Intelligence
//   off, model still downloading) every turn takes the same fallback
//   path as Python: a single small cortisol nudge plus a status notice.

import Foundation
import FoundationModels
import KindaliveKit

/// Rebuild the session proactively after this many exchanges, mirroring
/// the Python MAX_CONVERSATION_MESSAGES = 40 bound (an exchange is 2
/// messages).
private let maxSessionExchanges = maxConversationMessages / 2

/// How many recent exchanges to replay as a recap into a fresh session.
private let recapExchanges = 3

final class FoundationModelInterpreter: ImpulseInterpreter {
    /// "" when the model is available; otherwise a human-readable reason
    /// shown in the status line.
    private(set) var availabilityNotice: String
    private var session: LanguageModelSession?
    private var exchangeCount = 0
    private var recentExchanges: [(userText: String, reply: String)] = []

    init() {
        switch SystemLanguageModel.default.availability {
        case .available:
            availabilityNotice = ""
        case .unavailable(let reason):
            availabilityNotice = Self.describe(reason)
        }
        if availabilityNotice.isEmpty {
            session = Self.makeSession(recap: "")
        }
    }

    /// Warm the model so the first turn doesn't pay full load latency.
    func prewarm() {
        session?.prewarm()
    }

    /// Drop the transcript (personality switch / Reset). Also re-checks
    /// availability — the model may have finished downloading since launch.
    func resetConversation() {
        exchangeCount = 0
        recentExchanges = []
        switch SystemLanguageModel.default.availability {
        case .available:
            availabilityNotice = ""
        case .unavailable(let reason):
            availabilityNotice = Self.describe(reason)
        }
        session = availabilityNotice.isEmpty ? Self.makeSession(recap: "") : nil
    }

    func interpret(_ event: UserText, context: RobotContext) async -> InterpreterResult {
        guard availabilityNotice.isEmpty, session != nil else {
            return await FallbackInterpreter(reason: availabilityNotice)
                .interpret(event, context: context)
        }

        // Proactive refresh before the small context window overflows.
        if exchangeCount >= maxSessionExchanges {
            rebuildSessionWithRecap()
        }

        let prompt = InterpreterInstructions.turnPrompt(context: context, text: event.summary)
        do {
            return try await respond(to: prompt, event: event, context: context)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                // Reactive refresh + one retry.
                rebuildSessionWithRecap()
                if let retried = try? await respond(to: prompt, event: event, context: context) {
                    return retried
                }
            }
            return await fallback(for: event, context: context, error: "\(error)")
        } catch {
            return await fallback(for: event, context: context, error: "\(error)")
        }
    }

    private func respond(
        to prompt: String,
        event: UserText,
        context: RobotContext
    ) async throws -> InterpreterResult {
        guard let session else {
            throw KindaliveError.validation("no session")
        }
        let turn = try await session.respond(
            to: prompt,
            generating: RobotTurn.self,
            options: GenerationOptions(temperature: 0)
        ).content

        // Guided generation already constrains names and ranges; the Kit
        // validator stays in the loop as defense in depth (count bound,
        // clamps), exactly like the Python pipeline.
        let raw = turn.impulses.map {
            RawImpulse(
                chemical: $0.chemical.rawValue,
                delta: $0.delta,
                durationSeconds: $0.durationSeconds
            )
        }
        let impulses = try validateRawImpulses(raw)

        exchangeCount += 1
        recentExchanges.append((event.summary, turn.reply))
        if recentExchanges.count > recapExchanges {
            recentExchanges.removeFirst(recentExchanges.count - recapExchanges)
        }
        return InterpreterResult(reply: turn.reply, impulses: impulses, path: .llm)
    }

    private func fallback(
        for event: UserText,
        context: RobotContext,
        error: String
    ) async -> InterpreterResult {
        await FallbackInterpreter(reason: error).interpret(event, context: context)
    }

    private func rebuildSessionWithRecap() {
        session = Self.makeSession(recap: InterpreterInstructions.recap(recentExchanges))
        exchangeCount = 0
    }

    private static func makeSession(recap: String) -> LanguageModelSession {
        let instructions = recap.isEmpty
            ? InterpreterInstructions.text
            : InterpreterInstructions.text + "\n\n" + recap
        return LanguageModelSession(instructions: instructions)
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "device not eligible for Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled in Settings"
        case .modelNotReady:
            return "on-device model still downloading — try again soon"
        @unknown default:
            return "on-device model unavailable"
        }
    }
}
