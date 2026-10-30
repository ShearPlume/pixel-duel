#!/usr/bin/env python3
"""Placeholder SFX generator: tiny synthesized WAVs for the demo build.

    py -3 tools/audio/gen_sfx.py [output-dir]

Pure standard library (wave + math + random), 44.1 kHz mono 16-bit.
These are intentionally crude placeholders, not final sound design.
"""

import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100


def envelope(index, total, attack=0.005, decay=1.0):
    t = index / RATE
    length = total / RATE
    if t < attack:
        return t / attack
    return max(0.0, (1.0 - (t - attack) / max(1e-6, length - attack))) ** decay


def tone(freq_start, freq_end, seconds, decay=2.0, shape="sine", gain=0.9):
    total = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(total):
        progress = i / max(1, total - 1)
        freq = freq_start + (freq_end - freq_start) * progress
        phase += 2.0 * math.pi * freq / RATE
        if shape == "sine":
            value = math.sin(phase)
        elif shape == "square":
            value = 1.0 if math.sin(phase) >= 0.0 else -1.0
        elif shape == "saw":
            value = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
        else:
            value = math.sin(phase) * 0.7 + math.sin(phase * 2.0) * 0.3
        out.append(value * envelope(i, total, decay=decay) * gain)
    return out


def noise(seconds, decay=3.0, lowpass=0.35, gain=0.7, start=0):
    total = int(RATE * seconds)
    out = [0.0] * (start + total)
    previous = 0.0
    rng = random.Random(1234)
    for i in range(total):
        value = rng.uniform(-1.0, 1.0)
        previous += (value - previous) * lowpass
        out[start + i] = previous * envelope(i, total, decay=decay) * gain
    return out


def mix(*tracks):
    length = max(len(track) for track in tracks)
    out = [0.0] * length
    for track in tracks:
        for index, value in enumerate(track):
            out[index] += value
    return out


def soft_clip(samples, drive=1.6):
    return [math.tanh(value * drive) / math.tanh(drive) for value in samples]


def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32000)) for value in samples
        )
        handle.writeframes(frames)
    print(f"  {path.name}: {len(samples) / RATE * 1000:.0f} ms")


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("audio/sfx")
    print(f"writing placeholder SFX to {out_dir}")

    write_wav(out_dir / "hit_light.wav", soft_clip(mix(
        tone(240.0, 90.0, 0.085, decay=3.5, gain=0.85),
        noise(0.055, decay=5.0, lowpass=0.5, gain=0.55),
    )))

    write_wav(out_dir / "hit_heavy.wav", soft_clip(mix(
        tone(180.0, 55.0, 0.16, decay=2.6, gain=1.0, shape="triangle"),
        noise(0.10, decay=4.0, lowpass=0.3, gain=0.7),
    ), drive=2.2))

    write_wav(out_dir / "hurt.wav", soft_clip(mix(
        tone(340.0, 150.0, 0.22, decay=2.0, gain=0.55, shape="saw"),
        noise(0.12, decay=4.0, lowpass=0.22, gain=0.3, start=int(RATE * 0.01)),
    ), drive=1.4))

    write_wav(out_dir / "whiff.wav", soft_clip(
        noise(0.13, decay=2.6, lowpass=0.75, gain=0.45), drive=1.2
    ))

    write_wav(out_dir / "jump.wav", soft_clip(
        tone(210.0, 460.0, 0.10, decay=2.2, gain=0.45, shape="triangle"), drive=1.2
    ))

    write_wav(out_dir / "land.wav", soft_clip(mix(
        tone(150.0, 70.0, 0.10, decay=4.0, gain=0.7),
        noise(0.07, decay=5.0, lowpass=0.25, gain=0.5),
    ), drive=1.5))


if __name__ == "__main__":
    main()
