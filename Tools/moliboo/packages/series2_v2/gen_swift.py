"""Emit Swift MolibooSpec + Profile tables for Series 2 (#116-215) from specs.py + poster palettes + registry."""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from specs import SPECS
from render import palette
reg = json.load(open("/workspace/moli/ios/Modula/Resources/Moliboo/moliboo_registry.json"))
chars = {c["number"]: c for c in reg["characters"]}

BODY = {"round": ("round", .94, .88), "mochi": ("round", 1.04, .82), "egg": ("tall", .86, .98), "tall": ("tall", .82, 1.0),
        "wide": ("wide", 1.1, .8), "flat": ("wide", 1.16, .72), "cube": ("square", .92, .86), "squircle": ("square", .94, .88),
        "cloud": ("cloud", 1.06, .84), "ghost": ("dome", .92, .94), "drop": ("drop", .86, .98), "pear": ("pear", .92, .94),
        "onion": ("drop", .88, .96), "star": ("star", 1.04, 1.0), "lumpy": ("pebble", 1.0, .84)}
W = "c(1, 1, 1)"; GOLD = "gold"
F = {  # feature -> native parts ({m} mid, {a} accent, {b} accent2)
 "wave": [".topper(.wave, {a})"], "belly": [".mark(.belly, {l})"], "gills": [".frill({a})"], "feet": [],
 "manta": [".fins({m})", ".tail(.ribbon, {m})"], "shellhood": [".hood({a})", ".topper(.scallop, {a})"], "pearl": [".prop(.pearl, {W}, nil)"],
 "jelly": [".glow({a})", ".topper(.jellyBell, {a})"], "tentacles": [".tentacles({m})"], "spikes": [".spines({a})"],
 "floppy": [".ears(.floppy)"], "scarf": [".scarf({b})"], "starsprinkle": [".sparkles(3)"], "clam": [".shell({a})", ".prop(.pearl, {W}, nil)"],
 "finears": [".fins({a})"], "fishtail": [".tail(.whale, {a})"], "sailorhat": [".topper(.sailorHat, {W})"],
 "kite": [".prop(.kite, {a}, {b})"], "arms": [], "cloudears": [".ears(.round)"], "birdwings": [".wings(.feather, {a})"], "crest": [".featherCrest({a}, {b})"],
 "storm": [".lightning", ".topper(.raincloud, c(0.42, 0.45, 0.54))"], "propeller": [".topper(.propeller, c(0.45, 0.78, 0.4))"],
 "bigwings": [".wings(.eagle, {a})", ".windSwirl({a})"], "windtuft": [".topper(.windTuft, {a})"], "wisp": [".windSwirl({a})", ".topper(.windTuft, {l})"],
 "cape": [".blanket({b})"], "sunrays": [".rays(10, {a})", ".glow({a})"],
 "smoke": [".topper(.smoke, c(0.6, 0.58, 0.64))"], "embers": [".mark(.embers, {a})"], "flame": [".flame({a})"], "flamewings": [".wings(.dart, {a})", ".flame({a})"],
 "lavaglow": [".glow({a})", ".mark(.lavaGlow, {a})"], "cracks": [".mark(.cracks, {a})"], "ramhorns": [".ramHorns({a})"], "stonehood": [".hood({a})", ".rockSeams({a})"],
 "mane": [".mane(10)"], "torch": [".prop(.torch, {a}, nil)"],
 "petalcollar": [".rays(10, {a})"], "sprout": [".leaves(2, c(0.45, 0.78, 0.4))"], "sunflower": [".rays(14, {a})", ".glow({a})"], "berryleaf": [".leaves(3, c(0.4, 0.7, 0.35))"],
 "bee": [".wings(.insect, c(0.9, 0.96, 1))"], "stripes": [".mark(.stripes, c(0.22, 0.18, 0.2))"], "antennae": [".antennae({a})"],
 "mushcap": [".mushroomCap({a}, spots: true)"], "bellhat": [".topper(.bellHat, {a})"], "acorn": [".topper(.acorn, c(0.55, 0.36, 0.22))"],
 "clover": [".topper(.clover, {a})"], "curls": [".topper(.curls, {a})"],
 "crystalears": [".crystals({a})"], "prism": [".glow({a})", ".crystals({a})"], "icicles": [".topper(.icicles, {a})"], "aurora": [".aurora({a}, {b})", ".sparkles(3)"],
 "gemforehead": [".topper(.gem, {a})"], "bubbles": [".mark(.bubbles, {a})"], "icebuns": [".topper(.twinBuns, {a})"], "sealtail": [".tail(.whale, {m})"],
 "antlers": [".antlers({a})"], "earmuffs": [".headphones({a})"], "veil": [".hood({a})", ".sparkles(2)"],
 "goggles": [".goggles(c(0.78, 0.6, 0.3))"], "watch": [".mark(.clockDial, {a})"], "swirltop": [".topper(.swirl, {a})"], "gearears": [".topper(.gearEars, {a})"],
 "pendulum": [".prop(.pendulum, c(0.85, 0.66, 0.3), nil)"], "spring": [".topper(.spring, {a})"], "windkey": [".prop(.windKey, c(0.85, 0.66, 0.3), nil)"],
 "clockhands": [".mark(.clockDial, {a})"], "monocle": [".prop(.monocle, c(0.85, 0.66, 0.3), nil)"], "bolthorns": [".ramHorns({a})"], "rivets": [".mark(.rivets, {a})"],
 "dial": [".mark(.clockDial, {a})"], "longears": [".ears(.bunny)"], "spool": [".topper(.spool, {a})"], "octoears": [".ears(.mouse)"], "gearspots": [".mark(.gearSpots, {a})"],
 "drip": [".mark(.drip, {a})"], "sakura": [".petals(5, {b})"], "lemon": [".topper(.lemon, c(1, 0.86, 0.3))"], "cinnabuns": [".topper(.twinBuns, {a})"],
 "lollipops": [".prop(.lollipop, {a}, {W})"], "cookiedots": [".mark(.cookieDots, c(0.42, 0.26, 0.16))"], "jellyears": [".ears(.bunny)", ".glow({a})"],
 "gummydrop": [".topper(.gumdrop, {a})"], "wrapper": [".prop(.wrapper, {a}, nil)"], "candystripe": [".mark(.stripes, {W})"], "frosting": [".mark(.drip, {a})", ".sparkles(2)"],
 "inkdrip": [".mark(.drip, {m})", ".paintDrips([{m}])"], "paperears": [".ears(.cat)"], "quill": [".prop(.quill, {a}, nil)"], "polka": [".mark(.polka, {a})"],
 "beret": [".topper(.beret, {b})"], "crane": [".topper(.paperCrane, {a})"], "roundears": [".ears(.round)"], "brushtail": [".tail(.plume, {b})"],
 "bow": [".bowtie({a})"], "stamp": [".prop(.stamp, {a}, nil)"], "scrollears": [".ears(.ring)"], "chalkfluff": [".topper(.curls, {l})"],
 "pixelcrown": [".topper(.pixelCrown, {a})"], "boltears": [".ears(.fox)", ".lightning"], "glitch": [".mark(.glitch, {a})", ".pixels({b})"],
 "cyberears": [".ears(.cat)"], "visor": [".visor({a})"], "headphones": [".headphones({a})"], "starpaws": [".paws({a})"], "controller": [".prop(.controller, {b}, nil)"],
 "rings": [".ring({a})"], "halo": [".halo"], "diamondears": [".ears(.cat)", ".crystals({a})"], "datafins": [".fins({a})"], "cube": [".pixels({b})"],
 "sparks": [".orbiters(4, {b})", ".lightning"], "lanterns": [".lantern({a})", ".prop(.floatLantern, {b}, nil)"], "hood": [".hood({m})"], "mask": [".carnivalMask({a}, gold)"],
 "bunnyears": [".ears(.bunny)"], "floatlantern": [".prop(.floatLantern, {a}, nil)"], "nightcape": [".blanket({a})", ".sparkles(3)"], "ribbonloops": [".topper(.bigBow, {a})"],
 "partyhat": [".topper(.partyHat, {a})"], "glowbulbs": [".prop(.floatLantern, c(1, 0.86, 0.4), nil)", ".sparkles(2)"], "plumehat": [".topper(.plumeHat, {a})"],
 "moonhorns": [".crescent(c(1, 0.92, 0.6))"], "pinwheel": [".prop(.pinwheel, {a}, {b})"],
}
FLOAT = {"ghost", "flat", "star"}; FLOATF = {"jelly", "manta", "wisp", "tentacles", "fishtail", "storm", "sealtail"}
def cc(rgb): return "c(%.2f, %.2f, %.2f)" % tuple(v / 255 for v in rgb)

lines, profs = [], []
for n in sorted(SPECS):
    body, feats, eyes, mth, ov = SPECS[n]
    ch = chars[n]; key = ch["key"]
    folder = next(Path("/workspace/moli/out2").glob(f"{n:03d}_*"))
    p = palette(Path("/workspace/moli/moli-old") / f"{folder.name}.png", ov)
    sub = dict(m=cc(p["mid"]), a=cc(p["acc"]), b=cc(p["acc2"]), l=cc(p["light"]), W=W)
    sb, w, h = BODY[body]
    floats = body in FLOAT or any(f in FLOATF for f in feats)
    parts = []
    for f in feats:
        for q in F[f]: parts.append(q.format(**sub))
    if not floats: parts.append(".feet(%s)" % cc(tuple(int(v * 0.72) for v in p["mid"])))
    if not any(x in feats for x in ("birdwings", "bigwings", "flamewings", "manta", "bee")): parts.append(".nubs(%s)" % sub["m"])
    hat = dict(hatScale="0.9", hatMaxWidth="0.56")
    head_top = any(q.startswith(".topper") or q.startswith(".mushroomCap") or q.startswith(".hood") for f in feats for q in F[f])
    extra = ", headTopExtra: 0.06" if sb in ("drop",) else ""
    if sb == "drop": extra = ", headTopExtra: 0.17"
    if sb == "star": extra = ", headTopExtra: 0.12"
    form = ch["personality"]["description"].replace('"', "'")
    lines.append(f'        t[.{key}] = MolibooSpec(body: .{sb}, size: CGSize(width: {w}, height: {h}), palette: .spec({sub["m"]}, accent: {sub["a"]}), '
                 f'parts: [{", ".join(parts)}]' + (", floats: true, feet: false" if floats else "") +
                 f', hatScale: {hat["hatScale"]}, hatMaxWidth: {hat["hatMaxWidth"]}{extra}, form: "{form[:80]}")')
    tr = ", ".join('"%s"' % t for t in ch["traits"])
    profs.append(f'        .{key}: .init(number: {n}, title: "{ch["title"]}", traits: [{tr}]),')
keys = [chars[n]["key"] for n in sorted(SPECS)]
fam_keys = {}
for n in sorted(SPECS): fam_keys.setdefault(chars[n]["familyId"], []).append(chars[n]["key"])
out = {"specs": "\n".join(lines), "profiles": "\n".join(profs), "cases": fam_keys}
json.dump(out, open("/workspace/moli/series2_swift.json", "w"), indent=1)
print(len(lines), lines[0][:300])
