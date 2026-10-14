import bpy, sys, math, json
from mathutils import Vector
out = sys.argv[sys.argv.index("--")+1]
sc = bpy.context.scene; sc.frame_set(1)
hat = bpy.data.objects["Accessory_Cap_MolibooSignature"]
def show_hat(on):
    for o in [hat] + list(hat.children_recursive): o.hide_render = not on; o.hide_set(not on)
show_hat(True)
deps = bpy.context.evaluated_depsgraph_get(); stats = {}; lo = Vector((9,9,9)); hi = -lo
for o in sc.objects:
    if o.type != "MESH": continue
    m = o.evaluated_get(deps).to_mesh(); m.calc_loop_triangles()
    stats[o.name] = {"tris": len(m.loop_triangles), "shape_keys": [k.name for k in o.data.shape_keys.key_blocks][1:] if o.data.shape_keys else []}
    if not o.name.startswith("Hat"):
        for v in m.vertices: w = o.matrix_world @ v.co; lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
stats["_total_tris"] = sum(v["tris"] for k, v in stats.items() if not k.startswith("_"))
stats["_body_bounds_m"] = {"min": list(lo), "max": list(hi), "size": list(hi - lo)}
stats["_anchors"] = {o.name: list(o.matrix_world.translation) for o in sc.objects if o.name.startswith("anchor_")}
json.dump(stats, open(f"{out}/validation.json", "w"), indent=1)

sc.render.engine = "CYCLES"; sc.cycles.samples = int(__import__("os").environ.get("SAMPLES","64")); sc.cycles.device = "CPU"; sc.cycles.use_denoising = True
sc.render.resolution_x = 900; sc.render.resolution_y = 700; sc.view_settings.view_transform = "Filmic"
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.11, 0.12, 0.15, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
def area(name, loc, e, size, col=(1,1,1)):
    l = bpy.data.lights.new(name, "AREA"); l.energy = e; l.size = size; l.color = col
    o = bpy.data.objects.new(name, l); sc.collection.objects.link(o); o.location = loc
    o.rotation_euler = (Vector((0, 0, 0.04)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
area("Key", (-0.25, -0.35, 0.35), 4, 0.35)
area("Rim", (0.3, 0.35, 0.25), 5, 0.3, (0.75, 0.85, 1.0))
area("Fill", (0.35, -0.3, 0.05), 2.5, 0.4, (0.7, 1.0, 0.9))
bpy.ops.mesh.primitive_plane_add(size=20); fl = bpy.context.object
fm = bpy.data.materials.new("Floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.035, 0.038, 0.048, 1)
fl.data.materials.append(fm)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam; cam.data.lens = 85
tgt = Vector((0, 0, 0.055))
def shoot(name, ang, dist=0.62, elev=0.12):
    a = math.radians(ang); cam.location = tgt + Vector((dist*math.sin(a), -dist*math.cos(a), elev))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = f"{out}/{name}.png"; bpy.ops.render.render(write_still=True)
import os
ONLY = os.environ.get("ONLY")
for o in keyobjs_pre if False else []: pass
keyobjs = [o for o in sc.objects if o.data is not None and getattr(o.data, "shape_keys", None)]
for o in keyobjs:
    if o.data.shape_keys.animation_data: o.data.shape_keys.animation_data_clear()
if root := bpy.data.objects.get("Pebble"):
    root.animation_data_clear(); root.location = (0, 0, 0); root.rotation_euler = (0, 0, 0); root.scale = (1, 1, 1)
def expr(eyes, mouth):
    for o in keyobjs:
        for kb in o.data.shape_keys.key_blocks[1:]:
            m = o.name.startswith("Pebble_Mouth")
            kb.value = 1.0 if ((m and kb.name == mouth) or (not m and kb.name == eyes)) else 0.0
EXPRS = [("idle", None, None), ("blink", "blink", None), ("happy", "happy", "happy"), ("excited", "excited", "excited"),
         ("surprised", "surprised", "surprised"), ("sleepy", "sleepy", "sleepy"), ("sad", None, "sad")]
VIEWS = [("front", 0, 0.5, 0.08), ("three_quarter", -35, 0.52, 0.09), ("side", 90, 0.55, 0.08)]
for en, e, m in EXPRS:
    if ONLY and en not in ONLY.split(","): continue
    expr(e, m)
    for vn, ang, dist, elev in VIEWS:
        if ONLY and os.environ.get("VIEWS") and vn not in os.environ["VIEWS"].split(","): continue
        shoot(f"expr_{en}_{vn}", ang, dist, elev)
expr(None, None)
def closeup(name, ang):
    global tgt
    keep = tgt; tgt = Vector(bpy.data.objects["anchor_head"].matrix_world.translation) + Vector((0, 0, 0.008))
    shoot(name, ang, dist=0.22, elev=0.05); tgt = keep
if not ONLY or "closeup" in ONLY:
    closeup("cap_closeup", -30); closeup("cap_closeup_side", 70)
if not ONLY:
    shoot("view_rear", 180)
    show_hat(False); shoot("hat_off", -20); show_hat(True); shoot("hat_on", -20)
print("RENDER_OK")
