import math
import numpy as np
from core import *
from feats_a import FEAT, feat, T

@feat("crystalears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.25, cy - ry * 0.75), (cx + sd * rx * 0.85, cy - ry * 1.55), (cx + sd * rx * 0.95, cy - ry * 0.45)], 6), tri(c["acc"]), spec=True)
        f.flat(m_line([(cx + sd * rx * 0.85, cy - ry * 1.45), (cx + sd * rx * 0.65, cy - ry * 0.7)], 10), lighten(c["acc"], 0.6), 0.8)
@feat("prism", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for x, h, w in ((-0.45, 0.38, 0.16), (0, 0.62, 0.2), (0.45, 0.38, 0.16)):
        f.part(m_poly([(cx + rx * (x - w), t + ry * 0.12), (cx + rx * x, t - ry * h), (cx + rx * (x + w), t + ry * 0.12)], 3), tri(c["acc"] if x else lighten(c["acc"], 0.25)), spec=True)
@feat("icicles", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    hair = soften(sub(m_ellipse(cx, t + ry * 0.42, rx * 1.02, ry * 0.62), below(t + ry * 0.55)), 6)
    hair = union(hair, *[m_poly([(cx + rx * (x - 0.13), t + ry * 0.5), (cx + rx * x, t + ry * (0.5 + l)), (cx + rx * (x + 0.13), t + ry * 0.5)], 3) for x, l in ((-0.7, 0.3), (-0.35, 0.42), (0, 0.3), (0.35, 0.42), (0.7, 0.3))])
    f.part(inter(hair, body_mask(c["body"], cx, cy, rx * 1.04, ry * 1.04)), tri(c["acc"]), spec=True)
@feat("aurora", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for i, col in enumerate((c["acc"], c["acc2"], lighten(c["acc"], 0.4))):
        f.part(soften(m_line([(cx - rx * 1.1, cy - ry * (0.2 - i * 0.25)), (cx - rx * 0.6, cy - ry * (1.05 - i * 0.18)), (cx + rx * 0.2, cy - ry * (0.75 - i * 0.18)), (cx + rx * 1.05, cy - ry * (1.25 - i * 0.2))], rx * 0.24), 6), tri(col))
@feat("gemforehead", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_poly([(cx, cy - ry * 0.78), (cx + rx * 0.18, cy - ry * 0.56), (cx, cy - ry * 0.34), (cx - rx * 0.18, cy - ry * 0.56)], 3), tri(c["acc"]), spec=True)
@feat("bubbles", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y, r in ((-1.05, -0.65, 0.2), (1.0, -0.85, 0.16), (1.15, -0.35, 0.1)):
        f.part(sub(m_ellipse(cx + rx * x, cy + ry * y, rx * r, rx * r), m_ellipse(cx + rx * x, cy + ry * y, rx * r * 0.72, rx * r * 0.72)), tri(lighten(c["acc"], 0.3)), line=False)
        f.flat(m_ellipse(cx + rx * (x - r * 0.35), cy + ry * y - rx * r * 0.4, rx * r * 0.18, rx * r * 0.18), (255, 255, 255))
@feat("icebuns", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.85, cy - ry * 0.7, rx * 0.4, rx * 0.4), (lighten(c["acc"], 0.6), lighten(c["acc"], 0.25), c["acc"]), spec=True)
        f.flat(m_ellipse(cx + sd * rx * 0.85, cy - ry * 0.7, rx * 0.2, rx * 0.2), lighten(c["acc"], 0.7), 0.7)
@feat("sealtail", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(soften(union(m_ellipse(cx + rx * 0.9, cy + ry * 0.55, rx * 0.65, ry * 0.32), m_poly([(cx + rx * 1.35, cy + ry * 0.4), (cx + rx * 1.75, cy + ry * 0.05), (cx + rx * 1.8, cy + ry * 0.75)])), 10), tri(c["mid"]))
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.85, cy + ry * 0.6, rx * 0.28, rx * 0.12, rot=sd * 0.4), tri(c["acc"]))
@feat("antlers", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for sd in (-1, 1):
        x0, y0 = cx + sd * rx * 0.35, t + ry * 0.15
        x1, y1 = cx + sd * rx * 0.62, t - ry * 0.55
        f.part(m_line([(x0, y0), (x1, y1)], 26), tri(c["acc"]), line=False)
        for k in (0.35, 0.65):
            xm, ym = x0 + (x1 - x0) * k, y0 + (y1 - y0) * k
            f.part(m_line([(xm, ym), (xm + sd * rx * 0.28, ym - ry * 0.18)], 20), tri(c["acc"]), line=False)
        f.part(m_poly(star_pts(x1, y1 - 10, 46, 16, 6), 2), tri(lighten(c["acc"], 0.5)))
@feat("earmuffs", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.part(m_arc(cx, cy - ry * 0.1, rx * 0.98, 200, 340, 30), tri(c["acc2"]), line=False)
    for sd in (-1, 1):
        f.part(soften(union(*[m_ellipse(cx + sd * rx * 0.95 + rx * 0.14 * math.cos(a), cy - ry * 0.32 + rx * 0.14 * math.sin(a), rx * 0.13, rx * 0.13) for a in np.linspace(0, 6.28, 7)]), 4), tri(c["acc"]), spec=True)
@feat("veil", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    v = soften(union(m_ellipse(cx, cy - ry * 0.2, rx * 1.15, ry * 1.05), m_poly([(cx - rx * 1.15, cy - ry * 0.2), (cx + rx * 1.15, cy - ry * 0.2), (cx + rx * 1.4, cy + ry * 1.0), (cx - rx * 1.4, cy + ry * 1.0)])), 16)
    f.part(v, tri(lighten(c["acc"], 0.2)), spec=True)
@feat("goggles", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    y = cy - ry * 0.55
    f.part(m_super(cx, y, rx * 0.95, ry * 0.08, 4), tri((120, 80, 50)), line=False)
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 0.3, y, rx * 0.22, rx * 0.22), tri((205, 150, 70)))
        f.part(m_ellipse(cx + sd * rx * 0.3, y, rx * 0.15, rx * 0.15), tri((150, 210, 230)), spec=True, line=False)
@feat("watch", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y = cx, cy + ry * 0.62
    f.part(m_ellipse(x, y, rx * 0.3, rx * 0.3), tri((225, 185, 90)), spec=True)
    f.part(m_ellipse(x, y, rx * 0.23, rx * 0.23), tri((255, 252, 240)), line=False, gloss=0)
    f.flat(m_line([(x, y), (x, y - rx * 0.16)], 9), (70, 50, 40)); f.flat(m_line([(x, y), (x + rx * 0.11, y)], 9), (70, 50, 40))
    f.part(m_ellipse(x, y - rx * 0.33, rx * 0.07, rx * 0.07), tri((225, 185, 90)), line=False)
@feat("swirltop", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_arc(cx + rx * 0.05, t - ry * 0.05, ry * 0.24, 110, 430, rx * 0.12), tri(c["acc"]))
@feat("gearears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        gx, gy, r = cx + sd * rx * 0.82, cy - ry * 0.72, rx * 0.36
        teeth = union(m_ellipse(gx, gy, r * 0.82, r * 0.82), *[m_poly([(gx + r * 0.7 * math.cos(a - 0.2), gy + r * 0.7 * math.sin(a - 0.2)), (gx + r * 1.05 * math.cos(a - 0.12), gy + r * 1.05 * math.sin(a - 0.12)), (gx + r * 1.05 * math.cos(a + 0.12), gy + r * 1.05 * math.sin(a + 0.12)), (gx + r * 0.7 * math.cos(a + 0.2), gy + r * 0.7 * math.sin(a + 0.2))]) for a in np.linspace(0, 2 * math.pi, 9)[:-1]])
        f.part(sub(teeth, m_ellipse(gx, gy, r * 0.28, r * 0.28)), tri(c["acc"]), spec=True)
@feat("pendulum", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_poly([(cx - rx * 0.55, t + ry * 0.22), (cx + rx * 0.08, t - ry * 0.75), (cx + rx * 0.55, t + ry * 0.22)], 12), tri(c["acc"]), spec=True)
    f.part(m_line([(cx + rx * 0.08, t - ry * 0.72), (cx + rx * 0.62, t - ry * 0.55), (cx + rx * 0.78, t - ry * 0.15)], 10), tri((200, 160, 80)), line=False)
    f.part(m_ellipse(cx + rx * 0.78, t - ry * 0.08, rx * 0.12, rx * 0.12), tri((235, 190, 80)), spec=True)
@feat("spring", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for i in range(4):
        y = t - ry * 0.05 - i * ry * 0.2
        f.part(m_ellipse(cx, y, rx * (0.42 - i * 0.04), ry * 0.09), tri((235, 185, 70)))
        f.flat(m_ellipse(cx, y - ry * 0.02, rx * (0.3 - i * 0.04), ry * 0.045), darken((235, 185, 70), 0.2), 0.9)
    f.part(m_ellipse(cx, t - ry * 0.88, rx * 0.16, rx * 0.16), tri(c["acc"]), spec=True)
@feat("windkey", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    kx = cx - rx * 1.05
    f.part(m_line([(cx - rx * 0.6, cy + ry * 0.1), (kx, cy + ry * 0.1)], 26), tri((210, 165, 70)), line=False)
    for dy in (-1, 1):
        f.part(m_ellipse(kx - rx * 0.12, cy + ry * 0.1 + dy * rx * 0.17, rx * 0.2, rx * 0.15), tri((235, 190, 80)), spec=True)
@feat("monocle", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    x, y = cx + c["espread"], cy + c["eyey"]
    f.part(sub(m_ellipse(x, y, c["er"] * 1.5, c["er"] * 1.5), m_ellipse(x, y, c["er"] * 1.28, c["er"] * 1.28)), tri((215, 170, 70)), line=False)
    f.part(m_line([(x + c["er"] * 1.2, y + c["er"] * 1.0), (x + c["er"] * 1.6, y + c["er"] * 2.6)], 7), tri((215, 170, 70)), line=False)
@feat("clockhands", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_poly([(cx - 14, t + 20), (cx - 8, t - ry * 0.5), (cx, t - ry * 0.62), (cx + 8, t - ry * 0.5), (cx + 14, t + 20)], 3), tri(c["acc2"]), line=False)
    f.part(m_poly([(cx, t + 10), (cx + rx * 0.4, t - ry * 0.25), (cx + rx * 0.44, t - ry * 0.18), (cx + 10, t + 26)], 3), tri(c["acc2"]), line=False)
    f.part(m_ellipse(cx, t + 8, 20, 20), tri((235, 190, 80)), line=False)
@feat("bolthorns", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    for sd in (-1, 1):
        f.part(m_super(cx + sd * rx * 0.55, t - ry * 0.05, rx * 0.12, ry * 0.2, 4), tri((170, 175, 190)), spec=True)
        f.part(m_super(cx + sd * rx * 0.55, t - ry * 0.27, rx * 0.2, ry * 0.08, 4), tri((150, 155, 170)))
@feat("rivets", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.flat(inter(m_super(cx, cy + ry * 0.62, rx * 1.2, ry * 0.42, 6), body_mask(c["body"], cx, cy, rx, ry)), darken(c["acc"], 0.05), 0.9)
    for x in (-0.6, -0.2, 0.2, 0.6):
        f.part(m_ellipse(cx + rx * x, cy + ry * 0.45, rx * 0.06, rx * 0.06), tri((220, 210, 190)), line=False)
@feat("dial", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    x, y = cx + rx * 0.45, t + ry * 0.12
    f.part(m_ellipse(x, y, rx * 0.3, rx * 0.3), tri(c["acc"]), spec=True)
    f.part(m_ellipse(x, y, rx * 0.2, rx * 0.2), tri((255, 250, 235)), line=False, gloss=0)
    for k in range(4):
        a = k * math.pi / 2
        f.flat(m_ellipse(x + rx * 0.15 * math.cos(a), y + rx * 0.15 * math.sin(a), 6, 6), (80, 60, 50))
    f.flat(m_line([(x, y), (x + rx * 0.08, y - rx * 0.1)], 7), (80, 60, 50))
@feat("spool", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    f.part(m_super(cx, t - ry * 0.25, rx * 0.36, ry * 0.25, 5), tri(c["acc"]), spec=True)
    for k in range(4):
        f.flat(m_line([(cx - rx * 0.36, t - ry * (0.38 - k * 0.09)), (cx + rx * 0.36, t - ry * (0.38 - k * 0.09))], 6), darken(c["acc"], 0.25), 0.7)
    for y in (t, t - ry * 0.52):
        f.part(m_super(cx, y, rx * 0.5, ry * 0.065, 3), tri((205, 160, 100)))
    f.part(m_line([(cx + rx * 0.36, t - ry * 0.25), (cx + rx * 0.9, t - ry * 0.05), (cx + rx * 1.05, cy - ry * 0.3)], 8), tri(c["acc"]), line=False)
@feat("gearspots", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y, r in ((-0.6, 0.35, 0.16), (0.62, 0.42, 0.13), (0.0, 0.72, 0.11)):
        f.part(sub(m_ellipse(cx + rx * x, cy + ry * y, rx * r, rx * r), m_ellipse(cx + rx * x, cy + ry * y, rx * r * 0.4, rx * r * 0.4)), tri((230, 185, 80)), line=False)
@feat("octoears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_line([(cx + sd * rx * 0.6, cy - ry * 0.55), (cx + sd * rx * 1.1, cy - ry * 0.9), (cx + sd * rx * 1.35, cy - ry * 0.45), (cx + sd * rx * 1.15, cy - ry * 0.15)], rx * 0.24), tri(c["mid"]))
        for k in range(3):
            f.flat(m_ellipse(cx + sd * rx * (1.12 + 0.08 * k), cy - ry * (0.8 - k * 0.22), rx * 0.05, rx * 0.05), lighten(c["acc"], 0.4))
@feat("drip", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    d = union(sub(m_ellipse(cx, t + ry * 0.35, rx * 1.1, ry * 0.6), below(t + ry * 0.45)), *[m_ellipse(cx + rx * x, t + ry * (0.45 + l / 2), rx * 0.11, ry * l / 2) for x, l in ((-0.6, 0.3), (-0.2, 0.42), (0.25, 0.25), (0.6, 0.36))])
    f.part(inter(soften(d, 6), body_mask(c["body"], cx, cy, rx, ry)), tri(c["acc"]), spec=True, sil=False)
    f.part(m_poly([(cx - rx * 0.2, t + ry * 0.1), (cx + rx * 0.05, t - ry * 0.45), (cx + rx * 0.2, t + ry * 0.1)], 14), tri(c["acc"]))
@feat("sakura", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    x, y = cx + rx * 0.5, t + ry * 0.12
    for k in range(5):
        a = math.radians(k * 72 - 90)
        f.part(m_ellipse(x + rx * 0.13 * math.cos(a), y + rx * 0.13 * math.sin(a), rx * 0.11, rx * 0.11), tri(c["acc2"]))
    f.flat(m_ellipse(x, y, rx * 0.06, rx * 0.06), (255, 220, 110))
@feat("lemon", "back")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    x, y, r = cx + rx * 0.25, t - ry * 0.05, rx * 0.62
    f.part(sub(m_ellipse(x, y, r, r), below(y + 4)), tri((255, 215, 60)), spec=True)
    f.part(sub(m_ellipse(x, y, r * 0.82, r * 0.82), below(y)), tri((255, 245, 170)), line=False, sil=False)
    for a in (200, 240, 280, 320):
        f.flat(m_line([(x, y - 4), (x + r * 0.78 * math.cos(math.radians(a)), y + r * 0.78 * math.sin(math.radians(a)))], 8), (255, 215, 60), 0.9)
@feat("cinnabuns", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y, r = cx + sd * rx * 0.95, cy - ry * 0.45, rx * 0.56
        f.part(m_ellipse(x, y, r, r), tri((226, 158, 88)), spec=True)
        pts = [(x + r * (0.08 + 0.8 * k / 60) * math.cos(sd * k * 0.21), y + r * (0.08 + 0.8 * k / 60) * math.sin(sd * k * 0.21)) for k in range(61)]
        f.flat(m_line(pts, 26), (140, 80, 40), 0.95)
        f.flat(m_line(pts, 10), (250, 236, 220), 0.9)
        f.flat(m_ellipse(x - r * 0.3, y - r * 0.55, r * 0.25, r * 0.1), (255, 245, 230), 0.8)
@feat("longears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_ellipse(cx + sd * rx * 1.02, cy, rx * 0.36, ry * 0.85, rot=sd * -0.55), tri(c["acc"]))
@feat("lollipops", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        x, y, r = cx + sd * rx * 1.05, cy - ry * 0.75, rx * 0.38
        f.part(m_line([(cx + sd * rx * 0.6, cy - ry * 0.35), (x, y)], 16), tri((250, 250, 250)), line=False)
        f.part(m_ellipse(x, y, r, r), tri(c["acc"]), spec=True)
        f.flat(m_arc(x, y, r * 0.6, 0, 320, 18), (255, 255, 255), 0.9)
        f.flat(m_arc(x, y, r * 0.25, 90, 400, 14), (255, 255, 255), 0.9)
@feat("cookiedots", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    for x, y in ((-0.65, -0.65), (0.65, -0.65), (-0.7, 0.55), (0.7, 0.55), (0, 0.78), (0, -0.82)):
        f.flat(m_ellipse(cx + rx * x, cy + ry * y, 13, 13), darken(c["mid"], 0.35), 0.9)
@feat("jellyears", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        ear = m_ellipse(cx + sd * rx * 0.48, cy - ry * 1.05, rx * 0.25, ry * 0.68, rot=sd * 0.22)
        f.part(ear, (lighten(c["acc"], 0.55), lighten(c["acc"], 0.15), c["acc"]), spec=True)
        f.flat(inter(m_ellipse(cx + sd * rx * 0.5, cy - ry * 1.0, rx * 0.1, ry * 0.42, rot=sd * 0.22), ear), lighten(c["acc"], 0.6), 0.75)
        f.flat(m_ellipse(cx + sd * rx * 0.56, cy - ry * 1.3, rx * 0.05, rx * 0.05), (255, 255, 255), 0.9)
@feat("gummydrop", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    f.flat(inter(m_ellipse(cx, cy + ry * 0.5, rx * 0.65, ry * 0.35), body_mask(c["body"], cx, cy, rx, ry)), lighten(c["mid"], 0.45), 0.45)
@feat("wrapper", "back")
def _(f, b, c):
    cx, cy, rx, ry = b
    for sd in (-1, 1):
        f.part(m_poly([(cx + sd * rx * 0.75, cy - ry * 0.02), (cx + sd * rx * 1.5, cy - ry * 0.5), (cx + sd * rx * 1.38, cy + ry * 0.05), (cx + sd * rx * 1.5, cy + ry * 0.55)], 14), tri(c["acc"]), spec=True)
        f.flat(m_line([(cx + sd * rx * 1.0, cy), (cx + sd * rx * 1.35, cy - ry * 0.3)], 10), lighten(c["acc"], 0.55), 0.8)
@feat("candystripe", "front")
def _(f, b, c):
    cx, cy, rx, ry = b
    bm = body_mask(c["body"], cx, cy, rx, ry)
    for k in range(-3, 4):
        f.flat(inter(m_line([(cx + rx * (k * 0.4 - 0.4), cy + ry * 1.1), (cx + rx * (k * 0.4 + 0.4), cy - ry * 1.1)], 30), bm), (255, 255, 255), 0.5)
@feat("frosting", "front")
def _(f, b, c):
    cx, cy, rx, ry = b; t = T(b)
    fr = soften(union(*[m_ellipse(cx + rx * x, t + ry * y, rx * r, rx * r) for x, y, r in ((-0.75, 0.3, 0.3), (-0.35, 0.12, 0.34), (0.1, 0.05, 0.36), (0.55, 0.15, 0.32), (0.85, 0.35, 0.24), (-0.1, -0.25, 0.26), (0.05, -0.5, 0.16))]), 6)
    f.part(fr, tri(c["acc"]), spec=True)
    f.part(m_ellipse(cx + rx * 0.22, t - ry * 0.55, rx * 0.2, rx * 0.1, rot=-0.6), tri((90, 170, 90)))
