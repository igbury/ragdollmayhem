# Exports the ruby visor (build_visor.py) as the kit piece "LaserVisor": assets/visor/LaserVisor.glb and
# its entries in assets/army/manifest.json (then run assets/army/gen_install.py, MERGE = true).
# Run inside Blender:  exec(open(r"<repo>/assets/visor/export_visor.py").read(), {"__file__": r"<repo>/assets/visor/export_visor.py"})
#
# Same conventions as assets/army/export.py: one mesh per colour named "LaserVisor__<HEX>", each centred
# on its box, positions in the manifest in Roblox studs of the piece's origin (the visor's centre). The
# visor is modelled front -Y, up +Z, which is already the kit's Blender storage (-x, z, y) of Roblox axes.
# It is rebuilt at a lower resolution for the game; the .blend's own scene is rebuilt afterwards.
# Set by hand in the place after install.luau (the installer has no field for them): the C9CED6 shell part
# Material Metal, Color AEB4BE (reads as chrome); the 2BFF4A lens DoubleSided.
import json
import math
import os

import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ARMY = os.path.join(HERE, "..", "army")
STUDS = 6.8          # studs per metre: 0.22 m wide -> 1.5 studs, round a 1.15-stud R15 head
COLOUR = {           # object -> kit colour (the toon materials don't survive; MeshPart.Color does)
    "Visor_Front_Shell": "C9CED6", "Visor_Side_Arms": "C9CED6",   # silver
    "Ruby_Lens": "2BFF4A", "Inner_Red_Frame": "1F5E2E",           # green glass, dark green frame
}  # the side pods, their floors / dial notches and the arms' inner trim are left out: plain glasses temples instead
NEON = {"2BFF4A"}

ns = {}
exec(open(os.path.join(HERE, "build_visor.py")).read(), ns)
ns["N1"], ns["N2"] = 12, 5                 # outline points per quadrant (game resolution)
ns["ARM_STEPS"], ns["ARM_SEGS"] = 10, 12
# the game's visor is angular: near-sharp corners, a chamfered slit, a V nose cut, boxy glasses temples,
# flat shading (the .blend keeps the original rounded gold/ruby look)
ns["R_CORNER"] = 0.002
_lathe, _rrect = ns["lathe"], ns["rrect"]
ns["lathe"] = lambda profile, segs=48: _lathe(profile, 8)
ns["pill"] = lambda e=0.0: _rrect(ns["seam_u"]() - 0.0165 + e, ns["SLIT_B"] + e, (ns["SLIT_B"] + e) * 0.35, ns["SLIT_Z"])


def _plate_outline(ext=1.0):
    U = ns["seam_u"]()
    out = []
    for x, y in _rrect(U, ns["B_FRONT"], ns["R_CORNER"]):
        f = abs(x) / U
        y *= 1 - (1 - ns["B_END"] / ns["B_FRONT"]) * f * f
        if y < 0 and abs(x) < ns["NOTCH_W"]:           # V nose cut
            y += ns["NOTCH_D"] * (1 - abs(x) / ns["NOTCH_W"])
        out.append((x, y))
    return out


def _arm_section(h, n=None):
    n = n or ns["ARM_SEGS"]
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        pts.append((ns["ARM_T"] * math.copysign(abs(c) ** 0.15, c), h * math.copysign(abs(s) ** 0.15, s)))
    return pts


TEMPLE_H = 0.0065    # temple half height (the band's is ARM_H0)
TEMPLE_BACK = 0.045  # how far the temple runs on straight back past the old pod
TEMPLE_HOOK = 0.02   # the last part bends down behind the ear


def _arms(mats=None):
    """The band narrows into a plain glasses temple that runs straight back and hooks down at the end."""
    U, L = ns["seam_u"](), ns["path_len"]()
    u0, u1 = U - 0.007, L + TEMPLE_BACK
    T = ns["T"]
    rings = []
    steps = 18
    for k in range(steps + 1):
        u = u0 + (u1 - u0) * k / steps
        g = min(max((u - U) / (0.75 * L - U), 0.0), 1.0)
        g = g * g * (3 - 2 * g)
        h = ns["ARM_H0"] * (1 - g) + TEMPLE_H * g
        zc = -0.9 * max(0.0, u - (u1 - TEMPLE_HOOK))   # the hook: about 40 degrees down
        rings.append([ns["wrap"](u, z + zc, T / 2 + dx) for dx, z in _arm_section(h)])
    bm, vs = ns["loft"](rings, closed=False)
    bm.faces.new(vs[-1])   # the temple's tip is in the open now (the pod used to hide it)
    ns["bmesh"].ops.recalc_face_normals(bm, faces=bm.faces[:])
    ns["new_obj"]("Visor_Side_Arms", bm, ns["COLS"][0], mirror=True)


ns["plate_outline"], ns["arm_section"], ns["arms"] = _plate_outline, _arm_section, _arms
ns["build_all"]()

dg = bpy.context.evaluated_depsgraph_get()
groups = {}
for name, hexcol in COLOUR.items():
    ob = bpy.data.objects[name]
    for md in ob.modifiers:
        if md.type == 'SUBSURF':
            md.levels = 0   # smooth-shaded cage: ~5k triangles for the whole visor
    dg.update()
    me = ob.evaluated_get(dg).to_mesh()
    verts = [(ob.matrix_world @ v.co) * STUDS for v in me.vertices]
    g = groups.setdefault(hexcol, ([], []))
    base = len(g[0])
    g[0].extend(verts)
    g[1].extend([[base + i for i in p.vertices] for p in me.polygons])
    ob.evaluated_get(dg).to_mesh_clear()

out_col = bpy.data.collections.get("Export") or bpy.data.collections.new("Export")
if out_col.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(out_col)
for ob in list(out_col.objects):
    bpy.data.objects.remove(ob)
turn = Matrix.Rotation(3.141592653589793, 4, "Z")
entries = []
for hexcol, (verts, faces) in groups.items():
    lo = [min(v[i] for v in verts) for i in range(3)]
    hi = [max(v[i] for v in verts) for i in range(3)]
    c = [(a + b) / 2 for a, b in zip(lo, hi)]
    name = f"LaserVisor__{hexcol}"
    if bpy.data.meshes.get(name):
        bpy.data.meshes.remove(bpy.data.meshes[name])
    sub = bpy.data.meshes.new(name)
    sub.from_pydata([(v[0] - c[0], v[1] - c[1], v[2] - c[2]) for v in verts], [], faces)
    sub.shade_flat()
    sub.transform(turn)
    sub.update()
    tris = sum(len(p.vertices) - 2 for p in sub.polygons)
    assert tris <= 19000, f"{name}: {tris} triangles"
    part = bpy.data.objects.new(name, sub)
    out_col.objects.link(part)
    entries.append({"name": name, "color": hexcol, "tris": tris,
                    "at": [round(-c[0], 4), round(c[2], 4), round(c[1], 4)],
                    "size": [round(hi[0] - lo[0], 4), round(hi[2] - lo[2], 4), round(hi[1] - lo[1], 4)],
                    "neon": hexcol in NEON, "transparency": 0, "fabric": False, "textured": False})

bpy.ops.object.select_all(action="DESELECT")
for part in out_col.objects:
    part.select_set(True)
bpy.context.view_layer.objects.active = out_col.objects[0]
path = os.path.join(HERE, "LaserVisor.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                          export_yup=True, export_materials="NONE", export_normals=True)
for ob in list(out_col.objects):
    bpy.data.objects.remove(ob)
bpy.data.collections.remove(out_col)

mpath = os.path.join(ARMY, "manifest.json")
manifest = json.load(open(mpath))
manifest["LaserVisor"] = entries
with open(mpath, "w", newline="\n") as fh:
    json.dump(manifest, fh, indent=1)
print("LaserVisor:", [(e["name"], e["tris"]) for e in entries], "total", sum(e["tris"] for e in entries))

# put the full-resolution scene back
ns2 = {}
exec(open(os.path.join(HERE, "build_visor.py")).read(), ns2)
ns2["build_all"]()
