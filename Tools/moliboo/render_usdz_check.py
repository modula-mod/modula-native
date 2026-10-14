import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--")+1:]; usd, png = a
bpy.ops.wm.read_factory_settings(use_empty=True); sc = bpy.context.scene
bpy.ops.wm.usd_import(filepath=usd)
sc.render.engine="CYCLES"; sc.cycles.samples=32; sc.render.resolution_x=sc.render.resolution_y=512
sc.world=bpy.data.worlds.new("W"); sc.world.use_nodes=True; sc.world.node_tree.nodes["Background"].inputs[0].default_value=(0.93,0.95,0.97,1); sc.world.node_tree.nodes["Background"].inputs[1].default_value=0.45
cam=bpy.data.objects.new("C",bpy.data.cameras.new("C")); sc.collection.objects.link(cam); sc.camera=cam; cam.data.lens=85
t=Vector((0,0,0.05)); cam.location=t+Vector((0.15,-0.5,0.12)); cam.rotation_euler=(t-cam.location).to_track_quat("-Z","Y").to_euler()
sc.render.filepath=png; bpy.ops.render.render(write_still=True)
