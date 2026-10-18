"""Generate deterministic, original placeholder music and Foley for M2-J5."""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


RATE = 22_050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio"
TAU = math.tau


def tone(freq: float, time: float) -> float:
    """A soft clay-marimba tone with a short, hollow overtone."""
    phase = TAU * freq * time
    return math.sin(phase) * 0.75 + math.sin(phase * 2.01) * 0.18 + math.sin(phase * 3.0) * 0.07


def note(time: float, start: float, length: float, freq: float) -> float:
    age = time - start
    if age < 0 or age >= length:
        return 0.0
    attack = min(1.0, age / 0.012)
    release = min(1.0, (length - age) / 0.12)
    return tone(freq, age) * attack * release * math.exp(-age * 1.8)


def write(name: str, seconds: float, sample_fn) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    count = int(seconds * RATE)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        samples = bytearray()
        for i in range(count):
            time = i / RATE
            # Small fade at both edges prevents clicks when a stem loops.
            edge = min(1.0, time / 0.02, (seconds - time) / 0.02)
            value = max(-1.0, min(1.0, sample_fn(time) * edge))
            samples.extend(struct.pack("<h", int(value * 32767)))
        wav.writeframes(samples)


def music(notes: tuple[int, ...], *, bpm: int, pulse: float, bass: float, accent: float):
    beat = 60.0 / bpm
    bar = beat * len(notes)

    def sample(time: float) -> float:
        step = int(time / beat)
        start = step * beat
        frequency = 440.0 * (2.0 ** ((notes[step % len(notes)] - 69) / 12.0))
        melody = note(time, start, beat * 0.88, frequency) * 0.29
        low = note(time, (step // 2) * beat * 2, beat * 1.8, frequency / 4.0) * bass
        rhythm_age = time % beat
        rhythm = (math.sin(TAU * (68.0 - rhythm_age * 30.0) * rhythm_age)
                  * math.exp(-rhythm_age * 26.0) * pulse)
        click = (math.sin(TAU * 1200.0 * rhythm_age)
                 * math.exp(-rhythm_age * 95.0) * accent if step % 2 else 0.0)
        return melody + low + rhythm + click

    return bar, sample


def main() -> None:
    tracks = {
        "music_intermission": ((60, 64, 67, 64, 62, 65, 67, 65), 92, 0.025, 0.13, 0.01),
        "music_siren": ((60, 63, 66, 69, 60, 63, 67, 70), 112, 0.09, 0.19, 0.04),
        "music_combat": ((60, 67, 63, 70, 60, 67, 65, 70), 136, 0.18, 0.20, 0.08),
        "music_boss": ((48, 55, 51, 58, 48, 55, 53, 59), 126, 0.22, 0.27, 0.10),
        "music_cleared": ((72, 76, 79, 84), 110, 0.015, 0.07, 0.02),
        "music_game_over": ((60, 59, 55, 48), 72, 0.01, 0.15, 0.0),
    }
    for name, (notes, bpm, pulse, bass, accent) in tracks.items():
        duration, sample = music(notes, bpm=bpm, pulse=pulse, bass=bass, accent=accent)
        write(name, duration, sample)

    write("siren", 1.45, lambda t:
          (math.sin(TAU * (330 * t + 140 * t * t))
           + 0.35 * math.sin(TAU * (660 * t + 280 * t * t)))
          * 0.23 * min(1.0, t / 0.12) * min(1.0, (1.45 - t) / 0.22))

    write("pistol", 0.27, lambda t:
          (random.Random(int(t * RATE) + 7).uniform(-1, 1) * math.exp(-t * 28) * 0.42
           + math.sin(TAU * (155 * t - 130 * t * t)) * math.exp(-t * 18) * 0.36))

    write("wrench", 0.32, lambda t:
          (math.sin(TAU * (250 * t + 450 * t * t)) * math.exp(-t * 16) * 0.25
           + math.sin(TAU * 920 * t) * math.exp(-t * 34) * 0.10))

    write("robot_pop", 0.40, lambda t:
          (math.sin(TAU * (440 * t - 310 * t * t)) * math.exp(-t * 11) * 0.29
           + math.sin(TAU * 120 * t) * math.exp(-t * 22) * 0.18))

    rng = random.Random(45)
    noise = [rng.uniform(-1, 1) for _ in range(int(RATE * 1.2))]
    write("grain_leak", 1.2, lambda t:
          (noise[int(t * RATE)] * 0.08
           + math.sin(TAU * 85 * t) * 0.02))


if __name__ == "__main__":
    main()
