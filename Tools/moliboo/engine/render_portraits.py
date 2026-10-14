"""Transparent 512x512 three-quarter portraits from shipped USDZs (MOL-03 collection picker / companion).
blender -b -P render_portraits.py -- <outdir> <A.usdz> [...]   → <outdir>/Portrait_<Name>.png"""
import bpy, sys, os, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]; out = a[0]
for p in a[1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = int(os.environ.get("SAMPLES", "48"))
    sc.render.resolution_x = sc.render.resolution_y = 512; sc.render.film_transparent = True
    sc.view_settings.view_transform = "AgX"
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.9, 0.92, 0.95, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    bpy.ops.wm.usd_import(filepath=p)
    for o in bpy.data.objects:
        for c in list(o.constraints): o.constraints.remove(c)
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    lo = Vector([min(v[i] for v in pts) for i in range(3)]); hi = Vector([max(v[i] for v in pts) for i in range(3)])
    ctr = (lo + hi) / 2; size = max(hi - lo)
    for loc, e in ((ctr + Vector((-0.25, -0.35, 0.35)), 6), (ctr + Vector((0.3, -0.2, 0.15)), 2.5), (ctr + Vector((0, 0.35, 0.3)), 3)):
        bpy.ops.object.light_add(type="AREA", location=loc); L = bpy.context.object; L.data.energy = e; L.data.size = 0.4
        L.rotation_euler = (ctr - loc).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = size * 1.18
    d = Vector((0.55, -1.0, 0.32)).normalized(); cam.location = ctr + d * 1.0
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    name = os.path.splitext(os.path.basename(p))[0]
    sc.render.filepath = f"{out}/Portrait_{name}.png"; bpy.ops.render.render(write_still=True)
