# Builds "Fists" in weapons.blend: a comic bare fist for the hotbar / wheel icon (WeaponMeshes.icon),
# raised like a fist emoji: knuckles up, wrist down, the curled fingers and the thumb across them on
# +X, the side the icon camera looks from. Flat sRGB face colours ("Col") and comic.py's outline shell.
# Run inside Blender with weapons.blend open, then export.py with NAMES = ["Fists"]:
#   exec(open(r"<repo>/assets/weapons/fist.py").read(), {"__name__": "__main__"})
# Roblox axes like glove.py (+Y up, Z across the four fingers). Keep it under ~2k triangles before the
# outline: the icon atlas holds it with every other weapon under the 20k EditableMesh cap.
import os

import bpy
from mathutils import Vector as V

glove = {"__name__": "glove"}
exec(open(os.path.join(os.path.dirname(bpy.data.filepath), "glove.py")).read(), glove)

SKIN = (0.94, 0.94, 0.94)  # white like the first-person hands (init.client SKIN)


def build():
    g = glove["Glove"]()
    # palm and back of the hand, behind the curl of the fingers
    g.blob((-0.08, 0.02, 0), (0.3, 0.36, 0.4), SKIN, segs=14, rings=10)
    # four fingers side by side, each over the knuckle and down the front, tip tucked into the palm;
    # the pinky (+Z) a little smaller and lower
    for i, z in enumerate((-0.285, -0.095, 0.095, 0.27)):
        k = 1 - 0.08 * max(i - 1, 0)
        drop = 0.03 * max(i - 1, 0)
        pts = [V((-0.1, 0.28 - drop, z)), V((0.1, 0.42 * k - drop, z)), V((0.3, 0.3 * k - drop, z)),
               V((0.33, 0.06 - drop, z)), V((0.18, -0.08, z))]
        g.tube(pts, lambda t, k=k: (0.1 * k, 0.11 * k), SKIN, ring=10, samples=12, side=(0, 0, 1), a=0.12)
    # thumb across the middle of the fingers, from the base of the palm on the -Z side
    thumb = [V((0.02, -0.26, -0.36)), V((0.3, -0.12, -0.32)), V((0.43, -0.03, -0.12)), V((0.42, -0.02, 0.08))]
    g.tube(thumb, lambda t: (0.12 - 0.02 * t, 0.11 - 0.02 * t), SKIN, ring=10, samples=12, side=(0, 1, 0), a=0.25)
    # wrist running down out of the fist
    g.tube([V((-0.08, -0.15, 0)), V((-0.1, -0.45, 0)), V((-0.11, -0.7, 0))],
           lambda t: (0.25, 0.21), SKIN, ring=12, samples=8, side=(0, 0, 1), a=0.06)
    return g.finish("Fists")


def main():
    ob = build()
    ob.location = (16, 0, -4)
    print("Fists", sum(len(p.vertices) - 2 for p in ob.data.polygons), "tris before the outline")
    glove["comic"]["punch"](ob.data)
    glove["comic"]["outline"](ob.data)
    ob.data.update()


if __name__ == "__main__":
    main()
