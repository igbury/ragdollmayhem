# Preview renders of the arena kit: one image per piece, three-quarter view from the front (-Z).
#   blender -b assets/arena/arena.blend -P assets/arena/render.py -- OUT_DIR [Piece ...]
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else os.path.join(os.path.dirname(bpy.data.filepath), "renders")
only = set(argv[1:])
os.makedirs(out, exist_ok=True)

sc = bpy.context.scene
for eng in ("BLENDER_WORKBENCH",):
    sc.render.engine = eng
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "MATERIAL"
sh.show_shadows = True
sh.show_cavity = False
sh.show_backface_culling = True  # the outline is an inverted hull: from outside only its rim shows
sc.render.resolution_x, sc.render.resolution_y = 900, 900
sc.render.film_transparent = False
sc.world = sc.world or bpy.data.worlds.new("W")
sc.world.color = (0.55, 0.62, 0.7)

cam = bpy.data.objects.get("_cam") or bpy.data.objects.new("_cam", bpy.data.cameras.new("_cam"))
if cam.name not in sc.collection.objects:
    sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 50

obs = [o for o in bpy.data.collections["ArenaKit"].objects]
for o in obs:
    o.hide_render = True
for o in obs:
    if only and o.name not in only:
        continue
    o.hide_render = False
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo + hi) / 2
    r = (hi - lo).length / 2
    # Roblox front is -Z = Blender -Y; look from front-left-above
    d = Vector((-0.55, -1.0, 0.45)).normalized()
    cam.location = c + d * (r / math.tan(math.radians(18)) * 1.05)
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, o.name + ".png")
    bpy.ops.render.render(write_still=True)
    o.hide_render = True
print("rendered to", out)
