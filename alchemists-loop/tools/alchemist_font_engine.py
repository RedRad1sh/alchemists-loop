"""THROWAWAY PROBE: stroke-based SVG glyphs -> real TrueType font.

Pipeline: parse SVG path/circle primitives -> flatten curves to polylines ->
expand stroke into filled outlines -> map SVG user units to font units ->
emit a TTF with fontTools.

Key facts this relies on:
  * TrueType fills with the nonzero winding rule, so a glyph may be emitted as
    several overlapping same-direction contours without any boolean unioning.
  * Closed subpaths stroke to an annulus (outer contour + reversed inner one);
    open subpaths stroke to one contour with caps.
"""
import math
import re
import numpy as np

UPM = 1000
BASELINE_SVG = 85.0        # SVG y that becomes y=0 in font units
SCALE = UPM / 100.0        # 100-wide design cell -> 1000 upm
FLATTEN_TOL = 0.02         # SVG units


# --------------------------------------------------------------------------
# SVG path parsing
# --------------------------------------------------------------------------
_NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
_CMD = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])")


def _tokenize(d):
    out = []
    for part in _CMD.split(d):
        part = part.strip()
        if not part:
            continue
        if len(part) == 1 and part.isalpha():
            out.append(part)
        else:
            out.extend(float(x) for x in _NUM.findall(part))
    return out


def parse_path(d):
    """-> list of subpaths: {'segs': [(kind, *args)], 'closed': bool}
    seg kinds: ('L', p0, p1) ('Q', p0, c, p1) ('C', p0, c1, c2, p1)
               ('A', p0, (rx, ry, rot, large, sweep), p1)
    """
    tok = _tokenize(d)
    i = 0
    subs = []
    cur = None
    start = None
    p = (0.0, 0.0)
    prev_ctrl = None
    cmd = None

    def flush():
        nonlocal cur
        if cur is not None and cur["segs"]:
            subs.append(cur)
        cur = None

    def rel(pt, base):
        return (pt[0] + base[0], pt[1] + base[1]) if relmode else pt

    relmode = False
    while i < len(tok):
        if isinstance(tok[i], str):
            cmd = tok[i]
            i += 1
            relmode = cmd.islower()
            if cmd in "Zz":
                if cur is not None:
                    cur["closed"] = True
                    if cur["segs"]:
                        first = cur["segs"][0][1]
                        last = _seg_end(cur["segs"][-1])
                        if abs(last[0] - first[0]) > 1e-9 or abs(last[1] - first[1]) > 1e-9:
                            cur["segs"].append(("L", last, first))
                flush()
                if start is not None:
                    p = start
                prev_ctrl = None
                continue
            if cmd in "Mm":
                x, y = tok[i], tok[i + 1]
                i += 2
                p = (x + p[0], y + p[1]) if relmode else (x, y)
                flush()
                cur = {"segs": [], "closed": False}
                start = p
                prev_ctrl = None
                cmd = "L" if cmd == "M" else "l"   # implicit lineto after moveto
                relmode = cmd.islower()
                continue
        if cmd is None:
            raise ValueError("path data does not start with a command")

        c = cmd.upper()
        if c == "L":
            x, y = tok[i], tok[i + 1]
            i += 2
            q = (x + p[0], y + p[1]) if relmode else (x, y)
            cur["segs"].append(("L", p, q))
            p = q
        elif c == "H":
            x = tok[i]
            i += 1
            q = (x + p[0], p[1]) if relmode else (x, p[1])
            cur["segs"].append(("L", p, q))
            p = q
        elif c == "V":
            y = tok[i]
            i += 1
            q = (p[0], y + p[1]) if relmode else (p[0], y)
            cur["segs"].append(("L", p, q))
            p = q
        elif c == "C":
            v = tok[i:i + 6]
            i += 6
            if relmode:
                v = [v[0] + p[0], v[1] + p[1], v[2] + p[0], v[3] + p[1], v[4] + p[0], v[5] + p[1]]
            c1, c2, q = (v[0], v[1]), (v[2], v[3]), (v[4], v[5])
            cur["segs"].append(("C", p, c1, c2, q))
            prev_ctrl, p = c2, q
        elif c == "S":
            v = tok[i:i + 4]
            i += 4
            if relmode:
                v = [v[0] + p[0], v[1] + p[1], v[2] + p[0], v[3] + p[1]]
            c1 = (2 * p[0] - prev_ctrl[0], 2 * p[1] - prev_ctrl[1]) if prev_ctrl else p
            c2, q = (v[0], v[1]), (v[2], v[3])
            cur["segs"].append(("C", p, c1, c2, q))
            prev_ctrl, p = c2, q
        elif c == "Q":
            v = tok[i:i + 4]
            i += 4
            if relmode:
                v = [v[0] + p[0], v[1] + p[1], v[2] + p[0], v[3] + p[1]]
            cc, q = (v[0], v[1]), (v[2], v[3])
            cur["segs"].append(("Q", p, cc, q))
            prev_ctrl, p = cc, q
        elif c == "T":
            v = tok[i:i + 2]
            i += 2
            if relmode:
                v = [v[0] + p[0], v[1] + p[1]]
            cc = (2 * p[0] - prev_ctrl[0], 2 * p[1] - prev_ctrl[1]) if prev_ctrl else p
            q = (v[0], v[1])
            cur["segs"].append(("Q", p, cc, q))
            prev_ctrl, p = cc, q
        elif c == "A":
            v = tok[i:i + 7]
            i += 7
            rx, ry, rot, laf, sf = v[0], v[1], v[2], int(v[3]), int(v[4])
            q = (v[5], v[6])
            if relmode:
                q = (q[0] + p[0], q[1] + p[1])
            cur["segs"].append(("A", p, (rx, ry, rot, laf, sf), q))
            p = q
            prev_ctrl = None
        else:
            raise ValueError("unsupported command " + c)
        if c != "C" and c != "S":
            prev_ctrl = prev_ctrl if c in "QT" else prev_ctrl
    flush()
    return subs


def _seg_end(seg):
    return seg[-1]


# --------------------------------------------------------------------------
# flattening
# --------------------------------------------------------------------------
def _flatten_cubic(p0, c1, c2, p1, tol, out):
    # adaptive: subdivide until flat enough
    def flat(a, b, c, d):
        ux, uy = 3 * b[0] - 2 * a[0] - d[0], 3 * b[1] - 2 * a[1] - d[1]
        vx, vy = 3 * c[0] - 2 * d[0] - a[0], 3 * c[1] - 2 * d[1] - a[1]
        return max(ux * ux, vx * vx) + max(uy * uy, vy * vy)

    def rec(a, b, c, d, depth):
        if depth > 18 or flat(a, b, c, d) <= 16 * tol * tol:
            out.append(d)
            return
        ab = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        bc = ((b[0] + c[0]) / 2, (b[1] + c[1]) / 2)
        cd = ((c[0] + d[0]) / 2, (c[1] + d[1]) / 2)
        abc = ((ab[0] + bc[0]) / 2, (ab[1] + bc[1]) / 2)
        bcd = ((bc[0] + cd[0]) / 2, (bc[1] + cd[1]) / 2)
        mid = ((abc[0] + bcd[0]) / 2, (abc[1] + bcd[1]) / 2)
        rec(a, ab, abc, mid, depth + 1)
        rec(mid, bcd, cd, d, depth + 1)

    rec(p0, c1, c2, p1, 0)


def _flatten_quad(p0, c, p1, tol, out):
    # raise to cubic
    c1 = (p0[0] + 2.0 / 3.0 * (c[0] - p0[0]), p0[1] + 2.0 / 3.0 * (c[1] - p0[1]))
    c2 = (p1[0] + 2.0 / 3.0 * (c[0] - p1[0]), p1[1] + 2.0 / 3.0 * (c[1] - p1[1]))
    _flatten_cubic(p0, c1, c2, p1, tol, out)


def _flatten_arc(p0, prm, p1, out, n_max=256):
    rx, ry, phi, laf, sf = prm
    if rx == 0 or ry == 0:
        out.append(p1)
        return
    phi = math.radians(phi)
    cs, sn = math.cos(phi), math.sin(phi)
    dx2, dy2 = (p0[0] - p1[0]) / 2.0, (p0[1] - p1[1]) / 2.0
    x1p, y1p = cs * dx2 + sn * dy2, -sn * dx2 + cs * dy2
    rx, ry = abs(rx), abs(ry)
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    co = math.sqrt(max(0.0, num / den)) if den else 0.0
    if laf == sf:
        co = -co
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cs * cxp - sn * cyp + (p0[0] + p1[0]) / 2.0
    cy = sn * cxp + cs * cyp + (p0[1] + p1[1]) / 2.0

    def ang(ux, uy, vx, vy):
        d = (ux * vx + uy * vy) / (math.hypot(ux, uy) * math.hypot(vx, vy))
        a = math.acos(max(-1.0, min(1.0, d)))
        return -a if ux * vy - uy * vx < 0 else a

    th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if sf == 0 and dth > 0:
        dth -= 2 * math.pi
    elif sf == 1 and dth < 0:
        dth += 2 * math.pi
    n = max(2, min(n_max, int(abs(dth) / (math.pi / 32)) + 1))
    for k in range(1, n + 1):
        t = th1 + dth * k / n
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        out.append((cs * ex - sn * ey + cx, sn * ex + cs * ey + cy))


def flatten_subpath(sub, tol=FLATTEN_TOL):
    pts = []
    for seg in sub["segs"]:
        if not pts:
            pts.append(seg[1])
        if seg[0] == "L":
            pts.append(seg[2])
        elif seg[0] == "C":
            _flatten_cubic(seg[1], seg[2], seg[3], seg[4], tol, pts)
        elif seg[0] == "Q":
            _flatten_quad(seg[1], seg[2], seg[3], tol, pts)
        elif seg[0] == "A":
            _flatten_arc(seg[1], seg[2], seg[3], pts)
    return dedupe(pts), sub["closed"]


def dedupe(pts, eps=1e-7):
    out = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > eps or abs(p[1] - out[-1][1]) > eps:
            out.append((float(p[0]), float(p[1])))
    while len(out) > 1 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
    return out


def circle_pts(cx, cy, r, rx=None, ry=None):
    rx = r if rx is None else rx
    ry = r if ry is None else ry
    n = max(12, int(2 * math.pi * max(rx, ry) / 0.25))
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n))
            for k in range(n)]


def rect_pts(x, y, w, h, rx=0.0, ry=0.0):
    if rx <= 0 and ry <= 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    rx = min(rx, w / 2)
    ry = min(ry, h / 2)
    pts = []
    for (cx, cy, a0) in ((x + w - rx, y + ry, -math.pi / 2), (x + w - rx, y + h - ry, 0.0),
                         (x + rx, y + h - ry, math.pi / 2), (x + rx, y + ry, math.pi)):
        for k in range(9):
            a = a0 + (math.pi / 2) * k / 8
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


# --------------------------------------------------------------------------
# stroking
# --------------------------------------------------------------------------
def signed_area(pts):
    a = 0.0
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return a / 2.0


def _norm(v):
    l = math.hypot(v[0], v[1])
    return (v[0] / l, v[1] / l) if l > 1e-12 else (0.0, 0.0)


def _arc_pts(c, a0, a1, r, ccw):
    """Sample an arc between two angles, taking the short way round."""
    d = a1 - a0
    if ccw:
        while d < 0:
            d += 2 * math.pi
    else:
        while d > 0:
            d -= 2 * math.pi
    n = max(2, int(abs(d) / (math.pi / 12)) + 1)
    return [(c[0] + r * math.cos(a0 + d * k / n), c[1] + r * math.sin(a0 + d * k / n))
            for k in range(1, n + 1)]


def offset_side(pts, dist, closed):
    """Offset a polyline to one side, inserting round joins at the vertices.
    `dist` > 0 offsets to the left of the direction of travel."""
    n = len(pts)
    if n < 2:
        return []
    segs = []
    idx = list(range(n - 1)) + ([n - 1] if closed else [])
    for i in idx:
        a, b = pts[i], pts[(i + 1) % n]
        if closed and i == n - 1:
            b = pts[0]
        segs.append(_norm((b[0] - a[0], b[1] - a[1])))
    out = []
    for i in range(n):
        if not closed and i == 0:
            t = segs[0]
        elif not closed and i == n - 1:
            t = segs[-1]
        else:
            t0 = segs[i - 1] if i > 0 else segs[-1]
            t1 = segs[i] if i < len(segs) else segs[0]
            t = _norm((t0[0] + t1[0], t0[1] + t1[1]))
            if t == (0.0, 0.0):
                t = t1
        nrm = (-t[1], t[0])
        p = pts[i]
        off = (p[0] + nrm[0] * dist, p[1] + nrm[1] * dist)
        # round join against the previous offset point
        if out:
            prev = out[-1]
            r = dist
            a0 = math.atan2(prev[1] - p[1], prev[0] - p[0])
            a1 = math.atan2(off[1] - p[1], off[0] - p[0])
            if abs(a1 - a0) > 1e-6:
                # take the short way
                d = a1 - a0
                while d > math.pi:
                    d -= 2 * math.pi
                while d < -math.pi:
                    d += 2 * math.pi
                m = max(2, int(abs(d) / (math.pi / 12)) + 1)
                for k in range(1, m):
                    a = a0 + d * k / m
                    out.append((p[0] + abs(r) * math.cos(a), p[1] + abs(r) * math.sin(a)))
        out.append(off)
    return out


def stroke_contours(pts, closed, width):
    """Expand a stroked polyline into filled contours (list of point lists)."""
    hw = width / 2.0
    if hw <= 0:
        return []
    if closed:
        outer = offset_side(pts, -hw, True)
        inner = offset_side(pts, +hw, True)
        if len(outer) < 3 or len(inner) < 3:
            return []
        if signed_area(outer) < 0:
            outer = outer[::-1]
        if signed_area(inner) > 0:
            inner = inner[::-1]
        return [outer, inner[::-1][::-1]] if False else [outer, inner]
    left = offset_side(pts, -hw, False)
    right = offset_side(pts, +hw, False)
    if len(left) < 2 or len(right) < 2:
        return []
    # round caps: continue the left side around the end point, then back along right
    p_end = pts[-1]
    p_start = pts[0]
    contour = list(left)
    # cap at the end
    a0 = math.atan2(left[-1][1] - p_end[1], left[-1][0] - p_end[0])
    a1 = math.atan2(right[-1][1] - p_end[1], right[-1][0] - p_end[0])
    contour += _arc_pts(p_end, a0, a1, hw, ccw=True)
    contour += list(reversed(right))
    # cap at the start
    a0 = math.atan2(right[0][1] - p_start[1], right[0][0] - p_start[0])
    a1 = math.atan2(left[0][1] - p_start[1], left[0][0] - p_start[0])
    contour += _arc_pts(p_start, a0, a1, hw, ccw=True)
    contour = dedupe(contour)
    if len(contour) < 3:
        return []
    if signed_area(contour) < 0:
        contour = contour[::-1]
    return [contour]


# --------------------------------------------------------------------------
# coordinates
# --------------------------------------------------------------------------
def to_font(pts):
    return [(x * SCALE, (BASELINE_SVG - y) * SCALE) for (x, y) in pts]


def simplify(pts, tol):
    """Douglas-Peucker on a closed polygon (keeps >= 3 points)."""
    if len(pts) < 4 or tol <= 0:
        return pts

    def rdp(points):
        if len(points) < 3:
            return points
        (x0, y0), (x1, y1) = points[0], points[-1]
        dx, dy = x1 - x0, y1 - y0
        norm = math.hypot(dx, dy)
        best, bi = -1.0, 0
        for i in range(1, len(points) - 1):
            px, py = points[i]
            d = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / norm if norm > 1e-12 else math.hypot(px - x0, py - y0)
            if d > best:
                best, bi = d, i
        if best > tol:
            a = rdp(points[:bi + 1])
            b = rdp(points[bi:])
            return a[:-1] + b
        return [points[0], points[-1]]

    # rotate so the split point is not on a long straight run
    k = max(range(len(pts)), key=lambda i: math.hypot(pts[i][0] - pts[0][0], pts[i][1] - pts[0][1]))
    rot = pts[k:] + pts[:k]
    res = rdp(rot + [rot[0]])
    return res[:-1]
