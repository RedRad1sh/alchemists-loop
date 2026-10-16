#!/usr/bin/env python3
"""Alchemist's Loop teaser — 60s score, fully synthesized (no external music).

Structure (BPM 100, beat 0.6s, bar 2.4s):
  0.0- 7.2  bars 0-2   dark mystery: sub drone D, sparse tick, spark shimmer
  7.2-14.4  bars 2-5   heartbeat kick enters, pluck arp whisper
 14.4-21.6  bars 5-8   floor + pads fade in (Dm), arp brighter
 21.6-32.4  bars 8-13  warm groove: four-on-floor, Dm-Bb-F-C
 32.4-41.4  bars 13-17 offline section: hats out, bell melody
 41.4-47.4  bars 17-20 build: arp 16ths, energy up
 47.4-50.0             riser (noise + rising sine), drums mute
 50.0-57.6  bars 20-24 finale: half-time grand, big pad, shimmer
 57.6-60.0             final hit + tail
"""
import numpy as np
import wave

SR = 44100
DUR = 60.0
N = int(SR * DUR)
BPM = 100.0
BEAT = 60.0 / BPM
BAR = BEAT * 4

mixL = np.zeros(N)
mixR = np.zeros(N)


def seg(a, b=None):
    if b is None:
        b = DUR
    i0, i1 = max(0, int(a * SR)), min(N, int(b * SR))
    n = i1 - i0
    tt = np.arange(n) / SR
    return i0, n, tt


def add(sigL, sigR, i0):
    n = len(sigL)
    if i0 + n > N:
        n = N - i0
    if n <= 0:
        return
    mixL[i0:i0 + n] += sigL[:n]
    mixR[i0:i0 + n] += sigR[:n]


def env_ar(n, a, r, curve=3.0):
    e = np.ones(n)
    na, nr = int(a * SR), int(r * SR)
    na = min(na, n)
    nr = min(nr, n)
    if na > 0:
        e[:na] = np.linspace(0, 1, na)
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def place_note(freq, start, dur, amp, wave_fn, pan=0.0, attack=0.01, release=None):
    i0, n, tt = seg(start, start + dur)
    if n <= 0:
        return
    sig = wave_fn(freq, tt, dur) * env_ar(n, attack, release if release is not None else dur * 0.6)
    gl = amp * (1.0 - max(0.0, pan)) ** 0.5
    gr = amp * (1.0 + min(0.0, pan)) ** 0.5
    add(sig * gl, sig * gr, i0)


# ---------- instruments ----------

def sub(freq, tt, dur):
    x = 2 * np.pi * freq * tt
    s = np.sin(x) + 0.22 * np.sin(2 * x) + 0.08 * np.sin(3 * x)
    return np.tanh(1.4 * s) * 0.8


def pad_wave(freq, tt, dur):
    x = 2 * np.pi * freq * tt
    det = 0.006
    s = (np.sin(x * (1 + det)) + np.sin(x * (1 - det))
         + 0.5 * np.sin(x * 2.001) + 0.5 * np.sin(x * 1.997)
         + 0.25 * np.sin(x * 3.0))
    k = 64
    s = np.convolve(s, np.ones(k) / k, mode="same")
    return s * 0.5


def pluck(freq, tt, dur):
    x = 2 * np.pi * freq * tt
    s = np.sin(x) + 0.5 * np.sin(2 * x) + 0.22 * np.sin(3 * x) + 0.1 * np.sin(4 * x)
    e = np.exp(-tt * (5.2 + freq / 500.0))
    return s * e


def bell(freq, tt, dur):
    x = 2 * np.pi * freq * tt
    mod = 2.0 * np.sin(2 * np.pi * freq * 2.01 * tt)
    s = np.sin(x + mod * np.exp(-tt * 3)) + 0.4 * np.sin(2 * x)
    return s * np.exp(-tt * 1.9)


def kick(time):
    i0, n, tt = seg(time, time + 0.34)
    if n <= 0:
        return
    f = 120 * np.exp(-tt * 26) + 42
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-tt * 11)
    click = np.random.default_rng(7).standard_normal(n) * np.exp(-tt * 380) * 0.4
    s = np.tanh(1.8 * (s + click)) * 0.92
    add(s, s, i0)


def hat(time, amp=0.16, dur=0.05, tone=1.0):
    i0, n, tt = seg(time, time + dur)
    if n <= 0:
        return
    rng = np.random.default_rng(int(time * 1e4) % (2**32))
    x = rng.standard_normal(n)
    k = max(2, int(SR / (6800 * tone)))
    x = np.convolve(x, np.ones(k) / k, mode="same")
    s = (x - x.mean()) * np.exp(-tt * 90) * amp
    add(s * 0.6, s, i0)


def snare(time, amp=0.5):
    i0, n, tt = seg(time, time + 0.18)
    if n <= 0:
        return
    rng = np.random.default_rng(int(time * 1e4) % (2**32))
    x = rng.standard_normal(n)
    x = np.convolve(x, np.ones(3) / 3, mode="same")
    tone = np.sin(2 * np.pi * 190 * tt) * np.exp(-tt * 30)
    s = (x * 0.7 + tone) * np.exp(-tt * 22) * amp
    add(s, s * 0.96, i0)


def riser(start, dur, amp=0.5):
    i0, n, tt = seg(start, start + dur)
    if n <= 0:
        return
    rng = np.random.default_rng(99)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    step = 512
    for i in range(0, n, step):
        frac = i / n
        kk = max(2, int(SR / (900 + 4500 * frac)))
        y = np.convolve(noise[i:i + step], np.ones(kk) / kk, mode="same")
        out[i:i + len(y)] = y
    tone = np.sin(2 * np.pi * (180 + 620 * (tt / dur) ** 2) * tt) * 0.4
    e = (tt / dur) ** 2.2
    s = (out * 0.6 + tone) * e * amp
    fade = min(int(0.04 * SR), n)
    s[:fade] *= np.linspace(0, 1, fade)
    add(s * 0.7, s, i0)


def impact(time, amp=0.9):
    kick(time)
    i0, n, tt = seg(time, time + 1.6)
    if n <= 0:
        return
    f = 60 * np.exp(-tt * 7) + 34
    ph = 2 * np.pi * np.cumsum(f) / SR
    boom = np.sin(ph) * np.exp(-tt * 2.6)
    rng = np.random.default_rng(5)
    crash = rng.standard_normal(n)
    crash = np.convolve(crash, np.ones(6) / 6, mode="same") * np.exp(-tt * 3.2) * 0.5
    s = np.tanh(1.5 * (boom * 1.1 + crash)) * amp
    add(s, s * 0.94, i0)


def shimmer(time, dur=3.0, amp=0.16, root=587.33):
    for j, ratio in enumerate([1.0, 1.5, 2.0, 2.5, 3.0, 4.0]):
        st = time + j * 0.07
        pan = (-0.5 + 0.2 * j) if j % 2 == 0 else (0.5 - 0.2 * j)
        place_note(root * ratio, st, dur, amp * (0.9 ** j), bell,
                   pan=pan, attack=0.02, release=dur * 0.7)


def sweep_noise(start, dur, amp=0.3, hi=True):
    i0, n, tt = seg(start, start + dur)
    if n <= 0:
        return
    rng = np.random.default_rng(int(start * 100) % (2**32))
    x = rng.standard_normal(n)
    k = int(SR / (5200 if hi else 900))
    x = np.convolve(x, np.ones(k) / k, mode="same")
    x = x - x.mean()
    e = np.sin(np.pi * tt / dur) ** 2
    s = x * e * amp
    add(s * 0.4, s, i0)


NOTE = {"D2": 73.42, "F2": 87.31, "C2": 65.41, "Bb1": 58.27, "A1": 55.0,
        "D3": 146.83, "D4": 293.66, "F4": 349.23, "A4": 440.0, "C5": 523.25,
        "D5": 587.33, "Bb4": 466.16, "E4": 329.63, "G4": 392.0, "C4": 261.63,
        "Bb3": 233.08, "F3": 174.61, "A3": 220.0, "Bb2": 116.54, "C3": 130.81,
        "F5": 698.46, "A5": 880.0, "C6": 1046.5, "D6": 1174.66, "E5": 659.26, "G5": 783.99}

chords = {
    "Dm": ["D3", "F3", "A3", "D4"],
    "Bb": ["Bb2", "D3", "F3", "Bb3"],
    "F":  ["F3", "A3", "C4", "F3"],
    "C":  ["C3", "E4", "G4", "C4"],
}
prog = ["Dm", "Bb", "F", "C"]
ROOTS = {"Dm": "D2", "Bb": "Bb1", "F": "F2", "C": "C2"}


def chord_at(bar_idx):
    return chords[prog[bar_idx % 4]]


# ---------- arrangement ----------

# 0.0-8.0 dark mystery: drone D2
place_note(NOTE["D2"], 0.0, 8.0, 0.30, sub, attack=0.9, release=2.0)
place_note(NOTE["D3"], 0.6, 6.4, 0.10, pad_wave, attack=1.6, release=2.0)
shimmer(0.45, dur=2.6, amp=0.10, root=NOTE["D5"])
place_note(NOTE["A3"], 2.4, 1.8, 0.10, pluck, pan=-0.3)
place_note(NOTE["D4"], 4.2, 1.6, 0.12, pluck, pan=0.3)

# heartbeat kick bars 2-4 (7.2-16.8s)
for b in range(2, 5):
    bt = b * BAR
    kick(bt + 0 * BEAT)
    kick(bt + 2.5 * BEAT)
    if b % 2 == 1:
        kick(bt + 3.5 * BEAT)

# pluck arp whisper from 7.2
arp_notes = ["D4", "F4", "A4", "C5"]
for i in range(int(7.2 / (BEAT / 2)), int(21.6 / (BEAT / 2))):
    tt = i * BEAT / 2
    if tt >= 21.6:
        break
    gain = 0.09 if tt < 14.4 else 0.13
    place_note(NOTE[arp_notes[i % 4]], tt, 0.5, gain, pluck,
               pan=-0.25 + 0.5 * ((i % 4) / 3.0))

# keep the floor alive 14.4-21.6: sub roots + soft four-on-floor + quiet hats
for b in range(6, 9):
    bt = b * BAR
    place_note(NOTE[ROOTS[prog[b % 4]]], bt, BAR, 0.24, sub, attack=0.02, release=BEAT * 0.8)
    for q in range(4):
        kick(bt + q * BEAT)
        hat(bt + q * BEAT + BEAT / 2, amp=0.09, tone=1.2)

# pad chords 14.4 -> end
for bi in range(6, 20):
    bt = bi * BAR
    amp = 0.095 if bt < 21.6 - 0.1 else 0.12
    if 32.4 <= bt < 41.4:
        amp = 0.10
    if bt >= 50.0:
        amp = 0.15
    for nn in chord_at(bi):
        place_note(NOTE[nn], bt, BAR * 1.02, amp, pad_wave, attack=0.5, release=BAR * 0.5)

# groove 21.6-50
for b in range(9, 21):
    bt = b * BAR
    if bt >= 50.0:
        break
    offline = 32.4 <= bt < 41.4
    for q in range(4):
        kick(bt + q * BEAT)
        if not offline:
            hat(bt + q * BEAT + BEAT / 2, amp=0.14 if q % 2 else 0.18)
        else:
            hat(bt + q * BEAT + BEAT / 2, amp=0.07, tone=1.3)
        if b >= 13 and offline:
            snare(bt + 1.5 * BEAT, amp=0.28)
    if b % 4 == 3 and not offline:
        snare(bt + 3.5 * BEAT + BEAT / 2, amp=0.3)
    place_note(NOTE[ROOTS[prog[b % 4]]], bt, BAR, 0.26, sub, attack=0.02, release=BEAT * 0.8)

# offline bell melody 32.4-41.4
mel = [("D5", 32.4, 1.2), ("F5", 33.6, 1.2), ("A5", 34.8, 2.4), ("G5", 37.2, 1.2),
       ("F5", 38.4, 1.2), ("D5", 39.6, 1.8), ("E5", 40.8, 0.6)]
for nn, st, du in mel:
    place_note(NOTE[nn], st, du, 0.10, bell, pan=0.15)

# build 41.4-47.4: arp 16ths rising octave
for i in range(int(41.4 / (BEAT / 4)), int(47.4 / (BEAT / 4))):
    tt = i * BEAT / 4
    if tt >= 47.4:
        break
    nn = arp_notes[i % 4]
    oct_up = 2.0 if (i % 8) >= 4 else 1.0
    place_note(NOTE[nn] * oct_up, tt, 0.28, 0.085 + 0.05 * ((tt - 41.4) / 6.0), pluck,
               pan=(-0.3 if i % 2 else 0.3))
for b in range(18, 20):
    bt = b * BAR
    for q in range(4):
        kick(bt + q * BEAT)
        hat(bt + q * BEAT + BEAT / 2, amp=0.2)
    snare(bt + 3.5 * BEAT, amp=0.35)
riser(47.2, 2.8, amp=0.5)
sweep_noise(46.8, 3.2, amp=0.22, hi=False)

# finale 50.0: half-time grand
impact(50.0, amp=1.0)
shimmer(50.05, dur=3.6, amp=0.2, root=NOTE["D5"])
for b in range(21, 24):
    bt = b * BAR
    if bt >= 57.6:
        break
    kick(bt)
    kick(bt + 2.5 * BEAT)
    hat(bt + 1 * BEAT + BEAT / 2, amp=0.12)
    hat(bt + 3 * BEAT + BEAT / 2, amp=0.12)
    place_note(NOTE[ROOTS[prog[b % 4]]], bt, BAR, 0.3, sub, attack=0.02, release=BEAT)
    for nn in chord_at(b):
        place_note(NOTE[nn] * 2, bt, BAR * 1.05, 0.05, pad_wave, attack=0.4, release=BAR * 0.6)

# final hit 57.6
impact(57.6, amp=0.85)
place_note(NOTE["D2"], 57.6, 2.4, 0.3, sub, attack=0.01, release=1.4)
shimmer(57.65, dur=2.2, amp=0.14, root=NOTE["D6"])
for nn, st in [("D5", 57.7), ("A5", 57.85), ("D6", 58.0)]:
    place_note(NOTE[nn], st, 1.6, 0.09, bell, pan=0.0)

# sparkle ticks at scene boundaries
for st in [5.2, 13.5, 22.0, 32.4, 41.4]:
    shimmer(st + 0.02, dur=1.4, amp=0.07, root=NOTE["A5"])

# ---------- master ----------

mix = np.stack([mixL, mixR], axis=1)
mix = np.tanh(mix * 1.15) / 1.15
fade_in = int(0.10 * SR)
mix[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
fade_out = int(1.2 * SR)
mix[-fade_out:] *= (np.linspace(1, 0, fade_out) ** 1.5)[:, None]

peak = np.abs(mix).max()
mix = mix / peak * (10 ** (-1.2 / 20))

pcm = (mix * 32767).astype(np.int16)
with wave.open("/home/user/alchemists-loop/teaser/audio/music.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())

print("music.wav written:", DUR, "s  peak", float(peak))
