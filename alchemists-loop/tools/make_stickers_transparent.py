#!/usr/bin/env python3
"""
Удаляет белый фон со стикеров Светика + убирает белую антиалиас-кайму.

Этапы:
1. Floodfill от углов: все пиксели, «близкие к белому» и достижимые от края — в маску фона.
2. Удаляем дехало (white fringe): любой полупрозрачный пиксель, у которого большая часть
   RGB — белая и который смежен с прозрачным фоном — делаем ещё более прозрачным,
   убираем белёсый оттенок (умножаем цвет в сторону соседнего цветного пикселя).
3. Для пикселей у края (сосед = фон) с высокой яркостью и малой хромой (белый ободок
   генератора) — полностью убираем.
4. Обрезаем пустые поля, вписываем в 1024x1024 с равными отступами.
"""
import sys
from collections import deque
from pathlib import Path
from PIL import Image, ImageFilter

STICKER_DIR = Path(__file__).resolve().parent.parent / "assets" / "spirits" / "stickers"


def dist_to_white(c):
    r, g, b = c[:3]
    return ((255-r)**2 + (255-g)**2 + (255-b)**2) ** 0.5


def chroma(c):
    r, g, b = c[:3]
    return max(r, g, b) - min(r, g, b)


def luminance(c):
    r, g, b = c[:3]
    return int(0.299*r + 0.587*g + 0.114*b)


def floodfill_bg(px, w, h):
    """BFS от углов: пиксель — фон если он светлый ахроматический и белый в пределах порога."""
    bg = [[False]*w for _ in range(h)]
    q = deque()
    # первичный проход: строгий белый
    def seed(x, y, tol_init=22):
        if not (0 <= x < w and 0 <= y < h):
            return
        c = px[x, y]
        if chroma(c) <= 20 and dist_to_white(c) < tol_init and not bg[y][x]:
            bg[y][x] = True
            q.append((x, y))
    for x in range(w):
        seed(x, 0); seed(x, h-1)
    for y in range(h):
        seed(0, y); seed(w-1, y)

    dirs = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
    while q:
        x, y = q.popleft()
        c = px[x, y]
        for dx, dy in dirs:
            nx, ny = x+dx, y+dy
            if not (0 <= nx < w and 0 <= ny < h) or bg[ny][nx]:
                continue
            nc = px[nx, ny]
            # Сосед белый и похож на текущий → фон
            if chroma(nc) <= 25 and dist_to_white(nc) < 30:
                bg[ny][nx] = True
                q.append((nx, ny))
    return bg


def remove_white_halo(px, bg, w, h):
    """
    Убирает белый антиалиас-ободок вокруг персонажа:
    - любой пиксель на границе фон/персонаж, у которого яркость > 210 и хрома < 35
      (т.е. белёсый/светло-серый обод генератора) — альфа *= 0.3 и сдвигаем цвет в сторону соседа.
    - полупрозрачные белые пиксели прямо у фона — в прозрачность.
    """
    out = [[None]*w for _ in range(h)]
    dirs4 = [(-1,0),(1,0),(0,-1),(0,1)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if bg[y][x]:
                out[y][x] = (0, 0, 0, 0)
                continue

            # Проверяем, есть ли сосед-фон
            neighbor_color = None
            n_count = 0
            for dx, dy in dirs4:
                nx, ny = x+dx, y+dy
                if 0 <= nx < w and 0 <= ny < h:
                    if bg[ny][ny and ny < h and 0 <= nx < w] if False else (0<=nx<w and 0<=ny<h and bg[ny][nx]):
                        n_count += 1
                    elif not bg[ny][nx] and (0<=nx<w and 0<=ny<h):
                        neighbor_color = px[nx, ny]
            if n_count == 0:
                # Внутри персонажа — оставляем как есть
                out[y][x] = (r, g, b, a)
                continue

            # Пиксель на границе. Если он сам очень белый/светло-серый — это кайма.
            lum = luminance((r, g, b))
            chr_ = chroma((r, g, b))
            if lum > 215 and chr_ < 40:
                # Белая кайма: убираем в прозрачность
                # Частично смешиваем в сторону соседнего цветного пикселя, но с малой альфой
                if neighbor_color and n_count <= 2:
                    nr, ng, nb, na = neighbor_color
                    # смешиваем 25% соседнего цвета, альфа 20%
                    out[y][x] = (
                        int(r*0.5 + nr*0.5),
                        int(g*0.5 + ng*0.5),
                        int(b*0.5 + nb*0.5),
                        int(a*0.15),
                    )
                else:
                    out[y][x] = (0, 0, 0, 0)
            elif lum > 190 and chr_ < 25 and a < 255:
                # Полупрозрачный светлый пиксель у края — приглушаем альфу
                out[y][x] = (r, g, b, int(a*0.4))
            else:
                out[y][x] = (r, g, b, a)
    return out


def expand_bg_for_halo(out, w, h, passes=2):
    """Дополнительный проход: если пиксель теперь полупрозрачный и очень белый — сделай прозрачным."""
    dirs8 = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
    for _ in range(passes):
        changed = False
        new_out = [row[:] for row in out]
        for y in range(h):
            for x in range(w):
                r,g,b,a = out[y][x]
                if a == 0:
                    continue
                lum = luminance((r,g,b))
                chr_ = chroma((r,g,b))
                # Если 4+ из 8 соседей прозрачные и пиксель очень светлый — это кайма
                bg_neighbors = 0
                for dx,dy in dirs8:
                    nx,ny = x+dx,y+dy
                    if not(0<=nx<w and 0<=ny<h) or out[ny][nx][3] == 0:
                        bg_neighbors += 1
                if bg_neighbors >= 4 and lum > 220 and chr_ < 30:
                    new_out[y][x] = (0,0,0,0)
                    changed = True
                elif a < 80 and lum > 210:
                    new_out[y][x] = (0,0,0,0)
                    changed = True
        out = new_out
        if not changed:
            break
    return out


def build_image(out, w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            px[x,y] = tuple(out[y][x])
    return im


def trim_pad(im, size=1024, pad=56):
    # Найти bbox по ненулевой альфе
    a = im.split()[-1]
    bbox = a.getbbox()
    if not bbox:
        return im
    x0,y0,x1,y1 = bbox
    x0=max(0,x0-pad); y0=max(0,y0-pad); x1=min(im.width,x1+pad); y1=min(im.height,y1+pad)
    cropped = im.crop((x0,y0,x1,y1))
    canvas = Image.new("RGBA", (size,size), (0,0,0,0))
    # вписать в size с отступами
    avail = size - pad*2
    scale = min(avail/cropped.width, avail/cropped.height)
    nw, nh = int(cropped.width*scale), int(cropped.height*scale)
    cropped = cropped.resize((nw,nh), Image.LANCZOS)
    canvas.paste(cropped, ((size-nw)//2,(size-nh)//2), cropped)
    return canvas


def process(path: Path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()

    bg = floodfill_bg(px, w, h)
    out = remove_white_halo(px, bg, w, h)
    out = expand_bg_for_halo(out, w, h, passes=3)
    im_out = build_image(out, w, h)
    im_out = trim_pad(im_out, size=1024, pad=56)
    im_out.save(path, "PNG", optimize=True)

    a = im_out.split()[-1]
    total = im_out.size[0]*im_out.size[1]
    trans = sum(1 for v in a.tobytes() if v == 0)
    semi = sum(1 for v in a.tobytes() if 0 < v < 255)
    print(f"  {path.name:20s} transparent={trans*100/total:.1f}%  semi={semi*100/total:.1f}%")


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    files = [STICKER_DIR / f for f in args.files] if args.files else sorted(p for p in STICKER_DIR.glob("*.png"))
    print(f"Processing {len(files)} sticker(s) in {STICKER_DIR}\n")
    for f in files:
        if f.exists():
            process(f)
    print("\nDone.")


if __name__ == "__main__":
    sys.exit(main())
