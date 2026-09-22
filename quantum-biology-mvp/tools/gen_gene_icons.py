#!/usr/bin/env python3
"""Генератор иконок генов: чёткие неоновые символы вместо ИИ-каши.
Рисует 128x128 PNG (прозрачный фон + тёмная плашка), стиль совпадает с игрой.
Запуск: python3 tools/gen_gene_icons.py  (перезапишет assets/icons/*.png)
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 128
CX = CY = 64

def neon(draw_core, color, blur=7, glow_int=1.0):
    """core-функция рисует глиф цветом color; возвращаем неон: blur-слой + резкий слой."""
    core = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw_core(ImageDraw.Draw(core), color)
    glow = core.filter(ImageFilter.GaussianBlur(blur))
    a = glow.split()[3].point(lambda v: int(v * glow_int))
    glow.putalpha(a)
    light = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(light).ellipse((CX-58, CY-58, CX+58, CY+58), fill=(255, 255, 255, 16))
    out = Image.alpha_composite(light, glow)
    out = Image.alpha_composite(out, core)
    return out

def plate(color):
    """тёмная плашка-круг с обводкой в тон."""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((CX-56, CY-56, CX+56, CY+56), fill=(8, 14, 19, 235), outline=color+(90,), width=3)
    return img

def poly(d, pts, col):
    d.polygon(pts, fill=col)

# ---------------- глифы ----------------

def icon_fast_mitosis():
    col = (138, 255, 176)
    def core(d, c):
        poly(d, [(70, 14), (40, 62), (58, 62), (46, 110), (86, 52), (63, 52), (76, 26)], c)
        d.line([(58, 62), (70, 40)], fill=(255,255,255,200), width=4)
    return plate(col), neon(core, col)

def icon_chlorophyll():
    col = (124, 232, 107)
    def core(d, c):
        leaf = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
        dl = ImageDraw.Draw(leaf)
        dl.ellipse((44, 14, 84, 114), fill=c)               # вертикальный лист
        dl.line((64, 26, 64, 104), fill=(255,255,255,180), width=4)  # жилка
        leaf = leaf.rotate(38, resample=Image.BICUBIC, center=(64, 64))
        d._image.alpha_composite(leaf) if False else None
    # хак: рисуем отдельным слоем и вклеиваем
    leaf = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    dl = ImageDraw.Draw(leaf)
    dl.ellipse((44, 14, 84, 114), fill=col)
    dl.line((64, 26, 64, 104), fill=(255, 255, 255, 200), width=4)
    leaf = leaf.rotate(-38, resample=Image.BICUBIC, center=(64, 64))
    glow = leaf.filter(ImageFilter.GaussianBlur(8))
    a = glow.split()[3].point(lambda v: int(v * 0.9)); glow.putalpha(a)
    return plate(col), Image.alpha_composite(glow, leaf)

def icon_chemosynthesis():
    col = (195, 154, 255)
    def core(d, c):
        poly(d, [(64, 14), (104, 39), (104, 89), (64, 114), (24, 89), (24, 39)], c)
        poly(d, [(64, 36), (86, 49), (86, 79), (64, 92), (42, 79), (42, 49)], (70, 40, 130))
        for x, y in [(64, 44), (64, 84), (44, 64), (84, 64)]:
            d.ellipse((x-4, y-4, x+4, y+4), fill=(255, 255, 255, 220))
    return plate(col), neon(core, col)

def icon_gigantism():
    col = (95, 212, 255)
    def core(d, c):
        d.ellipse((30, 50, 56, 76), fill=(150, 175, 190))
        d.ellipse((70, 32, 114, 76), fill=c)
        for ang, ln in [(0, 14), (60, 10), (-60, 10)]:
            import math
            x0, y0 = 92, 54
            x1 = x0 + ln * math.cos(math.radians(ang)); y1 = y0 + ln * math.sin(math.radians(ang))
            d.line((x0, y0, x1, y1), fill=(255, 255, 255, 220), width=4)
    return plate(col), neon(core, col)

def icon_segmentation():
    col = (88, 200, 255)
    def core(d, c):
        r = [16, 13, 11, 9]
        xs = [34, 57, 76, 92]
        for x, rr in zip(xs, r):
            d.ellipse((x-rr, 64-rr, x+rr, 64+rr), fill=c, outline=(40, 90, 130), width=3)
        d.ellipse((34-6, 64-6, 34+6, 64+6), fill=(255, 255, 255, 160))
    return plate(col), neon(core, col)

def icon_pigmentation():
    cols = [(255, 107, 156), (95, 212, 255), (255, 209, 102)]
    def core(d, c):
        pts = [(34, 80), (64, 56), (94, 80)]
        for (x, y), cc in zip(pts, cols):
            d.ellipse((x-12, y-12, x+12, y+12), fill=cc)
            d.ellipse((x-12, y-26, x+12, y-2), fill=cc)   # «хвостик» капли
            d.ellipse((x+13, y-18, x+19, y-12), fill=cc)
    return plate((200, 200, 200)), neon(core, (200, 200, 200))

def icon_eyes():
    col = (110, 242, 224)
    def core(d, c):
        d.ellipse((38, 52, 90, 82), fill=(245, 255, 255))
        d.ellipse((48, 58, 80, 78), fill=c)          # радужка
        d.ellipse((56, 62, 74, 76), fill=(10, 20, 30))  # зрачок
        d.ellipse((58, 62, 66, 70), fill=(255, 255, 255, 230))  # блик
        d.arc((34, 46, 94, 88), 20, 160, fill=(20, 60, 70), width=4)  # веко
    return plate(col), neon(core, col)

def icon_flagella():
    col = (124, 240, 192)
    def core(d, c):
        d.ellipse((22, 46, 54, 78), fill=c)
        d.ellipse((26, 50, 50, 74), fill=(255, 255, 255, 60))
        pts = [(54, 62), (68, 56), (84, 64), (96, 44), (108, 36)]
        d.line(pts, fill=c, width=6, joint='curve')
        d.line([(54, 62), (68, 56), (84, 64), (96, 44), (108, 36)], fill=(255, 255, 255, 120), width=2, joint='curve')
    return plate(col), neon(core, col)

def icon_chitin():
    col = (150, 176, 190)
    def core(d, c):
        poly(d, [(64, 12), (100, 34), (96, 92), (64, 112), (32, 92), (28, 34)], c)
        poly(d, [(64, 46), (78, 62), (64, 84), (50, 62)], (60, 80, 95))
        poly(d, [(30, 40), (14, 32), (26, 54)], (255, 190, 110))   # шип слева
        poly(d, [(98, 40), (114, 32), (102, 54)], (255, 190, 110))  # шип справа
        d.ellipse((60, 40, 68, 48), fill=(255, 255, 255, 200))      # заклёпка
        d.ellipse((60, 78, 68, 86), fill=(255, 255, 255, 200))
    return plate(col), neon(core, col)

def icon_bioluminescence():
    col = (214, 255, 94)
    def core(d, c):
        d.ellipse((46, 46, 82, 82), fill=c)
        import math
        for i in range(8):
            ang = math.radians(i * 45)
            x0, y0 = 64 + 30 * math.cos(ang), 64 + 30 * math.sin(ang)
            ln = 18 if i % 2 == 0 else 12
            x1, y1 = x0 + ln * math.cos(ang), y0 + ln * math.sin(ang)
            d.line((x0, y0, x1, y1), fill=c, width=5)
    return plate(col), neon(core, col, glow_int=1.1)

def icon_quantum_aura():
    col = (232, 180, 255)
    gold = (255, 215, 94)
    def core(d, c):
        d.ellipse((30, 26, 98, 94), outline=col, width=3)   # кольцо
        poly(d, [(32, 92), (32, 44), (44, 58), (52, 34), (62, 54), (72, 34), (80, 58), (96, 44), (96, 92)], gold)  # корона
        poly(d, [(32, 84), (32, 92), (96, 92), (96, 84)], gold)
        for x, y in [(20, 24), (108, 20), (108, 100), (20, 106)]:
            d.ellipse((x-3, y-3, x+3, y+3), fill=col)
    return plate(col), neon(core, col, glow_int=1.2)

ICONS = [
    ("fast_mitosis", icon_fast_mitosis, (138, 255, 176)),
    ("chlorophyll", icon_chlorophyll, (124, 232, 107)),
    ("chemosynthesis", icon_chemosynthesis, (195, 154, 255)),
    ("gigantism", icon_gigantism, (95, 212, 255)),
    ("segmentation", icon_segmentation, (88, 200, 255)),
    ("pigmentation", icon_pigmentation, (220, 220, 220)),
    ("eyes", icon_eyes, (110, 242, 224)),
    ("flagella", icon_flagella, (124, 240, 192)),
    ("chitin_armor", icon_chitin, (150, 176, 190)),
    ("bioluminescence", icon_bioluminescence, (214, 255, 94)),
    ("quantum_aura", icon_quantum_aura, (232, 180, 255)),
]

def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
    os.makedirs(out_dir, exist_ok=True)
    sheet = Image.new('RGBA', (SIZE * 11 + 12 * 12, SIZE + 24), (10, 14, 18, 255))
    for i, (name, fn, col) in enumerate(ICONS):
        bg, glyph = fn()
        img = Image.alpha_composite(bg, glyph)
        img.save(os.path.join(out_dir, name + ".png"))
        sheet.paste(img, (12 + i * (SIZE + 12), 12))
        print("ok", name)
    sheet.convert('RGB').save(os.path.join(out_dir, "_sheet_preview.png"))
    print("done")

if __name__ == "__main__":
    main()
