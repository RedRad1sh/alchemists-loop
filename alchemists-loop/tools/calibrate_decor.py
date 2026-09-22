#!/usr/bin/env python3
"""Эффекты из пикселей арта (v2): вместо векторных примитивов — оверлеи.

Генерирует в assets/decor/fx/:
  glow_{id}.png   — размытая форма огня (кладётся на спрайт с мерцанием);
  shadow_{id}.png — приплюснутый силуэт низа (тень-опора, всегда по форме).
Пишет game/data/decor_calib.gd: размещение оверлеев + bbox стекла окон
(для shaft). Перезапускать после ре-экспорта арта.
QA: qa_fx.png — окна со стеклом, свечения, тени, композит-превью.
"""
import glob
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECOR = os.path.join(ROOT, "assets", "decor")
FX = os.path.join(DECOR, "fx")
OUT = os.path.join(ROOT, "game", "data", "decor_calib.gd")

GLOW_IDS = ["fireplace"] + [f"fireplace_{i}" for i in range(1, 10)] \
    + ["lamp"] + [f"lamp_{i}" for i in range(1, 10)]
# ножные предметы (тень-опора); висячие/настенные/ковры — без тени
FEET_PREFIX = ("table", "chair", "bed", "plant")
FEET_IDS = set()
for _p in FEET_PREFIX:
    FEET_IDS.add(_p)
    FEET_IDS.update(f"{_p}_{i}" for i in range(10))
FEET_IDS.update(["lamp", "lamp_1", "lamp_2", "lamp_3", "lamp_6", "lamp_7",
                 "lamp_8", "lamp_9", "shelf_6", "shelf_7"]
                + ["fireplace"] + [f"fireplace_{i}" for i in range(10) if i != 6])
WINDOW_IDS = ["window"] + [f"window_{i}" for i in range(1, 10)]
# регионы огня вручную там, где автомат врёт: ("ellipse",cx,cy,rx,ry) / ("box",x0,y0,x1,y1)
OVERRIDE_REGIONS = {
    "lamp": ("ellipse", 0.30, 0.28, 0.26, 0.24),
    "lamp_3": ("ellipse", 0.53, 0.14, 0.09, 0.12),
    "fireplace_6": ("box", 0.08, 0.30, 0.92, 0.70),
    "lamp_8": ("ellipse", 0.50, 0.22, 0.17, 0.17),
}
FX_TINT = {"lamp_8": [0.72, 0.55, 1.0]}  # фиолетовый шар светит фиолетовым


def components(mask):
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for y0 in range(h):
        for x0 in range(w):
            if not mask[y0, x0] or seen[y0, x0]:
                continue
            q = deque([(y0, x0)])
            seen[y0, x0] = True
            n = 0
            while q:
                y, x = q.popleft()
                n += 1
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            out.append(n)
    return out


def emitter_mask(sid, arr):
    """Маска огня в полном разрешении."""
    h, w = arr.shape[0], arr.shape[1]
    if sid in OVERRIDE_REGIONS:
        reg = OVERRIDE_REGIONS[sid]
        m = Image.new("L", (w, h), 0)
        dd = ImageDraw.Draw(m)
        if reg[0] == "ellipse":
            _, cx, cy, rx, ry = reg
            dd.ellipse([w * (cx - rx), h * (cy - ry), w * (cx + rx), h * (cy + ry)], fill=255)
        else:
            _, x0, y0, x1, y1 = reg
            dd.rectangle([w * x0, h * y0, w * x1, h * y1], fill=255)
        return np.array(m) > 0
    rgb = arr[:, :, :3].astype(np.int32)
    a = arr[:, :, 3] > 8
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    warm = (r > 140) & ((r - b) > 50) & (g > b)
    mask = a & warm & (lum >= np.percentile(lum[a], 96))
    if sid.startswith("fireplace"):
        mask[: mask.shape[0] // 4, :] = False
    if mask.sum() < 20:
        mask = a & (lum >= np.percentile(lum[a], 97))
    # мелкие брызги — выкинуть (компоненты на малой маске)
    small = np.array(Image.fromarray(mask).resize((64, 64), Image.NEAREST))
    big = np.array(Image.fromarray(small).resize((w, h), Image.NEAREST))
    return mask & big


def glass_box(arr):
    """Bbox стекла окна (синее; fallback — яркое для закатного) во фракциях."""
    rgb = arr[:, :, :3].astype(np.int32)
    a = arr[:, :, 3] > 8
    r, b = rgb[:, :, 0], rgb[:, :, 2]
    gb = _bbox_of(a & (b > r + 15) & (b > 50))
    if gb is None:  # закат: стекло яркое, рама тёмная
        lum = 0.299 * r + 0.587 * rgb[:, :, 1] + 0.114 * b
        gb = _bbox_of(a & (lum > np.percentile(lum[a], 55)))
    return gb


def _bbox_of(mask):
    ys, xs = np.nonzero(mask)
    if not len(xs):
        return None
    h, w = mask.shape
    return [round(float(xs.min()) / w, 3), round(float(ys.min()) / h, 3),
            round(float(xs.max() + 1) / w, 3), round(float(ys.max() + 1) / h, 3)]


def save_cropped(img, path, pad=6):
    bbox = img.getbbox()
    if bbox is None:
        return None
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(img.width, bbox[2] + pad)
    y1 = min(img.height, bbox[3] + pad)
    img.crop((x0, y0, x1, y1)).save(path)
    return (x0, y0, x1, y1)


def main():
    os.makedirs(FX, exist_ok=True)
    calib = {}
    # --- glow-оверлеи ---
    for sid in GLOW_IDS:
        p = os.path.join(DECOR, sid + ".png")
        arr = np.array(Image.open(p).convert("RGBA"))
        h, w = arr.shape[0], arr.shape[1]
        m = emitter_mask(sid, arr)
        white = Image.new("RGBA", (w, h), (255, 255, 255, 0))
        white.putalpha(Image.fromarray((m * 255).astype(np.uint8)))
        white = white.filter(ImageFilter.GaussianBlur(12))
        box = save_cropped(white, os.path.join(FX, f"glow_{sid}.png"), pad=4)
        e = calib.setdefault(sid, {})
        e["glow_fx"] = {"tex": f"glow_{sid}",
                        "rect": [round(box[0] / w, 3), round(box[1] / h, 3),
                                 round(box[2] / w, 3), round(box[3] / h, 3)]}
        if sid in FX_TINT:
            e["tint"] = FX_TINT[sid]
    # --- shadow-оверлеи ---
    for f in sorted(glob.glob(os.path.join(DECOR, "*.png"))):
        sid = os.path.basename(f)[:-4]
        if sid not in FEET_IDS:
            continue
        im = Image.open(f).convert("RGBA")
        w, h = im.size
        alpha = np.array(im)[:, :, 3]
        bottom = Image.fromarray(alpha[int(h * 0.55):]).resize(
            (w, max(4, int(h * 0.10))), Image.BILINEAR)
        sh = Image.new("RGBA", (w, bottom.height + 16), (0, 0, 0, 0))
        dark = Image.new("RGBA", bottom.size, (0, 0, 0, 255))
        a2 = np.array(bottom).astype(np.float32) * 0.42
        dark.putalpha(Image.fromarray(a2.astype(np.uint8)))
        dark = dark.filter(ImageFilter.GaussianBlur(5))
        sh.alpha_composite(dark, (0, 0))
        box = save_cropped(sh, os.path.join(FX, f"shadow_{sid}.png"), pad=4)
        # размещение: центр масс тени — на 2px ниже базы (верх заходит за предмет)
        crop = sh.crop(box)
        ca = np.array(crop)[:, :, 3].astype(np.float32)
        ys, xs = np.nonzero(ca > 4)
        cyc = float((ys * ca[ys, xs]).sum() / ca[ys, xs].sum())
        top_in_sprite = (h + 2) - cyc  # верх оверлея в пикселях спрайта
        e = calib.setdefault(sid, {})
        e["shadow_fx"] = {"tex": f"shadow_{sid}",
                          "rect": [round(box[0] / w, 3),
                                   round(top_in_sprite / h, 3),
                                   round(box[2] / w, 3),
                                   round((top_in_sprite + (box[3] - box[1])) / h, 3)]}
    # --- стекло окон ---
    for sid in WINDOW_IDS:
        arr = np.array(Image.open(os.path.join(DECOR, sid + ".png")).convert("RGBA"))
        gb = glass_box(arr)
        if gb:
            calib.setdefault(sid, {})["glass"] = gb
        else:
            print("NO GLASS:", sid)
    # --- .gd ---
    lines = ["class_name DecorCalib", "extends RefCounted",
             "# Эффекты из пикселей арта (tools/calibrate_decor.py). НЕ ПРАВИТЬ ВРУЧНУЮ.",
             "# glow_fx/shadow_fx: {tex, rect во фракциях спрайта}; glass: bbox стекла.",
             "const CALIB := {"]
    for sid in sorted(calib):
        parts = []
        for k in ("glow_fx", "shadow_fx"):
            if k in calib[sid]:
                v = calib[sid][k]
                r = ", ".join(str(x) for x in v["rect"])
                parts.append(f'"{k}": {{"tex": "{v["tex"]}", "rect": [{r}]}}')
        if "glass" in calib[sid]:
            parts.append('"glass": [%s]' % ", ".join(str(x) for x in calib[sid]["glass"]))
        if "tint" in calib[sid]:
            parts.append('"tint": [%s]' % ", ".join(str(x) for x in calib[sid]["tint"]))
        lines.append(f'\t"{sid}": {{{", ".join(parts)}}},')
    lines += ["}", ""]
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print("wrote", OUT, len(calib), "entries")
    # --- QA ---
    cell = 150
    # ряд 1: окна + стекло
    sheet = Image.new("RGB", (cell * 10, cell * 4 + 30), (24, 28, 34))
    d = ImageDraw.Draw(sheet)
    for i, sid in enumerate(WINDOW_IDS):
        im = Image.open(os.path.join(DECOR, sid + ".png")).convert("RGBA")
        dd = ImageDraw.Draw(im)
        gb = calib.get(sid, {}).get("glass")
        if gb:
            dd.rectangle([im.width * gb[0], im.height * gb[1],
                          im.width * gb[2], im.height * gb[3]], outline=(40, 255, 80), width=3)
        im.thumbnail((cell - 8, cell - 24))
        bg = Image.new("RGBA", (cell, cell), (40, 44, 52, 255))
        bg.alpha_composite(im, ((cell - im.width) // 2, (cell - im.height) // 2 + 6))
        sheet.paste(bg.convert("RGB"), (i * cell, 0))
        d.text((i * cell + 6, 2), sid, fill=(255, 220, 120))
    # ряд 2-3: композит свечений (спрайт + оверлей)
    for k, sid in enumerate(GLOW_IDS):
        base = Image.open(os.path.join(DECOR, sid + ".png")).convert("RGBA")
        g = calib[sid]["glow_fx"]
        ov = Image.open(os.path.join(FX, g["tex"] + ".png")).convert("RGBA")
        w, h = base.size
        full = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        full.alpha_composite(ov.resize((int(w * (g["rect"][2] - g["rect"][0])),
                                        int(h * (g["rect"][3] - g["rect"][1])))),
                             (int(w * g["rect"][0]), int(h * g["rect"][1])))
        tint = calib[sid].get("tint", [1.0, 0.62, 0.25])
        warm = Image.new("RGBA", (w, h), (int(tint[0] * 255), int(tint[1] * 255),
                                            int(tint[2] * 255), 255))
        show = Image.alpha_composite(base, Image.new("RGBA", (w, h), (0, 0, 0, 0)))
        glow_layer = Image.composite(warm, Image.new("RGBA", (w, h), (0, 0, 0, 0)), full.split()[3])
        glow_layer.putalpha(glow_layer.split()[3].point(lambda v: int(v * 0.55)))
        show = Image.alpha_composite(show, glow_layer)
        show.thumbnail((cell - 8, cell - 24))
        bg = Image.new("RGBA", (cell, cell), (20, 22, 28, 255))
        bg.alpha_composite(show, ((cell - show.width) // 2, (cell - show.height) // 2 + 6))
        sheet.paste(bg.convert("RGB"), ((k % 10) * cell, cell + (30 if k >= 10 else 0) + (cell if k >= 10 else 0)))
        d.text(((k % 10) * cell + 6, cell + (30 if k >= 10 else 0) + (cell if k >= 10 else 0) + 2),
               sid, fill=(255, 220, 120))
    # ряд 4: тени (чёрное на сером)
    keys = sorted([s for s in calib if "shadow_fx" in calib[s]])
    demo = ["bed", "chair", "table", "lamp", "lamp_2", "plant", "fireplace",
            "fireplace_4", "shelf_6", "shelf_7"]
    for i, sid in enumerate(demo):
        ov = Image.open(os.path.join(FX, f"shadow_{sid}.png")).convert("RGBA")
        ov.thumbnail((cell - 8, cell - 30))
        bg = Image.new("RGBA", (cell, cell), (140, 140, 140, 255))
        bg.alpha_composite(ov, ((cell - ov.width) // 2, (cell - ov.height) // 2 + 6))
        sheet.paste(bg.convert("RGB"), (i * cell, cell * 3 + 30))
        d.text((i * cell + 6, cell * 3 + 32), sid, fill=(20, 20, 20))
    sheet.save("/home/user/qa_fx.png")
    print("wrote /home/user/qa_fx.png")


if __name__ == "__main__":
    main()
