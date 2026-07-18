#!/usr/bin/env python3
"""Generate golden parity fixtures for the Swift port (ios/KindaliveKit).

Runs the Python engine — the source of truth — through deterministic
scenarios and dumps the numerical results as JSON. The Swift test suite
(`ios/KindaliveKit/Tests/KindaliveKitTests/FixtureParityTests.swift`)
loads these files and asserts near-equality, so any formula drift between
the two implementations shows up as a named red test.

Deterministic by construction: seeded RNG, ManualClock, no wall time.
Re-running must produce a zero git diff.

Usage:
    python3 scripts/generate_swift_fixtures.py
"""

from __future__ import annotations

import json
from pathlib import Path
from random import Random
from typing import Any

from kindalive.engine.chemicals import Chemical, ChemicalState, SPECIES_DEFAULTS
from kindalive.engine.clock import ManualClock
from kindalive.engine.impulse import ChemicalImpulse
from kindalive.engine.interactions import apply_interactions
from kindalive.engine.neurochemical_engine import NeurochemicalEngine
from kindalive.engine.seed_chemistry import SeedChemistry
from kindalive.emotions.projection import EmotionProjection
from kindalive.expression.face import FaceProjection
from kindalive.persistence.state_store import serialize_engine
from kindalive.personality.presets import PERSONALITY_PRESETS, get_seed

FIXTURES_DIR = (
    Path(__file__).resolve().parent.parent
    / "ios" / "KindaliveKit" / "Tests" / "KindaliveKitTests" / "Fixtures"
)

SEED = 20260718
CHEMS = [c.value for c in Chemical]


def _levels(state: ChemicalState) -> dict[str, float]:
    return state.as_dict()


def _baselines(state: ChemicalState) -> dict[str, float]:
    return state.baselines_as_dict()


def _make_state(
    levels: dict[str, float],
    baselines: dict[str, float] | None = None,
) -> ChemicalState:
    bl = None
    if baselines is not None:
        bl = {Chemical.from_string(k): v for k, v in baselines.items()}
    state = ChemicalState(baselines=bl)
    for name, value in levels.items():
        state.set(Chemical.from_string(name), value)
    return state


# ── decay.json ─────────────────────────────────────────────────────

def gen_decay() -> dict[str, Any]:
    """Single apply_decay(chem, dt) calls across a level × dt grid."""
    cases = []
    start_levels = [0.0, 0.05, 0.25, 0.6, 0.9, 1.0]
    dts = [0.05, 0.5, 1.0, 7.3, 60.0, 600.0, 3600.0]
    for chem in Chemical:
        for start in start_levels + [SPECIES_DEFAULTS[chem]["baseline"]]:
            for dt in dts:
                state = ChemicalState()
                state.set(chem, start)
                state.apply_decay(chem, dt)
                cases.append({
                    "chemical": chem.value,
                    "start_level": start,
                    "baseline": SPECIES_DEFAULTS[chem]["baseline"],
                    "half_life": SPECIES_DEFAULTS[chem]["half_life"],
                    "dt": dt,
                    "expected_level": state.get(chem),
                })
    return {"cases": cases}


# ── interactions.json ──────────────────────────────────────────────

def gen_interactions() -> dict[str, Any]:
    """One apply_interactions() call on hand-picked states."""
    scenarios: list[dict[str, Any]] = [
        {"name": "all_baseline_fixed_point", "levels": {}, "dt": 0.5, "scale": 1.0},
        {"name": "elevated_cortisol_erodes_serotonin",
         "levels": {"cortisol": 0.8, "serotonin": 0.6}, "dt": 0.5, "scale": 1.0},
        {"name": "gaba_damps_adrenaline_excess",
         "levels": {"adrenaline": 0.9, "gaba": 0.7}, "dt": 0.5, "scale": 1.0},
        {"name": "testosterone_amplifies_adrenaline",
         "levels": {"testosterone": 0.85, "adrenaline": 0.4}, "dt": 0.5, "scale": 1.0},
        {"name": "adrenaline_inhibits_gaba_to_floor",
         "levels": {"adrenaline": 1.0, "gaba": 0.15}, "dt": 0.5, "scale": 1.0},
        {"name": "oxytocin_relieves_cortisol",
         "levels": {"oxytocin": 0.9, "cortisol": 0.75}, "dt": 0.5, "scale": 1.0},
        {"name": "cortisol_baseline_drifts_up",
         "levels": {"cortisol": 0.85}, "dt": 0.5, "scale": 1.0},
        {"name": "cortisol_baseline_drifts_down",
         "levels": {"cortisol": 0.05}, "dt": 0.5, "scale": 1.0},
        {"name": "stoic_scale_0_7",
         "levels": {"cortisol": 0.8, "adrenaline": 0.7, "serotonin": 0.6},
         "dt": 0.5, "scale": 0.7},
        {"name": "anxious_scale_1_3",
         "levels": {"cortisol": 0.8, "adrenaline": 0.7, "gaba": 0.2},
         "dt": 0.5, "scale": 1.3},
        {"name": "small_dt",
         "levels": {"cortisol": 0.9, "adrenaline": 0.8, "oxytocin": 0.6},
         "dt": 0.1, "scale": 1.0},
        {"name": "everything_high",
         "levels": {c: 0.95 for c in CHEMS}, "dt": 0.5, "scale": 1.0},
        {"name": "everything_low",
         "levels": {c: 0.02 for c in CHEMS}, "dt": 0.5, "scale": 1.0},
    ]
    cases = []
    for sc in scenarios:
        state = _make_state(sc["levels"])
        inputs = {"levels": _levels(state), "baselines": _baselines(state)}
        apply_interactions(state, sc["dt"], scale=sc["scale"])
        cases.append({
            "name": sc["name"],
            "dt": sc["dt"],
            "scale": sc["scale"],
            "input": inputs,
            "expected": {"levels": _levels(state), "baselines": _baselines(state)},
        })
    return {"cases": cases}


# ── engine_trajectories.json ───────────────────────────────────────

def gen_trajectories() -> dict[str, Any]:
    """Full engine runs: impulses at t=0, snapshots along the way.

    The clock is advanced in lockstep with engine.advance (as Robot.advance
    does) so saturation windows and sustained drips see consistent time.
    """
    impulse_scripts: dict[str, list[dict[str, Any]]] = {
        "lottery_win": [
            {"chemical": "dopamine", "delta": 0.5, "source_id": "fx:lottery"},
            {"chemical": "adrenaline", "delta": 0.4, "source_id": "fx:lottery"},
            {"chemical": "endorphins", "delta": 0.35, "source_id": "fx:lottery"},
        ],
        "grief_with_ambient_rain": [
            {"chemical": "cortisol", "delta": 0.3, "source_id": "fx:grief"},
            {"chemical": "dopamine", "delta": -0.25, "source_id": "fx:grief"},
            {"chemical": "serotonin", "delta": -0.2, "source_id": "fx:grief"},
            {"chemical": "gaba", "delta": 0.2, "duration_seconds": 300.0,
             "source_id": "fx:rain"},
        ],
        "sustained_only": [
            {"chemical": "serotonin", "delta": 0.3, "duration_seconds": 180.0,
             "source_id": "fx:sun"},
            {"chemical": "oxytocin", "delta": 0.15, "duration_seconds": 240.0},
        ],
        "unsourced_shock": [
            {"chemical": "cortisol", "delta": 0.45},
            {"chemical": "adrenaline", "delta": 0.5},
            {"chemical": "gaba", "delta": -0.2},
        ],
    }
    snapshot_times = [0.0, 0.1, 1.0, 5.0, 30.0, 120.0, 600.0]

    scenarios = []
    for personality in PERSONALITY_PRESETS:
        for script_name, script in impulse_scripts.items():
            clock = ManualClock()
            engine = NeurochemicalEngine(clock=clock, seed=get_seed(personality))
            impulses = [
                ChemicalImpulse(
                    chemical=Chemical.from_string(item["chemical"]),
                    delta=item["delta"],
                    duration_seconds=item.get("duration_seconds", 0.0),
                    source_id=item.get("source_id", ""),
                )
                for item in script
            ]
            engine.apply_impulses(impulses)

            snapshots = []
            t = 0.0
            for target in snapshot_times:
                dt = target - t
                if dt > 0:
                    clock.advance(seconds=dt)
                    engine.advance(dt)
                    t = target
                snapshots.append({
                    "t": target,
                    "levels": _levels(engine.state),
                    "baselines": _baselines(engine.state),
                })
            scenarios.append({
                "personality": personality,
                "script": script_name,
                "impulses": script,
                "snapshots": snapshots,
            })
    return {"scenarios": scenarios}


# ── saturation.json ────────────────────────────────────────────────

def gen_saturation() -> dict[str, Any]:
    """Repeated impulses; clock advances WITHOUT engine.advance so the
    recorded levels isolate saturation dampening from decay."""
    scenarios = []

    def run(name: str, events: list[dict[str, Any]]) -> None:
        clock = ManualClock()
        engine = NeurochemicalEngine(clock=clock)
        steps = []
        for ev in events:
            clock.advance(seconds=ev.get("advance", 0.0))
            imp = ChemicalImpulse(
                chemical=Chemical.from_string(ev["chemical"]),
                delta=ev["delta"],
                duration_seconds=ev.get("duration_seconds", 0.0),
                source_id=ev.get("source_id", ""),
            )
            engine.apply_impulse(imp)
            steps.append({
                "advance": ev.get("advance", 0.0),
                "impulse": ev,
                "level_after": engine.state.get(imp.chemical),
            })
        scenarios.append({"name": name, "steps": steps})

    base = {"chemical": "dopamine", "delta": 0.2, "source_id": "fx:repeat"}
    run("same_source_dampens", [dict(base, advance=a) for a in [0, 10, 10, 10, 10, 10]])
    run("window_expiry_resets", [
        dict(base, advance=0), dict(base, advance=100), dict(base, advance=100),
        dict(base, advance=150),  # first event now outside the 300s window
        dict(base, advance=400),  # all events expired
    ])
    run("empty_source_never_dampens", [
        {"chemical": "dopamine", "delta": 0.2, "advance": a} for a in [0, 5, 5, 5]
    ])
    run("distinct_sources_independent", [
        dict(base, advance=0),
        {"chemical": "dopamine", "delta": 0.2, "source_id": "fx:other", "advance": 5},
        dict(base, advance=5),
    ])
    run("sustained_saturates_once", [
        {"chemical": "gaba", "delta": 0.3, "duration_seconds": 60.0,
         "source_id": "fx:amb", "advance": 0},
        {"chemical": "gaba", "delta": 0.3, "duration_seconds": 60.0,
         "source_id": "fx:amb", "advance": 1},
    ])
    return {"scenarios": scenarios}


# ── emotions.json / faces.json ─────────────────────────────────────

def _random_states(rng: Random, n: int) -> list[dict[str, dict[str, float]]]:
    states = []
    for _ in range(n):
        states.append({
            "levels": {c: round(rng.uniform(0.0, 1.0), 6) for c in CHEMS},
            "baselines": {c: round(rng.uniform(0.1, 0.5), 6) for c in CHEMS},
        })
    return states


def gen_emotions(rng: Random) -> dict[str, Any]:
    cases = []
    specs = _random_states(rng, 50)
    # Baseline-neutrality anchor: levels exactly at species baselines.
    specs.append({
        "levels": {c.value: SPECIES_DEFAULTS[c]["baseline"] for c in Chemical},
        "baselines": {c.value: SPECIES_DEFAULTS[c]["baseline"] for c in Chemical},
    })
    for spec in specs:
        state = _make_state(spec["levels"], spec["baselines"])
        emotions = EmotionProjection.compute(state)
        cases.append({"input": spec, "expected": emotions.as_dict()})
    return {"cases": cases}


def gen_faces(rng: Random) -> dict[str, Any]:
    cases = []
    specs = _random_states(rng, 50)
    specs.append({
        "levels": {c.value: SPECIES_DEFAULTS[c]["baseline"] for c in Chemical},
        "baselines": {c.value: SPECIES_DEFAULTS[c]["baseline"] for c in Chemical},
    })
    for spec in specs:
        state = _make_state(spec["levels"], spec["baselines"])
        face = FaceProjection.compute(state)
        cases.append({"input": spec, "expected": face.as_dict()})
    return {"cases": cases}


# ── face_geometry.json ─────────────────────────────────────────────
#
# Mirrors the shape math in kindalive/expression/web_assets/face3d.js
# drawMask() (lines ~134-195). The Swift FaceGeometry must reproduce
# these scalars exactly; the JS file remains the reference.

MUSCLE_NAMES = [
    "brow_inner_raise", "brow_outer_raise", "brow_lower",
    "eyelid_upper_raise", "eyelid_lower_tighten", "cheek_raise",
    "nose_wrinkle", "lip_corner_pull", "lip_corner_depress",
    "jaw_open", "lip_pucker", "lip_press",
]

EYE_Y = 10.5
EYE_DX = 7.6
MOUTH_Y = 21.5
COLS = 36


def _geometry(m: dict[str, float], blink: float) -> dict[str, Any]:
    cx = COLS / 2
    s = m["lip_corner_pull"] - m["lip_corner_depress"]
    open_k = max(0.10, min(
        1.2, 0.52 + 0.55 * m["eyelid_upper_raise"] - 0.55 * m["eyelid_lower_tighten"]
    )) * (1 - blink)
    show_brow = (
        m["brow_lower"] > 0.18
        or m["brow_inner_raise"] > 0.28
        or m["brow_outer_raise"] > 0.4
    )
    happy_eyes = s > 0.34 and blink < 0.5
    eye_rotation = m["brow_lower"] * 0.45         # × sx per side
    eye_half_height = max(0.7, 1.0 + 3.6 * open_k)
    brow_inner_y = EYE_Y - 5.2 + 2.6 * m["brow_lower"] - 1.6 * m["brow_inner_raise"]
    brow_outer_y = EYE_Y - 5.2 - 1.3 * m["brow_outer_raise"]
    mouth_half_width = 7.0 * (1 - 0.3 * m["lip_pucker"])
    jaw = m["jaw_open"]
    mouth_open = jaw > 0.10
    return {
        "smile": s,
        "open_k": open_k,
        "show_brow": show_brow,
        "happy_eyes": happy_eyes,
        "eye_center_x_right": cx + EYE_DX,
        "eye_center_y": EYE_Y,
        "eye_rotation": eye_rotation,
        "eye_half_height": eye_half_height,
        "brow_inner_y": brow_inner_y,
        "brow_outer_y": brow_outer_y,
        "mouth_y": MOUTH_Y,
        "mouth_half_width": mouth_half_width,
        "mouth_open": mouth_open,
        "mouth_ellipse_center_y": MOUTH_Y + 1.6 * s,
        "mouth_ellipse_ry": 1.4 + 5.6 * jaw,
        "mouth_curve_end_y": MOUTH_Y - 1.6 * s,
        "mouth_curve_control_y": MOUTH_Y + 5.2 * s,
    }


def gen_face_geometry(rng: Random) -> dict[str, Any]:
    named = {
        "neutral": {n: 0.0 for n in MUSCLE_NAMES},
        "big_grin": dict({n: 0.0 for n in MUSCLE_NAMES},
                         lip_corner_pull=0.9, cheek_raise=0.8, jaw_open=0.3),
        "angry": dict({n: 0.0 for n in MUSCLE_NAMES},
                      brow_lower=0.8, eyelid_lower_tighten=0.6, lip_press=0.7),
        "sad": dict({n: 0.0 for n in MUSCLE_NAMES},
                    brow_inner_raise=0.7, lip_corner_depress=0.6),
        "surprised": dict({n: 0.0 for n in MUSCLE_NAMES},
                          brow_outer_raise=0.9, eyelid_upper_raise=0.9, jaw_open=0.8),
    }
    cases = []
    for name, muscles in named.items():
        for blink in [0.0, 0.5, 1.0]:
            cases.append({
                "name": f"{name}_blink_{blink}",
                "muscles": muscles,
                "blink": blink,
                "expected": _geometry(muscles, blink),
            })
    for i in range(20):
        muscles = {n: round(rng.uniform(0.0, 1.0), 6) for n in MUSCLE_NAMES}
        blink = round(rng.uniform(0.0, 1.0), 6)
        cases.append({
            "name": f"random_{i}",
            "muscles": muscles,
            "blink": blink,
            "expected": _geometry(muscles, blink),
        })
    return {"cases": cases}


# ── voice_params.json ──────────────────────────────────────────────

EMOTION_NAMES = [
    "happiness", "excitement", "anger", "calm",
    "bonding", "anxiety", "sadness", "euphoria",
]


def _voice_params(d: dict[str, float]) -> tuple[float, float]:
    # Mirrors kindalive/expression/web_ui.py::_voice_params
    arousal = d["excitement"] + d["anxiety"] + d["anger"]
    valence = d["happiness"] + d["euphoria"] - d["sadness"] - d["anxiety"]
    rate = max(0.8, min(1.3, 1.0 + 0.35 * min(1.0, arousal)))
    pitch = max(0.7, min(1.4, 1.0 + 0.30 * max(-1.0, min(1.0, valence))))
    return round(rate, 2), round(pitch, 2)


def gen_voice_params(rng: Random) -> dict[str, Any]:
    cases = []
    for _ in range(30):
        emotions = {n: round(rng.uniform(0.0, 1.0), 6) for n in EMOTION_NAMES}
        rate, pitch = _voice_params(emotions)
        cases.append({"emotions": emotions, "rate": rate, "pitch": pitch})
    return {"cases": cases}


# ── persistence_sample.json ────────────────────────────────────────

def gen_persistence_sample() -> dict[str, Any]:
    """A real serialize_engine() dump: drifted baseline + live sustained."""
    clock = ManualClock()
    engine = NeurochemicalEngine(clock=clock, seed=get_seed("anxious"))
    engine.apply_impulses([
        ChemicalImpulse(Chemical.CORTISOL, 0.5, source_id="fx:stress"),
        ChemicalImpulse(Chemical.ADRENALINE, 0.4, source_id="fx:stress"),
        ChemicalImpulse(Chemical.GABA, 0.25, duration_seconds=120.0,
                        source_id="fx:breathing", source_label="slow breathing"),
    ])
    # Long enough for cortisol baseline drift, short enough that the
    # sustained impulse is only partially consumed.
    clock.advance(seconds=45.0)
    engine.advance(45.0)
    return serialize_engine(engine)


# ── main ───────────────────────────────────────────────────────────

def main() -> None:
    rng = Random(SEED)
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    fixtures = {
        "decay.json": gen_decay(),
        "interactions.json": gen_interactions(),
        "engine_trajectories.json": gen_trajectories(),
        "saturation.json": gen_saturation(),
        "emotions.json": gen_emotions(rng),
        "faces.json": gen_faces(rng),
        "face_geometry.json": gen_face_geometry(rng),
        "voice_params.json": gen_voice_params(rng),
        "persistence_sample.json": gen_persistence_sample(),
    }
    for name, data in fixtures.items():
        path = FIXTURES_DIR / name
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
        print(f"wrote {path.relative_to(Path.cwd())}")


if __name__ == "__main__":
    main()
