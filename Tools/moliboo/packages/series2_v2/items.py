#!/usr/bin/env python3
"""Wardrobe pack 2: glossy 2D wearables as PNG + anchor metadata (schema modula.moliboo.wearables.1).

Every item is drawn in design units with its ANCHOR at (500, 600) and its REFERENCE WIDTH = 600 units.
At runtime: scale = rig[ref] * s / refPx, and the anchor pixel goes to the rig point named by `anchor`:
  hat  -> (0, headTop + hatSink), ref hatWidth        face -> (0, eyeY), ref faceSpan = 2*faceHalfWidth + 0.08
  neck -> (0, neckY + 0.02), ref chord(neckY + 0.06)  back -> (0, backAnchorY), ref bodyW (drawn behind the body)
Usage: items.py <out_dir>
"""
import sys, json, math
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, str(Path(__file__).parent))
from core import *

AX, AY, REF = 500, 600, 600
OUTPX = 512

def bake(f):
    sil = f.sil.filter(ImageFilter.MaxFilter(9))
    m = (np.asarray(sil.filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255)[..., None] * 0.92
    a = f.img[..., 3:4]; out_a = a + m * (1 - a)
    ol = np.array(f.pal["outline"], np.float32)
    rgb = np.where(out_a > 0, (f.img[..., :3] * a + ol * m * (1 - a)) / np.maximum(out_a, 1e-5), 0)
    im = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(out_a * 255, 0, 255)]).astype(np.uint8), "RGBA")
    return im.resize((OUTPX, OUTPX), Image.Resampling.LANCZOS)

def H(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def pal(c): return dict(outline=darken(c, 0.62))
GOLD = H("#f2c14e"); PINK = H("#ff8fb1"); SKY = H("#7cc8ff"); MINT = H("#7fe0c0"); RED = H("#ef5a5a"); NAVY = H("#3b4a8f")
W = REF / 2  # half reference width

ITEMS = {}
def item(id, slot, anchor, name, blurb, family=None):
    def deco(fn): ITEMS[id] = dict(fn=fn, slot=slot, anchor=anchor, name=name, blurb=blurb, family=family); return fn
    return deco

# ---------- hats (anchor = brim centre) ----------
@item("hat2.flowercrown", "hat", "hat", "Flower crown", "A ring of glossy blooms.", "mosslight-grove")
def _(f):
    f.part(m_super(AX, AY - 20, W * 1.0, 40, 3), tri(H("#7cc36a")))
    for i, x in enumerate(np.linspace(-W * 0.85, W * 0.85, 5)):
        c = (PINK, H("#ffd25a"), SKY, PINK, H("#c79bff"))[i]
        y = AY - 40 - 26 * math.cos(x / W * 1.2)
        for k in range(5):
            a = k * 72 * math.pi / 180
            f.part(m_ellipse(AX + x + 34 * math.cos(a), y + 34 * math.sin(a), 30, 30), tri(c), gloss=0.3)
        f.part(m_ellipse(AX + x, y, 20, 20), tri(H("#ffe680")), line=False)
@item("hat2.vikinghelm", "hat", "hat", "Viking helmet", "Little horns, big courage.")
def _(f):
    for sd in (-1, 1):
        f.part(soften(m_line([(AX + sd * W * 0.8, AY - 110), (AX + sd * W * 1.1, AY - 230), (AX + sd * W * 1.02, AY - 330)], 60), 10), tri(H("#f4ead2")))
    f.part(m_ellipse(AX, AY - 20, W * 0.92, 250) if False else inter(m_ellipse(AX, AY, W * 0.92, 300), below(AY - 300)).point(lambda v: v) , tri(H("#a9b4c2")), spec=True)
    f.part(sub(m_super(AX, AY - 10, W * 0.98, 42, 3), below(AY + 40)), tri(H("#c99a4a")))
@item("hat2.starcrown", "hat", "hat", "Star crown", "Five golden points that twinkle.", "skyweavers")
def _(f):
    pts = [(AX - W * 0.85, AY)]
    for i in range(5):
        x = AX - W * 0.85 + (i + 0.5) * W * 1.7 / 5
        pts += [(x - W * 0.1, AY - 120), (x, AY - 230 if i % 2 == 0 else AY - 200), (x + W * 0.1, AY - 120)]
    pts += [(AX + W * 0.85, AY)]
    f.part(soften(m_poly(pts), 8), tri(GOLD), spec=True)
    for i in range(5):
        x = AX - W * 0.85 + (i + 0.5) * W * 1.7 / 5
        f.part(m_poly(star_pts(x, AY - 255 if i % 2 == 0 else AY - 225, 36, 15)), tri(H("#fff3a0")), gloss=0)
    f.part(m_ellipse(AX, AY - 60, 34, 34), tri(RED), spec=True)
@item("hat2.icecrown", "hat", "hat", "Ice crown", "Frosted crystal spires.", "aurora-vale")
def _(f):
    for x, h in ((-0.7, 160), (-0.35, 230), (0, 300), (0.35, 230), (0.7, 160)):
        f.part(m_poly([(AX + W * x - 45, AY), (AX + W * x, AY - h), (AX + W * x + 45, AY)], 4), tri(H("#bfe9ff")), spec=True)
    f.part(m_super(AX, AY - 10, W * 0.95, 38, 3), tri(H("#e9f7ff")))
@item("hat2.flamecrown", "hat", "hat", "Ember crown", "Flickering, but never hot.", "cinderlings")
def _(f):
    for x, h in ((-0.6, 170), (0, 280), (0.6, 170), (-0.3, 210), (0.3, 210)):
        f.part(soften(union(m_ellipse(AX + W * x, AY - 50, 60, 70), m_poly([(AX + W * x - 60, AY - 50), (AX + W * x, AY - h), (AX + W * x + 60, AY - 50)])), 12), tri(H("#ff8a3c")), gloss=0.3)
        f.flat(soften(union(m_ellipse(AX + W * x, AY - 40, 30, 40), m_poly([(AX + W * x - 30, AY - 40), (AX + W * x, AY - h * 0.6), (AX + W * x + 30, AY - 40)])), 8), H("#ffd25a"))
    f.part(m_super(AX, AY - 8, W * 0.92, 36, 3), tri(H("#b43a2a")))
@item("hat2.candycrown", "hat", "hat", "Candy crown", "Gumdrops on a frosted band.", "sugarvale")
def _(f):
    f.part(m_super(AX, AY - 40, W * 0.95, 70, 3), tri(H("#fff0f6")))
    for i, x in enumerate((-0.62, -0.2, 0.22, 0.64)):
        f.part(m_ellipse(AX + W * x, AY - 130, 55, 60), tri((PINK, MINT, H("#ffd25a"), SKY)[i]), spec=True)
    for x in np.linspace(-W * 0.85, W * 0.85, 7):
        f.flat(m_ellipse(AX + x, AY - 20, 14, 14), PINK)
@item("hat2.piratehat", "hat", "hat", "Pirate hat", "Skull-free, treasure-friendly.", "tideborn")
def _(f):
    f.part(soften(m_poly([(AX - W * 1.1, AY), (AX - W * 0.6, AY - 220), (AX, AY - 180), (AX + W * 0.6, AY - 220), (AX + W * 1.1, AY), (AX, AY + 30)]), 20), tri(H("#2e2a3a")), spec=True)
    f.flat(m_arc(AX, AY + 140, W * 1.0, 228, 312, 18), GOLD)
    f.part(m_poly(star_pts(AX, AY - 110, 50, 22)), tri(GOLD), gloss=0)
@item("hat2.leafcap", "hat", "hat", "Leaf cap", "One big leaf, perfectly balanced.", "mosslight-grove")
def _(f):
    f.part(soften(m_poly([(AX - W * 0.9, AY), (AX - W * 0.5, AY - 170), (AX + W * 0.3, AY - 230), (AX + W * 0.95, AY - 60), (AX + W * 0.7, AY + 10)]), 30), tri(H("#6cc46a")), spec=True)
    f.flat(m_line([(AX - W * 0.6, AY - 20), (AX + W * 0.6, AY - 150)], 12), H("#3f8f45"))
    f.part(m_line([(AX + W * 0.55, AY - 160), (AX + W * 0.7, AY - 260)], 22), tri(H("#7a5a3a")), line=False)
@item("hat2.goggleband", "hat", "hat", "Tinker goggles", "Brass goggles pushed up top.", "clocklings")
def _(f):
    f.part(m_super(AX, AY - 30, W * 1.0, 40, 3), tri(H("#6a4a3a")))
    for sd in (-1, 1):
        f.part(m_ellipse(AX + sd * W * 0.42, AY - 80, 90, 90), tri(H("#c99a4a")), spec=True)
        f.part(m_ellipse(AX + sd * W * 0.42, AY - 80, 60, 60), tri(H("#7fd0e8")), spec=True)
@item("hat2.paperlantern", "hat", "hat", "Lantern hat", "A tiny glowing paper lantern.", "lantern-parade")
def _(f):
    f.part(m_super(AX, AY - 150, W * 0.55, 140, 2.2), tri(H("#ff7a5a")), spec=True)
    for y in (-210, -150, -90):
        f.flat(m_arc(AX, AY + y + 220, W * 0.6, 245, 295, 8), H("#c9402e"))
    f.part(m_super(AX, AY - 10, W * 0.4, 26, 4), tri(GOLD)); f.part(m_super(AX, AY - 292, W * 0.3, 22, 4), tri(GOLD))
    f.flat(m_ellipse(AX, AY - 150, 70, 90), H("#ffe08a"), 0.55)

# ---------- face (anchor = between the eyes) ----------
@item("face2.heartglasses", "face", "face", "Heart shades", "Love-tinted lenses.")
def _(f):
    for sd in (-1, 1):
        x = AX + sd * W * 0.5
        h = soften(union(m_ellipse(x - 50, AY - 30, 70, 70), m_ellipse(x + 50, AY - 30, 70, 70), m_poly([(x - 115, AY), (x + 115, AY), (x, AY + 120)])), 10)
        f.part(h, tri(H("#ff4f7a")), spec=True)
    f.part(m_line([(AX - 60, AY - 30), (AX + 60, AY - 30)], 22), tri(H("#ff4f7a")), line=False)
@item("face2.starshades", "face", "face", "Star shades", "For main-character energy.", "skyweavers")
def _(f):
    for sd in (-1, 1):
        f.part(soften(m_poly(star_pts(AX + sd * W * 0.5, AY, 130, 62)), 6), tri(H("#ffd25a")), spec=True)
        f.flat(m_ellipse(AX + sd * W * 0.5, AY, 52, 52), H("#4a3a7a"), 0.8)
    f.part(m_line([(AX - 70, AY - 10), (AX + 70, AY - 10)], 22), tri(H("#ffd25a")), line=False)
@item("face2.snorkel", "face", "face", "Snorkel mask", "Ready for a reef dive.", "tideborn")
def _(f):
    f.part(sub(m_super(AX, AY, W * 1.05, 120, 3), union(m_ellipse(AX - W * 0.5, AY, 100, 92), m_ellipse(AX + W * 0.5, AY, 100, 92))), tri(H("#ffb03a")), spec=True)
    for sd in (-1, 1): f.flat(m_ellipse(AX + sd * W * 0.5, AY, 100, 92), H("#bfeaff"), 0.35)
    f.part(soften(m_line([(AX + W * 1.0, AY - 20), (AX + W * 1.15, AY - 120), (AX + W * 1.12, AY - 300)], 40), 8), tri(H("#4fb8e8")))

# ---------- neck (anchor = neck centre) ----------
@item("neck2.pearls", "accessory", "neck", "Pearl necklace", "A string of ocean pearls.", "tideborn")
def _(f):
    for i in range(9):
        t = (i / 8 - 0.5) * 2
        f.part(m_ellipse(AX + t * W * 0.55, AY + 40 + 110 * (1 - t * t), 30, 30), tri(H("#f6f0ff")), spec=True)
    f.part(m_ellipse(AX, AY + 205, 40, 48), tri(H("#ffc6dc")), spec=True)
@item("neck2.shellcharm", "accessory", "neck", "Shell charm", "A seashell on a cord.", "tideborn")
def _(f):
    f.flat(m_arc(AX, AY - 160, W * 0.85, 40, 140, 14), H("#7a5a3a"))
    s = m_ellipse(AX, AY + 90, 80, 70)
    f.part(s, tri(H("#ffb7a6")), spec=True)
    for a in (-50, -25, 0, 25, 50):
        f.flat(m_line([(AX, AY + 150), (AX + 75 * math.sin(math.radians(a)), AY + 150 - 110 * math.cos(math.radians(a)))], 8), H("#e0806e"))
@item("neck2.bellcollar", "accessory", "neck", "Bell collar", "Jingles with every hop.", "sugarvale")
def _(f):
    f.part(m_super(AX, AY, W * 0.95, 38, 3), tri(RED))
    f.part(m_ellipse(AX, AY + 75, 60, 60), tri(GOLD), spec=True)
    f.flat(m_line([(AX - 30, AY + 80), (AX + 30, AY + 80)], 8), darken(GOLD, 0.5))
@item("neck2.medal", "accessory", "neck", "Gold medal", "For tiny victories.")
def _(f):
    for sd in (-1, 1): f.part(m_poly([(AX + sd * W * 0.7, AY - 30), (AX + sd * W * 0.45, AY - 30), (AX + sd * 20, AY + 110), (AX + sd * 70, AY + 110)]), tri(SKY if sd < 0 else RED))
    f.part(m_ellipse(AX, AY + 170, 80, 80), tri(GOLD), spec=True)
    f.part(m_poly(star_pts(AX, AY + 170, 44, 20)), tri(H("#fff0a0")), gloss=0)
@item("neck2.knitscarf", "accessory", "neck", "Chunky knit scarf", "Extra cosy, extra long.", "aurora-vale")
def _(f):
    f.part(m_super(AX, AY, W * 1.02, 60, 2.6), tri(H("#ff7a8a")))
    for x in np.linspace(-W * 0.9, W * 0.9, 9): f.flat(m_line([(AX + x, AY - 45), (AX + x, AY + 45)], 10), H("#ffc0c8"), 0.6)
    f.part(m_super(AX + W * 0.45, AY + 150, 55, 130, 3), tri(H("#ff7a8a")))
    for k in range(4): f.flat(m_line([(AX + W * 0.45 - 40 + k * 26, AY + 270), (AX + W * 0.45 - 40 + k * 26, AY + 310)], 12), H("#ff7a8a"))
@item("neck2.bowtie", "accessory", "neck", "Polka bow tie", "Dapper and dotty.", "inkbound-atelier")
def _(f):
    for sd in (-1, 1): f.part(soften(m_poly([(AX, AY + 20), (AX + sd * 160, AY - 70), (AX + sd * 160, AY + 110)]), 12), tri(NAVY))
    f.part(m_ellipse(AX, AY + 20, 40, 44), tri(NAVY), spec=True)
    for x, y in ((-100, 0), (-90, 60), (100, 10), (95, 65)): f.flat(m_ellipse(AX + x, AY + y, 12, 12), (255, 255, 255))

# ---------- back (anchor = back centre, drawn behind the body) ----------
@item("back2.backpack", "back", "back", "Little backpack", "Room for one snack.")
def _(f):
    f.part(m_super(AX - W * 0.75, AY + 20, 150, 200, 3.2), tri(H("#ffb03a")), spec=True)
    f.part(m_super(AX - W * 0.75 - 20, AY + 110, 100, 70, 3), tri(H("#ff8f2a")))
@item("back2.jetpack", "back", "back", "Rocket pack", "Two tiny thrusters, zero emissions.", "neon-arcade")
def _(f):
    for sd in (-1, 1):
        x = AX + sd * W * 0.95
        f.part(soften(union(m_super(x, AY, 70, 190, 2.4), m_poly([(x - 60, AY - 150), (x, AY - 260), (x + 60, AY - 150)])), 8), tri(H("#c9d3e0")), spec=True)
        f.part(soften(union(m_ellipse(x, AY + 230, 45, 60), m_poly([(x - 40, AY + 230), (x, AY + 360), (x + 40, AY + 230)])), 10), tri(H("#ff8a3c")), gloss=0.2)
@item("back2.shellpack", "back", "back", "Turtle shell", "Home goes where you go.", "tideborn")
def _(f):
    m = m_ellipse(AX, AY + 40, W * 1.25, 280)
    f.part(m, tri(H("#6cb86a")), spec=True)
    for x, y in ((0, -60), (-150, 60), (150, 60), (-60, 170), (60, 170)):
        f.flat(soften(m_poly([(AX + x + 55 * math.cos(a), AY + 40 + y + 55 * math.sin(a)) for a in np.linspace(0, 6.28, 7)[:-1]]), 4), H("#a5dc8a"), 0.8)
@item("back2.fairywings", "back", "back", "Petal wings", "Translucent and shimmery.", "mosslight-grove")
def _(f):
    for sd in (-1, 1):
        f.part(m_ellipse(AX + sd * W * 1.05, AY - 120, 150, 210, rot=sd * 0.5), tri(H("#cdb4ff")), spec=True)
        f.part(m_ellipse(AX + sd * W * 0.95, AY + 140, 105, 140, rot=sd * -0.4), tri(H("#ffc4e6")), spec=True)
@item("back2.windupkey", "back", "back", "Wind-up key", "Tick, tick, go.", "clocklings")
def _(f):
    f.part(m_line([(AX, AY), (AX + W * 1.0, AY - 40)], 50), tri(H("#c99a4a")))
    for dy in (-90, 90):
        f.part(m_ellipse(AX + W * 1.08, AY - 40 + dy, 85, 95), tri(GOLD), spec=True)
        f.flat(m_ellipse(AX + W * 1.08, AY - 40 + dy, 30, 34), darken(GOLD, 0.4))

def render_all(out):
    out.mkdir(parents=True, exist_ok=True)
    manifest = []
    for id, it in ITEMS.items():
        f = Fig(pal((60, 40, 60)))
        f.pal = dict(outline=(70, 46, 62))
        it["fn"](f)
        im = bake(f)
        a = np.asarray(im)[..., 3]
        assert a[:3].max() == 0 and a[-3:].max() == 0 and a[:, :3].max() == 0 and a[:, -3:].max() == 0, f"{id} clipped"
        im.save(out / f"{id}.png", optimize=True)
        k = OUTPX / 1000 * U / U
        manifest.append(dict(id=id, slot=it["slot"], anchor=it["anchor"], name=it["name"], blurb=it["blurb"], family=it["family"],
                             file=f"{id}.png", size=OUTPX, anchorPx=[round(AX * OUTPX / 1000, 2), round(AY * OUTPX / 1000, 2)],
                             refPx=round(REF * OUTPX / 1000, 2), layer="back" if it["anchor"] == "back" else "front"))
        print("ok", id, flush=True)
    return manifest

if __name__ == "__main__":
    out = Path(sys.argv[1])
    items = render_all(out)
    (out / "wearables.json").write_text(json.dumps({
        "schemaVersion": "modula.moliboo.wearables.1",
        "status": "draft — not in the local MascotWardrobeCatalog, no price, no unlock, no ownership",
        "anchorConvention": __doc__.split("Usage:")[0].strip(),
        "items": items}, indent=2) + "\n")
