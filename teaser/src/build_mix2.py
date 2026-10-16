#!/usr/bin/env python3
"""60s edit of "Enchanced Alchemy" (3:14 source) + in-game SFX -> audio/mix2.wav

Edit map (source times measured by onset/energy analysis):
  Part A: source [0 .. 42.2]        -> teaser [0 .. 42.2]   (fade-in 1.3s)
  Part B: source [169.22 .. 187.92] -> teaser [41.4 .. 60]  (drop 177.82 -> teaser 50.0)
  equal-power crossfade teaser [40.6 .. 42.2]
  music dip 57.25-58.65 (achievement fanfare cuts through)
  gentle dip 31.5-36.5 (cozy offline scene)
  fade-out 58.35 -> 60.0
"""
import numpy as np
import wave

SR = 44100
DUR = 60.0
N = int(SR * DUR)


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        nch = w.getnchannels()
        raw = w.readframes(w.getnframes())
    d = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32767.0
    if nch == 2:
        d = d.reshape(-1, 2)
    return d, sr


def resample(d, sr, target=SR):
    if sr == target:
        return d
    x_old = np.arange(len(d)) / sr
    x_new = np.arange(int(len(d) * target / sr)) / target
    if d.ndim == 2:
        return np.stack([np.interp(x_new, x_old, d[:, c]) for c in range(d.shape[1])], axis=1)
    return np.interp(x_new, x_old, d)


src, sr = read_wav("/home/user/alchemists-loop/teaser/audio/source_full.wav")
src = resample(src, sr)
if src.ndim == 1:
    src = np.stack([src, src], axis=1)

DROP_SRC = 177.82          # measured attack of the big section
A_SRC0 = 0.0               # part A start
B_SRC0 = DROP_SRC - 8.6    # part B start -> drop lands at teaser 50.0
XF = 1.6                   # crossfade length, centered on 41.4 cut
CUT = 41.4

music = np.zeros((N, 2))


def copy_part(teaser_t0, src_t0, length, gain_env=None):
    """Copy source [src_t0, src_t0+length) to teaser [teaser_t0, ...)."""
    i_out = int(teaser_t0 * SR)
    i_src = int(src_t0 * SR)
    n = min(int(length * SR), N - i_out, len(src) - i_src)
    if n <= 0:
        return
    piece = src[i_src:i_src + n]
    if gain_env is not None:
        g = gain_env(np.arange(n) / SR + teaser_t0)
        piece = piece * g[:, None]
    music[i_out:i_out + n] += piece


# Part A: 0 -> CUT + XF/2 (extra tail eaten by crossfade)
xA = int((CUT + XF / 2) * SR)
music[:xA] += src[:xA]

# Part B: starts at CUT - XF/2 in teaser, from B_SRC0 - XF/2 in source
tB0 = CUT - XF / 2
sB0 = B_SRC0 - XF / 2
nB = min(N - int(tB0 * SR), len(src) - int(sB0 * SR))

# equal-power crossfade over [CUT-XF/2, CUT+XF/2]
xf_n = int(XF * SR)
wA = np.cos(np.linspace(0, np.pi / 2, xf_n)) ** 2   # 1 -> 0
wB = np.sin(np.linspace(0, np.pi / 2, xf_n)) ** 2   # 0 -> 1
segB = src[int(sB0 * SR):int(sB0 * SR) + nB].copy()
iB = int(tB0 * SR)
music[iB:iB + xf_n] *= wA[:, None]
music[iB:iB + xf_n] += segB[:xf_n] * wB[:, None]
music[iB + xf_n:iB + nB] += segB[xf_n:nB]

# ---------- gain automation ----------
t = np.arange(N) / SR
gain = np.ones(N)

# smooth start (track already quiet, extra cosine fade-in 1.3s)
fi = int(1.3 * SR)
gain[:fi] *= np.sin(np.linspace(0, np.pi / 2, fi)) ** 2

# cozy dip during offline scene (32-36.5), depth 0.85, smooth
d1 = 0.85 * np.exp(-((t - 34.0) / 2.2) ** 2)
gain *= (1 - d1)

# fanfare dip 57.25-58.65 (achievement.wav at 57.45), depth to 0.45
tt = np.clip(t, 50.0, 66.0)
d2 = 0.55 * (1 / (1 + np.exp(-(tt - 57.45) * 22))) * (1 / (1 + np.exp((tt - 58.45) * 22)))
gain *= (1 - d2)

# smooth ending: cosine fade 58.35 -> 59.95
fo0, fo1 = 58.35, 59.95
fo = np.ones(N)
m = (t >= fo0) & (t <= fo1)
fo[m] = np.cos(np.linspace(0, np.pi / 2, m.sum())) ** 2
fo[t > fo1] = 0.0
gain *= fo

music *= gain[:, None]

# ---------- SFX on top ----------
A = "/home/user/alchemists-loop/teaser/assets/sfx"
sfx = np.zeros((N, 2))


def read_any(path):
    import subprocess, imageio_ffmpeg, tempfile, os
    if path.endswith(".wav"):
        return read_wav(path)
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-i", path,
                    "-ar", str(SR), "-ac", "2", tmp],
                   capture_output=True)
    d, _ = read_wav(tmp)
    os.unlink(tmp)
    return d, SR


def put(path, t0, gain_=0.6, trim=(0.0, None), fade_in=0.005, fade_out=0.03,
        pan=0.0, pitch=1.0):
    d, srr = read_any(path)
    if pitch != 1.0:
        idx = np.arange(0, len(d), pitch)
        d = np.stack([np.interp(idx, np.arange(len(d)), d[:, c]) for c in range(2)], axis=1)
    a, b = trim
    d = d[int(a * SR): int(b * SR) if b else None]
    n = min(len(d), int((DUR - t0) * SR))
    if n <= 0:
        return
    i0 = int(t0 * SR)
    seg = d[:n].copy()
    fi_, fo_ = int(fade_in * SR), int(fade_out * SR)
    if fi_ > 0 and fi_ < n:
        seg[:fi_] *= np.linspace(0, 1, fi_)[:, None]
    if fo_ > 0 and fo_ < n:
        seg[-fo_:] *= np.linspace(1, 0, fo_)[:, None]
    gl = gain_ * (1.0 - max(0.0, pan)) ** 0.5
    gr = gain_ * (1.0 + min(0.0, pan)) ** 0.5
    sfx[i0:i0 + n, 0] += seg[:, 0] * gl
    sfx[i0:i0 + n, 1] += seg[:, 1] * gr


put(f"{A}/sparkle.wav",        0.45, gain_=0.40, trim=(0.2, 2.6))
put(f"{A}/whoosh_mystery.wav", 3.05, gain_=0.34, trim=(0.6, 3.4))
put(f"{A}/whoosh_mystery.wav", 5.15, gain_=0.42, trim=(0.4, 3.2))
put(f"{A}/swoosh.wav",         8.05, gain_=0.42)
put(f"{A}/swoosh.wav",         8.55, gain_=0.42, pitch=1.06)
put(f"{A}/bubbles.wav",        8.70, gain_=0.55, trim=(0.0, 1.67))
put(f"{A}/success.wav",        9.75, gain_=0.50, trim=(0.0, 2.6))
put(f"{A}/whoosh_gust.wav",   13.40, gain_=0.40, trim=(0.0, 3.4))
put(f"{A}/unlock.wav",        15.10, gain_=0.30)
put(f"{A}/unlock.wav",        16.35, gain_=0.30, pitch=1.12)
put(f"{A}/unlock.wav",        17.60, gain_=0.30, pitch=0.92)
put(f"{A}/sparkle.wav",       19.60, gain_=0.36, trim=(0.2, 2.4), pitch=1.15)
put(f"{A}/enter.wav",         21.95, gain_=0.50, trim=(0.0, 3.6))
put(f"{A}/sparkle.wav",       24.40, gain_=0.30, trim=(0.2, 2.0), pitch=1.2)
put(f"{A}/unlock.wav",        26.50, gain_=0.28, pitch=1.05)
put(f"{A}/unlock.wav",        28.50, gain_=0.28, pitch=0.95)
put(f"{A}/swoosh.wav",        31.95, gain_=0.36)
put(f"{A}/unlock.wav",        33.00, gain_=0.34, pitch=0.85)
put(f"{A}/unlock.wav",        36.50, gain_=0.30, pitch=1.1)
put(f"{A}/sparkle.wav",       39.40, gain_=0.36, trim=(0.2, 2.2), pitch=1.1)
put(f"{A}/whoosh_gust.wav",   41.30, gain_=0.42, trim=(0.0, 3.0))
put(f"{A}/ignite.wav",        42.60, gain_=0.30, trim=(0.0, 1.4))
put(f"{A}/ignite.wav",        44.20, gain_=0.34, trim=(0.0, 1.4), pitch=0.9)
put(f"{A}/ignite.wav",        45.80, gain_=0.44, trim=(0.0, 1.6), pitch=0.8)
put(f"{A}/sparkle.wav",       47.20, gain_=0.44, trim=(0.2, 2.4), pitch=0.85)
put(f"{A}/storm.wav",         47.60, gain_=0.18, trim=(2.0, 6.2), fade_in=1.8)  # track has its own riser
put(f"{A}/whoosh_gust.wav",   49.70, gain_=0.30, trim=(2.0, 4.4))
put(f"{A}/arcane.wav",        50.02, gain_=0.30, trim=(0.0, 3.2))
put(f"{A}/achievement.wav",   57.45, gain_=0.72, trim=(0.0, 2.4))
put(f"{A}/bubbles.wav",       58.30, gain_=0.22, trim=(0.0, 1.5))

# ---------- master ----------
mix = music + sfx
mix = np.tanh(mix * 1.10) / 1.10
fi = int(0.10 * SR)
mix[:fi] *= np.linspace(0, 1, fi)[:, None]
peak = np.abs(mix).max()
mix = mix / peak * (10 ** (-1.0 / 20))

pcm = (mix * 32767).astype(np.int16)
with wave.open("/home/user/alchemists-loop/teaser/audio/mix2.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("mix2.wav written  peak", float(peak))
