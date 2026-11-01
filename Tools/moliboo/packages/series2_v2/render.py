#!/usr/bin/env python3
"""Render Series 2 (#116-215) v2 figures. Usage: render.py <sources_dir> <old_cutouts_dir> [nums...]"""
import sys, json
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
from core import *
from feats_c import FEAT
from specs import SPECS

def hexc(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def kmeans(px, k=5, it=12):
    rng = np.random.default_rng(1)
    c = px[rng.choice(len(px), k, replace=False)]
    for _ in range(it):
        lab = np.argmin(((px[:, None] - c[None]) ** 2).sum(-1), 1)
        c = np.array([px[lab == i].mean(0) if (lab == i).any() else c[i] for i in range(k)])
    return c, np.bincount(lab, minlength=k)

def palette(cutout, ov):
    im = np.asarray(Image.open(cutout).convert("RGBA"))
    px = im[:, :, :3][im[:, :, 3] > 200].astype(np.float32)
    px = px[::max(1, len(px) // 6000)]
    lumv = px.mean(1); px = px[(lumv > 40) & (lumv < 245)]
    cs, n = kmeans(px)
    satv = cs.max(1) - cs.min(1)
    order = np.argsort(-n)
    mid = tuple(cs[order[0]])
    vivid = [i for i in np.argsort(-satv) if n[i] > 0.06 * n.sum()]
    acc = tuple(cs[vivid[0]]) if vivid else mid
    acc2 = tuple(cs[vivid[1]]) if len(vivid) > 1 else lighten(acc, 0.3)
    mid, acc, acc2 = sat(clamp(mid), 1.2), sat(clamp(acc), 1.3), sat(clamp(acc2), 1.25)
    if "mid" in ov: mid = hexc(ov["mid"])
    if "acc" in ov: acc = hexc(ov["acc"])
    if "acc2" in ov: acc2 = hexc(ov["acc2"])
    dark = darken(mid, 0.3)
    return dict(light=lighten(mid, 0.6), mid=mid, dark=dark, acc=acc, acc2=acc2,
                outline=darken(mix(mid, acc, 0.3), 0.62), ink=(54, 36, 48) if lum(mid) > 70 else (250, 240, 250),
                blush=mix((255, 130, 150), acc, 0.25))

def render(num, pal):
    body, feats, eyes, mth, _ = SPECS[num]
    rx, ry = 250, 240
    cx, cy = 500, 560
    f = Fig(pal)
    c = dict(mid=pal["mid"], dark=pal["dark"], acc=pal["acc"], acc2=pal["acc2"], body=body,
             er=rx * 0.17, espread=rx * 0.4, eyey=ry * 0.02)
    b = (cx, cy, rx, ry)
    late = {"mask", "monocle", "visor"}
    for x in feats:
        if FEAT[x][1] == "back": FEAT[x][0](f, b, c)
    f.part(body_mask(body, cx, cy, rx, ry), (pal["light"], pal["mid"], pal["dark"]), spec=True)
    for x in feats:
        if FEAT[x][1] == "front" and x not in late: FEAT[x][0](f, b, c)
    for sd in (-1, 1):
        f.flat(m_ellipse(cx + sd * rx * 0.62, cy + ry * 0.24, rx * 0.14, rx * 0.085), pal["blush"], 0.75)
        f.flat(m_ellipse(cx + sd * rx * 0.58, cy + ry * 0.21, rx * 0.04, rx * 0.025), (255, 255, 255), 0.7)
    glow = lum(pal["mid"]) < 70
    for sd in (-1, 1):
        st = "bead" if (eyes == "wink" and sd == 1) else eyes
        eye(f, cx + sd * c["espread"], cy + c["eyey"], c["er"], st, glow, pal["acc"], pal["ink"])
    mouth(f, cx, cy + ry * 0.3, rx * 0.2, mth, pal["ink"])
    for x in feats:
        if x in late: FEAT[x][0](f, b, c)
    return finish(f)

if __name__ == "__main__":
    src, old = Path(sys.argv[1]), Path(sys.argv[2])
    nums = [int(a) for a in sys.argv[3:]] or sorted(SPECS)
    for n in nums:
        folder = next(src.glob(f"{n:03d}_*"))
        pal = palette(old / f"{folder.name}.png", SPECS[n][4])
        im = render(n, pal)
        check(im)
        im.save(folder / "portrait.png", optimize=True)
        print("ok", folder.name, flush=True)
