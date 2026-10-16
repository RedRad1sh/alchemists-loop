#!/usr/bin/env python3
"""Per-cut 60s mixes: «Enchanced Alchemy» edit (same as v1) + cut-aware SFX.

SFX policy v2 ("light", по фидбеку: «слишком длинные звуки, музыку не слышно»):
  - arcane.wav и storm.wav НЕ используем вовсе (перегружают);
  - ни один эффект не длиннее ~1.2с (achievement 1.6с — единственный акцент финала);
  - тримы берут громкую часть файла (по RMS-профилю), а не тихий хвост;
  - глобальный SFX-мастер 0.85 — музыка всегда сверху.

Key tuning into the track key (D-major-pentatonic):
  enter.wav   C# -> D    (+70 cents, pitch 1.0495)
  bubbles.wav F  -> F#   (+100 cents, pitch 1.0595)
"""
import numpy as np
import wave
import os

SR = 44100
DUR = 60.0
N = int(SR * DUR)
A = "/home/user/alchemists-loop/teaser/assets/sfx"

# scene starts per cut (mirror of cuts_v2.js)
CUT_STARTS = {
    "v1": {"hookWorld": 0.0, "base": 5.2, "world": 11.4, "show": 19.4, "work": 26.6,
            "spring": 32.8, "sigil": 37.8, "house": 44.2, "finale": 50.0},
    "v2": {"hookSvetik": 0.0, "base": 4.5, "show": 10.7, "world": 17.9, "spring": 25.9,
            "house": 30.9, "work": 37.6, "sigil": 43.8, "finale": 50.0},
    "v3": {"mystery": 0.0, "feed": 5.0, "world": 11.5, "sigil": 19.5, "show": 25.5,
            "spring": 32.5, "race": 37.5, "offline": 43.2, "finale": 50.0},
    "v4": {"hookCozy": 0.0, "base": 5.0, "house": 11.0, "spring": 17.7, "offline": 22.7,
            "work": 29.7, "sigil": 35.9, "show": 41.9, "finale": 50.0},
    "v5": {"hookRace": 0.0, "feed": 4.5, "base": 11.0, "world": 16.6, "race": 24.6,
            "work": 30.3, "sigil": 36.5, "show": 42.5, "spring": 47.6, "finale": 50.0},
    "v6": {"hookSvetikBridge": 0.0, "world": 6.5, "base": 19.5, "show": 24.5, "offline": 30.5,
            "sigil": 37.0, "house": 43.5, "finale": 50.0},
}
# musical boundaries (mask crossfades of the music edit at 41.4 — cut boundaries near it vary)
D_DROP = 177.82
B_SRC0 = D_DROP - 8.6
XF = 1.6
CUT = 41.4
SFX_MASTER = 0.85


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        nch = w.getnchannels()
        raw = w.readframes(w.getnframes())
    d = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32767.0
    if nch == 2:
        d = d.reshape(-1, 2)
    return d, sr


def read_any(path):
    if path.endswith(".wav"):
        return read_wav(path)
    import subprocess, imageio_ffmpeg, tempfile
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-i", path,
                    "-ar", str(SR), "-ac", "2", tmp], capture_output=True)
    d, _ = read_wav(tmp)
    os.unlink(tmp)
    return d, SR


def resample(d, sr, target=SR):
    if sr == target:
        return d
    x_old = np.arange(len(d)) / sr
    x_new = np.arange(int(len(d) * target / sr)) / target
    if d.ndim == 2:
        return np.stack([np.interp(x_new, x_old, d[:, c]) for c in range(d.shape[1])], axis=1)
    return np.interp(x_new, x_old, d)


src, _ = read_wav("/home/user/alchemists-loop/teaser/audio/source_full.wav")
src = resample(src, SR)
if src.ndim == 1:
    src = np.stack([src, src], axis=1)

sfx = np.zeros((N, 2))


def put(path, t0, gain_=0.6, trim=(0.0, None), fade_in=0.005, fade_out=0.03,
        pan=0.0, pitch=1.0):
    d, srr = read_any(path)
    if pitch != 1.0:
        idx = np.arange(0, len(d), pitch)
        d = np.stack([np.interp(idx, np.arange(len(d)), d[:, c]) for c in range(2)], axis=1)
    a, b = trim
    d = d[int(a * SR): int(b * SR) if b else None]
    n = min(len(d), int((DUR - t0) * SR))
    if n <= 0 or t0 >= DUR - 0.05:
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


# short loud windows (from RMS profiles):
SPK = (2.35, 3.45)   # sparkle shimmer peak
ENT = (2.20, 3.40)   # enter peak
WMY = (2.40, 3.60)   # whoosh_mystery peak
GUS = (5.00, 6.20)   # whoosh_gust peak (only for the 49.7 pre-drop breath)
SWO = (1.10, 2.10)   # swoosh peak
SUC = (0.00, 1.10)   # success attack
ACV = (0.00, 1.60)   # achievement: both fanfare hits
BUB = (0.00, 1.20)   # bubbles attack
IGN = (1.90, 3.10)   # ignite flare peak

S = lambda *a, **k: put(f"{A}/sparkle.wav", *a, **k)
W_ = lambda *a, **k: put(f"{A}/whoosh_mystery.wav", *a, **k)
G = lambda *a, **k: put(f"{A}/whoosh_gust.wav", *a, **k)
SW = lambda *a, **k: put(f"{A}/swoosh.wav", *a, **k)
BU = lambda *a, **k: put(f"{A}/bubbles.wav", *a, **k)
SU = lambda *a, **k: put(f"{A}/success.wav", *a, **k)
AC = lambda *a, **k: put(f"{A}/achievement.wav", *a, **k)
UN = lambda *a, **k: put(f"{A}/unlock.wav", *a, **k)
EN = lambda *a, **k: put(f"{A}/enter.wav", *a, **k)
IG = lambda *a, **k: put(f"{A}/ignite.wav", *a, **k)
ENTER_TUNED = dict(pitch=1.0495)   # C# -> D
BUBBLES_TUNED = dict(pitch=1.0595)  # F -> F#


def scene_events(st):
    """SFX timeline from scene start table (light: only short accents)."""
    ev = []

    def add(fn, t, **k):
        ev.append((fn, t, k))

    for key, s in st.items():
        if key == "finale":
            continue
        if key in ("hookWorld", "mystery", "hookRace", "hookSvetik", "hookCozy", "hookSvetikBridge"):
            if key == "hookWorld":
                add(UN, s + 2.2, gain_=0.26)
                add(UN, s + 3.0, gain_=0.26, pitch=1.12)
                add(UN, s + 3.8, gain_=0.26, pitch=0.92)
                add(S, s + 4.35, gain_=0.28, trim=SPK)
            elif key == "mystery":
                add(S, s + 0.3, gain_=0.26, trim=SPK)
                add(W_, s + 2.3, gain_=0.26, trim=WMY)
                add(S, s + 3.5, gain_=0.24, trim=SPK, pitch=1.15)
            elif key == "hookRace":
                add(W_, s + 0.3, gain_=0.26, trim=WMY)
                add(UN, s + 1.7, gain_=0.26)
                add(S, s + 2.6, gain_=0.28, trim=SPK, pitch=1.2)
            elif key == "hookSvetik":
                add(EN, s + 0.15, gain_=0.36, trim=ENT, **ENTER_TUNED)
                add(S, s + 0.25, gain_=0.28, trim=SPK)
            elif key == "hookSvetikBridge":
                add(EN, s + 0.15, gain_=0.36, trim=ENT, **ENTER_TUNED)
                add(S, s + 0.25, gain_=0.28, trim=SPK)
                add(SW, s + 3.5, gain_=0.28, trim=SWO)
                add(SW, s + 4.3, gain_=0.30, trim=SWO, pitch=1.06)
            else:  # hookCozy
                add(S, s + 0.4, gain_=0.24, trim=SPK)
                add(BU, s + 0.5, gain_=0.28, trim=BUB, **BUBBLES_TUNED)
        elif key == "base":
            add(SW, s + 1.5, gain_=0.30, trim=SWO)
            add(SW, s + 1.9, gain_=0.30, trim=SWO, pitch=1.06)
            add(BU, s + 2.15, gain_=0.40, trim=BUB, **BUBBLES_TUNED)
            add(SU, s + 3.0, gain_=0.36, trim=SUC)
            add(UN, s + 3.9, gain_=0.24, pitch=0.85)
        elif key == "world":
            add(W_, s + 0.2, gain_=0.28, trim=WMY)
            add(SW, s + 2.0, gain_=0.30, trim=SWO)
            add(SW, s + 2.35, gain_=0.30, trim=SWO, pitch=1.06)
            add(BU, s + 2.6, gain_=0.38, trim=BUB, **BUBBLES_TUNED)
            add(IG, s + 3.5, gain_=0.24, trim=IGN)
            add(SU, s + 4.35, gain_=0.40, trim=SUC)
        elif key == "show":
            add(EN, s + 0.1, gain_=0.34, trim=ENT, **ENTER_TUNED)
            add(UN, s + 1.2, gain_=0.26, pitch=1.05)
            add(UN, s + 3.1, gain_=0.26, pitch=0.95)
            add(S, s + 5.0, gain_=0.26, trim=SPK, pitch=1.15)
        elif key == "work":
            add(UN, s + 0.4, gain_=0.24)
            add(UN, s + 0.68, gain_=0.24, pitch=1.12)
            add(UN, s + 0.96, gain_=0.24, pitch=0.92)
            add(S, s + 3.0, gain_=0.26, trim=SPK)
            add(S, s + 4.3, gain_=0.26, trim=SPK, pitch=1.1)
            add(UN, s + 4.7, gain_=0.24, pitch=0.85)
        elif key == "spring":
            add(S, s + 0.5, gain_=0.26, trim=SPK, pitch=1.2)
            add(BU, s + 1.2, gain_=0.22, trim=BUB, **BUBBLES_TUNED)
            add(S, s + 3.1, gain_=0.26, trim=SPK, pitch=0.9)
        elif key == "sigil":
            add(W_, s + 1.7, gain_=0.28, trim=WMY)
            add(SU, s + 2.55, gain_=0.38, trim=SUC)
            add(S, s + 2.6, gain_=0.30, trim=SPK, pitch=0.9)
        elif key == "house":
            add(EN, s + 0.3, gain_=0.34, trim=ENT, **ENTER_TUNED)
            add(UN, s + 1.7, gain_=0.20, pitch=0.9)
            add(UN, s + 2.0, gain_=0.20)
            add(UN, s + 2.3, gain_=0.20, pitch=1.1)
            add(IG, s + 4.2, gain_=0.26, trim=IGN)
        elif key == "race":
            add(UN, s + 1.3, gain_=0.24)
            add(UN, s + 1.7, gain_=0.24, pitch=1.12)
            add(UN, s + 2.1, gain_=0.24, pitch=0.92)
            add(SW, s + 3.6, gain_=0.28, trim=SWO)
            add(S, s + 4.3, gain_=0.26, trim=SPK)
        elif key == "feed":
            add(UN, s + 1.3, gain_=0.24)
            add(UN, s + 2.5, gain_=0.24, pitch=1.12)
            add(UN, s + 3.7, gain_=0.24, pitch=0.92)
            add(S, s + 4.9, gain_=0.26, trim=SPK, pitch=1.15)
        elif key == "offline":
            add(EN, s + 0.1, gain_=0.36, trim=ENT, **ENTER_TUNED)
            add(UN, s + 5.5, gain_=0.26, pitch=1.1)
    return ev


def build(cut_id):
    st = CUT_STARTS[cut_id]
    # ---- music edit (same as v1) ----
    music = np.zeros((N, 2))
    xA = int((CUT + XF / 2) * SR)
    music[:xA] += src[:xA]
    tB0 = CUT - XF / 2
    sB0 = B_SRC0 - XF / 2
    nB = min(N - int(tB0 * SR), len(src) - int(sB0 * SR))
    xf_n = int(XF * SR)
    wA = np.cos(np.linspace(0, np.pi / 2, xf_n)) ** 2
    wB = np.sin(np.linspace(0, np.pi / 2, xf_n)) ** 2
    segB = src[int(sB0 * SR):int(sB0 * SR) + nB].copy()
    iB = int(tB0 * SR)
    music[iB:iB + xf_n] *= wA[:, None]
    music[iB:iB + xf_n] += segB[:xf_n] * wB[:, None]
    music[iB + xf_n:iB + nB] += segB[xf_n:nB]

    t = np.arange(N) / SR
    gain = np.ones(N)
    fi = int(1.3 * SR)
    gain[:fi] *= np.sin(np.linspace(0, np.pi / 2, fi)) ** 2
    d1 = 0.85 * np.exp(-((t - 34.0) / 2.2) ** 2)
    gain *= (1 - d1)
    tt = np.clip(t, 50.0, 66.0)
    d2 = 0.55 * (1 / (1 + np.exp(-(tt - 57.45) * 22))) * (1 / (1 + np.exp((tt - 58.45) * 22)))
    gain *= (1 - d2)
    fo0, fo1 = 58.35, 59.95
    fo = np.ones(N)
    m = (t >= fo0) & (t <= fo1)
    fo[m] = np.cos(np.linspace(0, np.pi / 2, m.sum())) ** 2
    fo[t > fo1] = 0.0
    gain *= fo
    music *= gain[:, None]

    # ---- finale + per-cut events (light) ----
    AC(57.45, gain_=0.50, trim=ACV)
    BU(58.30, gain_=0.18, trim=BUB, **BUBBLES_TUNED)
    for fn, tt0, k in scene_events(st):
        fn(tt0, **k)
    # cut-transition ticks: short swoosh peak instead of a 1.6s gust tail
    bounds = sorted({s for k, s in st.items() if s not in (0.0, 50.0)})
    for b in bounds:
        if abs(b - 41.4) < 2.0:
            continue
        SW(b - 0.05, gain_=0.13, trim=SWO)

    # ---- master ----
    sfx[:] *= SFX_MASTER
    mix = music + sfx
    mix = np.tanh(mix * 1.10) / 1.10
    fi2 = int(0.10 * SR)
    mix[:fi2] *= np.linspace(0, 1, fi2)[:, None]
    peak = np.abs(mix).max()
    mix = mix / peak * (10 ** (-1.0 / 20))
    pcm = (mix * 32767).astype(np.int16)
    out = f"/home/user/alchemists-loop/teaser/audio/mix_{cut_id}.wav"
    with wave.open(out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(out, "peak", float(peak))


for v in ["v1", "v2", "v3", "v4", "v5", "v6"]:
    build(v)
