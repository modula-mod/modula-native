#!/usr/bin/env python3
"""Fit sheet: every Series 2 portrait wearing pack-2 items placed ONLY from rig.json anchors (MascotRig formulas),
plus rig-true silhouettes of sample originals. Writes a PNG and prints per-figure fit metrics."""
import sys, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, str(Path(__file__).parent))
from fit import Rig

S_PX = 150
def ref_and_anchor(rig, anchor):
    if anchor == "hat": return rig.hatWidth, (0, rig.headTop + rig.hatSink)
    if anchor == "face": return 2 * rig.faceHalfWidth + 0.08, (0, rig.eyeY)
    if anchor == "neck": return max(0.3, rig.chord(rig.neckY + 0.06)), (0, rig.neckY + 0.02)
    if anchor == "back": return rig.bodyW, (0, rig.backAnchorY)

def face_safe(rig, W, H, s):
    m = Image.new("L", (W, H), 255); d = ImageDraw.Draw(m)
    top, bot, w = rig.eyeTop - 0.012, rig.faceBottom, rig.faceHalfWidth + 0.012
    d.rounded_rectangle([W / 2 - w * s, H / 2 + top * s, W / 2 + w * s, H / 2 + bot * s], radius=0.1 * s, fill=0)
    return m

def place(canvas, item_im, meta, rig, s, clip=None):
    ref, (ax, ay) = ref_and_anchor(rig, meta["anchor"])
    k = ref * s / meta["refPx"]
    sz = max(1, int(round(meta["size"] * k)))
    im = item_im.resize((sz, sz), Image.Resampling.LANCZOS)
    W, H = canvas.size
    ox = int(round(W / 2 + ax * s - meta["anchorPx"][0] * k)); oy = int(round(H / 2 + ay * s - meta["anchorPx"][1] * k))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0)); layer.alpha_composite(im, (max(0, ox), max(0, oy)), (max(0, -ox), max(0, -oy)))
    if clip is not None:
        a = np.minimum(np.asarray(layer.getchannel("A")), np.asarray(clip)); layer.putalpha(Image.fromarray(a))
    return layer

def dress(portrait, rd, items, picks, s=S_PX):
    rig = Rig(rd); W, H = int(2.0 * s), int(1.9 * s)
    po = rd["portrait"]; side = int(round(po["side"] * s))
    pim = portrait.resize((side, side), Image.Resampling.LANCZOS)
    ox, oy = int(round(W / 2 + po["cx"] * s - side / 2)), int(round(H / 2 + po["cy"] * s - side / 2))
    body = Image.new("RGBA", (W, H), (0, 0, 0, 0)); body.alpha_composite(pim, (ox, oy))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fs = face_safe(rig, W, H, s)
    layers = {}
    for p in picks:
        meta, im = items[p]
        layers[p] = place(out, im, meta, rig, s, clip=None if meta["anchor"] in ("face", "back") else fs)
    for p in picks:
        if items[p][0]["anchor"] == "back": out.alpha_composite(layers[p])
    out.alpha_composite(body)
    for p in picks:
        if items[p][0]["anchor"] != "back": out.alpha_composite(layers[p])
    # metrics
    sil = np.asarray(body.getchannel("A")) > 128
    rep = {}
    eyes = Image.new("L", (W, H), 0); de = ImageDraw.Draw(eyes)
    for sd in (-1, 1):
        x, y, r = W / 2 + sd * rig.eyeSpread * s, H / 2 + rig.eyeY * s, rig.eyeSize / 2 * 0.87 * s
        de.ellipse([x - r, y - r, x + r, y + r], fill=255)
    eyes = np.asarray(eyes) > 0
    for p in picks:
        meta = items[p][0]; a = np.asarray(layers[p].getchannel("A")) > 128
        if meta["anchor"] == "hat":
            ys = np.nonzero(a.any(1))[0]; band = a.copy(); band[: max(0, ys.max() - int(0.05 * s))] = False
            rep["hatAttached"] = round(float((band & sil).sum() / max(1, band.sum())), 2)
            rep["hatEyeCover"] = round(float((a & eyes).sum() / max(1, eyes.sum())), 3)
        elif meta["anchor"] in ("neck", "back"):
            rep[meta["anchor"] + "OnBody"] = round(float((a & sil).sum() / max(1, a.sum())), 2)
    A = np.asarray(out)[..., 3]
    rep["clear"] = bool(A[:1].max() == 0 and A[-1:].max() == 0 and A[:, :1].max() == 0 and A[:, -1:].max() == 0)
    return out, rep

def original_silhouette(spec, s=S_PX):
    """Rig-true silhouette of an original (#001-100): body ellipse + eyes at the rig's own numbers."""
    W, H = int(2.0 * s), int(1.9 * s)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    bw, bh, by = spec["bodyW"], spec["bodyH"], spec["bodyY"]
    d.ellipse([W / 2 - bw / 2 * s, H / 2 + (by - bh / 2) * s, W / 2 + bw / 2 * s, H / 2 + (by + bh / 2) * s], fill=tuple(spec["col"]) + (255,), outline=(70, 50, 70, 255), width=3)
    d.ellipse([W / 2 - bw * 0.3 * s, H / 2 + (by - bh * 0.42) * s, W / 2 - bw * 0.05 * s, H / 2 + (by - bh * 0.3) * s], fill=(255, 255, 255, 150))
    for sd in (-1, 1):
        x, y, r = W / 2 + sd * spec["eyeSpread"] * s, H / 2 + spec["eyeY"] * s, spec["eyeSize"] * 0.53 * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=(30, 22, 40, 255)); d.ellipse([x - r * 0.6, y - r * 0.65, x - r * 0.1, y - r * 0.15], fill=(255, 255, 255, 255))
    d.arc([W / 2 - 0.08 * s, H / 2 + (spec["mouthY"] - 0.05) * s, W / 2 + 0.08 * s, H / 2 + (spec["mouthY"] + 0.03) * s], 20, 160, fill=(60, 40, 50, 255), width=3)
    return im
