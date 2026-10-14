import bpy, sys, math, os
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]; out = a[0]; assets = a[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = int(os.environ.get("SAMPLES", "32"))
sc.render.resolution_x, sc.render.resolution_y = 2400, 900; sc.render.film_transparent = False
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.34, 0.38, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
x = 0.0; gap = 0.05; roots = []
for p in assets:
    before = set(bpy.data.objects); bpy.ops.wm.usd_import(filepath=p); new = [o for o in bpy.data.objects if o not in before]
    top = [o for o in new if o.parent is None or o.parent not in new]
    pts = [o.matrix_world @ Vector(c) for o in new if o.type == "MESH" for c in o.bound_box]
    mnx = min(v.x for v in pts); mxx = max(v.x for v in pts); mnz = min(v.z for v in pts); cy = sum(v.y for v in pts) / len(pts)
    holder = bpy.data.objects.new("Holder_" + os.path.basename(p), None); bpy.context.scene.collection.objects.link(holder)
    for o in new:
        for c in list(o.constraints): o.constraints.remove(c)
    for t in top: t.parent = holder
    holder.location = Vector((x - mnx, -cy, -mnz))
    x += (mxx - mnx) + gap; bpy.context.view_layer.update()
bpy.context.view_layer.update()
cx = (x - gap) / 2 + 0.06
bpy.ops.mesh.primitive_plane_add(size=4, location=(cx, 0, 0)); fl = bpy.context.object
m = bpy.data.materials.new("Floor"); m.use_nodes = True; m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.44, 0.48, 1); fl.data.materials.append(m)
for loc, e in (((cx - 0.4, -0.6, 0.6), 25), ((cx + 0.5, -0.3, 0.4), 10), ((cx, 0.5, 0.5), 12)):
    bpy.ops.object.light_add(type="AREA", location=loc); L = bpy.context.object; L.data.energy = e; L.data.size = 0.6
    L.rotation_euler = (Vector((cx, 0, 0.05)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam; cam.data.lens = 30
for name, off in (("front", Vector((0, -1.6, 0.18))), ("three_quarter", Vector((0.75, -1.45, 0.3)))):
    cam.location = Vector((cx, 0, 0.05)) + off
    cam.rotation_euler = (Vector((cx, 0, 0.05)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = f"{out}/group_{name}.png"; bpy.ops.render.render(write_still=True)
