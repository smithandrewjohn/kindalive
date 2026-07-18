# Kindalive — Robot Emotion Architecture

## Overview

Kindalive models robot emotions as **emergent states from simulated neurochemistry**, not as discrete labels. There is no `mood = "happy"` variable. Instead, the robot maintains concentrations of simulated neurochemicals (dopamine, cortisol, oxytocin, etc.), and emotions are read-only projections derived from that chemical state — just like in biology.

This means complex, mixed emotional states emerge naturally. A robot can be excited *and* anxious simultaneously (high adrenaline + high cortisol) without anyone writing a rule for that combination.

---

## System Architecture

```
┌─────────────────────────────────────────────────┐
│              User typed paragraph                │
│  "you won the lottery"                          │
│  "Friday, finances up, day off tomorrow"        │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│           LLM Interpreter                        │
│  • Receives a UserText paragraph + personality   │
│  • Returns structured ChemicalImpulse[]          │
│  • Caches exact-paragraph repeats                │
│  • Falls back to a small cortisol nudge if down  │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│           Neurochemical Engine                   │
│  • Validates & applies impulses                  │
│  • Runs decay simulation (tick-based)            │
│  • Evaluates chemical interactions               │
│  • Manages baseline drift                        │
└────────────┬───────────────────┬────────────────┘
             │                   │
             ▼                   ▼
┌──────────────────────┐ ┌──────────────────────┐
│  Emotion Projection  │ │  Face Projection     │
│  • 8 emotions from   │ │  • 12 FACS muscles   │
│    chemical state    │ │    from chemical     │
│  • dominant mood +   │ │    state             │
│    accent color      │ │                      │
└──────────┬───────────┘ └──────────┬───────────┘
           │                        │
           ▼                        ▼
┌─────────────────────────────────────────────────┐
│          Expression Layer (web UI)               │
│  • emotion-mix + chemical bars                   │
│  • face_payload → setTargets → lerped muscles    │
│    → LED dot-matrix canvas, ~60 fps             │
└─────────────────────────────────────────────────┘
```

### The chain, end to end

Every link in this chain is exercised by
`tests/test_interpreter/test_full_pipeline.py::test_text_to_face_payload_chain`:

```
text paragraph
  → LLM interpreter            (UserText → ChemicalImpulse[])
  → NeurochemicalEngine        (impulses + decay + interactions → ChemicalState)
  → EmotionProjection          (state → 8 emotions → dominant mood accent)
  → FaceProjection             (state → 12-muscle FaceState)
  → face_payload / setTargets  (FaceState + mood → JSON pushed at 10 Hz)
  → face3d.js                  (lerp → muscle-driven dot grid → 2D-canvas render)
```

Emotions and the face are **parallel projections from the same
ChemicalState** — the face is not derived from the emotion labels, so
mixed states show up as blended muscle activations rather than a
quantized mood mask.

---

## Layer 1: Neurochemical Engine (The "Body")

The core simulation. Maintains a vector of chemical concentrations that evolve over time through impulses, decay, and cross-chemical interactions.

### Chemicals

| Chemical       | Role                              | Half-life | Baseline |
|----------------|-----------------------------------|-----------|----------|
| **Dopamine**   | Reward, motivation, pleasure      | ~20 min   | 0.3      |
| **Serotonin**  | Mood stability, well-being        | ~4 hrs    | 0.5      |
| **Oxytocin**   | Trust, bonding, affection         | ~30 min   | 0.2      |
| **Testosterone** | Competitiveness, energy, drive  | ~2 hrs    | 0.3      |
| **Cortisol**   | Stress, alertness                 | ~1 hr     | 0.2      |
| **Adrenaline** | Excitement, fight-or-flight       | ~3 min    | 0.1      |
| **Endorphins** | Euphoria, sustained positivity    | ~30 min   | 0.2      |
| **GABA**       | Calm, relaxation, inhibition      | ~1 hr     | 0.4      |

All concentrations are clamped to the range `[0.0, 1.0]`.

**Naming convention:** The Python enum uses uppercase (`Chemical.GABA`, `Chemical.DOPAMINE`), but the LLM-facing interfaces (prompts, JSON responses, config files) use lowercase (`gaba`, `dopamine`). The `Chemical` enum has a `.value` property returning the lowercase string, and a `from_string()` class method that accepts case-insensitive input.

Half-lives are tuned for *interesting robot behavior*, not biological accuracy. Adrenaline fades in minutes (so excitement from a goal is fleeting). Serotonin moves slowly (so a nice day has a long-lasting background effect).

### Decay

Each chemical decays toward its baseline exponentially:

```
level += (baseline - level) * (1 - 2^(-dt / half_life))
```

This is a true half-life: after `half_life` seconds, the gap between the current level and baseline closes by exactly 50%. Chemicals above baseline decay down, chemicals below baseline recover up.

### Cross-Chemical Interactions

After decay, interaction rules run. These model how chemicals affect each other.

**Important implementation details:**
- The engine **sub-steps** large time intervals: if `dt > 0.5s`, the engine internally subdivides into steps of at most 0.5s. This ensures numerical stability — interaction results are consistent regardless of whether time advances as one big step or many small ones.
- **Clamping to [0, 1] happens after each sub-step** (after all interaction rules run), not between individual rules. This prevents chemicals from going negative mid-tick.

**Equilibrium principle.** Every interaction term is written so it **vanishes when the relevant chemical is at baseline**. This makes the all-baseline resting state a true fixed point — at rest nothing drifts. Interactions couple *perturbations* (deviations from baseline), not absolute levels. Notation: `excess(x) = max(0, x − baseline_x)`.

| Rule | Effect | Rationale |
|------|--------|-----------|
| Excess cortisol erodes serotonin | `serotonin -= excess(cortisol) * 0.03 * dt` | Stress erodes well-being over time |
| GABA dampens adrenaline's excess | `adrenaline -= GABA * 0.15 * excess(adrenaline) * dt` | Calm restores arousal toward rest |
| Adrenaline's excess inhibits GABA | `GABA -= excess(adrenaline) * 0.30 * max(0, GABA − floor) * dt` | Hard to stay calm when amped up |
| Excess testosterone amplifies adrenaline | `adrenaline += excess(testosterone) * 0.015 * dt` | Competitiveness fuels excitement |
| Oxytocin relieves cortisol's excess | `cortisol -= oxytocin * 0.30 * excess(cortisol) * dt` | Bonding reduces stress |
| Sustained cortisol raises baseline | `cortisol_baseline += 0.001 * dt` (if cortisol > 0.7) | Chronic stress shifts resting state |
| Sustained low cortisol lowers baseline | `cortisol_baseline -= 0.0005 * dt` (if cortisol < 0.15) | Recovery from chronic stress |

Baseline drift is clamped to `[0.1, 0.5]` — baseline can shift but not to absurd extremes. The recovery threshold (0.15) sits *below* the resting cortisol baseline (0.2) so it only fires during a genuinely sustained low-cortisol stretch, not at normal rest.

**Why the deviation-from-baseline form matters.** The chemicals have very different decay timescales (adrenaline ~3 min, cortisol ~1 h, serotonin ~4 h). An earlier version used constant pushes toward zero (e.g. `cortisol -= oxytocin * 0.08`); because cortisol/GABA recover toward baseline far more slowly than those pushes drained them, they got **pinned at 0**. That removed adrenaline's GABA damping and let testosterone ratchet adrenaline to 1.0 (adrenaline "maxed out"), while oxytocin + baseline drift drove cortisol to its floor (cortisol "minimized out"). Gating each rule on `excess()` — and inhibiting GABA only down to a floor (half its baseline) so adrenaline's brake is never fully stripped — eliminates both runaways while preserving every rule's direction.

### Saturation

Repeated similar impulses have diminishing returns. The engine tracks recent impulse sources with a **sliding time window** (5 minutes) and applies a dampening factor:

```
effective_delta = delta * (1 / (1 + recent_impulse_count_in_window * 0.3))
```

The 5th goal in a blowout doesn't hit like the 1st. But if an hour passes between goals, the saturation counter resets and the next goal hits fresh.

### Impulse Structure

```python
@dataclass
class ChemicalImpulse:
    chemical: Chemical
    delta: float                        # signed magnitude of change
    duration_seconds: float = 0         # 0 = instant spike, >0 = sustained release
    source_id: str = ""                 # for saturation tracking and debugging
    source_label: str = ""              # human-readable description

# Convenience alias used in fallback rules and tests
Impulse = ChemicalImpulse
```

For sustained-duration impulses (`duration_seconds > 0`), the engine applies `delta / duration_seconds` per second over the duration, rather than applying the full delta instantly. This models the difference between a sudden shock and a slow drip (e.g., oxytocin from owner proximity over minutes).

### Simulation Timing

**Hybrid event-driven + tick-based.** The engine runs a decay/interaction sweep every **100ms** (10 Hz). Impulses are applied as they arrive between ticks. This balances responsiveness with efficiency — decay needs regular updates, but we don't waste cycles when nothing is happening.

For testing, the engine accepts a `Clock` interface so time can be controlled explicitly. No `time.sleep()` in the core — the test harness advances time manually.

---

## Layer 2: Emotion Projection (The "Mind")

Emotions are **computed, never stored**. They are pure functions of the current chemical state.

### Emotion Formulas

Each emotion is a weighted linear combination of chemical levels:

| Emotion       | Formula | Theoretical range |
|---------------|---------|-------------------|
| **Happiness** | `0.35 * dopamine + 0.35 * serotonin + 0.15 * endorphins + 0.15 * oxytocin - 0.2 * cortisol` | [-0.20, 1.00] |
| **Excitement**| `0.45 * adrenaline + 0.35 * dopamine + 0.20 * testosterone` | [0.00, 1.00] |
| **Anger**     | `0.35 * testosterone + 0.35 * cortisol + 0.30 * adrenaline - 0.30 * GABA` | [-0.30, 1.00] |
| **Calm**      | `0.45 * GABA + 0.35 * serotonin + 0.20 * oxytocin - 0.25 * adrenaline - 0.15 * cortisol` | [-0.40, 1.00] |
| **Bonding**   | `0.50 * oxytocin + 0.30 * serotonin + 0.20 * endorphins` | [0.00, 1.00] |
| **Anxiety**   | `0.40 * cortisol + 0.35 * adrenaline + 0.25 * testosterone - 0.35 * GABA - 0.15 * serotonin` | [-0.50, 1.00] |
| **Sadness**   | `0.60 * cortisol + 0.50 * deficit(dopamine) + 0.40 * deficit(serotonin) + 0.40 * deficit(oxytocin)` | [0.00, 1.00] |
| **Euphoria**  | `0.30 * dopamine + 0.30 * endorphins + 0.20 * adrenaline + 0.20 * oxytocin` | [0.00, 1.00] |

All results are clamped to `[0.0, 1.0]`.

**Design notes on formula balance:**
- Every emotion can reach 1.0 under the right conditions, so no emotion is systematically suppressed.
- Sadness uses `deficit(x) = max(0, baseline_x - x)` for the positive chemicals, so it activates on *absence* of dopamine, serotonin, or oxytocin relative to the robot's own normal resting level. This means isolation + depleted dopamine = sadness, even without high stress. At baseline, the deficit terms are exactly zero, so a neutral robot is not sad — only elevated cortisol contributes.
- At baseline chemical values, positive emotions (happiness, calm, bonding) sit around 0.20–0.40, negative emotions (anger, anxiety, sadness) sit at or below 0.15. The dominant emotion at rest is calm. This reflects a healthy resting state — not happy, not sad, just quietly neutral.

These weights are the primary tuning knobs for "does the robot feel right?" They live in a config file so they can be adjusted without code changes.

### Dominant Emotion

The emotion with the highest value at any moment is the **dominant emotion** — the one most visible in behavior. But the full vector is always available for nuanced expression.

---

## Layer 3a: Freeform Text Input (The "Sense")

The only input to the system is a paragraph of natural language the
owner typed. There is no polling, no batching, no API integrations —
the project deliberately stripped the sports/weather/news/finance
fetchers and the realtime/background event router because the freeform
path was the only one that earned its keep. A paragraph can describe a
single event ("you won the lottery"), several stacked events, or a mix
of discrete events and ambient conditions ("Friday, finances up, day
off tomorrow").

### UserText Structure

```python
@dataclass
class UserText:
    summary: str               # the paragraph the owner typed
    timestamp: datetime         # default: now
    source: str = "user"       # constant
    event_type: str = "freeform"  # constant
    raw_data: dict = {}        # unused
    urgency: str = "realtime"  # constant — every paragraph is interpreted now
```

The `source` / `event_type` constants exist because the prompt builder
and cache key on them. The legacy `ExternalEvent` alias has been
removed — `UserText` is the only input type.

The `summary` field is what the LLM sees. The freeform-paragraph
preamble in `prompt_builder.py` instructs the model to return one
consolidated impulse array reflecting the net effect of everything in
the paragraph, with intensity matched to the strongest fact.

---

## Layer 3b: LLM Interpreter (The "Intuition")

This is the key architectural change: instead of hand-coding emotional mappings for every possible event, **an LLM interprets events and produces chemical impulses**. This solves the combinatorial explosion problem — you don't need rules for every type of sports play, weather pattern, or headline. The LLM generalizes.

### Why LLM Instead of Hand-Coded Rules

| | Hand-coded rules | LLM interpreter |
|---|---|---|
| **Coverage** | Only handles paragraphs you anticipated | Handles anything expressible in natural language |
| **Context** | Rules are stateless and generic | Can factor in robot personality and current mood |
| **Multi-fact paragraphs** | Hard to compose without combinatorial rules | One consolidated impulse array, intensity matched to the strongest fact |
| **Nuance** | "I won" always maps the same way | "I won the lottery" vs "I won a free coffee" get different impulses |
| **Maintenance** | Grows linearly with phrasings | One prompt to maintain |

### How It Works

```
UserText
    ↓
┌─────────────────────────────────────────────┐
│  1. Check impulse cache (keyed on event     │
│     type + normalized summary)              │
│     → Cache HIT: return cached impulses     │
│     → Cache MISS: continue to step 2        │
├─────────────────────────────────────────────┤
│  2. Build LLM prompt:                       │
│     • System: chemical defs, intensity scale│
│       (0.05–0.50), JSON format rules,       │
│       9 calibration examples                │
│     • Context: robot personality, current    │
│       chemical state, affinity              │
│     • Event: the UserText summary       │
│     • (If source=user, event_type=freeform:  │
│       add owner-speaking preamble)           │
├─────────────────────────────────────────────┤
│  3. Call LLM (Claude Haiku via Anthropic)   │
│     → Returns raw text response             │
├─────────────────────────────────────────────┤
│  4. Parse & sanitize (see below):           │
│     • Strip markdown code fences            │
│     • Skip prose preambles                  │
│     • Fix leading + on positive numbers     │
│     • Fix trailing commas                   │
│     → json.loads → raw dicts                │
├─────────────────────────────────────────────┤
│  5. Validate: clamp deltas [-0.5, 0.5],     │
│     clamp duration [0, 300], resolve        │
│     chemical names via from_string()        │
│     → ChemicalImpulse[]                     │
├─────────────────────────────────────────────┤
│  6. Cache result for similar future events  │
├─────────────────────────────────────────────┤
│  On ANY failure (parse, validate, network): │
│  → Log to stderr with raw response snippet  │
│  → Set last_path="fallback", last_error=msg │
│  → Return heuristic impulses from           │
│    fallback_rules.py (14 rules by event key,│
│    default = cortisol +0.05 for unknown)    │
└─────────────────────────────────────────────┘
    ↓
ChemicalImpulse[]
```

### The Prompt

The system prompt teaches the LLM the chemical model, provides an explicit intensity scale with 9 calibrated examples, and includes strict JSON formatting rules. Key design lessons learned:

- **No `+` prefix on positive numbers** in examples. JSON forbids leading `+`; Haiku copies prompt notation into its output. Write `0.35`, not `+0.35`.
- **Default `duration_seconds` to 0** for discrete events. Sustained durations are reserved for ambient conditions only (sunny afternoon, steady rain). A sustained impulse spreads `delta / duration_seconds` per tick, so non-zero duration makes the effect *slower*, not stronger.
- **Freeform preamble**: when `event.source == "user"` and `event.event_type == "freeform"`, the user prompt prepends a frame that the robot's *owner* is speaking directly, encouraging proportional intensity instead of timid 0.05 nudges.

See `kindalive/interpreter/prompt_builder.py` for the full prompt text. The architecture doc does not duplicate it to avoid drift.

### JSON Parse Robustness

The `_extract_json_payload` + `_sanitize_json_quirks` functions in `llm_interpreter.py` handle three common LLM output deviations:

1. **Markdown code fences** — `\`\`\`json ... \`\`\`` wrappers stripped by regex.
2. **Prose preambles** — "Here is the response:" followed by JSON; the parser locates the first `[` or `{`.
3. **JSON syntax quirks** — leading `+` on positive numbers (`"delta": +0.35`) and trailing commas (`[{...},]`) are repaired with narrow regexes that use lookbehinds to avoid corrupting `+` characters inside string values.

### Fallback Rules

When the LLM is unavailable or its response fails to parse, `fallback_rules.py` supplies a single small cortisol nudge (`delta=0.05`, `source_id="fallback:freeform"`). It does not attempt to interpret the paragraph — it just registers that *something* happened so the robot flinches slightly instead of going numb. The 14 source-keyed heuristic rules from the fetcher era (sports, weather, finance, news, presence) were removed along with the fetchers; the only event shape left is `user:freeform`. The fixed `source_id` means the saturation window naturally dampens repeated fallbacks while the LLM stays down.

### Interpreter Telemetry

After every `interpret()` call, the `LLMInterpreter` sets two fields:
- `last_path`: `"llm"` (success), `"cache"` (cache hit), or `"fallback"` (failure)
- `last_error`: the exception message (empty on success)

The web UI surfaces these in the freeform status label. If `last_path == "fallback"`, check stderr for `[kindalive.llm]` logs that include the raw response snippet.

### Structured Output

The LLM acts as both the **emotional interpreter** and the robot's
**voice**. It returns a JSON object with two fields — a short spoken
`reply` and the `impulses` array:

```json
{
  "reply": "Oh nice — a goal! We're up 3-2!",
  "impulses": [
    {"chemical": "dopamine",   "delta": 0.25},
    {"chemical": "adrenaline", "delta": 0.35, "duration_seconds": 10}
  ]
}
```

- `impulses` is the 0–8 chemical impulses (validated as before). Each
  may also carry `duration_seconds`, `source_id`, `source_label`.
- `reply` is one short, spoken-style sentence in the robot's voice,
  coloured by its current mood. It is surfaced as `interpreter.last_reply`
  / `Robot.last_reply` and read aloud by the web UI's speech synthesizer
  (see Layer 5). The model returns `""` when there's nothing to say.

The parser (`_split_reply_and_impulses`) also accepts a bare impulse
array (no reply) for backward compatibility with older prompts and the
test mock backend. Empty/cache/fallback paths leave `last_reply` empty,
so a cache hit or an LLM outage simply produces no speech.

### Conversation Memory

The robot is **not** a series of one-off prompts — it remembers the
session. `Robot` keeps a running conversation (`Robot.conversation`):
after every successful LLM turn it appends the owner's line (plain text)
and the robot's answer (the compact `{"reply", "impulses"}` JSON it
produced). That history flows to the interpreter through
`RobotContext.history` and is sent to the model as **multi-turn chat
messages** ahead of the new message, so follow-ups land in context
("I won the lottery" → "Congrats!" → "well, it was only five dollars" →
"Ha, still counts!"). The robot's *current chemical state* is already in
the prompt, so memory adds continuity of **topic** on top of continuity
of **mood**.

The history is bounded to the most recent `MAX_CONVERSATION_MESSAGES`
(40 = 20 exchanges) to cap prompt size; trimming keeps pairs aligned so
the history always starts on a user turn (required by the chat APIs).
`Robot.reset_conversation()` forgets the thread (the web UI also resets
it implicitly by rebuilding the `Robot` on a personality change). Only
LLM-answered turns are remembered — a fallback/outage turn is skipped so
it can't poison the thread.

### Routing

There is no batching, no urgency distinction, no buffering. Every
`UserText` paragraph is interpreted immediately. The `RealtimeRouter`
class composes the cache + LLM + apply pipeline into one call site
that `Robot.process_event` can hold onto.

```
UserText → Cache lookup ──→ HIT:  apply immediately
                  │
                  └──→ MISS: single LLM call, apply on return
```

Latency with Haiku at temperature 0 is ~200–500ms on cache miss,
sub-millisecond on cache hit. The cache only applies to the **first**
message of a conversation: once there is any history, the interpreter
bypasses the cache (the same words mean something different mid-thread),
so in practice it rarely fires.

### LLM Selection

| Concern | Decision |
|---------|----------|
| **Cloud model** | Claude Haiku via `AnthropicBackend`. Fast, cheap, calibrated. |
| **OpenAI-compatible** | Any `/chat/completions` server via `OpenAICompatBackend` — Ollama, LM Studio, vLLM, llama.cpp locally, or OpenAI / **OpenRouter** in the cloud. Config via `KINDALIVE_LLM_BASE_URL` / `KINDALIVE_LLM_MODEL` / `KINDALIVE_LLM_KEY` (or `--llm-base-url` / `--llm-model` / `--llm-key`). |
| **Temperature** | 0 for maximum consistency. Same paragraph → same impulses. |
| **Latency budget** | <500ms cold (cloud), <5ms cached. Local models vary. |
| **Cost** | ~$0.001 per interpretation with Haiku; free locally. |

### Caching Strategy

**Cache key:** `hash(event_type + summary + personality_name + affinity_bucket)`

For freeform paragraphs the cache hits only on exact repeats — no
normalization can collapse "Friday, finances up, day off tomorrow"
with "Friday, sun is out, day off tomorrow" without losing meaning.
That's fine: Haiku calls are cheap, and repeated identical paragraphs
(an experimenter retesting the same input) still get instant responses.

- **TTL:** 1 hour
- **Size:** LRU, 1000 entries

### Fallback

If the LLM is unavailable (API down, rate limited, network error,
malformed JSON), the interpreter applies a single small cortisol
nudge. This keeps the robot emotionally responsive rather than going
numb, but does not pretend to interpret the paragraph.

```python
FALLBACK_IMPULSES = [
    Impulse("cortisol", +0.05, source_id="fallback:freeform"),
]
```

These rules don't understand context or nuance — they're a safety net, not the primary system.

### Validation

Every LLM response passes through validation before reaching the engine:

1. **Schema check** — valid JSON, correct field names and types
2. **Delta clamping** — values outside [-0.5, +0.5] get clamped
3. **Chemical names** — must be one of the 8 known chemicals
4. **Array size** — reject responses with more than 8 impulses (one per chemical max)
5. **Duration** — clamp to [0, 300] seconds

If validation fails, fall back to heuristic rules for that event.

---

## Layer 4: Personality (The "Self")

A robot's personality is defined by its **seed chemistry** (resting neurochemistry) and **how strongly it reacts** to the owner (its affinity). The fetcher-era topic subscriptions are gone — the owner's voice is the only input.

### Seed Chemistry (Baseline Configuration)

Every robot has a full 8-chemical baseline vector — its neurochemical "nature." This determines its resting emotional state before any events happen. Two robots with different seed chemistry will feel different even if they experience the same events.

There are three layers, applied in order:

```
Species Defaults → Seed Chemistry → Runtime Drift
(hardcoded)        (per-robot)       (cortisol baseline rule)
```

**1. Species defaults** — the fallback values from the Chemicals table above. These represent a "generic robot" and exist only so you don't have to specify all 8 values every time.

**2. Seed chemistry** — a partial or full override of the species defaults, set at robot creation time. This is the robot's *identity*. It can come from:
- A personality preset (named bundle, see below)
- A config file / database record
- Direct constructor arguments
- Random generation within defined ranges (for creating unique individuals)

**3. Runtime drift** — baseline shift from sustained chemical states (e.g., chronic cortisol elevating cortisol baseline). This operates on top of seed chemistry and persists across sessions.

```python
@dataclass
class SeedChemistry:
    """Full baseline configuration for a robot's resting neurochemistry."""
    baselines: dict[Chemical, float]       # resting levels (defaults filled from species)
    half_life_multipliers: dict[Chemical, float] = field(default_factory=dict)
        # e.g., {"adrenaline": 0.5} → adrenaline decays 2x faster
        # default 1.0 for all chemicals if not specified
    interaction_scale: float = 1.0
        # global multiplier on all cross-chemical interaction coefficients
        # >1.0 = more reactive chemistry, <1.0 = more stable/dampened

    @classmethod
    def from_species_defaults(cls) -> "SeedChemistry":
        """All 8 chemicals at species default baselines."""
        return cls(baselines={
            Chemical.DOPAMINE: 0.3, Chemical.SEROTONIN: 0.5,
            Chemical.OXYTOCIN: 0.2, Chemical.TESTOSTERONE: 0.3,
            Chemical.CORTISOL: 0.2, Chemical.ADRENALINE: 0.1,
            Chemical.ENDORPHINS: 0.2, Chemical.GABA: 0.4,
        })

    @classmethod
    def from_dict(cls, overrides: dict) -> "SeedChemistry":
        """Start from species defaults, apply overrides."""
        seed = cls.from_species_defaults()
        for chem_name, value in overrides.get("baselines", {}).items():
            seed.baselines[Chemical.from_string(chem_name)] = value
        for chem_name, mult in overrides.get("half_life_multipliers", {}).items():
            seed.half_life_multipliers[Chemical.from_string(chem_name)] = mult
        seed.interaction_scale = overrides.get("interaction_scale", 1.0)
        return seed
```

**Why seed chemistry matters:**

At species-default baselines, the dominant emotion at rest is **calm** (~0.34). Happiness and bonding follow closely, sadness is low (~0.12) because the deficit terms are zero when dopamine/serotonin/oxytocin sit at their baselines. A robot seeded with higher dopamine and serotonin (like the cheerful preset) starts in an even more positive resting state; an anxious preset with elevated cortisol and depressed GABA tilts the neutral state toward bonding-plus-mild-anxiety instead. The seed chemistry is what makes a robot feel like an *individual*, not just a reaction machine.

### Affinity

Each personality preset carries a `default_affinity` multiplier that
the LLM sees in the prompt context. A robot with `affinity=1.8` is
told it reacts strongly to its owner's words; a robot with
`affinity=0.5` is told it is muted. The legacy fetcher-era
`Subscription` dataclass with topic-specific affinity is gone — there
are no topics anymore, only the owner's voice.

### Personality Presets

Presets are named bundles of seed chemistry + affinity defaults + optional half-life tuning. They're convenience wrappers — you can always bypass them and seed chemistry directly.

```python
PERSONALITY_PRESETS = {
    "cheerful": {
        "baselines": {
            "serotonin": 0.6, "dopamine": 0.4,
            "endorphins": 0.3, "gaba": 0.45,
        },
        "half_life_multipliers": {},
        "interaction_scale": 1.0,
        "default_affinity": 1.2,  # reacts a bit more to everything
    },
    "stoic": {
        "baselines": {
            "gaba": 0.6, "serotonin": 0.5,
            "adrenaline": 0.08, "cortisol": 0.15,
        },
        "half_life_multipliers": {
            "adrenaline": 0.7,  # adrenaline fades faster — harder to excite
            "cortisol": 0.8,    # cortisol fades faster — recovers from stress quicker
        },
        "interaction_scale": 0.7,  # dampened cross-chemical interactions
        "default_affinity": 0.6,   # muted reactions
    },
    "anxious": {
        "baselines": {
            "cortisol": 0.35, "gaba": 0.25,
            "adrenaline": 0.15, "serotonin": 0.4,
        },
        "half_life_multipliers": {
            "cortisol": 1.5,    # cortisol lingers longer
            "gaba": 1.3,        # calm is slower to build
        },
        "interaction_scale": 1.3,  # amplified cross-chemical interactions
        "default_affinity": 1.5,   # over-reacts to stressors
    },
}
```

### Custom Seeding Examples

Presets are starting points. You can create fully custom robots:

```python
# A robot that's naturally curious and energetic
curious_seed = SeedChemistry.from_dict({
    "baselines": {
        "dopamine": 0.5,      # high reward-seeking
        "adrenaline": 0.15,   # slightly elevated baseline energy
        "serotonin": 0.45,    # moderate stability
        "gaba": 0.3,          # lower calm — restless
    },
})

# A robot that's deeply bonded but slow to excite
loyal_seed = SeedChemistry.from_dict({
    "baselines": {
        "oxytocin": 0.4,      # strong bonding baseline
        "serotonin": 0.6,     # stable mood
        "adrenaline": 0.05,   # very low excitability
    },
    "half_life_multipliers": {
        "oxytocin": 1.5,      # oxytocin lingers — stays bonded longer
        "adrenaline": 0.5,    # excitement fades very fast
    },
})

# A randomized unique individual
import random
unique_seed = SeedChemistry.from_dict({
    "baselines": {
        chem.value: round(random.uniform(
            max(0.1, default - 0.15),
            min(0.7, default + 0.15)
        ), 2)
        for chem, default in SeedChemistry.from_species_defaults().baselines.items()
    },
    "interaction_scale": round(random.uniform(0.7, 1.3), 2),
})
```

### Seed Chemistry in the Robot Constructor

```python
robot = Robot(
    engine=NeurochemicalEngine(clock=clock, seed=cheerful_seed),
    interpreter=LLMInterpreter(...),
    personality="cheerful",     # name (for LLM prompt context)
    expression=TextExpressionOutput(),
)

# Or with direct seeding, no preset:
robot = Robot(
    engine=NeurochemicalEngine(clock=clock, seed=curious_seed),
    personality="curious",      # just a label for the LLM
)
```

The `personality` string passed to the Robot is now just a **label** sent to the LLM interpreter so it can factor personality into its interpretation. The actual neurochemical behavior comes entirely from the seed chemistry.

---

## Layer 5: Expression (The "Output")

The emotion vector drives observable behavior. This layer is intentionally abstract — the same emotion engine can drive a humanoid robot, a chatbot, an LED display, or a virtual avatar.

The **only UI is a NiceGUI web dashboard** at
`kindalive/expression/web_ui.py` — a deliberately small page built
around the LED dot-matrix robot face: freeform text input below the face,
chemical levels on one side, the emotion mix on the other, and a
real-time clock with an optional speed multiplier. See
[docs/web-ui.md](web-ui.md) for the feature tour.

### Expression Interface

```python
class ExpressionOutput(Protocol):
    async def express(self, emotions: EmotionVector, chemicals: ChemicalState) -> None: ...
```

### Phase 1 Output: Text Description

For initial development and testing, the expression layer produces a **human-readable text description** of the robot's emotional and physical state. This is the primary way to verify the system "feels right" before connecting to any hardware or VLA model.

The output combines:
- **Dominant emotions** (top 2–3 from the emotion vector)
- **Physical posture/gesture hints** (derived from chemical levels)
- **Engagement level** (how attentive/active the robot appears)

```python
class TextExpressionOutput(ExpressionOutput):
    """
    Produces text like:
      "Happy and excited, leaning forward, highly engaged"
      "Anxious but alert, tense posture, scanning"
      "Calm and content, relaxed posture, passive"
      "Stressed and irritable, restless, fidgeting"
    """

    # Physical state mapping from chemicals (not emotions)
    POSTURE_RULES = {
        "leaning forward":  lambda c: c.adrenaline > 0.5 and c.dopamine > 0.4,
        "relaxed posture":  lambda c: c.gaba > 0.5 and c.adrenaline < 0.3,
        "tense posture":    lambda c: c.cortisol > 0.5 and c.gaba < 0.3,
        "restless":         lambda c: c.adrenaline > 0.4 and c.cortisol > 0.4,
        "still and steady": lambda c: c.gaba > 0.4 and c.serotonin > 0.4,
    }

    ENGAGEMENT_RULES = {
        "highly engaged":   lambda c: c.adrenaline > 0.4 or c.dopamine > 0.6,
        "passively content": lambda c: c.serotonin > 0.5 and c.adrenaline < 0.3,
        "withdrawn":        lambda c: c.cortisol > 0.5 and c.dopamine < 0.2,
        "scanning":         lambda c: c.cortisol > 0.4 and c.adrenaline > 0.3,
    }
```

Example outputs for test scenarios:

| Scenario | Expected text |
|----------|--------------|
| Couch with owner, hockey, nice day | `"Happy and excited, leaning forward, highly engaged"` |
| Market crash, storm, alone | `"Anxious and stressed, tense posture, scanning"` |
| Quiet evening, owner nearby | `"Calm and bonded, relaxed posture, passively content"` |
| Hockey fight, close game | `"Excited and aggressive, leaning forward, highly engaged"` |
| Recovering after bad news | `"Mildly anxious, still and steady, passively content"` |

This text output format is designed to map directly to a VLA (Vision-Language-Action) model later — each component (emotion, posture, engagement) becomes an input signal for physical robot behavior.

### Future Outputs

- **VLA model input** — map the chemical state, emotion vector, *and* the 12-muscle face vector to physical robot actions
- **Text tone modifier** — adjust language generation style based on dominant emotion
- **LED/display** — map emotions to colors, patterns, animations

### Native iOS Port

A native iOS app under `ios/` reimplements this architecture in Swift
(`KindaliveKit`), with Apple's on-device Foundation Models framework
replacing the cloud LLM interpreter. This document remains the source of
truth for every formula; the Swift port is a transcription locked to the
Python engine by golden fixtures (`scripts/generate_swift_fixtures.py`).
See `docs/ios-app.md`.

---

## Layer 5a: Facial Muscle Projection (the LED face)

A second projection from `ChemicalState`, parallel to `EmotionProjection`. Where the emotion vector quantizes the chemistry through 8 high-level moods, the face vector keeps everything continuous and animatable: each of 12 facial muscles is a weighted linear combination of chemicals, clamped to `[0.0, 1.0]`. Names map roughly to FACS Action Units so the same vector can drive the LED face, a physical robot face, or a blendshape model later.

### FaceState (FACS Action Units)

```python
@dataclass(frozen=True)
class FaceState:
    brow_inner_raise: float       # AU1  — sadness, concern
    brow_outer_raise: float       # AU2  — surprise, fear
    brow_lower: float             # AU4  — anger, focus
    eyelid_upper_raise: float     # AU5  — alertness, surprise
    eyelid_lower_tighten: float   # AU7  — anger, anxiety
    cheek_raise: float            # AU6  — Duchenne joy
    nose_wrinkle: float           # AU9  — disgust, anger
    lip_corner_pull: float        # AU12 — smile
    lip_corner_depress: float     # AU15 — frown
    jaw_open: float               # AU26 — surprise, laughter
    lip_pucker: float             # AU18 — affection, concern
    lip_press: float              # AU24 — restraint, anger
```

### Coefficient Table (chemicals → muscles)

The face is driven *directly* from `ChemicalState`, not from `EmotionVector` — this avoids quantizing through the 8-emotion bottleneck. `FaceTerm` reuses the `inverted` deficit semantics from `EmotionTerm`: an inverted term contributes `max(0, baseline - level)`, so a face only "frowns from sadness" when dopamine/serotonin fall below the robot's resting level.

Single source of truth: `kindalive/expression/face.py` (`FACE_WEIGHTS`). The matching `kindalive/config/face.toml` is documentation only — same convention as `emotions.toml` / `EMOTION_WEIGHTS`.

| Muscle | + contributors | − / inverted contributors |
|---|---|---|
| `brow_inner_raise`     | cortisol 0.40, deficit(dopamine) 0.35, deficit(serotonin) 0.25 | gaba −0.10 |
| `brow_outer_raise`     | adrenaline 0.50, dopamine 0.20                                  | gaba −0.10 |
| `brow_lower`           | testosterone 0.35, cortisol 0.30, adrenaline 0.20               | gaba −0.20, serotonin −0.10 |
| `eyelid_upper_raise`   | adrenaline 0.55, cortisol 0.25, dopamine 0.15                   | gaba −0.20 |
| `eyelid_lower_tighten` | cortisol 0.35, testosterone 0.25, adrenaline 0.20               | gaba −0.15 |
| `cheek_raise`          | dopamine 0.45, endorphins 0.30, oxytocin 0.20                   | cortisol −0.20 |
| `nose_wrinkle`         | testosterone 0.30, cortisol 0.30, adrenaline 0.15               | gaba −0.20 |
| `lip_corner_pull`      | dopamine 0.40, endorphins 0.30, serotonin 0.20, oxytocin 0.15   | cortisol −0.25 |
| `lip_corner_depress`   | cortisol 0.45, deficit(dopamine) 0.35, deficit(serotonin) 0.25  | endorphins −0.15 |
| `jaw_open`             | adrenaline 0.40, dopamine 0.25, endorphins 0.15                 | gaba −0.15, cortisol −0.10 |
| `lip_pucker`           | oxytocin 0.50, endorphins 0.20                                  | cortisol −0.10 |
| `lip_press`            | testosterone 0.35, cortisol 0.25, gaba 0.15                     | endorphins −0.10 |

### Rendering — the LED dot-matrix face

The face renders as a **retro LED dot-matrix panel** (Cozmo / flip-dot
style): two block/arc eyes, brow bars, and a mouth, all drawn as a grid
of glowing dots that light up in the dominant-emotion's accent color. It
is a plain **2D canvas** — no WebGL, no model files, no dependency — in
`kindalive/expression/web_assets/face3d.js`, with the Python half in
`kindalive/expression/face_3d.py`:

- `face_payload(face, mood_color, mood_intensity)` converts a
  `FaceState` plus the dominant-emotion accent color into the JSON the
  JS `window.kindaliveFace.setTargets(...)` API consumes.
- The renderer draws the eyes/brows/mouth into a low-resolution mask
  (one pixel per dot), then samples each cell's coverage onto a glowing
  dot — so canvas anti-aliasing gives the LED falloff for free.

The web UI pushes a payload at 10 Hz via `ui.run_javascript`. The JS
lerps every muscle toward its target and layers autonomous life on top:
blinking, eye saccades, and a breathing glow. Eyes become happy upward
arcs when the smile factor `s = lip_corner_pull − lip_corner_depress`
is high, alert blocks otherwise (narrowed by `eyelid_lower_tighten`,
widened by `eyelid_upper_raise`); brow bars angle from `brow_lower`
(furrowed) and `brow_inner_raise` (worried); the mouth curves with `s`,
narrows with `lip_pucker`, and opens with `jaw_open`.

**Lip-sync.** `window.kindaliveFace.setSpeaking(on)` / `mouthPulse()` let
the speech synthesizer drive the mouth: while speaking, a couple of
detuned oscillators add a syllable-rate flap on top of `jaw_open`, and
word boundaries pulse it (see Layer 5 — Voice).

---

## Robot Class (Top-Level Integration)

The `Robot` class wires all layers together and provides the public API:

```python
class Robot:
    def __init__(
        self,
        engine: NeurochemicalEngine,
        interpreter: LLMInterpreter | None = None,
        personality: str = "default",
        expression: ExpressionOutput | None = None,
    ): ...

    # Direct impulse injection (engine-level tests, bypasses interpreter)
    def receive_impulses(self, impulses: list[ChemicalImpulse]) -> None: ...

    # Full pipeline: text → interpreter → impulses → engine (+ remembers the turn)
    async def process_event(self, event: UserText) -> None: ...
    async def interpret_text(self, text: str) -> list[ChemicalImpulse]: ...

    # Read current emotional / chemical state
    def current_emotions(self) -> EmotionVector: ...
    def current_chemicals(self) -> ChemicalState: ...

    # The robot's spoken reply from the last LLM turn (empty if none)
    @property
    def last_reply(self) -> str: ...

    # Session conversation memory (multi-turn LLM context)
    @property
    def conversation(self) -> list[dict]: ...
    def reset_conversation(self) -> None: ...
```

Both `receive_impulses()` (sync, direct) and `process_event()` (async, via LLM) are valid entry points. Engine-level tests use the former; full-pipeline tests use the latter. `interpret_text()` is the convenience wrapper the web UI calls. After a successful LLM turn the robot stores `last_reply` (the spoken line) and appends the exchange to `conversation` (see Layer 3b — Conversation Memory).

---

## Key Technical Decisions

### Language: Python

- Fastest path to a working prototype
- `asyncio` for non-blocking LLM calls under the web server
- `pytest` and `hypothesis` for testing
- Easy to port the core engine to Rust later if performance matters on embedded hardware

### Core Dependencies

The core library (engine, emotion projection, face projection, `Robot`)
is **pure Python with zero third-party dependencies** — stdlib asyncio
only. Everything else is an optional extra:

- **NiceGUI (≥3.0)** (`[web]` extra) — the web dashboard (the LED face
  is a plain 2D canvas, so it needs nothing beyond the browser)
- **httpx** (`[openai]` extra, included in `[web]`) — async HTTP client
  for the OpenAI-compatible LLM backend
- **anthropic** (`[anthropic]` extra; `[live]` is a legacy alias) —
  Claude backend
- **pytest** / **hypothesis** / **mypy** (`[dev]` extra) — testing,
  property-based testing, strict type checking

### Simulation Tick: 100ms (10 Hz)

- Fast enough for responsive emotional shifts
- Slow enough to be trivial computationally
- The engine accepts a `Clock` interface for testability — tests inject a `ManualClock` that advances time on demand, no real waiting

### Persistence: Yes

- The robot's chemical state serializes to JSON on shutdown and restores on startup
- A robot that was stressed before a reboot should still be somewhat stressed after — moods don't vanish
- Baseline drift persists too (chronic states survive restarts)
- State snapshots can also be saved periodically for crash recovery

### Multi-Robot: Designed for it, start with one

- The `NeurochemicalEngine` is a class instance, not a singleton
- Each robot gets its own engine, seed chemistry, and personality
- A `RobotManager` can orchestrate multiple instances later
- Single-robot implementation first — no premature distributed systems

### Configuration: TOML files

- Chemical parameters (half-lives, baselines, interaction weights)
- Emotion projection weights
- Personality presets
- All tunable without code changes

---

## Project Structure

```
kindalive/
├── __init__.py
├── engine/
│   ├── chemicals.py             # Chemical enum, ChemicalState, decay logic
│   ├── impulse.py               # ChemicalImpulse dataclass
│   ├── seed_chemistry.py        # SeedChemistry: baseline config, half-life multipliers
│   ├── interactions.py          # Cross-chemical interaction rules
│   ├── neurochemical_engine.py  # Core simulation loop (sub-stepping, clamping)
│   └── clock.py                 # Clock interface (RealClock + ManualClock)
├── emotions/
│   ├── projection.py            # Emotion derivation from chemical state
│   └── emotion_vector.py        # EmotionVector dataclass
├── interpreter/
│   ├── text_input.py            # UserText dataclass — the only input type
│   ├── llm_interpreter.py       # LLM-based UserText → impulse translation + MockLLMBackend
│   ├── anthropic_backend.py     # Claude API backend (reads ANTHROPIC_API_KEY from env)
│   ├── openai_backend.py        # OpenAI-compatible backend (Ollama/LM Studio/vLLM/OpenAI)
│   ├── prompt_builder.py        # PromptBuilder + freeform multi-fact preamble
│   ├── impulse_cache.py         # LRU cache with TTL for interpreted results
│   ├── fallback_rules.py        # Single cortisol nudge for LLM-down case
│   ├── validator.py             # Schema check, delta clamping, sanitization
│   └── event_router.py          # RealtimeRouter (cache + LLM + apply)
├── personality/
│   └── presets.py               # Personality presets (cheerful, stoic, anxious)
├── expression/
│   ├── base.py                  # ExpressionOutput protocol
│   ├── text_output.py           # Human-readable mood descriptions
│   ├── face.py                  # 12-muscle FaceState + FaceProjection
│   ├── face_3d.py               # Python side of the face (payload + boot wiring)
│   ├── web_ui.py                # The only UI — NiceGUI dashboard
│   └── web_assets/
│       ├── face3d.js            # LED dot-matrix face (2D-canvas renderer)
│       └── style.css            # Dashboard styling + CRT scanline overlay
├── persistence/
│   └── state_store.py           # Serialize/deserialize/save/load chemical state
├── config/
│   ├── chemicals.toml           # Chemical parameters (half-lives, baselines)
│   ├── emotions.toml            # Projection weights
│   ├── face.toml                # Documentation copy of FACE_WEIGHTS
│   ├── personalities.toml       # Personality presets
│   └── interpreter.toml         # LLM model, cache TTL, fallback toggle
├── env_loader.py                # Dependency-free .env loader
├── robot.py                     # Top-level Robot (process_event + interpret_text)
└── main.py                      # CLI: `python -m kindalive.main --text "..."`

tests/
├── conftest.py
├── test_chemicals.py / test_saturation.py / test_interactions.py /
│   test_seed_chemistry.py / test_emotion_projection.py / test_expression.py /
│   test_face.py / test_face_3d.py / test_persistence.py /
│   test_env_loader.py / test_web_ui.py / test_properties.py /
│   test_integration.py
└── test_interpreter/
    ├── test_validator.py
    ├── test_fallback_rules.py       # one default-nudge test
    ├── test_impulse_cache.py
    ├── test_prompt_builder.py
    ├── test_llm_interpreter.py
    ├── test_openai_backend.py       # OpenAI-compatible protocol tests
    ├── test_event_router.py         # RealtimeRouter cache/LLM/apply path
    ├── test_full_pipeline.py        # text → MockLLM → engine → expression
    ├── test_freeform_prompt.py      # multi-fact preamble + calibration examples
    └── test_freeform_paragraphs.py  # live LLM benchmark (gated on ANTHROPIC_API_KEY)
```
