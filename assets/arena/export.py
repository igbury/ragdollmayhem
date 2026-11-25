# Exports the arena kit (build.py) for Roblox: assets/arena/ArenaKit.glb + assets/arena/manifest.json.
#   blender -b assets/arena/arena.blend -P assets/arena/export.py
# The army kit's way (assets/army/export.py): every piece split into one mesh per colour named
# "<Piece>__<HEX>" (MeshPart.Color carries the colour), all in one .glb; the manifest records each
# mesh's box centre in its piece's space, since the importer moves every MeshPart to its own centre.
# Meshes are turned 180 degrees about Blender Z so the glTF comes out in Roblox axes.
import json
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
NEON = {"FFE29A", "FF7A1E", "FFD040", "FF4E1A", "39D0E6"}  # build.py NEON
SEE_THROUGH = {"8FD0F0": 0.45, "4FB4EC": 0.3, "BCE6FF": 0.45}  # build.py SEE_THROUGH
GRASSY = set()
TRI_CAP = 19000


def blender_to_roblox(v):
    return (-v.x, v.z, v.y)


def main():
    kit = [ob for ob in bpy.data.objects if ob.type == "MESH" and ob.name.startswith("Arena_") and "__" not in ob.name]
    out_col = bpy.data.collections.get("Export") or bpy.data.collections.new("Export")
    if out_col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(out_col)
    for ob in list(out_col.objects):
        bpy.data.objects.remove(ob)
    manifest = {}
    turn = Matrix.Rotation(3.141592653589793, 4, "Z")
    for ob in sorted(kit, key=lambda o: o.name):
        me = ob.data
        entries = []
        for mi, mat in enumerate(me.materials):
            hexcol = mat.name
            faces = [p for p in me.polygons if p.material_index == mi]
            if not faces:
                continue
            used = sorted({v for p in faces for v in p.vertices})
            remap = {v: i for i, v in enumerate(used)}
            co = [me.vertices[v].co.copy() for v in used]
            lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
            hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
            centre = (lo + hi) / 2
            name = f"{ob.name}__{hexcol}"
            if bpy.data.meshes.get(name):
                bpy.data.meshes.remove(bpy.data.meshes[name])
            sub = bpy.data.meshes.new(name)
            sub.from_pydata([c - centre for c in co], [], [[remap[v] for v in p.vertices] for p in faces])
            sub.materials.append(mat)
            for p in sub.polygons:
                p.use_smooth = False
            sub.transform(turn)
            sub.update()
            tris = sum(len(p.vertices) - 2 for p in sub.polygons)
            assert tris <= TRI_CAP, f"{sub.name}: {tris} triangles is over the per-mesh cap"
            part = bpy.data.objects.new(sub.name, sub)
            out_col.objects.link(part)
            s = hi - lo
            entries.append({
                "name": sub.name, "color": hexcol, "tris": tris,
                "at": [round(x, 4) for x in blender_to_roblox(centre)], "size": [round(s.x, 4), round(s.z, 4), round(s.y, 4)],
                "neon": hexcol in NEON, "transparency": SEE_THROUGH.get(hexcol, 0),
            })
        manifest[ob.name] = entries
    # export only the split meshes, each at the origin (positions live in the manifest)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for part in out_col.objects:
        part.location = (0, 0, 0)
        part.select_set(True)
    bpy.context.view_layer.objects.active = out_col.objects[0]
    path = os.path.join(HERE, "ArenaKit.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_normals=True)
    with open(os.path.join(HERE, "manifest.json"), "w", newline="\n") as fh:
        json.dump(manifest, fh, indent=1)
    total = sum(len(v) for v in manifest.values())
    tris = sum(e["tris"] for v in manifest.values() for e in v)
    print("exported", total, "meshes from", len(manifest), "pieces,", tris, "tris ->", path, round(os.path.getsize(path) / 1024), "KB")


main()
