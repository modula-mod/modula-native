#!/usr/bin/env python3
"""Native Series 2 fit sheet. Each of #116-215 is rebuilt from its MolibooSpec (MolibooSeries2.swift): body shape,
size, offsets and eye/mouth anchors exactly as MascotRig.stock(_:) derives them for spec kinds, drawn as a glossy
rig-true silhouette with stubby nubs + feet. Pack-2 wearables are placed ONLY from rig anchors. Head-top signature
parts hide under a hat in the app, so the hatted silhouette is the real fitted outline."""
import sys, re, json, math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, str(Path(__file__).parent))
from fit import Rig
from fitsheet import place, face_safe

S = 110
SRC = Path(sys.argv[2] if len(sys.argv) > 2 else "swift/MolibooSeries2.swift").read_text()
SHAPE = {"cloud": "cloud", "drop": "drop", "wisp": "drop", "dome": "dome", "pebble": "pebble", "square": "square",
         "star": "star", "tall": "tall", "pear": "tall", "bell": "tall", "crystal": "tall", "wide": "wide"}
prof = {m[0]: int(m[1]) for m in re.findall(r"\.(\w+): \.init\(number: (\d+)", SRC)}
specs = []
for m in re.finditer(r"t\[\.(\w+)\] = MolibooSpec\((.*)\)\s*$", SRC, re.M):
    key, b = m.group(1), m.group(2)
    body = re.search(r"body: \.(\w+)", b).group(1)
    w, h = map(float, re.search(r"size: CGSize\(width: ([\d.]+), height: ([\d.]+)\)", b).groups())
    mid = tuple(int(float(v) * 255) for v in re.search(r"\.spec\(c\(([\d.]+), ([\d.]+), ([\d.]+)\)", b).groups())
    hx = re.search(r"headTopExtra: ([\d.]+)", b)
    hm = re.search(r"hatMaxWidth: ([\d.]+)", b)
    dropish = body in ("drop", "star")
    by, ey = (0.04, 0.10) if dropish else (0.10, 0.04)
    rd = dict(shape=SHAPE.get(body, "round"), bodyW=w, bodyH=h, bodyY=by, eyeY=ey, eyeSize=0.21, eyeSpread=0.19,
              mouthY=0.22, footY=by + h / 2, hatScale=float((re.search(r"hatScale: ([\d.]+)", b) or [0, 1])[1]),
              hatMaxWidth=float(hm.group(1)) if hm else None, headTop=(by - h / 2 + float(hx.group(1))) if hx else None)
    specs.append(dict(key=key, n=prof[key], body=body, rd=rd, col=mid, feet="floats: true" not in b and "feet: false" not in b,
                      nubs=".nubs(" in b))
specs.sort(key=lambda s: s["n"])
assert len(specs) == 100, len(specs)

def body_mask(rd, W, H, s):
    m = Image.new("L", (W, H), 0); d = ImageDraw.Draw(m)
    bw, bh, by = rd["bodyW"] * s, rd["bodyH"] * s, rd["bodyY"] * s
    x0, y0, x1, y1 = W / 2 - bw / 2, H / 2 + by - bh / 2, W / 2 + bw / 2, H / 2 + by + bh / 2
    sh = rd["shape"]
    if sh == "square": d.rounded_rectangle([x0, y0, x1, y1], radius=0.24 * s, fill=255)
    elif sh == "drop":
        pts = []
        for i in range(80):
            u = i / 79; yy = y0 + u * bh
            c = math.sin(u / 0.66 * math.pi / 2) if u < 0.66 else math.sqrt(max(0, 1 - ((u - 0.66) / 0.34) ** 2))
            pts.append((W / 2 + c * bw / 2, yy))
        d.polygon(pts + [(W - x, y) for x, y in reversed(pts)], fill=255)
    elif sh == "dome":
        d.pieslice([x0, y0, x1, y0 + 2 * 0.78 * bh], 180, 360, fill=255)
        d.rounded_rectangle([x0 + 0.02 * bw, y0 + 0.76 * bh, x1 - 0.02 * bw, y1], radius=0.08 * s, fill=255)
        d.rectangle([x0, y0 + 0.76 * bh, x1, y0 + 0.8 * bh], fill=255)
    elif sh == "pebble":
        d.ellipse([x0, y0 + 0.04 * bh, x1 - 0.04 * bw, y1], fill=255); d.ellipse([x0 + 0.06 * bw, y0, x1, y1 - 0.06 * bh], fill=255)
    else: d.ellipse([x0, y0, x1, y1], fill=255)
    return m

def figure(sp, s):
    rd = sp["rd"]; W, H = int(2.0 * s), int(1.9 * s)
    rig = Rig(rd)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    col = sp["col"]; dark = tuple(int(c * 0.62) for c in col); ol = tuple(int(c * 0.42) for c in col)
    bw, bh, by = rd["bodyW"] * s, rd["bodyH"] * s, rd["bodyY"] * s
    if sp["nubs"]:  # stubby arms tucked behind the body edge at hand height (series2Part .nubs, back layer)
        for sd in (-1, 1):
            hx = W / 2 + sd * max(0.2, rig.chord(rd["bodyY"] + rd["bodyH"] * 0.14) / 2) * 0.96 * s
            hy = H / 2 + (rd["bodyY"] + rd["bodyH"] * 0.14) * s
            d.ellipse([hx - 0.085 * s, hy - 0.06 * s, hx + 0.085 * s, hy + 0.06 * s], fill=col + (255,), outline=ol + (255,), width=2)
    if sp["feet"]:
        fy = H / 2 + rd["footY"] * s
        for sd in (-1, 1):
            fx = W / 2 + sd * bw * 0.2
            d.ellipse([fx - 0.1 * s, fy - 0.07 * s, fx + 0.1 * s, fy + 0.04 * s], fill=dark + (255,), outline=ol + (255,), width=2)
    m = body_mask(rd, W, H, s)
    shade = Image.new("RGBA", (W, H), col + (255,))
    g = Image.new("L", (W, H), 0); ImageDraw.Draw(g).ellipse([W / 2 - bw * 0.7, H / 2 + by + bh * 0.05, W / 2 + bw * 0.7, H / 2 + by + bh * 1.2], fill=90)
    shade = Image.composite(Image.new("RGBA", (W, H), dark + (255,)), shade, g.filter(ImageFilter.GaussianBlur(s * 0.08)))
    hl = Image.new("L", (W, H), 0); ImageDraw.Draw(hl).ellipse([W / 2 - bw * 0.32, H / 2 + by - bh * 0.44, W / 2 - bw * 0.02, H / 2 + by - bh * 0.28], fill=150)
    shade = Image.composite(Image.new("RGBA", (W, H), (255, 255, 255, 255)), shade, hl.filter(ImageFilter.GaussianBlur(s * 0.02)))
    edge = m.filter(ImageFilter.MaxFilter(5))
    im.paste(Image.new("RGBA", (W, H), ol + (255,)), (0, 0), edge)
    im.paste(shade, (0, 0), m)
    d = ImageDraw.Draw(im)
    for sd in (-1, 1):
        x, y, r = W / 2 + sd * rd["eyeSpread"] * s, H / 2 + rd["eyeY"] * s, rd["eyeSize"] * 0.53 * s
        d.ellipse([x - r, y - r, x + r, y + r], fill=(30, 22, 40, 255)); d.ellipse([x - r * 0.6, y - r * 0.65, x - r * 0.1, y - r * 0.15], fill=(255, 255, 255, 255))
    d.arc([W / 2 - 0.08 * s, H / 2 + (rd["mouthY"] - 0.05) * s, W / 2 + 0.08 * s, H / 2 + (rd["mouthY"] + 0.03) * s], 20, 160, fill=(60, 40, 50, 255), width=3)
    return im, m, rig

man = json.load(open("items/wearables.json"))["items"]
items = {m["id"]: (m, Image.open(f"items/{m['file']}").convert("RGBA")) for m in man}
hats = [m["id"] for m in man if m["anchor"] == "hat"]
faces = [m["id"] for m in man if m["anchor"] == "face"]
necks = [m["id"] for m in man if m["anchor"] == "neck"]
backs = [m["id"] for m in man if m["anchor"] == "back"]
cells, bad, report = [], [], []
for i, sp in enumerate(specs):
    base, sil_m, rig = figure(sp, S)
    W, H = base.size
    picks = [hats[i % len(hats)], necks[i % len(necks)], backs[i % len(backs)]] + ([faces[i % len(faces)]] if i % 2 else [])
    fs = face_safe(rig, W, H, S)
    lay = {p: place(base, items[p][1], items[p][0], rig, S, clip=None if items[p][0]["anchor"] in ("face", "back") else fs) for p in picks}
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for p in picks:
        if items[p][0]["anchor"] == "back": out.alpha_composite(lay[p])
    out.alpha_composite(base)
    for p in picks:
        if items[p][0]["anchor"] != "back": out.alpha_composite(lay[p])
    sil = np.asarray(sil_m) > 128
    eyes = Image.new("L", (W, H), 0); de = ImageDraw.Draw(eyes)
    for sd in (-1, 1):
        x, y, r = W / 2 + sd * rig.eyeSpread * S, H / 2 + rig.eyeY * S, rig.eyeSize / 2 * 0.87 * S
        de.ellipse([x - r, y - r, x + r, y + r], fill=255)
    eyes = np.asarray(eyes) > 0
    rep = {"key": sp["key"], "n": sp["n"], "items": picks}
    for p in picks:
        meta = items[p][0]; a = np.asarray(lay[p].getchannel("A")) > 128
        if meta["anchor"] == "hat":
            ys = np.nonzero(a.any(1))[0]; band = a.copy(); band[: max(0, ys.max() - int(0.05 * S))] = False
            rep["hatAttached"] = round(float((band & sil).sum() / max(1, band.sum())), 2)
            rep["hatEyeCover"] = round(float((a & eyes).sum() / max(1, eyes.sum())), 3)
            rep["hatFloatPx"] = int(max(0, (np.nonzero(sil.any(1))[0].min()) - ys.max()))
        elif meta["anchor"] in ("neck", "back"):
            rep[meta["anchor"] + "OnBody"] = round(float((a & sil).sum() / max(1, a.sum())), 2)
    A = np.asarray(out)[..., 3]
    rep["clear"] = bool(A[:1].max() == 0 and A[-1:].max() == 0 and A[:, :1].max() == 0 and A[:, -1:].max() == 0)
    ok = rep["clear"] and rep["hatAttached"] >= 0.35 and rep["hatEyeCover"] <= 0.02 and rep["hatFloatPx"] == 0 and rep["neckOnBody"] >= 0.25 and rep["backOnBody"] >= 0.05
    rep["ok"] = ok; report.append(rep)
    if not ok: bad.append(rep)
    cells.append((f"#{sp['n']} {sp['key'].capitalize()} · {sp['body']}", out, ok))
cols = 10; cw, ch = int(2.0 * S), int(1.9 * S) + 16
sheet = Image.new("RGB", (cols * cw, ((len(cells) + cols - 1) // cols) * ch + 34), (246, 243, 250)); d = ImageDraw.Draw(sheet)
d.text((8, 6), "Native Series 2 fit sheet (#116-215): MolibooSpec silhouettes via MascotRig.stock formulas; pack-2 hat/neck/back(+face) placed only from rig anchors.", fill=(30, 20, 40))
d.text((8, 19), "Frame = full 2.0s x 1.9s canvas. Red label = failed auto-check (clipped at canvas edge, hat floating/off head, eyes covered, neck/back off body).", fill=(30, 20, 40))
for i, (lab, im, ok) in enumerate(cells):
    r, c = divmod(i, cols); x, y = c * cw, 34 + r * ch
    tile = Image.new("RGBA", im.size, (255, 255, 255, 255)); tile.alpha_composite(im)
    sheet.paste(tile.convert("RGB"), (x, y)); d.rectangle([x, y, x + cw - 1, y + ch - 17], outline=(220, 214, 232))
    d.text((x + 4, y + ch - 15), lab[:34], fill=(40, 30, 50) if ok else (220, 30, 30))
sheet.save(sys.argv[1])
json.dump(report, open(Path(sys.argv[1]).with_suffix(".json"), "w"), indent=1)
print("ok", 100 - len(bad), "bad", len(bad)); [print(b) for b in bad]
