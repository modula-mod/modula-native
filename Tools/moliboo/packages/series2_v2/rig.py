"""Export a MascotRig-compatible fit for a rendered Series 2 portrait.

Rig convention (MascotRig / MolibooFitProfiles): fractions of figure size s, measured from the centre of the
figure canvas (2.0s x 1.9s), x right, y DOWN. The portrait PNG (640 px) is drawn as a square of side `side`*s
centred at (`cx`, `cy`)*s, so every anchor below lines up with the baked art.
"""
import numpy as np
from core import OUT, U

SHAPE = {"round": "round", "egg": "round", "mochi": "round", "lumpy": "round", "pear": "round", "onion": "round",
         "wide": "wide", "flat": "wide", "squircle": "square", "cube": "square", "drop": "drop", "cloud": "cloud",
         "ghost": "dome", "bell": "dome", "star": "star", "tall": "tall"}

def r4(v): return round(float(v), 4)

def export(f):
    g = f.geo; bb, k, off = f.fit
    def out(px, py):  # S-px -> output px
        return ((px - bb[0]) * k + off[0], (py - bb[1]) * k + off[1])
    m = np.asarray(g["bm"]) > 127
    ys, xs = np.nonzero(m)
    bx0, by0 = out(xs.min(), ys.min()); bx1, by1 = out(xs.max(), ys.max())
    bw_out = bx1 - bx0
    side = min(1.75, max(1.15, 0.98 * OUT / bw_out))
    sc = side / OUT                         # rig units per output px
    bcx, bcy = (bx0 + bx1) / 2, (by0 + by1) / 2
    dx = -(bcx - OUT / 2) * sc
    dy = 0.10 - (bcy - OUT / 2) * sc
    half = 0.4375 * side                    # content extent (40 px pad)
    dy = min(max(dy, -0.95 + half + 0.0), 0.95 - half)
    dx = min(max(dx, -1.0 + half), 1.0 - half)
    def R(px, py): return (dx + (px - OUT / 2) * sc, dy + (py - OUT / 2) * sc)
    _, top = R(0, by0); _, bot = R(0, by1)
    D = k * U * sc                          # rig units per design unit
    _, eyeY = R(0, out(0, g["eyey"] * U)[1])
    er = g["er"] * D
    _, mouthY = R(0, out(0, g["mouthy"] * U)[1])
    mouth_bottom = mouthY + 0.2 * g["rx"] * D * 0.5
    _, footY = R(0, out(0, g["feet_bottom"] * U)[1])
    # true head top on the centre column of the body mask
    col = int(round(g["cx"] * U))
    cyx = np.nonzero(m[:, max(0, col - 3):col + 4].any(1))[0]
    _, centreTop = R(0, out(0, cyx.min())[1])
    eyeSize = 2 * er                        # rig eyeTop = eyeY - 0.62*eyeSize covers bead + glow ring
    eyeTop = eyeY - eyeSize * 0.62
    headTop = min(centreTop + 0.03, eyeTop - 0.01)
    def chord(y_rig):
        py = OUT / 2 + (y_rig - dy) / sc
        sy = int(round((py - off[1]) / k + bb[1]))
        if sy < 0 or sy >= m.shape[0]: return 0.0
        row = np.nonzero(m[sy])[0]
        return 0.0 if len(row) == 0 else (row.max() - row.min()) * k * sc
    shape = SHAPE[g["body"]]
    return {
        "schemaVersion": "modula.moliboo.portraitRig.1",
        "portrait": {"side": r4(side), "cx": r4(dx), "cy": r4(dy)},
        "shape": shape, "bodyW": r4(bw_out * sc), "bodyH": r4(bot - top), "bodyY": r4((top + bot) / 2),
        "eyeY": r4(eyeY), "eyeSize": r4(eyeSize), "eyeSpread": r4(g["espread"] * D),
        "mouthY": r4(max(mouthY, mouth_bottom - 0.07)), "footY": r4(max(footY, bot)),
        "hasFeet": not g["floats"], "hasLegs": not g["floats"], "floats": bool(g["floats"]),
        "allowsTop": shape not in ("star",), "headTop": r4(headTop),
        "hatMaxWidth": r4(min(0.74, max(0.34, chord(headTop + 0.1) * 1.02))),
        "measuredChordAtNeck": r4(chord(max(mouthY, mouth_bottom - 0.07) + 0.08)),
    }
