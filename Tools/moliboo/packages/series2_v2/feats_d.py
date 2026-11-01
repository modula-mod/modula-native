"""Round 2: stubby limbs + redrawn signature features (override feats_a-c)."""
import math
from core import *
from feats_c import FEAT, feat, T

FLOAT_BODIES = {"ghost", "flat", "star"}
FLOAT_FEATS = {"jelly", "tentacles", "manta", "wisp", "fishtail", "storm"}

def limbs(f, b, c, num, feats):
    """Poster-style stubby arms + feet. Drawn BEFORE the body so they tuck behind its edge."""
    cx, cy, rx, ry = b
    body = c["body"]
    floats = body in FLOAT_BODIES or any(x in FLOAT_FEATS for x in feats)
    col = tri(c["mid"])
    wave_side = (1 if num % 2 else -1) if num % 3 == 0 else 0
    sx = {"tall": 0.78, "bell": 0.92, "drop": 0.9, "pear": 0.95, "cube": 0.95, "wide": 1.08, "flat": 1.2}.get(body, 0.94)
    for sd in (-1, 1):
        if sd == wave_side:   # raised waving arm
            f.part(m_ellipse(cx + sd * rx * (sx + 0.1), cy - ry * 0.05, rx * 0.13, ry * 0.21, rot=sd * 0.55), col, gloss=0.3)
        else:
            f.part(m_ellipse(cx + sd * rx * (sx + 0.02), cy + ry * 0.38, rx * 0.13, ry * 0.2, rot=sd * -0.7), col, gloss=0.3)
    if not floats:
        fy = {"ghost": 0.95, "flat": 0.82, "bell": 0.95}.get(body, 0.92)
        for sd in (-1, 1):
            f.part(m_ellipse(cx + sd * rx * 0.36, cy + ry * (fy + 0.06), rx * 0.2, ry * 0.12), tri(darken(c["mid"], 0.06)), gloss=0.35)
    return floats

@feat("wave", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    # A curling wave: a thick crescent rising from the back of the head and rolling forward, with a foam lip.
    ox, oy, R = cx + rx * 0.1, t - ry * 0.12, rx * 0.78
    outer = m_ellipse(ox, oy, R, R * 0.92)
    inner = m_ellipse(ox + R * 0.32, oy + R * 0.22, R * 0.52, R * 0.5)
    curl = sub(outer, inner)
    curl = sub(curl, m_poly([(ox + R * 0.05, oy + R * 0.2), (ox + R * 1.3, oy + R * 0.2), (ox + R * 1.3, oy + R * 1.4), (ox + R * 0.05, oy + R * 1.4)]))
    curl = soften(curl, 8)
    f.part(curl, tri(c["acc"]), spec=True)
    for i, (dx, dy, r) in enumerate(((0.55, -0.55, 0.13), (0.82, -0.25, 0.11), (0.92, 0.08, 0.09), (0.25, -0.82, 0.1))):
        f.part(m_ellipse(ox + R * dx, oy + R * dy, R * r, R * r), tri((250, 255, 255)), line=False, gloss=0.2)
    for k in range(2):
        f.flat(m_arc(ox, oy, R * (0.62 + k * 0.16), 200, 290, 10), lighten(c["acc"], 0.7), 0.7)

@feat("wisp", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    # Whispel: swirling wind ribbons wrapped around a curly tuft.
    col = lighten(c["mid"], 0.25)
    f.part(soften(union(m_line([(cx + rx * 0.55, cy + ry * 0.6), (cx + rx * 1.1, cy + ry * 0.85), (cx + rx * 1.35, cy + ry * 0.45), (cx + rx * 1.12, cy + ry * 0.12), (cx + rx * 0.9, cy + ry * 0.3)], rx * 0.22)), 10), tri(col))
    f.part(soften(sub(m_ellipse(cx - rx * 0.05, cy - ry * 1.05, rx * 0.34, rx * 0.32), m_ellipse(cx + rx * 0.08, cy - ry * 0.98, rx * 0.17, rx * 0.16)), 4), tri(col), spec=True)
    for k, (yy, a0, a1) in enumerate(((-0.35, 150, 330), (0.15, 160, 340))):
        f.part(m_arc(cx - rx * 0.1, cy + ry * yy, rx * (1.2 + 0.08 * k), a0, a1, rx * 0.075), tri(lighten(c["acc"], 0.35)), line=False, sil=True, gloss=0.4)

@feat("aurora", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    # Lumaine: a glowing aurora arch over the head with curtain streaks and stars.
    cols = (c["acc"], c["acc2"], lighten(c["acc"], 0.45))
    for i, col in enumerate(cols):
        r = rx * (1.28 - i * 0.16)
        f.part(m_arc(cx, cy + ry * 0.05, r, 192, 348, rx * 0.15), tri(col), line=(i == 0), gloss=0.45)
    for k in range(7):
        a = math.radians(205 + k * 22)
        x, y = cx + rx * 1.05 * math.cos(a), cy + ry * 0.05 + rx * 1.05 * math.sin(a)
        f.flat(m_line([(x, y - rx * 0.12), (x, y + rx * 0.12)], 6), (255, 255, 255), 0.55)
    for x, y, r in ((-1.2, -1.05, 0.11), (1.25, -0.95, 0.09), (0.05, -1.42, 0.1)):
        f.part(m_poly(star_pts(cx + rx * x, cy + ry * y, rx * r, rx * r * 0.42, 4)), tri((255, 244, 190)), gloss=0)

@feat("mask", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    y, e, er = cy + c["eyey"], c["espread"], c["er"]
    m = soften(union(m_super(cx, y, e + er * 2.0, er * 1.6, 2.6),
                     m_poly([(cx - e - er * 1.7, y - er * 0.3), (cx - e - er * 2.9, y - er * 2.1), (cx - e - er * 0.6, y - er * 1.2)]),
                     m_poly([(cx + e + er * 1.7, y - er * 0.3), (cx + e + er * 2.9, y - er * 2.1), (cx + e + er * 0.6, y - er * 1.2)])), 5)
    holes = union(m_ellipse(cx - e, y, er * 1.22, er * 1.28), m_ellipse(cx + e, y, er * 1.22, er * 1.28))
    trim = sub(m, m.filter(ImageFilter.MinFilter(15)))
    f.part(sub(m, holes), tri(c["acc"]), spec=True)
    f.flat(sub(trim, holes), (240, 196, 90), 0.95)
    f.flat(sub(sub(holes.filter(ImageFilter.MaxFilter(9)), holes), m_ellipse(0, 0, 1, 1)), (240, 196, 90), 0.95)
    # feather plume
    f.part(soften(m_line([(cx + e + er * 2.4, y - er * 1.6), (cx + e + er * 3.0, y - er * 3.6), (cx + e + er * 2.4, y - er * 5.0)], er * 0.75), 6), tri(lighten(c["acc"], 0.25)))
    f.part(m_ellipse(cx + e + er * 2.35, y - er * 1.6, er * 0.45, er * 0.45), tri((240, 196, 90)), line=False)

@feat("pinwheel", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y, R = cx + rx * 1.0, cy - ry * 0.95, rx * 0.72
    f.part(m_line([(cx + rx * 0.95, cy + ry * 0.35), (x, y)], 16), tri((214, 170, 112)))
    for k in range(4):
        a = math.radians(k * 90 + 15)
        blade = m_poly([(x, y), (x + R * math.cos(a), y + R * math.sin(a)), (x + R * 0.55 * math.cos(a + 1.45), y + R * 0.55 * math.sin(a + 1.45))], 6)
        f.part(blade, tri(c["acc"] if k % 2 else c["acc2"]), gloss=0.4)
    f.part(m_ellipse(x, y, R * 0.13, R * 0.13), tri((255, 255, 255)), line=True)
