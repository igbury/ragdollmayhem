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
    piece = me.attributes.get("Piece")  # moving pieces (comic.py / longguns.py), names in ob["pieces"]
    names = list(ob.get("pieces", []))
    vs, ns, cs = {}, {}, {}
    groups = {name: (set(), set()) for name in names}  # piece -> (vertex ids, normal ids)

    def idx(table, key):
        if key not in table:
            table[key] = len(table) + 1
        return table[key]

    faces = []
    for tri in me.loop_triangles:
        p = piece.data[tri.polygon_index].value if piece else 0
        name = names[p - 1] if p else ""  # keys carry the piece, so it never shares a vertex or normal
        f = []
        for li in tri.loops:
            co = me.vertices[me.loops[li].vertex_index].co
            f.append(idx(vs, (name, fmt(-co.x), fmt(co.z), fmt(co.y))))
        for li in tri.loops:
            n = normals[li].vector
            f.append(idx(ns, (name, fmt(-n.x), fmt(n.z), fmt(n.y))))
        if name:
            groups[name][0].update(f[0:3])
            groups[name][1].update(f[3:6])
        c = col.data[tri.loops[0]].color_srgb
        f.append(idx(cs, (fmt(c[0]), fmt(c[1]), fmt(c[2]))))
        faces.append(f)

    def flat(table):
        return ",".join(",".join(k[-3:]) for k in table)

    def ids(s):
        return ",".join(map(str, sorted(s)))

    p = "".join(f"\t\t{name} = {{ v = {{{ids(v)}}}, n = {{{ids(n)}}} }},\n" for name, (v, n) in groups.items() if v)
    with open(os.path.join(OUT, ob.name + ".luau"), "w", newline="\n") as fh:
        fh.write(
            "-- Generated from assets/weapons/weapons.blend. v = xyz per vertex, n = xyz per normal, c = rgb per colour,\n"
            "-- f = 7 numbers per triangle: 3 vertex ids, 3 normal ids, 1 colour id (all 1-based),\n"
            "-- p = the vertex and normal ids of each moving piece (WeaponMeshes.pose).\n"
            "return {\n"
            f"\tv = {{{flat(vs)}}},\n"
            f"\tn = {{{flat(ns)}}},\n"
            f"\tc = {{{flat(cs)}}},\n"
            f"\tf = {{{','.join(','.join(map(str, f)) for f in faces)}}},\n"
            + (f"\tp = {{\n{p}\t}},\n" if p else "")
            + "}\n"
        )
    print(ob.name, len(vs), "verts", len(faces), "tris", {k: len(v[0]) for k, v in groups.items()})


for ob in bpy.data.objects:
    if ob.type == "MESH" and ob.name != "Cube" and ob.name in globals().get("NAMES", [ob.name]):
        export(ob)
