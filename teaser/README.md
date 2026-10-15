# Тизер «Петля Алхимика» (Shorts / TikTok)

- `alchemists-loop-teaser.mp4` — ролик 9:16, 1080×1920, 30 fps, 30.5 с, H.264+AAC (генерируемый артефакт, в git не коммитится).
- `poster.png` — обложка (кадр финальной карточки).
- `svg/` — SVG-исходники оверлеев: пар, кольцо тапа, вспышка-лучи, стрелки петли, пузырь реплики, счётчик, стена глифов, финальная карточка.
- Сценарий: `docs/teaser-scenario.md`.
- Генератор: `tools/teaser/render.py` (кадры игры из `alchemists-loop/previews` + спрайты Светика + SVG-оверлеи через `tools/teaser/minisvg.py` + процедурный звук `tools/teaser/audio.py` → ffmpeg).

Пересборка: `python3 tools/teaser/render.py [out.mp4]` (нужны Pillow, numpy, imageio-ffmpeg).
QC-кадры: `python3 tools/teaser/render.py --qc 1.5 7.0 12.0 …`
