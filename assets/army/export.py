# Exports the army kit (build.py) for upload: assets/army/ArmyKit.glb + assets/army/manifest.json.
# Run inside Blender with army.blend open:
#   exec(open(r"<repo>/assets/army/export.py").read(), {"__file__": r"<repo>/assets/army/export.py"})
#
# Every piece is split into one mesh per colour (MeshPart.Color carries the colour: an uploaded mesh
# has no per-face colours), named "<Piece>__<HEX>". All of them go into ONE .glb, so the whole kit is
# one Model upload. The importer may move each MeshPart to its own bounding-box centre, so the
# manifest records where each one belongs instead: `at` = its box centre in Roblox space (studs) of
# the piece's origin (a uniform piece: the body part's centre; Heli_Body: the body; the rotors: their
# hub; the Baton: the grip), `size` = its box.
# The meshes are written in Roblox axes (glTF Y up = Roblox Y up, x and z as Roblox has them), so a
# MeshPart with no rotation is the right way round: Blender holds them as (-x, z, y) (build.py), so
# they are turned 180 degrees about Blender Z before export, which the glTF exporter then makes
# (x, y, z). Checked once against an asymmetric piece after the first import (see install.lua).
import json
import os

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIXES = ("Soldier_", "Heavy_", "Worker_", "Zombie_", "Heli_", "Baton", "Cop_", "Sport_", "Park_", "City_", "Factory_", "Tank_")
NEON = {"FF3030", "30FF60", "FFFFFF", "FF8A20", "FFF6D0", "3060FF", "FFF4C8", "F4F4E6"}
SEE_THROUGH = {"8FD0F0": 0.55, "2AA8D8": 0.15, "5AB4E0": 0.1, "364A66": 0.25, "1E2634": 0.15}
# the zombie's cloth (build.py: rags, mud, trousers, patch, tie, bandage, rope): Fabric when installed,
# so in the game's flat light the rags have a weave instead of looking like plastic
FABRIC = {"6A604C", "4A4436", "5C4E3A", "2E3446", "5A6680", "4A3A6A", "D8D2C0", "7C6C48"}
TRI_CAP = 19000


def blender_to_roblox(v):
    return (-v.x, v.z, v.y)


def main():
    kit = [ob for ob in bpy.data.objects if ob.type == "MESH" and ob.name.startswith(PREFIXES) and "__" not in ob.name]
    out_col = bpy.data.collections.get("Export") or bpy.data.collections.new("Export")
    if out_col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(out_col)
    out_col.hide_viewport = False  # hidden at the end of the last export: hidden objects can't be selected
    for ob in list(out_col.objects):
        bpy.data.objects.remove(ob)
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
            name = f"{ob.name}__{hexcol}"
            if bpy.data.meshes.get(name):  # a last export's mesh: else this one comes out "<name>.001"
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
            r = blender_to_roblox(centre)
            s = hi - lo
            entries.append({
                "name": sub.name, "color": hexcol, "tris": tris,
                "at": [round(x, 4) for x in r], "size": [round(s.x, 4), round(s.z, 4), round(s.y, 4)],
                "neon": hexcol in NEON, "transparency": SEE_THROUGH.get(hexcol, 0),
                "fabric": ob.name.startswith("Zombie_") and hexcol in FABRIC,
            })
        manifest[ob.name] = entries
    # export only the split meshes, each at the origin (positions live in the manifest)
    bpy.ops.object.select_all(action="DESELECT")
    for part in out_col.objects:
        part.location = (0, 0, 0)
        part.select_set(True)
    bpy.context.view_layer.objects.active = out_col.objects[0]
    path = os.path.join(HERE, "ArmyKit.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_normals=True)
    with open(os.path.join(HERE, "manifest.json"), "w", newline="\n") as fh:
        json.dump(manifest, fh, indent=1)
    total = sum(len(v) for v in manifest.values())
    print("exported", total, "meshes from", len(manifest), "pieces ->", path, round(os.path.getsize(path) / 1024), "KB")
    out_col.hide_viewport = True


main()
