import math
import numpy as np
from core import *
from feats_b import FEAT, feat, T

@feat("inkdrip", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y in ((-0.55, 0.2), (0.6, 0.45)):
        f.flat(m_ellipse(cx + rx * x, cy + ry * y, rx * 0.09, rx * 0.09), lighten(c["mid"], 0.45), 0.8)
    f.part(m_poly([(cx - rx * 0.12, cy + ry * 1.1), (cx, cy + ry * 0.88), (cx + rx * 0.12, cy + ry * 1.1), (cx, cy + ry * 1.24)], 12), tri(c["mid"]))
@feat("paperears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.2, cy - ry * 0.7), (cx + sd * rx * 1.25, cy - ry * 1.35), (cx + sd * rx * 0.95, cy - ry * 0.25)], 4), tri(c["acc"]), gloss=0.2)
        f.flat(m_poly([(cx + sd * rx * 0.55, cy - ry * 0.75), (cx + sd * rx * 1.15, cy - ry * 1.2), (cx + sd * rx * 0.95, cy - ry * 0.55)], 3), darken(c["acc"], 0.14), 0.8)
@feat("quill", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_ellipse(cx + rx * 0.35, t - ry * 0.45, rx * 0.18, ry * 0.62, rot=0.5), tri(c["acc"]), spec=True)
    f.flat(m_line([(cx + rx * 0.08, t + ry * 0.05), (cx + rx * 0.64, t - ry * 0.95)], 8), lighten(c["acc"], 0.55), 0.9)
@feat("polka", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    bm = body_mask(c["body"], cx, cy, rx, ry)
    for x, y, r in ((-0.72, 0.1, 0.12), (0.7, 0.05, 0.1), (-0.4, 0.62, 0.1), (0.42, 0.6, 0.12), (0.0, 0.85, 0.08), (-0.55, -0.6, 0.09), (0.55, -0.62, 0.08)):
        f.flat(inter(m_ellipse(cx + rx * x, cy + ry * y, rx * r, rx * r), bm), lighten(c["acc"], 0.1), 0.95)
@feat("beret", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_ellipse(cx - rx * 0.15, t + ry * 0.1, rx * 0.72, ry * 0.2, rot=-0.15), tri(c["acc2"]), spec=True)
    f.part(m_line([(cx - rx * 0.15, t - ry * 0.08), (cx - rx * 0.05, t - ry * 0.25)], 14), tri(c["acc2"]), line=False)
@feat("crane", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.4, cy - ry * 0.1), (cx + sd * rx * 1.6, cy - ry * 1.05), (cx + sd * rx * 1.05, cy + ry * 0.2)]), tri(c["acc"]), gloss=0.15)
        f.flat(m_poly([(cx + sd * rx * 0.8, cy - ry * 0.25), (cx + sd * rx * 1.6, cy - ry * 1.05), (cx + sd * rx * 1.05, cy + ry * 0.2)]), darken(c["acc"], 0.15), 0.9)
    f.part(m_poly([(cx - rx * 0.2, cy - ry * 0.75), (cx + rx * 0.05, cy - ry * 1.5), (cx + rx * 0.25, cy - ry * 0.75)]), tri(c["acc2"]), gloss=0.15)
@feat("brushtail", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_line([(cx - rx * 0.4, cy + ry * 0.5), (cx - rx * 1.2, cy - ry * 0.5)], 26), tri((165, 110, 60)), line=False)
    f.part(m_poly([(cx - rx * 1.05, cy - ry * 0.38), (cx - rx * 1.32, cy - ry * 0.6), (cx - rx * 1.55, cy - ry * 1.05), (cx - rx * 1.25, cy - ry * 0.85)], 8), tri(c["acc2"]))
@feat("roundears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.72, cy - ry * 0.78, rx * 0.34, rx * 0.34), tri(c["mid"]))
        f.flat(m_ellipse(cx + sd * rx * 0.72, cy - ry * 0.76, rx * 0.18, rx * 0.18), lighten(c["acc"], 0.2), 0.9)
@feat("bow", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    x, y = cx + rx * 0.35, t + ry * 0.15
    for sd in (-1, 1):
        f.part(m_poly([(x, y), (x + sd * rx * 0.32, y - rx * 0.2), (x + sd * rx * 0.32, y + rx * 0.2)], 10), tri(c["acc"]))
    f.part(m_ellipse(x, y, rx * 0.08, rx * 0.08), tri(c["acc"]))
@feat("stamp", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_super(cx, t - ry * 0.2, rx * 0.5, ry * 0.32, 6), tri(c["acc"]), spec=True)
    f.flat(m_super(cx, t - ry * 0.2, rx * 0.3, ry * 0.18, 6), lighten(c["acc"], 0.45), 0.9)
    f.flat(m_super(cx, t - ry * 0.2, rx * 0.18, ry * 0.08, 6), c["acc"], 0.9)
@feat("scrollears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y = cx + sd * rx * 0.88, cy - ry * 0.6
        f.part(m_super(x, y + ry * 0.2, rx * 0.2, ry * 0.45, 3), tri(c["acc"]))
        f.part(m_ellipse(x, y - ry * 0.25, rx * 0.25, rx * 0.25), tri(c["acc"]), spec=True)
        f.flat(m_arc(x, y - ry * 0.25, rx * 0.13, 0, 320, 12), darken(c["acc"], 0.3), 0.8)
@feat("chalkfluff", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(soften(union(*[m_ellipse(cx + sd * rx * (0.75 + 0.22 * math.cos(a)), cy - ry * (0.65 + 0.25 * math.sin(a)), rx * 0.2, rx * 0.2) for a in np.linspace(0, 6.28, 7)]), 5), tri(lighten(c["acc"], 0.1)))
@feat("pixelcrown", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    q = rx * 0.17
    for i, j in ((-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2), (1, 2), (0, 3)):
        f.part(m_super(cx + i * q * 1.05, t + ry * 0.1 - j * q * 1.05, q * 0.5, q * 0.5, 8), tri(c["acc"] if (i + j) % 2 == 0 else lighten(c["acc"], 0.35)), line=False)
@feat("boltears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y = cx + sd * rx * 0.55, cy - ry * 0.75
        f.part(m_poly([(x, y + ry * 0.2), (x + sd * rx * 0.55, y - ry * 0.6), (x + sd * rx * 0.3, y - ry * 0.25), (x + sd * rx * 0.75, y - ry * 0.55), (x + sd * rx * 0.25, y + ry * 0.3)], 4), tri(c["acc"]), spec=True)
@feat("glitch", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y, w in ((-1.2, -0.3, 0.25), (1.05, 0.15, 0.3), (-1.0, 0.45, 0.18), (1.15, -0.6, 0.15), (0.3, -1.15, 0.2)):
        f.part(m_super(cx + rx * x, cy + ry * y, rx * w, rx * 0.08, 8), tri(c["acc"] if x < 0 else c["acc2"]), line=False)
@feat("cyberears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.15, cy - ry * 0.85), (cx + sd * rx * 0.8, cy - ry * 1.5), (cx + sd * rx * 0.92, cy - ry * 0.5)], 8), tri(c["mid"]))
        f.part(m_poly([(cx + sd * rx * 0.4, cy - ry * 0.85), (cx + sd * rx * 0.78, cy - ry * 1.25), (cx + sd * rx * 0.82, cy - ry * 0.7)], 4), tri(c["acc"]), line=False)
@feat("visor", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_super(cx, cy + c["eyey"] - c["er"] * 1.45, rx * 0.78, c["er"] * 0.32, 4), tri(c["acc"]), spec=True)
@feat("headphones", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_arc(cx, cy - ry * 0.05, rx * 1.0, 195, 345, 34), tri(c["acc2"]))
    for sd in (-1, 1):
        f.part(m_super(cx + sd * rx * 0.98, cy - ry * 0.05, rx * 0.17, ry * 0.3, 3), tri(c["acc"]), spec=True)
@feat("controller", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y = cx, cy + ry * 0.68
    f.part(m_super(x, y, rx * 0.5, ry * 0.2, 3), tri((90, 90, 110)), spec=True)
    f.flat(m_super(x - rx * 0.27, y, rx * 0.09, rx * 0.03, 6), (230, 230, 240)); f.flat(m_super(x - rx * 0.27, y, rx * 0.03, rx * 0.09, 6), (230, 230, 240))
    f.flat(m_ellipse(x + rx * 0.22, y - rx * 0.05, rx * 0.05, rx * 0.05), (255, 90, 110)); f.flat(m_ellipse(x + rx * 0.34, y + rx * 0.05, rx * 0.05, rx * 0.05), (90, 200, 255))
@feat("starpaws", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly(star_pts(cx + sd * rx * 0.85, cy - ry * 0.8, rx * 0.36, rx * 0.17, 5, -90 + sd * 12), 4), tri(c["acc"]), spec=True)
@feat("rings", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y, r = cx + sd * rx * 1.0, cy - ry * 0.7, rx * 0.6
        f.part(sub(m_ellipse(x, y, r, r), m_ellipse(x, y, r * 0.45, r * 0.45)), tri(c["acc"]), spec=True)
@feat("halo", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(sub(m_ellipse(cx, t - ry * 0.28, rx * 0.48, ry * 0.13), m_ellipse(cx, t - ry * 0.28, rx * 0.34, ry * 0.06)), tri((255, 230, 120)))
@feat("diamondears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y = cx + sd * rx * 0.72, cy - ry * 0.95
        f.part(m_poly([(x, y - ry * 0.48), (x + rx * 0.34, y), (x, y + ry * 0.48), (x - rx * 0.34, y)], 6), tri(c["acc"]), spec=True)
        f.part(m_poly([(x, y - ry * 0.24), (x + rx * 0.16, y), (x, y + ry * 0.24), (x - rx * 0.16, y)], 3), tri(lighten(c["acc"], 0.5)), line=False)
@feat("datafins", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 1.05, cy - ry * 0.25, rx * 0.5, ry * 0.32, rot=sd * -0.5), tri(c["mid"]))
        for k in range(3):
            f.flat(m_ellipse(cx + sd * rx * (0.85 + k * 0.17), cy - ry * (0.15 + k * 0.12), rx * 0.05, rx * 0.05), (255, 255, 255), 0.85)
@feat("cube", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y, s_ = cx + rx * 0.78, cy + ry * 0.62, rx * 0.22
    f.part(m_poly([(x, y - s_), (x + s_, y - s_ * 0.5), (x + s_, y + s_ * 0.6), (x, y + s_), (x - s_, y + s_ * 0.6), (x - s_, y - s_ * 0.5)], 3), tri(c["acc2"]), spec=True)
@feat("sparks", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i in range(7):
        a = math.radians(-90 + (i - 3) * 30)
        x, y = cx + rx * 1.1 * math.cos(a), cy - ry * 0.1 + ry * 1.1 * math.sin(a)
        f.part(m_poly(star_pts(x, y, rx * (0.26 if i % 2 == 0 else 0.18), rx * 0.07, 4, -90 + i * 10), 2), tri(c["acc"] if i % 2 == 0 else c["acc2"]))
@feat("lanterns", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y = cx + sd * rx * 0.92, cy - ry * 0.68
        f.flat(m_ellipse(x, y, rx * 0.44, rx * 0.5), (255, 220, 120), 0.35)
        body = m_super(x, y, rx * 0.3, rx * 0.36, 2.3)
        f.part(body, tri((255, 180, 60)), spec=True)
        for k in (-0.5, 0, 0.5):
            f.flat(inter(m_line([(x + rx * 0.3 * k, y - rx * 0.36), (x + rx * 0.3 * k, y + rx * 0.36)], 6), body), (215, 120, 40), 0.6)
        for yy in (y - rx * 0.38, y + rx * 0.38):
            f.part(m_super(x, yy, rx * 0.16, rx * 0.05, 4), tri((180, 60, 50)), line=False)
@feat("mask", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    y, e, er = cy + c["eyey"], c["espread"], c["er"]
    m = soften(union(m_ellipse(cx - e, y, er * 1.8, er * 1.4), m_ellipse(cx + e, y, er * 1.8, er * 1.4),
                     m_poly([(cx - e - er * 1.6, y - er * 0.4), (cx - e - er * 2.4, y - er * 2.0), (cx - e - er * 0.6, y - er * 1.1)]),
                     m_poly([(cx + e + er * 1.6, y - er * 0.4), (cx + e + er * 2.4, y - er * 2.0), (cx + e + er * 0.6, y - er * 1.1)])), 4)
    m = sub(m, union(m_ellipse(cx - e, y, er * 1.18, er * 1.24), m_ellipse(cx + e, y, er * 1.18, er * 1.24)))
    f.part(m, tri(c["acc"]), spec=True)
@feat("hood", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(soften(union(m_ellipse(cx, cy - ry * 0.15, rx * 1.18, ry * 1.08), m_poly([(cx - rx * 0.4, cy - ry * 0.9), (cx + rx * 0.9, cy - ry * 1.55), (cx + rx * 0.65, cy - ry * 0.5)])), 14), tri(c["acc"]), spec=True)
@feat("bunnyears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.42, cy - ry * 1.12, rx * 0.2, ry * 0.6, rot=sd * 0.18), tri(c["mid"]))
        f.flat(m_ellipse(cx + sd * rx * 0.43, cy - ry * 1.08, rx * 0.09, ry * 0.42, rot=sd * 0.18), c["acc"], 0.9)
@feat("floatlantern", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y = cx + rx * 1.15, cy - ry * 0.95
    f.flat(m_ellipse(x, y, rx * 0.3, rx * 0.34), (255, 220, 120), 0.35)
    f.part(m_super(x, y, rx * 0.17, rx * 0.22, 2.4), tri((255, 190, 80)), spec=True)
    f.flat(m_line([(x, y + rx * 0.22), (x - rx * 0.1, y + rx * 0.5)], 6), (200, 140, 60), 0.8)
@feat("nightcape", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    cp = soften(union(m_ellipse(cx, cy - ry * 0.12, rx * 1.12, ry * 1.06), m_poly([(cx - rx * 1.12, cy), (cx + rx * 1.12, cy), (cx + rx * 1.35, cy + ry * 1.0), (cx - rx * 1.35, cy + ry * 1.0)]),
                    m_poly([(cx - rx * 0.6, cy - ry * 0.85), (cx - rx * 0.05, cy - ry * 1.7), (cx + rx * 0.5, cy - ry * 0.85)])), 12)
    f.part(cp, tri(c["acc"]), spec=True)
    for x, y in ((-0.85, 0.55), (0.9, 0.3), (-0.1, -1.25)):
        f.part(m_poly(star_pts(cx + rx * x, cy + ry * y, rx * 0.09, rx * 0.04, 4), 1), tri((255, 225, 120)), line=False, sil=False)
@feat("ribbonloops", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        for dx, dy, r in ((0.85, -0.85, 0.36), (1.2, -0.35, 0.3)):
            x, y = cx + sd * rx * dx, cy + ry * dy
            f.part(sub(m_ellipse(x, y, rx * r, rx * r * 0.8), m_ellipse(x, y, rx * r * 0.55, rx * r * 0.42)), tri(c["acc"]), spec=True)
@feat("partyhat", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    hat = m_poly([(cx - rx * 0.35, t + ry * 0.15), (cx + rx * 0.12, t - ry * 0.8), (cx + rx * 0.4, t + ry * 0.15)], 6)
    f.part(hat, tri(c["acc"]), spec=True)
    for k in range(3):
        f.flat(inter(m_line([(cx - rx * 0.5, t - ry * (0.05 + k * 0.28)), (cx + rx * 0.6, t - ry * (0.2 + k * 0.28))], 18), hat), c["acc2"], 0.9)
    f.part(m_ellipse(cx + rx * 0.12, t - ry * 0.85, rx * 0.12, rx * 0.12), tri(c["acc2"]), spec=True)
@feat("glowbulbs", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for sd in (-1, 1):
        f.part(m_line([(cx + sd * rx * 0.25, t + 25), (cx + sd * rx * 0.5, t - ry * 0.35), (cx + sd * rx * 0.72, t - ry * 0.42)], 12), tri(c["dark"]), line=False)
        x, y = cx + sd * rx * 0.75, t - ry * 0.45
        f.flat(m_ellipse(x, y, rx * 0.25, rx * 0.25), (255, 220, 100), 0.35)
        f.part(m_ellipse(x, y, rx * 0.14, rx * 0.14), tri((255, 220, 100)), spec=True)
@feat("plumehat", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_super(cx, t + ry * 0.05, rx * 0.4, ry * 0.25, 4), tri(c["acc"]), spec=True)
    f.part(m_super(cx, t + ry * 0.22, rx * 0.6, ry * 0.07, 3), tri(c["acc"]))
    f.part(m_super(cx, t + ry * 0.1, rx * 0.41, ry * 0.05, 5), tri((255, 210, 90)), line=False)
    f.part(m_ellipse(cx + rx * 0.3, t - ry * 0.45, rx * 0.12, ry * 0.32, rot=0.4), tri(c["acc2"]))
@feat("moonhorns", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(sub(m_ellipse(cx, t - ry * 0.05, rx * 0.72, rx * 0.6), m_ellipse(cx, t - ry * 0.32, rx * 0.62, rx * 0.5)), tri((255, 225, 120)), spec=True)
@feat("pinwheel", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y = cx + rx * 0.95, cy - ry * 0.95
    f.part(m_line([(cx + rx * 0.7, cy + ry * 0.1), (x, y)], 12), tri((200, 160, 110)), line=False)
    for k in range(4):
        a = math.radians(k * 90 + 20)
        f.part(m_poly([(x, y), (x + rx * 0.4 * math.cos(a), y + rx * 0.4 * math.sin(a)), (x + rx * 0.28 * math.cos(a + 1.0), y + rx * 0.28 * math.sin(a + 1.0))], 3), tri(c["acc"] if k % 2 else c["acc2"]))
    f.part(m_ellipse(x, y, rx * 0.06, rx * 0.06), tri((255, 230, 120)), line=False)
@feat("belly", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_ellipse(cx, cy + ry * 0.58, rx * 0.48, ry * 0.28), tri(lighten(c["mid"], 0.6)), line=False, gloss=0, sil=False)
@feat("scarf", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(inter(m_super(cx, cy + ry * 0.48, rx * 1.1, ry * 0.11, 3), body_mask(c["body"], cx, cy, rx * 1.03, ry * 1.03)), tri(c["acc2"]), sil=False)
    f.part(m_super(cx + rx * 0.45, cy + ry * 0.74, rx * 0.12, ry * 0.22, 3), tri(c["acc2"]))
@feat("feet", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.42, cy + ry * 0.95, rx * 0.22, ry * 0.12), tri(c["mid"]))
@feat("arms", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.86, cy + ry * 0.42, rx * 0.15, ry * 0.2, rot=sd * -0.5), tri(c["mid"]))
