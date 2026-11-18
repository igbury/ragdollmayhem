# The army kit for Wanted (soldier and heavy uniforms, the helicopter, the police baton), modelled in
# code in Blender in the weapons' comic style: chunky bevelled shapes, flat saturated colours, a
# black inverted-hull outline (as assets/weapons/comic.py bakes it). Run inside Blender:
#   exec(open(r"<repo>/assets/army/build.py").read())
# It rebuilds every piece in the open file and saves it as assets/army/army.blend.
#
# Everything is written in ROBLOX space, in studs (x right, y up, front -Z) and converted on the
# way in: Blender = (-x, z, y) (the same axes export.py uses for the weapons).
# A uniform piece sits around the centre of the body part it is welded to (R15 sizes measured on
# the dummies' body: the Roblox Boy bundle). One object per piece; every colour is its own material,
# named by its hex, so export.py can split it into one mesh per colour (MeshPart.Color carries it).
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) if "__file__" in globals() else None

R2B = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Roblox -> Blender (a rotation: det +1)
OUTLINE = 0.024  # studs the black shell sits off the surface (comic.py: 0.018..0.035)

# palette (sRGB hex); "special" finishes are set on the MeshPart when the kit is installed
OLIVE, OLIVE_DARK, OLIVE_DEEP = "6E8A3A", "4E6428", "3A4A1E"
TAN, KHAKI, SAND = "C9A86A", "9E8E5E", "D8C08A"
STRAP, BLACK, GUNMETAL = "2E2A24", "1C1C20", "3A3C44"
CHARCOAL, PLATE, PLATE_LIGHT, EDGE = "343844", "4E5566", "7A8296", "1A1C22"
VISOR, LENS, GLASS = "2AA8D8", "5AB4E0", "8FD0F0"
SKIN, RED, GREEN, WHITE, YELLOW, ORANGE = "E0DED8", "FF3030", "30FF60", "FFFFFF", "FFCC22", "FF8A20"
HELI, HELI_DARK, HELI_STRIPE = "5E7A34", "2C3424", "E8D27A"
NEON = {RED, GREEN, WHITE, ORANGE, "FFF6D0"}  # glow (Neon) when installed
SEE_THROUGH = {GLASS: 0.55, VISOR: 0.15, LENS: 0.1}

R15 = {  # measured part sizes (studs)
    "Head": (1.16, 1.18, 1.16), "UpperTorso": (1.76, 1.88, 1.11), "LowerTorso": (1.69, 0.57, 0.96),
    "UpperArm": (0.57, 1.16, 0.78), "LowerArm": (0.63, 1.01, 0.62), "Hand": (0.68, 1.16, 0.77),
    "UpperLeg": (0.75, 1.54, 0.75), "LowerLeg": (0.74, 1.17, 0.8), "Foot": (0.84, 0.65, 1.24),
}


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def material(h):
    m = bpy.data.materials.get(h)
    if not m:
        m = bpy.data.materials.new(h)
        r, g, b = hex_rgb(h)
        lin = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))
        m.diffuse_color = (*lin, 1)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs[0].default_value = (*lin, 1)
        bsdf.inputs["Roughness"].default_value = 0.7
    return m


class Piece:
    """Collects shapes for one object, in Roblox space, then bakes it into Blender."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.cols = []  # material order
        self.layer = None

    def _col(self, h):
        if h not in self.cols:
            self.cols.append(h)
        return self.cols.index(h)

    def _place(self, geom_verts, faces, at, rot, h):
        m = Matrix.Translation(R2B @ Vector(at)) @ (R2B @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix() @ R2B.inverted()).to_4x4()
        bmesh.ops.transform(self.bm, matrix=m, verts=geom_verts)
        i = self._col(h)
        for f in faces:
            f.material_index = i

    def box(self, size, at, h, rot=(0, 0, 0), bevel=0.05):
        """A block `size` (Roblox x, y, z) centred `at`, edges rounded by `bevel` studs."""
        sx, sy, sz = size
        res = bmesh.ops.create_cube(self.bm, size=1)
        vs = res["verts"]
        bmesh.ops.scale(self.bm, vec=(sx, sz, sy), verts=vs)  # Blender x, y(=Roblox z), z(=Roblox y)
        faces = list({f for v in vs for f in v.link_faces})
        b = min(bevel, 0.45 * min(size))
        if b > 0.005:
            edges = list({e for f in faces for e in f.edges})
            out = bmesh.ops.bevel(self.bm, geom=edges, offset=b, segments=2, profile=0.5, affect="EDGES")
            faces = [f for f in set(faces) | set(out["faces"]) if f.is_valid]
            vs = list({v for f in faces for v in f.verts})
        faces = [f for f in faces if f.is_valid]
        self._place(vs, faces, at, rot, h)

    def cyl(self, diameter, length, at, h, axis="y", rot=(0, 0, 0), segs=16, d2=None, bevel=0.0):
        """A cylinder (or cone, to `d2`) along Roblox `axis`, centred `at`."""
        dx = diameter if isinstance(diameter, (int, float)) else diameter[0]
        dz = diameter if isinstance(diameter, (int, float)) else diameter[1]
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=0.5, radius2=0.5 * (d2 / dx if d2 else 1), depth=1)
        vs = res["verts"]
        bmesh.ops.scale(self.bm, vec=(dx, dz, length), verts=vs)  # along Blender Z = Roblox Y
        turn = {"y": (0, 0, 0), "x": (0, 0, 90), "z": (90, 0, 0)}[axis]
        m = Euler([math.radians(a) for a in turn], "XYZ").to_matrix()
        bmesh.ops.transform(self.bm, matrix=(R2B @ m @ R2B.inverted()).to_4x4(), verts=vs)
        faces = list({f for v in vs for f in v.link_faces})
        if bevel > 0:
            caps = [e for e in {e for f in faces for e in f.edges} if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.dot(e.link_faces[1].normal)) < 0.5]
            out = bmesh.ops.bevel(self.bm, geom=caps, offset=bevel, segments=2, profile=0.5, affect="EDGES")
            faces = [f for f in set(faces) | set(out["faces"]) if f.is_valid]
            vs = list({v for f in faces for v in f.verts})
        faces = [f for f in faces if f.is_valid]
        self._place(vs, faces, at, rot, h)

    def ball(self, size, at, h, rot=(0, 0, 0), cut=None, segs=18, rings=10):
        """An ellipsoid of `size`; `cut`: keep only what is above this fraction of its height (a dome)."""
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=0.5)
        vs = res["verts"]
        if cut is not None:
            # slice the sphere with a plane and close the hole with a flat cap (flattening the lower
            # half instead folded faces over each other and turned half the dome inside out)
            geom = list({e for v in vs for e in v.link_edges}) + list({f for v in vs for f in v.link_faces}) + vs
            out = bmesh.ops.bisect_plane(self.bm, geom=geom, plane_co=(0, 0, cut - 0.5), plane_no=(0, 0, 1), clear_inner=True)
            vs = [g for g in out["geom"] if isinstance(g, bmesh.types.BMVert) and g.is_valid]
            rim = [e for e in {e for v in vs for e in v.link_edges} if e.is_boundary]
            if rim:
                cap = bmesh.ops.edgeloop_fill(self.bm, edges=rim)
                vs = list({v for f in cap["faces"] for v in f.verts} | set(vs))
            vs = [v for v in vs if v.is_valid]
        bmesh.ops.scale(self.bm, vec=(size[0], size[2], size[1]), verts=vs)
        faces = [f for f in {f for v in vs for f in v.link_faces} if f.is_valid]
        self._place(vs, faces, at, rot, h)

    def _solid(self, rings_pts, at, h, rot, closed=True):
        """Faces between consecutive point loops (Roblox-space lists of equal length)."""
        loops = [[self.bm.verts.new(R2B @ Vector(p)) for p in pts] for pts in rings_pts]
        n = len(loops[0])
        faces = []
        for a, b in zip(loops, loops[1:] + ([loops[0]] if closed else [])):
            for i in range(n):
                faces.append(self.bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])))
        vs = [v for l in loops for v in l]
        m = Matrix.Translation(R2B @ Vector(at)) @ (R2B @ Euler([math.radians(x) for x in rot], "XYZ").to_matrix() @ R2B.inverted()).to_4x4()
        bmesh.ops.transform(self.bm, matrix=m, verts=vs)
        i = self._col(h)
        for f in faces:
            f.material_index = i
        return faces

    def ring(self, radius, tube, at, h, rot=(0, 0, 0), segs=20, sides=8):
        """A torus in the Roblox XY plane (facing Z), centred `at`."""
        loops = []
        for i in range(segs):
            u = 2 * math.pi * i / segs
            cu, su = math.cos(u), math.sin(u)
            loops.append([((radius + tube * math.cos(2 * math.pi * j / sides)) * cu,
                           (radius + tube * math.cos(2 * math.pi * j / sides)) * su,
                           tube * math.sin(2 * math.pi * j / sides)) for j in range(sides)])
        faces = self._solid(loops, at, h, rot)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)

    def star(self, radius, depth, at, h, rot=(0, 0, 0), inner=0.42):
        """A five-pointed star plate in the Roblox YZ plane (facing X), point up."""
        pts = []
        for i in range(10):
            a = math.pi / 2 + i * math.pi / 5
            r = radius if i % 2 == 0 else radius * inner
            pts.append((r * math.cos(a), r * math.sin(a)))
        front = [self.bm.verts.new(R2B @ Vector((-depth / 2, y, z))) for y, z in pts]
        back = [self.bm.verts.new(R2B @ Vector((depth / 2, y, z))) for y, z in pts]
        cf = self.bm.verts.new(R2B @ Vector((-depth / 2, 0, 0)))
        cb = self.bm.verts.new(R2B @ Vector((depth / 2, 0, 0)))
        faces = []
        for i in range(10):
            j = (i + 1) % 10
            faces.append(self.bm.faces.new((cf, front[j], front[i])))
            faces.append(self.bm.faces.new((cb, back[i], back[j])))
            faces.append(self.bm.faces.new((front[i], front[j], back[j], back[i])))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        vs = front + back + [cf, cb]
        m = Matrix.Translation(R2B @ Vector(at)) @ (R2B @ Euler([math.radians(x) for x in rot], "XYZ").to_matrix() @ R2B.inverted()).to_4x4()
        bmesh.ops.transform(self.bm, matrix=m, verts=vs)
        i = self._col(h)
        for f in faces:
            f.material_index = i

    def wedge(self, size, at, h, rot=(0, 0, 0)):
        """A Roblox WedgePart's shape: full height at the back (+z), sloping to the front bottom edge."""
        sx, sy, sz = size
        x, y, z = sx / 2, sy / 2, sz / 2
        pts = [(-x, -y, -z), (x, -y, -z), (x, -y, z), (-x, -y, z), (-x, y, z), (x, y, z)]
        vs = [self.bm.verts.new(R2B @ Vector(p)) for p in pts]
        quads = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)]
        faces = [self.bm.faces.new([vs[i] for i in q]) for q in quads]
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        # place without the R2B on the points twice: they are already in Blender space
        m = Matrix.Translation(R2B @ Vector(at)) @ (R2B @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix() @ R2B.inverted()).to_4x4()
        bmesh.ops.transform(self.bm, matrix=m, verts=vs)
        i = self._col(h)
        for f in faces:
            f.material_index = i

    def finish(self, outline=True):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if outline:
            black = self._col("000000")
            bm.normal_update()
            acc = {}
            for v in bm.verts:
                k = tuple(round(c, 4) for c in v.co)
                acc[k] = acc.get(k, Vector()) + v.normal
            geom = bmesh.ops.duplicate(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:])["geom"]
            for v in geom:
                if isinstance(v, bmesh.types.BMVert):
                    n = acc.get(tuple(round(c, 4) for c in v.co), v.normal)
                    if n.length > 1e-6:
                        v.co += n.normalized() * OUTLINE
            shell = [f for f in geom if isinstance(f, bmesh.types.BMFace)]
            bmesh.ops.reverse_faces(bm, faces=shell)
            for f in shell:
                f.material_index = black
        old = bpy.data.objects.get(self.name)
        if old:
            bpy.data.objects.remove(old)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for h in self.cols:
            me.materials.append(material(h))
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        col = bpy.data.collections.get("ArmyKit") or bpy.data.collections.new("ArmyKit")
        if col.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(col)
        col.objects.link(ob)
        ob["roblox_part"] = self.name.split("_", 1)[1] if "_" in self.name else ""
        return ob


# ---------------------------------------------------------------- Soldier --------------------
def soldier():
    hx, hy, hz = R15["Head"]
    p = Piece("Soldier_Head")
    p.ball((hx * 1.22, hy * 1.0, hz * 1.26), (0, hy * 0.08, 0.03), OLIVE, cut=0.42)  # helmet dome
    p.cyl((hx * 1.3, hz * 1.34), 0.14, (0, hy * 0.06, 0.03), OLIVE_DARK, segs=20)  # brim band
    p.cyl((hx * 1.25, hz * 1.29), 0.11, (0, hy * 0.3, 0.03), BLACK, segs=20)  # goggle strap
    p.box((0.86, 0.26, 0.16), (0, hy * 0.32, -hz * 0.6), BLACK, bevel=0.06)  # goggle frame
    for x in (-0.2, 0.2):
        p.cyl(0.3, 0.1, (x, hy * 0.32, -hz * 0.69), LENS, axis="z", segs=14)
    p.box((0.28, 0.22, 0.12), (0, hy * 0.52, -hz * 0.6), GUNMETAL, bevel=0.04)  # NVG mount
    for x in (-1, 1):
        p.box((0.07, 0.14, hz * 0.6), (x * hx * 0.63, hy * 0.16, 0.03), BLACK, bevel=0.02)  # rail
        p.cyl(0.42, 0.18, (x * hx * 0.56, -hy * 0.06, 0.03), OLIVE_DARK, axis="x", segs=16, bevel=0.03)  # ear cup
        p.box((0.06, hy * 0.5, 0.06), (x * hx * 0.45, -hy * 0.28, -0.1), STRAP, bevel=0.0)  # chin strap
    p.finish()

    tx, ty, tz = R15["UpperTorso"]
    p = Piece("Soldier_UpperTorso")
    p.box((tx * 0.8, ty * 0.66, 0.3), (0, -ty * 0.06, -tz * 0.56), OLIVE_DARK, bevel=0.08)  # front plate
    p.box((tx * 0.8, ty * 0.66, 0.3), (0, -ty * 0.06, tz * 0.56), OLIVE_DARK, bevel=0.08)  # back plate
    p.box((tx * 1.08, ty * 0.3, tz * 1.16), (0, -ty * 0.26, 0), OLIVE_DEEP, bevel=0.1)  # cummerbund
    for x in (-0.24, 0.24):
        p.box((0.32, 0.14, tz * 1.18), (x * tx, ty * 0.34, 0), OLIVE_DEEP, bevel=0.05)  # shoulder straps
    for y in (-0.02, -0.12):
        p.box((tx * 0.74, 0.05, 0.05), (0, y * ty, -tz * 0.72), STRAP, bevel=0)  # webbing
    p.box((tx * 0.62, 0.18, tz * 1.02), (0, ty * 0.47, 0), OLIVE, bevel=0.07)  # collar
    for x in (-0.21, 0, 0.21):
        p.box((0.32, 0.42, 0.24), (x * tx, -ty * 0.3, -tz * 0.74), TAN, bevel=0.06)  # mag pouches
        p.box((0.34, 0.1, 0.26), (x * tx, -ty * 0.19, -tz * 0.75), KHAKI, bevel=0.03)
    p.box((tx * 0.38, 0.32, 0.14), (0, ty * 0.13, -tz * 0.66), OLIVE, bevel=0.05)  # admin pouch
    p.box((0.38, 0.22, 0.04), (0, ty * 0.14, -tz * 0.73), SAND, bevel=0)  # patch
    p.box((0.24, 0.52, 0.22), (tx * 0.36, ty * 0.05, -tz * 0.62), BLACK, bevel=0.05)  # radio
    p.cyl(0.05, 1.1, (tx * 0.39, ty * 0.42, -tz * 0.56), BLACK, segs=6)  # antenna
    p.ball((0.34, 0.38, 0.34), (-tx * 0.36, -ty * 0.14, -tz * 0.68), OLIVE_DEEP)  # grenade
    # pack: body, lid, side pockets, straps, bedroll
    p.box((tx * 0.68, ty * 0.62, 0.55), (0, -ty * 0.04, tz * 0.86), OLIVE, bevel=0.1)
    p.box((tx * 0.7, 0.26, 0.6), (0, ty * 0.27, tz * 0.87), OLIVE_DARK, bevel=0.08)
    for x in (-1, 1):
        p.box((0.22, ty * 0.32, 0.42), (x * tx * 0.41, -ty * 0.1, tz * 0.86), OLIVE_DARK, bevel=0.06)
        p.box((0.09, ty * 0.62, 0.05), (x * tx * 0.16, -ty * 0.04, tz * 1.1), STRAP, bevel=0)
    p.cyl(0.36, tx * 0.78, (0, ty * 0.43, tz * 0.88), TAN, axis="x", segs=14, bevel=0.04)
    p.finish()

    lx, ly, lz = R15["LowerTorso"]
    p = Piece("Soldier_LowerTorso")
    p.box((lx * 1.07, 0.24, lz * 1.12), (0, ly * 0.2, 0), BLACK, bevel=0.06)  # belt
    p.box((0.3, 0.22, 0.08), (0, ly * 0.2, -lz * 0.6), TAN, bevel=0.03)  # buckle
    p.box((0.26, 0.62, 0.36), (lx * 0.56, -ly * 0.2, 0), BLACK, bevel=0.06)  # holster
    p.box((0.16, 0.26, 0.22), (lx * 0.56, ly * 0.26, -0.05), GUNMETAL, bevel=0.04)  # grip
    p.box((0.36, 0.42, 0.36), (-lx * 0.52, -ly * 0.1, lz * 0.3), OLIVE_DARK, bevel=0.07)  # dump pouch
    p.finish()

    for side, sign in (("Left", -1), ("Right", 1)):
        ax, ay, az = R15["UpperArm"]
        p = Piece(f"Soldier_{side}UpperArm")
        p.box((0.05, 0.34, 0.34), (sign * ax * 0.53, ay * 0.15, 0), SAND, bevel=0.02)  # unit patch
        p.box((0.06, 0.12, 0.34), (sign * ax * 0.55, ay * 0.15, 0), OLIVE_DEEP, bevel=0)
        p.finish()
        bx, by, bz = R15["LowerArm"]
        p = Piece(f"Soldier_{side}LowerArm")
        p.ball((bx * 0.95, 0.38, 0.28), (0, by * 0.36, bz * 0.42), BLACK)  # elbow pad
        p.cyl((bx * 1.06, bz * 1.06), 0.12, (0, -by * 0.42, 0), OLIVE_DEEP, segs=14)  # cuff
        p.finish()
        ux, uy, uz = R15["UpperLeg"]
        p = Piece(f"Soldier_{side}UpperLeg")
        p.box((0.14, 0.5, 0.48), (sign * ux * 0.57, -uy * 0.08, 0), OLIVE, bevel=0.05)  # cargo pocket
        p.box((0.16, 0.1, 0.5), (sign * ux * 0.58, uy * 0.09, 0), OLIVE_DARK, bevel=0.02)
        p.finish()
        kx, ky, kz = R15["LowerLeg"]
        p = Piece(f"Soldier_{side}LowerLeg")
        p.ball((kx * 0.9, 0.46, 0.3), (0, ky * 0.33, -kz * 0.5), BLACK)  # knee pad
        p.cyl((kx * 1.08, kz * 1.08), 0.09, (0, ky * 0.33, 0), STRAP, segs=14)
        p.cyl((kx * 1.12, kz * 1.1), 0.26, (0, -ky * 0.4, 0), STRAP, segs=14, bevel=0.03)  # boot cuff
        p.finish()


# ---------------------------------------------------------------- Heavy ----------------------
def heavy():
    hx, hy, hz = R15["Head"]
    p = Piece("Heavy_Head")
    p.ball((hx * 1.32, hy * 1.12, hz * 1.36), (0, hy * 0.05, 0.03), CHARCOAL, cut=0.3)  # shell
    p.box((0.18, 0.16, hz * 1.1), (0, hy * 0.6, 0.03), PLATE_LIGHT, bevel=0.05)  # crest
    for x in (-1, 1):
        p.box((0.14, hy * 0.66, hz * 0.76), (x * hx * 0.62, -hy * 0.14, 0.06), PLATE, bevel=0.06)  # cheek
        p.ball((0.16, 0.16, 0.16), (x * hx * 0.66, hy * 0.1, 0.02), PLATE_LIGHT)  # bolt
    p.box((hx * 0.98, 0.44, 0.12), (0, hy * 0.04, -hz * 0.6), EDGE, bevel=0.04)  # visor frame
    p.box((hx * 0.86, 0.3, 0.08), (0, hy * 0.04, -hz * 0.66), VISOR, bevel=0.02)  # visor
    p.box((hx * 0.86, hy * 0.38, 0.28), (0, -hy * 0.31, -hz * 0.5), PLATE, bevel=0.07)  # jaw
    for x in (-0.24, 0.24):
        p.cyl(0.28, 0.18, (x, -hy * 0.34, -hz * 0.68), EDGE, axis="z", segs=14, bevel=0.03)  # filter
        p.cyl(0.18, 0.04, (x, -hy * 0.34, -hz * 0.78), PLATE_LIGHT, axis="z", segs=14)
    p.finish()

    tx, ty, tz = R15["UpperTorso"]
    p = Piece("Heavy_UpperTorso")
    p.box((tx * 1.18, ty * 0.92, tz * 1.42), (0, -ty * 0.02, 0), CHARCOAL, bevel=0.14)  # shell
    p.box((tx * 0.84, ty * 0.58, 0.2), (0, ty * 0.08, -tz * 0.76), PLATE, bevel=0.06)  # breastplate
    for x in (-0.36, 0.36):
        for y in (0.33, -0.17):
            p.ball((0.12, 0.12, 0.08), (x * tx, y * ty, -tz * 0.86), PLATE_LIGHT)  # rivets
    for y in (-0.3, -0.42):
        p.box((tx * 0.92, 0.17, tz * 1.44), (0, y * ty, 0), PLATE, bevel=0.06)  # belly bands
    p.cyl((tx * 0.72, tz * 1.22), 0.32, (0, ty * 0.5, 0), EDGE, segs=20, bevel=0.05)  # gorget
    p.box((tx * 0.72, ty * 0.64, 0.52), (0, 0, tz * 0.9), EDGE, bevel=0.1)  # power pack
    for x in (-0.18, 0.18):
        p.cyl(0.32, 0.52, (x * tx, ty * 0.16, tz * 1.12), PLATE, segs=14, bevel=0.04)
        p.cyl(0.24, 0.05, (x * tx, ty * 0.3, tz * 1.12), ORANGE, segs=14)  # vents (glow)
    p.finish()

    lx, ly, lz = R15["LowerTorso"]
    p = Piece("Heavy_LowerTorso")
    p.box((lx * 1.12, ly * 0.9, lz * 1.24), (0, ly * 0.05, 0), CHARCOAL, bevel=0.08)
    p.box((lx * 1.14, 0.13, lz * 1.26), (0, ly * 0.3, 0), PLATE, bevel=0.03)
    p.box((0.52, 0.44, 0.36), (lx * 0.55, -ly * 0.1, lz * 0.25), EDGE, bevel=0.06)  # ammo box
    p.wedge((lx * 0.38, ly * 1.1, 0.22), (0, -ly * 0.45, -lz * 0.6), PLATE, rot=(0, 180, 0))  # groin plate
    for x in (-0.36, 0.36):
        p.box((lx * 0.38, ly * 1.2, 0.16), (x * lx, -ly * 0.55, -lz * 0.58), PLATE, rot=(-8, 0, 0), bevel=0.04)  # tassets
    p.finish()

    for side, sign in (("Left", -1), ("Right", 1)):
        ax, ay, az = R15["UpperArm"]
        p = Piece(f"Heavy_{side}UpperArm")
        p.ball((ax * 2.0, ay * 0.62, az * 1.56), (sign * ax * 0.14, ay * 0.3, 0), PLATE, cut=0.25)  # pauldron
        for i, y in enumerate((0.12, -0.02)):
            p.box((ax * (1.8 - i * 0.2), 0.13, az * (1.38 - i * 0.1)), (sign * ax * 0.2, y * ay, 0), CHARCOAL, rot=(0, 0, sign * 18), bevel=0.04)
        p.box((ax * 1.24, ay * 0.4, az * 1.22), (0, -ay * 0.24, 0), CHARCOAL, bevel=0.06)
        p.finish()
        bx, by, bz = R15["LowerArm"]
        p = Piece(f"Heavy_{side}LowerArm")
        p.box((bx * 1.32, by * 0.74, bz * 1.32), (0, -by * 0.04, 0), CHARCOAL, bevel=0.08)
        p.box((bx * 1.38, 0.13, bz * 1.38), (0, by * 0.3, 0), PLATE, bevel=0.04)
        p.box((0.13, by * 0.6, 0.13), (sign * bx * 0.64, -by * 0.04, 0), PLATE_LIGHT, bevel=0.03)
        p.finish()
        nx, ny, nz = R15["Hand"]
        p = Piece(f"Heavy_{side}Hand")
        p.box((0.52, 0.28, 0.26), (0, -ny * 0.05, -nz * 0.3), PLATE, bevel=0.05)  # knuckles
        p.finish()
        ux, uy, uz = R15["UpperLeg"]
        p = Piece(f"Heavy_{side}UpperLeg")
        p.box((ux * 1.2, uy * 0.62, 0.24), (0, -uy * 0.08, -uz * 0.56), PLATE, bevel=0.06)
        p.box((0.2, uy * 0.56, uz * 0.82), (sign * ux * 0.58, -uy * 0.08, 0), CHARCOAL, bevel=0.05)
        p.finish()
        kx, ky, kz = R15["LowerLeg"]
        p = Piece(f"Heavy_{side}LowerLeg")
        p.ball((kx * 1.08, 0.52, 0.44), (0, ky * 0.38, -kz * 0.46), PLATE_LIGHT)  # knee cop
        p.box((kx * 1.18, ky * 0.64, 0.26), (0, -ky * 0.08, -kz * 0.56), CHARCOAL, bevel=0.07)
        p.box((0.13, ky * 0.6, 0.09), (0, -ky * 0.08, -kz * 0.72), PLATE, bevel=0.02)
        p.finish()
        fx, fy, fz = R15["Foot"]
        p = Piece(f"Heavy_{side}Foot")
        p.box((fx * 1.12, fy * 0.62, fz * 1.1), (0, fy * 0.1, 0), CHARCOAL, bevel=0.1)
        p.box((fx * 1.14, 0.12, 0.32), (0, fy * 0.02, -fz * 0.47), PLATE, bevel=0.03)
        p.finish()


# ---------------------------------------------------------------- Helicopter -----------------
ROTOR_PIVOT = (0, 5.35, 0)  # main rotor centre, Body space (Helicopter.luau)
TAIL_PIVOT = (0.55, 3.8, 18.0)


def helicopter():
    p = Piece("Heli_Body")
    # fuselage: cabin, roof, belly, round nose, tinted canopy and chin windows, frame
    p.box((6.2, 4.4, 8), (0, 0, 0), HELI, bevel=0.5)
    p.box((5.6, 0.7, 8.2), (0, 2.4, 0), HELI, bevel=0.3)
    p.box((5.6, 0.9, 9.4), (0, -2.45, -0.4), HELI_DARK, bevel=0.3)
    p.ball((6, 4.4, 6.6), (0, -0.2, -4.4), HELI, segs=24, rings=14)
    p.ball((5.3, 3.5, 5.6), (0, 0.8, -5.0), GLASS, segs=24, rings=14)
    p.ball((3.6, 1.6, 3), (0, -1.4, -6.3), GLASS, segs=20, rings=10)
    p.box((0.24, 0.24, 4.6), (0, 2.15, -5), HELI_DARK, rot=(-24, 0, 0), bevel=0.05)
    for x in (-1, 1):
        p.box((0.22, 3.4, 0.22), (x * 2.05, 0.9, -6.3), HELI_DARK, rot=(-30, 0, x * -18), bevel=0.05)
        p.box((0.14, 1.3, 1.9), (x * 3.12, 1.0, -2.7), GLASS, bevel=0.06)  # side window
        p.box((0.12, 3.2, 3.6), (x * 3.08, -0.2, 1.4), "141614", bevel=0)  # open bay
        p.box((0.24, 0.18, 7.6), (x * 3.2, 1.55, 3), HELI_DARK, bevel=0.05)  # rails
        p.box((0.24, 0.18, 7.6), (x * 3.2, -1.95, 3), HELI_DARK, bevel=0.05)
        p.box((0.16, 3.3, 3.5), (x * 3.3, -0.2, 4.6), HELI, bevel=0.12)  # slid-back door
        p.box((0.18, 1.1, 1.4), (x * 3.32, 0.7, 4.6), GLASS, bevel=0.06)
        p.box((0.9, 0.14, 2.2), (x * 3.4, -2.7, 1.4), HELI_DARK, bevel=0.04)  # step
        p.box((0.14, 0.5, 3.4), (x * 3.13, 1.9, -1.6), HELI_STRIPE, bevel=0.02)  # stripe
        # skids: tube, upturned front, struts
        p.cyl(0.44, 12, (x * 2.8, -4.5, -0.2), HELI_DARK, axis="z", segs=12)
        p.cyl(0.44, 2.2, (x * 2.8, -4.0, -6.8), HELI_DARK, axis="z", rot=(35, 0, 0), segs=12)
        for z in (-3.2, 2.6):
            p.box((0.36, 1.9, 0.36), (x * 2.55, -3.6, z), HELI_DARK, rot=(0, 0, x * -14), bevel=0.06)
        p.ball((0.36, 0.36, 0.36), (x * 3.12, -1.7, -3.4), RED if x < 0 else GREEN)  # nav light
    # crew behind the canopy
    for x in (-1.2, 1.2):
        p.box((1.1, 1.8, 0.3), (x, 0.4, -3.6), HELI_DARK, bevel=0.08)
        p.box((1.1, 1.3, 0.8), (x, 0.1, -4.1), OLIVE, bevel=0.15)
        p.ball((0.85, 0.85, 0.85), (x, 1.15, -4.2), SKIN)
        p.ball((0.98, 0.8, 1.02), (x, 1.3, -4.18), OLIVE_DARK, cut=0.4)
        p.box((0.7, 0.24, 0.1), (x, 1.22, -4.62), BLACK, bevel=0.03)
    p.box((4.2, 0.9, 0.6), (0, 0.2, -5.6), HELI_DARK, rot=(-25, 0, 0), bevel=0.1)  # instrument panel
    # engine: housing, cowl, intakes, exhausts, grilles, beacon, antennas
    p.box((3.6, 1.5, 6.2), (0, 3.4, 0.8), HELI, bevel=0.35)
    p.ball((3.6, 1.5, 2.4), (0, 3.4, -2.3), HELI)
    for x in (-1, 1):
        p.cyl(0.9, 0.5, (x * 1.1, 3.4, -2.6), "141614", axis="z", segs=14, bevel=0.05)
        p.cyl(0.75, 1.6, (x * 1.3, 3.6, 3.8), HELI_DARK, rot=(70, 0, x * -25), segs=12, bevel=0.05)
        for i in range(3):
            p.box((0.06, 0.08, 2.6), (x * 1.82, 3.0 + i * 0.3, 1.2), HELI_DARK, bevel=0)
    p.ball((0.42, 0.42, 0.42), (0, 4.25, 3.4), RED)
    p.cyl(0.07, 1.4, (0.8, -3.4, 1.8), HELI_DARK, segs=6)
    p.cyl(0.07, 1.2, (-0.6, 3.1, -3.2), HELI_DARK, rot=(-30, 0, 0), segs=6)
    # searchlight and its lens
    p.cyl(0.9, 0.7, (1.4, -2.9, -5.2), HELI_DARK, axis="z", rot=(-55, 0, 0), segs=14, bevel=0.06)
    p.cyl(0.7, 0.08, (1.4, -3.15, -5.55), "FFF6D0", axis="z", rot=(-55, 0, 0), segs=14)
    # door gun, port side
    p.box((0.32, 1.6, 0.32), (-3.7, -0.9, 0.6), HELI_DARK, bevel=0.05)
    p.box((0.5, 0.5, 1.4), (-3.7, 0, 0.6), GUNMETAL, rot=(0, -35, 0), bevel=0.08)
    p.box((0.5, 0.5, 0.6), (-3.35, -0.1, 0.85), OLIVE, rot=(0, -35, 0), bevel=0.06)
    p.cyl(0.32, 1.9, (-3.7 + math.sin(math.radians(35)) * 1.5, 0, 0.6 - math.cos(math.radians(35)) * 1.5), BLACK, axis="z", rot=(0, -35, 0), segs=10)
    # tail: stepped boom, shaft cover, fin, stabiliser, end plates, tail light, skid
    p.box((2.2, 2.0, 5), (0, 1.0, 6.4), HELI, bevel=0.3)
    p.box((1.6, 1.5, 5), (0, 1.2, 11.2), HELI, bevel=0.25)
    p.box((1.1, 1.1, 4), (0, 1.4, 15.4), HELI, bevel=0.2)
    p.box((0.6, 0.4, 13), (0, 2.15, 10.4), HELI_DARK, bevel=0.1)
    for x in (-1, 1):  # boom star roundels
        p.cyl(1.3, 0.06, (x * 1.12, 1.0, 6.6), WHITE, axis="x", segs=20)
        p.star(0.42, 0.08, (x * 1.14, 1.0, 6.6), HELI_DARK)
    p.wedge((0.42, 4.4, 3.2), (0, 3.6, 17.2), HELI)
    p.box((5.2, 0.32, 1.6), (0, 1.4, 15.0), HELI, bevel=0.1)
    for x in (-1, 1):
        p.box((0.22, 1.2, 1.4), (x * 2.6, 1.4, 15.0), HELI, bevel=0.06)
    p.ball((0.32, 0.32, 0.32), (0, 1.4, 17.5), WHITE)
    p.box((0.22, 1.4, 0.22), (0, 0.3, 16.6), HELI_DARK, rot=(30, 0, 0), bevel=0.04)
    p.cyl(0.62, 1.4, (0, 4.6, 0), HELI_DARK, segs=12)  # mast
    p.finish()

    p = Piece("Heli_Rotor")  # centred on ROTOR_PIVOT
    p.cyl(1.7, 0.45, (0, 0, 0), HELI_DARK, segs=16, bevel=0.08)
    p.ball((0.8, 0.55, 0.8), (0, 0.32, 0), HELI_DARK)
    for i in range(4):
        a = i * 90
        rad = math.radians(a)
        c, s = math.cos(rad), -math.sin(rad)
        p.box((1.3, 0.34, 0.56), (c * 1.2, 0, s * 1.2), HELI_DARK, rot=(0, a, 0), bevel=0.06)
        p.box((13.4, 0.16, 1.0), (c * 8.5, 0.02, s * 8.5), "22251E", rot=(0, a, 0), bevel=0.05)
        p.box((0.9, 0.17, 1.02), (c * 15.6, 0.02, s * 15.6), YELLOW, rot=(0, a, 0), bevel=0.04)
    p.finish()

    p = Piece("Heli_TailRotor")  # centred on TAIL_PIVOT, turns about X
    p.cyl(0.5, 0.5, (0, 0, 0), HELI_DARK, axis="x", segs=12, bevel=0.05)
    for i in range(3):
        a = i * 120
        rad = math.radians(a)
        p.box((0.1, 2.3, 0.42), (0.05, math.cos(rad) * 1.2, math.sin(rad) * 1.2), "22251E", rot=(a, 0, 0), bevel=0.03)
        p.box((0.11, 0.3, 0.43), (0.05, math.cos(rad) * 2.3, math.sin(rad) * 2.3), YELLOW, rot=(a, 0, 0), bevel=0.02)
    p.finish()


# ---------------------------------------------------------------- Baton ----------------------
def baton():
    """Side-handle nightstick, along +Y from the grip (the origin), like the Bat."""
    p = Piece("Baton")
    p.cyl(0.24, 0.12, (0, -0.52, 0), "9EA2AC", segs=18, bevel=0.03)  # butt cap
    for i in range(6):  # ribbed grip
        p.cyl(0.21, 0.07, (0, -0.4 + i * 0.125, 0), "34343A", segs=18)
        p.cyl(0.195, 0.06, (0, -0.34 + i * 0.125, 0), "2A2A30", segs=18)
    p.cyl(0.23, 0.1, (0, 0.38, 0), "9EA2AC", segs=18, bevel=0.02)  # collar
    p.cyl(0.18, 1.6, (0, 1.2, 0), "17171C", segs=18, d2=0.165)  # shaft
    p.cyl(0.19, 0.08, (0, 1.98, 0), "9EA2AC", segs=18)  # ring
    p.cyl(0.17, 0.2, (0, 2.12, 0), "17171C", segs=18)
    p.ball((0.17, 0.2, 0.17), (0, 2.24, 0), "9EA2AC")  # tip
    p.cyl(0.2, 0.06, (0, 0.55, 0.06), "9EA2AC", axis="z", segs=14)  # side handle collar
    for i in range(4):
        p.cyl(0.15, 0.06, (0, 0.55, 0.13 + i * 0.075), "34343A", axis="z", segs=14)
        p.cyl(0.14, 0.02, (0, 0.55, 0.165 + i * 0.075), "2A2A30", axis="z", segs=14)
    p.cyl(0.18, 0.08, (0, 0.55, 0.46), "9EA2AC", axis="z", segs=14, bevel=0.02)  # knob
    p.ring(0.19, 0.035, (0, -0.78, 0), "7A5434", rot=(0, 90, 0))  # leather wrist strap, a loop under the butt
    p.finish()


def build_all():
    for ob in list(bpy.data.objects):
        if ob.name in ("Cube",) or ob.name.startswith(("Soldier_", "Heavy_", "Heli_", "Baton")):
            bpy.data.objects.remove(ob)
    soldier()
    heavy()
    helicopter()
    baton()
    # lay them out for a look (object origins stay at the attach point; only the display moves)
    x = 0
    for prefix in ("Soldier_", "Heavy_"):
        for ob in bpy.data.objects:
            if ob.name.startswith(prefix):
                part = ob.name[len(prefix):]
                ob.location = Vector((x, 0, 0)) + R2B @ Vector(RIG.get(part, (0, 0, 0)))
        x -= 4
    bpy.data.objects["Heli_Body"].location = (12, 0, 4)
    bpy.data.objects["Heli_Rotor"].location = Vector((12, 0, 4)) + R2B @ Vector(ROTOR_PIVOT)
    bpy.data.objects["Heli_TailRotor"].location = Vector((12, 0, 4)) + R2B @ Vector(TAIL_PIVOT)
    bpy.data.objects["Baton"].location = (4, 0, 0.5)


# where each body part sits on the standing dummy, relative to the UpperTorso (measured), for the layout only
RIG = {
    "Head": (0, 1.48, 0.04), "UpperTorso": (0, 0, 0), "LowerTorso": (0, -0.83, -0.06),
    "LeftUpperArm": (-1.19, 0.18, 0.06), "RightUpperArm": (1.19, 0.18, 0.06),
    "LeftLowerArm": (-1.31, -0.39, 0.15), "RightLowerArm": (1.31, -0.39, 0.15),
    "LeftHand": (-1.38, -1.09, 0.05), "RightHand": (1.38, -1.09, 0.05),
    "LeftUpperLeg": (-0.42, -1.53, -0.01), "RightUpperLeg": (0.42, -1.53, -0.01),
    "LeftLowerLeg": (-0.45, -2.43, 0.09), "RightLowerLeg": (0.45, -2.43, 0.09),
    "LeftFoot": (-0.45, -2.8, -0.1), "RightFoot": (0.45, -2.8, -0.1),
}

if __name__ == "__main__" or True:
    build_all()
    if REPO:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(REPO, "assets", "army", "army.blend"))
    print("built", len([o for o in bpy.data.objects if o.name.startswith(("Soldier_", "Heavy_", "Heli_", "Baton"))]), "pieces")
