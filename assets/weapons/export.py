# Exports weapon meshes from weapons.blend into src/client/WeaponMeshes/<Name>.luau.
# Run inside Blender with the .blend open:  exec(open(r"<repo>/assets/weapons/export.py").read())
# Set NAMES first to export only some objects (default: every mesh except "Cube").
# Axes: Roblox (x, y, z) = Blender (-x, z, y)  (Blender +Z up -> Roblox +Y, Blender -Y -> Roblox -Z forward).
# Origin = the object's origin = the grip. Colours: the "Col" corner attribute (sRGB), one per face.
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.dirname(bpy.data.filepath)))
OUT = os.path.join(REPO, "src", "client", "WeaponMeshes")


def fmt(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def export(ob):
    me = ob.data
    me.calc_loop_triangles()
    col = me.color_attributes["Col"]
    normals = me.corner_normals
    vs, ns, cs = {}, {}, {}

    def idx(table, key):
        if key not in table:
            table[key] = len(table) + 1
        return table[key]

    faces = []
    for tri in me.loop_triangles:
        f = []
        for li in tri.loops:
            co = me.vertices[me.loops[li].vertex_index].co
            f.append(idx(vs, (fmt(-co.x), fmt(co.z), fmt(co.y))))
        for li in tri.loops:
            n = normals[li].vector
            f.append(idx(ns, (fmt(-n.x), fmt(n.z), fmt(n.y))))
        c = col.data[tri.loops[0]].color_srgb
        f.append(idx(cs, (fmt(c[0]), fmt(c[1]), fmt(c[2]))))
        faces.append(f)

    def flat(table):
        return ",".join(",".join(k) for k in table)

    with open(os.path.join(OUT, ob.name + ".luau"), "w", newline="\n") as fh:
        fh.write(
            "-- Generated from assets/weapons/weapons.blend. v = xyz per vertex, n = xyz per normal, c = rgb per colour,\n"
            "-- f = 7 numbers per triangle: 3 vertex ids, 3 normal ids, 1 colour id (all 1-based).\n"
            "return {\n"
            f"\tv = {{{flat(vs)}}},\n"
            f"\tn = {{{flat(ns)}}},\n"
            f"\tc = {{{flat(cs)}}},\n"
            f"\tf = {{{','.join(','.join(map(str, f)) for f in faces)}}},\n"
            "}\n"
        )
    print(ob.name, len(vs), "verts", len(faces), "tris")


for ob in bpy.data.objects:
    if ob.type == "MESH" and ob.name != "Cube" and ob.name in globals().get("NAMES", [ob.name]):
        export(ob)
