#!/usr/bin/env python3
"""Synthesises Kisel's interface sounds.

They are meant to sound like the characters look: soft, round, a little wet,
and quiet: low notes, felt on every hammer, the top end rolled off, nothing near full level. Three
voices make all of them, in one key (C major pentatonic) so that any two heard one
after another still agree:

  bubble   a sine that glides in pitch as it swells and dies: a drop, a jelly "bloop"
  mallet   a soft wooden bar (a fundamental, a short knock of overtones): the notes
  glass    a small bell with a long thin ring: the sparkle on top

Every sound sits in a little room (a short reverb) and is stereo: the notes of a run
step from one side to the other, the sparkles scatter.

  hover    a bubble no bigger than a pinhead
  click    a jelly pop
  open     a drop rising into two notes, a glint after        close  the same, falling
  send     a quick step up and away                           receive  a "plip" coming down
  done     four notes up, a bell on the last, a shower of sparkles
  alert    two glass pings, the second answering from the other side
  deny     two muffled notes going down
  dizzy    a wobbling run that staggers up and falls over

No dependencies beyond the standard library. Output: resources/sounds/*.wav (stereo,
16-bit, 44.1 kHz). Run again to regenerate; the files are committed.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "resources" / "sounds"
TAU = 2 * math.pi
random.seed(7)  # (the sparkles fall the same way every time the script is run)

# C major pentatonic, the octaves the sounds live in
C4, D4, E4, G4, A4 = 261.63, 293.66, 329.63, 392.00, 440.00
C5, D5, E5, G5, A5 = 523.25, 587.33, 659.25, 783.99, 880.00
C6, D6, E6, G6, A6, C7 = 1046.50, 1174.66, 1318.51, 1567.98, 1760.00, 2093.00


def voice(ms, f0, f1=None, glide_ms=0.0, partials=((1, 1.0, 6.0),), attack_ms=5.0, vibrato=0.0, vib_hz=6.0):
    """One note. `partials` are (multiple of the pitch, loudness, how fast it dies).
    The pitch runs from f0 to f1 over `glide_ms` (an even slide in pitch, not in hertz)."""
    n = int(RATE * ms / 1000)
    out = [0.0] * n
    phase = 0.0
    attack = max(1, int(RATE * attack_ms / 1000))
    glide = max(1.0, RATE * glide_ms / 1000)
    ratio = (f1 / f0) if f1 else 1.0
    for i in range(n):
        t = i / RATE
        f = f0 * ratio ** min(1.0, i / glide) if f1 else f0
        if vibrato:
            f *= 1 + vibrato * math.sin(TAU * vib_hz * t)
        phase += TAU * f / RATE
        s = 0.0
        for mult, amp, die in partials:
            s += amp * math.exp(-die * t) * math.sin(mult * phase)
        a = i / attack
        out[i] = s * (0.5 - 0.5 * math.cos(math.pi * a) if a < 1 else 1.0)  # a rounded attack: no click
    return out


def bubble(f0, f1, ms, glide_ms=None):
    """A drop: a pure tone sliding from f0 to f1 while it swells and dies."""
    return voice(ms, f0, f1, glide_ms or ms * 0.7, partials=((1, 1.0, 1000 * 4.5 / ms), (2, 0.04, 1000 * 7 / ms)), attack_ms=min(16.0, ms * 0.3))


def mallet(freq, ms=420, soft=1.0):
    """A soft wooden bar struck with a felt head: the note and a breath of the octave
    above it, with hardly any knock."""
    return voice(ms, freq, partials=((1, 1.0, 7.0 / soft), (2, 0.1, 12.0), (4.0, 0.025 * soft, 32.0)), attack_ms=9.0)


def glass(freq, ms=900, shimmer=0.0):
    """A small bell heard from the next room: mostly its note, the ring kept short of harsh."""
    return voice(ms, freq, partials=((1, 1.0, 4.8), (2.76, 0.1, 9.0), (5.4, 0.02, 16.0)), attack_ms=7.0, vibrato=shimmer, vib_hz=5.0)


class Mix:
    """A stereo strip of `ms`: sounds are laid into it at a time, a loudness and a place
    between the ears (-1 left .. 1 right)."""

    def __init__(self, ms):
        n = int(RATE * ms / 1000)
        self.l = [0.0] * n
        self.r = [0.0] * n

    def add(self, sound, at_ms=0.0, gain=1.0, pan=0.0):
        at = int(RATE * at_ms / 1000)
        a = (pan + 1) * math.pi / 4  # equal power
        gl, gr = gain * math.cos(a), gain * math.sin(a)
        for i, s in enumerate(sound):
            j = at + i
            if j >= len(self.l):
                break
            self.l[j] += s * gl
            self.r[j] += s * gr
        return self

    def room(self, wet=0.16, size=1.0, damp=0.45):
        """A small soft room: four echoes that feed themselves, the highs dying first,
        crossed over between the two sides."""
        for src, dst, delays in ((self.l, self.r, (29.7, 37.1, 41.1, 47.3)), (self.r, self.l, (31.3, 35.9, 43.7, 49.1))):
            n = len(src)
            tail = [0.0] * n
            for ms in delays:
                d = int(RATE * ms * size / 1000)
                buf = [0.0] * n
                low = 0.0
                for i in range(n):
                    back = buf[i - d] if i >= d else 0.0
                    low += (back - low) * (1 - damp)
                    buf[i] = src[i] + low * 0.72
                    tail[i] += back
            for i in range(n):
                dst[i] += tail[i] * wet * 0.25
        return self


def soften(samples, cutoff=2600.0, passes=2):
    """Rolls the top end off (a one-pole low-pass, run twice): nothing bites."""
    k = 1 - math.exp(-TAU * cutoff / RATE)
    for _ in range(passes):
        low = 0.0
        for i, s in enumerate(samples):
            low += (s - low) * k
            samples[i] = low


def save(name, mix, peak=0.5):
    soften(mix.l)
    soften(mix.r)
    n = len(mix.l)
    fade = int(RATE * 0.012)
    for i in range(fade):  # (whatever is left of the ring goes out smoothly)
        k = i / fade
        mix.l[n - 1 - i] *= k
        mix.r[n - 1 - i] *= k
    top = max(1e-9, max(max(abs(s) for s in mix.l), max(abs(s) for s in mix.r)))
    scale = peak / top
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<hh", int(32767 * a * scale), int(32767 * b * scale)) for a, b in zip(mix.l, mix.r)))
    print(f"{name}: {n * 1000 // RATE} ms")


def sparkles(mix, at_ms, count, span_ms, notes, gain=0.16):
    """A scatter of tiny bells, each a little later and somewhere else between the ears."""
    for k in range(count):
        t = at_ms + span_ms * (k / count) ** 1.3 + random.uniform(-12, 12)
        mix.add(glass(random.choice(notes), 380), t, gain * random.uniform(0.6, 1.0), random.uniform(-0.9, 0.9))


OUT.mkdir(parents=True, exist_ok=True)

# hover: a bubble no bigger than a pinhead (it is heard a lot: it must never tire)
save("hover", Mix(110).add(bubble(700, 880, 55), 0, 1.0).room(0.08, 0.5), peak=0.22)

# click: a jelly pop, with a little wood under it
save("click", Mix(240).add(bubble(300, 460, 85), 0, 1.0).add(mallet(G4, 170, 0.7), 4, 0.3).room(0.12, 0.6), peak=0.36)

# open: a drop rising into two notes, and a glint after
m = Mix(820)
m.add(bubble(220, 440, 140), 0, 0.8, -0.2)
m.add(mallet(E4, 400), 55, 0.75, -0.3).add(mallet(A4, 480), 150, 0.85, 0.3)
m.add(glass(E5, 520), 215, 0.1, 0.5).add(glass(A5, 480), 275, 0.08, -0.5)
save("open", m.room(0.2))

# close: the same, falling
m = Mix(700)
m.add(mallet(A4, 360), 0, 0.75, 0.3).add(mallet(E4, 440), 95, 0.8, -0.3)
m.add(bubble(440, 220, 170), 150, 0.6, 0.0)
save("close", m.room(0.18), peak=0.46)

# send: a quick step up and away
m = Mix(520)
m.add(bubble(330, 660, 100), 0, 0.7, -0.4)
m.add(mallet(G4, 260), 30, 0.7, -0.2).add(mallet(D5, 340), 105, 0.8, 0.4)
m.add(glass(G5, 300), 150, 0.07, 0.7)
save("send", m.room(0.16, 0.8), peak=0.46)

# receive: a "plip" coming down
m = Mix(560)
m.add(mallet(D5, 260), 0, 0.7, 0.4).add(mallet(G4, 360), 80, 0.8, -0.2)
m.add(bubble(620, 360, 120), 85, 0.5, -0.1)
save("receive", m.room(0.16, 0.8), peak=0.46)

# done: four notes up, a bell on the last, a shower of sparkles
m = Mix(1500)
for k, (note, pan) in enumerate(((C4, -0.5), (E4, -0.15), (G4, 0.15), (C5, 0.5))):
    m.add(mallet(note, 520), k * 82, 0.72 + 0.07 * k, pan)
    m.add(bubble(note * 0.75, note, 70), k * 82, 0.18, pan)
m.add(glass(C5, 1100, 0.002), 250, 0.36, 0.0).add(glass(G5, 950), 262, 0.14, -0.4).add(glass(E5, 950), 274, 0.12, 0.4)
sparkles(m, 340, 7, 620, (G5, A5, C6, D6, E6), gain=0.07)
save("done", m.room(0.24, 1.15))

# alert: two glass pings, the second answering from the other side
m = Mix(900)
m.add(glass(E5, 520), 0, 0.7, -0.35).add(mallet(E5, 280), 0, 0.5, -0.35)
m.add(glass(E5, 620), 200, 0.8, 0.35).add(mallet(E5, 280), 200, 0.5, 0.35)
m.add(glass(A5, 500), 205, 0.08, 0.0)
save("alert", m.room(0.2))

# deny: two muffled notes going down
m = Mix(620)
m.add(mallet(E4, 300, 0.45), 0, 0.9, 0.2).add(mallet(C4, 420, 0.4), 130, 1.0, -0.2)
m.add(bubble(260, 180, 140), 135, 0.3, -0.1)
save("deny", m.room(0.14, 0.9), peak=0.46)

# dizzy: a wobbling run that staggers up and falls over
m = Mix(1050)
for k, note in enumerate((E4, G4, D4, A4, E4, C5)):
    pan = 0.75 * math.sin(k * 1.9)
    m.add(voice(230, note, note * 1.04, 200, partials=((1, 1.0, 9.0), (2, 0.08, 13.0)), attack_ms=10, vibrato=0.03, vib_hz=9), k * 78, 0.7, pan)
m.add(bubble(700, 200, 340), 470, 0.5, 0.0)
m.add(glass(E5, 380, 0.01), 500, 0.07, -0.6).add(glass(G5, 380, 0.01), 590, 0.07, 0.6)
save("dizzy", m.room(0.2), peak=0.46)
