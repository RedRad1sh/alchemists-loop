"""Мини-растеризатор подмножества SVG для тизера «Петли Алхимика».

Поддерживается: svg/g/defs/linearGradient/radialGradient/path/rect/circle/ellipse/
line/polygon/polyline/text; transform (translate/scale/rotate/matrix); opacity,
fill-opacity, stroke-opacity; градиенты userSpaceOnUse и objectBoundingBox;
параметры {{name}} в любых атрибутах и в тексте (подстановка перед разбором).

Шрифты: family="Manrope" с font-weight → TTF из assets/fonts (кириллица).
Рендер в PIL RGBA. Без внешних зависимостей кроме Pillow.
"""
from __future__ import annotations

import math
import re
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

FONT_DIR = "assets/fonts"
_FONT_WEIGHTS = {
    "400": "Manrope-Regular.ttf",
    "500": "Manrope-Medium.ttf",
    "600": "Manrope-SemiBold.ttf",
    "700": "Manrope-Bold.ttf",
    "800": "Manrope-ExtraBold.ttf",
}
_font_cache: dict = {}


def font(weight: str = "800", size: int = 40):
    key = (weight, size)
    if key not in _font_cache:
        path = f"{FONT_DIR}/{_FONT_WEIGHTS.get(weight, _FONT_WEIGHTS['800'])}"
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


def _strip_ns(tag: str) -> str:
    return tag.split("}")[-1]


def _parse_color(value: str, default=None):
    if value is None:
        return default
    value = value.strip()
    if value in ("none", ""):
        return None
    if value.startswith("#"):
        h = value[1:]
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        if len(h) == 6:
            return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
        if len(h) == 8:
            return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16))
    m = re.match(r"rgba?\(([^)]+)\)", value)
    if m:
        parts = [p.strip() for p in m.group(1).split(",")]
        rgb = [int(float(p)) for p in parts[:3]]
        a = float(parts[3]) * 255 if len(parts) > 3 else 255
        return (rgb[0], rgb[1], rgb[2], int(a))
    named = {"white": (255, 255, 255), "black": (0, 0, 0)}
    return named.get(value, default)


def _mat_mul(a, b):
    return (
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
    )


def _parse_transform(s: str):
    m = (1, 0, 0, 1, 0, 0)
    if not s:
        return m
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", s):
        v = [float(x) for x in re.split(r"[,\s]+", args.strip()) if x]
        if name == "translate":
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == "rotate":
            a = math.radians(v[0])
            ca, sa = math.cos(a), math.sin(a)
            t = (ca, sa, -sa, ca, 0, 0)
            if len(v) == 3:
                cx, cy = v[1], v[2]
                t = _mat_mul((1, 0, 0, 1, cx, cy), _mat_mul(t, (1, 0, 0, 1, -cx, -cy)))
        elif name == "matrix":
            t = tuple(v)
        else:
            continue
        m = _mat_mul(m, t)
    return m


_NUM = r"[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?"


def _parse_path(d: str):
    """Возвращает список подпутей; каждый — список точек (x, y)."""
    toks = re.findall(rf"[MmLlHhVvCcQqSsTtZz]|{_NUM}", d)
    subs: list = []
    cur: list = []
    x = y = 0.0
    sx = sy = 0.0
    i = 0
    cmd = ""
    last_ctrl = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    while i < len(toks):
        if isinstance(toks[i], str) and toks[i].isalpha():
            cmd = toks[i]
            i += 1
        c = cmd
        if c in "Mm":
            nx, ny = num(), num()
            if c == "m":
                nx, ny = x + nx, y + ny
            if cur:
                subs.append(cur)
            cur = [(nx, ny)]
            x, y, sx, sy = nx, ny, nx, ny
            cmd = "L" if c == "M" else "l"
        elif c in "Ll":
            nx, ny = num(), num()
            if c == "l":
                nx, ny = x + nx, y + ny
            cur.append((nx, ny))
            x, y = nx, ny
        elif c in "Hh":
            nx = num()
            if c == "h":
                nx += x
            cur.append((nx, y))
            x = nx
        elif c in "Vv":
            ny = num()
            if c == "v":
                ny += y
            cur.append((x, ny))
            y = ny
        elif c in "CcSsQqTt":
            if c in "Cc":
                x1, y1, x2, y2, nx, ny = num(), num(), num(), num(), num(), num()
            elif c in "Ss":
                x2, y2, nx, ny = num(), num(), num(), num()
                x1, y1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl else (x, y)
            elif c in "QqTt":
                if c in "Qq":
                    x1, y1, nx, ny = num(), num(), num(), num()
                else:
                    x1, y1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl else (x, y)
                    nx, ny = num(), num()
                x2, y2 = x1 + (x1 - x) * 0.0, y1
                # квадратичная → кубическая
                cx1, cy1 = x + 2 / 3 * (x1 - x), y + 2 / 3 * (y1 - y)
                cx2, cy2 = nx + 2 / 3 * (x1 - nx), ny + 2 / 3 * (y1 - ny)
                x1, y1, x2, y2 = cx1, cy1, cx2, cy2
            n = 24
            p0 = (x, y)
            for k in range(1, n + 1):
                u = k / n
                w = 1 - u
                bx = w**3 * p0[0] + 3 * w * w * u * x1 + 3 * w * u * u * x2 + u**3 * nx
                by = w**3 * p0[1] + 3 * w * w * u * y1 + 3 * w * u * u * y2 + u**3 * ny
                cur.append((bx, by))
            last_ctrl = (x2, y2)
            x, y = nx, ny
            continue
        elif c in "Zz":
            cur.append((sx, sy))
            x, y = sx, sy
            subs.append(cur)
            cur = []
            last_ctrl = None
            continue
        else:
            i += 1
            continue
        last_ctrl = None
    if cur:
        subs.append(cur)
    return subs


class _Attrs:
    """Обёртка элемента с учётом унаследованных от <g> атрибутов."""

    def __init__(self, el, attrs):
        self._el = el
        self.attrib = attrs

    def get(self, key, default=None):
        return self.attrib.get(key, default)

    def __iter__(self):
        return iter(self._el)

    def itertext(self):
        return self._el.itertext()


class Gradient:
    def __init__(self, el, grads):
        self.kind = _strip_ns(el.tag)
        self.stops = []
        href = el.get("href") or el.get("{http://www.w3.org/1999/xlink}href")
        if href and href.startswith("#") and href[1:] in grads:
            self.stops = list(grads[href[1:]].stops)
        for st in el:
            if _strip_ns(st.tag) == "stop":
                off = float(st.get("offset", 0))
                col = _parse_color(st.get("stop-color", "#000"), (0, 0, 0))
                op = float(st.get("stop-opacity", 1))
                self.stops.append((off, col, op))
        self.units = el.get("gradientUnits", "objectBoundingBox")
        if self.kind == "linearGradient":
            self.p1 = (float(el.get("x1", 0)), float(el.get("y1", 0)))
            self.p2 = (float(el.get("x2", 1)), float(el.get("y2", 0)))
        else:
            self.c = (float(el.get("cx", 0.5)), float(el.get("cy", 0.5)))
            self.r = float(el.get("r", 0.5))
            self.f = (float(el.get("fx", self.c[0])), float(el.get("fy", self.c[1])))

    def image(self, bbox, size):
        x0, y0, x1, y1 = bbox
        w = max(1, int(math.ceil(x1 - x0)))
        h = max(1, int(math.ceil(y1 - y0)))
        yy, xx = np_mgrid(h, w)
        if self.units == "objectBoundingBox":
            bw = max(1e-6, x1 - x0)
            bh = max(1e-6, y1 - y0)
            ux = xx / bw
            uy = yy / bh
        else:
            ux = xx + x0
            uy = yy + y0
        if self.kind == "linearGradient":
            dx, dy = self.p2[0] - self.p1[0], self.p2[1] - self.p1[1]
            denom = dx * dx + dy * dy or 1e-6
            tpos = ((ux - self.p1[0]) * dx + (uy - self.p1[1]) * dy) / denom
        else:
            fx, fy = self.f
            r = max(1e-6, self.r)
            tpos = np_sqrt((ux - fx) ** 2 + (uy - fy) ** 2) / r
        tpos = np_clip(tpos, 0.0, 1.0)
        stops = sorted(self.stops) or [(0.0, (0, 0, 0), 1.0), (1.0, (0, 0, 0), 1.0)]
        out = np_zeros((h, w, 4))
        for i in range(len(stops) - 1):
            o0, c0, a0 = stops[i]
            o1, c1, a1 = stops[i + 1]
            seg = (tpos >= o0) & (tpos <= o1) if i < len(stops) - 2 else (tpos >= o0)
            span = max(1e-6, o1 - o0)
            u = np_clip((tpos - o0) / span, 0.0, 1.0)
            for ch in range(3):
                out[:, :, ch] = np_where(seg, c0[ch] + (c1[ch] - c0[ch]) * u, out[:, :, ch])
            out[:, :, 3] = np_where(seg, (a0 + (a1 - a0) * u) * 255, out[:, :, 3])
        if len(stops) == 1:
            o0, c0, a0 = stops[0]
            out[:, :, 0], out[:, :, 1], out[:, :, 2] = c0
            out[:, :, 3] = a0 * 255
        return Image.fromarray(out.astype("uint8"), "RGBA").resize(size, Image.BILINEAR)


# лёгкие numpy-хелперы без импорта на уровне модуля (numpy есть в venv)
import numpy as _np


def np_mgrid(h, w):
    g = _np.mgrid[0:h, 0:w]
    return g[0].astype("float32"), g[1].astype("float32")


def np_sqrt(a):
    return _np.sqrt(a)


def np_clip(a, lo, hi):
    return _np.clip(a, lo, hi)


def np_zeros(shape):
    return _np.zeros(shape, "float32")


def np_where(cond, a, b):
    return _np.where(cond, a, b)


class Renderer:
    def __init__(self, svg_text: str, params: dict | None = None, scale: float = 1.0):
        if params:
            svg_text = re.sub(
                r"\{\{(\w+)\}\}", lambda m: str(params.get(m.group(1), "0")), svg_text
            )
        self.root = ET.fromstring(svg_text)
        self.grads: dict = {}
        self._collect_grads(self.root)
        w = float(self.root.get("width", 100))
        h = float(self.root.get("height", 100))
        self.w, self.h = int(w * scale), int(h * scale)
        vb = self.root.get("viewBox")
        if vb:
            self.vb = [float(v) for v in vb.split()]
        else:
            self.vb = [0, 0, w, h]
        self.scale = scale * (w / self.vb[2] if self.vb[2] else 1)
        self.img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.img)

    def _collect_grads(self, el):
        for ch in el:
            tag = _strip_ns(ch.tag)
            if tag in ("linearGradient", "radialGradient"):
                self.grads[ch.get("id")] = Gradient(ch, self.grads)
            else:
                self._collect_grads(ch)

    def render(self) -> Image.Image:
        base = (self.scale, 0, 0, self.scale, -self.vb[0] * self.scale, -self.vb[1] * self.scale)
        self._walk(self.root, base, 1.0)
        return self.img

    _INHERIT = ("fill", "stroke", "stroke-width", "stroke-opacity", "fill-opacity",
                "stroke-linecap", "font-family", "font-weight", "font-size", "text-anchor")

    def _walk(self, el, mat, opacity, inherit=None):
        inherit = dict(inherit or {})
        for k in self._INHERIT:
            if el.get(k) is not None:
                inherit[k] = el.get(k)
        for ch in el:
            tag = _strip_ns(ch.tag)
            if tag == "defs":
                continue
            attrs = dict(ch.attrib)
            for k in self._INHERIT:
                if attrs.get(k) is None and k in inherit:
                    attrs[k] = inherit[k]
            m = _mat_mul(mat, _parse_transform(attrs.get("transform", "")))
            op = opacity * float(attrs.get("opacity", 1))
            if tag == "g":
                self._walk(ch, m, op, attrs)
            elif tag in ("path", "rect", "circle", "ellipse", "line", "polygon", "polyline"):
                self._shape(tag, ch if len(attrs) == len(ch.attrib) else _Attrs(ch, attrs), m, op)
            elif tag == "text":
                self._text(ch if len(attrs) == len(ch.attrib) else _Attrs(ch, attrs), m, op)

    def _polys(self, tag, el):
        if tag == "path":
            return _parse_path(el.get("d", ""))
        if tag == "rect":
            x, y = float(el.get("x", 0)), float(el.get("y", 0))
            w, h = float(el.get("width", 0)), float(el.get("height", 0))
            rx = el.get("rx")
            ry = el.get("ry")
            rx = float(rx) if rx else (float(ry) if ry else 0)
            ry = float(ry) if ry else rx
            if rx > 0:
                pts = [(x + rx, y)]
                corners = [
                    ((x + w - rx, y + ry), 270, 360),
                    ((x + w - rx, y + h - ry), 0, 90),
                    ((x + rx, y + h - ry), 90, 180),
                    ((x + rx, y + ry), 180, 270),
                ]
                for (ccx, ccy), a0, a1 in corners:
                    for k in range(0, 9):
                        a = math.radians(a0 + (a1 - a0) * k / 8)
                        pts.append((ccx + rx * math.cos(a), ccy + ry * math.sin(a)))
                pts.append((x + rx, y))
                return [pts]
            return [[(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)]]
        if tag == "circle":
            cx, cy, r = float(el.get("cx", 0)), float(el.get("cy", 0)), float(el.get("r", 0))
            return [_circle_pts(cx, cy, r, r)]
        if tag == "ellipse":
            cx, cy = float(el.get("cx", 0)), float(el.get("cy", 0))
            rx, ry = float(el.get("rx", 0)), float(el.get("ry", 0))
            return [_circle_pts(cx, cy, rx, ry)]
        if tag == "line":
            return [[(float(el.get("x1", 0)), float(el.get("y1", 0)),),
                    (float(el.get("x2", 0)), float(el.get("y2", 0)))]]
        if tag in ("polygon", "polyline"):
            vals = [float(v) for v in re.split(r"[,\s]+", el.get("points", "").strip()) if v]
            pts = list(zip(vals[0::2], vals[1::2]))
            if tag == "polygon":
                pts.append(pts[0])
            return [pts]
        return []

    def _shape(self, tag, el, mat, opacity):
        polys = self._polys(tag, el)
        if not polys:
            return
        tpolys = []
        for sub in polys:
            tpolys.append([(mat[0] * x + mat[2] * y + mat[4], mat[1] * x + mat[3] * y + mat[5]) for x, y in sub])
        fill = el.get("fill", None if tag in ("line", "polyline") else "#000")
        stroke = el.get("stroke")
        sw = float(el.get("stroke-width", 1)) * math.sqrt(abs(mat[0] * mat[3] - mat[1] * mat[2]))
        fop = float(el.get("fill-opacity", 1)) * opacity
        sop = float(el.get("stroke-opacity", 1)) * opacity
        if fill and fill != "none":
            xs = [p[0] for sub in tpolys for p in sub]
            ys = [p[1] for sub in tpolys for p in sub]
            bbox = (min(xs), min(ys), max(xs), max(ys))
            if fill.startswith("url(#"):
                gid = fill[5:-1]
                g = self.grads.get(gid)
                if g:
                    x0, y0 = int(math.floor(bbox[0])), int(math.floor(bbox[1]))
                    x1, y1 = int(math.ceil(bbox[2])) + 1, int(math.ceil(bbox[3])) + 1
                    w, h = max(1, x1 - x0), max(1, y1 - y0)
                    grad = g.image((x0, y0, x1, y1), (w, h))
                    mask = Image.new("L", (w, h), 0)
                    md = ImageDraw.Draw(mask)
                    for sub in tpolys:
                        md.polygon([(p[0] - x0, p[1] - y0) for p in sub], fill=int(255 * fop))
                    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                    layer.paste(grad, (0, 0), mask)
                    self.img.alpha_composite(layer, (x0, y0))
            else:
                col = _parse_color(fill, (0, 0, 0))
                a = col[3] if len(col) == 4 else 255
                col = (col[0], col[1], col[2], int(a * fop))
                layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
                ld = ImageDraw.Draw(layer)
                for sub in tpolys:
                    ld.polygon(sub, fill=col)
                self.img.alpha_composite(layer)
        if stroke and stroke != "none":
            xs = [p[0] for sub in tpolys for p in sub]
            ys = [p[1] for sub in tpolys for p in sub]
            pad = int(sw) + 2
            x0, y0 = int(min(xs)) - pad, int(min(ys)) - pad
            x1, y1 = int(max(xs)) + pad, int(max(ys)) + pad
            x0, y0 = max(0, x0), max(0, y0)
            x1, y1 = min(self.img.width, x1), min(self.img.height, y1)
            w, h = max(1, x1 - x0), max(1, y1 - y0)
            mask = Image.new("L", (w, h), 0)
            md = ImageDraw.Draw(mask)
            for sub in tpolys:
                if len(sub) > 1:
                    md.line([(p[0] - x0, p[1] - y0) for p in sub], fill=int(255 * sop),
                            width=max(1, int(round(sw))), joint="curve")
            if stroke.startswith("url(#"):
                g = self.grads.get(stroke[5:-1])
                if g:
                    grad = g.image((x0, y0, x1, y1), (w, h))
                    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                    layer.paste(grad, (0, 0), mask)
                    self.img.alpha_composite(layer, (x0, y0))
            else:
                col = _parse_color(stroke, (0, 0, 0))
                a = col[3] if len(col) == 4 else 255
                col = (col[0], col[1], col[2], int(a * sop))
                layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                ld = ImageDraw.Draw(layer)
                for sub in tpolys:
                    if len(sub) > 1:
                        ld.line([(p[0] - x0, p[1] - y0) for p in sub], fill=col,
                                width=max(1, int(round(sw))), joint="curve")
                self.img.alpha_composite(layer, (x0, y0))

    def _text(self, el, mat, opacity):
        txt = "".join(el.itertext())
        size = float(el.get("font-size", 16))
        weight = el.get("font-weight", "800")
        fnt = font(weight, max(6, int(round(size * math.sqrt(abs(mat[0] * mat[3] - mat[1] * mat[2]))))))
        anchor = el.get("text-anchor", "start")
        col = _parse_color(el.get("fill", "#000"), (0, 0, 0))
        a = col[3] if len(col) == 4 else 255
        col = (col[0], col[1], col[2], int(a * opacity))
        bbox = self.draw.textbbox((0, 0), txt, font=fnt)
        tw = bbox[2] - bbox[0]
        x, y = float(el.get("x", 0)), float(el.get("y", 0))
        if anchor == "middle":
            x -= tw / 2
        elif anchor == "end":
            x -= tw
        y -= bbox[3] - fnt.size * 0.08  # базовая линия ≈ низ глифа
        px = mat[0] * x + mat[2] * y + mat[4]
        py = mat[1] * x + mat[3] * y + mat[5]
        fill_raw = el.get("fill", "#000")
        if isinstance(fill_raw, str) and fill_raw.startswith("url(#"):
            g = self.grads.get(fill_raw[5:-1])
            if g:
                bx0, by0 = int(px) - 4, int(py) - 4
                bx1, by1 = int(px + tw) + 4, int(py + fnt.size) + 4
                bw, bh = max(1, bx1 - bx0), max(1, by1 - by0)
                mask = Image.new("L", (bw, bh), 0)
                ImageDraw.Draw(mask).text((px - bx0, py - by0), txt, font=fnt, fill=int(255 * opacity))
                grad = g.image((bx0, by0, bx1, by1), (bw, bh))
                layer = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
                layer.paste(grad, (0, 0), mask)
                self.img.alpha_composite(layer, (bx0, by0))
                return
        self.draw.text((px, py), txt, font=fnt, fill=col)


def _circle_pts(cx, cy, rx, ry, n=48):
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n + 1)]


def render_svg(svg_text: str, params: dict | None = None, scale: float = 1.0) -> Image.Image:
    return Renderer(svg_text, params, scale).render()


def render_file(path: str, params: dict | None = None, scale: float = 1.0) -> Image.Image:
    with open(path, encoding="utf-8") as f:
        return render_svg(f.read(), params, scale)
