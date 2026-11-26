# QA renders of the boss kit: each boss from the front, three-quarter and side, in EEVEE with a key,
# a rim and a fill, on a flat grey backdrop (the black inverted-hull outlines show as in the game).
#   blender -b assets/myth/bosses.blend -P assets/myth/render_bosses.py -- <out_dir> [tag] [Kind ...]
# writes <out_dir>/<Kind>_<tag>_<view>.png. Never saves the .blend.
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.join(os.path.dirname(bpy.data.filepath), "renders")
TAG = argv[1] if len(argv) > 1 else "qa"
KINDS = argv[2:] or ["Cyclops", "Minotaur", "Talos"]
VIEWS = {"front": (0, -1, 0.12), "threequarter": (0.75, -1, 0.25), "side": (1, -0.05, 0.1), "low": (0.35, -1, -0.12)}
os.makedirs(OUT, exist_ok=True)

scene = bpy.context.scene
try:
    scene.render.engine = "BLENDER_EEVEE"
except TypeError:
    pass
scene.render.resolution_x = scene.render.resolution_y = 900
scene.render.film_transparent = False
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.get("QA") or bpy.data.worlds.new("QA")
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (0.42, 0.45, 0.52, 1)
bg.inputs[1].default_value = 0.9
scene.world = world


def body(kind):
    return [o for o in scene.objects if o.type == "MESH" and o.name.startswith(kind + "_") and "Pylon" not in o.name and "__" not in o.name]


def bounds(obs):
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in obs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo, hi = Vector(map(min, lo, w)), Vector(map(max, hi, w))
    return lo, hi


def light(name, kind, energy, direction, size=5):
    ob = bpy.data.objects.get(name)
    if not ob:
        ob = bpy.data.objects.new(name, bpy.data.lights.new(name, kind))
        scene.collection.objects.link(ob)
    ob.data.energy = energy
    if kind == "AREA":
        ob.data.size = size
    ob.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    return ob


cam = bpy.data.objects.get("QACam") or bpy.data.objects.new("QACam", bpy.data.cameras.new("QACam"))
if cam.name not in scene.collection.objects:
    scene.collection.objects.link(cam)
cam.data.lens = 60
scene.camera = cam
key = light("QAKey", "SUN", 3.2, (-0.6, 0.8, -0.7))
rim = light("QARim", "SUN", 2.2, (0.5, -0.9, -0.3))
fill = light("QAFill", "SUN", 0.8, (0.8, 0.6, -0.2))
for o in scene.objects:
    if o.type == "LIGHT" and not o.name.startswith("QA"):
        o.hide_render = True

all_kinds = ["Cyclops", "Minotaur", "Talos"]
for kind in KINDS:
    for o in scene.objects:
        if o.type == "MESH":
            o.hide_render = not (o.name.startswith(kind + "_") and "Pylon" not in o.name)
    obs = body(kind)
    if not obs:
        print("no meshes for", kind)
        continue
    lo, hi = bounds(obs)
    centre, size = (lo + hi) / 2, hi - lo
    reach = max(size.z, size.x * 1.1) * 0.5 / math.tan(cam.data.angle / 2) * 1.12
    for view, d in VIEWS.items():
        d = Vector(d).normalized()
        cam.location = centre + d * reach
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT, f"{kind}_{TAG}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)
