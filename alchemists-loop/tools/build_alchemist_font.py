#!/usr/bin/env python3
"""Собирает TTF-шрифт «Alchemist Runic» из SVG-спрайта с глифами.

Зачем: глифы нарисованы обводкой (stroke, fill="none"), а в шрифте контуры
заливные. Скрипт разворачивает обводку в заливку (смещение на ±w/2, круглые
стыки и окончания) и раскладывает результат по таблицам TrueType.

Запуск из корня проекта:
    python tools/build_alchemist_font.py
    python tools/build_alchemist_font.py --stroke-scale 3.4 --advance tight

Требуется fontTools:  python -m pip install fonttools
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import alchemist_font_engine as eng  # noqa: E402

from fontTools.fontBuilder import FontBuilder  # noqa: E402
from fontTools.pens.ttGlyphPen import TTGlyphPen  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DEFAULT_SVG = os.path.join(HERE, "alchemist-glyphs.svg")
DEFAULT_OUT = os.path.join(ROOT, "assets", "fonts", "Alchemist-Runic.ttf")

ELEM = re.compile(r"<(path|circle|ellipse|rect)\b([^>]*?)/?>", re.S)

# Пунктуация: в спрайте у неё именованные id, а не сам символ.
NAMED = {
    "period": ".", "comma": ",", "colon": ":", "semicolon": ";",
    "exclam": "!", "question": "?", "hyphen": "-", "endash": "\u2013",
    "emdash": "\u2014", "plus": "+", "equal": "=", "slash": "/",
    "backslash": "\\", "parenleft": "(", "parenright": ")",
    "bracketleft": "[", "bracketright": "]", "guillemotleft": "\u00ab",
    "guillemotright": "\u00bb", "quotedbl": '"', "quoteleft": "'",
    "multiply": "\u00d7", "ellipsis": "\u2026", "percent": "%",
    "numerosign": "\u2116",
}


def attrs_of(s: str) -> dict:
    return dict(re.findall(r'([\w:-]+)\s*=\s*"([^"]*)"', s))


def codepoint(gid: str) -> int | None:
    """glyph-A -> 0x41, glyph-cyr-Я -> 0x042F, glyph-4 -> 0x34, glyph-hyphen -> 0x2D"""
    body = gid[len("glyph-"):]
    if body in NAMED:
        return ord(NAMED[body])
    if body.startswith("cyr-"):
        rest = body[4:]
        return ord(rest) if len(rest) == 1 else None
    if len(body) == 1 and (body.isalnum()):
        return ord(body)
    return None


def glyph_geometry(body: str, stroke_scale: float):
    """-> (contours, is_hole). Обводка разворачивается в заливку."""
    contours, holes = [], []
    for m in ELEM.finditer(body):
        tag, a = m.group(1), attrs_of(m.group(2))
        sw = float(a.get("stroke-width", 1.0)) * stroke_scale
        filled = a.get("fill", "none") not in ("none",)
        stroked = "stroke" in a

        subpaths = []
        if tag == "path":
            subpaths = [(pts, closed) for pts, closed in
                        (eng.flatten_subpath(s) for s in eng.parse_path(a.get("d", "")))]
        elif tag == "circle":
            subpaths = [(eng.circle_pts(float(a["cx"]), float(a["cy"]), float(a["r"])), True)]
        elif tag == "ellipse":
            subpaths = [(eng.circle_pts(float(a["cx"]), float(a["cy"]), 0,
                                        float(a["rx"]), float(a["ry"])), True)]
        elif tag == "rect":
            subpaths = [(eng.rect_pts(float(a["x"]), float(a["y"]), float(a["width"]),
                                      float(a["height"]), float(a.get("rx", 0)),
                                      float(a.get("ry", 0))), True)]

        for pts, closed in subpaths:
            if len(pts) < 2:
                continue
            if stroked and sw > 0:
                cs = [c for c in eng.stroke_contours(pts, closed, sw)
                      if len(c) >= 3 and abs(eng.signed_area(c)) > 0.05]
                if closed and len(cs) == 2:
                    cs.sort(key=lambda c: abs(eng.signed_area(c)))
                    contours.append(cs[1]); holes.append(False)   # внешний
                    contours.append(cs[0]); holes.append(True)    # внутренний
                else:
                    for c in cs:
                        contours.append(c); holes.append(False)
            if filled:
                c = eng.dedupe(pts)
                if len(c) >= 3 and abs(eng.signed_area(c)) > 0.05:
                    contours.append(c); holes.append(False)
    return contours, holes


def main() -> int:
    ap = argparse.ArgumentParser(description="Собрать Alchemist Runic TTF из SVG-глифов")
    ap.add_argument("--svg", default=DEFAULT_SVG, help="исходный SVG со спрайтом глифов")
    ap.add_argument("--out", default=DEFAULT_OUT, help="куда положить TTF")
    ap.add_argument("--stroke-scale", type=float, default=3.4,
                    help="множитель толщины штриха; 3.4 = 6.8%% кегля, читается от 20 px")
    ap.add_argument("--advance", choices=["tight", "uniform"], default="tight",
                    help="tight — апрош по чернилам, uniform — как в исходной сетке 100x100")
    ap.add_argument("--sidebearing", type=float, default=60.0,
                    help="боковой пробел в единицах шрифта (только для tight)")
    ap.add_argument("--simplify", type=float, default=4.0,
                    help="допуск упрощения контура, единиц шрифта")
    ap.add_argument("--family", default="Alchemist Runic")
    args = ap.parse_args()

    if not os.path.exists(args.svg):
        print(f"нет файла глифов: {args.svg}", file=sys.stderr)
        return 2
    raw = open(args.svg, encoding="utf-8").read()
    pairs = re.findall(r'<symbol id="(glyph-[^"]+)"[^>]*>(.*?)</symbol>', raw, re.S)
    if not pairs:
        print("в SVG не найдено ни одного <symbol id=\"glyph-...\">", file=sys.stderr)
        return 2

    glyph_order = [".notdef", "space"]
    cmap, glyf, metrics = {}, {}, {}
    skipped, ink_lo, ink_hi = [], 1e9, -1e9
    total_pts = 0

    box = [(120, 0), (880, 0), (880, 700), (120, 700)]
    pen = TTGlyphPen(None)
    for c in (box, box[::-1]):
        pen.moveTo(c[0])
        for p in c[1:]:
            pen.lineTo(p)
        pen.closePath()
    glyf[".notdef"] = pen.glyph()
    metrics[".notdef"] = (1000, 0)
    glyf["space"] = TTGlyphPen(None).glyph()
    metrics["space"] = (500, 0)

    for gid, body in pairs:
        cp = codepoint(gid)
        if cp is None:
            skipped.append(gid)
            continue
        name = "uni%04X" % cp
        if name in glyf:                      # дубль кодпоинта
            skipped.append(gid)
            continue
        contours, holes = glyph_geometry(body, args.stroke_scale)
        pts = [p for c in contours for p in c]
        if not pts:
            skipped.append(gid)
            continue
        x0 = min(p[0] for p in pts); x1 = max(p[0] for p in pts)
        y0 = min(p[1] for p in pts); y1 = max(p[1] for p in pts)
        ink_lo = min(ink_lo, y1); ink_hi = max(ink_hi, y0)

        if args.advance == "uniform":
            dx, adv = 0.0, float(eng.UPM)
        else:
            dx = args.sidebearing - x0 * eng.SCALE
            adv = (x1 - x0) * eng.SCALE + 2 * args.sidebearing

        pen = TTGlyphPen(None)
        for c, is_hole in zip(contours, holes):
            f = [(x + dx, y) for (x, y) in eng.to_font(c)]
            f = eng.simplify(f, args.simplify)
            f = [(int(round(x)), int(round(y))) for (x, y) in f]
            cl = []
            for p in f:
                if not cl or p != cl[-1]:
                    cl.append(p)
            if len(cl) < 3:
                continue
            area = eng.signed_area(cl)
            # TrueType заливает по правилу nonzero: дырка должна идти против внешнего
            if is_hole and area > 0:
                cl = cl[::-1]
            if not is_hole and area < 0:
                cl = cl[::-1]
            pen.moveTo(cl[0])
            for p in cl[1:]:
                pen.lineTo(p)
            pen.closePath()
            total_pts += len(cl)
        glyf[name] = pen.glyph()
        metrics[name] = (int(round(adv)), 0)
        cmap[cp] = name
        glyph_order.append(name)

    # метрики по факту чернил: ничего не должно обрезаться
    asc = int(math.ceil((eng.BASELINE_SVG - ink_hi) * eng.SCALE / 10.0) * 10) + 10
    desc = int(math.floor((eng.BASELINE_SVG - ink_lo) * eng.SCALE / 10.0) * 10) - 10
    asc = max(asc, 800)
    desc = min(desc, -200)

    fb = FontBuilder(eng.UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyf)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=asc, descent=desc)
    fb.setupNameTable({
        "familyName": args.family,
        "styleName": "Regular",
        "uniqueFontIdentifier": f"{args.family.replace(' ', '')}-Regular-1.0",
        "fullName": f"{args.family} Regular",
        "psName": f"{args.family.replace(' ', '')}-Regular",
        "version": "Version 1.000",
        "manufacturer": "generated by tools/build_alchemist_font.py",
        "designer": "Alchemist's Loop",
        "licenseDescription": "Proprietary. Internal project asset, all rights reserved.",
    })
    fb.setupOS2(sTypoAscender=asc, sTypoDescender=desc, sTypoLineGap=0,
                usWinAscent=asc, usWinDescent=abs(desc),
                sxHeight=470, sCapHeight=700, achVendID="ALCH", fsType=0)
    fb.setupPost()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    fb.save(args.out)

    print(f"источник : {args.svg}")
    print(f"собрано  : {args.out}  ({os.path.getsize(args.out)} байт)")
    print(f"глифов   : {len(glyph_order)}   точек контуров: {total_pts}")
    print(f"штрих    : x{args.stroke_scale} = {args.stroke_scale * 2:.1f}% кегля")
    print(f"апрош    : {args.advance}")
    print(f"вертикаль: ascent {asc}  descent {desc}")
    if skipped:
        print(f"пропущено: {len(skipped)} ({', '.join(skipped[:8])}"
              f"{' ...' if len(skipped) > 8 else ''})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
