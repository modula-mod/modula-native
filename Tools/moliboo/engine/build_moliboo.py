# MOL-02 shared Moliboo build engine (Blender 4.2.3 LTS). One engine, data-driven per character.
#   blender -b -P build_moliboo.py -- characters/<id>.json <outdir>
# Outputs: <Name>.blend (editable), <Name>_BaseColor.png (baked), <Name>.usdz, clips.json, attachments.json
# Pebble stays on its frozen v2.2 script (Tools/moliboo/build_pebble.py) until a refactor parity check is approved.
import bpy, bmesh, sys, math, json, random, os
from mathutils import Vector, noise
argv = sys.argv[sys.argv.index("--") + 1:]
SPEC = json.load(open(argv[0])); out = argv[1]; os.makedirs(out, exist_ok=True)
CID, NAME = SPEC["id"], SPEC["name"]; P = NAME + "_"
random.seed(SPEC.get("seed", 1))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.fps = 30

# ---------------- materials
def principled(name, rgb, rough=0.35, coat=0.0, sss=0.0, spec=0.5, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat; b.inputs["Subsurface Weight"].default_value = sss
    b.inputs["Specular IOR Level"].default_value = spec
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1); b.inputs["Emission Strength"].default_value = emit
    return m

def body_material(pal):
    m = principled(P + "Skin", pal["ramp"][-1][1], rough=pal.get("rough", 0.4), coat=pal.get("coat", 0.3), sss=pal.get("sss", 0.1))
    nt = m.node_tree; N = nt.nodes; L = nt.links; B = N["Principled BSDF"]
    B.inputs["Coat Roughness"].default_value = pal.get("coatRough", 0.25)
    tc = N.new("ShaderNodeTexCoord"); sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
    axis = pal.get("axis", "Z")
    g = N.new("ShaderNodeMapRange"); g.inputs["From Min"].default_value = pal.get("from", 0.0); g.inputs["From Max"].default_value = pal.get("to", 0.1)
    L.new(sep.outputs[axis], g.inputs["Value"])
    ramp = N.new("ShaderNodeValToRGB"); E = ramp.color_ramp.elements
    st = pal["ramp"]; E[0].position, E[0].color = st[0][0], (*st[0][1], 1); E[1].position, E[1].color = st[-1][0], (*st[-1][1], 1)
    for pos, c in st[1:-1]: e = E.new(pos); e.color = (*c, 1)
    L.new(g.outputs["Result"], ramp.inputs["Fac"])
    cloud = N.new("ShaderNodeTexNoise"); cloud.inputs["Scale"].default_value = pal.get("cloudScale", 16); cloud.inputs["Detail"].default_value = 3
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "OVERLAY"; mix.inputs["Factor"].default_value = pal.get("cloud", 0.08)
    L.new(ramp.outputs["Color"], mix.inputs[6]); L.new(cloud.outputs["Color"], mix.inputs[7]); last = mix.outputs[2]
    if pal.get("specks"):
        fl = N.new("ShaderNodeTexNoise"); fl.inputs["Scale"].default_value = pal.get("speckScale", 90)
        fr = N.new("ShaderNodeValToRGB"); fr.color_ramp.elements[0].position = 0.735; fr.color_ramp.elements[1].position = 0.755
        L.new(fl.outputs["Fac"], fr.inputs["Fac"])
        mf = N.new("ShaderNodeMix"); mf.data_type = "RGBA"; mf.inputs[7].default_value = (*pal["specks"], 1)
        L.new(fr.outputs["Color"], mf.inputs["Factor"]); L.new(last, mf.inputs[6]); last = mf.outputs[2]
    L.new(last, B.inputs["Base Color"])
    return m

def smooth(o):
    for p in o.data.polygons: p.use_smooth = True
    return o

def select_only(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o

def apply_mod(o, mod):
    select_only(o); bpy.ops.object.modifier_apply(modifier=mod.name)

# ---------------- body generators
BS = SPEC["body"]; W, D, H = BS["W"], BS["D"], BS["H"]
def gen_blob():
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, radius=1.0); o = bpy.context.object
    for v in o.data.vertices:
        x, y, z = v.co
        zz = z * (1.0 + BS.get("lean", 0.0) * (-x) * max(z, 0))
        zz = zz * (1 + BS.get("topSwell", 0.0) * max(z, 0) ** 2)
        fb = BS.get("baseFlat", -0.4)
        if zz < fb: zz = fb - (fb - zz) * 0.25
        yy = y * (1 - BS.get("bellyFlat", 0.0) * max(-y, 0) ** 3)
        p = Vector((x * W, yy * D, zz * H)) + Vector((x, y, z)) * BS.get("lumps", 0.0006) * noise.noise(Vector((x, y, z)) * 2.3)
        v.co = p
    return o
def gen_cube():
    bpy.ops.mesh.primitive_cube_add(size=2); o = bpy.context.object
    o.scale = (W, D, H); bpy.ops.object.transform_apply(scale=True)
    bv = o.modifiers.new("Bevel", "BEVEL"); bv.width = BS.get("bevel", 0.02); bv.segments = 8; bv.limit_method = "NONE"
    apply_mod(o, bv)
    for v in o.data.vertices:   # soft, slightly pillowy faces and a tiny lean (wobbly cube)
        c = v.co; k = BS.get("pillow", 0.06)
        v.co = Vector((c.x * (1 + k * (1 - (c.z / H) ** 2) * 0.5), c.y * (1 + k * (1 - (c.z / H) ** 2) * 0.5), c.z))
    return o
body = {"blob": gen_blob, "cube": gen_cube, "box": gen_cube}[BS["type"]]()
body.name = P + "Body"; bpy.ops.object.transform_apply()

# joined parts (same skin): eye domes, ears, … — become part of the body before face placement
def add_join_parts():
    parts = []
    for jp in BS.get("joinSpheres", []):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=1, location=jp["at"])
        s = bpy.context.object; s.scale = jp["r"]; bpy.ops.object.transform_apply(scale=True); parts.append(s)
    if parts:
        select_only(body)
        for s in parts: s.select_set(True)
        bpy.context.view_layer.objects.active = body; bpy.ops.object.join()
        rm = body.modifiers.new("Remesh", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = 0.0022; apply_mod(body, rm)
add_join_parts()
mn = min(v.co.z for v in body.data.vertices)
for v in body.data.vertices: v.co.z -= mn
smooth(body)
if BS["type"] == "blob" and not BS.get("joinSpheres"):
    m = body.modifiers.new("Subd", "SUBSURF"); m.levels = 1; apply_mod(body, m)
else:
    m = body.modifiers.new("Smooth", "CORRECTIVE_SMOOTH"); m.iterations = 6; apply_mod(body, m)
M_BODY = body_material(SPEC["palette"]); body.data.materials.append(M_BODY)
root = bpy.data.objects.new(NAME, None); sc.collection.objects.link(root); body.parent = root
bpy.context.view_layer.update()
HEIGHT = max(v.co.z for v in body.data.vertices)

def surface(x, z, inset=0.0):
    ok, loc, nrm, _ = body.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0))); assert ok, (x, z)
    return loc - nrm * inset, nrm
def top(x, y):
    ok, loc, nrm, _ = body.ray_cast(Vector((x, y, 1)), Vector((0, 0, -1))); assert ok, (x, y); return loc
def on_surface(obj, x, z, inset=0.0):
    loc, nrm = surface(x, z, inset); obj.location = loc; obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(nrm); obj.parent = root
def disc(name, r, depth, mat, segs=40, square=False):
    if square:
        bpy.ops.mesh.primitive_cube_add(size=2); o = bpy.context.object
        bv = o.modifiers.new("B", "BEVEL"); bv.width = 0.35; bv.segments = 4; apply_mod(o, bv)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=1); o = bpy.context.object
    o.name = name; o.scale = (r, r, depth); bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat); return smooth(o)

# ---------------- face
F = SPEC["face"]; ER = F["eyeR"]; EYE_Z = F["eyeZ"]; EYE_X = F["eyeX"]; SQUARE = F.get("eyeStyle") == "pixel"
M_EYE = principled(P + "Eye", F.get("eyeColor", (0.02, 0.025, 0.05)), rough=0.4, spec=0.08, emit=F.get("eyeEmit", 0.0))
M_IRIS = principled(P + "Iris", F.get("irisColor", (0.22, 0.48, 0.95)), rough=0.4, spec=0.08, emit=F.get("eyeEmit", 0.0) * 0.6)
M_SHINE = principled(P + "EyeShine", (1, 1, 1), rough=0.05, emit=2.0)
M_MOUTH = principled(P + "Mouth", F.get("mouthColor", (0.16, 0.08, 0.16)), rough=0.4, emit=F.get("mouthEmit", 0.0))
M_CHEEK = principled(P + "Cheek", F.get("cheekColor", (0.93, 0.58, 0.78)), rough=0.6)
if F.get("screen"):   # Bolt: inset dark screen panel the pixel face sits on
    sc_ = F["screen"]; M_SCREEN = principled(P + "Screen", sc_["color"], rough=0.15, coat=0.8, emit=sc_.get("emit", 0.2))
    bpy.ops.mesh.primitive_cube_add(size=2); scr = bpy.context.object; scr.name = P + "Screen"
    scr.scale = (sc_["w"], 0.004, sc_["h"]); bpy.ops.object.transform_apply(scale=True)
    bv = scr.modifiers.new("B", "BEVEL"); bv.width = 0.006; bv.segments = 6; apply_mod(scr, bv)
    loc, _ = surface(0, sc_["z"]); scr.location = (0, loc.y + 0.0012, sc_["z"]); scr.parent = root
    scr.data.materials.append(M_SCREEN); smooth(scr)
for side, sx in (("L", -1), ("R", 1)):
    x = sx * EYE_X
    eye = disc(f"{P}Eye_{side}", ER, 0.0035, M_EYE, square=SQUARE); eye.scale = (1, F.get("eyeAspect", 1.12), 1)
    select_only(eye); bpy.ops.object.transform_apply(scale=True); on_surface(eye, x, EYE_Z, inset=0.0006)
    if not SQUARE:
        iris = disc(f"{P}Iris_{side}", ER * 0.78, 0.0012, M_IRIS)
        for v in iris.data.vertices:
            if v.co.y > -ER * 0.05: v.co.y = -ER * 0.05 + (v.co.y + ER * 0.05) * 0.05
        on_surface(iris, x, EYE_Z - ER * 0.30, inset=-0.0026)
        s1 = disc(f"{P}EyeShine_{side}", ER * 0.30, 0.001, M_SHINE, 16); on_surface(s1, x - ER * 0.28, EYE_Z + ER * 0.38, inset=-0.0036)
        s2 = disc(f"{P}EyeShine2_{side}", ER * 0.13, 0.001, M_SHINE, 12); on_surface(s2, x + ER * 0.35, EYE_Z - ER * 0.15, inset=-0.0036)
    if F.get("cheek"):
        c = F["cheek"]; ch = disc(f"{P}Cheek_{side}", c["r"], 0.0016, M_CHEEK, 24); ch.scale = (1, 0.62, 1)
        select_only(ch); bpy.ops.object.transform_apply(scale=True); on_surface(ch, sx * c["x"], c["z"], inset=0.0004)
def shape_keys(o, ks):
    if not o.data.shape_keys: o.shape_key_add(name="Basis")
    for n, f in ks:
        k = o.shape_key_add(name=n)
        for i, v in enumerate(o.data.vertices): k.data[i].co = f(v.co.copy())
for side in "LR":
    for nm in (f"{P}Eye_{side}", f"{P}Iris_{side}"):
        o = bpy.data.objects.get(nm)
        if not o: continue
        iris = "Iris" in nm
        shape_keys(o, [
            ("blink", lambda p: Vector((p.x * 1.05, p.y * 0.06 - ER * 0.25, p.z * 0.6))),
            ("happy", (lambda p: Vector((0.0, ER * 0.37, 0.0))) if iris else
                      (lambda p: Vector((p.x * 1.05, ER * 0.42 * (1 - min((p.x / ER) ** 2, 1)) - ER * 0.05 + p.y * 0.16, p.z * 0.7)))),
            ("sleepy", lambda p: Vector((p.x, min(p.y, ER * 0.15) * 0.75 - ER * 0.12, p.z))),
            ("excited", lambda p: p * 1.18),
            ("surprised", lambda p: Vector((p.x * 0.86, p.y * 1.06, p.z))),
            ("sad", lambda p: Vector((p.x, p.y * 0.85 - ER * 0.05 * (p.x / ER) * (1 if side == "L" else -1), p.z)))])
    for nm in (f"{P}EyeShine_{side}", f"{P}EyeShine2_{side}"):
        o = bpy.data.objects.get(nm)
        if o: shape_keys(o, [(kn, (lambda f: lambda p: p * f)(f)) for kn, f in
                             (("blink", 0.0), ("happy", 0.0), ("sleepy", 0.4), ("excited", 1.25), ("surprised", 1.0), ("sad", 1.0))])
# mouth ribbon on the surface
MF = F["mouth"]; MW = MF["width"]; bm = bmesh.new(); NS = 16
for i in range(NS + 1):
    t = -1 + 2 * i / NS; zc = -MF.get("smile", 0.0012) * (1 - t * t)
    for dz in (0.0009, -0.0009): bm.verts.new((MW * t, 0, zc + dz))
bm.verts.ensure_lookup_table()
for i in range(NS): bm.faces.new((bm.verts[2*i], bm.verts[2*i+1], bm.verts[2*i+3], bm.verts[2*i+2]))
me = bpy.data.meshes.new(P + "Mouth"); bm.to_mesh(me)
mouth = bpy.data.objects.new(P + "Mouth", me); sc.collection.objects.link(mouth); mouth.data.materials.append(M_MOUTH)
sol = mouth.modifiers.new("S", "SOLIDIFY"); sol.thickness = 0.0012; apply_mod(mouth, sol)
mloc, _ = surface(0, MF["z"]); mouth.location = mloc + Vector((0, -0.0004, 0)); mouth.parent = root
u = lambda p: max(1 - (p.x / MW) ** 2, 0); cv = lambda p: -MF.get("smile", 0.0012) * u(p); topm = lambda p: p.z > cv(p)
shape_keys(mouth, [
    ("happy", lambda p: Vector((p.x * 1.3, p.y, (p.z - cv(p)) + cv(p) * 2.2))),
    ("excited", lambda p: Vector((p.x * 1.2, p.y, (0.0006 - 0.0007 * u(p)) if topm(p) else -0.0068 * u(p) ** 0.5))),
    ("surprised", lambda p: Vector((p.x * 0.42, p.y, (0.0016 if topm(p) else -0.0030) * u(p) ** 0.5 - 0.0008))),
    ("sleepy", lambda p: Vector((p.x * 0.6, p.y, p.z * 0.3))),
    ("sad", lambda p: Vector((p.x, p.y, -p.z - 0.0012)))])
if F.get("cheek") and "cheek_puff" in SPEC.get("personality", []):
    for side in "LR": shape_keys(bpy.data.objects[f"{P}Cheek_{side}"], [("puff", lambda p: Vector((p.x * 1.6, p.y * 1.6, p.z * 3.0)))])
bpy.context.view_layer.update()
def conform(obj, offset, depth_keep=0.15):
    mw = obj.matrix_world.copy(); inv = mw.inverted()
    blocks = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    for data in ([kb.data for kb in blocks] if blocks else [obj.data.vertices]):
        for d in data:
            w = mw @ d.co
            ok, loc, _, _ = body.ray_cast(Vector((w.x, -1, w.z)), Vector((0, 1, 0)))
            if not ok: continue
            w.y = loc.y - offset - max(d.co.z, -1) * depth_keep; d.co = inv @ w
    if blocks:
        for v, b in zip(obj.data.vertices, blocks[0].data): v.co = b.co
if not F.get("screen"):
    for side in "LR":
        for nm, off in ((f"{P}Eye_{side}", 0.0003), (f"{P}Iris_{side}", 0.0007), (f"{P}EyeShine_{side}", 0.0010),
                        (f"{P}EyeShine2_{side}", 0.0010), (f"{P}Cheek_{side}", 0.0001)):
            if bpy.data.objects.get(nm): conform(bpy.data.objects[nm], off)
    mw = mouth.matrix_world.copy()
    for kb in mouth.data.shape_keys.key_blocks:
        for d in kb.data:
            w = mw @ d.co; ok, loc, _, _ = body.ray_cast(Vector((w.x, -1, w.z)), Vector((0, 1, 0)))
            if ok: d.co.y += (loc.y - 0.0007) - w.y + d.co.y
    for v, b in zip(mouth.data.vertices, mouth.data.shape_keys.key_blocks[0].data): v.co = b.co
else:   # pixel face sits flat on the screen, slightly proud of it
    scr = bpy.data.objects[P + "Screen"]; zfront = scr.location.y - 0.004 - 0.0012
    for o in [o for o in sc.objects if o.type == "MESH" and o.name.startswith((P + "Eye", P + "Mouth"))]:
        o.rotation_mode = "QUATERNION"; o.location.y = zfront
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector((0, -1, 0))) if "Mouth" not in o.name else o.rotation_quaternion

# ---------------- extra parts (own materials; animatable)
PARTS = {}
def part_material(name, rgb, **kw):
    return bpy.data.materials.get(P + name) or principled(P + name, rgb, **kw)
def gen_gills(pp):
    mat = part_material("Gill", pp["color"], rough=0.45, coat=0.3, sss=0.25)
    for side, sx in (("L", -1), ("R", 1)):
        for i, (ang, ln) in enumerate(pp["fronds"]):
            pivot = bpy.data.objects.new(f"{P}Gill_{side}{i}", None); sc.collection.objects.link(pivot); pivot.parent = root
            base = Vector((sx * pp["x"], pp.get("y", 0.0), pp["z"]))
            ok, loc, nrm, _ = body.ray_cast(base + Vector((sx * 0.2, 0, 0)), Vector((-sx, 0, 0)))
            pivot.location = (loc if ok else base) - Vector((sx * 0.002, 0, 0))
            pivot.rotation_euler = (0, math.radians(sx * -ang), 0) if False else (math.radians(0), math.radians(-sx * 0), 0)
            # frond: tapered stalk + feathery side filaments, lies outward along ±X, raised by ang
            a = math.radians(ang); dirv = Vector((sx * math.cos(a), 0, math.sin(a)))
            bm = bmesh.new()
            stalk = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=pp["r"], radius2=pp["r"] * 0.45, depth=ln)
            bmesh.ops.translate(bm, verts=stalk["verts"], vec=(0, 0, ln / 2))
            for k in range(pp.get("feathers", 5)):
                t = (k + 1) / (pp.get("feathers", 5) + 1)
                for s in (-1, 1):
                    f = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=pp["r"] * 0.45, radius2=pp["r"] * 0.2, depth=ln * 0.32)
                    bmesh.ops.translate(bm, verts=f["verts"], vec=(0, 0, ln * 0.16))
                    bmesh.ops.rotate(bm, verts=f["verts"], cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(math.radians(55 * s), 3, "Y"))
                    bmesh.ops.translate(bm, verts=f["verts"], vec=(0, 0, ln * t))
            me = bpy.data.meshes.new(f"{P}GillMesh_{side}{i}"); bm.to_mesh(me); bm.free()
            o = bpy.data.objects.new(f"{P}GillFrond_{side}{i}", me); sc.collection.objects.link(o)
            o.rotation_mode = "QUATERNION"; o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(dirv)
            o.parent = pivot; o.data.materials.append(mat); smooth(o)
            PARTS.setdefault("gills", []).append(pivot)
def gen_limbs(pp):
    for i, (x, y) in enumerate(pp["at"]):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=(x, y, pp.get("z", 0.004)))
        o = bpy.context.object; o.name = f"{P}Foot_{i}"; o.scale = pp["r"]; select_only(o); bpy.ops.object.transform_apply(scale=True)
        o.data.materials.append(part_material("Foot", pp["color"], rough=0.45, coat=0.2)); smooth(o); o.parent = root
def gen_tail(pp):
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=pp["r"], radius2=pp["r"] * 0.25, depth=pp["len"])
    o = bpy.context.object; o.name = f"{P}Tail"; o.rotation_euler = (math.radians(-100), 0, 0)
    o.location = (0, D * 0.9, pp["z"]); o.data.materials.append(part_material("Tail", pp["color"], rough=0.4, coat=0.3)); smooth(o); o.parent = root
    PARTS["tail"] = o
def gen_antenna(pp):
    pivot = bpy.data.objects.new(f"{P}Antenna", None); sc.collection.objects.link(pivot); pivot.parent = root
    pivot.location = top(pp["x"], 0) - Vector((0, 0, 0.002))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=pp["r"], depth=pp["len"], location=(0, 0, pp["len"] / 2))
    st = bpy.context.object; st.name = f"{P}AntennaStalk"; st.data.materials.append(part_material("Metal", pp["metal"], rough=0.25, spec=0.8)); st.parent = pivot; smooth(st)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=pp["tip"], location=(0, 0, pp["len"] + pp["tip"] * 0.6))
    tp = bpy.context.object; tp.name = f"{P}AntennaTip"; tp.data.materials.append(part_material("Light", pp["light"], rough=0.2, emit=3.0)); tp.parent = pivot; smooth(tp)
    shape_keys(tp, [("flash", lambda p: p * 1.45)])
    PARTS["antenna"] = pivot
def gen_bolts(pp):
    for side, sx in (("L", -1), ("R", 1)):
        ok, loc, nrm, _ = body.ray_cast(Vector((sx * 0.3, 0, pp["z"])), Vector((-sx, 0, 0)))
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=pp["r"], depth=pp["depth"])
        o = bpy.context.object; o.name = f"{P}Bolt_{side}"; o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(nrm); o.location = loc
        o.data.materials.append(part_material("Metal", pp["metal"], rough=0.25, spec=0.8)); smooth(o); o.parent = root
def gen_panel_lines(pp):
    for i, z in enumerate(pp["z"]):
        bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.004, major_segments=64, minor_segments=6)
        o = bpy.context.object; o.name = f"{P}Seam_{i}"; o.scale = (W * 1.005, D * 1.005, 1); o.location = (0, 0, z)
        select_only(o); bpy.ops.object.transform_apply(scale=True)
        o.data.materials.append(part_material("Seam", pp["color"], rough=0.35)); o.parent = root
GEN = {"gills": gen_gills, "limbs": gen_limbs, "tail": gen_tail, "antenna": gen_antenna, "bolts": gen_bolts, "seams": gen_panel_lines}
for pp in SPEC.get("parts", []): GEN[pp["kind"]](pp)

# ---------------- anchors
A = SPEC["anchors"]
anchors = {"anchor_head": top(*A["head"]) + Vector((0, 0, 0.004)), "anchor_face": surface(0, EYE_Z)[0],
           "anchor_back": Vector((0, D * 0.95, HEIGHT * 0.55)), "anchor_neck": surface(0, MF["z"] - 0.01)[0], "anchor_base": Vector((0, 0, 0))}
for n, loc in anchors.items():
    a = bpy.data.objects.new(n, None); a.empty_display_size = 0.01; a.location = loc; a.parent = root; sc.collection.objects.link(a)

# ---------------- bake skin
select_only(body); bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02); bpy.ops.object.mode_set(mode="OBJECT")
img = bpy.data.images.new(P + "BaseColor", 2048, 2048)
N = M_BODY.node_tree.nodes; tn = N.new("ShaderNodeTexImage"); tn.image = img; N.active = tn
sc.render.engine = "CYCLES"; sc.cycles.samples = 1; sc.cycles.device = "CPU"
sc.render.bake.use_pass_direct = False; sc.render.bake.use_pass_indirect = False; sc.render.bake.margin = 16
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
img.filepath_raw = f"{out}/{P}BaseColor.png"; img.file_format = "PNG"; img.save(); img.filepath = f"//{P}BaseColor.png"
M_BODY.node_tree.links.new(tn.outputs["Color"], N["Principled BSDF"].inputs["Base Color"])

# ---------------- clips: shared + expression holds + personality
CLIPS = {"idle_bob": (1, 60), "blink": (61, 72), "wobble": (73, 102), "tap": (103, 130)}
root.rotation_mode = "XYZ"
def kf(obj, path, f, val, idx=None):
    if idx is None: setattr(obj, path, val); obj.keyframe_insert(path, frame=f)
    else: getattr(obj, path)[idx] = val; obj.keyframe_insert(path, index=idx, frame=f)
def rest(f):
    kf(root, "location", f, (0, 0, 0)); kf(root, "rotation_euler", f, (0, 0, 0)); kf(root, "scale", f, (1, 1, 1))
for f in (1, 61, 73, 103, 130): rest(f)
kf(root, "location", 30, (0, 0, 0.003)); kf(root, "scale", 30, (1.01, 1.01, 0.985)); kf(root, "location", 60, (0, 0, 0)); kf(root, "scale", 60, (1, 1, 1))
for f, a in ((78, 7), (84, -6), (90, 4), (96, -2), (102, 0)): kf(root, "rotation_euler", f, math.radians(a), 1)
kf(root, "scale", 108, (1.08, 1.08, 0.88)); kf(root, "scale", 114, (0.95, 0.95, 1.08)); kf(root, "location", 114, (0, 0, 0.012))
kf(root, "location", 121, (0, 0, 0)); kf(root, "scale", 121, (1.04, 1.04, 0.95)); kf(root, "scale", 130, (1, 1, 1))
face = [o for o in sc.objects if o.type == "MESH" and o.data.shape_keys and o.name.startswith(P)]
def keyval(o, name, f, v):
    kb = o.data.shape_keys.key_blocks.get(name)
    if kb: kb.value = v; kb.keyframe_insert("value", frame=f)
for o in face:
    if "Eye" in o.name or "Iris" in o.name:
        for f, v in ((1, 0), (61, 0), (65, 1), (68, 1), (72, 0), (130, 0)): keyval(o, "blink", f, v)
keyval(mouth, "happy", 1, 0); keyval(mouth, "happy", 103, 0); keyval(mouth, "happy", 110, 1); keyval(mouth, "happy", 125, 1); keyval(mouth, "happy", 130, 0)
EXPR = {"idle": {}, "happy": {"happy": 1}, "excited": {"excited": 1}, "surprised": {"surprised": 1}, "sleepy": {"sleepy": 1}, "sad": {"sad": 1}}
f0 = 131
for name, want in EXPR.items():
    a, b = f0, f0 + 5; CLIPS[f"expr_{name}"] = (a, b)
    for o in face:
        for kb in o.data.shape_keys.key_blocks[1:]:
            for f in (a, b): kb.value = float(want.get(kb.name, 0)); kb.keyframe_insert("value", frame=f)
    for f in (a, b): rest(f)
    f0 = b + 1
def personality(name, length, body_fn):
    global f0
    a, b = f0, f0 + length - 1; CLIPS[name] = (a, b); rest(a); rest(b); body_fn(a, b); f0 = b + 1
def p_gill_flutter(a, b):
    for i, g in enumerate(PARTS.get("gills", [])):
        g.rotation_mode = "XYZ"; side = -1 if "_L" in g.name else 1
        for k, f in enumerate(range(a, b + 1, 3)):
            g.rotation_euler = (0, math.radians(side * (10 if (k + i) % 2 else -6) * (f < b)), 0); g.keyframe_insert("rotation_euler", frame=f)
def p_exuberant_bounce(a, b):
    for k, (f, z, s) in enumerate(((a + 4, 0, (1.1, 1.1, 0.86)), (a + 10, 0.022, (0.92, 0.92, 1.12)), (a + 16, 0, (1.08, 1.08, 0.9)),
                                   (a + 22, 0.012, (0.96, 0.96, 1.06)), (a + 28, 0, (1, 1, 1)))):
        kf(root, "location", f, (0, 0, z)); kf(root, "scale", f, s)
    for o in face: keyval(o, "excited", a, 0); keyval(o, "excited", a + 6, 1); keyval(o, "excited", b - 4, 1); keyval(o, "excited", b, 0)
def p_slow_blink(a, b):
    for o in face:
        if "Eye" in o.name or "Iris" in o.name:
            for f, v in ((a, 0), (a + 12, 1), (a + 26, 1), (b, 0)): keyval(o, "blink", f, v)
def p_cheek_puff(a, b):
    for o in face:
        if "Cheek" in o.name:
            for f, v in ((a, 0), (a + 8, 1), (b - 8, 1), (b, 0)): keyval(o, "puff", f, v)
    kf(root, "scale", a + 8, (1.05, 1.05, 1.0)); kf(root, "scale", b - 8, (1.05, 1.05, 1.0))
def p_measured_hop(a, b):
    kf(root, "scale", a + 6, (1.06, 1.06, 0.92)); kf(root, "location", a + 14, (0, -0.004, 0.016)); kf(root, "scale", a + 14, (0.97, 0.97, 1.05))
    kf(root, "location", a + 22, (0, -0.008, 0)); kf(root, "scale", a + 25, (1.05, 1.05, 0.94)); kf(root, "location", b, (0, 0, 0))
def p_cube_squash(a, b):
    for f, s in ((a + 5, (1.14, 1.14, 0.8)), (a + 11, (0.9, 0.9, 1.16)), (a + 17, (1.07, 1.07, 0.9)), (a + 23, (0.97, 0.97, 1.04))):
        kf(root, "scale", f, s)
    kf(root, "location", a + 11, (0, 0, 0.008)); kf(root, "location", a + 17, (0, 0, 0))
def p_antenna_flash(a, b):
    tip = bpy.data.objects.get(P + "AntennaTip")
    if tip:
        for f, v in ((a, 0), (a + 3, 1), (a + 7, 0), (a + 10, 1), (a + 14, 0), (b, 0)): keyval(tip, "flash", f, v)
    ant = PARTS.get("antenna")
    if ant:
        ant.rotation_mode = "XYZ"
        for f, r in ((a, 0), (a + 5, 9), (a + 10, -7), (a + 15, 4), (b, 0)): ant.rotation_euler = (0, math.radians(r), 0); ant.keyframe_insert("rotation_euler", frame=f)
def p_servo_tilt(a, b):
    for f, r in ((a + 6, 10), (a + 16, 10), (a + 22, -4), (b, 0)): kf(root, "rotation_euler", f, math.radians(r), 1)
PFN = {"gill_flutter": (24, p_gill_flutter), "exuberant_bounce": (32, p_exuberant_bounce), "slow_blink": (40, p_slow_blink),
       "cheek_puff": (36, p_cheek_puff), "measured_hop": (32, p_measured_hop), "cube_squash": (30, p_cube_squash),
       "antenna_flash": (20, p_antenna_flash), "servo_tilt": (30, p_servo_tilt)}
for pn in SPEC.get("personality", []):
    ln, fn = PFN[pn]; personality(pn, ln, fn)
# every animated channel starts neutral at frame 1
for o in face:
    ad = o.data.shape_keys.animation_data
    for kb in o.data.shape_keys.key_blocks[1:]:
        fc = ad and ad.action and ad.action.fcurves.find(f'key_blocks["{kb.name}"].value')
        if fc and not any(abs(k.co.x - 1) < 0.5 for k in fc.keyframe_points): fc.keyframe_points.insert(1, 0.0)
sc.frame_start, sc.frame_end = 1, f0 - 1
json.dump({"fps": 30, "clips": {k: {"start": a, "end": b} for k, (a, b) in CLIPS.items()}}, open(f"{out}/clips.json", "w"), indent=1)
cap = SPEC.get("cap")
json.dump({CID: {"cap.moliboo.signature": dict(cap, anchor="anchor_head") if cap else {"compatible": False}}}, open(f"{out}/attachments.json", "w"), indent=1)
sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=f"{out}/{NAME}.blend")
bpy.ops.object.select_all(action="DESELECT")
def sel(o): o.select_set(True); [sel(c) for c in o.children]
sel(root)
bpy.ops.wm.usd_export(filepath=f"{out}/{NAME}.usdz", selected_objects_only=True, export_materials=True, generate_preview_surface=True,
                      export_shapekeys=True, export_animation=True, convert_orientation=True,
                      export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y")
print("MOLIBOO_BUILD_OK", CID, json.dumps({"height": HEIGHT, "frames": f0 - 1}))
