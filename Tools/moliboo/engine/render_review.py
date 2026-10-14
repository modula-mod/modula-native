# Review renders for one character: expressions × (front, three-quarter, side), rear, cap on/off, cap close-up.
#   blender -b <Name>.blend -P render_review.py -- <spec.json> <cap.usdz> <outdir>
import bpy, sys, math, json, os
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]; SPEC = json.load(open(a[0])); CAPUSD = a[1]; out = a[2]; os.makedirs(out, exist_ok=True)
NAME = SPEC["name"]; P = NAME + "_"; sc = bpy.context.scene
root = bpy.data.objects[NAME]
for o in [root] + list(root.children_recursive):
    o.animation_data_clear()
    if o.type == "MESH" and o.data.shape_keys: o.data.shape_keys.animation_data_clear()
root.location = (0, 0, 0); root.rotation_euler = (0, 0, 0); root.scale = (1, 1, 1)
for o in root.children_recursive:
    if o.name.startswith(P + "Gill_"): o.rotation_euler = (0, 0, 0)
    if o.name == P + "Antenna": o.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()
# cap: import the shipped asset and attach exactly like the runtime config (anchor + offset, XYZ degrees, scale)
cap = None; capcfg = SPEC.get("cap")
if capcfg and capcfg.get("compatible"):
    before = set(bpy.data.objects); bpy.ops.wm.usd_import(filepath=CAPUSD)
    new = [o for o in bpy.data.objects if o not in before]; cap = bpy.data.objects.new("CapMount", None); sc.collection.objects.link(cap)
    for o in new:
        if o.parent is None: o.parent = cap
    anc = bpy.data.objects["anchor_head"].matrix_world.translation
    cap.location = anc + Vector(capcfg["offset"]); cap.rotation_euler = [math.radians(d) for d in capcfg["rotationDegrees"]]
    cap.scale = [capcfg["scale"]] * 3
def show_cap(on):
    if cap:
        for o in [cap] + list(cap.children_recursive): o.hide_render = not on
show_cap(False)
keyobjs = [o for o in root.children_recursive if o.type == "MESH" and o.data.shape_keys]
def expr(eyes, mouth):
    for o in keyobjs:
        for kb in o.data.shape_keys.key_blocks[1:]:
            m = o.name.startswith(P + "Mouth"); kb.value = 1.0 if ((m and kb.name == mouth) or (not m and kb.name == eyes)) else 0.0
sc.render.engine = "CYCLES"; sc.cycles.samples = int(os.environ.get("SAMPLES", "32")); sc.cycles.device = "CPU"; sc.cycles.use_denoising = True
sc.render.resolution_x = 720; sc.render.resolution_y = 600; sc.view_settings.view_transform = "Filmic"
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.11, 0.12, 0.15, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
H = max((o.matrix_world @ v.co).z for o in root.children_recursive if o.type == "MESH" for v in o.data.vertices)
tgt = Vector((0, 0, H * 0.48))
def area(name, loc, e, size, col=(1, 1, 1)):
    l = bpy.data.lights.new(name, "AREA"); l.energy = e; l.size = size; l.color = col
    o = bpy.data.objects.new(name, l); sc.collection.objects.link(o); o.location = loc
    o.rotation_euler = (tgt - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
area("Key", (-0.25, -0.35, 0.38), 4, 0.35); area("Rim", (0.3, 0.35, 0.28), 5, 0.3, (0.75, 0.85, 1.0)); area("Fill", (0.35, -0.3, 0.08), 2.5, 0.4, (1.0, 0.95, 0.9))
bpy.ops.mesh.primitive_plane_add(size=20); fl = bpy.context.object; fm = bpy.data.materials.new("Floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.035, 0.038, 0.048, 1); fl.data.materials.append(fm)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam; cam.data.lens = 85
DIST = max(0.5, H * 5.2)
def shoot(name, ang, dist=None, elev=0.09, t=None):
    t = t or tgt; dist = dist or DIST; r = math.radians(ang)
    cam.location = t + Vector((dist * math.sin(r), -dist * math.cos(r), elev)); cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = f"{out}/{name}.png"; bpy.ops.render.render(write_still=True)
EXPRS = [("idle", None, None), ("blink", "blink", None), ("happy", "happy", "happy"), ("excited", "excited", "excited"),
         ("surprised", "surprised", "surprised"), ("sleepy", "sleepy", "sleepy"), ("sad", "sad", "sad")]
VIEWS = [("front", 0), ("three_quarter", -35), ("side", 90)]
ONLY = os.environ.get("ONLY")
for en, e, m in EXPRS:
    if ONLY and en not in ONLY.split(","): continue
    expr(e, m)
    for vn, ang in VIEWS: shoot(f"expr_{en}_{vn}", ang)
expr(None, None)
if not ONLY:
    shoot("view_rear", 180)
    shoot("cap_off", -25); show_cap(True); shoot("cap_on", -25)
    if cap: shoot("cap_closeup", -30, dist=0.24, elev=0.05, t=bpy.data.objects["anchor_head"].matrix_world.translation + Vector((0, 0, 0.006)))
    show_cap(False)
print("REVIEW_OK")
