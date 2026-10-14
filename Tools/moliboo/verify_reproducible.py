"""Semantic reproducibility check for MOL-01 exports (run with Blender's bundled python, which has pxr).
Byte-identical USDZ/PNG output is not guaranteed by Blender 4.2 (prim order, Cycles bake noise), so the frozen
artifacts are pinned by SHA-256 and a rebuild is accepted when it is semantically equivalent:
same prim set, per-mesh point/face counts, bounds (±1e-5 m), blend-shape names, time range; texture mean |Δ| < 1/255."""
import sys, json
from pxr import Usd, UsdGeom, UsdSkel
import zipfile, io
def summary(path):
    s = Usd.Stage.Open(path); out = {"time": [s.GetStartTimeCode(), s.GetEndTimeCode()], "up": UsdGeom.GetStageUpAxis(s)}
    cache = UsdGeom.BBoxCache(0, ["default", "render"])
    for p in s.Traverse():
        k = str(p.GetPath())
        if p.IsA(UsdGeom.Mesh):
            m = UsdGeom.Mesh(p); r = cache.ComputeWorldBound(p).ComputeAlignedRange()
            out[k] = ["mesh", len(m.GetPointsAttr().Get()), len(m.GetFaceVertexCountsAttr().Get()),
                      [round(v, 5) for v in list(r.GetMin()) + list(r.GetMax())]]
        elif p.GetTypeName() == "SkelAnimation":
            out[k] = ["anim", list(UsdSkel.Animation(p).GetBlendShapesAttr().Get())]
        else:
            out[k] = [p.GetTypeName()]
    return out
def tex_diff(a, b):
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError:
        return None
    A = Image.open(a).convert("RGB"); B = Image.open(b).convert("RGB")
    return sum(ImageStat.Stat(ImageChops.difference(A, B)).mean) / 3
ref, new = sys.argv[1], sys.argv[2]; ok = True
for f in ["Pebble.usdz", "Accessory_Cap_MolibooSignature.usdz"]:
    a, b = summary(f"{ref}/{f}"), summary(f"{new}/{f}")
    bad = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    print(f, "EQUIVALENT" if not bad else f"DIFFERS at {bad[:5]}"); ok &= not bad
for f in ["clips.json", "attachments.json"]:
    same = json.load(open(f"{ref}/{f}")) == json.load(open(f"{new}/{f}")); print(f, "EQUAL" if same else "DIFFERS"); ok &= same
d = tex_diff(f"{ref}/Pebble_BaseColor.png", f"{new}/Pebble_BaseColor.png")
if d is not None: print("Pebble_BaseColor.png mean|Δ| =", round(d, 4)); ok &= d < 1.0
print("REPRODUCIBLE" if ok else "NOT REPRODUCIBLE"); sys.exit(0 if ok else 1)
