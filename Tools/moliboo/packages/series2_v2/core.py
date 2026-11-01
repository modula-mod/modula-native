"""Moliboo v2 core: masks, glossy part painter, face, bodies, fit-to-canvas."""
import colorsys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1280
OUT, PAD = 640, 40
U = S / 1000.0

def clamp(c): return tuple(int(max(0, min(255, v))) for v in c)
def mix(a, b, t): return clamp([a[i] * (1 - t) + b[i] * t for i in range(3)])
def lighten(c, t): return mix(c, (255, 255, 255), t)
def darken(c, t): return mix(c, (0, 0, 0), t)
def sat(c, k=1.15, v=1.0):
    h, s, vv = colorsys.rgb_to_hsv(*(x / 255 for x in c))
    r, g, b = colorsys.hsv_to_rgb(h, min(1, s * k), min(1, vv * v))
    return clamp((r * 255, g * 255, b * 255))
def tri(c): return (lighten(c, 0.55), c, darken(c, 0.32))
def lum(c): return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def L(): return Image.new("L", (S, S), 0)
def P(x, y): return (x * U, y * U)
def m_poly(pts, rnd=0):
    im = L(); ImageDraw.Draw(im).polygon([P(x, y) for x, y in pts], fill=255)
    return soften(im, rnd) if rnd else im
def m_ellipse(cx, cy, rx, ry, rot=0):
    if rot == 0:
        im = L(); ImageDraw.Draw(im).ellipse([P(cx - rx, cy - ry), P(cx + rx, cy + ry)], fill=255); return im
    pts = [(cx + rx * math.cos(t) * math.cos(rot) - ry * math.sin(t) * math.sin(rot),
            cy + rx * math.cos(t) * math.sin(rot) + ry * math.sin(t) * math.cos(rot)) for t in np.linspace(0, 2 * math.pi, 90)]
    return m_poly(pts)
def m_super(cx, cy, rx, ry, n=3.0, flat=0.0):
    pts = []
    for t in np.linspace(0, 2 * math.pi, 160):
        c, s = math.cos(t), math.sin(t)
        x = cx + rx * np.sign(c) * abs(c) ** (2 / n)
        y = cy + ry * np.sign(s) * abs(s) ** (2 / n)
        if flat and s > 0: y = cy + (y - cy) * (1 - flat)
        pts.append((x, y))
    return m_poly(pts)
def m_line(pts, w):
    im = L(); d = ImageDraw.Draw(im)
    d.line([P(x, y) for x, y in pts], fill=255, width=max(1, int(w * U)), joint="curve")
    for x, y in pts:
        d.ellipse([P(x - w / 2, y - w / 2), P(x + w / 2, y + w / 2)], fill=255)
    return im
def m_arc(cx, cy, r, a0, a1, w, steps=40):
    return m_line([(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in np.linspace(a0, a1, steps)], w)
def soften(im, r): return im.filter(ImageFilter.GaussianBlur(r * U)).point(lambda v: 255 if v > 127 else 0)
def union(*ms):
    a = np.zeros((S, S), np.uint8)
    for m in ms: a = np.maximum(a, np.asarray(m))
    return Image.fromarray(a)
def sub(a, b): return Image.fromarray(np.clip(np.asarray(a).astype(int) - np.asarray(b), 0, 255).astype(np.uint8))
def inter(a, b): return Image.fromarray(np.minimum(np.asarray(a), np.asarray(b)))
def below(y): return m_poly([(-50, y), (1050, y), (1050, 1050), (-50, 1050)])
def star_pts(cx, cy, r1, r2, n=5, rot=-90):
    return [(cx + (r1 if i % 2 == 0 else r2) * math.cos(math.radians(rot + i * 180 / n)),
             cy + (r1 if i % 2 == 0 else r2) * math.sin(math.radians(rot + i * 180 / n))) for i in range(2 * n)]

YY, XX = np.mgrid[0:S, 0:S].astype(np.float32)

class Fig:
    def __init__(s, pal):
        s.pal = pal
        s.img = np.zeros((S, S, 4), np.float32)
        s.sil = L()
    def _comp(s, mask, rgb):
        m = (np.asarray(mask.filter(ImageFilter.GaussianBlur(1.1))).astype(np.float32) / 255)[..., None]
        a = s.img[..., 3:4]
        out_a = m + a * (1 - m)
        s.img[..., :3] = np.where(out_a > 0, (rgb * m + s.img[..., :3] * a * (1 - m)) / np.maximum(out_a, 1e-5), 0)
        s.img[..., 3:4] = out_a
    def flat(s, mask, col, alpha=1.0):
        if alpha < 1: mask = mask.point(lambda v: int(v * alpha))
        s._comp(mask, np.array(col, np.float32))
    def part(s, mask, cols, spec=False, line=True, sil=True, gloss=0.35):
        bb = mask.getbbox()
        if not bb: return
        x0, y0, x1, y1 = bb; w, h = max(x1 - x0, 1), max(y1 - y0, 1)
        light, mid, dark = (np.array(c, np.float32) for c in cols)
        g = np.sqrt(((XX - (x0 + 0.36 * w)) / (1.05 * w)) ** 2 + ((YY - (y0 + 0.28 * h)) / (1.05 * h)) ** 2)
        g = np.clip(g / 0.85, 0, 1)[..., None]
        col = light * (1 - g) ** 2 + mid * (2 * g * (1 - g)) + dark * g ** 2
        bot = np.clip((YY - (y0 + 0.55 * h)) / (0.45 * h), 0, 1)[..., None]
        col = col * (1 - 0.22 * bot) + dark * 0.22 * bot
        s._comp(mask, col)
        if line:
            s.flat(sub(mask, mask.filter(ImageFilter.MinFilter(5))), s.pal["outline"], 0.55)
        cxu, cyu = (x0 + 0.3 * w) / U, (y0 + 0.24 * h) / U
        if spec:
            s.flat(inter(m_ellipse(cxu, cyu, w / U * 0.17, h / U * 0.075, rot=-0.45), mask), (255, 255, 255), 0.85)
            s.flat(inter(m_ellipse(cxu + w / U * 0.2, cyu - h / U * 0.05, w / U * 0.03, w / U * 0.03), mask), (255, 255, 255), 0.95)
        elif gloss:
            s.flat(inter(m_ellipse(cxu + w / U * 0.04, cyu + h / U * 0.02, w / U * 0.14, h / U * 0.08, rot=-0.5), mask), (255, 255, 255), gloss)
        if sil: s.sil = union(s.sil, mask)

def eye(f, x, y, r, style, glow, accent, ink):
    if style in ("happy", "wink"):
        f.flat(m_arc(x, y + r * 0.35, r * 0.72, 200, 340, r * 0.36), ink); return
    if glow: f.flat(m_ellipse(x, y, r * 1.18, r * 1.24), lighten(accent, 0.35), 0.9)
    bead = m_ellipse(x, y, r, r * 1.08)
    f.part(bead, ((70, 58, 86), (30, 22, 40), (10, 8, 16)), line=False, sil=False, gloss=0)
    f.flat(inter(m_ellipse(x, y + r * 0.6, r * 0.72, r * 0.42), bead), mix(accent, (30, 22, 40), 0.35), 0.85)
    f.flat(m_ellipse(x - r * 0.3, y - r * 0.34, r * 0.4, r * 0.4), (255, 255, 255))
    f.flat(m_ellipse(x + r * 0.36, y + r * 0.3, r * 0.16, r * 0.16), (255, 255, 255), 0.95)
    if style == "sparkle":
        f.flat(m_poly(star_pts(x + r * 0.32, y - r * 0.52, r * 0.24, r * 0.07, 4, -90)), (255, 255, 255))

def mouth(f, x, y, w, style, ink, tongue=(255, 120, 140)):
    lw = max(w * 0.16, 9)
    if style == "smile": f.flat(m_arc(x, y - w * 0.35, w * 0.5, 30, 150, lw), ink)
    elif style == "open":
        m = m_poly([(x - w * 0.5, y - w * 0.1), (x + w * 0.5, y - w * 0.1), (x + w * 0.3, y + w * 0.38), (x, y + w * 0.48), (x - w * 0.3, y + w * 0.38)], 6)
        f.flat(m, darken(ink, 0.1)); f.flat(inter(m_ellipse(x, y + w * 0.42, w * 0.3, w * 0.2), m), tongue)
    elif style == "cat":
        f.flat(m_arc(x - w * 0.22, y - w * 0.05, w * 0.23, 20, 160, lw * 0.9), ink)
        f.flat(m_arc(x + w * 0.22, y - w * 0.05, w * 0.23, 20, 160, lw * 0.9), ink)
    elif style == "o":
        f.flat(m_ellipse(x, y + w * 0.08, w * 0.17, w * 0.21), darken(ink, 0.1))
        f.flat(m_ellipse(x, y + w * 0.16, w * 0.1, w * 0.08), tongue)
    elif style == "fang":
        f.flat(m_arc(x, y - w * 0.35, w * 0.5, 30, 150, lw), ink)
        f.flat(m_poly([(x + w * 0.1, y + w * 0.1), (x + w * 0.32, y + w * 0.08), (x + w * 0.22, y + w * 0.34)], 2), (255, 255, 255))
    elif style == "beak":
        f.part(m_poly([(x - w * 0.32, y - w * 0.15), (x + w * 0.32, y - w * 0.15), (x, y + w * 0.34)], 5), tri((255, 186, 72)), sil=False, gloss=0.3)

def body_mask(kind, cx, cy, rx, ry):
    if kind == "round": return m_ellipse(cx, cy, rx, ry)
    if kind == "wide": return m_super(cx, cy, rx * 1.12, ry * 0.86, 2.4)
    if kind == "egg":
        return m_poly([(cx + rx * 0.9 * math.cos(t) * (0.82 if math.sin(t) < 0 else 1), cy + ry * 1.08 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 120)])
    if kind == "mochi": return m_super(cx, cy + ry * 0.08, rx * 1.05, ry * 0.92, 2.6, flat=0.18)
    if kind == "squircle": return m_super(cx, cy, rx * 0.96, ry * 0.96, 4.2)
    if kind == "drop":
        return union(m_ellipse(cx, cy + ry * 0.12, rx * 0.95, ry * 0.86), m_poly([(cx - rx * 0.62, cy - ry * 0.2), (cx + rx * 0.62, cy - ry * 0.2), (cx + rx * 0.12, cy - ry * 1.12)], 14))
    if kind == "pear":
        return soften(union(m_ellipse(cx, cy + ry * 0.2, rx * 1.02, ry * 0.8), m_ellipse(cx, cy - ry * 0.35, rx * 0.72, ry * 0.62)), 22)
    if kind == "cloud":
        return soften(union(m_ellipse(cx, cy + ry * 0.15, rx * 0.95, ry * 0.78), *[m_ellipse(cx + rx * dx, cy + ry * dy, rx * r, rx * r) for dx, dy, r in
                      ((-0.62, 0.05, 0.42), (0.62, 0.05, 0.42), (-0.35, -0.42, 0.45), (0.3, -0.5, 0.5), (0, 0.35, 0.6))]), 10)
    if kind == "ghost":
        top = m_ellipse(cx, cy - ry * 0.05, rx * 0.92, ry * 0.95)
        rect = m_poly([(cx - rx * 0.92, cy - ry * 0.05), (cx + rx * 0.92, cy - ry * 0.05), (cx + rx * 0.92, cy + ry * 0.78), (cx - rx * 0.92, cy + ry * 0.78)])
        waves = union(*[m_ellipse(cx + rx * (-0.69 + i * 0.46), cy + ry * 0.8, rx * 0.235, ry * 0.2) for i in range(4)])
        return soften(union(top, rect, waves), 6)
    if kind == "bell":
        return soften(m_poly([(cx - rx * 0.55, cy - ry * 0.7), (cx + rx * 0.55, cy - ry * 0.7), (cx + rx * 0.78, cy + ry * 0.2), (cx + rx * 1.08, cy + ry * 0.92), (cx - rx * 1.08, cy + ry * 0.92), (cx - rx * 0.78, cy + ry * 0.2)]), 40)
    if kind == "onion":
        return union(m_ellipse(cx, cy + ry * 0.1, rx, ry * 0.88), m_poly([(cx - rx * 0.4, cy - ry * 0.55), (cx + rx * 0.4, cy - ry * 0.55), (cx, cy - ry * 1.18)], 10))
    if kind == "cube": return m_super(cx, cy, rx * 0.98, ry * 0.9, 7)
    if kind == "star": return soften(m_poly(star_pts(cx, cy + ry * 0.08, rx * 1.15, rx * 0.68, 5)), 40)
    if kind == "flat": return m_super(cx, cy + ry * 0.2, rx * 1.3, ry * 0.68, 2.3)
    if kind == "tall": return m_super(cx, cy, rx * 0.8, ry * 1.08, 2.4)
    if kind == "lumpy":
        return soften(union(m_ellipse(cx, cy, rx * 0.95, ry * 0.92), *[m_ellipse(cx + rx * 0.85 * math.cos(a), cy + ry * 0.82 * math.sin(a), rx * 0.24, rx * 0.24) for a in np.linspace(0, 6.28, 10)[:-1]]), 8)
    raise KeyError(kind)

def finish(f):
    sil = f.sil.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MaxFilter(7))
    m = (np.asarray(sil.filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255)[..., None] * 0.92
    a = f.img[..., 3:4]
    out_a = a + m * (1 - a)
    ol = np.array(f.pal["outline"], np.float32)
    rgb = np.where(out_a > 0, (f.img[..., :3] * a + ol * m * (1 - a)) / np.maximum(out_a, 1e-5), 0)
    im = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(out_a * 255, 0, 255)]).astype(np.uint8), "RGBA")
    bb = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    crop = im.crop(bb)
    k = min((OUT - 2 * PAD) / crop.width, (OUT - 2 * PAD) / crop.height)
    crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    off = ((OUT - crop.width) // 2, (OUT - crop.height) // 2)
    canvas.paste(crop, off, crop)
    f.fit = (bb, k, off)   # design px -> out px: (p - bb[:2]) * k + off
    return canvas

def check(im):
    a = np.asarray(im)[:, :, 3]
    ys, xs = np.nonzero(a > 4)
    assert im.size == (OUT, OUT) and im.mode == "RGBA"
    e = PAD - 4
    assert a[:e].max() == 0 and a[-e:].max() == 0 and a[:, :e].max() == 0 and a[:, -e:].max() == 0, "touches margin"
