import math
import numpy as np
from core import *
FEAT = {}
def feat(name, layer="front"):
    def deco(fn): FEAT[name] = (fn, layer); return fn
    return deco
def T(b): return b[1] - b[3]

@feat("wave", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    # tall curling wave crest leaning right, with a foam tip
    pts = [(cx - rx * 0.7, t + ry * 0.45), (cx - rx * 0.62, t - ry * 0.4), (cx - rx * 0.2, t - ry * 1.0), (cx + rx * 0.45, t - ry * 1.08), (cx + rx * 0.85, t - ry * 0.7), (cx + rx * 0.62, t - ry * 0.32), (cx + rx * 0.25, t - ry * 0.48), (cx + rx * 0.3, t - ry * 0.15), (cx + rx * 0.7, t + ry * 0.45)]
    crest = soften(m_poly(pts), 14)
    f.part(crest, tri(c["acc"]), spec=True)
    f.part(m_ellipse(cx + rx * 0.55, t - ry * 0.72, rx * 0.13, rx * 0.13), tri(lighten(c["acc"], 0.7)), line=False)
    for k in range(3):
        f.flat(m_arc(cx - rx * 0.1, t - ry * 0.2, rx * (0.3 + k * 0.15), 200, 300, 12), lighten(c["acc"], 0.65), 0.75)

@feat("gills", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        for a in (-40, -15, 10):
            ang = math.radians(a)
            f.part(m_ellipse(cx + sd * rx * (0.95 + 0.25 * math.cos(ang)), cy - ry * 0.25 + ry * 0.55 * math.sin(ang), rx * 0.3, rx * 0.12, rot=sd * ang * 0.9 - sd * 0.25), tri(c["acc"]))
@feat("manta", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.4, cy - ry * 0.55), (cx + sd * rx * 1.75, cy - ry * 0.05), (cx + sd * rx * 1.3, cy + ry * 0.45), (cx + sd * rx * 0.4, cy + ry * 0.5)], 24), tri(c["mid"]))
        f.part(m_line([(cx + sd * rx * 0.25, T(b) + ry * 0.2), (cx + sd * rx * 0.45, T(b) - ry * 0.32)], rx * 0.14), tri(c["acc"]))
    f.part(m_line([(cx, cy + ry * 0.7), (cx + rx * 0.2, cy + ry * 1.1), (cx + rx * 0.5, cy + ry * 1.15)], rx * 0.08), tri(c["dark"]))
@feat("shellhood", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    fan = union(*[m_ellipse(cx + rx * math.cos(math.radians(a)), cy - ry * 0.1 + ry * math.sin(math.radians(a)), rx * 0.34, rx * 0.34) for a in range(160, 381, 22)], m_ellipse(cx, cy - ry * 0.1, rx * 1.05, ry))
    f.part(fan, tri(c["acc"]), spec=True)
    for a in range(170, 371, 22):
        f.flat(inter(m_line([(cx, cy), (cx + rx * 1.15 * math.cos(math.radians(a)), cy - ry * 0.1 + ry * 1.15 * math.sin(math.radians(a)))], 10), fan), darken(c["acc"], 0.18), 0.5)
@feat("jelly", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    dome = sub(m_ellipse(cx, cy - ry * 0.42, rx * 1.12, ry * 0.7), below(cy - ry * 0.25))
    dome = union(dome, *[m_ellipse(cx + rx * (-0.9 + i * 0.36), cy - ry * 0.27, rx * 0.2, ry * 0.12) for i in range(6)])
    f.part(dome, tri(c["acc"]), spec=True)
    for i in range(3):
        f.flat(m_ellipse(cx + rx * (-0.45 + i * 0.45), cy - ry * 0.72, rx * 0.07, rx * 0.07), lighten(c["acc"], 0.7), 0.9)
@feat("tentacles", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i in range(5):
        x = cx + rx * (-0.7 + i * 0.35)
        f.part(m_line([(x, cy + ry * 0.5), (x + rx * 0.12 * (1 if i % 2 else -1), cy + ry * 0.9), (x, cy + ry * 1.22)], rx * 0.16), tri(c["acc"]))
@feat("spikes", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i in range(14):
        a = math.radians(i * 360 / 14 - 90)
        x, y = cx + rx * math.cos(a), cy + ry * math.sin(a)
        if y > cy + ry * 0.6: continue
        tip = (cx + rx * 1.32 * math.cos(a), cy + ry * 1.32 * math.sin(a))
        f.part(m_poly([(x - 40 * math.sin(a), y + 40 * math.cos(a)), tip, (x + 40 * math.sin(a), y - 40 * math.cos(a))], 6), tri(c["acc"]))
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 1.08, cy + ry * 0.25, rx * 0.2, rx * 0.12, rot=sd * 0.6), tri(c["acc"]))
@feat("finears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.55, cy - ry * 0.45), (cx + sd * rx * 1.45, cy - ry * 1.05), (cx + sd * rx * 1.2, cy - ry * 0.1), (cx + sd * rx * 0.75, cy + ry * 0.05)], 20), tri(c["acc"]))
@feat("fishtail", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_poly([(cx + rx * 0.6, cy + ry * 0.5), (cx + rx * 1.35, cy + ry * 0.05), (cx + rx * 1.25, cy + ry * 0.6), (cx + rx * 1.4, cy + ry * 1.0)], 16), tri(c["acc"]))
@feat("clam", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    shell = union(*[m_ellipse(cx + rx * 1.15 * math.cos(math.radians(a)), cy + ry * 0.25 + ry * 1.15 * math.sin(math.radians(a)), rx * 0.3, rx * 0.3) for a in range(180, 361, 20)], m_ellipse(cx, cy + ry * 0.25, rx * 1.2, ry * 1.1))
    f.part(sub(shell, below(cy + ry * 0.65)), tri(c["acc"]), spec=True)
@feat("pearl", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_ellipse(cx + rx * 0.62, cy + ry * 0.55, rx * 0.2, rx * 0.2), tri((250, 244, 255)), spec=True)
@feat("floppy", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.98, cy + ry * 0.05, rx * 0.3, ry * 0.68, rot=sd * -0.35), tri(c["acc"]))
@feat("sailorhat", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_super(cx, t + ry * 0.1, rx * 0.68, ry * 0.12, 3), tri((250, 250, 252)))
    f.part(m_super(cx, t - ry * 0.12, rx * 0.46, ry * 0.22, 2.6), tri((250, 250, 252)))
    f.part(m_super(cx, t + ry * 0.04, rx * 0.47, ry * 0.06, 4), tri(c["acc"]), line=False)
@feat("kite", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_poly([(cx + rx * 0.95, cy - ry * 1.25), (cx + rx * 1.35, cy - ry * 0.85), (cx + rx * 0.95, cy - ry * 0.25), (cx + rx * 0.55, cy - ry * 0.85)], 6), tri(c["acc"]), spec=True)
    f.part(m_line([(cx + rx * 0.95, cy - ry * 0.25), (cx + rx * 1.15, cy + ry * 0.1), (cx + rx * 1.0, cy + ry * 0.45)], 14), tri(c["acc2"]), line=False)
    for x, y in ((1.12, 0.05), (1.05, 0.35)):
        f.part(m_poly([(cx + rx * x - 26, cy + ry * y), (cx + rx * x + 26, cy + ry * y - 14), (cx + rx * x + 26, cy + ry * y + 14)], 4), tri(c["acc2"]), line=False)
@feat("cloudears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(union(m_ellipse(cx + sd * rx * 0.75, cy - ry * 0.75, rx * 0.32, rx * 0.32), m_ellipse(cx + sd * rx * 1.0, cy - ry * 0.45, rx * 0.26, rx * 0.26), m_ellipse(cx + sd * rx * 0.55, cy - ry * 1.0, rx * 0.22, rx * 0.22)), tri(lighten(c["acc"], 0.25)))
@feat("birdwings", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        for i in range(3):
            f.part(m_ellipse(cx + sd * rx * (1.0 + i * 0.12), cy - ry * (0.15 - i * 0.2), rx * (0.5 - i * 0.08), rx * 0.16, rot=sd * (-0.6 + i * 0.35)), tri(c["acc"]))
@feat("crest", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for a in (-25, 0, 25):
        ang = math.radians(a - 90)
        f.part(m_ellipse(cx + rx * 0.35 * math.cos(ang), t + ry * 0.02 + ry * 0.35 * math.sin(ang), rx * 0.11, rx * 0.26, rot=math.radians(a)), tri(c["acc"]))
@feat("storm", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_poly([(cx + rx * 0.75, cy + ry * 0.25), (cx + rx * 1.15, cy + ry * 0.25), (cx + rx * 0.98, cy + ry * 0.55), (cx + rx * 1.22, cy + ry * 0.55), (cx + rx * 0.78, cy + ry * 1.15), (cx + rx * 0.88, cy + ry * 0.72), (cx + rx * 0.66, cy + ry * 0.72)], 3), tri((255, 220, 60)), spec=True)
@feat("propeller", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_line([(cx, t + 20), (cx, t - ry * 0.32)], 22), tri((150, 110, 70)), line=False)
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.42, t - ry * 0.36, rx * 0.42, rx * 0.14, rot=sd * -0.15), tri(c["acc"]))
        f.flat(m_line([(cx + sd * rx * 0.1, t - ry * 0.36), (cx + sd * rx * 0.75, t - ry * 0.4)], 7), darken(c["acc"], 0.25), 0.6)
@feat("starsprinkle", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y, r in ((-0.75, -0.55, 0.16), (0.62, -0.72, 0.12), (0.82, 0.2, 0.1)):
        f.part(m_poly(star_pts(cx + rx * x, cy + ry * y, rx * r, rx * r * 0.45, 5), 2), tri((255, 222, 90)))
@feat("bigwings", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        for i in range(4):
            Ln = rx * (1.3 - i * 0.18); ang = -0.85 + i * 0.32
            x0, y0 = cx + sd * rx * 0.55, cy - ry * 0.05
            f.part(m_ellipse(x0 + sd * Ln * 0.5 * math.cos(ang), y0 + Ln * 0.5 * math.sin(ang), Ln * 0.55, rx * 0.16, rot=ang if sd > 0 else math.pi - ang), tri(lighten(c["acc"], 0.12 * i)))
@feat("windtuft", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_arc(cx - rx * 0.05, t - ry * 0.12, ry * 0.22, 120, 420, rx * 0.15), tri(c["acc"]))
@feat("wisp", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(soften(m_line([(cx + rx * 0.5, cy + ry * 0.55), (cx + rx * 1.05, cy + ry * 0.7), (cx + rx * 1.3, cy + ry * 0.35), (cx + rx * 1.18, cy + ry * 0.05)], rx * 0.3), 10), tri(lighten(c["mid"], 0.15)))
@feat("cape", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_poly([(cx - rx * 0.7, cy - ry * 0.1), (cx + rx * 0.7, cy - ry * 0.1), (cx + rx * 1.15, cy + ry * 1.0), (cx, cy + ry * 0.92), (cx - rx * 1.15, cy + ry * 1.0)], 20), tri(c["acc2"]))
@feat("sunrays", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i in range(12):
        a = math.radians(i * 30 - 90)
        f.part(m_poly([(cx + rx * 0.9 * math.cos(a - 0.17), cy + ry * 0.9 * math.sin(a - 0.17)), (cx + rx * 1.38 * math.cos(a), cy + ry * 1.38 * math.sin(a)), (cx + rx * 0.9 * math.cos(a + 0.17), cy + ry * 0.9 * math.sin(a + 0.17))], 10), tri(c["acc"]))
@feat("smoke", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(soften(union(m_ellipse(cx - rx * 0.1, t - ry * 0.1, rx * 0.36, rx * 0.3), m_ellipse(cx + rx * 0.22, t - ry * 0.42, rx * 0.28, rx * 0.24), m_ellipse(cx - rx * 0.05, t - ry * 0.7, rx * 0.2, rx * 0.18)), 6), tri(lighten(c["mid"], 0.25)))
@feat("embers", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y, r in ((-0.55, 0.45, 0.07), (0.6, 0.35, 0.06), (0.1, 0.7, 0.05), (-0.25, -0.55, 0.05), (0.45, -0.5, 0.045)):
        f.flat(m_ellipse(cx + rx * x, cy + ry * y, rx * r * 1.8, rx * r * 1.8), c["acc"], 0.35)
        f.flat(m_ellipse(cx + rx * x, cy + ry * y, rx * r, rx * r), lighten(c["acc"], 0.45))
@feat("flame", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    fl = soften(m_poly([(cx - rx * 0.62, t + ry * 0.4), (cx - rx * 0.5, t - ry * 0.45), (cx - rx * 0.2, t - ry * 0.1), (cx, t - ry * 0.95), (cx + rx * 0.22, t - ry * 0.12), (cx + rx * 0.55, t - ry * 0.55), (cx + rx * 0.62, t + ry * 0.4)]), 12)
    f.part(fl, (lighten(c["acc"], 0.5), c["acc"], darken(c["acc"], 0.2)), spec=True)
    f.part(soften(m_poly([(cx - rx * 0.25, t + ry * 0.3), (cx, t - ry * 0.45), (cx + rx * 0.25, t + ry * 0.3)]), 10), tri((255, 230, 110)), line=False, sil=False)
@feat("flamewings", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        w = soften(m_poly([(cx + sd * rx * 0.6, cy + ry * 0.2), (cx + sd * rx * 1.5, cy - ry * 0.95), (cx + sd * rx * 1.3, cy - ry * 0.3), (cx + sd * rx * 1.6, cy - ry * 0.35), (cx + sd * rx * 1.2, cy + ry * 0.25), (cx + sd * rx * 1.45, cy + ry * 0.3), (cx + sd * rx * 0.85, cy + ry * 0.55)]), 10)
        f.part(w, (lighten(c["acc"], 0.45), c["acc"], darken(c["acc"], 0.2)))
@feat("lavaglow", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.flat(inter(m_ellipse(cx, cy + ry * 0.6, rx * 0.6, ry * 0.3), body_mask(c["body"], cx, cy, rx, ry)), (255, 200, 80), 0.55)
    for x in (-0.5, 0.45):
        f.flat(m_ellipse(cx + rx * x, cy + ry * 0.7, rx * 0.1, rx * 0.1), (255, 230, 130), 0.9)
@feat("cracks", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for pts in (((-0.85, 0.45), (-0.62, 0.6), (-0.68, 0.8)), ((0.7, 0.55), (0.86, 0.7), (0.66, 0.84)), ((-0.15, 0.78), (0.1, 0.9)), ((-0.3, -0.75), (-0.1, -0.62))):
        f.flat(m_line([(cx + rx * x, cy + ry * y) for x, y in pts], 22), (255, 160, 50))
        f.flat(m_line([(cx + rx * x, cy + ry * y) for x, y in pts], 9), (255, 235, 140))
@feat("ramhorns", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        hx, hy = cx + sd * rx * 0.82, cy - ry * 0.45
        f.part(m_ellipse(hx, hy, rx * 0.4, rx * 0.4), tri(c["acc"]), spec=True)
        f.flat(m_arc(hx, hy, rx * 0.24, 0, 300, 18), darken(c["acc"], 0.3), 0.8)
        f.flat(m_arc(hx, hy, rx * 0.1, 0, 300, 14), darken(c["acc"], 0.3), 0.8)
@feat("stonehood", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_poly([(cx - rx * 1.05, cy - ry * 0.1), (cx - rx * 0.2, t - ry * 0.65), (cx + rx * 0.6, t - ry * 0.4), (cx + rx * 1.05, cy - ry * 0.1)], 10), tri(c["acc"]), spec=True)
    f.part(m_poly(star_pts(cx + rx * 0.2, t - ry * 0.15, 34, 14, 4), 2), tri((255, 220, 120)), line=False)
@feat("mane", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    m = union(*[m_ellipse(cx + rx * 1.02 * math.cos(math.radians(a)), cy - ry * 0.05 + ry * 1.02 * math.sin(math.radians(a)), rx * 0.34, rx * 0.34) for a in range(150, 391, 20)])
    f.part(soften(m, 6), (lighten(c["acc"], 0.4), c["acc"], darken(c["acc"], 0.25)))
@feat("torch", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(soften(m_poly([(cx - rx * 0.32, t + ry * 0.18), (cx - rx * 0.12, t - ry * 0.35), (cx + rx * 0.05, t - ry * 0.12), (cx + rx * 0.2, t - ry * 0.7), (cx + rx * 0.34, t + ry * 0.18)]), 10), (lighten(c["acc"], 0.5), c["acc"], darken(c["acc"], 0.2)), spec=True)
@feat("petalcollar", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i in range(8):
        a = math.radians(i * 45 + 22)
        f.part(m_ellipse(cx + rx * 0.95 * math.cos(a), cy - ry * 0.05 + ry * 0.95 * math.sin(a), rx * 0.36, rx * 0.22, rot=a), tri(c["acc"]))
@feat("sprout", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_line([(cx, t + 20), (cx + 6, t - ry * 0.38)], 20), tri((110, 170, 70)))
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.3, t - ry * 0.45, rx * 0.3, rx * 0.15, rot=sd * -0.45), tri((130, 205, 90)))
@feat("sunflower", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i in range(14):
        a = math.radians(i * 360 / 14)
        f.part(m_ellipse(cx + rx * 1.08 * math.cos(a), cy - ry * 0.02 + ry * 1.08 * math.sin(a), rx * 0.3, rx * 0.13, rot=a), tri(c["acc"]))
@feat("berryleaf", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for a in (-0.8, -0.25, 0.3, 0.85):
        f.part(m_ellipse(cx + rx * 0.4 * math.sin(a), t + ry * 0.05 - ry * 0.25 * math.cos(a), rx * 0.1, rx * 0.3, rot=a), tri((90, 170, 80)))
@feat("bee", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.95, cy - ry * 0.62, rx * 0.48, rx * 0.36, rot=sd * -0.5), tri((235, 245, 255)), spec=True)
        f.part(m_ellipse(cx + sd * rx * 1.0, cy - ry * 0.12, rx * 0.32, rx * 0.22, rot=sd * 0.3), tri((235, 245, 255)))
@feat("antennae", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for sd in (-1, 1):
        f.part(m_line([(cx + sd * rx * 0.22, t + 30), (cx + sd * rx * 0.42, t - ry * 0.32)], 14), tri(c["dark"]), line=False)
        f.part(m_ellipse(cx + sd * rx * 0.45, t - ry * 0.38, rx * 0.12, rx * 0.12), tri(c["acc2"]), spec=True)
@feat("stripes", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    bm = body_mask(c["body"], cx, cy, rx, ry)
    for y in (0.48, 0.78):
        f.flat(inter(m_ellipse(cx, cy + ry * y, rx * 1.2, ry * 0.08), bm), darken(c["mid"], 0.55), 0.75)
@feat("mushcap", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    cap = soften(sub(m_ellipse(cx, t + ry * 0.35, rx * 1.3, ry * 0.75), below(t + ry * 0.45)), 10)
    f.part(cap, tri(c["acc"]), spec=True)
    for x, y, r in ((-0.6, -0.05, 0.13), (0.1, -0.3, 0.16), (0.7, 0.05, 0.11)):
        f.flat(inter(m_ellipse(cx + rx * x, t + ry * y, rx * r, rx * r * 0.8), cap), (255, 250, 235), 0.95)
@feat("bellhat", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_poly([(cx - rx * 0.4, t - ry * 0.35), (cx + rx * 0.4, t - ry * 0.35), (cx + rx * 0.6, t + ry * 0.05), (cx + rx * 0.9, t + ry * 0.3), (cx - rx * 0.9, t + ry * 0.3), (cx - rx * 0.6, t + ry * 0.05)], 16), tri(c["acc"]), spec=True)
    for i in range(5):
        f.part(m_ellipse(cx + rx * (-0.72 + i * 0.36), t + ry * 0.32, rx * 0.12, ry * 0.08), tri(c["acc"]), line=False)
    f.part(m_line([(cx, t - ry * 0.3), (cx + rx * 0.15, t - ry * 0.55)], 14), tri((100, 160, 80)), line=False)
@feat("acorn", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    cap = soften(sub(m_ellipse(cx, t + ry * 0.4, rx * 1.02, ry * 0.62), below(t + ry * 0.5)), 8)
    f.part(cap, tri((140, 95, 55)))
    for i in range(6):
        f.flat(inter(m_line([(cx + rx * (-0.9 + i * 0.36), t + ry * 0.45), (cx + rx * (-0.6 + i * 0.36), t - ry * 0.1)], 8), cap), (110, 72, 40), 0.6)
    f.part(m_line([(cx, t - ry * 0.18), (cx + rx * 0.08, t - ry * 0.4)], 18), tri((110, 72, 40)))
@feat("clover", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        hx, hy = cx + sd * rx * 0.9, cy - ry * 0.55
        f.part(soften(union(m_ellipse(hx - rx * 0.17, hy, rx * 0.28, rx * 0.28), m_ellipse(hx + rx * 0.17, hy, rx * 0.28, rx * 0.28), m_poly([(hx - rx * 0.42, hy + rx * 0.08), (hx + rx * 0.42, hy + rx * 0.08), (hx, hy + rx * 0.5)])), 8), tri(c["acc"]), spec=True)
@feat("curls", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for a in range(200, 341, 28):
        x, y = cx + rx * 0.95 * math.cos(math.radians(a)), cy - ry * 0.05 + ry * 0.95 * math.sin(math.radians(a))
        f.part(m_arc(x, y, rx * 0.16, 0, 310, rx * 0.11), tri(c["acc"]))
