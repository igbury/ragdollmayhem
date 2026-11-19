# Exports the factory kit (build.py) for Studio: assets/factory/FactoryKit.glb + manifest.json.
# Run inside Blender with factory.blend open:
#   exec(open(r"<repo>/assets/factory/export.py").read(), {"__file__": r"<repo>/assets/factory/export.py"})
#
# As assets/port/export.py: every piece split into one mesh per colour, "<Piece>__<HEX>", all in ONE
# .glb; the manifest records where each mesh's box centre sits in its piece's space (`at`, studs,
# Roblox axes), since the importer recentres every mesh. `finish` is the Roblox material per colour.
import json
import os

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIXES = ("Factory_",)
FINISH = {"FF6E14": "Neon", "BEBEC3": "Metal"}  # lava glows, chrome shines; the rest is Plastic
TRI_CAP = 19000


def blender_to_roblox(v):
    return (-v.x, v.z, v.y)


def main():
    kit = [ob for ob in bpy.data.objects if ob.type == "MESH" and ob.name.startswith(PREFIXES) and "__" not in ob.name]
    out_col = bpy.data.collections.get("Export") or bpy.data.collections.new("Export")
    if out_col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(out_col)
    out_col.hide_viewport = False  # hidden after the last export: hidden objects cannot be selected
    for ob in list(out_col.objects):
        bpy.data.objects.remove(ob)
    # and the meshes they left behind, or the new ones come out "<name>.001" (the importer names
    # parts after the meshes, and install.luau reads the colour from the name)
    for me in list(bpy.data.meshes):
        if me.users == 0 and "__" in me.name and me.name.startswith(PREFIXES):
            bpy.data.meshes.remove(me)
    manifest = {}
    turn = Matrix.Rotation(3.141592653589793, 4, "Z")
    for ob in kit:
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
            sub = bpy.data.meshes.new(f"{ob.name}__{hexcol}")
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
                "finish": FINISH.get(hexcol, "Plastic"),
            })
        manifest[ob.name] = entries
    bpy.ops.object.select_all(action="DESELECT")
    for part in out_col.objects:
        part.location = (0, 0, 0)
        part.select_set(True)
    bpy.context.view_layer.objects.active = out_col.objects[0]
    path = os.path.join(HERE, "FactoryKit.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_normals=True,
                              export_animations=False, export_cameras=False, export_lights=False)
    with open(os.path.join(HERE, "manifest.json"), "w", newline="\n") as fh:
        json.dump(manifest, fh, indent=1)
    total = sum(len(v) for v in manifest.values())
    tris = sum(e["tris"] for v in manifest.values() for e in v)
    print("exported", total, "meshes,", tris, "tris, from", len(manifest), "pieces ->", path, round(os.path.getsize(path) / 1024), "KB")
    out_col.hide_viewport = True


main()
