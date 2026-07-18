# Kindalive for iOS — Native App with On-Device Apple Intelligence

A native iOS port of Kindalive that runs the entire pipeline on the
phone: Apple's **Foundation Models framework** (the on-device Apple
Intelligence model, iOS 26+) interprets what you type, a line-faithful
Swift port of the neurochemical engine feels it, and the LED dot-matrix
face + synthesized voice express it. **No network, no API keys** — the
model, the chemistry, and the voice all run on-device.

The Python package under `kindalive/` remains the **source of truth**
for every formula. The Swift port is locked to it by golden fixtures
(see [Parity: the fixture workflow](#parity-the-fixture-workflow)).

## Requirements

- **Xcode 26** on macOS (Tahoe) or newer
- **iOS 26** deployment target
- An **Apple Intelligence-capable device** (iPhone 15 Pro or later /
  M-series iPad) with Apple Intelligence enabled in Settings.
  The simulator works if the host Mac has Apple Intelligence enabled.
- On non-eligible devices the app still runs: every message takes the
  same fallback path as the Python version (a small cortisol nudge +
  a status notice) instead of a real interpretation.

## Building

```bash
open ios/Kindalive.xcodeproj
```

1. Select the **KindaliveKit** scheme → **⌘U**. This runs the full unit
   + fixture-parity suite — the numerical gate proving the Swift core
   matches the Python engine. Any red test names the exact formula that
   diverged.
2. Select the **Kindalive** scheme → **Run** on your device.

The project file was authored by hand (this repo is developed without
Xcode in the loop). If Xcode ever refuses to open it, regenerate an
equivalent project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd ios && xcodegen generate
```

The core also builds on Linux (`cd ios/KindaliveKit && swift test`)
since it depends on Foundation only.

## Layout

```
ios/
├── KindaliveKit/            # Pure-Swift core (SwiftPM package, Linux-testable)
│   ├── Sources/KindaliveKit/
│   │   ├── Engine/          # Chemicals, decay, impulses, interactions,
│   │   │                    # saturation, seed chemistry, clocks
│   │   ├── Emotions/        # EmotionVector + projection weights
│   │   ├── Expression/      # FaceState, face projection, FaceGeometry
│   │   ├── Interpreter/     # UserText, protocol, context, validator,
│   │   │                    # fallback, model instructions
│   │   ├── Personality/     # The 4 presets
│   │   ├── Persistence/     # Python-compatible version-1 JSON state
│   │   ├── Voice/           # Mood → rate/pitch mapping
│   │   └── Robot.swift      # Top-level API (same shape as Python Robot)
│   └── Tests/KindaliveKitTests/   # Unit tests + FixtureParityTests + Fixtures/
├── KindaliveApp/            # iOS app (SwiftUI, FoundationModels, AVFoundation)
│   ├── Interpreter/         # @Generable types + FoundationModelInterpreter
│   ├── Face/                # FaceRenderModel + Canvas LED renderer
│   ├── Speech/              # AVSpeechSynthesizer + lip sync
│   ├── Views/               # Dashboard views
│   └── Persistence/         # Documents/robot_state.json + UserDefaults
├── Kindalive.xcodeproj/     # Hand-authored Xcode 16-format project
└── project.yml              # XcodeGen fallback spec
```

## Architecture mapping

| Python (authoritative) | Swift |
|---|---|
| `engine/chemicals.py` | `Engine/Chemical.swift`, `Engine/ChemicalState.swift` |
| `engine/impulse.py` | `Engine/ChemicalImpulse.swift` |
| `engine/interactions.py` | `Engine/Interactions.swift` |
| `engine/neurochemical_engine.py` | `Engine/NeurochemicalEngine.swift` |
| `engine/seed_chemistry.py` | `Engine/SeedChemistry.swift` |
| `engine/clock.py` | `Engine/Clock.swift` |
| `emotions/` | `Emotions/` |
| `expression/face.py` | `Expression/FaceState.swift`, `FaceProjection.swift` |
| `web_assets/face3d.js` (shape math) | `Expression/FaceGeometry.swift` (fixture-locked) |
| `web_assets/face3d.js` (renderer) | `KindaliveApp/Face/` (Canvas + TimelineView) |
| `interpreter/prompt_builder.py` | `Interpreter/InterpreterInstructions.swift`, `RobotContext.swift` |
| `interpreter/validator.py` | `Interpreter/ImpulseValidator.swift` |
| `interpreter/fallback_rules.py` | `Interpreter/FallbackInterpreter.swift` |
| `interpreter/llm_interpreter.py` + backends | `KindaliveApp/Interpreter/FoundationModelInterpreter.swift` |
| `personality/presets.py` | `Personality/Presets.swift` |
| `persistence/state_store.py` | `Persistence/StateStore.swift` |
| `expression/web_ui.py` (`_voice_params`, palettes, jitter) | `Voice/VoiceParams.swift`, `MoodPalette.swift`, `Robot.jostle` |
| `robot.py` | `Robot.swift` |

## The on-device interpreter

Where the Python interpreter asks Claude for JSON and repairs whatever
comes back (`_extract_json_payload`, `_sanitize_json_quirks`), the iOS
interpreter uses **guided generation**: `@Generable` Swift types with
`@Guide` constraints, so the framework itself guarantees valid chemical
names and bounded deltas — no JSON parsing at all.

```swift
@Generable
struct RobotTurn {
    @Guide(description: "One short spoken sentence…")
    var reply: String
    @Guide(description: "0 to 8 impulses…", .maximumCount(8))
    var impulses: [GeneratedImpulse]
}

let turn = try await session.respond(
    to: prompt, generating: RobotTurn.self,
    options: GenerationOptions(temperature: 0)
).content
```

Key design points (see `FoundationModelInterpreter.swift`):

- **Instructions** are adapted from `INTERPRETER_SYSTEM_PROMPT`: role
  framing, the 8 chemical descriptions, the intensity scale, the
  duration-0 rule, and the calibration examples survive; the JSON-format
  rules are dropped (obsolete under guided generation). The freeform
  multi-fact preamble is folded in, since every turn is an owner
  paragraph.
- **Per-turn context**: personality · affinity · dominant mood · top-4
  chemicals rides in each prompt (it changes every turn), mirroring
  `PromptBuilder.build_user_prompt`.
- **Conversation memory** lives in the `LanguageModelSession` transcript
  natively — history is not replayed into prompts. `Robot.conversation`
  (bounded to 40 messages, same as Python) remains the UI-facing record.
- **Context overflow**: the on-device ~3B model has a small window.
  After 20 exchanges the session is proactively rebuilt with a short
  recap of the last 3 exchanges; `exceededContextWindowSize` triggers
  the same rebuild reactively with one retry.
- **Availability**: `SystemLanguageModel.default.availability` gates the
  whole path. Ineligible device / Apple Intelligence off / model still
  downloading → every turn returns the Python-identical fallback (single
  cortisol +0.05, `source_id "fallback:freeform"`) and the header badge
  + status line say why.
- **Validation stays**: guided generation guarantees shape, but the Kit
  validator (max 8 impulses, delta/duration clamps, unknown-chemical
  skip) remains in the loop as defense in depth.

### Deliberate deviations from Python

- **No impulse cache.** On-device inference has no per-call cost, and
  the Python cache is bypassed whenever conversation history exists
  anyway. Consequently there is no `cache` status path — only `llm` and
  `fallback`.
- **AVSpeech rate mapping.** Kit's `VoiceParams.rate` keeps the web's
  1.0-centered multiplier semantics; the app maps it as
  `AVSpeechUtteranceDefaultSpeechRate * rate` because
  `AVSpeechUtterance.rate` is an absolute 0–1 scale. Expect one tuning
  pass by ear.
- **Time speed** (1×/10×/60×) uses the web UI's ManualClock +
  scaled-dt tick pattern rather than a separate clock type.

## Parity: the fixture workflow

`scripts/generate_swift_fixtures.py` runs the **Python** engine through
deterministic scenarios (seeded RNG, `ManualClock`) and writes golden
JSON to `ios/KindaliveKit/Tests/KindaliveKitTests/Fixtures/`. The Swift
`FixtureParityTests` load them and assert near-equality (1e-9 for
single-formula cases, 1e-6 for long trajectories).

**If you change any formula, weight, or coefficient in Python** (after
updating `docs/architecture.md` and the TOML mirror, per CLAUDE.md):

```bash
python3 scripts/generate_swift_fixtures.py   # regenerate goldens
# then update the mirrored constant in ios/KindaliveKit/Sources/… and
# re-run the Swift tests (⌘U on KindaliveKit, or `swift test` on Linux)
```

The Swift weight tables mirror the Python modules the same way the TOML
config files do: Python is authoritative, the mirrors are transcriptions.

## Manual verification script

On a device with Apple Intelligence:

1. At rest the face blinks, glances around, and its glow breathes.
2. Type "you won the lottery" → eyes widen, brows raise, big grin;
   dopamine/adrenaline bars spike; the accent color shifts; the robot
   speaks a reply with the mouth flapping in sync with the words.
3. Switch time to 60× → chemistry decays, the face relaxes toward calm.
4. Type "the cat is missing and a storm is rolling in" → inner brows
   rise, lip corners depress, cortisol climbs.
5. Settings → disable Apple Intelligence (or use a simulator without
   it) → the badge shows `offline — …`, sends show `FALLBACK`, and
   cortisol nudges up by 0.05.
6. Background the app, relaunch → the mood is restored
   (`Documents/robot_state.json`, loadable by the Python
   `persistence.load_state` too).
7. Switch personality to `anxious`, repeat (2) — same event, twitchier
   robot (higher cortisol baseline, 1.3× interactions).

## Known API-surface caveats

Written against the iOS 26 SDK as documented at the time of the port;
double-check in Xcode if the compiler disagrees:

- `@Guide` constraint spellings (`.range(_:)`, `.maximumCount(_:)`).
- `SystemLanguageModel.Availability.UnavailableReason` case names
  (`.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`).
- `LanguageModelSession.GenerationError.exceededContextWindowSize`.
- If the instructions + examples crowd the small context window, trim
  the calibration examples in `InterpreterInstructions.swift` to ~6
  (keep the extremes and one multi-fact example) — that is the first
  tuning knob, mirroring pitfall #2 in `docs/llm-benchmark.md`.

No entitlements, usage-description strings, or API keys are required:
Foundation Models needs no entitlement, and speech *synthesis* (unlike
recognition) needs no permission.
