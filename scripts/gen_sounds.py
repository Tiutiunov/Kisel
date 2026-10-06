#!/usr/bin/env python3
"""Synthesises Kisel's interface sounds: short, soft bloops under 400 ms.

Matches the table in the design system's motion.md ("Sound pairing"):
  open   rising two-note chirp        close  falling two-note chirp
  click  short low blip               send / receive  small up / down blips
  done   four-note rising arpeggio    alert  two equal pings
  deny   soft falling pair            dizzy  wobbling four-note run
  hover  barely-there tick

No dependencies beyond the standard library. Output: resources/sounds/*.wav
(mono, 16-bit, 44.1 kHz). Run again to regenerate; the files are committed.
"""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "resources" / "sounds"


def tone(freq, ms, vol=0.5, vibrato=0.0):
    n = int(RATE * ms / 1000)
    out = []
    for i in range(n):
        t = i / RATE
        f = freq * (1 + vibrato * math.sin(2 * math.pi * 14 * t))
        # soft attack (8 ms) and exponential release keep it bloop-like, no clicks
        env = min(1.0, i / (RATE * 0.008)) * math.exp(-4.2 * i / n)
        s = math.sin(2 * math.pi * f * t) + 0.18 * math.sin(2 * math.pi * 2 * f * t)
        out.append(vol * env * s)
    return out


def seq(notes, gap_ms=0):
    out = []
    for f, ms, *rest in notes:
        out += tone(f, ms, *rest)
        out += [0.0] * int(RATE * gap_ms / 1000)
    return out


def save(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * s * scale)) for s in samples))
    print(f"{name}: {len(samples) * 1000 // RATE} ms")


C5, E5, G5, C6 = 523.25, 659.25, 783.99, 1046.5

OUT.mkdir(parents=True, exist_ok=True)
save("open", seq([(660, 90), (880, 150)]))
save("close", seq([(880, 90), (587, 150)]))
save("click", tone(330, 70, 0.55))
save("send", seq([(520, 60), (780, 110)]))
save("receive", seq([(780, 60), (520, 110)]))
save("done", seq([(C5, 80), (E5, 80), (G5, 80), (C6, 170)]))
save("alert", seq([(880, 110), (880, 140)], gap_ms=70))
save("deny", seq([(392, 110), (294, 190)]))
save("dizzy", seq([(500, 70, 0.5, 0.03), (650, 70, 0.5, 0.03), (480, 70, 0.5, 0.03), (700, 120, 0.5, 0.03)]))
save("hover", tone(1200, 30, 0.25))
