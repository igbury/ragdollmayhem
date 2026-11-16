# Comic restyle for the weapon meshes in weapons.blend: exaggerated shapes, punchier colours and a
# baked black outline shell (an inverted hull: pushed-out copy, faces reversed, pure black (0,0,0),
# which WeaponMeshes' icon atlas skips). It must start from the ORIGINAL meshes (git 53af630),
# else the effects stack: set SOURCE to a copy of that blend and they are loaded first. Then export.py.
#   git show 53af630:assets/weapons/weapons.blend > orig.blend
#   SOURCE = r"<path>/orig.blend"; exec(open(r"<repo>/assets/weapons/comic.py").read(), {"__name__": "__main__", "SOURCE": SOURCE})
# Shape ops never move the grip (the origin) or the left-hand support points much: they grow what is
# far from the hand. Axes are Blender's: X = thickness, -Y = forward (guns, knife), +Z = up (melee).
import colorsys
import os

import bmesh
import bpy
from mathutils import Vector

AX = {"x": 0, "y": 1, "z": 2}

RULES = {
    "Axe": [("thick", 1.3), ("swell", "z", 1.3, 1.6, 1.22)],
    "Bat": [("cross", "z", 0.6, 2.2, 1.45)],
    "Katana": [("thick", 1.2), ("cross", "z", 0.5, 1.5, 1.25)],
    "Knife": [("thick", 1.3), ("cross", "y", -0.05, -0.4, 1.4)],
    "Pan": [("swell", "z", 1.0, 1.5, 1.3)],
    "Grenade": [("swell", "z", -10, -9, 1.12)],
    "Molotov": [("cross", "z", 0.5, 0.15, 1.3)],
    "Tomato": [("squash", 1.15, 1.15, 0.88)],
    "Revolver": [("thick", 1.35), ("cross", "y", -0.8, -1.1, 1.15)],
    "Shotgun": [("thick", 1.35), ("cross", "y", -1.8, -2.2, 1.4)],
    "Rifle": [("thick", 1.35), ("cross", "y", -1.9, -2.3, 1.4)],
    "Sniper": [("thick", 1.3), ("cross", "y", -3.0, -3.45, 1.45)],
    "Rocket": [("cross", "y", -1.7, -2.2, 1.35), ("cross", "y", 0.9, 1.3, 1.2)],
}


# Moving pieces (animated at runtime by WeaponMeshes.pose): every loose part whose bounding box lies
# inside lo..hi (original mesh, Blender axes) is tagged. longguns.py tags its own (Shotgun Pump).
PIECES = {
    "Revolver": [("Cylinder", (-0.2, -0.47, 0.1), (0.2, -0.11, 0.48))],
}


def islands(bm):
    seen, out = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        stack, comp = [f], []
        seen.add(f)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.edges:
                for g in e.link_faces:
                    if g not in seen:
                        seen.add(g)
                        stack.append(g)
        out.append(comp)
    return out


def tag(ob, pieces):
    """pieces: [(name, select(island_faces) -> bool)]. Face attribute "Piece" = 1-based index into ob["pieces"]."""
    me = ob.data
    names = list(ob.get("pieces", []))
    bm = bmesh.new()
    bm.from_mesh(me)
    layer = bm.faces.layers.int.get("Piece") or bm.faces.layers.int.new("Piece")
    for name, select in pieces:
        if name not in names:
            names.append(name)
        for comp in islands(bm):
            if select(comp):
                for f in comp:
                    f[layer] = names.index(name) + 1
    bm.to_mesh(me)
    bm.free()
    ob["pieces"] = names


def inside(lo, hi):
    def select(comp):
        vs = {v for f in comp for v in f.verts}
        return all(lo[i] <= v.co[i] <= hi[i] for v in vs for i in range(3))
    return select


def ramp(c, a, b):
    t = max(0.0, min(1.0, (c - a) / (b - a)))
    return t * t * (3 - 2 * t)


def centre(vs):
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return (lo + hi) / 2, lo


def shape(me, ops):
    vs = [v.co for v in me.vertices]
    for op in ops:
        kind = op[0]
        if kind == "thick":
            for v in vs:
                v.x *= op[1]
        elif kind == "squash":
            c, lo = centre(vs)
            base = Vector((c.x, c.y, lo.z))
            for v in vs:
                d = v - base
                v.x, v.y, v.z = base.x + d.x * op[1], base.y + d.y * op[2], base.z + d.z * op[3]
        else:  # swell: grow uniformly about the region's centre; cross: only across the axis
            _, axis, a, b, f = op
            i = AX[axis]
            far = [v for v in vs if ramp(v[i], a, b) > 0.999] or vs
            c, _ = centre(far)
            for v in vs:
                t = ramp(v[i], a, b)
                if t == 0:
                    continue
                d = (v - c) * ((f - 1) * t)
                if kind == "cross":
                    d[i] = 0
                v += d


def punch(me):
    for d in me.color_attributes["Col"].data:
        r, g, b, a = d.color_srgb
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        d.color_srgb = (*colorsys.hsv_to_rgb(h, min(1, s * 1.3), min(1, v * 1.12 + 0.02)), a)


def outline(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    lay = bm.loops.layers.color.get("Col") or bm.loops.layers.float_color.get("Col")
    bm.normal_update()
    size = max(max(v.co[i] for v in bm.verts) - min(v.co[i] for v in bm.verts) for i in range(3))
    t = min(0.035, max(0.018, 0.01 * size))
    acc = {}  # averaged normal per position, so split edges don't crack the shell
    for v in bm.verts:
        k = tuple(round(c, 4) for c in v.co)
        acc[k] = acc.get(k, Vector()) + v.normal
    geom = bmesh.ops.duplicate(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:])["geom"]
    for v in geom:
        if isinstance(v, bmesh.types.BMVert):
            n = acc[tuple(round(c, 4) for c in v.co)]
            if n.length > 1e-6:
                v.co += n.normalized() * t
    faces = [f for f in geom if isinstance(f, bmesh.types.BMFace)]
    bmesh.ops.reverse_faces(bm, faces=faces)
    for f in faces:
        for loop in f.loops:
            loop[lay] = (0, 0, 0, 1)
    bm.to_mesh(me)
    bm.free()


def load_originals(path):
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = [n for n in src.objects if n in RULES]
    material = bpy.data.materials["WeaponVertexColor"]
    for ob in dst.objects:
        target = bpy.data.objects[ob.name.rsplit(".", 1)[0] if ob.name not in RULES else ob.name]
        old = target.data
        target.data = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(old)
        target.data.name = target.name
        target.data.materials.clear()
        target.data.materials.append(material)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)


def main():
    if globals().get("SOURCE"):
        load_originals(SOURCE)
    # Shotgun and Sniper are built from code, not taken from the old blend
    exec(open(os.path.join(os.path.dirname(bpy.data.filepath), "longguns.py")).read(), {"__name__": "longguns"})
    for name, pieces in PIECES.items():
        tag(bpy.data.objects[name], [(piece, inside(lo, hi)) for piece, lo, hi in pieces])
    for name, ops in RULES.items():
        restyle(name, ops)


def restyle(name, ops):
    me = bpy.data.objects[name].data
    shape(me, ops)
    punch(me)
    outline(me)
    me.update()
    print(name, len(me.polygons), "faces")


if __name__ == "__main__":
    main()
