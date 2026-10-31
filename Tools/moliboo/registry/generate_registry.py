#!/usr/bin/env python3
"""MOL-03 canonical Moliboo registry generator.

Reads the native 2D roster (ModulaMascot.swift + MolibooLegends.swift) plus the Series 2
concept file (Tools/moliboo/registry/series2/) and writes
ios/Modula/Resources/Moliboo/moliboo_registry.json (schema modula.moliboo.registry.1).

Series 2 keeps draft concept order: concept 101 becomes catalogue #116 and concept 200
becomes #215. Originals 001–100 and Legends 101–115 are never renumbered. Series 2 stays
draft and not purchasable; artwork is package: only (not bundled).

Identity facts (key, number, name, family, title, traits, description, parts) come from code and are
never renamed. Personality numbers and signature reactions are derived deterministically from the
character's own traits and silhouette parts, so re-running the generator is reproducible.

Usage: generate_registry.py <repo-root> [--check]
"""
import json, re, sys, pathlib, hashlib

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
CHECK = "--check" in sys.argv
MASCOT = ROOT / "ios/Modula/DesignSystem/Mascot"
OUT = ROOT / "ios/Modula/Resources/Moliboo/moliboo_registry.json"

src = "\n".join(p.read_text() for p in sorted(MASCOT.glob("*.swift")))
main = (MASCOT / "ModulaMascot.swift").read_text()

# 1. Roster order from the enum.
enum_block = re.search(r"enum ModulaMascotKind: String[^{]*\{(.*?)var id: String", main, re.S).group(1)
keys = []
for line in enum_block.splitlines():
    line = line.strip()
    if line.startswith("case "):
        keys += [k.strip().strip("`") for k in line[5:].split(",")]

# 2. Profiles: number, title, traits.
prof = {}
for m in re.finditer(r'\.`?(\w+)`?: (?:Profile|\.init)\(number: (\d+), title: "([^"]*)", traits: \[([^\]]*)\]\)', src):
    prof[m.group(1)] = (int(m.group(2)), m.group(3), re.findall(r'"([^"]*)"', m.group(4)))

# 3. Originals hand-written descriptions.
pers_block = re.search(r"var personality: String \{(.*?)default:", main, re.S).group(1)
desc = {m.group(1): m.group(2) for m in re.finditer(r'case \.`?(\w+)`?: "([^"]*)"', pers_block)}

# 4. Family specs: body, parts, form, floats.
part_names = set()
for blk in re.findall(r"enum MolibooPart[^{]*\{(.*?)\n\}", src, re.S):
    for m in re.finditer(r"case ([^\n]+)", blk):
        part_names |= set(re.findall(r"(?:^|,\s*)(\w+)", re.sub(r"\([^)]*\)", "", m.group(1))))
part_names |= set(re.findall(r"^\s*case (\w+)", "\n".join(re.findall(r"extension MolibooPart[^{]*\{(.*?)\n\}", src, re.S)), re.M))
spec = {}
for m in re.finditer(r"t\[\.`?(\w+)`?\] = MolibooSpec\((.*)\)\s*$", src, re.M):
    body = m.group(2)
    pm = re.search(r"parts: \[(.*?)\](?:, (?:floats|feet|hatScale|hatMaxWidth|headTopExtra|form)|\))", body)
    parts = []
    if pm:
        depth = 0; tok = ""
        for ch in pm.group(1):
            if ch == "(": depth += 1
            if ch == ")": depth -= 1
            if ch == "," and depth == 0:
                parts.append(tok); tok = ""
            else:
                tok += ch
        parts.append(tok)
        parts = [re.match(r"\s*\.(\w+)", p).group(1) for p in parts if re.match(r"\s*\.(\w+)", p)]
    fm = re.search(r'form: "([^"]*)"', body)
    bm = re.search(r"body: \.(\w+)", body)
    spec[m.group(1)] = {"body": bm.group(1) if bm else "round", "parts": parts,
                        "form": fm.group(1) if fm else "", "floats": "floats: true" in body}

FAMILIES = [
    ("originals", "The Originals", "Originals", 1, 25, "Home", True, "originals.bouncy"),
    ("angels", "Moliboo Angels", "Angels", 26, 40, "Celestia", True, "angels.float"),
    ("underground", "Moliboo Underground", "Underground", 41, 55, "The Underground", True, "underground.pulse"),
    ("enchanted", "Moliboo Enchanted", "Enchanted", 56, 70, "The Luminous Wilds", True, "enchanted.sway"),
    ("stardust", "Moliboo Stardust", "Stardust", 71, 85, "The Stardust Reach", True, "stardust.orbit"),
    ("dreamers", "Moliboo Dreamers", "Dreamers", 86, 100, "The Dreaming Vale", True, "dreamers.drift"),
    ("legends", "Moliboo Legends", "Legends", 101, 115, "The Mythic Wilds", False, "legends.mythic"),
]
def family_of(n):
    for f in FAMILIES:
        if f[3] <= n <= f[4]: return f
    raise SystemExit(f"number {n} outside every family range")

# Shared animation primitives (MOL-03 §7). Profiles configure them; there is one runtime.
PRIMITIVES = ["translate", "rotate", "scale", "squashStretch", "opacity", "blink", "layerOffset",
              "glowIntensity", "particleBurst", "accessoryFollow", "expressionTransition"]
MOTION = {
    "originals.bouncy": {"familyId": "originals", "language": "Bouncing, wobbling, playful stretching, little hops",
        "idle": [{"primitive": "translate", "axis": "y", "amplitude": 0.035, "period": 1.6},
                 {"primitive": "squashStretch", "amplitude": 0.04, "period": 1.6},
                 {"primitive": "rotate", "amplitude": 2.5, "period": 3.2}],
        "tempo": 1.0},
    "angels.float": {"familyId": "angels", "language": "Floating, gentle wing movement, soft halo motion, subtle glow",
        "idle": [{"primitive": "translate", "axis": "y", "amplitude": 0.05, "period": 3.4},
                 {"primitive": "layerOffset", "layer": "wings", "amplitude": 0.03, "period": 1.8},
                 {"primitive": "glowIntensity", "amplitude": 0.25, "period": 4.0}],
        "tempo": 0.7},
    "underground.pulse": {"familyId": "underground", "language": "Digital blinking, energetic pulses, tiny glitches, street rhythm",
        "idle": [{"primitive": "scale", "amplitude": 0.03, "period": 0.9},
                 {"primitive": "blink", "amplitude": 1.0, "period": 2.6},
                 {"primitive": "translate", "axis": "x", "amplitude": 0.01, "period": 0.45}],
        "tempo": 1.3},
    "enchanted.sway": {"familyId": "enchanted", "language": "Organic sway, leaf movement, antenna motion, gentle settling",
        "idle": [{"primitive": "rotate", "amplitude": 3.5, "period": 4.2},
                 {"primitive": "layerOffset", "layer": "leaves", "amplitude": 0.02, "period": 2.4},
                 {"primitive": "squashStretch", "amplitude": 0.02, "period": 4.2}],
        "tempo": 0.8},
    "stardust.orbit": {"familyId": "stardust", "language": "Slow rotation, orbiting particles, twinkling and floating",
        "idle": [{"primitive": "rotate", "amplitude": 4.0, "period": 7.0},
                 {"primitive": "translate", "axis": "y", "amplitude": 0.04, "period": 4.5},
                 {"primitive": "glowIntensity", "amplitude": 0.35, "period": 2.2}],
        "tempo": 0.6},
    "dreamers.drift": {"familyId": "dreamers", "language": "Sleepy breathing, yawning, drifting and relaxed movement",
        "idle": [{"primitive": "scale", "amplitude": 0.025, "period": 5.0},
                 {"primitive": "translate", "axis": "x", "amplitude": 0.02, "period": 8.0},
                 {"primitive": "blink", "amplitude": 0.6, "period": 6.0}],
        "tempo": 0.5},
    "legends.mythic": {"familyId": "legends", "language": "Grounded, majestic presence: slow heavy sway, a proud settle, rare flourishes",
        "idle": [{"primitive": "rotate", "amplitude": 2.0, "period": 5.5},
                 {"primitive": "squashStretch", "amplitude": 0.03, "period": 5.5},
                 {"primitive": "glowIntensity", "amplitude": 0.15, "period": 6.0}],
        "tempo": 0.65},
    # Series 2 motion languages. Each profile differs in primitive, period and tempo so families
    # do not share a signature. Reduce Motion is applied to every profile below.
    "tideborn.swell": {"familyId": "tideborn", "language": "A slow swell with a sideways drift",
        "idle": [{"primitive": "translate", "axis": "y", "amplitude": 0.045, "period": 2.8},
                 {"primitive": "translate", "axis": "x", "amplitude": 0.02, "period": 3.6},
                 {"primitive": "rotate", "amplitude": 1.4, "period": 5.1}],
        "tempo": 0.72},
    "skyweavers.glide": {"familyId": "skyweavers", "language": "A high float, a slow turn and a soft glow",
        "idle": [{"primitive": "translate", "axis": "y", "amplitude": 0.06, "period": 4.1},
                 {"primitive": "rotate", "amplitude": 2.2, "period": 6.4},
                 {"primitive": "glowIntensity", "amplitude": 0.2, "period": 3.3}],
        "tempo": 0.55},
    "cinderlings.flicker": {"familyId": "cinderlings", "language": "A quick flicker, a squash and a warm glow",
        "idle": [{"primitive": "scale", "amplitude": 0.04, "period": 1.1},
                 {"primitive": "squashStretch", "amplitude": 0.035, "period": 1.7},
                 {"primitive": "glowIntensity", "amplitude": 0.4, "period": 2.4}],
        "tempo": 1.15},
    "mosslight-grove.settle": {"familyId": "mosslight-grove", "language": "A leafy sway with a small sideways settle",
        "idle": [{"primitive": "rotate", "amplitude": 2.8, "period": 3.8},
                 {"primitive": "translate", "axis": "x", "amplitude": 0.018, "period": 5.5},
                 {"primitive": "layerOffset", "layer": "leaves", "amplitude": 0.025, "period": 2.2}],
        "tempo": 0.78},
    "aurora-vale.shimmer": {"familyId": "aurora-vale", "language": "A long shimmer, a slight lift and a slow turn",
        "idle": [{"primitive": "glowIntensity", "amplitude": 0.45, "period": 2.9},
                 {"primitive": "translate", "axis": "y", "amplitude": 0.03, "period": 6.2},
                 {"primitive": "rotate", "amplitude": 1.1, "period": 8.4}],
        "tempo": 0.48},
    "clocklings.tick": {"familyId": "clocklings", "language": "A tight tick, a small pulse and a short sway",
        "idle": [{"primitive": "rotate", "amplitude": 5.0, "period": 2.2},
                 {"primitive": "scale", "amplitude": 0.02, "period": 1.3},
                 {"primitive": "translate", "axis": "x", "amplitude": 0.012, "period": 0.8}],
        "tempo": 1.25},
    "sugarvale.bob": {"familyId": "sugarvale", "language": "A soft bob, a squash and a gentle pulse",
        "idle": [{"primitive": "squashStretch", "amplitude": 0.05, "period": 2.1},
                 {"primitive": "translate", "axis": "y", "amplitude": 0.028, "period": 2.5},
                 {"primitive": "scale", "amplitude": 0.02, "period": 3.3}],
        "tempo": 0.9},
    "inkbound-atelier.drift": {"familyId": "inkbound-atelier", "language": "A paper drift, a slow tilt and a quiet fade",
        "idle": [{"primitive": "translate", "axis": "x", "amplitude": 0.03, "period": 4.8},
                 {"primitive": "rotate", "amplitude": 1.6, "period": 7.2},
                 {"primitive": "opacity", "amplitude": 0.08, "period": 3.0}],
        "tempo": 0.62},
    "neon-arcade.pulse": {"familyId": "neon-arcade", "language": "A fast pulse, a twitch and a bright glow",
        "idle": [{"primitive": "scale", "amplitude": 0.045, "period": 0.7},
                 {"primitive": "translate", "axis": "x", "amplitude": 0.025, "period": 0.55},
                 {"primitive": "glowIntensity", "amplitude": 0.5, "period": 1.4}],
        "tempo": 1.4},
    "lantern-parade.glow": {"familyId": "lantern-parade", "language": "A lantern lift, a warm glow and a proud turn",
        "idle": [{"primitive": "translate", "axis": "y", "amplitude": 0.038, "period": 3.1},
                 {"primitive": "glowIntensity", "amplitude": 0.3, "period": 2.6},
                 {"primitive": "rotate", "amplitude": 2.4, "period": 4.6}],
        "tempo": 0.84},
}
for p in MOTION.values():
    p["reducedMotion"] = {"idle": [{"primitive": "opacity", "amplitude": 0.0, "period": 0}], "allowBlink": True,
                          "note": "Reduce Motion: no translation/rotation/scale; expression changes cross-fade."}

# Signature details from silhouette parts (first match wins; order = visual priority).
SIG_PARTS = [
    ("skateboard", "kickflip", "rides its skateboard"), ("santaHat", "hatBob", "bobs its Santa hat"),
    ("kitsuneTails", "tailFan", "fans its fox tails"), ("tentacles", "tentacleCurl", "curls its tentacles"),
    ("humps", "humpRipple", "ripples its humps"), ("puddle", "puddleRipple", "ripples its shadow puddle"),
    ("rockSeams", "rumbleShake", "rumbles its rock seams"), ("harp", "noteBurst", "strums a harp note"),
    ("halo", "haloSpin", "spins its halo"), ("orbiters", "orbitSpin", "spins its orbiters"),
    ("ring", "ringTilt", "tilts its ring"), ("wings", "wingFlutter", "flutters its wings"),
    ("skate", "kickflip", "kicks off"), ("shell", "shellPeek", "peeks from its shell"),
    ("headphones", "beatBounce", "nods to the beat"), ("speakers", "beatBounce", "pulses its speakers"),
    ("pixels", "glitch", "glitches its pixels"), ("lightning", "spark", "throws a spark"),
    ("thunderMark", "spark", "crackles with thunder"), ("flameCrest", "flare", "flares its crest"),
    ("flame", "flare", "flares its flame"), ("crescent", "moonGlint", "glints its crescent"),
    ("moonMark", "moonGlint", "glints its moon mark"), ("antlers", "antlerTilt", "tilts its antlers"),
    ("jackalopeAntlers", "antlerTilt", "tilts its antlers"), ("ramHorns", "hornNod", "nods its horns"),
    ("horn", "hornGlint", "glints its horn"), ("mushroomCap", "capWobble", "wobbles its mushroom cap"),
    ("wreath", "leafRustle", "rustles its wreath"), ("leaves", "leafRustle", "rustles its leaves"),
    ("petals", "petalOpen", "opens its petals"), ("tendrils", "tendrilWave", "waves its tendrils"),
    ("antennae", "antennaBob", "bobs its antennae"), ("ears", "earTwitch", "twitches its ears"),
    ("tail", "tailWag", "wags its tail"), ("mane", "maneShake", "shakes its mane"),
    ("shag", "furShake", "shakes its fur"), ("beard", "beardWiggle", "wiggles its beard"),
    ("frostSpikes", "frostSparkle", "sparkles with frost"), ("snowflakes", "frostSparkle", "scatters snowflakes"),
    ("wand", "wandSparkle", "waves its wand"), ("lantern", "lanternSwing", "swings its lantern"),
    ("notes", "noteBurst", "hums a note"), ("cloudSeat", "cloudPuff", "puffs its cloud"),
    ("nightcap", "capFlop", "flops its nightcap"), ("blanket", "blanketSnuggle", "snuggles its blanket"),
    ("glow", "glowPulse", "pulses its glow"), ("sparkles", "twinkle", "twinkles"),
]
ORIGINALS_SIG = {
    "pip": ("frillWave", "waves its frills"), "moss": ("puffThink", "puffs up to think"),
    "nimbus": ("cloudDrift", "drifts like a cloud"), "mochi": ("earFlick", "flicks an ear, secretly listening"),
    "sprout": ("leafGrow", "grows its sprout"), "ember": ("flare", "flares bright"),
    "tuck": ("headTilt", "tilts its head like an owl"), "bloop": ("tentacleFloat", "floats its tentacles"),
    "bun": ("earFlop", "flops its ears and hops"), "pebble": ("steadySettle", "settles steadily"),
    "tofu": ("wobble", "wobbles"), "comet": ("sparkTrail", "leaves a sparkle trail"),
    "puff": ("inflate", "inflates with excitement"), "bolt": ("screenBeep", "beeps on its screen face"),
    "glim": ("glowPulse", "glows its firefly light"), "echo": ("earTwitch", "turns its big ears"),
    "quill": ("curlPeek", "curls up then peeks out"), "orbit": ("orbitSpin", "spins its pocket moon"),
    "prism": ("colourShift", "shifts its colours"), "wisp": ("ghostDrift", "drifts like a ghost"),
    "doodle": ("inkSplash", "splashes ink"), "chime": ("bellRing", "rings its bell"),
    "rolo": ("shellPeek", "peeks from its spiral shell"), "pogo": ("springBounce", "springs on its foot"),
    "fable": ("unfold", "unfolds like origami"),
}

HI_E = {"energetic","excitable","restless","playful","brave","fearless","impatient","joyful","passionate","impulsive",
        "competitive","spontaneous","jolly","festive","bold","loud","wild","fiery","fast","bouncy","rebellious","mischievous",
        "funny","dramatic","adventurous","cheerful","outgoing","lively","sporty","rhythmic","daring","strong"}
LO_E = {"sleepy","calm","patient","gentle","dreamy","reserved","unbothered","wise","reflective","shy","quiet","cozy",
        "sleep","serene","peaceful","soft","slow","ancient","tranquil","relaxed","thoughtful","still","lazy","soothing"}
CUR = {"curious","inventive","philosophical","adventurous","explorer","perceptive","analytical","imaginative","bookish",
       "precise","clever","inquisitive","scholar","explore","mysterious","artistic","wise","creative","magical","tinkerer"}
SOC = {"outgoing","affectionate","friendly","social","kind","generous","cheerful","playful","loving","love","joyful",
       "jolly","festive","warm","caring","nurturing","sweet","loyal","helpful","guiding","leader","hopeful"}
UNSOC = {"shy","independent","reserved","elusive","mysterious","cautious","quiet","unbothered","solitary","secretive","aloof"}
FAMILY_BIAS = {"originals": (0.05, 0, 0.05), "angels": (-0.1, 0, 0.1), "underground": (0.15, 0.05, 0),
               "enchanted": (-0.05, 0.05, 0), "stardust": (-0.1, 0.1, -0.05), "dreamers": (-0.25, -0.05, 0.05),
               "legends": (0, 0.05, -0.05),
               "tideborn": (-0.05, 0.08, 0.06), "skyweavers": (-0.08, 0.06, 0.04), "cinderlings": (0.12, 0.02, 0),
               "mosslight-grove": (-0.06, 0.06, 0.04), "aurora-vale": (-0.1, 0.08, 0), "clocklings": (0.04, 0.1, -0.02),
               "sugarvale": (0.06, 0, 0.1), "inkbound-atelier": (-0.04, 0.1, -0.04), "neon-arcade": (0.14, 0.04, 0.02),
               "lantern-parade": (0.08, 0.02, 0.1)}
ARCH = [("dreamy", {"sleepy","dreamy","sleep","cozy","calm","quiet"}), ("playful", HI_E & {"playful","excitable","mischievous","funny","bouncy","spontaneous","jolly","cheerful"}),
        ("brave", {"brave","fearless","bold","protective","strong","leader"}), ("curious", CUR),
        ("gentle", {"gentle","kind","soft","shy","sensitive","caring"}), ("mysterious", {"mysterious","elusive","secretive","ancient"}),
        ("wise", {"wise","patient","reflective","thoughtful","philosophical"})]

def clamp(x): return round(max(0.1, min(0.95, x)), 2)
def words(traits, title):
    return {w.lower().strip(".,") for t in traits + [title] for w in re.split(r"[\s-]+", t)}

PART_FREQ = {}
for _sp in spec.values():
    for _p in set(_sp["parts"]): PART_FREQ[_p] = PART_FREQ.get(_p, 0) + 1

characters = []
seen = set()
for key in keys:
    if key not in prof: raise SystemExit(f"{key}: no profile")
    number, title, traits = prof[key]
    fam = family_of(number)
    w = words(traits, title)
    be, bc, bs = FAMILY_BIAS[fam[0]]
    energy = clamp(0.5 + 0.17 * (len(w & HI_E) - len(w & LO_E)) + be)
    curiosity = clamp(0.5 + 0.18 * len(w & CUR) + bc)
    social = clamp(0.5 + 0.16 * (len(w & SOC) - len(w & UNSOC)) + bs)
    archetype = next((a for a, s in ARCH if w & s), {"originals": "playful", "angels": "gentle", "underground": "playful",
        "enchanted": "gentle", "stardust": "curious", "dreamers": "dreamy", "legends": "mysterious",
        "tideborn": "curious", "skyweavers": "dreamy", "cinderlings": "playful", "mosslight-grove": "gentle",
        "aurora-vale": "mysterious", "clocklings": "curious", "sugarvale": "playful", "inkbound-atelier": "wise",
        "neon-arcade": "playful", "lantern-parade": "playful"}[fam[0]])
    sp = spec.get(key)
    parts = sp["parts"] if sp else []
    if key in ORIGINALS_SIG:
        sig, line = ORIGINALS_SIG[key]
    else:
        # Prefer the rarest silhouette part so signatures stay distinctive (ties keep SIG_PARTS order).
        cands = [(PART_FREQ.get(p, 0), i, s, l) for i, (p, s, l) in enumerate(SIG_PARTS) if p in parts]
        sig, line = (min(cands)[2], min(cands)[3]) if cands else ("hop", "does a little hop")
    name = key[0].upper() + key[1:]
    description = desc.get(key) or (sp["form"] if sp and sp["form"] and sp["form"].lower() != title.lower() else title)
    wearable = fam[6]
    motion = fam[7]
    preferred = {"originals": "bouncy" if energy >= 0.6 else "wobbly", "angels": "floating", "underground": "pulsing",
                 "enchanted": "swaying", "stardust": "orbiting", "dreamers": "drifting", "legends": "majestic",
                 "tideborn": "drifting", "skyweavers": "floating", "cinderlings": "flickering", "mosslight-grove": "swaying",
                 "aurora-vale": "shimmering", "clocklings": "ticking", "sugarvale": "bobbing", "inkbound-atelier": "drifting",
                 "neon-arcade": "pulsing", "lantern-parade": "glowing"}[fam[0]]
    # Reactions map onto the shared MascotMood vocabulary + one shared primitive each.
    tap_mood = "excited" if energy >= 0.7 else ("happy" if energy >= 0.4 else "pleased")
    reactions = {
        "tap": {"mood": tap_mood, "primitive": "squashStretch" if fam[0] in ("originals", "underground") else "translate", "burst": "pop", "durationMs": 900},
        "doubleTap": {"mood": "laughing" if social >= 0.55 else "happy", "primitive": "particleBurst", "burst": "hearts", "durationMs": 1200},
        "longPress": {"mood": "shy" if social < 0.45 else "pleased", "primitive": "scale", "burst": "aura", "durationMs": 1600},
        "horizontalDrag": {"mood": "dizzy" if energy >= 0.6 else "curious", "primitive": "rotate", "burst": None, "durationMs": 700},
        "greeting": {"mood": "wave", "primitive": "translate", "burst": "sparkle", "durationMs": 1400},
        "equip": ({"mood": "excited" if energy >= 0.6 else "pleased", "primitive": "accessoryFollow", "burst": "outfit", "durationMs": 1100}
                  if wearable else {"mood": "pleased", "primitive": "glowIntensity", "burst": "aura", "durationMs": 1100,
                                    "note": "Legends wear their own look; equip shows an admire reaction and never changes the outfit"}),
        "idleTimeout": {"mood": "sleepy", "primitive": "scale", "burst": None, "durationMs": 2400, "afterSeconds": 45},
        "foreground": {"mood": "happy", "primitive": "translate", "burst": None, "durationMs": 800},
        "signature": {"id": sig, "mood": "excited" if energy >= 0.6 else "happy", "primitive": "layerOffset", "burst": "sparkle",
                      "durationMs": 1500, "line": f"{name} {line}"},
    }
    nid = f"moliboo.{number:03d}"
    if nid in seen: raise SystemExit(f"duplicate {nid}")
    seen.add(nid)
    characters.append({
        "id": nid, "number": number, "key": key, "name": name, "familyId": fam[0], "title": title, "traits": traits,
        "assetVersion": "1.0.0", "rendering": "2d",
        "baseAsset": f"native2d:{'spec' if sp else 'figure'}/{key}",
        "body": sp["body"] if sp else "figure", "parts": parts,
        "wearable": wearable,
        "accessoryProfile": f"fit/{key}" if wearable else None,
        "expressions": ["neutral", "happy", "excited", "curious", "sleepy", "surprised", "sad"],
        "animations": [f"idle/{motion}", "tap", "doubleTap", "longPress", "greeting", "equip" if wearable else "admire", f"signature/{sig}"],
        "reactionSet": f"{key}.reactions", "reactions": reactions,
        "personality": {"archetype": archetype, "energy": energy, "curiosity": curiosity, "sociability": social,
                        "description": description,
                        "disclaimer": "Behavioural styling metadata only; Moliboos do not have real emotions or awareness."},
        "preferredMotion": preferred, "idleSet": f"{fam[0]}.{archetype}", "motionProfile": motion,
        "packageId": f"moliboo.character.{number:03d}",
        "availability": "released", "purchasable": False,
    })

# Series 2 drafts. Concept numbers 101–200 stay in the source file; catalogue numbers are +15
# so they sit after Legends 101–115. Nothing here is purchasable and no artwork is native2d.
SERIES2_OFFSET = 15
SERIES2_MOTION = {
    "tideborn": ("tideborn.swell", "drifting"),
    "skyweavers": ("skyweavers.glide", "floating"),
    "cinderlings": ("cinderlings.flicker", "flickering"),
    "mosslight-grove": ("mosslight-grove.settle", "swaying"),
    "aurora-vale": ("aurora-vale.shimmer", "shimmering"),
    "clocklings": ("clocklings.tick", "ticking"),
    "sugarvale": ("sugarvale.bob", "bobbing"),
    "inkbound-atelier": ("inkbound-atelier.drift", "drifting"),
    "neon-arcade": ("neon-arcade.pulse", "pulsing"),
    "lantern-parade": ("lantern-parade.glow", "glowing"),
}
def slug_family(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")

def append_series2():
    genesis_path = ROOT / "Tools/moliboo/registry/series2/moliboo_marketplace_genesis.json"
    accents_path = ROOT / "Tools/moliboo/registry/series2/accents.json"
    genesis = json.loads(genesis_path.read_text())
    accents = json.loads(accents_path.read_text())
    if genesis.get("schema") != "modula.moliboo.marketplace-concepts.v1":
        raise SystemExit("unexpected Series 2 concept schema")
    concepts = genesis["characters"]
    collections = genesis["collections"]
    if [c["concept_number"] for c in concepts] != list(range(101, 201)):
        raise SystemExit("Series 2 concepts must be 101–200 in order")
    if len(collections) != 10 or any(c.get("count") != 10 for c in collections):
        raise SystemExit("Series 2 must be 10 families of 10")
    by_collection = {}
    for c in concepts:
        by_collection.setdefault(c["collection"], []).append(c)
    if [c["name"] for c in collections] != list(by_collection):
        raise SystemExit("Series 2 family order does not match the concept file")
    existing_keys = {c["key"] for c in characters}
    existing_lines = {c["reactions"]["signature"]["line"] for c in characters}
    families_out = []
    for col in collections:
        members = by_collection[col["name"]]
        if len(members) != 10:
            raise SystemExit(f"{col['name']} does not have 10 concepts")
        fid = slug_family(col["name"])
        if fid not in SERIES2_MOTION:
            raise SystemExit(f"no motion profile for {fid}")
        concept_lo = members[0]["concept_number"]
        concept_hi = members[-1]["concept_number"]
        if [m["concept_number"] for m in members] != list(range(concept_lo, concept_hi + 1)):
            raise SystemExit(f"{col['name']} concept numbers are not contiguous")
        motion, preferred = SERIES2_MOTION[fid]
        first_accent = accents[str(concept_lo)]["mid"]
        families_out.append({
            "id": fid, "name": col["name"], "label": col["name"],
            "range": [concept_lo + SERIES2_OFFSET, concept_hi + SERIES2_OFFSET],
            "world": col["name"], "wearable": False, "motionProfile": motion,
            "series": 2, "availability": "draft",
            "palette": col["palette"], "artDirection": col["art_direction"],
            "accentHex": first_accent,
        })
        for concept in members:
            number = concept["concept_number"] + SERIES2_OFFSET
            if not (116 <= number <= 215):
                raise SystemExit(f"catalogue number {number} is outside Series 2")
            key = concept["name"].lower()
            if not re.fullmatch(r"[a-z][a-z0-9]*", key):
                raise SystemExit(f"unsafe Series 2 key {key}")
            if key in existing_keys:
                raise SystemExit(f"Series 2 key {key} collides with the built-in roster")
            existing_keys.add(key)
            if concept.get("registry_character_id") is not None:
                raise SystemExit(f"{key} already has a registry id in the concept file")
            if concept.get("marketplace_status") != "draft" or concept.get("purchasable") is not False:
                raise SystemExit(f"{key} is not a non-purchasable draft")
            if concept.get("concept_id") != f"moliboo.concept.{concept['concept_number']}":
                raise SystemExit(f"{key} concept id mismatch")
            if concept.get("source_class") != "modula_house_concept":
                raise SystemExit(f"{key} is not a house concept")
            accent = accents.get(str(concept["concept_number"]))
            if not accent or not all(re.fullmatch(r"#[0-9A-F]{6}", accent[k] or "") for k in ("light", "mid", "deep")):
                raise SystemExit(f"{key} is missing artwork accent colours")
            title = concept["personality"].strip()
            appearance = concept["appearance_2d"].strip()
            traits = [part[:1].upper() + part[1:] for part in title.split() if part]
            if not title or not appearance or not traits:
                raise SystemExit(f"{key} is missing personality or appearance")
            w = words(traits, title)
            be, bc, bs = FAMILY_BIAS[fid]
            energy = clamp(0.5 + 0.17 * (len(w & HI_E) - len(w & LO_E)) + be)
            curiosity = clamp(0.5 + 0.18 * len(w & CUR) + bc)
            social = clamp(0.5 + 0.16 * (len(w & SOC) - len(w & UNSOC)) + bs)
            archetype = next((a for a, s in ARCH if w & s), {
                "tideborn": "curious", "skyweavers": "dreamy", "cinderlings": "playful",
                "mosslight-grove": "gentle", "aurora-vale": "mysterious", "clocklings": "curious",
                "sugarvale": "playful", "inkbound-atelier": "wise", "neon-arcade": "playful",
                "lantern-parade": "playful"}[fid])
            line = f"{concept['name']} — {appearance}"
            if line in existing_lines:
                raise SystemExit(f"signature line collision: {line}")
            existing_lines.add(line)
            tap_mood = "excited" if energy >= 0.7 else ("happy" if energy >= 0.4 else "pleased")
            reactions = {
                "tap": {"mood": tap_mood, "primitive": "translate", "burst": "pop", "durationMs": 900},
                "doubleTap": {"mood": "laughing" if social >= 0.55 else "happy", "primitive": "particleBurst", "burst": "hearts", "durationMs": 1200},
                "longPress": {"mood": "shy" if social < 0.45 else "pleased", "primitive": "scale", "burst": "aura", "durationMs": 1600},
                "horizontalDrag": {"mood": "dizzy" if energy >= 0.6 else "curious", "primitive": "rotate", "burst": None, "durationMs": 700},
                "greeting": {"mood": "wave", "primitive": "translate", "burst": "sparkle", "durationMs": 1400},
                "equip": {"mood": "pleased", "primitive": "glowIntensity", "burst": "aura", "durationMs": 1100,
                          "note": "Series 2 drafts are not wearable and not purchasable; equip never changes a saved outfit."},
                "idleTimeout": {"mood": "sleepy", "primitive": "scale", "burst": None, "durationMs": 2400, "afterSeconds": 45},
                "foreground": {"mood": "happy", "primitive": "translate", "burst": None, "durationMs": 800},
                "signature": {"id": f"draft{number}", "mood": "excited" if energy >= 0.6 else "happy",
                              "primitive": "glowIntensity", "burst": "sparkle", "durationMs": 1500, "line": line},
            }
            characters.append({
                "id": f"moliboo.{number:03d}", "number": number, "key": key, "name": concept["name"],
                "familyId": fid, "title": title, "traits": traits,
                "assetVersion": "0.1.0", "rendering": "2d",
                "baseAsset": f"package:moliboo.character.{number:03d}/portrait.png",
                "body": "portrait", "parts": [],
                "wearable": False, "accessoryProfile": None,
                "expressions": ["neutral", "happy", "excited", "curious", "sleepy", "surprised", "sad"],
                "animations": [f"idle/{motion}", "tap", "doubleTap", "longPress", "greeting", "admire", f"signature/draft{number}"],
                "reactionSet": f"{key}.reactions", "reactions": reactions,
                "personality": {"archetype": archetype, "energy": energy, "curiosity": curiosity, "sociability": social,
                                "description": appearance,
                                "disclaimer": "Behavioural styling metadata only; Moliboos do not have real emotions or awareness."},
                "preferredMotion": preferred, "idleSet": f"{fid}.{archetype}", "motionProfile": motion,
                "packageId": f"moliboo.character.{number:03d}",
                "availability": "draft", "purchasable": False,
                "conceptId": concept["concept_id"],
            })
    return families_out

series2_families = append_series2()
characters.sort(key=lambda c: c["number"])
if [c["number"] for c in characters] != list(range(1, 216)):
    raise SystemExit("catalogue numbers must be 1–215 with no gaps")
if len({c["key"] for c in characters}) != 215 or len({c["id"] for c in characters}) != 215:
    raise SystemExit("catalogue ids or keys are not unique")
registry = {
    "schemaVersion": "modula.moliboo.registry.1",
    "registryVersion": "1.1.0",
    "generator": "Tools/moliboo/registry/generate_registry.py",
    "coordinateConvention": "2D fits are fractions of the figure size s, measured from the centre of the figure canvas (2.0s x 1.9s); x grows right, y grows DOWN; rotation in degrees clockwise; zIndex orders wardrobe layers (back < body < face < front).",
    "expressionContract": {"states": ["neutral", "happy", "excited", "curious", "sleepy", "surprised", "sad"],
        "moodMap": {"neutral": "idle", "happy": "happy", "excited": "excited", "curious": "curious", "sleepy": "sleepy", "surprised": "surprised", "sad": "sad"},
        "transition": {"crossfadeMs": 220, "reducedMotionCrossfadeMs": 0, "interruptible": True, "blink": "optional"}},
    "animationPrimitives": PRIMITIVES,
    "motionProfiles": MOTION,
    "families": [{"id": f[0], "name": f[1], "label": f[2], "range": [f[3], f[4]], "world": f[5], "wearable": f[6], "motionProfile": f[7], "series": 1, "availability": "released"} for f in FAMILIES] + series2_families,
    "characters": characters,
}
text = json.dumps(registry, indent=2, ensure_ascii=False) + "\n"
if CHECK:
    cur = OUT.read_text() if OUT.exists() else ""
    if cur != text:
        print("moliboo_registry.json is stale; run Tools/moliboo/registry/generate_registry.py"); sys.exit(1)
    print(f"registry up to date ({len(characters)} characters)"); sys.exit(0)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(text)
fams = {}
for c in characters: fams[c["familyId"]] = fams.get(c["familyId"], 0) + 1
print(f"wrote {OUT} characters={len(characters)} families={fams} sha256={hashlib.sha256(text.encode()).hexdigest()[:16]}")
