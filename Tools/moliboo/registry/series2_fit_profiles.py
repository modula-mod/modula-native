#!/usr/bin/env python3
"""Adds rig-derived fit profiles (validated: false) for native Series 2 (#116–215) to moliboo_accessory_fits.json.

Mirrors MascotRig.stock(_:) for spec-driven kinds exactly (anchor = headTop, width = hatWidth, scale = hatScale).
The measured pass (MOL03VisualAcceptanceTests with MOLIBOO_FIT_EXPORT) replaces these and sets `validated`
once Xcode runs are allowed. Usage: series2_fit_profiles.py <repo-root>
"""
import json, math, re, sys, pathlib
ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
SRC = (ROOT / "ios/Modula/DesignSystem/Mascot/MolibooSeries2.swift").read_text()
FITS = ROOT / "ios/Modula/Resources/Moliboo/moliboo_accessory_fits.json"
REG = json.loads((ROOT / "ios/Modula/Resources/Moliboo/moliboo_registry.json").read_text())
SHAPE = {"cloud": "cloud", "drop": "drop", "wisp": "drop", "dome": "dome", "pebble": "pebble", "square": "square",
         "star": "star", "tall": "tall", "pear": "tall", "bell": "tall", "crystal": "tall", "wide": "wide"}

def chord(shape, bw, bh, top, y, corner=0.24):
    u = (y - top) / max(bh, 0.01)
    if not (0 < u < 1): return 0
    dy = abs(u - 0.5) * 2
    if shape == "square":
        edge = max(0.2, 1 - corner * 2 / max(bh, 0.01))
        if dy <= edge: return bw
        k = (dy - edge) / max(1 - edge, 0.01)
        return bw * (0.55 + 0.45 * math.sqrt(max(0, 1 - k * k)))
    if shape == "drop":
        if u < 0.66: return bw * math.sin(u / 0.66 * math.pi / 2)
        k = (u - 0.66) / 0.34; return bw * math.sqrt(max(0, 1 - k * k))
    if shape == "dome":
        if u < 0.78:
            k = (0.78 - u) / 0.78; return bw * math.sqrt(max(0, 1 - k * k))
        return bw * 0.96
    if shape == "cloud":
        return bw * (0.92 if u > 0.55 else 0.98 * math.sqrt(max(0, 1 - ((0.55 - u) / 0.6) ** 2)))
    if shape == "star": return bw * 0.62 * math.sqrt(max(0, 1 - dy * dy))
    return bw * math.sqrt(max(0, 1 - dy * dy))

def r4(v): return round(v * 10000) / 10000
ids = {c["key"]: c["id"] for c in REG["characters"]}
ORIG = FITS.read_text()
fits = json.loads(ORIG)
n = 0
for m in re.finditer(r"t\[\.(\w+)\] = MolibooSpec\((.*)\)\s*$", SRC, re.M):
    key, b = m.group(1), m.group(2)
    body = re.search(r"body: \.(\w+)", b).group(1)
    w, h = map(float, re.search(r"size: CGSize\(width: ([\d.]+), height: ([\d.]+)\)", b).groups())
    hs = float((re.search(r"hatScale: ([\d.]+)", b) or [0, 1])[1])
    hm = re.search(r"hatMaxWidth: ([\d.]+)", b); hm = float(hm.group(1)) if hm else 9
    hx = re.search(r"headTopExtra: ([\d.]+)", b)
    shape = SHAPE.get(body, "round")
    dropish = body in ("drop", "star")
    by = 0.04 if dropish else 0.10
    ey = 0.10 if dropish else 0.04
    es = 0.21
    top = by - h / 2
    eye_top = ey - es * 0.62
    head = top + float(hx.group(1)) if hx else min(top + 0.03, eye_top - 0.01)
    sink = max(0, min(0.06, eye_top - 0.02 - head))
    width = min(hm, max(0.34, chord(shape, w, h, top, head + 0.1) * 0.98), 0.74) * hs
    fits["profiles"][f"fit/{key}"] = {
        "accessoryId": fits["accessoryId"], "anchor": {"x": 0, "y": r4(head)}, "characterId": ids[key],
        "eyeClearance": r4(eye_top - head), "followHeadMotion": True, "layer": "front",
        "occlusion": "head-top props hide while a hat is worn; ears, horns and halos stay in their own layers",
        "rotation": 0, "scale": r4(hs), "sink": r4(sink), "validated": False, "width": r4(width), "zIndex": 30}
    if hm < 9: fits["profiles"][f"fit/{key}"]["maxWidth"] = hm
    n += 1
if n != 100: raise SystemExit(f"expected 100 Series 2 specs, found {n}")
# Match Foundation's JSONEncoder output (.prettyPrinted, .sortedKeys) so the diff stays additive.
text = json.dumps(fits, indent=2, sort_keys=True, ensure_ascii=False).replace('": ', '" : ').replace("/", "\\/")
FITS.write_text(text + ("\n" if ORIG.endswith("\n") else ""))
print(f"fit profiles: {len(fits['profiles'])} (+{n} Series 2, validated=false)")
