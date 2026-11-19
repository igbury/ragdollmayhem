"""Exports the Myth Yard bosses and cages (build_myth_yard.py) for Roblox: assets/myth/.

Run headless on the built scene:
  blender -b blender/myth_yard.blend --factory-startup --python-exit-code 1 -P blender/export_myth_kit.py

Writes one GLB per monster (MythKit_<Kind>.glb: the boss and its cage), manifest.json and,
through assets/myth/gen_install.py, install.luau.

* Bosses are exported in their rest pose and in the boss root's own (unscaled) space, the same space
  as MythRig's part rig before Model:ScaleTo. Every mesh is grouped by the joint that moves it and
  that joint's rig part (Neck -> Head, ElbowR -> RightLowerArm (hand included), ...).
* Cages are exported in cage space (the cage root = the boss's home on the yard floor) as "Static"
  and "Gate" (the part that opens when the boss is released).
* Each group is split into one mesh per material (a MeshPart has one colour and one material) and
  into chunks under the 20k-triangle mesh limit. The manifest records where each mesh's box centre
  sits (Roblox axes, studs), its colour, material and finish.
* Point lights (flames, ichor glow) are listed with their place, colour and strength.
Axes: Blender (x, y, z) -> Roblox (-x, z, y); meshes are turned 180 degrees about Blender Z before
export so the glTF (Y up) is in Roblox axes (same as assets/army/export.py).
"""
import bpy, bmesh, json, math, os, subprocess, sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets", "myth")
os.makedirs(OUT, exist_ok=True)
TRI_CAP = 19000
KINDS = {"Cyclops": "Cyclops", "Minotaur": "Minotaur", "Talos": "Talos"}
GATES = {"Cyclops": ("Portcullis",), "Minotaur": ("Lab_Gate",), "Talos": ("Talos_Cage", "DomeArc")}
JOINT_PART = {
    "Root": "HumanoidRootPart", "Hips": "LowerTorso", "Spine": "UpperTorso", "Neck": "Head",
    "ShoulderR": "RightUpperArm", "ShoulderL": "LeftUpperArm", "ElbowR": "RightLowerArm", "ElbowL": "LeftLowerArm",
    "HipR": "RightUpperLeg", "HipL": "LeftUpperLeg", "KneeR": "RightLowerLeg", "KneeL": "LeftLowerLeg",
}


def r3(v):
    return [round(-v.x, 4), round(v.z, 4), round(v.y, 4)]


def srgb(c):
    def f(v):
        v = max(0.0, min(1.0, v))
        return v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return "%02X%02X%02X" % tuple(round(f(x) * 255) for x in c[:3])


def finish(m):
    """Roblox material, neon flag for a Blender material."""
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    emit = bsdf.inputs["Emission Strength"].default_value if bsdf else 0
    metal = bsdf.inputs["Metallic"].default_value if bsdf else 0
    n = m.name.lower()
    if emit > 0.5:
        return "Neon"
    if metal > 0.5:
        return "Metal"
    for key, rb in (("marble", "Marble"), ("slate", "Slate"), ("granite", "Granite"), ("sand", "Sand"),
                    ("wood", "Wood"), ("plank", "WoodPlanks"), ("straw", "Fabric"), ("cloth", "Fabric"),
                    ("leather", "Fabric"), ("rope", "Fabric"), ("hair", "Fabric"), ("fur", "Fabric"),
                    ("mortar", "Concrete"), ("brick", "Brick"), ("cobble", "Cobblestone"), ("stone", "Slate"),
                    ("moss", "Grass"), ("rust", "CorrodedMetal"), ("terracotta", "Brick"), ("coal", "Basalt")):
        if key in n:
            return rb
    return "SmoothPlastic"


def simplify():
    """Game LOD: one bevel segment, one subdivision level, less curve resolution."""
    for ob in bpy.data.objects:
        for md in getattr(ob, "modifiers", []):
            if md.type == "BEVEL":
                md.segments = 1
            elif md.type == "SUBSURF":
                md.levels = md.render_levels = min(md.render_levels, 1)
        if ob.type == "CURVE":
            ob.data.bevel_resolution = min(ob.data.bevel_resolution, 1)
            ob.data.resolution_u = min(ob.data.resolution_u, 6)
        if ob.type == "FONT":
            ob.data.bevel_depth = 0
            ob.data.resolution_u = 4


class Bucket:
    def __init__(self):
        self.co, self.faces, self.smooth = [], [], []


def collect(obs, frame, group_of, buckets, mats):
    dg = bpy.context.evaluated_depsgraph_get()
    inv = frame.matrix_world.inverted()
    for ob in obs:
        if ob.type not in ("MESH", "CURVE", "FONT") or ob.hide_render:
            continue
        group = group_of(ob)
        if group is None:
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        M = inv @ ob.matrix_world
        co = [M @ v.co for v in me.vertices]
        for p in me.polygons:
            if not ob.material_slots:
                continue
            m = ob.material_slots[min(p.material_index, len(ob.material_slots) - 1)].material
            if m is None:
                continue
            mats[m.name] = m
            b = buckets.setdefault((group, m.name), Bucket())
            base = len(b.co)
            b.co.extend(co[v] for v in p.vertices)
            b.faces.append(list(range(base, base + len(p.vertices))))
            b.smooth.append(p.use_smooth)
        ev.to_mesh_clear()


def emit_meshes(kind, buckets, mats, out_col, entries):
    turn = Matrix.Rotation(math.pi, 4, "Z")
    for (group, mname), b in sorted(buckets.items()):
        m = mats[mname]
        # chunks under the per-mesh triangle cap, in face order (batches are spatially coherent)
        chunks, cur, tris = [], [], 0
        for i, f in enumerate(b.faces):
            t = len(f) - 2
            if cur and tris + t > TRI_CAP:
                chunks.append(cur)
                cur, tris = [], 0
            cur.append(i)
            tris += t
        if cur:
            chunks.append(cur)
        for ci, idx in enumerate(chunks):
            used = sorted({v for i in idx for v in b.faces[i]})
            remap = {v: k for k, v in enumerate(used)}
            co = [b.co[v] for v in used]
            lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
            hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
            centre = (lo + hi) / 2
            name = f"{kind}_{group}__{len(entries)}"
            me = bpy.data.meshes.new(name)
            me.from_pydata([c - centre for c in co], [], [[remap[v] for v in b.faces[i]] for i in idx])
            for p, i in zip(me.polygons, idx):
                p.use_smooth = b.smooth[i]
            me.transform(turn)
            # merge the duplicated corners back so smooth faces share normals across primitives' edges
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
            bm.to_mesh(me)
            bm.free()
            try:
                me.set_sharp_from_angle(angle=math.radians(40))
            except Exception:
                pass
            me.materials.append(m)
            me.update()
            ob = bpy.data.objects.new(name, me)
            out_col.objects.link(ob)
            s = hi - lo
            entries.append({
                "name": name, "group": group, "color": srgb(m.diffuse_color), "material": finish(m),
                "tris": sum(len(p.vertices) - 2 for p in me.polygons),
                "at": r3(centre), "size": [round(s.x, 3), round(s.z, 3), round(s.y, 3)],
            })


def lights_in(obs, frame, group_of):
    out = []
    for ob in obs:
        if ob.type != "LIGHT" or ob.data.type not in ("POINT", "SPOT"):
            continue
        group = group_of(ob)
        if group is None:
            continue
        p = frame.matrix_world.inverted() @ ob.matrix_world.translation
        e = ob.data.energy
        out.append({"group": group, "at": r3(p), "color": srgb(ob.data.color),
                    "brightness": round(min(3.0, 0.6 + e / 120), 2), "range": round(min(24.0, 8 + math.sqrt(e) * 1.2), 1)})
    return out


def main():
    simplify()
    # every boss in its rest pose, standing at its root
    for ob in bpy.data.objects:
        if ob.type == "EMPTY" and ob.rotation_mode != "QUATERNION":
            if any(c.name.startswith("Boss_") for c in ob.users_collection) and not ob.name.startswith("Boss_"):
                ob.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

    out_col = bpy.data.collections.new("Export")
    bpy.context.scene.collection.children.link(out_col)
    manifest = {}
    for kind in KINDS:
        B = bpy.data.objects["Boss_" + kind]
        cage_root = bpy.data.objects["Cage_" + kind]
        prefix = next(c.name[:-4] for c in B.children if c.type == "EMPTY" and c.name.endswith("Hips"))
        joints = {B.name: "HumanoidRootPart"}
        for ob in B.children_recursive:
            if ob.type == "EMPTY" and ob.name.startswith(prefix) and ob.name[len(prefix):] in JOINT_PART:
                joints[ob.name] = JOINT_PART[ob.name[len(prefix):]]

        def boss_group(ob):
            p = ob.parent
            while p is not None and p.name not in joints:
                p = p.parent
            return joints.get(p.name) if p else None

        gate_names = GATES[kind]

        def cage_group(ob):
            return "Gate" if ob.name.startswith(gate_names) else "Static"

        boss_obs = list(bpy.data.collections["Boss_" + kind].all_objects)
        cage_obs = list(bpy.data.collections["Cage_" + kind].all_objects)
        entries, mats = [], {}
        buckets = {}
        collect(boss_obs, B, boss_group, buckets, mats)
        emit_meshes(kind, buckets, mats, out_col, entries)
        boss_entries = entries
        entries, buckets = [], {}
        collect(cage_obs, cage_root, cage_group, buckets, mats)
        start = len(boss_entries)
        tmp = boss_entries + entries
        emit_meshes(kind, buckets, mats, out_col, tmp)
        cage_entries = tmp[start:]
        # the boss's feet in cage space (it stands on a plinth / dais in some cages)
        stand = cage_root.matrix_world.inverted() @ B.matrix_world.translation
        gate = [e for e in cage_entries if e["group"] == "Gate"]
        glo = [min(e["at"][i] - e["size"][i] / 2 for e in gate) for i in range(3)]
        ghi = [max(e["at"][i] + e["size"][i] / 2 for e in gate) for i in range(3)]
        manifest[kind] = {
            "boss": boss_entries, "cage": cage_entries,
            "boss_lights": lights_in(boss_obs, B, boss_group),
            "cage_lights": lights_in(cage_obs, cage_root, cage_group),
            "stand": r3(stand), "gate_box": [glo, ghi],
        }
        # one GLB per monster
        bpy.ops.object.select_all(action="DESELECT")
        names = {e["name"] for e in boss_entries + cage_entries}
        sel = [o for o in out_col.objects if o.name in names]
        for o in sel:
            o.select_set(True)
        bpy.context.view_layer.objects.active = sel[0]
        path = os.path.join(OUT, f"MythKit_{kind}.glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_materials="NONE", export_normals=True,
                                  export_texcoords=False)
        bt = sum(e["tris"] for e in boss_entries)
        ct = sum(e["tris"] for e in cage_entries)
        print(f"@@JSON@@" + json.dumps({"kind": kind, "boss_meshes": len(boss_entries), "boss_tris": bt,
                                        "cage_meshes": len(cage_entries), "cage_tris": ct,
                                        "lights": len(manifest[kind]["boss_lights"]) + len(manifest[kind]["cage_lights"]),
                                        "stand": manifest[kind]["stand"], "gate_box": manifest[kind]["gate_box"],
                                        "glb_kb": round(os.path.getsize(path) / 1024)}))
    with open(os.path.join(OUT, "manifest.json"), "w", newline="\n") as fh:
        json.dump(manifest, fh, indent=1)


main()
