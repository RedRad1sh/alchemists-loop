#!/usr/bin/env python3
"""Кейинг AI-спрайтов: сплошной тёмный фон -> прозрачность, трим, даунскейл.
Usage: key_sprites.py <src.png|dir> <dest_dir> [max_side=256]"""
import os, sys
import numpy as np
from PIL import Image

def key_one(src, dest, max_side=256, tol=14.0, pad=2):
    im = Image.open(src).convert('RGB')
    a = np.asarray(im).astype(np.float32)
    h, w, _ = a.shape
    # цвет фона = медиана углов 8x8
    corners = np.concatenate([a[:8,:8].reshape(-1,3), a[:8,-8:].reshape(-1,3),
                              a[-8:,:8].reshape(-1,3), a[-8:,-8:].reshape(-1,3)])
    bg = np.median(corners, axis=0)
    dist = np.sqrt(((a - bg) ** 2).sum(axis=2))
    alpha = np.ones((h, w), dtype=np.float32)
    alpha[dist < tol] = 0.0
    # мягкая кромка 1px
    edge = (dist >= tol) & (dist < tol + 14)
    alpha[edge] = (dist[edge] - tol) / 14.0
    rgba = np.dstack([a, alpha * 255]).astype(np.uint8)
    out = Image.fromarray(rgba, 'RGBA')
    bbox = out.getbbox()
    if bbox is None:
        print(f"EMPTY: {src}"); return None
    l, t, r, b = bbox
    out = out.crop((max(0,l-pad), max(0,t-pad), min(w,r+pad), min(h,b+pad)))
    ow, oh = out.size
    sc = min(1.0, max_side / max(ow, oh))
    if sc < 1.0:
        out = out.resize((max(1,int(ow*sc)), max(1,int(oh*sc))), Image.LANCZOS)
    out.save(dest)
    cov = 100.0 * (np.asarray(out)[:,:,3] > 8).mean()
    print(f"{os.path.basename(src)}: {w}x{h} -> {out.size[0]}x{out.size[1]} alpha_cov={cov:.1f}%")
    return dest

if __name__ == '__main__':
    src, dest = sys.argv[1], sys.argv[2]
    max_side = int(sys.argv[3]) if len(sys.argv) > 3 else 256
    os.makedirs(dest, exist_ok=True)
    files = [os.path.join(src, f) for f in sorted(os.listdir(src))] if os.path.isdir(src) else [src]
    for f in files:
        if f.endswith('.png') and 'sheet' not in f and '/qa_' not in f.replace('\\','/') and not os.path.basename(f).startswith('qa_'):
            key_one(f, os.path.join(dest, os.path.basename(f)), max_side)
