#!/usr/bin/env python3
"""Mix the 60s teaser soundtrack: synthesized score + in-game SFX."""
import numpy as np
import wave
import os

SR = 44100
DUR = 60.0
N = int(SR * DUR)

A = "/home/user/alchemists-loop/teaser/assets/sfx"
OUT = "/home/user/alchemists-loop/teaser/audio/mix.wav"


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        nch = w.getnchannels()
        sw = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if sw != 2:
        raise ValueError(f"expect 16-bit: {path}")
    d = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32767.0
    if nch == 2:
        d = d.reshape(-1, 2).mean(axis=1)
    return d, sr


def resample(d, sr, target=SR):
    if sr == target:
        return d
    x_old = np.arange(len(d)) / sr
    x_new = np.arange(int(len(d) * target / sr)) / target
    return np.interp(x_new, x_old, d)


mix = np.zeros((N, 2))


def put(path, t, gain=0.6, trim=(0.0, None), fade_in=0.005, fade_out=0.03,
        pan=0.0, pitch=1.0):
    d, sr = read_wav(path)
    if pitch != 1.0:
        idx = np.arange(0, len(d), pitch)
        d = np.interp(idx, np.arange(len(d)), d)
    a, b = trim
    d = d[int(a * sr): int(b * sr) if b else None]
    n = min(len(d), int((DUR - t) * SR))
    if n <= 0:
        return
    i0 = int(t * SR)
    seg = d[:n].copy()
    fi, fo = int(fade_in * SR), int(fade_out * SR)
    if fi > 0 and fi < n:
        seg[:fi] *= np.linspace(0, 1, fi)
    if fo > 0 and fo < n:
        seg[-fo:] *= np.linspace(1, 0, fo)
    gl = gain * (1.0 - max(0.0, pan)) ** 0.5
    gr = gain * (1.0 + min(0.0, pan)) ** 0.5
    mix[i0:i0 + n, 0] += seg * gl
    mix[i0:i0 + n, 1] += seg * gr


# --- SFX timeline (times tuned to storyboard beats) ---
put(f"{A}/sparkle.wav",        0.45, gain=0.40, trim=(0.2, 2.6))
put(f"{A}/whoosh_mystery.wav", 3.05, gain=0.34, trim=(0.6, 3.4))
put(f"{A}/whoosh_mystery.wav", 5.15, gain=0.42, trim=(0.4, 3.2))          # scene 2 in
put(f"{A}/swoosh.wav",         8.05, gain=0.42)                            # water orb throw
put(f"{A}/swoosh.wav",         8.55, gain=0.42, pitch=1.06)                # fire orb throw
put(f"{A}/bubbles.wav",        8.70, gain=0.55, trim=(0.0, 1.67))          # cauldron boils
put(f"{A}/success.wav",        9.75, gain=0.55, trim=(0.0, 2.6))           # ПАР reveal
put(f"{A}/whoosh_gust.wav",   13.40, gain=0.40, trim=(0.0, 3.4))           # scene 3 in
put(f"{A}/unlock.wav",        15.10, gain=0.30)                            # feed row
put(f"{A}/unlock.wav",        16.35, gain=0.30, pitch=1.12)
put(f"{A}/unlock.wav",        17.60, gain=0.30, pitch=0.92)
put(f"{A}/sparkle.wav",       19.60, gain=0.36, trim=(0.2, 2.4), pitch=1.15)  # 58-й beat
put(f"{A}/enter.wav",         21.95, gain=0.50, trim=(0.0, 3.6))           # Светик enters
put(f"{A}/sparkle.wav",       24.40, gain=0.30, trim=(0.2, 2.0), pitch=1.2)
put(f"{A}/unlock.wav",        26.50, gain=0.28, pitch=1.05)
put(f"{A}/unlock.wav",        28.50, gain=0.28, pitch=0.95)
put(f"{A}/swoosh.wav",        31.95, gain=0.36)                            # scene 5 in
put(f"{A}/unlock.wav",        33.00, gain=0.34, pitch=0.85)                # counter on
put(f"{A}/unlock.wav",        36.50, gain=0.30, pitch=1.1)
put(f"{A}/sparkle.wav",       39.40, gain=0.36, trim=(0.2, 2.2), pitch=1.1)
put(f"{A}/whoosh_gust.wav",   41.30, gain=0.42, trim=(0.0, 3.0))           # scene 6 in
put(f"{A}/ignite.wav",        42.60, gain=0.30, trim=(0.0, 1.4))           # rare flare
put(f"{A}/ignite.wav",        44.20, gain=0.34, trim=(0.0, 1.4), pitch=0.9)
put(f"{A}/ignite.wav",        45.80, gain=0.44, trim=(0.0, 1.6), pitch=0.8)  # epic
put(f"{A}/sparkle.wav",       47.20, gain=0.44, trim=(0.2, 2.4), pitch=0.85)  # LEGENDARY foil
put(f"{A}/storm.wav",         47.60, gain=0.30, trim=(2.0, 6.2), fade_in=1.8)  # riser tail
put(f"{A}/whoosh_gust.wav",   49.70, gain=0.30, trim=(2.0, 4.4))           # into impact
put(f"{A}/arcane.wav",        50.02, gain=0.30, trim=(0.0, 3.2))           # magic hit
put(f"{A}/achievement.wav",   57.45, gain=0.62, trim=(0.0, 2.4))           # logo fanfare
put(f"{A}/bubbles.wav",       58.30, gain=0.25, trim=(0.0, 1.5))           # cozy tail

# --- soundtrack under everything ---
d, sr = read_wav("/home/user/alchemists-loop/teaser/audio/music.wav")
d = resample(d, sr)
n = min(len(d), N)
mix[:n] += d[:n, None] if d.ndim == 1 else d[:n]

# master: soft clip, normalize, fades
mix = np.tanh(mix * 1.12) / 1.12
fi = int(0.10 * SR)
mix[:fi] *= np.linspace(0, 1, fi)[:, None]
fo = int(1.0 * SR)
mix[-fo:] *= (np.linspace(1, 0, fo) ** 1.4)[:, None]
peak = np.abs(mix).max()
mix = mix / peak * (10 ** (-1.0 / 20))

pcm = (mix * 32767).astype(np.int16)
with wave.open(OUT, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("mix.wav written  peak", float(peak))
