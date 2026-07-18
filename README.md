# Kindalive

Robot emotions through simulated neurochemistry — shown on an LED dot-matrix face.

![A five-message conversation with the Kindalive robot: each typed message fires visible chemical impulses — dopamine, cortisol, adrenaline bars spiking and crashing — while the LED dot-matrix face flows through excitement, happiness, anger, sadness, and bonding](docs/screenshots/face-demo.gif)

Kindalive models robot emotions as **emergent states from simulated
body chemistry**, not as discrete labels. There is no `mood = "happy"`
variable. A robot maintains concentrations of 8 simulated
neurochemicals (dopamine, cortisol, oxytocin, …), and emotions are
read-only projections derived from that chemical state.

You type a paragraph — "you won the lottery", "the cat is missing and
a storm is rolling in" — an LLM (cloud Claude or any local
OpenAI-compatible model — incl. OpenRouter) translates it into chemical impulses, the
neurochemical engine integrates them, and a **retro LED dot-matrix
robot face** contorts to show the resulting
emotional mix, with every chemical level visible beside it.

## How It Works

```
   Your paragraph
        │
        ▼
  LLM Interpreter ──→ ChemicalImpulse[]
  (Claude or local)         │
                            ▼
                  Neurochemical Engine
                  (decay, interactions, sub-stepping)
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
      Emotion Projection          Face Projection
      (8 emotions)                (12 FACS muscles)
              │                           │
              ▼                           ▼
        emotion bars              LED dot-matrix face
```

## Key Concepts

**8 Chemicals**: Dopamine, serotonin, oxytocin, testosterone, cortisol,
adrenaline, endorphins, GABA. Each has its own half-life, baseline, and
cross-chemical interactions. Adrenaline fades in minutes (fleeting
excitement). Serotonin moves over hours (lasting mood).

**8 Emotions**: Happiness, excitement, anger, calm, bonding, anxiety,
sadness, euphoria. Each is a weighted linear combination of chemical
levels — computed on the fly, never stored.

**12 Facial Muscles**: A second projection from the same chemistry,
named after FACS Action Units (brow raise, lid tighten, lip corner
pull, jaw open, …). They drive the LED face directly — no quantizing
through emotion labels.

**Seed Chemistry**: Every robot has a configurable baseline — its
"nature". A cheerful robot has higher resting serotonin and dopamine; a
stoic robot has elevated GABA and dampened interactions.

**LLM Interpreter**: Instead of hand-coding emotional mappings, an LLM
reads your paragraph and produces chemical impulses. "I won the
lottery" and "I won a free coffee" get very different responses —
automatically.

## Quick Start

```bash
# Everything: web dashboard + both LLM backends
pip3 install -e ".[all]"

# Offline — face + chemistry work, text input disabled
python3 -m kindalive.expression.web_ui

# With Claude (cloud)
ANTHROPIC_API_KEY=sk-ant-... python3 -m kindalive.expression.web_ui

# With a local model via Ollama / LM Studio / vLLM
KINDALIVE_LLM_BASE_URL=http://localhost:11434/v1 \
KINDALIVE_LLM_MODEL=llama3.1 \
python3 -m kindalive.expression.web_ui
```

The **core library is pure Python with zero dependencies** — `pip
install kindalive` alone gives you the neurochemical engine, the
emotion projection, the face projection, and the `Robot` API, ready to
embed in your own robot. Extras add the optional layers:

| Extra | What it adds |
|-------|--------------|
| `[web]` | The NiceGUI dashboard (LED face, chemical levels, emotion mix) |
| `[anthropic]` | Claude backend for the LLM interpreter |
| `[openai]` | Any OpenAI-compatible backend (Ollama, LM Studio, vLLM, OpenRouter) |
| `[all]` | All of the above |
| `[dev]` | pytest, hypothesis, coverage, mypy |

Open <http://localhost:8080>, type something to the robot, and watch
the face react. The UI auto-loads a `.env` file from the repo root, so
you can keep `ANTHROPIC_API_KEY=...` there instead of exporting it.

![The full Kindalive dashboard: live neurochemistry bars on the left, the LED dot-matrix face in the center with the dominant emotion beneath it, the emotion mix on the right, and the "Tell the robot something…" input below](docs/screenshots/web_ui.png)

### On your phone

The dashboard is responsive and installable (Add to Home Screen launches
it fullscreen). Reach it from your phone on the same Wi-Fi:

```bash
python3 -m kindalive.expression.web_ui --host 0.0.0.0
# then open http://<your-computer-LAN-IP>:8080 on the phone
```

To use it without your computer running, host the included `Dockerfile`
on something always-on (a cloud VM, Fly.io/Render/Railway, or a
Raspberry Pi):

```bash
docker build -t kindalive .
docker run -p 8080:8080 -e ANTHROPIC_API_KEY=sk-ant-... kindalive
```

See [docs/web-ui.md](docs/web-ui.md#use-it-from-your-phone) for the full
walkthrough.

There is also a one-shot CLI:

```bash
python3 -m kindalive.main --text "Friday, finances up, day off tomorrow"
```

## Library Example

```python
from kindalive.engine.clock import ManualClock
from kindalive.engine.chemicals import Chemical
from kindalive.engine.impulse import ChemicalImpulse
from kindalive.expression.face import FaceProjection
from kindalive.robot import Robot

robot = Robot(personality="cheerful", clock=ManualClock())

robot.receive_impulses([
    ChemicalImpulse(Chemical.DOPAMINE, delta=0.35),
    ChemicalImpulse(Chemical.ADRENALINE, delta=0.40),
])

emotions = robot.current_emotions()      # happiness, excitement, ...
face = FaceProjection.compute(robot.current_chemicals())
# face.lip_corner_pull, face.jaw_open, ... → drive any renderer
```

## Real Hardware

`FaceState` is renderer-agnostic — the same 12 floats in `[0, 1]` that
drive the web face can drive physical hardware. [`examples/`](examples/)
has two ready-to-run adapters, and both degrade gracefully: without the
driver library installed they render to the terminal, so you can develop
the mapping on a laptop and copy the same file to a Raspberry Pi
unchanged.

Each demo injects a chemical impulse recipe (`--mood joy`, `fear`,
`anger`, or `sadness`) and then lets the neurochemical engine run in
real time: the expression blooms, then visibly decays back to the
robot's baseline over ~20 seconds — the same fade you see on the web
face. In a real robot you would drop the recipe and read `FaceState`
from a live `Robot` instead.

### MAX7219 8×8 LED matrix — a physical dot-matrix face

The MAX7219 is a ~$3 SPI display driver, usually sold pre-soldered to
an 8×8 LED module (and often as chainable 4-in-1 strips). The adapter
condenses the 12 facial muscles onto the 8×8 grid: rows 0–1 are the
brows (lifted when raised, shifted inward when knitted in anger), rows
2–3 are the eyes (two rows when wide open, a squint when tightened),
and rows 5–7 are the mouth (corners curl up for a smile, down for a
frown, and the jaw opens into a hollow box).

Wire it to the Pi's SPI header, enable SPI via
`sudo raspi-config` → *Interface Options* → *SPI*, and run:

| MAX7219 pin | Raspberry Pi |
|-------------|--------------|
| VCC | 5V |
| GND | GND |
| DIN | MOSI (pin 19) |
| CS  | CE0 (pin 24) |
| CLK | SCLK (pin 23) |

```bash
pip install luma.led_matrix
python3 examples/led_matrix_face.py --mood joy
```

### PCA9685 servo board — an animatronic face

The PCA9685 is a 16-channel PWM driver on I2C — the standard hobby
board for driving many servos from two Pi pins. The adapter assigns one
servo per muscle on channels 0–11, so a mechanical face (brow linkages,
eyelids, lip corners, jaw) tracks the chemistry directly.

The whole mapping is one table in `servo_face.py`: each channel gets a
`(muscle, rest_angle, full_contraction_angle)` triple, and activation is
linearly interpolated between the two angles (they may run "backwards"
for mirrored linkages). Tuning your head to its linkage geometry means
editing that table — no engine knowledge required.

Enable I2C via `sudo raspi-config` → *Interface Options* → *I2C*, then:

```bash
pip install adafruit-circuitpython-servokit
python3 examples/servo_face.py --mood anger
```

Power the servos from their own 5–6 V supply on the PCA9685's V+
terminal (sharing ground with the Pi) — a dozen hobby servos can draw
several amps, far more than the Pi's 5 V rail can source.

### Bring your own actuators

The part worth copying into your own robot is tiny — get a `FaceState`,
map its 12 floats to whatever you have (LEDs, servos, an e-ink face, a
plotter…):

```python
from kindalive.expression.face import FaceProjection

face = FaceProjection.compute(engine.state)   # 12 floats in [0, 1]
my_renderer.draw(face.lip_corner_pull, face.jaw_open, ...)
```

## Native iOS App

`ios/` contains a native iOS port that runs the whole pipeline
on-device: Apple's Foundation Models framework (Apple Intelligence,
iOS 26+) replaces Claude as the interpreter — guided generation returns
typed impulses, so there's no JSON parsing at all — and a pure-Swift
port of the engine (`KindaliveKit`) drives the same LED face with
`AVSpeechSynthesizer` voice + lip sync. No network, no API keys. The
Python engine stays the source of truth; the Swift core is locked to it
by golden fixtures generated from this repo. See
[docs/ios-app.md](docs/ios-app.md).

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | **Source of truth** — chemicals, emotions, face projection, LLM interpreter, personalities |
| [Web UI](docs/web-ui.md) | The dashboard — LED face, chemical levels, emotion mix, LLM setup |
| [iOS App](docs/ios-app.md) | Native iOS port — on-device Apple Intelligence, SwiftUI LED face, fixture parity |
| [Testing Strategy](docs/testing-strategy.md) | Test layers with code examples and build order |
| [LLM Benchmark](docs/llm-benchmark.md) | Scenarios for evaluating LLM interpretation quality |

## Tech Stack

- **Python 3.9+**, asyncio
- **NiceGUI ≥ 3.0** — web dashboard (the LED face is a plain 2D canvas,
  no extra dependency)
- **LLM**: Claude Haiku via the Anthropic API, or any
  OpenAI-compatible server (Ollama, LM Studio, vLLM, OpenAI, OpenRouter)
- **Testing**: pytest, hypothesis, pytest-asyncio

## Running Tests

```bash
# Fast unit tests (no API keys, no LLM calls)
pytest tests/ -m "not integration and not llm"

# Live LLM benchmark (requires ANTHROPIC_API_KEY)
pytest tests/ -m llm
```

## Project Status

Kindalive is a hobby project, built for the joy of it and maintained at
hobby pace. It is tested (180+ tests, >80% coverage gate,
`mypy --strict`, CI on Python 3.9–3.13) and usable, but issues and PRs
may sit for a while — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
