#!/usr/bin/env python3
"""Synthesizes Kehai's four bundled notification sounds — cute, chiptune-y,
and all under a second (kb/features.md "Custom notification sounds").

Same spirit as tool/generate_tray_icon.py: the *source of truth is this
script*, not the binaries. Everything is written by hand out of square and
triangle waves with tiny envelopes — no samples, no libraries, no licences
to chase, and re-running this regenerates byte-identical files.

The four voices:

  sparkle — ascending 4-note square arpeggio (C6 E6 G6 C7). The headline
            "thinking of you" sound: it goes UP, which is the whole feeling.
  pop     — one soft square blip with a downward pitch bend. A doodle
            landing on the desk, not an alert.
  chime   — two triangle notes a fourth apart (G5 → C6) with a long-ish
            tail, faintly bell-like. Photos and the daily-question reveal.
  purr    — a low triangle (110 Hz) wobbling at ~17 Hz under a very soft
            envelope. The quiet one, for people who want to be told
            *gently*.

Output (16-bit mono PCM WAV, 44.1 kHz — the one format every platform can
play without a codec):

  assets/sounds/<name>.wav                     Flutter asset (desktop)
  android/app/src/main/res/raw/kehai_<name>.wav  Android channel sound

Android needs its own copy under res/raw because a NotificationChannel's
sound is a `android.resource://` URI resolved by the *system* UI process,
which cannot read our Flutter asset bundle.

Run: python3 tool/generate_notification_sounds.py   (from app/)
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
AMPLITUDE = 0.62  # headroom: these get mixed with whatever else is playing


def square(phase: float) -> float:
    """Square wave, 50% duty, phase in turns."""
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def soft_square(phase: float) -> float:
    """Square with a 25% duty — thinner, cuter, less harsh than 50%."""
    return 1.0 if (phase % 1.0) < 0.25 else -1.0


def triangle(phase: float) -> float:
    p = phase % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def envelope(t: float, duration: float, attack: float, release: float) -> float:
    """Trapezoid envelope. Attack kills clicks; release kills the buzz-cut
    ending that makes short chiptune blips sound broken."""
    if t < attack:
        return t / attack
    if t > duration - release:
        return max(0.0, (duration - t) / release)
    return 1.0


def render(
    samples: list[float],
    *,
    start: float,
    duration: float,
    freq,
    wave_fn,
    gain: float = 1.0,
    attack: float = 0.004,
    release: float = 0.035,
    tremolo: float = 0.0,
    tremolo_hz: float = 0.0,
) -> None:
    """Mixes one voice into `samples` (in place). `freq` may be a constant or
    a callable taking normalized time 0..1, which is how the pitch bends."""
    n = int(duration * RATE)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq(t / duration) if callable(freq) else freq
        phase += f / RATE
        value = wave_fn(phase) * gain * envelope(t, duration, attack, release)
        if tremolo:
            value *= 1.0 - tremolo * (0.5 - 0.5 * math.cos(2 * math.pi * tremolo_hz * t))
        index = int(start * RATE) + i
        while index >= len(samples):
            samples.append(0.0)
        samples[index] += value


def sparkle() -> list[float]:
    """Ascending arpeggio — C6, E6, G6, C7. 4 x 55ms, slightly overlapping so
    it reads as one gesture instead of four beeps."""
    samples: list[float] = []
    notes = [1046.50, 1318.51, 1567.98, 2093.00]
    for i, freq in enumerate(notes):
        render(
            samples,
            start=i * 0.052,
            duration=0.10 if i == len(notes) - 1 else 0.075,
            freq=freq,
            wave_fn=soft_square,
            gain=0.55 + 0.08 * i,  # crescendo into the top note
            release=0.05 if i == len(notes) - 1 else 0.03,
        )
    return samples


def pop() -> list[float]:
    """One blip with a downward bend, 90ms. Deliberately the least musical of
    the four — it's a little object landing, not a tune."""
    samples: list[float] = []
    render(
        samples,
        start=0.0,
        duration=0.09,
        freq=lambda u: 880.0 - 300.0 * (u**0.6),
        wave_fn=square,
        gain=0.8,
        attack=0.003,
        release=0.045,
    )
    return samples


def chime() -> list[float]:
    """Two triangle notes, G5 then C6, each with a faint octave shimmer on
    top — as close to a bell as two oscillators get."""
    samples: list[float] = []
    for i, freq in enumerate([783.99, 1046.50]):
        start = i * 0.14
        render(
            samples,
            start=start,
            duration=0.30 if i else 0.22,
            freq=freq,
            wave_fn=triangle,
            gain=0.9,
            attack=0.005,
            release=0.20 if i else 0.14,
        )
        render(
            samples,
            start=start,
            duration=0.18,
            freq=freq * 2,
            wave_fn=triangle,
            gain=0.22,
            attack=0.004,
            release=0.13,
        )
    return samples


def purr() -> list[float]:
    """Low soft wobble: 110 Hz triangle, amplitude wobbling at 17 Hz, plus a
    whisper of the fifth above so it isn't a plain hum."""
    samples: list[float] = []
    render(
        samples,
        start=0.0,
        duration=0.46,
        freq=lambda u: 112.0 - 8.0 * u,
        wave_fn=triangle,
        gain=0.95,
        attack=0.03,
        release=0.20,
        tremolo=0.55,
        tremolo_hz=17.0,
    )
    render(
        samples,
        start=0.02,
        duration=0.40,
        freq=165.0,
        wave_fn=triangle,
        gain=0.20,
        attack=0.04,
        release=0.22,
        tremolo=0.55,
        tremolo_hz=17.0,
    )
    return samples


VOICES = {
    "sparkle": sparkle,
    "pop": pop,
    "chime": chime,
    "purr": purr,
}


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = AMPLITUDE / peak
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * scale * 32767))))
        for s in samples
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def main() -> None:
    app = Path(__file__).resolve().parent.parent
    assets = app / "assets" / "sounds"
    raw = app / "android" / "app" / "src" / "main" / "res" / "raw"

    for name, voice in VOICES.items():
        samples = voice()
        write_wav(assets / f"{name}.wav", samples)
        # res/raw names must be lowercase [a-z0-9_]; prefixed so they can
        # never collide with a library's resource of the same name.
        write_wav(raw / f"kehai_{name}.wav", samples)
        seconds = len(samples) / RATE
        print(f"{name:8s} {seconds:.2f}s  ->  {assets.name}/{name}.wav + res/raw/kehai_{name}.wav")


if __name__ == "__main__":
    main()
