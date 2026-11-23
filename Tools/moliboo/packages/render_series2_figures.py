#!/usr/bin/env python3
"""Glossy 2D Series 2 figures in the same recipe as ModulaMascotFigure.

#001–115 are drawn in SwiftUI: a soft radial body, a white specular, bead eyes
with two catch-lights, blush, and one signature shape. This script paints that
same still figure for #116–215. Colour comes from the poster cutout; the shape
is simplified, not traced. Output is a padded 640² transparent PNG plus figure.svg.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
REG = json.loads((ROOT / "ios/Modula/Resources/Moliboo/moliboo_registry.json").read_text())
SOURCES = ROOT / "Tools/moliboo/packages/series2/sources"
N = 640

# One signature shape per catalogue number. Poster 101 → #116.
FEATURE = {
    116: "curl", 117: "frills", 118: "wings", 119: "shell", 120: "tentacles",
    121: "spikes", 122: "scarf", 123: "shell", 124: "crest", 125: "ears",
    126: "wings", 127: "cloud", 128: "flame", 129: "cloud", 130: "sprout",
    131: "ears", 132: "swirl", 133: "wings", 134: "hat", 135: "star",
    136: "flame", 137: "flame", 138: "flame", 139: "horn", 140: "flame",
    141: "flame", 142: "star", 143: "flame", 144: "shell", 145: "crest",
    146: "flower", 147: "sprout", 148: "flower", 149: "berry", 150: "leaf",
    151: "sprout", 152: "leaf", 153: "thorn", 154: "leaf", 155: "flower",
    156: "crystal", 157: "crystal", 158: "snow", 159: "ribbon", 160: "gem",
    161: "crystal", 162: "wings", 163: "snow", 164: "star", 165: "ribbon",
    166: "clock", 167: "gear", 168: "gear", 169: "horn", 170: "swirl",
    171: "clock", 172: "gear", 173: "ears", 174: "spool", 175: "note",
    176: "candy", 177: "swirl", 178: "candy", 179: "swirl", 180: "cloud",
    181: "candy", 182: "ears", 183: "swirl", 184: "bow", 185: "leaf",
    186: "quill", 187: "ears", 188: "quill", 189: "hat", 190: "curl",
    191: "quill", 192: "lantern", 193: "stamp", 194: "scroll", 195: "hat",
    196: "pixel", 197: "star", 198: "ears", 199: "hat", 200: "heart",
    201: "hat", 202: "swirl", 203: "antenna", 204: "pixel", 205: "star",
    206: "lantern", 207: "hat", 208: "star", 209: "ears", 210: "ribbon",
    211: "star", 212: "gem", 213: "hat", 214: "moon", 215: "wings",
}

# Real built-in palettes from ModulaMascotKind.builtInPalette, for the comparison row only.
ORIGINALS = [
    (1, "Pip", "frills", (255, 224, 240), (255, 158, 199), (219, 92, 148), (255, 107, 179), (148, 56, 102)),
    (2, "Moss", "belly", (230, 250, 199), (133, 214, 107), (56, 143, 71), (250, 245, 219), (31, 92, 46)),
    (3, "Nimbus", "cloud", (255, 255, 255), (224, 237, 255), (158, 189, 245), (158, 204, 255), (92, 117, 189)),
    (4, "Mochi", "ears", (250, 245, 255), (219, 209, 240), (163, 153, 199), (255, 179, 204), (102, 87, 128)),
    (5, "Sprout", "sprout", (255, 245, 184), (250, 209, 97), (209, 148, 56), (107, 199, 87), (128, 87, 31)),
    (6, "Ember", "flame", (255, 240, 128), (255, 148, 56), (235, 77, 31), (255, 219, 77), (148, 41, 20)),
    (7, "Tuck", "ears", (240, 209, 168), (179, 128, 87), (107, 71, 46), (255, 184, 71), (71, 41, 26)),
    (8, "Bloop", "tentacles", (245, 224, 255), (199, 148, 250), (133, 87, 219), (255, 168, 230), (97, 56, 158)),
    (9, "Bun", "ears", (255, 255, 255), (245, 240, 240), (214, 204, 204), (255, 189, 204), (128, 102, 102)),
    (10, "Pebble", "leaf", (235, 245, 255), (184, 209, 230), (128, 153, 184), (107, 199, 143), (77, 97, 122)),
    (11, "Tofu", "none", (255, 255, 250), (250, 245, 230), (224, 214, 189), (255, 184, 128), (143, 128, 102)),
    (12, "Comet", "star", (255, 250, 184), (255, 219, 71), (245, 153, 36), (115, 199, 255), (158, 102, 20)),
    (13, "Puff", "crest", (209, 245, 255), (128, 214, 250), (66, 148, 214), (255, 209, 92), (31, 92, 143)),
    (14, "Bolt", "pixel", (245, 250, 255), (209, 224, 240), (133, 153, 184), (77, 230, 242), (71, 92, 122)),
    (15, "Glim", "star", (209, 240, 143), (133, 194, 87), (77, 122, 51), (255, 240, 92), (46, 82, 31)),
]


def sample_palette(path: Path):
    im = np.asarray(Image.open(path).convert("RGBA"))
    pix = im[:, :, :3][im[:, :, 3] > 160].astype(np.float32)
    if pix.size == 0:
        pix = np.array([[180, 180, 190]], np.float32)
    lum = pix.mean(1)
    sat = pix.max(1) - pix.min(1)
    keep = (lum > 35) & (lum < 245) & (sat > 16)
    use = pix[keep] if keep.sum() > 40 else pix
    mid = np.median(use, 0)
    vivid = use[sat[keep] > np.quantile(sat[keep], 0.72)] if keep.sum() > 40 else use
    accent = np.median(vivid, 0) if len(vivid) else mid
    light = np.clip(mid * 0.35 + 255 * 0.65, 0, 255)
    dark = np.clip(mid * 0.55, 0, 255)
    outline = np.clip(dark * 0.55, 0, 255)
    return tuple(map(tuple, (light, mid, dark, accent, outline)))


def blend(img, mask, color):
    color = np.array(color, np.float32)
    m = mask.astype(np.float32)
    src = img[:, :, :3].astype(np.float32)
    a = img[:, :, 3].astype(np.float32) / 255
    out_a = m + a * (1 - m)
    out_rgb = np.where(out_a[..., None] > 0, (color * m[..., None] + src * (a * (1 - m))[..., None]) / np.maximum(out_a[..., None], 1e-4), 0)
    img[:, :, :3] = np.clip(out_rgb, 0, 255)
    img[:, :, 3] = np.clip(out_a * 255, 0, 255)


def ellipse(cx, cy, rx, ry):
    yy, xx = np.ogrid[:N, :N]
    return ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1


def body(img, cx, cy, rx, ry, light, mid, dark, outline):
    yy, xx = np.ogrid[:N, :N]
    nx = (xx - cx) / rx
    ny = (yy - cy) / ry
    r = np.sqrt(nx ** 2 + ny ** 2)
    inside = r <= 1
    gx = (xx - (cx - rx * 0.28)) / (rx * 1.35)
    gy = (yy - (cy - ry * 0.42)) / (ry * 1.35)
    g = np.clip(np.sqrt(gx ** 2 + gy ** 2), 0, 1)
    light, mid, dark = (np.array(c, np.float32).reshape(1, 1, 3) for c in (light, mid, dark))
    gg = g[..., None]
    col = light * (1 - gg) ** 2 + mid * (2 * gg * (1 - gg)) + dark * gg ** 2
    # bottom shade
    shade = np.clip((ny + 0.2) / 1.2, 0, 1)
    col = col * (1 - 0.28 * shade[..., None]) + dark * (0.28 * shade[..., None])
    m = inside.astype(np.float32)
    src = img[:, :, :3].astype(np.float32)
    a = img[:, :, 3].astype(np.float32) / 255
    out_a = m + a * (1 - m)
    out_rgb = np.where(out_a[..., None] > 0, (col * m[..., None] + src * (a * (1 - m))[..., None]) / np.maximum(out_a[..., None], 1e-4), 0)
    img[:, :, :3] = np.clip(out_rgb, 0, 255)
    img[:, :, 3] = np.clip(out_a * 255, 0, 255)
    ring = (r <= 1) & (r >= 0.94)
    blend(img, ring, outline)
    # specular
    spec = ellipse(cx - rx * 0.28, cy - ry * 0.32, rx * 0.22, ry * 0.1)
    blend(img, spec & inside, (255, 255, 255))
    dot = ellipse(cx - rx * 0.05, cy - ry * 0.42, rx * 0.045, rx * 0.045)
    blend(img, dot & inside, (255, 255, 255))


def eye(img, cx, cy, r, accent):
    # Same bead as MascotEye: a dark glossy eye, iris glow, two catch-lights. No white sclera.
    blend(img, ellipse(cx, cy, r, r * 1.06), (28, 20, 36))
    blend(img, ellipse(cx, cy + r * 0.28, r * 0.55, r * 0.32), tuple(np.clip(np.array(accent) * 0.45, 0, 255)))
    blend(img, ellipse(cx - r * 0.22, cy - r * 0.22, r * 0.28, r * 0.28), (255, 255, 255))
    blend(img, ellipse(cx + r * 0.28, cy + r * 0.26, r * 0.1, r * 0.1), (255, 255, 255))


def feature(img, kind, cx, cy, rx, ry, accent, dark, light):
    if kind in ("none", "belly"):
        if kind == "belly":
            blend(img, ellipse(cx, cy + ry * 0.35, rx * 0.38, ry * 0.22), light)
        return
    if kind == "ears":
        for side in (-1, 1):
            blend(img, ellipse(cx + side * rx * 0.42, cy - ry * 0.72, rx * 0.22, ry * 0.38), accent)
            blend(img, ellipse(cx + side * rx * 0.42, cy - ry * 0.68, rx * 0.1, ry * 0.18), light)
    elif kind == "frills":
        for side in (-1, 1):
            for i in range(3):
                blend(img, ellipse(cx + side * (rx * 0.85 + i * 8), cy - ry * 0.15 - i * 28, rx * 0.16, ry * 0.28), accent)
    elif kind == "wings":
        for side in (-1, 1):
            blend(img, ellipse(cx + side * rx * 0.95, cy - ry * 0.05, rx * 0.42, ry * 0.28), accent)
    elif kind == "shell":
        blend(img, ellipse(cx, cy - ry * 0.78, rx * 0.46, ry * 0.28), accent)
        blend(img, ellipse(cx, cy - ry * 0.7, rx * 0.2, ry * 0.1), light)
    elif kind == "tentacles":
        for i, side in enumerate((-1.1, -0.55, 0, 0.55, 1.1)):
            blend(img, ellipse(cx + side * rx * 0.55, cy + ry * 0.85, rx * 0.1, ry * 0.34), accent)
    elif kind == "spikes":
        for i in range(7):
            ang = -0.9 + i * 0.3
            blend(img, ellipse(cx + np.sin(ang) * rx * 0.95, cy - np.cos(ang) * ry * 0.9, 16, 22), accent)
    elif kind == "scarf":
        blend(img, ellipse(cx, cy + ry * 0.15, rx * 0.7, ry * 0.12), accent)
        blend(img, ellipse(cx + rx * 0.45, cy + ry * 0.45, rx * 0.12, ry * 0.28), accent)
    elif kind == "crest":
        blend(img, ellipse(cx, cy - ry * 0.85, rx * 0.16, ry * 0.32), accent)
    elif kind == "cloud":
        for dx, dy, rr in ((-0.35, -0.75, 0.28), (0.05, -0.88, 0.34), (0.4, -0.72, 0.26)):
            blend(img, ellipse(cx + dx * rx, cy + dy * ry, rx * rr, ry * rr), light)
    elif kind == "sprout":
        blend(img, ellipse(cx, cy - ry * 0.95, 10, ry * 0.22), dark)
        blend(img, ellipse(cx + 18, cy - ry * 1.05, rx * 0.16, ry * 0.1), accent)
    elif kind == "flame":
        blend(img, ellipse(cx, cy - ry * 0.95, rx * 0.22, ry * 0.34), accent)
        blend(img, ellipse(cx, cy - ry * 1.05, rx * 0.1, ry * 0.16), light)
    elif kind == "horn":
        blend(img, ellipse(cx, cy - ry * 0.95, rx * 0.1, ry * 0.36), accent)
    elif kind == "flower":
        for i in range(5):
            ang = i * np.pi * 2 / 5
            blend(img, ellipse(cx + np.cos(ang) * 28, cy - ry * 0.95 + np.sin(ang) * 18, 16, 16), accent)
        blend(img, ellipse(cx, cy - ry * 0.95, 10, 10), light)
    elif kind == "leaf":
        blend(img, ellipse(cx + 8, cy - ry * 0.95, rx * 0.22, ry * 0.12), accent)
    elif kind == "berry":
        blend(img, ellipse(cx, cy - ry * 0.9, 22, 22), accent)
        blend(img, ellipse(cx - 6, cy - ry * 0.96, 6, 6), light)
    elif kind == "thorn":
        blend(img, ellipse(cx, cy - ry * 0.92, 12, 28), accent)
    elif kind == "crystal":
        blend(img, ellipse(cx, cy - ry * 0.95, 18, 32), accent)
        blend(img, ellipse(cx - 4, cy - ry * 1.02, 6, 10), light)
    elif kind == "gem":
        blend(img, ellipse(cx, cy - ry * 0.2, 18, 22), accent)
    elif kind == "snow":
        blend(img, ellipse(cx, cy - ry * 0.95, 26, 8), light)
        blend(img, ellipse(cx, cy - ry * 0.95, 8, 26), light)
    elif kind == "ribbon":
        blend(img, ellipse(cx - rx * 0.2, cy - ry * 0.85, rx * 0.28, 12), accent)
        blend(img, ellipse(cx + rx * 0.35, cy - ry * 0.55, 12, ry * 0.28), accent)
    elif kind == "star":
        blend(img, ellipse(cx, cy - ry * 0.95, 22, 22), accent)
        blend(img, ellipse(cx, cy - ry * 0.95, 8, 28), light)
    elif kind == "clock":
        blend(img, ellipse(cx, cy - ry * 0.15, 34, 34), light)
        blend(img, ellipse(cx + 8, cy - ry * 0.22, 4, 14), dark)
    elif kind == "gear":
        blend(img, ellipse(cx + rx * 0.72, cy - ry * 0.55, 26, 26), accent)
        blend(img, ellipse(cx + rx * 0.72, cy - ry * 0.55, 10, 10), light)
    elif kind == "swirl":
        blend(img, ellipse(cx + rx * 0.15, cy - ry * 0.85, rx * 0.28, ry * 0.16), accent)
    elif kind == "hat":
        blend(img, ellipse(cx, cy - ry * 0.72, rx * 0.55, ry * 0.16), accent)
        blend(img, ellipse(cx, cy - ry * 0.95, rx * 0.28, ry * 0.22), accent)
    elif kind == "spool":
        blend(img, ellipse(cx, cy + ry * 0.15, 16, 28), accent)
    elif kind == "note":
        blend(img, ellipse(cx + 10, cy - ry * 0.7, 12, 10), accent)
        blend(img, ellipse(cx + 20, cy - ry * 0.95, 4, 22), accent)
    elif kind == "candy":
        blend(img, ellipse(cx, cy - ry * 0.15, 26, 18), accent)
        blend(img, ellipse(cx - 30, cy - ry * 0.15, 10, 8), light)
        blend(img, ellipse(cx + 30, cy - ry * 0.15, 10, 8), light)
    elif kind == "bow":
        blend(img, ellipse(cx - 22, cy - ry * 0.55, 16, 12), accent)
        blend(img, ellipse(cx + 22, cy - ry * 0.55, 16, 12), accent)
    elif kind == "quill":
        blend(img, ellipse(cx + rx * 0.35, cy - ry * 0.35, 10, 36), accent)
    elif kind == "lantern":
        blend(img, ellipse(cx, cy - ry * 0.95, 22, 28), accent)
        blend(img, ellipse(cx, cy - ry * 0.95, 8, 10), light)
    elif kind == "stamp":
        blend(img, ellipse(cx + rx * 0.55, cy + ry * 0.1, 20, 16), accent)
    elif kind == "scroll":
        blend(img, ellipse(cx - rx * 0.15, cy + ry * 0.35, rx * 0.4, 12), light)
    elif kind == "pixel":
        for dx, dy in ((-18, -ry * 0.9), (8, -ry * 0.95), (22, -ry * 0.75)):
            blend(img, ellipse(cx + dx, cy + dy, 8, 8), accent)
    elif kind == "heart":
        blend(img, ellipse(cx - 10, cy - ry * 0.9, 12, 12), accent)
        blend(img, ellipse(cx + 10, cy - ry * 0.9, 12, 12), accent)
    elif kind == "antenna":
        blend(img, ellipse(cx, cy - ry * 1.05, 6, 26), dark)
        blend(img, ellipse(cx, cy - ry * 1.2, 10, 10), accent)
    elif kind == "moon":
        blend(img, ellipse(cx, cy - ry * 0.95, 24, 24), light)
        blend(img, ellipse(cx + 8, cy - ry * 0.98, 18, 18), mid_color(dark, light))
    elif kind == "curl":
        blend(img, ellipse(cx + 16, cy - ry * 0.9, rx * 0.2, ry * 0.16), accent)


def mid_color(a, b):
    return tuple((np.array(a) + np.array(b)) / 2)


def smile(img, cx, cy, outline):
    draw_layer = Image.fromarray(img.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(draw_layer)
    d.arc((cx - 28, cy - 8, cx + 28, cy + 22), 20, 160, fill=tuple(int(v) for v in outline) + (230,), width=6)
    return np.asarray(draw_layer).copy()


def render(light, mid, dark, accent, outline, feature_name):
    img = np.zeros((N, N, 4), np.float32)
    cx, cy, rx, ry = 320, 348, 168, 156
    # Feature first so ears and wings sit behind the body, then body covers the roots.
    back = feature_name in {"ears", "frills", "wings", "tentacles", "spikes", "cloud", "swirl", "ribbon"}
    if back:
        feature(img, feature_name, cx, cy, rx, ry, accent, dark, light)
    body(img, cx, cy, rx, ry, light, mid, dark, outline)
    if not back:
        feature(img, feature_name, cx, cy, rx, ry, accent, dark, light)
    for side in (-1, 1):
        blend(img, ellipse(cx + side * 78, cy + 36, 28, 16), tuple(np.array(accent) * 0.75 + 40))
    eye(img, cx - 58, cy - 8, 34, accent)
    eye(img, cx + 58, cy - 8, 34, accent)
    img = smile(img, cx, cy + 48, outline)
    # Keep every painted pixel inside a 36px margin.
    a = img[:, :, 3] > 8
    ys, xs = np.nonzero(a)
    if ys.size:
        pad = 36
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        if x0 < pad or y0 < pad or x1 > N - 1 - pad or y1 > N - 1 - pad:
            sprite = Image.fromarray(img.astype(np.uint8), "RGBA")
            scale = min((N - 2 * pad) / (x1 - x0 + 1), (N - 2 * pad) / (y1 - y0 + 1), 1)
            cropped = sprite.crop((x0, y0, x1 + 1, y1 + 1))
            cropped = cropped.resize((max(1, int(cropped.width * scale)), max(1, int(cropped.height * scale))), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
            canvas.paste(cropped, ((N - cropped.width) // 2, N - pad - cropped.height), cropped)
            img = np.asarray(canvas).astype(np.float32)
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def svg_for(light, mid, dark, accent, outline, feature_name, name):
    def hx(c):
        return "#{:02x}{:02x}{:02x}".format(*(int(v) for v in c))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="640" height="640" viewBox="0 0 640 640">
  <g id="{name}">
    <ellipse cx="320" cy="348" rx="168" ry="156" fill="{hx(mid)}" stroke="{hx(outline)}" stroke-width="6"/>
    <ellipse cx="278" cy="300" rx="36" ry="16" fill="#ffffff" opacity="0.85"/>
    <ellipse cx="250" cy="384" rx="28" ry="16" fill="{hx(accent)}" opacity="0.45"/>
    <ellipse cx="390" cy="384" rx="28" ry="16" fill="{hx(accent)}" opacity="0.45"/>
    <circle cx="262" cy="340" r="34" fill="#1a1420"/>
    <circle cx="378" cy="340" r="34" fill="#1a1420"/>
    <circle cx="252" cy="330" r="12" fill="#ffffff"/>
    <circle cx="388" cy="330" r="12" fill="#ffffff"/>
    <path d="M292 396 Q320 418 348 396" fill="none" stroke="{hx(outline)}" stroke-width="6" stroke-linecap="round"/>
    <metadata>feature:{feature_name}</metadata>
  </g>
</svg>
'''


def characters():
    out = []
    for fam in REG["families"]:
        if fam["series"] != 2:
            continue
        out.extend(c for c in REG["characters"] if c["familyId"] == fam["id"])
    return out


def main():
    for c in characters():
        n = c["number"]
        folder = SOURCES / f"{n:03d}_{c['key']}"
        light, mid, dark, accent, outline = sample_palette(folder / "portrait.png")
        feat = FEATURE[n]
        im = render(light, mid, dark, accent, outline, feat)
        im.save(folder / "portrait.png")
        (folder / "figure.svg").write_text(svg_for(light, mid, dark, accent, outline, feat, c["key"]))
        check = Image.open(folder / "portrait.png")
        check.load()
        if check.size != (640, 640) or check.mode != "RGBA":
            raise SystemExit(c["key"])
        alpha = np.asarray(check)[:, :, 3]
        ys, xs = np.nonzero(alpha > 8)
        if xs.min() < 28 or ys.min() < 28 or xs.max() > 611 or ys.max() > 611:
            raise SystemExit(f"{c['key']} touches the canvas edge")
    # Comparison contact sheet: real-palette #001–015 on the first row, then #116–215.
    cell, label = 96, 20
    sheet_w = 15 * cell
    sheet = Image.new("RGB", (sheet_w, (cell + label) + 10 * (cell + label) + 8), (246, 243, 238))
    draw = ImageDraw.Draw(sheet)
    originals = []
    for num, name, feat, light, mid, dark, accent, outline in ORIGINALS:
        originals.append((num, name, render(light, mid, dark, accent, outline, feat)))
    for i, (num, name, im) in enumerate(originals):
        thumb = im.copy()
        thumb.thumbnail((cell - 12, cell - 12))
        bg = Image.new("RGBA", thumb.size, (246, 243, 238, 255))
        bg.alpha_composite(thumb)
        x = i * cell
        sheet.paste(bg.convert("RGB"), (x + (cell - thumb.width) // 2, 2))
        draw.text((x + 4, cell - 16), f"#{num:03d}", fill=(40, 40, 40))
    cs = characters()
    for i, c in enumerate(cs):
        im = Image.open(SOURCES / f"{c['number']:03d}_{c['key']}" / "portrait.png")
        r, col = divmod(i, 10)
        thumb = im.copy()
        thumb.thumbnail((cell - 12, cell - 12))
        bg = Image.new("RGBA", thumb.size, (246, 243, 238, 255))
        bg.alpha_composite(thumb)
        x, y = col * cell, (cell + label) + r * (cell + label)
        sheet.paste(bg.convert("RGB"), (x + (cell - thumb.width) // 2, y + 2))
        draw.text((x + 4, y + cell - 16), f"#{c['number']} {c['name']}", fill=(40, 40, 40))
    out = Path("/opt/cursor/artifacts/series2-glossy-contact-sheet.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print("wrote", len(cs), "figures", out)


if __name__ == "__main__":
    main()
