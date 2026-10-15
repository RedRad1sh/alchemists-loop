"""Процедурная музыка+SFX для тизера (numpy → WAV, 44.1 kHz stereo)."""
from __future__ import annotations

import math

import numpy as np

SR = 44100


def _t(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def _env(n: int, attack: float, release: float) -> np.ndarray:
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def add(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0):
    i = int(at * SR)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i:i + n] += sig[:n] * gain


def pad_chord(freqs, dur: float) -> np.ndarray:
    t = _t(dur)
    sig = np.zeros_like(t)
    for k, f in enumerate(freqs):
        det = 1 + 0.0015 * (k - 1)
        sig += 0.5 * np.sin(2 * np.pi * f * det * t)
        sig += 0.18 * np.sin(2 * np.pi * f * 2 * det * t)
    sig *= _env(len(t), 0.6, 0.9)
    trem = 1 + 0.12 * np.sin(2 * np.pi * 0.7 * t)
    return sig * trem / len(freqs)


def pluck(f: float, dur: float = 0.5) -> np.ndarray:
    t = _t(dur)
    sig = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 9)
    return sig * np.exp(-t * 7) * _env(len(t), 0.005, 0.1)


def blip(f0: float, f1: float, dur: float = 0.18) -> np.ndarray:
    t = _t(dur)
    f = f0 + (f1 - f0) * (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 14) * _env(len(t), 0.004, 0.05)


def bell(f: float, dur: float = 1.4) -> np.ndarray:
    t = _t(dur)
    sig = np.zeros_like(t)
    for mult, amp in [(1, 1), (2.0, 0.5), (2.98, 0.3), (4.2, 0.16)]:
        sig += amp * np.sin(2 * np.pi * f * mult * t) * np.exp(-t * (2.2 + mult))
    return sig * _env(len(t), 0.004, 0.2)


def whoosh(dur: float = 0.6, f_lo: float = 300, f_hi: float = 2600) -> np.ndarray:
    n = int(dur * SR)
    noise = np.random.default_rng(7).standard_normal(n)
    # простой sweep-фильтр: скользящее среднее с переменной длиной
    out = np.zeros(n)
    win = np.linspace(SR / f_lo, SR / f_hi, n).astype(int).clip(2, 4096)
    acc = 0.0
    buf = np.zeros(4097)
    ptr = 0
    for i in range(n):
        buf[ptr] = noise[i]
        w = win[i]
        acc = buf[(ptr - np.arange(w)) % 4097].mean()
        out[i] = acc * w**0.5
        ptr = (ptr + 1) % 4097
    env = np.sin(np.pi * np.arange(n) / n) ** 1.5
    return out * env


def crackle(dur: float, rate: float = 9) -> np.ndarray:
    n = int(dur * SR)
    rng = np.random.default_rng(11)
    out = np.zeros(n)
    t = 0.0
    while t < dur:
        i = int(t * SR)
        ln = int(rng.integers(30, 260))
        if i + ln < n:
            out[i:i + ln] += rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln / 4)) * 0.5
        t += rng.random() / rate
    return out


def build(total: float) -> np.ndarray:
    rng = np.random.default_rng(4)
    buf = np.zeros(int(total * SR))
    # пад: Am F C G Am
    chords = [
        (0.0, 3.5, [110.0, 130.81, 164.81]),
        (3.5, 3.5, [87.31, 110.0, 130.81]),
        (7.0, 3.5, [130.81, 164.81, 196.0]),
        (10.5, 3.5, [98.0, 123.47, 146.83]),
        (14.0, 3.5, [110.0, 130.81, 164.81]),
        (17.5, 3.5, [87.31, 110.0, 130.81]),
        (21.0, 3.5, [130.81, 164.81, 196.0]),
        (24.5, 2.5, [98.0, 123.47, 146.83]),
        (27.0, total - 27.0, [110.0, 164.81, 220.0, 246.94]),
    ]
    for at, dur, fr in chords:
        add(buf, pad_chord(fr, dur), at, 0.30)
    # бульки котла (сцены 1-2)
    for at in [0.5, 1.1, 1.7, 2.3, 2.8, 3.6, 4.4, 5.1, 5.8]:
        add(buf, blip(340 + rng.random() * 260, 140, 0.22), at, 0.16)
    # тап по ячейке
    add(buf, blip(1200, 700, 0.09), 3.4, 0.30)
    add(buf, whoosh(0.5, 400, 2400), 4.55, 0.22)
    # открытие: колокол
    add(buf, bell(659.25), 6.55, 0.34)
    add(buf, bell(987.77, 1.1), 6.72, 0.22)
    add(buf, whoosh(0.45, 500, 3000), 6.45, 0.18)
    # арпеджио стены глифов
    arp = [440, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.7]
    for i, f in enumerate(arp):
        add(buf, pluck(f, 0.55), 10.7 + i * 0.34, 0.20)
    # светик: милые блипы
    add(buf, blip(523, 784, 0.14), 15.2, 0.24)
    add(buf, blip(659, 988, 0.16), 16.6, 0.24)
    add(buf, blip(784, 1175, 0.12), 16.78, 0.18)
    # дом: потрескивание камина
    add(buf, crackle(4.0, 10), 18.6, 0.16)
    add(buf, bell(392, 1.0), 18.7, 0.12)
    # qte-пульс и тики эфира
    for i in range(4):
        add(buf, blip(880, 440, 0.1), 22.6 + i * 0.5, 0.16)
    for i in range(6):
        add(buf, pluck(1318.5, 0.25), 24.6 + i * 0.32, 0.10)
    add(buf, whoosh(0.5, 350, 2200), 24.45, 0.20)
    # финал
    add(buf, bell(523.25, 1.8), 26.6, 0.30)
    add(buf, bell(659.25, 1.6), 26.75, 0.22)
    add(buf, bell(783.99, 1.5), 26.9, 0.18)
    for i, f in enumerate([880, 1046.5, 1318.5]):
        add(buf, pluck(f, 0.7), 27.4 + i * 0.22, 0.16)
    # мастеринг
    n = len(buf)
    fade_in = int(0.25 * SR)
    buf[:fade_in] *= np.linspace(0, 1, fade_in)
    fade_out = int(0.7 * SR)
    buf[-fade_out:] *= np.linspace(1, 0, fade_out)
    peak = np.max(np.abs(buf)) or 1.0
    buf = buf / peak * 0.86
    buf = np.tanh(buf * 1.4) / math.tanh(1.4)
    stereo = np.stack([buf, buf], axis=1)
    det = np.roll(buf, int(0.008 * SR))
    stereo[:, 1] = 0.75 * buf + 0.25 * det
    return (stereo * 32767).astype("<i2")


def write_wav(path: str, total: float):
    import wave
    data = build(total)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


if __name__ == "__main__":
    import sys
    write_wav(sys.argv[1] if len(sys.argv) > 1 else "/tmp/teaser_audio.wav", 30.5)
    print("wav ok")
