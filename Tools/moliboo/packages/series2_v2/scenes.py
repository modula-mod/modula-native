#!/usr/bin/env python3
"""Scene pack 2: one glossy 2D backdrop per family (1280x960 PNG, opaque). Usage: scenes.py <out_dir>
Design units: 1000 across; visible height 750 (y 0..750). Figures stand on the ground line at y ~ 600."""
import sys, json, math
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
from core import *

def H(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def grad(top, bot):
    t = np.linspace(0, 1, S)[:, None, None]
    return (np.array(top, np.float32) * (1 - t) + np.array(bot, np.float32) * t) * np.ones((S, S, 3), np.float32)
def ground(y, amp=18, ph=0):
    return m_poly([(-50, 1050), (-50, y)] + [(x, y + amp * math.sin(x / 140 + ph)) for x in range(0, 1001, 20)] + [(1050, y), (1050, 1050)])
def sparkles(f, pts, col=(255, 255, 255), a=0.9):
    for x, y, r in pts: f.flat(m_poly(star_pts(x, y, r, r * 0.38, 4)), col, a)

SCENES = {}
def scene(id, family, name, sky):
    def deco(fn): SCENES[id] = (fn, family, name, sky); return fn
    return deco
rng = np.random.default_rng(7)

@scene("scene2.ocean", "tideborn", "Seaside cove", (H("#8fd8ff"), H("#e8f8ff")))
def _(f):
    f.part(m_ellipse(800, 140, 70, 70), tri(H("#ffe27a")), line=False, gloss=0.4)
    f.part(ground(420, 10), tri(H("#3aa9d8")), line=False, gloss=0.2)
    for k in range(4): f.flat(m_arc(150 + k * 240, 470 + (k % 2) * 30, 80, 200, 340, 9), (255, 255, 255), 0.6)
    f.part(ground(600, 14, 1.0), tri(H("#f6dca0")), line=False, gloss=0.25)
    f.part(soften(m_poly(star_pts(140, 660, 50, 22)), 6), tri(H("#ff8f6a")))
    f.part(m_ellipse(880, 655, 60, 40), tri(H("#ffb7c8")), gloss=0.4)
    for x, y, r in ((300, 330, 16), (330, 280, 10), (620, 360, 13), (700, 300, 8)): f.flat(m_ellipse(x, y, r, r), (255, 255, 255), 0.55)
@scene("scene2.sky", "skyweavers", "Cloud harbour", (H("#9ecbff"), H("#fdf1ff")))
def _(f):
    for i, c in enumerate((H("#ff9fb5"), H("#ffd27a"), H("#9ee6b0"), H("#9ccfff"))):
        f.part(m_arc(500, 700, 470 - i * 40, 180, 360, 38), tri(c), line=False, gloss=0.3)
    for x, y, s in ((170, 200, 1.0), (760, 140, 0.8), (520, 330, 0.7)):
        f.part(soften(union(*[m_ellipse(x + dx * s, y + dy * s, r * s, r * s) for dx, dy, r in ((-70, 10, 55), (0, -20, 75), (75, 10, 55), (0, 25, 60))]), 6), tri((255, 255, 255)), gloss=0.5)
    f.part(soften(union(*[m_ellipse(x, 650, 120, 90) for x in range(0, 1001, 160)]), 10), tri((255, 255, 255)), line=False)
@scene("scene2.volcano", "cinderlings", "Ember peak", (H("#5a2a5a"), H("#ff9a5a")))
def _(f):
    f.part(soften(m_poly([(150, 620), (420, 230), (580, 230), (860, 620)]), 14), tri(H("#6a3a3a")), spec=True)
    f.part(soften(m_poly([(420, 232), (580, 232), (545, 330), (500, 300), (455, 340)]), 6), tri(H("#ff7a2a")), gloss=0.5)
    f.part(soften(union(m_ellipse(500, 160, 90, 60), m_ellipse(430, 120, 60, 45), m_ellipse(580, 110, 70, 50)), 6), tri(H("#8a7a8a")), line=False)
    f.part(ground(600, 12), tri(H("#3a2430")), line=False)
    for _ in range(18): x, y = rng.uniform(40, 960), rng.uniform(80, 560); f.flat(m_ellipse(x, y, 6, 6), H("#ffcf6a"), 0.85)
@scene("scene2.garden", "mosslight-grove", "Petal meadow", (H("#bfeaff"), H("#f4ffe6")))
def _(f):
    f.part(m_ellipse(160, 140, 60, 60), tri(H("#ffe27a")), line=False)
    f.part(ground(470, 40, 0.5), tri(H("#9ad98a")), line=False, gloss=0.3)
    f.part(ground(590, 16, 2.0), tri(H("#6cc46a")), line=False, gloss=0.3)
    for x, c in ((90, H("#ff8fb1")), (260, H("#ffd25a")), (740, H("#c79bff")), (900, H("#ff8fb1"))):
        f.part(m_line([(x, 640), (x, 560)], 12), tri(H("#4f9a4a")), line=False)
        for k in range(5): a = k * 1.2566; f.part(m_ellipse(x + 26 * math.cos(a), 545 + 26 * math.sin(a), 22, 22), tri(c), gloss=0.3)
        f.part(m_ellipse(x, 545, 14, 14), tri(H("#fff0a0")), line=False)
    f.part(inter(m_ellipse(600, 600, 70, 55), below(-1)), tri(H("#ef5a5a")), spec=True)
    for x, y in ((575, 580), (620, 570), (600, 600)): f.flat(m_ellipse(x, y, 10, 10), (255, 255, 255))
@scene("scene2.ice", "aurora-vale", "Aurora snowfield", (H("#bfe4ff"), H("#f4fbff")))
def _(f):
    for x, h, c in ((200, 330, H("#d7efff")), (520, 240, H("#c3e5ff")), (820, 300, H("#d7efff"))):
        f.part(soften(m_poly([(x - 260, 620), (x, h), (x + 260, 620)]), 10), tri(c), spec=True)
        f.flat(soften(m_poly([(x - 70, h + 90), (x, h), (x + 70, h + 90), (x + 30, h + 75), (x, h + 100), (x - 30, h + 75)]), 4), (255, 255, 255))
    f.part(ground(600, 10), tri((250, 253, 255)), line=False, gloss=0.2)
    f.part(inter(m_ellipse(820, 620, 110, 90), sub(m_poly([(0, 0), (1000, 0), (1000, 620), (0, 620)]), m_poly([(0, 0), (0, 0), (1, 1)]))), tri((245, 250, 255)), spec=True)
    for _ in range(28): x, y = rng.uniform(20, 980), rng.uniform(20, 560); f.flat(m_ellipse(x, y, 5, 5), (255, 255, 255), 0.9)
@scene("scene2.clockwork", "clocklings", "Clock tower loft", (H("#f6e2bf"), H("#d9b98a")))
def _(f):
    for x, y, r, c in ((180, 220, 150, H("#c99a4a")), (420, 140, 90, H("#b5884a")), (820, 260, 190, H("#d4a85a")), (640, 470, 80, H("#a87a3a"))):
        teeth = union(*[m_ellipse(x + r * math.cos(a), y + r * math.sin(a), r * 0.16, r * 0.16) for a in np.linspace(0, 6.28, 13)[:-1]])
        f.part(sub(union(m_ellipse(x, y, r, r), teeth), m_ellipse(x, y, r * 0.35, r * 0.35)), tri(c), spec=True)
    f.part(ground(610, 0), tri(H("#8a5a3a")), line=False, gloss=0.2)
    for x in range(0, 1001, 100): f.flat(m_line([(x, 612), (x, 760)], 4), H("#6a4028"), 0.6)
@scene("scene2.sweets", "sugarvale", "Candy hills", (H("#ffd6ea"), H("#fff6e6")))
def _(f):
    f.part(ground(470, 40, 1.2), tri(H("#ffb7d5")), line=False, gloss=0.35)
    f.part(ground(590, 18, 0.2), tri(H("#fff0f6")), line=False, gloss=0.3)
    for x, c in ((150, H("#ff6f9a")), (850, H("#7fd6ff"))):
        f.part(m_line([(x, 620), (x, 430)], 14), tri((255, 255, 255)), line=False)
        f.part(m_ellipse(x, 400, 70, 70), tri(c), spec=True)
        for k in range(3): f.flat(m_arc(x, 400, 20 + k * 18, 0, 300, 7), (255, 255, 255), 0.8)
    for x, c in ((380, H("#7fe0c0")), (470, H("#ffd25a")), (620, H("#c79bff"))):
        f.part(inter(m_ellipse(x, 620, 40, 46), below(-1)), tri(c), spec=True)
@scene("scene2.ink", "inkbound-atelier", "Ink atelier", (H("#fbf4e6"), H("#efe2c8")))
def _(f):
    f.part(m_super(500, 260, 220, 160, 6), tri(H("#ffffff")), spec=False)
    for x, y, r, c in ((440, 230, 50, H("#3b4a8f")), (540, 290, 38, H("#ef5a5a")), (560, 200, 26, H("#ffd25a"))): f.flat(soften(union(m_ellipse(x, y, r, r), m_ellipse(x + r, y + 10, r * 0.4, r * 0.4)), 4), c, 0.9)
    f.part(m_line([(400, 420), (500, 620)], 18), tri(H("#9a6a3a")), line=False); f.part(m_line([(600, 420), (500, 620)], 18), tri(H("#9a6a3a")), line=False)
    f.part(ground(620, 0), tri(H("#c8a87a")), line=False)
    for x, y in ((120, 660), (880, 650), (170, 140), (860, 120)): f.flat(soften(union(m_ellipse(x, y, 34, 30), m_ellipse(x + 30, y - 20, 12, 12), m_ellipse(x - 28, y + 18, 9, 9)), 3), H("#2a2a3a"), 0.85)
    f.part(m_line([(760, 560), (900, 420)], 16), tri(H("#3a3a5a")), line=False); f.part(m_ellipse(905, 415, 18, 26, rot=0.8), tri(H("#2a2a3a")), line=False)
@scene("scene2.arcade", "neon-arcade", "Neon arcade", (H("#24134a"), H("#5a2a7a")))
def _(f):
    for k in range(9): f.flat(m_line([(500, 470), (-300 + k * 200, 760)], 4), H("#ff5ad8"), 0.8)
    for k in range(5): y = 480 + k * k * 12; f.flat(m_line([(-10, y), (1010, y)], 4), H("#5ad8ff"), 0.8)
    f.part(m_ellipse(500, 300, 150, 150), tri(H("#ff8a5a")), line=False, gloss=0.3)
    for y in (260, 300, 340, 380): f.flat(m_line([(330, y), (670, y)], 10), H("#24134a"))
    for x, y in ((120, 120), (860, 90), (780, 220), (200, 260), (930, 330)): f.flat(m_super(x, y, 10, 10, 8), (255, 255, 255))
    f.part(m_super(160, 600, 70, 40, 4), tri(H("#3a3a5a"))); f.part(m_line([(160, 590), (150, 520)], 14), tri(H("#cfcfe0")), line=False); f.part(m_ellipse(150, 510, 24, 24), tri(H("#ef5a5a")), spec=True)
@scene("scene2.lantern", "lantern-parade", "Lantern night", (H("#13234a"), H("#3a3a7a")))
def _(f):
    f.part(m_ellipse(820, 140, 70, 70), tri(H("#fff3c0")), line=False, gloss=0.3)
    f.flat(m_arc(500, -250, 650, 40, 140, 5), H("#c9b48a"), 0.9)
    for k in range(7):
        a = math.radians(48 + k * 14); x, y = 500 + 650 * math.cos(a), -250 + 650 * math.sin(a)
        c = (H("#ff7a5a"), H("#ffc25a"), H("#ff9ac0"))[k % 3]
        f.flat(m_ellipse(x, y + 60, 60, 66), H("#ffe08a"), 0.25)
        f.part(m_super(x, y + 60, 34, 44, 2.2), tri(c), spec=True)
    f.part(ground(610, 16), tri(H("#1d2a4a")), line=False)
    for _ in range(26): x, y = rng.uniform(20, 980), rng.uniform(20, 420); f.flat(m_ellipse(x, y, 3, 3), (255, 255, 255), 0.85)

def render_all(out):
    out.mkdir(parents=True, exist_ok=True)
    meta = []
    for id, (fn, fam, name, sky) in SCENES.items():
        f = Fig(dict(outline=(60, 44, 70)))
        fn(f)
        base = grad(*sky)
        a = f.img[..., 3:4]
        rgb = base * (1 - a) + f.img[..., :3] * a
        im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").crop((0, 0, S, int(S * 0.75)))
        im.save(out / f"{id}.png", optimize=True)
        meta.append(dict(id=id, slot="background", family=fam, name=name, file=f"{id}.png", width=im.width, height=im.height, groundY=round(600 / 750, 3)))
        print("ok", id, flush=True)
    (out / "scenes.json").write_text(json.dumps({"schemaVersion": "modula.moliboo.scenes.1",
        "status": "draft — not in the local scene catalog, no price, no unlock, no ownership",
        "groundYConvention": "fraction of image height where a standing figure's feet rest", "scenes": meta}, indent=2) + "\n")

if __name__ == "__main__": render_all(Path(sys.argv[1]))
