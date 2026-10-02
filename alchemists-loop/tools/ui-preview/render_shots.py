#!/usr/bin/env python3
"""Рендер приёмочных скриншотов UI «Atheneum» без браузера.

Кадры строятся теми же значениями, что и интерактивное превью (app.js):
«ДО» — по фактическому коду/кадрам previews/*.png, «ПОСЛЕ» — по токенам
game/ui/design_tokens.gd. Иконки растрируются из репозиторных SVG (svglib),
текст — настоящими шрифтами игры assets/fonts/Manrope-*.ttf.

Запуск: python3 tools/ui-preview/render_shots.py
Результат: docs/ui-ux/screenshots/*.png
"""
from __future__ import annotations

import pathlib
import tempfile

from PIL import Image, ImageDraw, ImageFont
from reportlab.graphics import renderPM
from svglib.svglib import svg2rlg

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent          # alchemists-loop/
ICONS = ROOT / "assets" / "ui" / "icons"
FONTS = ROOT / "assets" / "fonts"
OUT = ROOT.parent / "docs" / "ui-ux" / "screenshots"
CACHE = pathlib.Path(tempfile.gettempdir()) / "atheneum_icons"

W, H = 540, 960

BEFORE = dict(bg0=(14, 17, 26), bg1=(17, 24, 36), bg2=(22, 29, 41), bg3=(16, 21, 29),
              line=(29, 38, 52), line2=(42, 54, 72), ink1=(255, 255, 255),
              ink2=(153, 168, 180), ink3=(140, 153, 164), accent=(32, 164, 155),
              accent_ink=(255, 255, 255), gold=(232, 170, 26), gold_ink=(41, 31, 8),
              r=8, hit=36)
AFTER = dict(bg0=(10, 15, 22), bg1=(18, 26, 36), bg2=(24, 34, 46), bg3=(13, 20, 29),
             line=(36, 49, 63), line2=(53, 72, 92), ink1=(234, 242, 247),
             ink2=(169, 184, 198), ink3=(126, 141, 156), accent=(58, 214, 198),
             accent_ink=(5, 38, 34), gold=(233, 180, 76), gold_ink=(36, 26, 5),
             r=10, hit=44)

FONT_FILES = {400: "Manrope-Regular.ttf", 500: "Manrope-Medium.ttf",
              600: "Manrope-SemiBold.ttf", 700: "Manrope-Bold.ttf",
              800: "Manrope-ExtraBold.ttf"}
_font_cache: dict = {}


DEJAVU = pathlib.Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
DEJAVU_B = pathlib.Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")


def _needs_fallback(s: str) -> bool:
    return any(0x2190 <= ord(ch) <= 0x2BFF or ord(ch) >= 0x1F000 for ch in s)


def font(size: int, weight: int = 400, fb: bool = False) -> ImageFont.FreeTypeFont:
    key = (size, weight, fb)
    if key not in _font_cache:
        if fb:
            path = DEJAVU_B if weight >= 600 and DEJAVU_B.exists() else DEJAVU
            if not path.exists():
                path = FONTS / FONT_FILES[weight]
        else:
            path = FONTS / FONT_FILES[weight]
        _font_cache[key] = ImageFont.truetype(str(path), size)
    return _font_cache[key]


def text(img, xy, s, size=15, weight=400, color=(255, 255, 255), anchor="la", tracking=0.0):
    d = ImageDraw.Draw(img)
    f_sel = font(size, weight, fb=_needs_fallback(s))
    if tracking:
        x, y = xy
        f = f_sel
        for ch in s:
            d.text((x, y), ch, font=f, fill=color, anchor="la")
            x += d.textlength(ch, font=f) + tracking
        return
    d.text(xy, s, font=f_sel, fill=color, anchor=anchor)


def rrect(img, box, r, fill=None, outline=None, width=1):
    semi = (fill and len(fill) > 3 and fill[3] < 255) or (outline and len(outline) > 3 and outline[3] < 255)
    if not semi:
        ImageDraw.Draw(img).rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)
        return
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(ov).rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)
    img.alpha_composite(ov)


def blend_rect(img, box, color):
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(ov).rectangle(box, fill=color)
    img.alpha_composite(ov)


def _raster_icons() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = CACHE / "_src.svg"
    for f in sorted(ICONS.glob("*.svg")):
        dst = CACHE / f"{f.stem}.png"
        if dst.exists():
            continue
        tmp.write_text(f.read_text().replace("#FFFFFF", "#000000"))
        d = svg2rlg(str(tmp))
        d.width, d.height = 96, 96
        d.scale(4, 4)
        renderPM.drawToFile(d, str(dst), fmt="PNG")


def icon(img, name, box, color, size=None):
    x, y, w, h = box
    size = size or min(w, h)
    src = Image.open(CACHE / f"{name}.png").convert("RGBA")
    px = src.load()
    for yy in range(src.height):
        for xx in range(src.width):
            r, g, b, _a = px[xx, yy]
            px[xx, yy] = (*color, int(255 - (r + g + b) / 3))
    src = src.resize((size, size), Image.LANCZOS)
    img.paste(src, (int(x + (w - size) / 2), int(y + (h - size) / 2)), src)


def orb(img, cx, cy, r, color, glyph=None, count=None, mode="after"):
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    hl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hr = int(r * 0.62)
    hd.ellipse([cx - r * 0.55 - hr // 2, cy - r * 0.6 - hr // 2,
                cx - r * 0.55 + hr // 2, cy - r * 0.6 + hr // 2], fill=(255, 255, 255, 45))
    img.alpha_composite(hl)
    if glyph:
        text(img, (cx, cy - 2), glyph, size=int(r * 0.9), weight=600,
             color=(13, 18, 24) if sum(color) > 380 else (255, 255, 255), anchor="mm")
    if count:
        s = str(count)
        f = font(11, 600) if mode == "after" else font(12, 400)
        d = ImageDraw.Draw(img)
        tw = d.textlength(s, font=f)
        if mode == "after":
            bw, bh = tw + 10, 15
            bx, by = cx - bw / 2, cy + r * 0.62 - bh / 2
            rrect(img, [bx, by, bx + bw, by + bh], bh // 2, fill=(13, 20, 29, 217))
            d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=bh // 2,
                                outline=(255, 255, 255, 64), width=1)
            text(img, (cx, by + bh / 2 - 1), s, size=11, weight=600, color=(255, 255, 255), anchor="mm")
        else:
            br = max(13, tw / 2 + 5)
            bx, by = cx - r * 0.7, cy + r * 0.7
            d.ellipse([bx - br, by - br, bx + br, by + br], fill=(6, 10, 14, 232),
                      outline=(255, 255, 255, 56), width=2)
            text(img, (bx, by - 1), s, size=12, color=(255, 255, 255), anchor="mm")


def button(img, box, label, kind=0, mode="after", icon_name=None, disabled=False, size=13):
    x, y, w, h = box
    C = AFTER if mode == "after" else BEFORE
    if mode == "after":
        fill = {0: (24, 34, 46, 235), 1: C["accent"], 2: C["gold"]}[kind]
        if disabled:
            fill = (18, 26, 36, 150)
        rrect(img, [x, y, x + w, y + h], C["r"], fill=fill,
              outline=None if kind else C["line"], width=1)
        fg = {0: C["ink1"], 1: C["accent_ink"], 2: C["gold_ink"]}[kind]
        if disabled:
            fg = C["ink3"]
    else:
        fill = {0: (40, 53, 73), 1: (32, 164, 155), 2: (232, 170, 26)}[kind]
        rrect(img, [x, y, x + w, y + h], 8, fill=fill)
        fg = {0: (224, 236, 240), 1: (255, 255, 255), 2: (41, 31, 8)}[kind]
    if icon_name:
        iw = 16
        icon(img, icon_name, (x + 12, y + h / 2 - iw / 2, iw, iw), fg)
        text(img, (x + 12 + iw + 6, y + h / 2), label, size=size, weight=600, color=fg, anchor="lm")
    else:
        text(img, (x + w / 2, y + h / 2), label, size=size, weight=600, color=fg, anchor="mm")


def new_phone() -> Image.Image:
    return Image.new("RGBA", (W, H), (0, 0, 0, 255))


def header(img, mode):
    C = AFTER if mode == "after" else BEFORE
    img.paste(Image.new("RGBA", (W, H), C["bg0"]), (0, 0))
    if mode == "after":
        # блок 1, вариант A: иконки, тач 44, бейдж-пилюля; цвета кнопок игры
        _hz_head_buttons(img, 24, 0.0)
        return 56
    text(img, (12, 22), "ПЕТЛЯ АЛХИМИКА", size=24, weight=800, color=C["ink1"])
    x = W - 12 - 36 - 4 * (46 if mode == "before" else 44) - 3 * 6
    bw = 46 if mode == "before" else 44
    bh = 36 if mode == "before" else 44
    y = 14
    if mode == "before":
        glyphs = [("✦", True), ("▲", False), ("♪", False), ("Ж", False)]
        for i, (g, gold) in enumerate(glyphs):
            bx = x + i * (bw + 6)
            rrect(img, [bx, y, bx + bw, y + bh], 8, fill=C["gold"] if gold else (40, 53, 73))
            text(img, (bx + bw / 2, y + bh / 2), g, size=14, weight=600,
                 color=C["gold_ink"] if gold else (224, 236, 240), anchor="mm")
            if i == 1:
                text(img, (bx + bw - 5, y + 3), "1", size=11, color=(255, 255, 255))
    else:
        names = ["star", "trend_up", "volume", "book"]
        for i, nm in enumerate(names):
            bx = x + i * (bw + 6)
            rrect(img, [bx, y, bx + bw, y + bh], 10, fill=(24, 34, 46, 235), outline=C["line"])
            icon(img, nm, (bx + bw / 2 - 10, y + bh / 2 - 10, 20, 20), C["ink1"])
            if i == 1:
                rrect(img, [bx + bw - 8, y - 5, bx + bw + 8, y + 11], 8, fill=C["gold"])
                text(img, (bx + bw, y + 3), "1", size=11, weight=600, color=C["gold_ink"], anchor="mm")
    orb(img, W - 12 - 18, y + 18, 18, (80, 190, 120), mode=mode)
    return y + bh




def resrow(img, top, mode):
    C = AFTER if mode == "after" else BEFORE
    y = top + 10
    if mode == "before":
        text(img, (12, y), "⚡ Эфир: 120 / 230  ·  резерв: 0  ·  +1.05/с", size=14, color=C["ink1"])
        button(img, [W - 12 - 82 - 8 - 82, y - 5, 82, 34], "Дом", 2, mode)
        button(img, [W - 12 - 82, y - 5, 82, 34], "Лавка", 1, mode)
        y += 34
        text(img, (12, y + 4), "Веществ открыто: 11 / 57  ·  Рецептов: 7 / 53", size=14, color=C["ink2"])
        y += 26
        text(img, (12, y + 2), "✦ Светик: Первая пара — 0/1", size=13, color=(255, 217, 112))
        y += 22
    else:
        icon(img, "bolt", (12, y + 1, 18, 18), C["accent"])
        text(img, (36, y), "120 / 230", size=15, weight=600, color=C["ink1"])
        text(img, (118, y + 2), "+1.05/с · резерв 0", size=13, color=C["ink3"])
        button(img, [W - 12 - 96 - 8 - 96, y - 6, 96, 40], "Дом", 0, mode, icon_name="home")
        button(img, [W - 12 - 96, y - 6, 96, 40], "Лавка", 0, mode, icon_name="bag")
        y += 40
        text(img, (12, y + 4), "Веществ открыто: 11 / 57  ·  Рецептов: 7 / 53", size=13, color=C["ink2"])
        y += 24
        icon(img, "star", (12, y + 1, 14, 14), C["gold"])
        text(img, (32, y), "Светик: Первая пара — 0/1", size=13, color=C["gold"])
        y += 20
    return y + 8


TABS = [("flask", "Эксперимент"), ("cauldron", "Лаборатория"), ("globe", "Мир"),
        ("home", "Дом"), ("trophy", "Рейтинг"), ("sliders", "Инструменты")]


def tabs(img, top, mode, active):
    C = AFTER if mode == "after" else BEFORE
    y = top
    if mode == "before":
        x = 12
        for i, (_, nm) in enumerate(TABS):
            tw = int(ImageDraw.Draw(img).textlength(nm, font=font(14))) + 24
            fill = (26, 33, 45) if i == active else (16, 20, 28)
            rrect(img, [x, y, x + tw, y + 34], 0, fill=fill, outline=(42, 54, 72))
            if i == active:
                ImageDraw.Draw(img).rectangle([x, y, x + tw, y + 2], fill=(89, 224, 214))
            text(img, (x + tw / 2, y + 17), nm, size=14, color=(255, 255, 255) if i == active else (207, 216, 224), anchor="mm")
            x += tw
        return y + 34 + 8
    # автоподбор: 6 разделов обязаны поместиться в 540 px целиком
    d = ImageDraw.Draw(img)
    chosen = None
    for fs, pad, isz, gap, hsep in [(11, 6, 16, 4, 2), (11, 5, 15, 3, 2), (10, 5, 15, 3, 2)]:
        total = 14 + sum(int(isz + gap + d.textlength(nm, font=font(fs, 600)) + pad * 2) + hsep
                         for _, nm in TABS)
        if total <= W - 12:
            chosen = (fs, pad, isz, gap, hsep)
            break
    fs, pad, isz, gap, hsep = chosen or (10, 4, 14, 3, 1)
    rrect(img, [12, y, W - 12, y + 38], 999, fill=(18, 26, 36, 217), outline=C["line"])
    x = 14.0
    for i, (icn, nm) in enumerate(TABS):
        tl = d.textlength(nm, font=font(fs, 600))
        tw = int(isz + gap + tl + pad * 2)
        if i == active:
            rrect(img, [x, y + 3, x + tw, y + 35], 999, fill=(58, 214, 198, 46), outline=(58, 214, 198, 179))
        cw = isz + gap + tl
        sx = x + (tw - cw) / 2
        icon(img, icn, (sx, y + 19 - isz / 2, isz, isz), C["accent"] if i == active else C["ink2"])
        text(img, (sx + isz + gap, y + 19), nm, size=fs, weight=600,
             color=C["accent"] if i == active else C["ink2"], anchor="lm")
        x += tw + hsep
    return y + 38 + 8


def panel(img, box, mode, double=False):
    C = AFTER if mode == "after" else BEFORE
    rrect(img, list(box), C["r"] if mode == "after" else 14, fill=C["bg1"], outline=C["line"])
    if double and mode == "before":
        rrect(img, [box[0] + 5, box[1] + 5, box[2] - 5, box[3] - 5], 12, outline=(70, 183, 174), width=3)


def screen_lab(mode):
    tm, mode = mode, "before"
    img = new_phone()
    C = AFTER if mode == "after" else BEFORE
    top = header(img, tm)
    top = resrow(img, top, mode)
    top = tabs(img, top, tm, 1)
    panel(img, [12, top, W - 12, H - 190 if mode == "after" else H - 168], mode)
    cy = top + 96
    orb(img, 120, cy, 30, (224, 118, 79), glyph="▲" if mode == "before" else None, mode=mode)
    text(img, (120, cy + 42), "A", size=11, color=C["ink3"], anchor="mm")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([200, cy - 40, 340, cy + 46], radius=60, fill=(51, 60, 78))
    d.ellipse([192, cy - 52, 348, cy - 18], fill=(91, 101, 121))
    orb(img, 420, cy, 30, (90, 167, 232), glyph="◆" if mode == "before" else None, mode=mode)
    text(img, (420, cy + 42), "B", size=11, color=C["ink3"], anchor="mm")
    y = cy + 70
    text(img, (24, y), "Родник", size=16 if mode == "before" else 17,
         weight=400 if mode == "before" else 700,
         color=(89, 224, 214) if mode == "before" else C["ink1"])
    y += 28
    for i, col in enumerate([(224, 118, 79), (90, 167, 232), (196, 164, 124), (206, 232, 239)]):
        orb(img, 150 + i * 80, y + 22, 22, col, glyph=("▲", "◆", "▲", "≋")[i] if mode == "before" else None, mode=mode)
    y += 56
    text(img, (24, y), "Каждые 6 с: +1 «Вода».", size=13, color=C["ink2"])
    y += 26
    text(img, (24, y), "Книга рецептов", size=16 if mode == "before" else 17,
         weight=400 if mode == "before" else 700,
         color=(255, 255, 255) if mode == "before" else C["ink1"])
    y += 28
    if mode == "after":
        rrect(img, [24, y, W - 24, y + 44], 10, fill=C["bg3"], outline=C["line2"])
        icon(img, "search", (36, y + 14, 16, 16), C["ink3"])
        text(img, (60, y + 22), "Поиск вещества по названию…", size=15, color=C["ink3"])
    else:
        rrect(img, [24, y, W - 24, y + 44], 4, fill=(21, 27, 37))
        text(img, (36, y + 22), "Поиск вещества по названию…", size=14, color=(109, 120, 131))
    # BrewBar
    by = H - (168 if mode == "before" else 190)
    rrect(img, [12 if mode == "before" else 10, by, W - (12 if mode == "before" else 10), H - (12 if mode == "before" else 10)],
          14 if mode == "before" else 18, fill=(16, 22, 31, 242), outline=(36, 64, 74) if mode == "before" else C["line"])
    if mode == "before":
        ry = by + 12
        button(img, [24, ry, 48, 42], "Все", 0, mode)
        for i, col in enumerate([(224, 118, 79), (90, 167, 232), (196, 164, 124), (206, 232, 239)]):
            orb(img, 100 + i * 52, ry + 21, 22, col, glyph="◆" if i == 1 else "▲", count=100, mode=mode)
        button(img, [320, ry - 5, 130, 52], "ВАРИТЬ", 1, mode, size=16)
        button(img, [456, ry, 34, 42], "↻", 1, mode)
        button(img, [494, ry, 34, 42], "✕", 0, mode)
        ry += 56
        rrect(img, [24, ry, W - 24, ry + 12], 6, fill=(41, 50, 61))
        rrect(img, [24, ry, 24 + int((W - 48) * 0.42), ry + 12], 6, fill=(77, 217, 226))
        ry += 20
        text(img, (24, ry), "Перетащи ингредиенты в лунки или нажми «Варить».", size=13, color=C["ink2"])
    else:
        ry = by + 14
        button(img, [24, ry, 48, 44], "Все", 0, mode)
        for i, col in enumerate([(224, 118, 79), (90, 167, 232), (196, 164, 124), (206, 232, 239)]):
            orb(img, 104 + i * 56, ry + 22, 23, col, count=100, mode=mode)
        ry += 56
        text(img, (24, ry), "КОТЁЛ", size=11, weight=600, color=(89, 224, 214), tracking=0.7)
        rrect(img, [24, ry + 16, 372, ry + 26], 5, fill=C["bg3"], outline=C["line"])
        rrect(img, [24, ry + 16, 24 + int(348 * 0.42), ry + 26], 5, fill=C["accent"])
        button(img, [384, ry - 6, 132, 52], "ВАРИТЬ", 1, mode, icon_name="cauldron", size=15)
        ry += 34
        y2 = ry + 18
        text(img, (24, y2 + 14), "Перетащи ингредиенты в лунки или нажми «Варить».", size=13, color=C["ink2"])
        button(img, [368, y2, 44, 44], "", 1, mode, icon_name="repeat")
        button(img, [420, y2, 44, 44], "", 0, mode, icon_name="x")
        button(img, [472, y2, 44, 44], "Стоп", 1, mode, disabled=True, size=12)
    return img


def screen_experiment(mode):
    tm, mode = mode, "before"
    img = new_phone()
    C = BEFORE
    top = header(img, tm)
    top = resrow(img, top, mode)
    top = tabs(img, top, tm, 0)
    text(img, (12, top), "ЭКСПЕРИМЕНТ", size=20, weight=800, color=(255, 255, 255))
    button(img, [W - 12 - 118, top - 4, 118, 36], "Светик · 10 ⚡", 2, mode, size=13)
    top += 34
    text(img, (12, top), "«Вода» в котле · выбери второй реагент.", size=13, color=C["ink2"])
    top += 24
    panel(img, [12, top, W - 12, H - 12], mode, double=True)
    y = top + 14
    text(img, (26, y), "ВЫБРАТЬ ВТОРОЙ", size=14, weight=700, color=C["ink1"])
    text(img, (W - 116, y + 8), "8 / 11", size=11, color=C["ink3"], anchor="rm")
    button(img, [W - 108, y - 6, 84, 40], "Закрыть", 0, mode)
    y += 34
    text(img, (26, y), "Нажми на ячейку — вещество сразу появится на поле.", size=12, color=C["ink2"])
    y += 24
    rrect(img, [26, y, W - 26, y + 44], 4, fill=(21, 27, 37))
    text(img, (38, y + 22), "Найти второй реагент…", size=14, color=(109, 120, 131))
    y += 54
    x = 26
    for i, nm in enumerate(["Недавние", "Светик", "Стихии", "Все"]):
        tw = int(ImageDraw.Draw(img).textlength(nm, font=font(12, 600))) + 28
        if i == 0:
            rrect(img, [x, y, x + tw, y + 40], 8, fill=(56, 69, 90))
            fg = (255, 255, 255)
        else:
            rrect(img, [x, y, x + tw, y + 40], 8, outline=(42, 54, 72))
            fg = (207, 216, 224)
        text(img, (x + tw / 2, y + 20), nm, size=12, weight=600, color=fg, anchor="mm")
        x += tw + 5
    y += 50
    # ячейки 4xN — как в текущей игре (GridContainer columns=4)
    cells = [((90, 167, 232), "Вода"), ((206, 232, 239), "Воздух"), ((196, 164, 124), "Земля"),
             ((224, 118, 79), "Огонь"), ((168, 232, 255), "Лёд"), ((150, 214, 145), "Росток"),
             ((221, 208, 162), "Пыль"), ((172, 200, 228), "Туман")]
    cw = (W - 52 - 18) // 4
    for i, (col, nm) in enumerate(cells):
        cx = 26 + (i % 4) * (cw + 6)
        cy = y + (i // 4) * 74
        rrect(img, [cx, cy, cx + cw, cy + 66], 12, fill=(15, 31, 46, 148), outline=(51, 87, 107, 173))
        orb(img, cx + cw / 2, cy + 26, 14, col, mode=mode)
        text(img, (cx + cw / 2, cy + 50), nm, size=10, color=(207, 216, 224), anchor="mm")
    y += 2 * 74 + 6
    text(img, (W / 2, y), "Ячейки 4×N — как в игре, без строк-таблиц.", size=11, color=C["ink3"], anchor="mm")
    return img


def screen_house(mode):
    tm, mode = mode, "before"
    img = new_phone()
    C = AFTER if mode == "after" else BEFORE
    top = header(img, tm)
    top = resrow(img, top, mode)
    top = tabs(img, top, tm, 3)
    panel(img, [12, top, W - 12, H - 12], mode)
    y = top + 16
    text(img, (W / 2, y), "ДОМ СВЕТИКА", size=22 if mode == "before" else 21, weight=800,
         color=(255, 230, 107) if mode == "before" else C["gold"], anchor="mm")
    y += 26
    text(img, (W / 2, y), "Уют, обстановка и произвольные цвета — видно другим игрокам.",
         size=13, color=C["ink2"], anchor="mm")
    y += 22
    rrect(img, [26, y, W - 26, y + 250], 10, fill=(107, 90, 73))
    d = ImageDraw.Draw(img)
    d.ellipse([W - 190, y + 70, W - 110, y + 160], fill=(255, 157, 60, 200))
    d.ellipse([W - 172, y + 88, W - 128, y + 140], fill=(255, 215, 106))
    d.rectangle([60, y + 40, 130, y + 110], fill=(70, 110, 150), outline=(90, 66, 44), width=6)
    y += 262
    if mode == "before":
        button(img, [26, y, W - 52, 46], "Домик построен ✓", 2, mode, disabled=True, size=14)
        y += 58
    else:
        icon(img, "check", (26, y + 2, 16, 16), (111, 207, 142))
        text(img, (50, y + 10), "Домик построен — уют виден гостям и в рейтинге.", size=13, color=C["ink2"])
        y += 30
    text(img, (26, y), "Обстановка", size=14, weight=400 if mode == "before" else 700,
         color=(255, 255, 255) if mode == "before" else C["ink1"])
    y += 24
    text(img, (26, y), "Коллекция: 12/90 · купленное ставится бесплатно", size=12, color=C["ink2"])
    y += 24
    furn = [("home", "Окно · 1/10", "Классическое"), ("map", "Ковёр · 3/10", "Восточный"),
            ("user", "Стул · 1/10", "Классический"), ("leaf", "Растение · 1/10", "В горшке")]
    for icn, nm, val in furn:
        rrect(img, [26, y, 82, y + 44], 8, fill=(12, 17, 24))
        icon(img, icn, (40, y + 12, 20, 20), (159, 180, 196))
        text(img, (94, y + 22), nm, size=14, color=C["ink1"], anchor="lm")
        if mode == "before":
            button(img, [W - 172, y, 146, 44], f"{val} ✓", 1, mode, size=14)
        else:
            bw = 118
            button(img, [W - 26 - bw, y + 2, bw, 40], val, 0, mode, size=13)
            icon(img, "chevron_right", (W - 40, y + 14, 14, 14), C["ink2"])
        y += 52
    return img


def screen_popup(mode):
    img = screen_lab(mode)  # внутри mode станет "before", вкладки — tm
    blend_rect(img, [0, 0, W, H], (0, 0, 0, 158) if mode == "before" else (4, 8, 12, 168))
    cw, ch = 320, 330
    x0, y0 = (W - cw) // 2, (H - ch) // 2 - 20
    C = AFTER if mode == "after" else BEFORE
    rrect(img, [x0, y0, x0 + cw, y0 + ch], 16 if mode == "before" else 18,
          fill=(16, 22, 31, 250) if mode == "before" else (18, 26, 36, 250),
          outline=(42, 54, 72) if mode == "before" else C["line2"])
    y = y0 + 18
    if mode == "after":
        button(img, [x0 + cw - 56, y0 + 12, 44, 44], "", 0, mode, icon_name="x")
        y += 34
    text(img, (W / 2, y + 10), "НОВЫЙ РЕЦЕПТ!", size=24 if mode == "before" else 21, weight=800,
         color=(255, 230, 107) if mode == "before" else C["gold"], anchor="mm")
    y += 40
    orb(img, W / 2, y + 55, 46, (150, 214, 145), glyph="✿" if mode == "before" else None, mode=mode)
    y += 116
    text(img, (W / 2, y), "Огонь + Росток → Цветок", size=14, color=C["ink2"], anchor="mm")
    y += 20
    text(img, (W / 2, y), "+12 эфира", size=14, color=C["ink2"], anchor="mm")
    y += 26
    if mode == "before":
        button(img, [x0 + 16, y, (cw - 40) / 2, 44], "Забрать", 2, mode, size=14)
        button(img, [x0 + 24 + (cw - 40) / 2, y, (cw - 40) / 2, 44], "Закрыть", 0, mode, size=14)
    else:
        button(img, [x0 + 16, y, cw - 32 - 104, 44], "Забрать", 1, mode, size=15)
        button(img, [x0 + cw - 16 - 96, y, 96, 44], "Закрыть", 0, mode, size=14)
    return img


def board_icons():
    cols, cell = 6, 150
    names = [p.stem for p in sorted(ICONS.glob("*.svg"))]
    rows = (len(names) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell + 40, rows * (cell + 10) + 120), (7, 11, 16, 255))
    text(img, (20, 28), "Икон-сет «Atheneum» — 37 SVG, сетка 24×24, stroke 2", size=24, weight=800, color=(234, 242, 247))
    text(img, (20, 66), "assets/ui/icons/*.svg · генератор tools/make_icons.py · раньше иконок не было (глифы ✦ ▲ ♪ Ж ⚡)", size=14, color=(126, 141, 156))
    for i, nm in enumerate(names):
        cx = 20 + (i % cols) * cell + cell // 2
        cy = 120 + (i // cols) * (cell + 10) + 40
        rrect(img, [cx - cell // 2 + 8, cy - 40, cx + cell // 2 - 8, cy + 62], 12, fill=(16, 24, 35), outline=(28, 39, 51))
        icon(img, nm, (cx - 16, cy - 26, 32, 32), (234, 242, 247))
        text(img, (cx, cy + 40), nm, size=12, color=(126, 141, 156), anchor="mm")
    return img


def board_tabs():
    img = Image.new("RGBA", (1160, 360), (7, 11, 16, 255))
    text(img, (24, 26), "Меню вкладок: ДО (слева) и ПОСЛЕ (справа)", size=24, weight=800, color=(234, 242, 247))
    text(img, (24, 62), "Пилюля-дорожка, круглое обрамление активной, иконка 16 px + текст 11 px по центру;", size=13, color=(126, 141, 156))
    text(img, (24, 80), "все 6 разделов внутри 540 px («Инструменты» целиком).", size=13, color=(126, 141, 156))
    for half, m in ((0, "before"), (1, "after")):
        x0 = 24 + half * 560
        rrect(img, [x0, 110, x0 + 548, 336], 14, fill=(13, 20, 28), outline=(28, 39, 51))
        text(img, (x0 + 16, 126), "ДО" if m == "before" else "ПОСЛЕ", size=13, weight=700, color=(126, 141, 156))
        sub = Image.new("RGBA", (540, 200), (0, 0, 0, 0))
        tabs(sub, 20, m, 1)
        img.paste(sub, (x0 + 4, 150), sub)
        if m == "after":
            for i, nm in enumerate(["flask", "cauldron", "globe", "home", "trophy", "sliders"]):
                icon(img, nm, (x0 + 16 + i * 40, 260, 24, 24), (234, 242, 247))
    return img


def main() -> None:
    _raster_icons()
    OUT.mkdir(parents=True, exist_ok=True)
    shots = {
        "screen_lab_before": screen_lab("before"),
        "screen_lab_after": screen_lab("after"),
        "screen_experiment_before": screen_experiment("before"),
        "screen_experiment_after": screen_experiment("after"),
        "screen_house_after": screen_house("after"),
        "screen_popup_after": screen_popup("after"),
        "board_icons": board_icons(),
        "board_tabs": board_tabs(),
    }
    for name, img in shots.items():
        img.convert("RGB").save(OUT / f"{name}.png")
        print("wrote", OUT / f"{name}.png", img.size)




# ================= итерация-2, блок 1: шапка и строка ресурсов =================
HZ_H = 250


def _hz_base() -> Image.Image:
    return Image.new("RGBA", (W, HZ_H), BEFORE["bg0"] + (255,))


def _hz_bubble(img, y):
    rrect(img, [W - 242, y, W - 12, y + 56], 12, fill=(22, 32, 44, 250), outline=(44, 58, 75))
    text(img, (W - 230, y + 12), "Привет! Я — Светик. Давай", size=13, color=(232, 241, 248))
    text(img, (W - 230, y + 32), "сварим что-нибудь!", size=13, color=(232, 241, 248))


def hz_before() -> Image.Image:
    img = _hz_base()
    text(img, (12, 20), "ПЕТЛЯ АЛХИМИКА", size=24, weight=800, color=(255, 255, 255))
    x = W - 12 - 36 - 4 * 46 - 3 * 6
    for i, (g, gold) in enumerate([("✦", True), ("▲", False), ("♪", False), ("Ж", False)]):
        bx = x + i * 52
        rrect(img, [bx, 14, bx + 46, 14 + 36], 8, fill=(232, 170, 26) if gold else (40, 53, 73))
        text(img, (bx + 23, 32), g, size=14, weight=600,
             color=(41, 31, 8) if gold else (224, 236, 240), anchor="mm")
        if i == 1:
            text(img, (bx + 40, 17), "1", size=11, color=(255, 255, 255))
    orb(img, W - 30, 32, 18, (80, 190, 120))
    text(img, (12, 66), "⚡ Эфир: 120 / 230  ·  резерв: 0  ·  +1.05/с", size=14, color=(255, 255, 255))
    button(img, [W - 12 - 82 - 8 - 82, 60, 82, 34], "Дом", 2, "before")
    button(img, [W - 12 - 82, 60, 82, 34], "Лавка", 1, "before")
    text(img, (12, 104), "Веществ открыто: 11 / 57  ·  Рецептов: 7 / 53", size=14, color=BEFORE["ink2"])
    text(img, (12, 130), "✦ Светик: Первая пара — 0/1", size=13, color=(255, 217, 112))
    _hz_bubble(img, 58)  # перекрывает «Дом»/«Лавка» — как в игре сейчас
    return img


def _hz_head_buttons(img, title_size, tracking):
    text(img, (12, 22), "ПЕТЛЯ АЛХИМИКА", size=title_size, weight=800,
         color=AFTER["ink1"], tracking=tracking)
    x = W - 12 - 40 - 4 * 44 - 3 * 6
    for i, (nm, gold) in enumerate([("star", True), ("trend_up", False), ("volume", False), ("book", False)]):
        bx = x + i * 50
        if gold:
            rrect(img, [bx, 12, bx + 44, 56], 10, fill=AFTER["gold"])
            icon(img, nm, (bx + 12, 22, 20, 20), AFTER["gold_ink"])
        else:
            rrect(img, [bx, 12, bx + 44, 56], 10, fill=(24, 34, 46, 235), outline=AFTER["line"])
            icon(img, nm, (bx + 12, 22, 20, 20), AFTER["ink1"])
        if i == 1:
            rrect(img, [bx + 34, 6, bx + 50, 22], 8, fill=AFTER["gold"])
            text(img, (bx + 42, 14), "1", size=11, weight=600, color=AFTER["gold_ink"], anchor="mm")
    orb(img, W - 32, 34, 20, (80, 190, 120))


def hz_after_a() -> Image.Image:
    """Минимум: иконки + тач 44 + бейдж-пилюля + пузырь не перекрывает кнопки."""
    img = _hz_base()
    _hz_head_buttons(img, 24, 0.0)
    text(img, (12, 66), "⚡ Эфир: 120 / 230  ·  резерв: 0  ·  +1.05/с", size=14, color=(255, 255, 255))
    button(img, [W - 12 - 82 - 8 - 82, 60, 82, 34], "Дом", 2, "before")
    button(img, [W - 12 - 82, 60, 82, 34], "Лавка", 1, "before")
    text(img, (12, 104), "Веществ открыто: 11 / 57  ·  Recipes: 7 / 53".replace("Recipes", "Рецептов"),
         size=14, color=BEFORE["ink2"])
    text(img, (12, 130), "✦ Светик: Первая пара — 0/1", size=13, color=(255, 217, 112))
    _hz_bubble(img, 158)
    return img


def hz_after_b() -> Image.Image:
    """Порядок: то же + KPI-чип эфира, равные «Дом/Лавка», тайтл 21 с трекингом."""
    img = _hz_base()
    _hz_head_buttons(img, 21, 0.4)
    icon(img, "bolt", (12, 66, 18, 18), AFTER["accent"])
    text(img, (36, 64), "120 / 230", size=16, weight=600, color=AFTER["ink1"])
    text(img, (128, 68), "+1.05/с · резерв 0", size=13, color=AFTER["ink3"])
    button(img, [W - 12 - 96 - 8 - 96, 60, 96, 40], "Дом", 0, "after", icon_name="home")
    button(img, [W - 12 - 96, 60, 96, 40], "Лавка", 0, "after", icon_name="bag")
    text(img, (12, 108), "Веществ открыто: 11 / 57  ·  Рецептов: 7 / 53", size=13, color=AFTER["ink2"])
    icon(img, "star", (12, 130, 14, 14), AFTER["gold"])
    text(img, (32, 129), "Светик: Первая пара — 0/1", size=13, color=AFTER["gold"])
    _hz_bubble(img, 158)
    return img


def board_header() -> Image.Image:
    variants = [("ДО · как сейчас в игре", hz_before()),
                ("ПОСЛЕ A · минимум: иконки, тач 44, бейдж-пилюля", hz_after_a()),
                ("ПОСЛЕ B · A + KPI-чип эфира, равные Дом/Лавка, тайтл 21", hz_after_b())]
    img = Image.new("RGBA", (W + 40, len(variants) * (HZ_H + 64) + 90), (7, 11, 16, 255))
    text(img, (20, 26), "Блок 1 · Шапка и строка ресурсов", size=24, weight=800, color=(234, 242, 247))
    text(img, (20, 62), "Код игры не тронут: это мок-предложения для согласования.",
         size=13, color=(126, 141, 156))
    y = 90
    for caption, sub in variants:
        text(img, (20, y + 14), caption, size=14, weight=700, color=(169, 184, 198))
        img.paste(sub, (20, y + 40), sub)
        y += HZ_H + 64
    return img


if __name__ == "__main__":
    main()
