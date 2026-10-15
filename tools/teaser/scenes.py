"""Сцены тизера «Петля Алхимика»: композитинг кадров игры + SVG-оверлеев.

Каждый sceneN(tl) рисует один кадр 1080x1920 (PIL RGB) для локального времени tl.
Таймлайн SCENES: (start, dur, fn, caption).
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import minisvg  # noqa: E402

minisvg.FONT_DIR = os.path.join(
    os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")),
    "alchemists-loop", "assets", "fonts")

W, H = 1080, 1920
FPS = 30

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GAME = os.path.join(ROOT, "alchemists-loop")
SVG = os.path.join(ROOT, "teaser", "svg")
PRE = os.path.join(GAME, "previews")
SPIRITS = os.path.join(GAME, "game", "spirits")
FX = os.path.join(GAME, "assets", "decor", "fx")

_cache: dict = {}


def load(path: str) -> Image.Image:
    if path not in _cache:
        _cache[path] = Image.open(path).convert("RGBA")
    return _cache[path]


def svg(name: str, params: dict | None = None, scale: float = 1.0) -> Image.Image:
    with open(os.path.join(SVG, name), encoding="utf-8") as f:
        return minisvg.render_svg(f.read(), params, scale)


def ease_out(t: float) -> float:
    return 1 - (1 - min(1, max(0, t))) ** 3


def ease_back(t: float) -> float:
    t = min(1, max(0, t))
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ** 3 + c1 * (t - 1) ** 2


def clamp01(t: float) -> float:
    return min(1.0, max(0.0, t))


def kb(frame: Image.Image, cx: float, cy: float, cw: float) -> Image.Image:
    """Кроп кадра (центр cx,cy, ширина cw в исходных пикселях) → 1080x1920."""
    src_w, src_h = frame.size
    ch = cw * src_h / src_w
    x0 = max(0, min(src_w - cw, cx - cw / 2))
    y0 = max(0, min(src_h - ch, cy - ch / 2))
    crop = frame.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch)))
    return crop.resize((W, H), Image.LANCZOS)


def src_to_target(cx, cy, cw, sx, sy, src_w=540, src_h=960):
    ch = cw * src_h / src_w
    x0 = max(0, min(src_w - cw, cx - cw / 2))
    y0 = max(0, min(src_h - ch, cy - ch / 2))
    return ((sx - x0) * W / cw, (sy - y0) * H / ch)


def paste(canvas: Image.Image, layer: Image.Image, center, scale=1.0, rot=0.0, opacity=1.0):
    if scale != 1.0:
        layer = layer.resize((max(1, int(layer.width * scale)), max(1, int(layer.height * scale))), Image.BILINEAR)
    if rot:
        layer = layer.rotate(rot, expand=True, resample=Image.BILINEAR)
    if opacity < 1.0:
        a = layer.getchannel("A").point(lambda v: int(v * opacity))
        layer = layer.copy()
        layer.putalpha(a)
    canvas.alpha_composite(layer, (int(center[0] - layer.width / 2), int(center[1] - layer.height / 2)))


_glow_sprites: dict = {}


def glow(canvas: Image.Image, center, radius: float, color=(255, 255, 255), opacity=0.5):
    key = color
    if key not in _glow_sprites:
        base = svg  # noqa: F841  (placeholder, sprite below)
        img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        for i in range(128, 0, -2):
            a = int(255 * (1 - i / 128) ** 2 * 0.9)
            d.ellipse((128 - i, 128 - i, 128 + i, 128 + i), fill=(color[0], color[1], color[2], a))
        _glow_sprites[key] = img
    spr = _glow_sprites[key].resize((int(radius * 2), int(radius * 2)), Image.BILINEAR)
    paste(canvas, spr, center, opacity=opacity)


def cut_center(layer: Image.Image, radius: float, soft: float = 40.0) -> Image.Image:
    """Обнуляет альфу в центре слоя (для вспышек-лучей вокруг попапа)."""
    w, h = layer.size
    yy, xx = np.mgrid[0:h, 0:w].astype("float32")
    r = np.sqrt((xx - w / 2) ** 2 + (yy - h / 2) ** 2)
    k = np.clip((r - radius) / soft, 0, 1)
    a = layer.getchannel("A").point(lambda v: v)
    import numpy as _n
    arr = _n.array(a, "float32") * k
    layer = layer.copy()
    layer.putalpha(Image.fromarray(arr.astype("uint8"), "L"))
    return layer


import numpy as np  # noqa: E402


def caption(canvas: Image.Image, text: str, tl: float, y: int = 1385, size: int = 80):
    pop = ease_back(clamp01(tl / 0.28))
    alpha = clamp01(tl / 0.18)
    fnt = minisvg.font("800", size)
    d = ImageDraw.Draw(canvas)
    words = text.split()
    lines, cur = [], ""
    for w_ in words:
        trial = (cur + " " + w_).strip()
        if d.textlength(trial, font=fnt) > 920 and cur:
            lines.append(cur)
            cur = w_
        else:
            cur = trial
    if cur:
        lines.append(cur)
    layer = Image.new("RGBA", (W, 340), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    yy = 20
    for ln in lines:
        ld.text((W / 2 + 4, yy + 7), ln, font=fnt, fill=(0, 0, 0, 130), anchor="ma", stroke_width=0)
        ld.text((W / 2, yy), ln, font=fnt, fill=(255, 255, 255, 255), anchor="ma",
                stroke_width=12, stroke_fill=(10, 8, 14, 255))
        yy += size + 26
    layer = layer.crop(layer.getbbox() or (0, 0, 1, 1))
    if pop != 1.0:
        layer = layer.resize((max(1, int(layer.width * pop)), max(1, int(layer.height * pop))), Image.BILINEAR)
    paste(canvas, layer, (W / 2, y), opacity=alpha)


def dim(canvas: Image.Image, factor: float):
    if factor >= 1:
        return
    black = Image.new("RGBA", canvas.size, (0, 0, 0, int(255 * (1 - factor))))
    canvas.alpha_composite(black)


# ---------------------------------------------------------------- сцены
def scene1(tl: float) -> Image.Image:
    f = load(os.path.join(PRE, "experiment_finaljuice.png"))
    u = ease_out(tl / 3.0)
    cw = 540 - 160 * u
    cx, cy = 270, 620 + 20 * u
    img = kb(f, cx, cy, cw)
    dim(img, 0.35 + 0.65 * clamp01(tl / 0.5))
    px, py = src_to_target(cx, cy, cw, 270, 560)
    bx, by = src_to_target(cx, cy, cw, 270, 630)
    ph = tl * 2.2
    st = svg("steam.svg", {"o": 0.34, "y": int(18 * math.sin(ph)), "y2": int(18 * math.sin(ph + 2))})
    st = st.filter(ImageFilter.GaussianBlur(4))
    paste(img, st, (px, py - 60), scale=W / cw * 0.55, opacity=0.85)
    glow(img, (bx, by), 210 * (1 + 0.06 * math.sin(tl * 5)), (90, 170, 235), 0.30)
    for i in range(5):
        seed = i * 1.7
        bt = (tl * 0.8 + seed) % 1.6
        bxx = bx + 90 * math.sin(seed * 9 + bt * 2)
        byy = by + 40 - bt * 90
        r = 6 + 5 * math.sin(seed * 5)
        d = ImageDraw.Draw(img)
        d.ellipse((bxx - r, byy - r, bxx + r, byy + r), fill=(190, 225, 255, int(140 * (1 - bt / 1.6))))
    caption(img, "А что, если алхимия — это петля?", tl - 0.45)
    return img


def scene2(tl: float) -> Image.Image:
    fp = load(os.path.join(PRE, "experiment_fullscreen.png"))
    fj = load(os.path.join(PRE, "experiment_finaljuice.png"))
    if tl < 1.2:
        img = kb(fp, 270, 480, 540)
    elif tl < 1.8:
        u = (tl - 1.2) / 0.6
        img = kb(fp, 270, 480, 540)
        img = Image.blend(img, kb(fj, 270, 560, 500), ease_out(u))
    else:
        img = kb(fj, 270, 590, 470)
    dim(img, 0.88)
    # кольцо тапа по ячейке «Вода» (src 101,503)
    if 0.35 < tl < 1.25:
        u = (tl - 0.35) / 0.9
        tx, ty = (202, 1006) if tl < 1.2 else src_to_target(270, 560, 500, 101, 503)
        ring = svg("tap_ring.svg", {"r": int(14 + 66 * ease_out(u)), "o": round(0.95 * (1 - u), 2)})
        paste(img, ring, (tx, ty), scale=1.6)
    if tl > 1.8:
        bt = tl - 1.8
        px, py = src_to_target(270, 590, 470, 270, 560)
        st = svg("steam.svg", {"o": 0.30, "y": int(16 * math.sin(bt * 2.4)), "y2": int(16 * math.cos(bt * 2.1))})
        st = st.filter(ImageFilter.GaussianBlur(4))
        paste(img, st, (px, py - 40), scale=1.05)
        glow(img, src_to_target(270, 590, 470, 270, 630), 190, (90, 170, 235), 0.28)
    caption(img, "Смешай два вещества…", tl)
    return img


def scene3(tl: float) -> Image.Image:
    fp = load(os.path.join(PRE, "experiment_fullscreen.png"))
    fpop = load(os.path.join(PRE, "new_recipe_popup.png"))
    pop = 0.92 + 0.08 * ease_back(clamp01(tl / 0.35))
    img = kb(fp, 270, 480, 540)
    dim(img, 0.55)
    cx, cy = 546, 958
    glow(img, (cx, cy), 330 + 40 * math.sin(tl * 4), (179, 157, 219), 0.38)
    if tl < 1.5:
        u = tl / 1.5
        sp = svg("spark_burst.svg", {"o": round(0.95 * (1 - u * 0.7), 2), "len": int(68 - 38 * u)})
        sc = 1.9 + 0.9 * ease_out(u)
        sp = cut_center(sp, 112)
        paste(img, sp, (cx, cy), scale=sc, rot=tl * 40)
    else:
        u = 1.0
        sp = svg("spark_burst.svg", {"o": 0.28, "len": 30})
        sp = cut_center(sp, 112)
        paste(img, sp, (cx, cy), scale=2.8 + 0.25 * math.sin(tl * 3), rot=tl * 18)
    # попап отдельным слоем поверх вспышки
    crop = fpop.crop((118, 316, 428, 642))
    cw2, ch2 = crop.width * 2, crop.height * 2
    crop = crop.resize((int(cw2 * pop), int(ch2 * pop)), Image.LANCZOS)
    shadow = Image.new("RGBA", (crop.width + 60, crop.height + 60), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((30, 30, crop.width + 30, crop.height + 30),
                                              radius=26, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    paste(img, shadow, (cx, cy + 10))
    paste(img, crop, (cx, cy))
    for i in range(10):
        a = i * 0.628 + 0.3
        u = clamp01((tl - 0.1 - i * 0.05) / 1.6)
        if u <= 0 or u >= 1:
            continue
        rr = 200 + 380 * ease_out(u)
        x = cx + rr * math.cos(a)
        y = cy + rr * math.sin(a) * 1.2
        r = 7 * (1 - u) + 2
        d = ImageDraw.Draw(img)
        col = (255, 215, 106) if i % 2 else (179, 157, 219)
        d.ellipse((x - r, y - r, x + r, y + r), fill=col + (int(220 * (1 - u)),))
    caption(img, "…и первооткрытие — твоё. Навсегда.", tl)
    return img


GLYPHS = ["fire", "water", "air", "earth", "crystal", "house", "fish", "bird"]


def scene4(tl: float) -> Image.Image:
    img = Image.new("RGBA", (W, H), (16, 12, 24, 255))
    glow(img, (540, 620), 700, (53, 196, 181), 0.16)
    n = 11 + int(clamp01(tl / 3.4) * 46)
    chip = svg("counter_chip.svg", {"text": f"открыто {n}/57"})
    paste(img, chip, (540, 250), scale=1.0, opacity=clamp01(tl / 0.3))
    xs = [170, 423, 676, 929]
    ys = [520, 800]
    for i, g in enumerate(GLYPHS):
        u = clamp01((tl - 0.25 - i * 0.16) / 0.45)
        if u <= 0:
            continue
        s = ease_back(u)
        fx = xs[i % 4] + 6 * math.sin(tl * 1.6 + i)
        fy = ys[i // 4] + 8 * math.sin(tl * 1.3 + i * 2)
        layer = svg(f"glyph_{g}.svg")
        paste(img, layer, (fx, fy), scale=1.75 * s, rot=6 * math.sin(tl + i))
    caption(img, "57 веществ. 105 рецептов. Мир открывает их с тобой.", tl, size=72)
    return img


def scene5(tl: float) -> Image.Image:
    f = load(os.path.join(PRE, "companion_final.png"))
    img = kb(f, 270, 480, 540)
    dim(img, 0.86)
    bob = 12 * math.sin(tl * 3.1)
    name = "laugh.png" if tl > 2.0 else "idle.png"
    spr = load(os.path.join(SPIRITS, name))
    bounce = 1 + 0.12 * math.sin(clamp01((tl - 2.0) / 0.4) * math.pi) if tl > 2.0 else 1.0
    glow(img, (872, 452 + bob), 170, (255, 170, 60), 0.32)
    paste(img, spr, (872, 452 + bob), scale=0.95 * bounce, rot=5 * math.sin(tl * 2))
    if tl > 0.7:
        b = svg("bubble.svg", {"o": round(clamp01((tl - 0.7) / 0.25), 2),
                               "text": "варим!" if tl > 2.0 else "привет!"})
        b = b.transpose(Image.FLIP_LEFT_RIGHT)
        paste(img, b, (660, 268 + bob * 0.6), scale=0.78 * ease_back(clamp01((tl - 0.7) / 0.35)))
    caption(img, "Светик подскажет, поболтает и запомнит твоё имя.", tl, y=1350, size=74)
    return img


ROOM = (14, 288, 512, 588)


def scene6(tl: float) -> Image.Image:
    f = load(os.path.join(PRE, "house_final_repaired.png"))
    room = f.crop(ROOM)
    rw = W
    rh = int(room.height * rw / room.width)
    room = room.resize((rw, rh), Image.LANCZOS)
    img = Image.new("RGBA", (W, H), (16, 12, 24, 255))
    ry = 430
    glow(img, (540, ry + rh / 2), 760, (255, 170, 80), 0.10)
    mask = Image.new("L", (rw, rh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, rw - 1, rh - 1), radius=34, fill=255)
    room.putalpha(mask)
    img.alpha_composite(room, (0, ry))
    bd0 = ImageDraw.Draw(img)
    bd0.rounded_rectangle((3, ry + 3, rw - 4, ry + rh - 4), radius=34,
                          outline=(53, 196, 181, 190), width=5)
    # живой огонь: игровые кадры свечения камина
    gi = int(tl * 10) % 10
    gname = "glow_fireplace.png" if gi == 0 else f"glow_fireplace_{gi}.png"
    gpath = os.path.join(FX, gname)
    if os.path.exists(gpath):
        gl = load(gpath)
        gx = int((355 - ROOM[0]) * rw / room.width * (room.width / rw) * 1.0)
        gx = int((355 - ROOM[0]) * rw / (ROOM[2] - ROOM[0]))
        gy = ry + int((497 - ROOM[1]) * rh / (ROOM[3] - ROOM[1]))
        paste(img, gl, (gx, gy), scale=2.6, opacity=0.95)
    # луч из окна
    wx = int((65 - ROOM[0]) * rw / (ROOM[2] - ROOM[0]))
    wy = ry + int((345 - ROOM[1]) * rh / (ROOM[3] - ROOM[1]))
    sway = 10 * math.sin(tl * 0.9)
    beam = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(beam)
    bd.polygon([(wx, wy), (wx + 150 + sway, wy), (wx + 300 + sway, wy + 430), (wx + 50, wy + 430)],
               fill=(255, 236, 190, 26))
    img.alpha_composite(beam)
    caption(img, "Построй ему дом. Он виден другим игрокам.", tl, y=1345, size=74)
    return img


def scene7(tl: float) -> Image.Image:
    fq = load(os.path.join(PRE, "event_qte_repaired.png"))
    fl = load(os.path.join(PRE, "lab_cells48.png"))
    if tl < 2.0:
        img = kb(fq, 270, 520, 540)
        dim(img, 0.9)
        for k in range(2):
            u = ((tl * 0.9) + k * 0.5) % 1.0
            r = 70 + 150 * ease_out(u)
            d = ImageDraw.Draw(img)
            d.ellipse((704 - r, 1330 - r, 704 + r, 1330 + r),
                      outline=(245, 179, 1, int(200 * (1 - u))), width=8)
        glow(img, (704, 1330), 200, (245, 179, 1), 0.25)
    else:
        u = clamp01((tl - 2.0) / 0.45)
        img = kb(fq, 270, 520, 540)
        lab = kb(fl, 270, 430, 540)
        img = Image.blend(img, lab, ease_out(u))
        dim(img, 0.9)
        if u > 0.4:
            rot = (tl - 2.0) * 80
            arr = svg("loop_arrows.svg", {"o": round(clamp01((u - 0.4) / 0.4) * 0.95, 2)})
            paste(img, arr, (540, 600), scale=1.5, rot=rot)
            et = (tl - 2.4) % 1.4
            if tl > 2.4:
                chip = svg("counter_chip.svg", {"text": "+1.08 ⚡/с"})
                paste(img, chip, (540, 430 - 60 * et), scale=0.8, opacity=1 - et / 1.4)
    caption(img, "Кометы, заказы гильдии… и эфир капает, пока тебя нет.", tl, y=1330, size=70)
    return img


def scene8(tl: float) -> Image.Image:
    g = 0.20 + 0.08 * math.sin(tl * 2.6)
    img = svg("end_card.svg", {"glow": round(g, 3), "glow2": round(g * 0.45, 3)})
    bob = 12 * math.sin(tl * 2.8)
    spr = load(os.path.join(SPIRITS, "idle.png"))
    glow(img, (930, 560 + bob), 150, (255, 170, 60), 0.35)
    paste(img, spr, (930, 560 + bob), scale=0.8, rot=6 * math.sin(tl * 2.2))
    d = ImageDraw.Draw(img)
    for i in range(14):
        a = i * 2.39996
        rr = 300 + 120 * ((i * 37) % 5) / 5
        x = 540 + rr * math.cos(a + tl * 0.15)
        y = 640 + rr * 0.9 * math.sin(a + tl * 0.15)
        tw = 0.5 + 0.5 * math.sin(tl * 3 + i * 1.7)
        s = 3 + 5 * tw
        d.line((x - s, y, x + s, y), fill=(255, 255, 255, int(120 * tw)), width=3)
        d.line((x, y - s, x, y + s), fill=(255, 255, 255, int(120 * tw)), width=3)
    return img


SCENES = [
    (0.0, 3.0, scene1, 1),
    (3.0, 3.5, scene2, 2),
    (6.5, 4.0, scene3, 3),
    (10.5, 4.0, scene4, 4),
    (14.5, 4.0, scene5, 5),
    (18.5, 4.0, scene6, 6),
    (22.5, 4.0, scene7, 7),
    (26.5, 4.0, scene8, 8),
]
DUR = SCENES[-1][0] + SCENES[-1][1]

_vignette = None


def vignette() -> Image.Image:
    global _vignette
    if _vignette is None:
        import numpy as np
        yy, xx = np.mgrid[0:H, 0:W].astype("float32")
        dx = (xx - W / 2) / (W / 2)
        dy = (yy - H / 2) / (H / 2)
        r = np.sqrt(dx * dx + dy * dy)
        a = np.clip((r - 0.75) / 0.55, 0, 1) ** 1.6 * 110
        # scrim снизу под субтитры
        scr = np.clip((yy - (H * 0.70)) / (H * 0.22), 0, 1) * 90
        top = np.clip(((H * 0.06) - yy) / (H * 0.06), 0, 1) * 60
        alpha = np.clip(a + scr + top, 0, 160).astype("uint8")
        img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
        img.putalpha(Image.fromarray(alpha, "L"))
        _vignette = img
    return _vignette


def frame_at(t: float) -> Image.Image:
    for start, dur, fn, _idx in SCENES:
        if t < start + dur or fn is SCENES[-1][2]:
            tl = t - start
            img = fn(tl).convert("RGBA")
            # вспышки на стыках
            flash_at = {6.5: 0.14, 26.5: 0.16}
            for ft, fd in flash_at.items():
                if ft - fd < t < ft + fd:
                    u = 1 - abs(t - ft) / fd
                    white = Image.new("RGBA", (W, H), (255, 250, 235, int(200 * u)))
                    img.alpha_composite(white)
            img.alpha_composite(vignette())
            return img.convert("RGB")
    return SCENES[-1][2](DUR - SCENES[-1][0]).convert("RGB")
