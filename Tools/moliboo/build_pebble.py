# MOL-01 Pebble (#010) v2.2-frozen — refined to match the original Modula Pebble reference art.
# Reproducible: blender -b -P build_pebble.py -- <outdir>     (Blender 4.2.3 LTS)
# Outputs: Pebble.blend (editable), Pebble_BaseColor.png (baked), Pebble.usdz, Accessory_Cap_MolibooSignature.usdz, clips.json, attachments.json
import bpy, bmesh, sys, math, json, random
from mathutils import Vector, Matrix, noise
out = sys.argv[sys.argv.index("--")+1]
random.seed(10)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.fps = 30

# ---------- materials
def principled(name, rgb, rough=0.35, coat=0.0, sss=0.0, spec=0.5):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat; b.inputs["Subsurface Weight"].default_value = sss
    b.inputs["Specular IOR Level"].default_value = spec
    return m

M_BODY = principled("PebbleStone", (0.72, 0.74, 0.88), rough=0.36, coat=0.40, sss=0.12)
M_BODY.node_tree.nodes["Principled BSDF"].inputs["Coat Roughness"].default_value = 0.22
nt = M_BODY.node_tree; N = nt.nodes; L = nt.links; B = N["Principled BSDF"]
tc = N.new("ShaderNodeTexCoord"); sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
# vertical gradient: mint/teal near the base → lavender-grey body → pale top
grad = N.new("ShaderNodeMapRange"); grad.inputs["From Min"].default_value = 0.0; grad.inputs["From Max"].default_value = 0.10
L.new(sep.outputs["Z"], grad.inputs["Value"])
ramp = N.new("ShaderNodeValToRGB"); E = ramp.color_ramp.elements
E[0].position = 0.0; E[0].color = (0.26, 0.58, 0.54, 1)
E[1].position = 1.0; E[1].color = (0.60, 0.62, 0.86, 1)
e = E.new(0.16); e.color = (0.32, 0.44, 0.66, 1)
e = E.new(0.55); e.color = (0.42, 0.44, 0.74, 1)
L.new(grad.outputs["Result"], ramp.inputs["Fac"])
# soft cloudy variation + sparse mint flecks (stone surface detail)
cloud = N.new("ShaderNodeTexNoise"); cloud.inputs["Scale"].default_value = 18; cloud.inputs["Detail"].default_value = 4
mixc = N.new("ShaderNodeMix"); mixc.data_type = "RGBA"; mixc.blend_type = "OVERLAY"; mixc.inputs["Factor"].default_value = 0.12
L.new(ramp.outputs["Color"], mixc.inputs[6]); L.new(cloud.outputs["Color"], mixc.inputs[7])
fl = N.new("ShaderNodeTexNoise"); fl.inputs["Scale"].default_value = 90
fr = N.new("ShaderNodeValToRGB"); fr.color_ramp.elements[0].position = 0.735; fr.color_ramp.elements[1].position = 0.755
L.new(fl.outputs["Fac"], fr.inputs["Fac"])
mixf = N.new("ShaderNodeMix"); mixf.data_type = "RGBA"; mixf.inputs[7].default_value = (0.62, 0.92, 0.84, 1)
L.new(fr.outputs["Color"], mixf.inputs["Factor"]); L.new(mixc.outputs[2], mixf.inputs[6])
# deep-slate mineral specks + faint veins (subtle; identity unchanged)
dk = N.new("ShaderNodeTexNoise"); dk.inputs["Scale"].default_value = 140
dr = N.new("ShaderNodeValToRGB"); dr.color_ramp.elements[0].position = 0.73; dr.color_ramp.elements[1].position = 0.75
L.new(dk.outputs["Fac"], dr.inputs["Fac"])
mixd = N.new("ShaderNodeMix"); mixd.data_type = "RGBA"; mixd.inputs[7].default_value = (0.30, 0.33, 0.48, 1)
L.new(dr.outputs["Color"], mixd.inputs["Factor"]); L.new(mixf.outputs[2], mixd.inputs[6])
wv = N.new("ShaderNodeTexWave"); wv.inputs["Scale"].default_value = 4; wv.inputs["Distortion"].default_value = 9; wv.inputs["Detail"].default_value = 3
vr = N.new("ShaderNodeValToRGB"); vr.color_ramp.elements[0].position = 0.0; vr.color_ramp.elements[1].position = 0.08
vr.color_ramp.elements[0].color = (1, 1, 1, 1); vr.color_ramp.elements[1].color = (0, 0, 0, 1)
L.new(wv.outputs["Fac"], vr.inputs["Fac"])
vmul = N.new("ShaderNodeMath"); vmul.operation = "MULTIPLY"; vmul.inputs[1].default_value = 0.035
L.new(vr.outputs["Color"], vmul.inputs[0])
mixv = N.new("ShaderNodeMix"); mixv.data_type = "RGBA"; mixv.inputs[7].default_value = (0.90, 0.92, 0.98, 1)
L.new(vmul.outputs[0], mixv.inputs["Factor"]); L.new(mixd.outputs[2], mixv.inputs[6])
L.new(mixv.outputs[2], B.inputs["Base Color"])
# micro surface bump
bn = N.new("ShaderNodeBump"); bn.inputs["Strength"].default_value = 0.05
L.new(cloud.outputs["Fac"], bn.inputs["Height"]); L.new(bn.outputs["Normal"], B.inputs["Normal"])

M_EYE = principled("PebbleEye", (0.02, 0.025, 0.05), rough=0.4, coat=0.0, spec=0.08)
M_IRIS = principled("PebbleIrisBlue", (0.22, 0.48, 0.95), rough=0.4, coat=0.0, spec=0.08)
M_SHINE = principled("PebbleEyeShine", (1, 1, 1), rough=0.05)
M_SHINE.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 1, 1, 1)
M_SHINE.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2.0
M_MOUTH = principled("PebbleMouth", (0.16, 0.08, 0.16), rough=0.4)
M_CHEEK = principled("PebbleCheek", (0.93, 0.58, 0.78), rough=0.6)
M_CAP = principled("CapBlue", (0.16, 0.24, 0.92), rough=0.32, coat=0.5)
M_POM = principled("CapPomWhite", (0.96, 0.96, 0.98), rough=0.85, sss=0.2)
M_LEAF = principled("SprigGreen", (0.25, 0.70, 0.18), rough=0.45, coat=0.3)

def smooth(o):
    for p in o.data.polygons: p.use_smooth = True
    return o

# ---------- body: wide, low, asymmetric (higher on the left), soft base
bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, radius=1.0)
body = bpy.context.object; body.name = "Pebble_Body"
W, D, Hh = 0.088, 0.060, 0.064      # half-width, half-depth, half-height (m) → ~0.176 × 0.12 × ~0.094
for v in body.data.vertices:
    x, y, z = v.co
    lean = 1.0 + 0.16 * (-x) * max(z, 0)          # left side (−x) rises
    zz = z * lean
    if zz < -0.35: zz = -0.35 - (-(zz + 0.35)) * 0.25   # soft flattened base (not a hard cut)
    p = Vector((x * W, y * D, zz * Hh))
    p += Vector((x, y, z)) * 0.0012 * noise.noise(Vector((x, y, z)) * 2.3)  # gentle organic lumps
    v.co = p
bpy.ops.object.transform_apply()
mn = min(v.co.z for v in body.data.vertices)
for v in body.data.vertices: v.co.z -= mn
smooth(body); body.data.materials.append(M_BODY)
m = body.modifiers.new("Subd", "SUBSURF"); m.levels = 1
bpy.ops.object.modifier_apply(modifier="Subd")
root = bpy.data.objects.new("Pebble", None); sc.collection.objects.link(root); body.parent = root

def surface(x, z, inset=0.0):
    """Point + normal on the front (−Y) surface of the body at (x, z)."""
    ok, loc, nrm, _ = body.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
    assert ok, (x, z)
    return loc - nrm * inset, nrm

def on_surface(obj, x, z, inset=0.0):
    loc, nrm = surface(x, z, inset)
    obj.location = loc
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, -1, 0)).rotation_difference(-nrm) if False else Vector((0, 0, 1)).rotation_difference(nrm)
    obj.parent = root

def disc(name, r, depth, mat, segs=40):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs//2, radius=1)
    o = bpy.context.object; o.name = name; o.scale = (r, r, depth); bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat); return smooth(o)

# ---------- face: big wide-set glossy eyes with blue lower iris and two highlights
EYE_Z, EYE_X, ER = 0.058, 0.030, 0.0118
for side, sx in (("L", -1), ("R", 1)):
    x = sx * EYE_X
    eye = disc(f"Pebble_Eye_{side}", ER, 0.0035, M_EYE); eye.scale = (1, 1.12, 1)  # local Y = vertical on face after orient
    bpy.ops.object.transform_apply(scale=True)
    on_surface(eye, x, EYE_Z, inset=0.0006)
    # iris: lower crescent (blue) — a disc clipped to the lower half, sits just in front of the eye
    iris = disc(f"Pebble_Iris_{side}", ER * 0.78, 0.0012, M_IRIS)
    for v in iris.data.vertices:
        if v.co.y > -ER * 0.05: v.co.y = -ER * 0.05 + (v.co.y + ER * 0.05) * 0.05
    on_surface(iris, x, EYE_Z - ER * 0.30, inset=-0.0026)
    s1 = disc(f"Pebble_EyeShine_{side}", ER * 0.30, 0.001, M_SHINE, 16); on_surface(s1, x - ER * 0.28, EYE_Z + ER * 0.38, inset=-0.0036)
    s2 = disc(f"Pebble_EyeShine2_{side}", ER * 0.13, 0.001, M_SHINE, 12); on_surface(s2, x + ER * 0.35, EYE_Z - ER * 0.15, inset=-0.0036)
    ch = disc(f"Pebble_Cheek_{side}", 0.0095, 0.0016, M_CHEEK, 24); ch.scale = (1, 0.62, 1); bpy.ops.object.transform_apply(scale=True)
    on_surface(ch, sx * 0.050, 0.044, inset=0.0004)

# eye shape keys (applied in the eye's local frame: local Y = up on the face)
for side in "LR":
    for nm in (f"Pebble_Eye_{side}", f"Pebble_Iris_{side}"):
        o = bpy.data.objects[nm]; o.shape_key_add(name="Basis")
        def key(n, f):
            k = o.shape_key_add(name=n)
            for i, v in enumerate(o.data.vertices): k.data[i].co = f(v.co.copy())
        key("blink", lambda p: Vector((p.x * 1.05, p.y * 0.06 - ER * 0.25, p.z * 0.6)))
        if "Iris" in nm: key("happy", lambda p: Vector((0.0, ER * 0.37, 0.0)))   # zero-area point: no sliver at any angle
        else: key("happy", lambda p: Vector((p.x * 1.05, ER * 0.42 * (1 - (p.x / ER) ** 2) - ER * 0.05 + p.y * 0.16, p.z * 0.7)))   # ^ arc
        key("sleepy", lambda p: Vector((p.x, min(p.y, ER * 0.15) * 0.75 - ER * 0.12, p.z)))
        key("excited", lambda p: p * 1.18)
        key("surprised", lambda p: Vector((p.x * 0.86, p.y * 1.06, p.z)))

for side in "LR":
    for nm in (f"Pebble_EyeShine_{side}", f"Pebble_EyeShine2_{side}"):
        o = bpy.data.objects[nm]; o.shape_key_add(name="Basis")
        for kn, f in (("blink", 0.0), ("happy", 0.0), ("sleepy", 0.4), ("excited", 1.25), ("surprised", 1.0)):
            k = o.shape_key_add(name=kn)
            for i, v in enumerate(o.data.vertices): k.data[i].co = v.co * f
        kb = o.data.shape_keys.key_blocks["blink"]
        for f, v in ((1, 0), (61, 0), (65, 1), (68, 1), (72, 0), (130, 0)): kb.value = v; kb.keyframe_insert("value", frame=f)

# mouth: tiny curve on the surface; shape keys for every expression
bm = bmesh.new(); NS = 16; MW = 0.0075
for i in range(NS + 1):
    t = -1 + 2 * i / NS; x = MW * t; zc = -0.0012 * (1 - t * t)
    for dz in (0.0009, -0.0009): bm.verts.new((x, 0, zc + dz))
bm.verts.ensure_lookup_table()
for i in range(NS): bm.faces.new((bm.verts[2*i], bm.verts[2*i+1], bm.verts[2*i+3], bm.verts[2*i+2]))
me = bpy.data.meshes.new("Pebble_Mouth"); bm.to_mesh(me)
mouth = bpy.data.objects.new("Pebble_Mouth", me); sc.collection.objects.link(mouth); mouth.data.materials.append(M_MOUTH)
sol = mouth.modifiers.new("S", "SOLIDIFY"); sol.thickness = 0.0012
bpy.context.view_layer.objects.active = mouth; bpy.ops.object.select_all(action="DESELECT"); mouth.select_set(True)
bpy.ops.object.modifier_apply(modifier="S")
mloc, mn_ = surface(0, 0.044); mouth.location = mloc + Vector((0, -0.0004, 0)); mouth.parent = root
mouth.shape_key_add(name="Basis")
def mkey(n, f):
    k = mouth.shape_key_add(name=n)
    for i, v in enumerate(mouth.data.vertices): k.data[i].co = f(v.co.copy())
u = lambda p: 1 - (p.x / MW) ** 2
cv = lambda p: -0.0012 * (1 - (p.x / MW) ** 2)
topm = lambda p: p.z > cv(p)
mkey("happy", lambda p: Vector((p.x * 1.3, p.y, (p.z - cv(p)) + cv(p) * 2.2)))
mkey("excited", lambda p: Vector((p.x * 1.2, p.y, (0.0006 - 0.0007 * u(p)) if topm(p) else -0.0068 * max(u(p), 0) ** 0.5)))
mkey("surprised", lambda p: Vector((p.x * 0.42, p.y, (0.0016 if topm(p) else -0.0030) * max(u(p), 0) ** 0.5 - 0.0008)))
mkey("sleepy", lambda p: Vector((p.x * 0.6, p.y, p.z * 0.3)))
def conform(kname):
    kb = mouth.data.shape_keys.key_blocks[kname]
    for d in kb.data:
        w = mouth.location + d.co
        ok, loc, nrm, _ = body.ray_cast(Vector((w.x, -1, w.z)), Vector((0, 1, 0)))
        if ok: d.co.y += (loc.y - 0.0007) - w.y + (d.co.y - 0.0)   # keep ribbon thickness, sit 0.7 mm proud
mkey("sad", lambda p: Vector((p.x, p.y, -p.z - 0.0012)))
mkey("pout", lambda p: Vector((p.x * 0.7, p.y, -p.z * 1.6 - 0.002)))   # reference card "^" mouth
for kn in [k.name for k in mouth.data.shape_keys.key_blocks]: conform(kn)

# ---------- conform face parts onto the curved body (no side-profile protrusion)
def conform(obj, offset, depth_keep=0.15):
    """Snap every vertex of every shape key onto the body surface (+offset)."""
    mw = obj.matrix_world.copy(); inv = mw.inverted()
    blocks = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    targets = [kb.data for kb in blocks] if blocks else [obj.data.vertices]
    for data in targets:
        for d in data:
            w = mw @ d.co
            ok, loc, _, _ = body.ray_cast(Vector((w.x, -1, w.z)), Vector((0, 1, 0)))
            if not ok: continue
            w.y = loc.y - offset - max(d.co.z, -1) * depth_keep
            d.co = inv @ w
    if blocks:
        for v, b in zip(obj.data.vertices, blocks[0].data): v.co = b.co
bpy.context.view_layer.update()
for side in "LR":
    conform(bpy.data.objects[f"Pebble_Eye_{side}"], 0.0003)
    conform(bpy.data.objects[f"Pebble_Iris_{side}"], 0.0007)
    conform(bpy.data.objects[f"Pebble_EyeShine_{side}"], 0.0010)
    conform(bpy.data.objects[f"Pebble_EyeShine2_{side}"], 0.0010)
    conform(bpy.data.objects[f"Pebble_Cheek_{side}"], 0.0001)

# ---------- anchors (identity rotation; position on the surface)
def top(x, y):
    ok, loc, nrm, _ = body.ray_cast(Vector((x, y, 1)), Vector((0, 0, -1))); assert ok; return loc
anchors = {"anchor_head": top(0.040, 0.004) + Vector((0, 0, 0.004)), "anchor_face": surface(0, EYE_Z)[0],
           "anchor_back": Vector((0, D * 0.95, 0.050)), "anchor_neck": surface(0, 0.030)[0], "anchor_base": Vector((0, 0, 0))}
for name, loc in anchors.items():
    a = bpy.data.objects.new(name, None); a.empty_display_size = 0.01; a.location = loc; a.parent = root
    sc.collection.objects.link(a)

# ---------- bake base colour (gradient + cloud + flecks) so USDZ matches Blender
bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02); bpy.ops.object.mode_set(mode="OBJECT")
img = bpy.data.images.new("Pebble_BaseColor", 2048, 2048)
tn = N.new("ShaderNodeTexImage"); tn.image = img; N.active = tn
sc.render.engine = "CYCLES"; sc.cycles.samples = 1; sc.cycles.device = "CPU"
sc.render.bake.use_pass_direct = False; sc.render.bake.use_pass_indirect = False; sc.render.bake.margin = 16
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
img.filepath_raw = f"{out}/Pebble_BaseColor.png"; img.file_format = "PNG"; img.save()
img.filepath = f"//Pebble_BaseColor.png"
# keep the procedural graph in the .blend for editing, but drive Base Color from the bake for export parity
L.new(tn.outputs["Color"], B.inputs["Base Color"])
for n in (bn,): N.remove(n)   # USD preview surface cannot carry procedural bump

# ---------- hat: small curved blue cap, tilted, white pom-pom, optional leafy sprig
hatroot = bpy.data.objects.new("Accessory_Cap_MolibooSignature", None); sc.collection.objects.link(hatroot)
hatpivot = bpy.data.objects.new("Hat_Pivot", None); sc.collection.objects.link(hatpivot); hatpivot.parent = hatroot
# tilt is NOT baked: it lives in the per-character attachment config (attachments.json)
PEBBLE_CAP = {"offset": [0.0, 0.0, -0.0045], "rotationDegrees": [-8.0, 18.0, -25.0], "scale": 1.0}
bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1)
crown = bpy.context.object; crown.name = "Hat_Crown"
bm = bmesh.new(); bm.from_mesh(crown.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.05], context="VERTS"); bm.to_mesh(crown.data); bm.free()
crown.scale = (0.026, 0.024, 0.017); bpy.ops.object.transform_apply(scale=True)
sol = crown.modifiers.new("S", "SOLIDIFY"); sol.thickness = 0.0016; bpy.ops.object.modifier_apply(modifier="S")
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1, depth=0.0018)
brim = bpy.context.object; brim.name = "Hat_Brim"
for v in brim.data.vertices:   # forward-facing curved bill
    if v.co.y < 0: v.co.y *= 1.7
    v.co.z += 0.0010 * (min(v.co.y, 0) ** 2)   # peak curls slightly UP (no droop)
brim.scale = (0.024, 0.022, 1); brim.location = (0, -0.006, -0.0005); bpy.ops.object.transform_apply(location=False, scale=True)
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.0062, location=(0, 0, 0.0172))
pom = bpy.context.object; pom.name = "Hat_Pom"
for v in pom.data.vertices: v.co += v.co.normalized() * 0.0007 * noise.noise(v.co * 900)   # fluffy
for o, mt in ((crown, M_CAP), (brim, M_CAP), (pom, M_POM)):
    o.data.materials.append(mt); smooth(o); o.parent = hatpivot
sprig = bpy.data.objects.new("Hat_Sprig", None); sc.collection.objects.link(sprig); sprig.parent = hatpivot
sprig.location = (0.019, 0.006, 0.004)
def leaf_mesh(name, ln, wd):
    """Leaf blade: pointed tip, rounded base, folded along the midrib, tip curls up. Origin at the petiole."""
    bm = bmesh.new(); NU, NV = 14, 6; grid = []
    for i in range(NU + 1):
        t = i / NU; half = wd * math.sin(math.pi * t ** 0.8) * (1 - t ** 3) ** 0.5
        row = []
        for j in range(-NV, NV + 1):
            v = j / NV; x = t * ln; y = v * half
            z = 0.03 * abs(v) * half + 0.10 * ln * t ** 2      # midrib fold + tip curl
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for i in range(NU):
        for j in range(2 * NV):
            a, b, c, d = grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]
            if len({a, b, c, d}) == 4: bm.faces.new((a, b, c, d))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); sc.collection.objects.link(o)
    so = o.modifiers.new("S", "SOLIDIFY"); so.thickness = 0.0005; so.offset = 0
    bpy.context.view_layer.objects.active = o; bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    bpy.ops.object.modifier_apply(modifier="S")
    return o
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.0007, depth=0.010)
stem = bpy.context.object; stem.name = "Hat_Sprig_Stem"; stem.rotation_euler = (0, math.radians(55), 0)
stem.location = (0.003, 0, 0.003); stem.data.materials.append(M_LEAF); smooth(stem); stem.parent = sprig
for i, (yaw, pitch, ln, wd) in enumerate(((5, 62, 0.028, 0.0090), (45, 48, 0.024, 0.0080), (-35, 52, 0.023, 0.0078),
                                           (95, 35, 0.019, 0.0064), (-80, 38, 0.018, 0.0060))):
    lf = leaf_mesh(f"Hat_Leaf_{i}", ln, wd)
    lf.rotation_euler = (0, math.radians(-pitch), math.radians(yaw)); lf.location = (0.006, 0, 0.006)
    lf.data.materials.append(M_LEAF); smooth(lf); lf.parent = sprig
hatroot.location = anchors["anchor_head"] + Vector(PEBBLE_CAP["offset"])
hatroot.rotation_euler = [math.radians(a) for a in PEBBLE_CAP["rotationDegrees"]]
json.dump({"pebble": {"cap.moliboo.signature": dict(PEBBLE_CAP, anchor="anchor_head", compatible=True)}}, open(f"{out}/attachments.json", "w"), indent=1)

# ---------- animation clips on one timeline (frame ranges recorded in clips.json)
CLIPS = {"idle_bob": (1, 60), "blink": (61, 72), "wobble": (73, 102), "tap": (103, 130)}
root.rotation_mode = "XYZ"
def kf(obj, path, f, val, idx=None):
    if idx is None: setattr(obj, path, val); obj.keyframe_insert(path, frame=f)
    else: getattr(obj, path)[idx] = val; obj.keyframe_insert(path, index=idx, frame=f)
for f in (1, 61, 73, 103, 130): kf(root, "location", f, (0, 0, 0)); kf(root, "rotation_euler", f, (0, 0, 0)); kf(root, "scale", f, (1, 1, 1))
# idle: gentle bob + breathe
kf(root, "location", 30, (0, 0, 0.003)); kf(root, "scale", 30, (1.01, 1.01, 0.985)); kf(root, "location", 60, (0, 0, 0)); kf(root, "scale", 60, (1, 1, 1))
# wobble: side-to-side tilt
for f, a in ((78, 7), (84, -6), (90, 4), (96, -2), (102, 0)): kf(root, "rotation_euler", f, math.radians(a), 1)
# tap: squash → stretch hop → settle
kf(root, "scale", 108, (1.08, 1.08, 0.88)); kf(root, "scale", 114, (0.95, 0.95, 1.08)); kf(root, "location", 114, (0, 0, 0.012))
kf(root, "location", 121, (0, 0, 0)); kf(root, "scale", 121, (1.04, 1.04, 0.95)); kf(root, "scale", 130, (1, 1, 1))
# blink via shape keys
for side in "LR":
    for nm in (f"Pebble_Eye_{side}", f"Pebble_Iris_{side}"):
        kb = bpy.data.objects[nm].data.shape_keys.key_blocks["blink"]
        for f, v in ((1, 0), (61, 0), (65, 1), (68, 1), (72, 0), (130, 0)): kb.value = v; kb.keyframe_insert("value", frame=f)
mk = mouth.data.shape_keys.key_blocks["happy"]
for f, v in ((1, 0), (103, 0), (110, 1), (125, 1), (130, 0)): mk.value = v; mk.keyframe_insert("value", frame=f)
EXPR = {"idle": ({}, {}), "happy": ({"happy": 1}, {"happy": 1}), "excited": ({"excited": 1}, {"excited": 1}),
        "surprised": ({"surprised": 1}, {"surprised": 1}), "sleepy": ({"sleepy": 1}, {"sleepy": 1}), "sad": ({}, {"sad": 1})}
face = [o for o in sc.objects if o.type == "MESH" and o.data.shape_keys and o.name.startswith("Pebble_")]
f0 = 131
for name, (eyes, mouthk) in EXPR.items():
    a, b = f0, f0 + 5
    CLIPS[f"expr_{name}"] = (a, b)
    for o in face:
        want = mouthk if o.name == "Pebble_Mouth" else eyes
        for kb in o.data.shape_keys.key_blocks[1:]:
            for f in (a, b): kb.value = float(want.get(kb.name, 0)); kb.keyframe_insert("value", frame=f)
    for f in (a, b): kf(root, "location", f, (0, 0, 0)); kf(root, "rotation_euler", f, (0, 0, 0)); kf(root, "scale", f, (1, 1, 1))
    f0 = b + 1
for o in face:   # make sure earlier clips start from neutral on every key
    for kb in o.data.shape_keys.key_blocks[1:]:
        fc = o.data.shape_keys.animation_data and o.data.shape_keys.animation_data.action and \
             o.data.shape_keys.animation_data.action.fcurves.find(f'key_blocks["{kb.name}"].value')
        if fc and not any(abs(k.co.x - 1) < 0.5 for k in fc.keyframe_points): fc.keyframe_points.insert(1, 0.0)
sc.frame_start, sc.frame_end = 1, f0 - 1
json.dump({"fps": 30, "clips": {k: {"start": a, "end": b} for k, (a, b) in CLIPS.items()}}, open(f"{out}/clips.json", "w"), indent=1)
sc.frame_set(1)

bpy.ops.wm.save_as_mainfile(filepath=f"{out}/Pebble.blend")

def export(r, path, anim):
    bpy.ops.object.select_all(action="DESELECT")
    def sel(o): o.select_set(True); [sel(c) for c in o.children]
    sel(r)
    bpy.ops.wm.usd_export(filepath=path, selected_objects_only=True, export_materials=True, generate_preview_surface=True,
                          export_shapekeys=True, export_animation=anim, convert_orientation=True,
                          export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y")
saved = hatroot.location.copy(); hatroot.location = (0, 0, 0)
saved_rot = tuple(hatroot.rotation_euler); hatroot.rotation_euler = (0, 0, 0)
export(hatroot, f"{out}/Accessory_Cap_MolibooSignature.usdz", False)
hatroot.rotation_euler = saved_rot
hatroot.location = saved; hatroot.hide_set(True); hatroot.hide_render = True
for c in hatroot.children_recursive: c.hide_render = True
export(root, f"{out}/Pebble.usdz", True)
print("PEBBLE_BUILD_OK")
