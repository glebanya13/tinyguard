#!/usr/bin/env python3
"""Synthesises Bimbleguard's sound effects into assets/audio/*.wav.

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


def cannon_shot():
    # Deep boom: low sine drop + noise burst.
    boom = shaped(tone(lambda t: 110 - 140 * t, 0.5), 0.002, 0.14)
    blast = shaped(lowpass(noise(0.5, 40), 0.18), 0.001, 0.08, 0.9)
    return mix(boom, blast)


def frost_shot():
    # Icy chime with a shimmering tail.
    layers = [shaped(tone(lambda t, f=f: f * (1 + 0.004 * math.sin(t * 40)), 0.45), 0.003, 0.12, a)
              for f, a in ((1568.0, 0.6), (2093.0, 0.4), (2637.0, 0.25))]
    return mix(*layers)


def sword_swing():
    # Whoosh: band-passed noise sweeping up.
    out = []
    raw = noise(0.22, 50)
    y = 0.0
    for i, s in enumerate(raw):
        k = 0.05 + 0.35 * (i / len(raw))
        y += k * (s - y)
        out.append(y * env(i / RATE, 0.05, 0.06))
    return out


def chop():
    # Axe into wood: sharp knock + creak.
    knock = shaped(tone(lambda t: 320 - 500 * t, 0.12), 0.0008, 0.03)
    crack = shaped(lowpass(noise(0.12, 60), 0.45), 0.0005, 0.02, 0.8)
    return mix(knock, crack)


def boss_roar():
    # Low growl with vibrato, for boss waves.
    def growl(p):
        return math.sin(p) + 0.5 * math.sin(2 * p + 0.3) + 0.3 * math.sin(3 * p)
    roar = tone(lambda t: 70 + 18 * math.sin(t * 22), 1.3, growl)
    rough = lowpass(noise(1.3, 70), 0.06)
    return [((a + 0.6 * b) * min(1.0, i / (0.15 * RATE)) * min(1.0, (len(roar) - i) / (0.4 * RATE)))
            for i, (a, b) in enumerate(zip(roar, rough))]


def zap():
    """Electric crackle: noisy buzz with a falling pitch."""
    buzz = shaped(tone(lambda t: 520 - 300 * t, 0.3, lambda p: 1.0 if math.sin(p) > 0 else -1.0), 0.002, 0.08, 0.5)
    crackle = [v if abs(v) > 0.6 else 0.0 for v in noise(0.3, 120)]
    return mix(buzz, shaped(crackle, 0.001, 0.06, 0.8))


def wave_boom():
    """Wave start: a deep explosion - thump, noisy blast and a rumbling tail."""
    thump = shaped(tone(lambda t: 70 * math.exp(-t * 3.0) + 28, 1.4), 0.004, 0.35)
    blast = shaped(lowpass(noise(1.4, 150), 0.25), 0.002, 0.12, 1.0)
    rumble = shaped(lowpass(noise(1.6, 151), 0.03), 0.05, 0.6, 1.4)
    crackle = shaped([v if abs(v) > 0.7 else 0.0 for v in noise(0.6, 152)], 0.01, 0.15, 0.3)
    return mix(thump, blast, rumble, crackle)


def music_loop():
    """Calm adventure loop: I-V-vi-IV in C, bass, soft pad, plucked melody and
    light percussion. 16 bars at 100 bpm; the end joins the start seamlessly."""
    bpm = 100
    beat = 60.0 / bpm
    bars = 16
    total = int(bars * 4 * beat * RATE)
    out = [0.0] * total

    def note_freq(n):  # MIDI note -> Hz
        return 440.0 * 2 ** ((n - 69) / 12)

    def add(start_s, dur_s, freq, amp, attack, decay, shape):
        i0 = int(start_s * RATE)
        n = int(dur_s * RATE)
        phase = 0.0
        step = 2 * math.pi * freq / RATE
        for k in range(n):
            idx = (i0 + k) % total  # wrap so the loop stays seamless
            t = k / RATE
            e = min(1.0, t / attack) * math.exp(-t / decay)
            out[idx] += shape(phase) * amp * e
            phase += step

    def tri(p):
        x = (p / (2 * math.pi)) % 1.0
        return 4 * abs(x - 0.5) - 1

    def pluck(p):
        return math.sin(p) + 0.3 * math.sin(2 * p) + 0.12 * math.sin(3 * p)

    chords = [(48, [60, 64, 67]), (43, [59, 62, 67]), (45, [57, 60, 64]), (41, [57, 60, 65])]
    scale = [60, 62, 64, 67, 69, 72, 74, 76]
    rng = random.Random(77)
    melody_shape = [0, 2, 4, 3, 2, 4, 5, 4, 3, 1, 2, 0, 1, 3, 2, 1]
    for bar in range(bars):
        root, chord = chords[bar % 4]
        t0 = bar * 4 * beat
        # Bass on beats 1 and 3, an octave jump on the "and" of 4.
        for b, off in ((0, 0), (2, 0), (3.5, 12)):
            add(t0 + b * beat, beat * 1.4, note_freq(root - 12 + off), 0.32, 0.01, 0.35, tri)
        # Pad: soft chord for the whole bar.
        for n in chord:
            add(t0, beat * 4, note_freq(n), 0.06, 0.4, 2.5, math.sin)
        # Melody: eighth notes, phrase changes every 4 bars.
        for eighth in range(8):
            if rng.random() < 0.3:
                continue
            idx = (melody_shape[(bar * 2 + eighth // 4) % 16] + (eighth % 4 == 2) * 2) % len(scale)
            n = scale[idx] + (12 if bar % 8 >= 4 and eighth % 2 == 0 else 0)
            add(t0 + eighth * beat / 2, beat * 0.9, note_freq(n), 0.12, 0.004, 0.22, pluck)
        # Percussion: soft kick on 1 and 3, shaker on eighths.
        for b in (0, 2):
            i0 = int((t0 + b * beat) * RATE)
            for k in range(int(0.18 * RATE)):
                t = k / RATE
                out[(i0 + k) % total] += 0.35 * math.sin(2 * math.pi * (55 + 90 * math.exp(-t * 30)) * t) * math.exp(-t * 18)
        shaker = noise(0.05, 900 + bar)
        for eighth in range(8):
            i0 = int((t0 + eighth * beat / 2) * RATE)
            amp = 0.05 if eighth % 2 else 0.03
            for k, v in enumerate(shaker):
                out[(i0 + k) % total] += v * amp * math.exp(-k / RATE * 60)
    return lowpass(out, 0.5)


def main() -> None:
    write("bow_shot", bow_shot(), 0.6)
    write("slime_hit", slime_hit(), 0.7)
    write("slime_pop", slime_pop(), 0.75)
    write("coin", coin(), 0.5)
    write("build", build(), 0.75)
    write("upgrade", upgrade(), 0.7)
    write("base_hit", base_hit(), 0.8)
    write("victory", jingle([523.25, 659.25, 783.99, 1046.5, 1318.5]), 0.7)
    write("defeat", jingle([392.0, 349.23, 311.13, 261.63], 0.2), 0.7)
    write("cannon_shot", cannon_shot(), 0.8)
    write("frost_shot", frost_shot(), 0.6)
    write("sword_swing", sword_swing(), 0.6)
    write("chop", chop(), 0.7)
    write("boss_roar", boss_roar(), 0.8)
    write("zap", zap(), 0.6)
    write("wave_boom", wave_boom(), 0.9)
    write("music_loop", music_loop(), 0.55)


if __name__ == "__main__":
    main()
