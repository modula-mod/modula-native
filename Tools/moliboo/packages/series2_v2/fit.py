"""Python mirror of MascotRig anchors + a few MascotWearPainter items, to verify wardrobe fit on portraits."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

class Rig:
    def __init__(s, d):
        s.__dict__.update(d)
        s.headTopOverride = d.get("headTop")
        s.hatScale = d.get("hatScale", 1.0)
        s.hatMaxWidth = d.get("hatMaxWidth")
    bodyTop = property(lambda s: s.bodyY - s.bodyH / 2)
    bodyBottom = property(lambda s: s.bodyY + s.bodyH / 2)
    eyeTop = property(lambda s: s.eyeY - s.eyeSize * 0.62)
    eyeBottom = property(lambda s: s.eyeY + s.eyeSize * 0.62)
    faceBottom = property(lambda s: s.mouthY + 0.07)
    faceHalfWidth = property(lambda s: s.eyeSpread + s.eyeSize * 0.62)
    @property
    def headTop(s): return s.headTopOverride if s.headTopOverride is not None else min(s.bodyTop + 0.03, s.eyeTop - 0.01)
    @property
    def hatSink(s): return max(0, min(0.06, s.eyeTop - 0.02 - s.headTop))
    neckY = property(lambda s: s.faceBottom + 0.012)
    backAnchorY = property(lambda s: s.bodyY - s.bodyH * 0.08)
    def chord(s, y):
        u = (y - s.bodyTop) / max(s.bodyH, 0.01)
        if not 0 < u < 1: return 0
        dy = abs(u - 0.5) * 2
        sh = s.shape
        if sh in ("square", "roundedRect"):
            edge = max(0.2, 1 - 0.24 * 2 / max(s.bodyH, .01))
            if dy <= edge: return s.bodyW
            kk = (dy - edge) / max(1 - edge, .01); return s.bodyW * (0.55 + 0.45 * math.sqrt(max(0, 1 - kk * kk)))
        if sh == "drop":
            if u < 0.66: return s.bodyW * math.sin(u / 0.66 * math.pi / 2)
            kk = (u - 0.66) / 0.34; return s.bodyW * math.sqrt(max(0, 1 - kk * kk))
        if sh == "dome":
            if u < 0.78: kk = (0.78 - u) / 0.78; return s.bodyW * math.sqrt(max(0, 1 - kk * kk))
            return s.bodyW * 0.96
        if sh == "cloud": return s.bodyW * (0.92 if u > 0.55 else 0.98 * math.sqrt(max(0, 1 - ((0.55 - u) / 0.6) ** 2)))
        if sh == "star": return s.bodyW * 0.62 * math.sqrt(max(0, 1 - dy * dy))
        return s.bodyW * math.sqrt(max(0, 1 - dy * dy))
    @property
    def hatWidth(s):
        fit = max(0.34, s.chord(s.headTop + 0.1) * 0.98)
        return min(s.hatMaxWidth if s.hatMaxWidth is not None else 9, fit, 0.74) * s.hatScale

def glossy(base, mask, outline=(60, 40, 60)):
    """Fill mask with a soft vertical gloss + outline onto RGBA `base`."""
    W, H = base.size
    a = np.asarray(mask).astype(np.float32) / 255
    bb = mask.getbbox()
    if not bb: return
    yy = np.linspace(0, 1, H)[:, None] * np.ones((1, W))
    t = np.clip((yy * H - bb[1]) / max(1, bb[3] - bb[1]), 0, 1)
    col = np.array(outline, np.float32)
    return t

def paint_part(img, mask, col, ol=(58, 40, 58), gloss=True):
    W, H = img.size
    m = np.asarray(mask).astype(np.float32)[..., None] / 255
    bb = mask.getbbox()
    if not bb: return
    t = np.clip((np.arange(H)[:, None] - bb[1]) / max(1, bb[3] - bb[1]), 0, 1)[..., None] * np.ones((1, W, 1))
    c = np.array(col, np.float32); light = c + (255 - c) * 0.5; dark = c * 0.7
    rgb = light * (1 - t) ** 2 + c * 2 * t * (1 - t) + dark * t ** 2
    edge = np.asarray(mask.filter(ImageFilter.MaxFilter(5))).astype(np.float32)[..., None] / 255
    src = np.asarray(img).astype(np.float32)
    ring = np.clip(edge - m, 0, 1)
    out = src.copy()
    for layer, colr in ((ring, np.array(ol, np.float32)), (m, rgb)):
        a = layer
        out[..., :3] = out[..., :3] * (1 - a) + colr * a
        out[..., 3:] = np.maximum(out[..., 3:], a * 255)
    if gloss:
        hb = Image.new("L", img.size, 0)
        ImageDraw.Draw(hb).ellipse([bb[0] + (bb[2] - bb[0]) * 0.18, bb[1] + (bb[3] - bb[1]) * 0.12, bb[0] + (bb[2] - bb[0]) * 0.5, bb[1] + (bb[3] - bb[1]) * 0.34], fill=255)
        hm = (np.asarray(hb).astype(np.float32) / 255 * np.asarray(mask).astype(np.float32) / 255)[..., None] * 0.6
        out[..., :3] = out[..., :3] * (1 - hm) + 255 * hm
    img.paste(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA"))

def dress(portrait, rd, s=200, hat="beanie", acc="glasses", hatcol=(236, 84, 104), acccol=(70, 110, 220)):
    """Render a portrait on the 2.0s x 1.9s rig canvas with a hat + accessory placed by the rig.
    Returns (image, report)."""
    rig = Rig(rd)
    W, H = int(2.0 * s), int(1.9 * s)
    cx, cy = W / 2, H / 2
    P = lambda x, y: (cx + x * s, cy + y * s)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    po = rd["portrait"]; side = int(round(po["side"] * s))
    pim = portrait.convert("RGBA").resize((side, side), Image.Resampling.LANCZOS)
    ox, oy = int(round(cx + po["cx"] * s - side / 2)), int(round(cy + po["cy"] * s - side / 2))
    body_alpha = Image.new("L", (W, H), 0); body_alpha.paste(pim.getchannel("A"), (ox, oy))
    # back layer: backpack / cape behind
    if acc == "backpack":
        m = Image.new("L", (W, H), 0); d = ImageDraw.Draw(m)
        bw = min(0.5, rig.bodyW * 0.62)
        x0, y0 = P(-rig.bodyW / 2 - 0.06, rig.backAnchorY - 0.1); x1, y1 = P(-rig.bodyW / 2 + bw * 0.6, rig.backAnchorY + 0.28)
        d.rounded_rectangle([x0, y0, x1, y1], radius=0.08 * s, fill=255)
        paint_part(img, m, acccol)
    img.alpha_composite(pim, (ox, oy))
    rep = {}
    hm = Image.new("L", (W, H), 0)
    if hat:
        brim = rig.headTop + rig.hatSink
        Wd = rig.hatWidth
        d = ImageDraw.Draw(hm)
        if hat == "beanie":
            x0, y0 = P(-Wd * 0.5, brim - Wd * 0.55); x1, y1 = P(Wd * 0.5, brim + Wd * 0.12)
            d.chord([x0, y0, x1, y1 + (y1 - y0) * 0.6], 180, 360, fill=255)
            d.rounded_rectangle([*P(-Wd * 0.53, brim - Wd * 0.1), *P(Wd * 0.53, brim + Wd * 0.06)], radius=0.04 * s, fill=255)
            d.ellipse([*P(-0.07, brim - Wd * 0.68), *P(0.07, brim - Wd * 0.54)], fill=255)
        elif hat == "crown":
            pts = [P(-Wd * 0.45, brim + 0.02), P(-Wd * 0.48, brim - Wd * 0.4), P(-Wd * 0.24, brim - Wd * 0.18), P(0, brim - Wd * 0.5),
                   P(Wd * 0.24, brim - Wd * 0.18), P(Wd * 0.48, brim - Wd * 0.4), P(Wd * 0.45, brim + 0.02)]
            d.polygon(pts, fill=255)
        paint_part(img, hm, hatcol)
        # attach check: hat bottom band overlaps the portrait silhouette
        band = Image.new("L", (W, H), 0)
        ImageDraw.Draw(band).rectangle([*P(-Wd * 0.3, brim - 0.02), *P(Wd * 0.3, brim + 0.03)], fill=255)
        ov = np.asarray(band).astype(bool) & (np.asarray(body_alpha) > 128)
        rep["hatAttached"] = float(ov.sum() / max(1, np.asarray(band).astype(bool).sum()))
    # eye zones (true eyes)
    ez = Image.new("L", (W, H), 0); de = ImageDraw.Draw(ez)
    r_eye = rig.eyeSize / 2 * 1.08 / 1.24 * 1.0
    for sd in (-1, 1):
        x, y = P(sd * rig.eyeSpread, rig.eyeY); R = r_eye * s
        de.ellipse([x - R, y - R, x + R, y + R], fill=255)
    rep["hatEyeCover"] = float((np.asarray(hm).astype(bool) & np.asarray(ez).astype(bool)).sum() / max(1, np.asarray(ez).astype(bool).sum()))
    if acc == "glasses":
        r = rig.eyeSize * 0.62 + 0.03
        g = Image.new("L", (W, H), 0); dg = ImageDraw.Draw(g)
        for sd in (-1, 1):
            x, y = P(sd * rig.eyeSpread, rig.eyeY)
            dg.ellipse([x - r * s, y - r * s, x + r * s, y + r * s], outline=255, width=max(3, int(0.03 * s)))
        dg.line([P(-rig.eyeSpread + r, rig.eyeY), P(rig.eyeSpread - r, rig.eyeY)], fill=255, width=max(3, int(0.025 * s)))
        paint_part(img, g, acccol, gloss=False)
        rep["glassesOnFace"] = float((np.asarray(g).astype(bool) & (np.asarray(body_alpha) > 128)).sum() / max(1, np.asarray(g).astype(bool).sum()))
    if acc == "scarf":
        ny = rig.neckY + 0.015; half = rig.faceHalfWidth + 0.08
        side_y = max(ny - 0.1, rig.eyeBottom + 0.05)
        ys = [side_y + (ny + 0.035 - side_y) * (1 - (2 * i / 40 - 1) ** 2) for i in range(41)]
        pts = [P(-half - 0.06 + (2 * half + 0.12) * i / 40, ys[i]) for i in range(41)]
        g = Image.new("L", (W, H), 0); dg = ImageDraw.Draw(g)
        dg.line(pts, fill=255, width=int(0.075 * s), joint="curve")
        dg.rounded_rectangle([*P(0.1, ny + 0.0), *P(0.2, ny + 0.2)], radius=0.03 * s, fill=255)
        # clip to inflated(1.12) of the rig body ellipse-ish: approximate by dilated real silhouette
        clip = body_alpha.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MaxFilter(int(0.06 * s) | 1))
        g = Image.fromarray(np.minimum(np.asarray(g), np.asarray(clip)))
        paint_part(img, g, acccol)
        rep["scarfOnBody"] = float((np.asarray(g) > 0).sum() > 0)
    # canvas clip check: nothing touches the canvas edge
    a = np.asarray(img)[..., 3]
    rep["clear"] = bool(a[:2].max() == 0 and a[-2:].max() == 0 and a[:, :2].max() == 0 and a[:, -2:].max() == 0)
    return img, rep
