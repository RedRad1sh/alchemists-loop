"""Рендер тизера «Петля Алхимика»: кадры сцен → ffmpeg (H.264 + AAC).

Запуск:  python3 render.py [out.mp4]
QC:      python3 render.py --qc 1.5 5.0 8.0 ...   → PNG в /tmp/qc_*.png
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scenes  # noqa: E402
import audio  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "teaser", "alchemists-loop-teaser.mp4")
WAV = "/tmp/teaser_audio.wav"


def get_ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def main():
    args = sys.argv[1:]
    if args and args[0] == "--qc":
        for ts in args[1:]:
            t = float(ts)
            img = scenes.frame_at(t)
            p = f"/tmp/qc_{t:.1f}.png"
            img.save(p)
            print("saved", p)
        return
    out = args[0] if args else OUT
    os.makedirs(os.path.dirname(out), exist_ok=True)
    audio.write_wav(WAV, scenes.DUR)
    ff = get_ffmpeg()
    cmd = [
        ff, "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{scenes.W}x{scenes.H}",
        "-r", str(scenes.FPS), "-i", "-",
        "-i", WAV,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-c:a", "aac", "-b:a", "160k",
        "-shortest", out,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    n_frames = int(scenes.DUR * scenes.FPS)
    t0 = time.time()
    try:
        for i in range(n_frames):
            t = i / scenes.FPS
            img = scenes.frame_at(t)
            proc.stdin.write(img.tobytes())
            if i % 60 == 0:
                print(f"frame {i}/{n_frames} ({time.time() - t0:.0f}s)", flush=True)
        # постер
        scenes.frame_at(28.2).save(os.path.join(ROOT, "teaser", "poster.png"))
        proc.stdin.close()
    except BrokenPipeError:
        print(proc.stderr.read().decode()[-2000:])
        raise
    err = proc.stderr.read().decode()
    rc = proc.wait()
    if rc != 0:
        print(err[-3000:])
        raise SystemExit(f"ffmpeg rc={rc}")
    print(f"done {out} in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
