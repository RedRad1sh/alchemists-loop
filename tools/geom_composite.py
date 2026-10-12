#!/usr/bin/env python3
"""High-fidelity композит сцены из геом-дампа Demo-харнесса (R17e).

НЕ рендер Godot: это композиция из РЕАЛЬНЫХ rect'ов живой UI (дамп
--demo --geom) + настоящих PNG-спрайтов пропов + текстов узлов.
Нужен, чтобы оценивать дизайн сцены визуально в sandbox, где пиксельный
рендер движка невозможен (headless = null-текстура, нет GL/X).

Использование:
    python3 tools/geom_composite.py /tmp/geom_master.png-дамп.txt out.png "Заголовок"
"""
import re
import sys

from PIL import Image, ImageDraw, ImageFont, ImageFilter

LINE_RE = re.compile(
    r"^(?P<pad> *)(?P<name>\S+) \[(?P<cls>\w+)\] "
    r"pos=\((?P<x>[\d.-]+), (?P<y>[\d.-]+)\) "
    r"size=\((?P<w>[\d.-]+), (?P<h>[\d.-]+)\) "
    r"vis=(?P<vis>true|false)"
    r"(?: min=\([^)]*\))?"
    r"(?: z=(?P<z>-?\d+))?"
    r'(?: text="(?P<text>.*)")?$'
)

SCENE_DIR = "alchemists-loop/assets/ui/scene"
PROP_SPRITES = {
    "Prop_fountain": "fountain.png",
    "Prop_workbench": "workbench.png",
    "Prop_retort": "retort.png",
    "Prop_deck": "deck.png",
    "Prop_scroll": "scroll.png",
}

BG = (13, 20, 30)
PANEL_FILL = (21, 31, 44, 210)
PANEL_LINE = (58, 74, 90)
BTN_FILL = (24, 34, 47, 235)
GOLD = (240, 190, 90)
TXT = (214, 222, 228)
DIM = (10, 10, 12, 150)


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


def render(nodes, out, title, assets_root):
    stack = []
    for n in nodes:
        del stack[n["depth"]:]
        parent_vis = stack[-1] if stack else True
        n["eff_vis"] = n["vis"] and parent_vis
        stack.append(n["eff_vis"])
    nodes = sorted(nodes, key=lambda n: n["z"])

    img = Image.new("RGBA", (540, 960), BG + (255,))
    draw = ImageDraw.Draw(img, "RGBA")
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    font_s = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    font_b = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 14)

    for n in nodes:
        if not n["eff_vis"] or n["w"] < 2 or n["h"] < 2:
            continue
        x0, y0 = n["x"], n["y"]
        x1, y1 = x0 + n["w"], y0 + n["h"]
        name, cls = n["name"], n["cls"]

        if name in PROP_SPRITES:
            # настоящий спрайт пропа, вписанный в его реальный rect
            spr = Image.open(f"{assets_root}/{SCENE_DIR}/{PROP_SPRITES[name]}").convert("RGBA")
            spr.thumbnail((int(n["w"]) + 24, int(n["h"]) + 24), Image.LANCZOS)
            cx, cy = (x0 + n["w"] / 2, y0 + n["h"] / 2)
            img.alpha_composite(spr, (int(cx - spr.width / 2), int(cy - spr.height / 2)))
            continue
        if cls == "TextureRect":
            continue  # Glow/Sprite внутри пропов — уже в арте
        if cls == "ColorRect":
            if "Dim" in name:
                draw.rectangle([x0, y0, x1, y1], fill=DIM)
            elif name == "FieldDecor":
                draw.rectangle([x0, y0, x1, y1], fill=(17, 26, 38, 255))
            continue
        if cls in ("PanelContainer", "Panel"):
            draw.rounded_rectangle([x0, y0, x1, y1], 10, fill=PANEL_FILL,
                                   outline=PANEL_LINE)
            continue
        if cls == "Button":
            draw.rounded_rectangle([x0 + 1, y0 + 1, x1 - 1, y1 - 1], 8,
                                   fill=BTN_FILL, outline=GOLD, width=2)
            t = n["text"].replace("⏎", " | ")
            if t:
                f = font_s if len(t) > 14 else font
                tw = draw.textlength(t, font=f)
                while tw > n["w"] - 10 and len(t) > 4:
                    t = t[:-4] + "…"
                    tw = draw.textlength(t, font=f)
                draw.text((x0 + max(4, (n["w"] - tw) / 2),
                           y0 + max(2, (n["h"] - f.size) / 2)), t,
                          font=f, fill=(236, 214, 150))
            continue
        if cls == "Label":
            t = n["text"]
            if not t:
                continue
            f = font_b if t.isupper() and len(t) < 24 else font
            draw.text((x0 + 2, y0 + 1), t[:90], font=f, fill=TXT)
            continue
        if cls in ("LineEdit", "GridContainer"):
            draw.rectangle([x0 + .5, y0 + .5, x1 - .5, y1 - .5],
                           outline=(70, 90, 110))

    draw.rectangle([0, 0, 540, 24], fill=(8, 12, 16, 255))
    draw.text((8, 5), title, font=font_b, fill=GOLD)
    img.convert("RGB").save(out)
    print("saved", out)


if __name__ == "__main__":
    src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
    root = sys.argv[4] if len(sys.argv) > 4 else "/home/user/alchemists-loop"
    render(parse(src), dst, title, root)
