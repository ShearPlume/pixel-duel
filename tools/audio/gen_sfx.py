#!/usr/bin/env python3
"""Procedural sound design for the brawl build.

    py -3 tools/audio/gen_sfx.py

Writes 44.1 kHz mono 16-bit WAVs into art/audio/. Everything is synthesised
here (no sampled libraries), but each effect is layered like a real recording:
a fast transient, a body, and a decay tail, plus light plate reverb on the big
impacts. The game plays them through scripts/audio/sfx.gd, which throttles and
distance-mixes so a five player match does not turn into noise.
"""

import math
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "art" / "audio"
rng = np.random.default_rng(20261031)


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env_ad(n, attack=0.004, decay=0.18, curve=2.0):
    """Fast attack, exponential-ish decay: the shape of every impact."""
    attack_n = max(1, int(RATE * attack))
    out = np.ones(n)
    out[:attack_n] = np.linspace(0.0, 1.0, attack_n) ** 0.6
    tail = np.linspace(0.0, 1.0, n - attack_n)
    out[attack_n:] *= np.exp(-tail * curve) * (1.0 - tail) ** 0.4
    return out


def env_swell(n, peak=0.45):
    """Rise then fall: air, cloth, whooshes."""
    x = np.linspace(0.0, 1.0, n)
    return np.where(x < peak,
                    (x / peak) ** 1.6,
                    ((1.0 - x) / (1.0 - peak)) ** 1.4)


def noise(n, seed=None):
    local = np.random.default_rng(seed) if seed is not None else rng
    return local.uniform(-1.0, 1.0, n)


def lowpass(x, cutoff):
    """One pole low pass; enough for shaping noise without scipy."""
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out = np.empty_like(x)
    acc = 0.0
    for index in range(x.size):
        acc += alpha * (x[index] - acc)
        out[index] = acc
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, low, high):
    return highpass(lowpass(x, high), low)


def sweep_sine(start_hz, end_hz, seconds, shape="sine", vibrato=0.0, vibrato_hz=0.0):
    t = t_axis(seconds)
    progress = t / max(1e-6, seconds)
    freq = start_hz + (end_hz - start_hz) * progress
    if vibrato and vibrato_hz:
        freq = freq * (1.0 + vibrato * np.sin(2.0 * math.pi * vibrato_hz * t))
    phase = 2.0 * math.pi * np.cumsum(freq) / RATE
    if shape == "sine":
        return np.sin(phase)
    if shape == "triangle":
        return 2.0 / math.pi * np.arcsin(np.sin(phase))
    if shape == "square":
        return np.sign(np.sin(phase)) * 0.7
    if shape == "saw":
        return 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
    return np.sin(phase)


def pluck(freq, seconds, damping=0.9965):
    """Karplus-Strong: a real string model, cheap and convincing for a guitar."""
    n = int(RATE * seconds)
    period = max(2, int(RATE / freq))
    buffer = rng.uniform(-1.0, 1.0, period)
    out = np.empty(n)
    index = 0
    for i in range(n):
        out[i] = buffer[index]
        nxt = (index + 1) % period
        buffer[index] = damping * 0.5 * (buffer[index] + buffer[nxt])
        index = nxt
    return out


def reverb(x, mix=0.22, size=0.05):
    """Two combs and one allpass: a small room, enough to seat explosions."""
    delay = max(1, int(RATE * size))
    out = x.copy()
    for offset, gain in ((delay, 0.42), (int(delay * 1.7), 0.31)):
        if offset <= 0 or offset >= out.size:
            continue
        tail = np.zeros_like(out)
        tail[offset:] = out[:-offset] * gain
        out += tail
    return out * (1.0 - mix) + lowpass(out, 4200) * mix


def pad(x, seconds):
    n = int(RATE * seconds)
    if x.size >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - x.size)])


def mix(*tracks):
    length = max(track.size for track in tracks)
    out = np.zeros(length)
    for track in tracks:
        out[:track.size] += track
    return out


def finish(x, peak=0.85, drive=1.0):
    """Soft clip then normalise, so nothing ever clips the mixer."""
    if drive != 1.0:
        x = np.tanh(x * drive) / math.tanh(drive)
    top = float(np.max(np.abs(x))) or 1.0
    return (x / top) * peak


def write(name, samples):
    path = OUT / f"{name}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(samples, -1.0, 1.0)
    ints = (data * 32767.0).astype("<i2")
    import wave
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(ints.tobytes())
    peak = float(np.max(np.abs(data)))
    rms = float(np.sqrt(np.mean(data ** 2)))
    print(f"  {name:<14} {data.size / RATE * 1000:6.0f} ms  peak {peak:.2f}  rms {rms:.3f}")


def build():
    # --- movement -----------------------------------------------------------
    n = int(RATE * 0.15)
    jump = mix(
        bandpass(noise(n, 1), 500.0, 2400.0) * env_swell(n, 0.35) * 0.55,
        sweep_sine(170.0, 330.0, 0.15) * env_ad(n, 0.006, 0.15, 3.2) * 0.45,
    )
    write("jump", finish(jump, 0.62, 1.1))

    n = int(RATE * 0.17)
    double_jump = mix(
        bandpass(noise(n, 2), 900.0, 4200.0) * env_swell(n, 0.3) * 0.5,
        sweep_sine(260.0, 540.0, 0.17) * env_ad(n, 0.005, 0.17, 3.0) * 0.42,
    )
    write("jump_double", finish(double_jump, 0.6, 1.1))

    n = int(RATE * 0.13)
    land = mix(
        sweep_sine(120.0, 52.0, 0.13, "triangle") * env_ad(n, 0.003, 0.13, 4.2) * 0.85,
        lowpass(noise(n, 3), 900.0) * env_ad(n, 0.002, 0.09, 5.0) * 0.35,
    )
    write("land", finish(land, 0.7, 1.2))

    # --- impacts ------------------------------------------------------------
    n = int(RATE * 0.10)
    hit_light = mix(
        sweep_sine(240.0, 95.0, 0.10, "triangle") * env_ad(n, 0.002, 0.10, 4.0) * 0.8,
        bandpass(noise(n, 4), 700.0, 6000.0) * env_ad(n, 0.001, 0.05, 6.0) * 0.5,
    )
    write("hit_light", finish(hit_light, 0.85, 1.6))

    n = int(RATE * 0.24)
    hit_heavy = mix(
        sweep_sine(170.0, 58.0, 0.24, "triangle") * env_ad(n, 0.002, 0.24, 3.2) * 0.95,
        lowpass(noise(n, 5), 2600.0) * env_ad(n, 0.001, 0.12, 4.4) * 0.55,
        reverb(lowpass(noise(n, 6), 700.0) * env_ad(n, 0.004, 0.2, 3.0) * 0.25),
    )
    write("hit_heavy", finish(hit_heavy, 0.9, 1.9))

    # --- guitar -------------------------------------------------------------
    n = int(RATE * 0.24)
    swing = bandpass(noise(n, 7), 500.0, 2600.0) * env_swell(n, 0.5)
    swing *= 0.35 + 0.65 * np.linspace(0.0, 1.0, n) ** 3  # air builds toward contact
    write("guitar_swing", finish(swing, 0.5, 1.0))

    chord = np.zeros(int(RATE * 0.62))
    for index, freq in enumerate((196.0, 293.66, 392.0)):
        string = pluck(freq, 0.62, damping=0.9972)
        start = int(RATE * 0.012 * index)
        chord[start:start + string.size] += string[:chord.size - start] * (0.8 - 0.12 * index)
    n = chord.size
    crack = bandpass(noise(n, 8), 900.0, 7000.0) * env_ad(n, 0.001, 0.06, 6.0) * 0.5
    body = sweep_sine(150.0, 70.0, 0.18, "triangle") * env_ad(int(RATE * 0.18), 0.002, 0.18, 4.0) * 0.6
    guitar_hit = chord * env_ad(n, 0.002, 0.6, 1.6) + crack
    guitar_hit[:body.size] += body
    write("guitar_hit", finish(guitar_hit, 0.9, 1.4))

    # --- guns ---------------------------------------------------------------
    n = int(RATE * 0.10)
    pew = sweep_sine(1500.0, 480.0, 0.10, "square") * env_ad(n, 0.002, 0.10, 4.5)
    click = bandpass(noise(n, 9), 1500.0, 9000.0) * np.exp(-np.linspace(0, 1, n) * 40.0)
    write("pistol", finish(pew * 0.55 + click * 0.6, 0.62, 1.2))

    n = int(RATE * 0.20)
    bloop = sweep_sine(520.0, 240.0, 0.20, "sine", vibrato=0.06, vibrato_hz=22.0)
    bubble_fire = mix(
        bloop * env_ad(n, 0.01, 0.2, 3.0) * 0.6,
        bandpass(noise(n, 10), 600.0, 3000.0) * env_swell(n, 0.25) * 0.18,
    )
    write("bubble_fire", finish(bubble_fire, 0.5, 1.0))

    n = int(RATE * 0.12)
    pop = mix(
        bandpass(noise(n, 11), 400.0, 5000.0) * env_ad(n, 0.001, 0.06, 6.5) * 0.8,
        sweep_sine(900.0, 300.0, 0.12, "sine") * env_ad(n, 0.002, 0.12, 5.0) * 0.4,
    )
    pop = np.concatenate([pop, np.zeros(int(RATE * 0.06))])
    write("bubble_pop", finish(pop, 0.62, 1.3))

    # --- cake ---------------------------------------------------------------
    n = int(RATE * 0.26)
    cake_throw = bandpass(noise(n, 12), 300.0, 1400.0) * env_swell(n, 0.4)
    write("cake_throw", finish(cake_throw, 0.42, 1.0))

    n = int(RATE * 0.70)
    boom = sweep_sine(110.0, 34.0, 0.70, "sine") * env_ad(n, 0.004, 0.7, 2.6) * 0.95
    debris = lowpass(noise(n, 13), 2200.0) * env_ad(n, 0.002, 0.36, 3.4) * 0.55
    tail = reverb(lowpass(noise(n, 14), 900.0) * env_ad(n, 0.02, 0.6, 2.4) * 0.35, 0.3, 0.07)
    write("explosion", finish(mix(boom, debris, tail), 0.95, 1.6))

    # --- pickups ------------------------------------------------------------
    def chime(freqs, seconds, gain=0.5, shape="sine"):
        n = int(RATE * seconds)
        out = np.zeros(n)
        for index, freq in enumerate(freqs):
            start = int(RATE * 0.05 * index)
            note = sweep_sine(freq, freq, seconds - 0.05 * index, shape)
            note *= env_ad(note.size, 0.006, seconds - 0.05 * index, 4.0)
            out[start:start + note.size] += note * gain
        return out

    write("pickup", finish(chime((880.0, 1320.0), 0.20), 0.5, 1.0))
    write("heart", finish(chime((523.25, 659.25, 783.99), 0.40, 0.45, "triangle"), 0.55, 1.0))

    # --- match flow ---------------------------------------------------------
    n = int(RATE * 0.65)
    ko = mix(
        sweep_sine(420.0, 70.0, 0.65, "saw") * env_ad(n, 0.004, 0.65, 2.4) * 0.5,
        sweep_sine(120.0, 40.0, 0.65, "sine") * env_ad(n, 0.004, 0.65, 2.2) * 0.8,
        reverb(lowpass(noise(n, 15), 1200.0) * env_ad(n, 0.01, 0.5, 3.0) * 0.3, 0.28, 0.06),
    )
    write("ko", finish(ko, 0.85, 1.4))

    n = int(RATE * 0.45)
    respawn = mix(
        sweep_sine(300.0, 1250.0, 0.45, "sine") * env_swell(n, 0.55) * 0.55,
        bandpass(noise(n, 16), 1200.0, 6000.0) * env_swell(n, 0.6) * 0.2,
    )
    write("respawn", finish(respawn, 0.5, 1.0))

    # --- ui -----------------------------------------------------------------
    n = int(RATE * 0.07)
    write("select_move", finish(
        bandpass(noise(n, 17), 1800.0, 7000.0) * np.exp(-np.linspace(0, 1, n) * 9.0) * 0.6,
        0.35, 1.0))
    n = int(RATE * 0.26)
    confirm = chime((660.0, 990.0), 0.26, 0.5, "triangle")
    write("select_confirm", finish(confirm, 0.55, 1.0))


def main():
    print(f"writing SFX to {OUT}")
    build()
    print(f"done: {len(list(OUT.glob('*.wav')))} files")


if __name__ == "__main__":
    main()
