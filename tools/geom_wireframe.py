#!/usr/bin/env python3
"""Wireframe-схемы UI из геом-дампа Demo-харнесса (R17).

Дамп получается РЕАЛЬНЫМ прогоном игры headless:
    godot --headless --path alchemists-loop -- --demo --geom [--action=…]
и содержит геометрию настоящих Control-узлов (pos/size/vis/z/text).
Этот скрипт рисует по дампу схематичный макет 540×960 — не пиксели движка,
но реальные координаты, размеры, z-порядок и подписи живой UI.

Использование:
    python3 tools/geom_wireframe.py /tmp/geom_lab.txt shots/wireframe_lab.png "Лаборатория"
"""
import re
import sys

from PIL import Image, ImageDraw, ImageFont

LINE_RE = re.compile(
    r"^(?P<pad> *)(?P<name>\S+) \[(?P<cls>\w+)\] "
    r"pos=\((?P<x>[\d.-]+), (?P<y>[\d.-]+)\) "
    r"size=\((?P<w>[\d.-]+), (?P<h>[\d.-]+)\) "
    r"vis=(?P<vis>true|false)"
    r"(?: min=\([^)]*\))?"
    r"(?: z=(?P<z>-?\d+))?"
    r'(?: text="(?P<text>.*)")?$'
)

BG = (16, 24, 32)
PANEL_FILL = (26, 36, 48)
PANEL_LINE = (58, 74, 90)
BTN_FILL = (22, 32, 44)
BTN_LINE = (196, 168, 74)   # золото темы
TXT_COLOR = (214, 222, 228)
BTN_TXT = (232, 224, 192)
DIM_FILL = (0, 0, 0)
OTHER_LINE = (70, 90, 110)


def parse(path):
    nodes = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = LINE_RE.match(line.rstrip("\n"))
            if not m:
                continue
            nodes.append({
                "idx": len(nodes),
                "depth": len(m["pad"]) // 2,
                "name": m["name"],
                "cls": m["cls"],
                "x": float(m["x"]), "y": float(m["y"]),
                "w": float(m["w"]), "h": float(m["h"]),
                "vis": m["vis"] == "true",
                "z": int(m["z"] or 0),
                "text": m["text"] or "",
            })
    return nodes


def effective_visibility(nodes):
    """Дерево в исходном порядке: узел виден, если видны все предки."""
    stack = []
    for n in nodes:
        del stack[n["depth"]:]
        parent_vis = stack[-1] if stack else True
        vis = n["vis"] and parent_vis
        stack.append(vis)
        n["eff_vis"] = vis


def render(nodes, out, title):
    effective_visibility(nodes)
    # stable sort: порядок дерева сохраняется внутри одного z.
    nodes = sorted(nodes, key=lambda n: n["z"])
    img = Image.new("RGB", (540, 960), BG)
    draw = ImageDraw.Draw(img, "RGBA")
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    font_s = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 10)

    for n in nodes:
        if not n["eff_vis"] or n["w"] < 2 or n["h"] < 2:
            continue
        x0, y0 = n["x"], n["y"]
        x1, y1 = x0 + n["w"], y0 + n["h"]
        cls = n["cls"]
        if cls == "ColorRect":
            if "Dim" in n["name"]:
                draw.rectangle([x0, y0, x1, y1], fill=DIM_FILL + (150,))
        elif cls in ("PanelContainer", "Panel"):
            draw.rectangle([x0, y0, x1, y1], fill=PANEL_FILL + (235,),
                           outline=PANEL_LINE)
        elif cls == "Button":
            draw.rectangle([x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5],
                           fill=BTN_FILL, outline=BTN_LINE)
            t = n["text"].replace("⏎", " | ")
            if t:
                tw = draw.textlength(t, font=font_s)
                while tw > n["w"] - 8 and len(t) > 4:
                    t = t[:-4] + "…"
                    tw = draw.textlength(t, font=font_s)
                draw.text((x0 + max(4, (n["w"] - tw) / 2),
                           y0 + max(2, (n["h"] - 12) / 2)), t,
                          font=font_s, fill=BTN_TXT)
        elif cls == "Label":
            t = n["text"]
            if not t:
                continue
            draw.text((x0 + 1, y0 + 1), t[:80], font=font, fill=TXT_COLOR)
        elif cls in ("TextureRect", "LineEdit", "GridContainer"):
            # прозрачные контейнеры и спрайты — только тонкий контур
            draw.rectangle([x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5],
                           outline=OTHER_LINE)
        # остальные Container/Control прозрачны в игре — не рисуем

    draw.rectangle([0, 0, 540, 22], fill=(8, 12, 16))
    draw.text((8, 4), title, font=font, fill=(240, 200, 90))
    img.save(out)
    print("saved", out)


if __name__ == "__main__":
    src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
    render(parse(src), dst, title)
