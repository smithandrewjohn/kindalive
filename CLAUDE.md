# CLAUDE.md — Instructions for Working on Kindalive

## What This Project Is

Kindalive is a robot emotion system that models emotions through simulated neurochemistry. The owner types a paragraph of natural language ("you won the lottery", "Friday, finances up, day off tomorrow"); an LLM interpreter translates that paragraph to chemical impulses, which drive a neurochemical engine. Emotions are computed projections of the chemical state — never stored directly.

## Architecture (Read This First)

Before making any changes, read `docs/architecture.md`. It is the **source of truth** for the entire system. All other docs derive from it.

Key architectural rules that must not be violated:
- Emotions are **computed, never stored**. They are pure functions of `ChemicalState`.
- All chemicals are clamped to `[0.0, 1.0]`. All emotions are clamped to `[0.0, 1.0]`.
- The decay formula is `level += (baseline - level) * (1 - 2^(-dt / half_life))` — true half-life. Do NOT use `e^(-dt/half_life)`.
- The engine sub-steps any `dt > 0.5s` into 0.5s increments for numerical stability. Clamping happens after each sub-step.
- The LLM interpreter returns structured JSON: an object `{"reply": "<spoken line>", "impulses": [ ...impulse dicts... ]}` (a bare impulse array is still accepted for back-compat via `_split_reply_and_impulses`). The parser (`_extract_json_payload` + `_sanitize_json_quirks` in `interpreter/llm_interpreter.py`) tolerates markdown code fences, prose preambles, leading `+` on positive numbers, and trailing commas — but must ultimately yield valid JSON.
- `SeedChemistry` configures a robot's baseline. Personality presets are sugar over `SeedChemistry`.

## Documentation

| File | Role |
|------|------|
| `docs/architecture.md` | Source of truth. System design, formulas, data types, project structure. |
| `docs/web-ui.md` | The only UI — NiceGUI dashboard around the LED dot-matrix face. Layout, features, LLM setup, `.env` auto-loading. |
| `docs/testing-strategy.md` | Test layers with executable code examples. Build order. |
| `docs/llm-benchmark.md` | Scenarios for LLM interpretation quality (pass/fail scorecard). |

## Build Order

Follow the build order in `docs/testing-strategy.md` strictly. Each step is designed so it can be fully tested before the next step begins. Do not skip ahead.

Current status — feature-complete through the face pivot and packaged for open-source release:

- **Input**: a freeform text paragraph through `Robot.interpret_text(...)` or the web UI textarea. The old data fetchers, event batching, scenario generator, and TUIs are gone; `UserText`/`RealtimeRouter` are the only input/router names (no legacy aliases).
- **Face**: 12-muscle `FaceState` projection rendered as a retro LED dot-matrix panel on a 2D canvas (`web_assets/face3d.js` + `face_3d.py`). The full chain — text → LLM → impulses → `ChemicalState` → `FaceState` → renderer payload — is locked by `test_full_pipeline.py::test_text_to_face_payload_chain`.
- **Web UI**: mobile-responsive, installable PWA (manifest + icon in `web_assets/`); `Dockerfile` + `KINDALIVE_HOST`/`$PORT` for always-on hosting. Header Reset rebuilds the robot with a slightly-randomized chemical state (±`RESET_JITTER`=0.22 per chemical, also applied at server start) and a fresh conversation.
- **Voice**: the LLM returns `{"reply", "impulses"}`; `reply` surfaces as `Robot.last_reply`, shows as a 🗣 bubble, is spoken via the browser Web Speech API (mood-mapped rate/pitch, 🔊 toggle, iOS gesture-priming), and drives a lip-sync mouth flap (`setSpeaking`/`mouthPulse`). A bare impulse array is still accepted for back-compat.
- **Memory**: `Robot.conversation` (bounded to `MAX_CONVERSATION_MESSAGES=40`) is fed to the LLM as multi-turn chat via `RobotContext.history`; the paragraph cache is bypassed once a thread is underway.
- **Backends**: `AnthropicBackend` (Claude) and `OpenAICompatBackend` (Ollama/LM Studio/vLLM/OpenAI/OpenRouter).
- **Packaging**: the core (`engine/`, `emotions/`, `expression/face.py`, `Robot`) has **zero third-party dependencies**; NiceGUI and the LLM libraries live in extras (`[web]`, `[anthropic]`, `[openai]`, `[all]`, `[dev]`). MIT licensed. CI (`.github/workflows/ci.yml`) runs tests + the >=80% coverage gate on Python 3.10–3.13, a core-only run on 3.9 (NiceGUI needs 3.10+), and `mypy --strict` — all three must stay green.
- **Hardware**: `examples/` maps `FaceState` to a MAX7219 LED matrix and PCA9685 servos, with terminal fallbacks when the driver libraries aren't installed.

~181 tests passing. Primary UI: `python3 -m kindalive.expression.web_ui`. CLI: `python3 -m kindalive.main --text "..."`.

## Code Conventions

- **Python 3.9+**, asyncio for all I/O
- **Type hints everywhere** — the codebase should pass `mypy --strict`
- **Enum values are lowercase** strings (`Chemical.DOPAMINE.value == "dopamine"`), enum names are uppercase (`Chemical.DOPAMINE`)
- `Chemical.from_string()` is case-insensitive
- Use `engine.advance(dt=...)` to advance simulation time, never `state.tick()`
- The `Robot` class is the top-level API. External code should not touch `NeurochemicalEngine` directly.
- Config lives in TOML files under `config/`. Chemical parameters, emotion weights, personalities — all tunable without code changes.
- Test files mirror source structure: `kindalive/engine/chemicals.py` → `tests/test_chemicals.py`

## Testing

```bash
# Fast unit tests (no API keys, no LLM calls); add --cov for the >=80% gate
pytest tests/ -m "not integration and not llm"

# Strict type check — must be clean (CI enforces it)
mypy

# Full pipeline with mock LLM
pytest tests/test_integration.py

# Property-based tests
pytest tests/test_properties.py

# Live LLM integration (requires ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=xxx pytest tests/ -m llm

# Live LLM benchmark subset (scenario reference: docs/llm-benchmark.md)
ANTHROPIC_API_KEY=xxx pytest tests/test_interpreter/test_freeform_paragraphs.py -v --tb=short
```

Target: **>80% code coverage**, **>90% LLM benchmark PASS rate**.

Use `ManualClock` in all tests — never `time.time()` or `asyncio.sleep()` in the core engine.

## Key Data Types

```python
# The 8 chemicals (engine/chemicals.py)
class Chemical(Enum):
    DOPAMINE, SEROTONIN, OXYTOCIN, TESTOSTERONE,
    CORTISOL, ADRENALINE, ENDORPHINS, GABA

# Impulse from LLM or direct injection (engine/impulse.py)
@dataclass
class ChemicalImpulse:
    chemical: Chemical
    delta: float                    # [-0.5, +0.5]
    duration_seconds: float = 0    # 0 = instant, >0 = sustained drip
    source_id: str = ""
    source_label: str = ""

# The only input — a paragraph the owner typed (interpreter/text_input.py)
@dataclass
class UserText:
    summary: str                   # the paragraph
    timestamp: datetime
    source: str = "user"          # constant
    event_type: str = "freeform"  # constant
    raw_data: dict = {}            # unused
    urgency: str = "realtime"     # constant
# (The legacy `ExternalEvent` alias has been removed.)

# Robot baseline configuration (engine/seed_chemistry.py)
@dataclass
class SeedChemistry:
    baselines: dict[Chemical, float]
    half_life_multipliers: dict[Chemical, float]  # default 1.0
    interaction_scale: float = 1.0                # global interaction coefficient multiplier

# Continuous facial-muscle vector (expression/face.py) — 12 floats in [0,1],
# computed from ChemicalState parallel to EmotionVector. Drives the LED
# dot-matrix face via `face_3d.face_payload(face)` → window.kindaliveFace.
@dataclass(frozen=True)
class FaceState:
    brow_inner_raise: float       # AU1
    brow_outer_raise: float       # AU2
    brow_lower: float             # AU4
    eyelid_upper_raise: float     # AU5
    eyelid_lower_tighten: float   # AU7
    cheek_raise: float            # AU6
    nose_wrinkle: float           # AU9
    lip_corner_pull: float        # AU12
    lip_corner_depress: float     # AU15
    jaw_open: float               # AU26
    lip_pucker: float             # AU18
    lip_press: float              # AU24
```

## Common Pitfalls

1. **Don't use `e^(-dt/half_life)` for decay.** That's not a true half-life. Use `2^(-dt/half_life)`.
2. **Don't apply interactions without sub-stepping.** Large dt values (e.g., 60s in tests) will produce wildly wrong results if you don't sub-step at max 0.5s.
3. **Don't forget clamping order.** Clamp to [0, 1] after ALL interaction rules run in a sub-step, not between individual rules.
4. **Don't test emotions directly against fixed thresholds.** Use relative assertions (`happiness > anxiety`) or wide ranges. The system is designed for emergent behavior — exact values shift as you tune.
5. **Don't scale impulse deltas by dt.** Impulses are discrete events, not rates. Decay and interactions scale by dt; impulses do not.
6. **Saturation uses a 5-minute sliding window**, not a permanent counter. Make sure the counter resets.
7. **The LLM returns lowercase chemical names.** Always use `Chemical.from_string()` for case-insensitive parsing.
8. **Sustained impulses deliver `delta / duration_seconds` per second**, not the full delta up front. The prompt explicitly tells the LLM to default `duration_seconds` to 0 (instant spike) for discrete events. Non-zero durations should only be used for atmospheric/ambient conditions (sunny afternoon, steady rain). Using a large duration on a discrete event (e.g., "won the lottery" with `duration_seconds=60`) makes it ramp instead of spike — counter-intuitive and usually wrong.
9. **Baseline drift is bounded to [0.1, 0.5]** and only applies to cortisol. Don't let it become an unbounded ratchet.
10. **Sadness uses deficit-from-baseline, not `(1 - level)`.** Inverted `EmotionTerm`s compute `max(0, state.baseline(chem) - level)` so sadness only rises when dopamine/serotonin/oxytocin fall *below* their own resting level. At baseline, these terms are exactly zero, and the dominant emotion is calm — never sadness.
11. **Don't use `+` prefix notation in the LLM prompt examples.** JSON forbids leading `+` on positive numbers (`"delta": +0.35` is invalid). Haiku copies prompt notation into its output. Use plain `0.35`, not `+0.35`. The interpreter has a defensive `_sanitize_json_quirks` stripper, but fix the prompt first.
12. **The freeform preamble enforces ONE consolidated impulse array per paragraph.** `PromptBuilder.build_user_prompt` detects `event.source == "user"` and `event.event_type == "freeform"` and prepends a multi-fact framing: the LLM is told to return one array reflecting the net effect of everything in the paragraph, with intensity matched to the strongest fact. The `INTERPRETER_SYSTEM_PROMPT` includes both single-event and multi-fact calibration examples to anchor this.
13. **`LLMInterpreter.last_path` / `last_error` / `last_reply`** are telemetry fields set after every `interpret()` call — `last_path` is `"llm"`, `"cache"`, or `"fallback"`; `last_reply` is the spoken reply (empty on cache/fallback/silent, surfaced as `Robot.last_reply`). The web UI surfaces these in the status label + 🗣 reply bubble. If you see `FALLBACK`, check stderr for `[kindalive.llm]` logs that include the raw response snippet.
14. **Fallback is a single small cortisol nudge** (`source_id="fallback:freeform"`). It does not interpret the paragraph — it just registers that *something* happened so the robot doesn't go numb when the LLM is down.

## When Modifying Formulas or Coefficients

If you change emotion weights, interaction coefficients, or chemical parameters:
1. Update `docs/architecture.md` first (source of truth)
2. Update the corresponding TOML config file
3. Run the full test suite — especially property tests and emotion projection tests
4. Run the LLM benchmark to check for regressions (>90% PASS required)
5. Check that baseline neutrality expectations still hold (test_default_state_is_neutral)
6. Regenerate the Swift parity fixtures (`python3 scripts/generate_swift_fixtures.py`)
   and update the mirrored constant in `ios/KindaliveKit/Sources/KindaliveKit/`.
   The Swift weight/coefficient tables mirror the Python modules the same way the
   TOMLs do — Python stays authoritative. See `docs/ios-app.md`.

## Project Structure

```
kindalive/
├── engine/          # Core simulation: chemicals, decay, impulses, interactions
├── emotions/        # Emotion projection from chemical state
├── interpreter/     # text_input (UserText), llm_interpreter, prompt_builder,
│                    # cache, validator, fallback_rules, event_router
│                    # (RealtimeRouter), anthropic_backend, openai_backend
├── personality/     # Presets, seed chemistry config
├── expression/      # web_ui (NiceGUI, the only UI), text_output,
│                    # face (12-muscle FaceProjection), face_3d (payload +
│                    # boot wiring), web_assets/face3d.js (LED dot-matrix face)
├── persistence/     # Serialize/deserialize/save/load state
├── config/          # TOML config files (chemicals, emotions, personalities, interpreter, face)
├── env_loader.py    # Dependency-free .env loader
├── robot.py         # Top-level Robot (process_event + interpret_text)
└── main.py          # Freeform CLI: `python -m kindalive.main --text "..."`

examples/            # FaceState → real hardware (MAX7219 LED matrix,
│                    # PCA9685 servos), terminal fallbacks, own README
ios/                 # Native iOS app (docs/ios-app.md): KindaliveKit —
│                    # pure-Swift engine port locked to Python by golden
│                    # fixtures — plus a SwiftUI app using on-device
│                    # Apple Intelligence (FoundationModels, iOS 26+)
scripts/generate_swift_fixtures.py  # Python engine → golden parity JSON
.github/workflows/   # CI: tests + coverage gate, py3.9 core run, mypy --strict

tests/
├── conftest.py
├── test_chemicals.py / test_seed_chemistry.py / test_saturation.py /
│   test_interactions.py / test_emotion_projection.py / test_expression.py /
│   test_integration.py / test_properties.py / test_persistence.py /
│   test_env_loader.py / test_web_ui.py / test_face.py / test_face_3d.py
└── test_interpreter/
    ├── test_validator.py / test_fallback_rules.py / test_impulse_cache.py
    ├── test_prompt_builder.py / test_llm_interpreter.py
    ├── test_openai_backend.py / test_event_router.py / test_full_pipeline.py
    ├── test_freeform_prompt.py     # multi-fact preamble + calibration examples
    └── test_freeform_paragraphs.py # live LLM benchmark (gated on ANTHROPIC_API_KEY)
```
