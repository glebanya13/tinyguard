#!/usr/bin/env python3
"""Synthesises Tinyguard's sound effects into assets/audio/*.wav.

Pure Python (no dependencies), deterministic: same output on every run.
Usage: python3 tools/gen_sounds.py
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"


def env(t: float, attack: float, decay: float) -> float:
    """Linear attack, exponential decay."""
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def lowpass(samples: list[float], k: float) -> list[float]:
    out, y = [], 0.0
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def write(name: str, samples: list[float], gain: float = 0.8) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * gain * 32767)) for s in samples))
    print(f"assets/audio/{name}.wav  {len(samples) / RATE:.2f} s")


def tone(freq_fn, dur: float, shape=math.sin) -> list[float]:
    out, phase = [], 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        phase += 2 * math.pi * freq_fn(t) / RATE
        out.append(shape(phase))
    return out


def noise(dur: float, seed: int) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-1, 1) for _ in range(int(dur * RATE))]


def mix(*layers: list[float]) -> list[float]:
    n = max(len(layer) for layer in layers)
    return [sum(layer[i] if i < len(layer) else 0.0 for layer in layers) for i in range(n)]


def shaped(samples, attack, decay, amp=1.0):
    return [s * amp * env(i / RATE, attack, decay) for i, s in enumerate(samples)]


def bow_shot():
    # Crossbow: string twang (falling pitch) + short woody click.
    twang = shaped(tone(lambda t: 190 * (1 + 0.6 * math.exp(-t * 40)), 0.32,
                        lambda p: math.sin(p) + 0.35 * math.sin(2 * p)), 0.002, 0.07)
    click = shaped(lowpass(noise(0.05, 1), 0.5), 0.0005, 0.008, 0.8)
    whoosh = shaped(lowpass(noise(0.25, 2), 0.08), 0.03, 0.06, 0.5)
    return mix(twang, click, whoosh)


def slime_hit():
    # Wet "splat": low sine drop with filtered noise.
    body = shaped(tone(lambda t: 150 - 220 * t, 0.16), 0.003, 0.05)
    squish = shaped(lowpass(noise(0.16, 3), 0.15), 0.002, 0.04, 0.9)
    return mix(body, squish)


def slime_pop():
    # Bubble pop rising in pitch, then a splash.
    pop = shaped(tone(lambda t: 260 + 900 * t, 0.12), 0.002, 0.05)
    splash = shaped(lowpass(noise(0.35, 4), 0.25), 0.01, 0.09, 0.7)
    bubbles = []
    for k, (start, f) in enumerate([(0.06, 520), (0.11, 700), (0.16, 600)]):
        b = [0.0] * int(start * RATE) + shaped(tone(lambda t, f=f: f + 400 * t, 0.06), 0.002, 0.02, 0.4)
        bubbles.append(b)
    return mix(pop, splash, *bubbles)


def coin():
    # Two bright dings, like a coin pickup.
    def ding(f, start):
        return [0.0] * int(start * RATE) + shaped(
            tone(lambda t: f, 0.3, lambda p: math.sin(p) + 0.3 * math.sin(3 * p)), 0.002, 0.08)
    return mix(ding(1318.5, 0.0), ding(1760.0, 0.07))


def build():
    # Three wooden knocks and a soft chime.
    layers = []
    for k, start in enumerate([0.0, 0.16, 0.32]):
        knock = shaped(tone(lambda t: 220 - 300 * t, 0.12), 0.001, 0.025)
        thud = shaped(lowpass(noise(0.1, 10 + k), 0.2), 0.001, 0.02, 0.8)
        layers.append([0.0] * int(start * RATE) + mix(knock, thud))
    chime = [0.0] * int(0.48 * RATE) + shaped(tone(lambda t: 880, 0.5, lambda p: math.sin(p) + 0.2 * math.sin(2 * p)),
                                              0.005, 0.15, 0.6)
    return mix(*layers, chime)


def upgrade():
    # Rising arpeggio with sparkle.
    layers = []
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        start = k * 0.08
        layers.append([0.0] * int(start * RATE) + shaped(
            tone(lambda t, f=f: f, 0.4, lambda p: math.sin(p) + 0.25 * math.sin(2 * p)), 0.003, 0.12, 0.8))
    sparkle = shaped([s * math.sin(i * 0.9) for i, s in enumerate(noise(0.6, 20))], 0.05, 0.15, 0.15)
    return mix(*layers, sparkle)


def wave_horn():
    # Brassy horn: detuned saw-like tones with vibrato.
    def saw(p):
        return sum(math.sin(k * p) / k for k in range(1, 7))
    a = tone(lambda t: 196 * (1 + 0.006 * math.sin(t * 30)), 1.1, saw)
    b = tone(lambda t: 294 * (1 + 0.006 * math.sin(t * 31)), 1.1, saw)
    horn = [(x + 0.7 * y) for x, y in zip(a, b)]
    horn = lowpass(horn, 0.18)
    return [s * min(1.0, i / (0.12 * RATE)) * min(1.0, (len(horn) - i) / (0.3 * RATE)) for i, s in enumerate(horn)]


def base_hit():
    # Low thump with a crumble.
    thump = shaped(tone(lambda t: 90 - 40 * t, 0.4), 0.002, 0.12)
    crumble = shaped(lowpass(noise(0.4, 30), 0.1), 0.01, 0.1, 0.6)
    return mix(thump, crumble)


def jingle(notes, dur_each=0.14):
    layers = []
    for k, f in enumerate(notes):
        layers.append([0.0] * int(k * dur_each * RATE) + shaped(
            tone(lambda t, f=f: f, 0.6, lambda p: math.sin(p) + 0.3 * math.sin(2 * p) + 0.1 * math.sin(3 * p)),
            0.004, 0.18, 0.8))
    return mix(*layers)


def main() -> None:
    write("bow_shot", bow_shot(), 0.6)
    write("slime_hit", slime_hit(), 0.7)
    write("slime_pop", slime_pop(), 0.75)
    write("coin", coin(), 0.5)
    write("build", build(), 0.75)
    write("upgrade", upgrade(), 0.7)
    write("wave_horn", wave_horn(), 0.7)
    write("base_hit", base_hit(), 0.8)
    write("victory", jingle([523.25, 659.25, 783.99, 1046.5, 1318.5]), 0.7)
    write("defeat", jingle([392.0, 349.23, 311.13, 261.63], 0.2), 0.7)


if __name__ == "__main__":
    main()
