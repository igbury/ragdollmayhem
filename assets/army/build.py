# The army kit for Wanted (soldier and heavy uniforms, the helicopter, the police baton) plus the factory worker and zombie outfits, modelled in
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

    def __init__(self, name, exact=False, fit=None, outline=OUTLINE):
        self.name = name
        self.fit = fit  # (body part, "box" | "round"): see fit_to_body
        self.refs = [(0, fit[1])] if fit else []
        self.outline = outline  # studs the black shell sits off the surface
        # exact: bevelled shapes keep their colour on every face. Off for the pieces made before it
        # existed: there bevel's shrunk big faces fell back to the piece's first colour, and that is
        # how they look in the game (the police car is exact).
        self.exact = exact
        self.bm = bmesh.new()
        self.cols = []  # material order
        self.layer = None

    def ref(self, ref):
        """The shapes made after this fit to the body against `ref` (see fit_to_body)."""
        self.refs.append((len(self.bm.verts), ref))

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
            faces, vs = self._bevel(edges, b)
        self._place(vs, faces, at, rot, h)

    def _bevel(self, edges, offset, clamp=False):
        """Rounds `edges`; returns the faces and vertices of their shape afterwards (see `exact`)."""
        shape = {f for e in edges for f in e.link_faces}
        others = set(self.bm.faces) - shape  # untouched by the bevel: everything else is this shape now
        out = bmesh.ops.bevel(self.bm, geom=edges, offset=offset, segments=2, profile=0.5, affect="EDGES", clamp_overlap=clamp)
        if self.exact:
            faces = [f for f in self.bm.faces if f not in others]
        else:
            faces = [f for f in shape | set(out["faces"]) if f.is_valid]
        return faces, list({v for f in faces for v in f.verts})

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
            faces, vs = self._bevel(caps, bevel)
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

    def prism(self, profile, width, at, h, bevel=0.1):
        """A side profile (Roblox (z, y) points, in order round the outline) pushed `width` studs
        across X, centred `at`. Corners sharper than 25 degrees get rounded by `bevel` studs."""
        sides = [[self.bm.verts.new(R2B @ Vector((x, y, z))) for z, y in profile] for x in (-width / 2, width / 2)]
        n = len(profile)
        faces = [self.bm.faces.new(sides[0]), self.bm.faces.new(sides[1][::-1])]
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((sides[0][i], sides[1][i], sides[1][j], sides[0][j])))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        vs = sides[0] + sides[1]
        if bevel > 0:
            self.bm.normal_update()
            edges = [e for e in {e for f in faces for e in f.edges} if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(25)]
            faces, vs = self._bevel(edges, bevel, clamp=True)
        self._place(vs, faces, at, (0, 0, 0), h)

    def slab(self, outline, y0, y1, at, h, bevel=0.1):
        """A top-view outline (Roblox (x, z) points, in order round it) pushed up from y0 to y1,
        placed `at`. Corners sharper than 25 degrees get rounded by `bevel` studs."""
        sides = [[self.bm.verts.new(R2B @ Vector((x, y, z))) for x, z in outline] for y in (y0, y1)]
        n = len(outline)
        faces = [self.bm.faces.new(sides[0]), self.bm.faces.new(sides[1][::-1])]
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((sides[0][i], sides[1][i], sides[1][j], sides[0][j])))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        vs = sides[0] + sides[1]
        if bevel > 0:
            self.bm.normal_update()
            edges = [e for e in {e for f in faces for e in f.edges} if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(25)]
            faces, vs = self._bevel(edges, bevel, clamp=True)
        self._place(vs, faces, at, (0, 0, 0), h)

    def text(self, s, width, depth, at, h, side):
        """Raised lettering `width` studs long on a car side: `side` +1 faces +X, -1 faces -X; it reads
        front to back on either side, as a viewer standing there sees it."""
        font = None
        for f in ("ariblk.ttf", "impact.ttf", "arialbd.ttf"):
            path = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", f)
            if os.path.exists(path):
                font = bpy.data.fonts.load(path, check_existing=True)
                break
        cu = bpy.data.curves.new("_txt", "FONT")
        cu.body, cu.align_x, cu.align_y, cu.extrude, cu.resolution_u = s, "CENTER", "CENTER", depth / 2, 3
        if font:
            cu.font = font
        ob = bpy.data.objects.new("_txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        xs = [v.co.x for v in me.vertices]
        k = width / (max(xs) - min(xs))
        # text (u along, v up, w out of the page) -> Roblox: on +X it reads toward -Z, on -X toward +Z
        vmap = [self.bm.verts.new(R2B @ (Vector(at) + Vector((side * v.co.z, v.co.y * k, -side * v.co.x * k)))) for v in me.vertices]
        faces = [self.bm.faces.new([vmap[i] for i in p.vertices]) for p in me.polygons]
        ob.to_mesh_clear()
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        i = self._col(h)
        for f in faces:
            f.material_index = i

    def finish(self, outline=True):
        bm = self.bm
        if self.fit:
            fit_to_body(bm, self.fit[0], self.refs)
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
                        v.co += n.normalized() * self.outline
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


# ---------------------------------------------------------------- Worker ---------------------
HAT, HAT_DARK = "FFC21A", "D99A0A"
VEST, VEST_DARK, REFLECT = "FF7A1A", "D0600E", "D8DCE0"
LEATHER, LEATHER_DARK, GLOVE, WOOD, STEEL = "7A5230", "5A3A20", "C9A060", "B07A44", "8A9098"
COLLAR, POCKET, MUFF = "2E4A74", "24364F", "E03A2A"
PAPER = "F4F4F0"  # not WHITE: that one is Neon (the helicopter's lights)


def worker():
    hx, hy, hz = R15["Head"]
    p = Piece("Worker_Head")
    p.ball((hx * 1.16, hy * 1.0, hz * 1.2), (0, hy * 0.1, 0.02), HAT, cut=0.42)  # hard hat
    p.ball((0.22, hy * 1.08, hz * 1.28), (0, hy * 0.1, 0.02), HAT_DARK, cut=0.42)  # ridge
    p.cyl((hx * 1.3, hz * 1.36), 0.08, (0, hy * 0.08, 0.0), HAT, segs=22)  # brim
    p.box((hx * 0.8, 0.08, 0.34), (0, hy * 0.08, -hz * 0.72), HAT, bevel=0.03)  # peak
    p.box((0.3, 0.26, 0.04), (0, hy * 0.36, -hz * 0.53), PAPER, rot=(30, 0, 0), bevel=0)  # safety sticker
    p.box((0.2, 0.06, 0.05), (0, hy * 0.36, -hz * 0.55), "2FA84A", rot=(30, 0, 0), bevel=0)
    p.box((0.06, 0.2, 0.05), (0, hy * 0.36, -hz * 0.55), "2FA84A", rot=(30, 0, 0), bevel=0)
    p.cyl((hx * 1.2, hz * 1.24), 0.1, (0, hy * 0.2, 0.02), BLACK, segs=20)  # goggle strap
    p.box((0.86, 0.24, 0.14), (0, hy * 0.22, -hz * 0.62), BLACK, bevel=0.06)  # goggles up on the hat
    p.box((0.74, 0.16, 0.06), (0, hy * 0.22, -hz * 0.7), GLASS, bevel=0.02)
    for x in (-1, 1):
        p.cyl(0.44, 0.18, (x * hx * 0.56, -hy * 0.06, 0.02), MUFF, axis="x", segs=16, bevel=0.04)  # ear muffs
        p.cyl(0.3, 0.06, (x * hx * 0.65, -hy * 0.06, 0.02), BLACK, axis="x", segs=14)
    p.finish()

    tx, ty, tz = R15["UpperTorso"]
    p = Piece("Worker_UpperTorso")
    for x in (-1, 1):
        p.box((tx * 0.46, ty * 0.78, 0.14), (x * tx * 0.26, -ty * 0.04, -tz * 0.53), VEST, bevel=0.05)  # front halves
        p.box((0.14, ty * 0.5, tz * 1.0), (x * tx * 0.52, -ty * 0.18, 0), VEST, bevel=0.04)  # sides
        p.box((0.36, 0.14, tz * 1.2), (x * tx * 0.26, ty * 0.45, 0), VEST, bevel=0.04)  # shoulder straps
        p.box((0.12, 0.16, tz * 1.22), (x * tx * 0.26, ty * 0.45, 0), REFLECT, bevel=0)
        for y in (0.08, -0.24):
            p.box((tx * 0.42, 0.12, 0.04), (x * tx * 0.26, y * ty, -tz * 0.61), REFLECT, bevel=0)
    p.box((tx * 0.94, ty * 0.78, 0.14), (0, -ty * 0.04, tz * 0.53), VEST, bevel=0.05)  # back panel
    for y in (0.08, -0.24):
        p.box((tx * 0.9, 0.12, 0.04), (0, y * ty, tz * 0.61), REFLECT, bevel=0)
    p.box((0.05, ty * 0.72, 0.04), (0, -ty * 0.04, -tz * 0.6), "2A2A30", bevel=0)  # zip
    p.box((0.28, 0.36, 0.04), (-tx * 0.26, ty * 0.27, -tz * 0.62), PAPER, bevel=0.02)  # ID badge
    p.box((0.14, 0.14, 0.05), (-tx * 0.26, ty * 0.3, -tz * 0.63), "5AB4E0", bevel=0)
    p.box((0.3, 0.3, 0.05), (tx * 0.26, ty * 0.26, -tz * 0.62), VEST_DARK, bevel=0.02)  # pen pocket
    p.cyl(0.06, 0.24, (tx * 0.3, ty * 0.36, -tz * 0.63), "2A5AC0", segs=8)
    p.box((tx * 0.6, 0.16, tz * 0.98), (0, ty * 0.47, 0), COLLAR, bevel=0.06)  # shirt collar
    p.finish()

    lx, ly, lz = R15["LowerTorso"]
    p = Piece("Worker_LowerTorso")
    p.box((lx * 1.08, 0.22, lz * 1.12), (0, ly * 0.18, 0), LEATHER, bevel=0.06)  # tool belt
    p.box((0.28, 0.2, 0.08), (0, ly * 0.18, -lz * 0.6), STEEL, bevel=0.03)  # buckle
    for x in (-1, 1):
        p.box((0.4, 0.46, 0.3), (x * lx * 0.4, -ly * 0.3, -lz * 0.5), LEATHER_DARK, bevel=0.06)  # pouches
    p.cyl(0.11, 0.9, (lx * 0.6, -0.22, 0), WOOD, segs=10)  # hammer in its loop
    p.box((0.16, 0.16, 0.5), (lx * 0.6, ly * 0.52, 0), STEEL, bevel=0.04)
    p.box((0.16, 0.3, 0.3), (-lx * 0.58, -ly * 0.05, 0), HAT, bevel=0.05)  # tape measure
    p.cyl(0.14, 0.04, (-lx * 0.58 - 0.09, -ly * 0.05, 0), BLACK, axis="x", segs=12)
    p.finish()

    for side, sign in (("Left", -1), ("Right", 1)):
        ax, ay, az = R15["UpperArm"]
        p = Piece(f"Worker_{side}UpperArm")
        p.cyl((ax * 1.08, az * 1.06), 0.14, (0, ay * 0.1, 0), REFLECT, segs=14)  # reflective band
        p.finish()
        bx, by, bz = R15["LowerArm"]
        p = Piece(f"Worker_{side}LowerArm")
        p.cyl((bx * 1.12, bz * 1.12), 0.34, (0, -by * 0.36, 0), GLOVE, segs=14, d2=bx * 1.2, bevel=0.03)  # glove cuff
        p.cyl((bx * 1.22, bz * 1.22), 0.07, (0, -by * 0.2, 0), LEATHER, segs=14)
        p.finish()
        ux, uy, uz = R15["UpperLeg"]
        p = Piece(f"Worker_{side}UpperLeg")
        p.box((0.12, 0.5, 0.46), (sign * ux * 0.56, -uy * 0.06, 0), POCKET, bevel=0.04)  # side pocket
        p.finish()
        kx, ky, kz = R15["LowerLeg"]
        p = Piece(f"Worker_{side}LowerLeg")
        p.cyl((kx * 1.1, kz * 1.1), 0.32, (0, -ky * 0.38, 0), LEATHER_DARK, segs=14, bevel=0.03)  # boot tops
        p.finish()
        fx, fy, fz = R15["Foot"]
        p = Piece(f"Worker_{side}Foot")
        p.box((fx * 1.1, fy * 0.62, fz * 1.08), (0, fy * 0.1, 0), LEATHER, bevel=0.12)  # boot
        p.ball((fx * 1.04, fy * 0.9, 0.56), (0, -fy * 0.2, -fz * 0.42), STEEL, cut=0.5)  # steel toe
        p.box((fx * 1.14, 0.12, fz * 1.12), (0, -fy * 0.22, 0), BLACK, bevel=0.04)  # sole
        p.finish()


# ---------------------------------------------------------------- the real body ---------------
# The R15 sizes are boxes, the dummies are not: the torso tapers, limbs are rounded, the head is a
# cylinder. A piece made with fit=(part, ref) is laid out against the box (or the round shape inside
# it) and then every vertex is moved along a ray from the part's core so that its height over the
# reference becomes its height over the real body (dummy_body.obj): plates lie on the curve
# instead of floating off the corners or sinking in. ref "box": shapes placed on the box's faces;
# "round": shapes wrapped round the part (sleeves, wraps, a cylinder head's hair).
_BODY = {}
FIT_EDGE = 0.2  # studs: longer edges are cut before a piece is fitted


def _head_mesh(sx, sy, sz, rc=0.24, segs=28):
    """The classic head: a cylinder with rounded rims (SpecialMesh Head, Scale 1, 1, 0.877)."""
    prof = [(0.0, -0.5)]
    for k in range(7):  # bottom rim, then top rim (r, y in units of the size)
        a = -math.pi / 2 + k * math.pi / 12
        prof.append((0.5 - rc + rc * math.cos(a), -0.5 + rc + rc * math.sin(a)))
    for k in range(7):
        a = k * math.pi / 12
        prof.append((0.5 - rc + rc * math.cos(a), 0.5 - rc + rc * math.sin(a)))
    prof.append((0.0, 0.5))
    vs, fs = [], []
    for r, y in prof:
        for i in range(segs):
            t = 2 * math.pi * i / segs
            vs.append(Vector((math.cos(t) * r * sx, y * sy, math.sin(t) * r * sz)))
    for j in range(len(prof) - 1):
        for i in range(segs):
            a, b = j * segs + i, j * segs + (i + 1) % segs
            fs += [(a, b, b + segs), (a, b + segs, a + segs)]
    return vs, fs


def _body(part):
    from mathutils.bvhtree import BVHTree
    if not _BODY:
        path = os.path.join(REPO, "assets", "army", "dummy_body.obj") if REPO else bpy.path.abspath("//dummy_body.obj")
        raw, name = {}, None
        for line in open(path, encoding="utf-8"):
            t = line.split()
            if not t or t[0] == "#":
                continue
            if t[0] == "o":
                name = t[1]
                raw[name] = (Vector([float(x) for x in t[2:5]]), [], [])
            elif t[0] == "v":
                raw[name][1].append(Vector([float(x) for x in t[1:4]]))
            elif t[0] == "f":
                raw[name][2].append(tuple(int(i) - 1 for i in t[1:4]))
        for name, (size, vs, fs) in raw.items():
            lo = Vector([min(v[i] for v in vs) for i in range(3)])
            hi = Vector([max(v[i] for v in vs) for i in range(3)])
            mid = (lo + hi) / 2
            vs = [v - mid for v in vs]
            _BODY[name] = (size, vs, fs, BVHTree.FromPolygons(vs, fs))
        hx, hy, hz = R15["Head"]
        vs, fs = _head_mesh(hx, hy, hz * 0.877)
        _BODY["Head"] = (Vector((hx, hy, hz * 0.877)), vs, fs, BVHTree.FromPolygons(vs, fs))
    return _BODY[part]


def fit_to_body(bm, part, refs):
    """refs: (first vertex, ref) in making order: Piece.ref() switches it for the shapes after."""
    size = Vector(R15[part] if part in R15 else R15[part.replace("Left", "").replace("Right", "")])
    _, _, _, tree = _body(part)
    H = size / 2
    a = 2 if "Foot" in part else 1  # the axis things wrap round (up, a foot's along it); the core is a segment on it
    core = max(0.0, H[a] - min(H[i] for i in range(3) if i != a))
    # a flat face only bends where it has vertices: cut the long edges first (each shape keeps its ref)
    tag = bm.verts.layers.int.new("fit_ref")
    names = sorted({rf for _, rf in refs})
    for k, v in enumerate(bm.verts):
        v[tag] = names.index(next(rf for start, rf in reversed(refs) if k >= start))
    for _ in range(4):
        long = [e for e in bm.edges if e.calc_length() > FIT_EDGE]
        if not long:
            break
        bmesh.ops.subdivide_edges(bm, edges=long, cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])  # bent quads would not stay flat
    for v in bm.verts:
        ref = names[v[tag]]
        r = R2B @ v.co  # R2B is its own inverse
        c = Vector((0, 0, 0))
        c[a] = max(-core, min(core, r[a]))
        d = r - c
        L = d.length
        if L < 1e-5:
            continue
        n = d / L
        if ref == "box":
            rref = min(((H[i] if n[i] > 0 else -H[i]) - c[i]) / n[i] for i in range(3) if abs(n[i]) > 1e-9)
        else:  # an elliptic cylinder along the long axis, its ends the box's
            cross = math.sqrt(sum((n[i] / H[i]) ** 2 for i in range(3) if i != a))
            rref = 1 / cross if cross > 1e-9 else math.inf
            if abs(n[a]) > 1e-9:
                rref = min(rref, ((H[a] if n[a] > 0 else -H[a]) - c[a]) / n[a])
        # the outer surface: the last hit along the ray (the core can sit outside a hollow shape)
        far, start = None, c.copy()
        for _ in range(8):
            hit = tree.ray_cast(start, n)
            if hit[0] is None:
                break
            far = (hit[0] - c).length
            start = hit[0] + n * 1e-4
        if far is None:
            continue
        v.co = R2B @ (c + n * (L - rref + far))


# ---------------------------------------------------------------- Zombie ---------------------
# The kind's body colours do most of it (main script KINDS: grey shirt torso, green arms and head,
# blue trousers); the kit tears them up: thinning hair, a stitched scar, a shirt in holes with the
# bony chest showing through, sleeves and trouser legs torn off, a loose bandage, one shoe left.
# Kept safe for uploads (no gore): nothing red, no wounds, no bone through skin; the ribs are bumps
# in the green skin, bruises purple and yellow.
ZSKIN, ZSKIN_DARK, ZSKIN_DEEP = "7FA05A", "5E7E40", "4A6630"
# In the game's sun a flat colour washes out and two close ones melt together, so every rag is a
# clear step darker than the dirty shirt it hangs off (KINDS.Zombie torso 9C9580) and the dirt is mud.
RAG, RAG_DARK, DIRT, TROUSER, PATCH, HAIR = "6A604C", "4A4436", "5C4E3A", "2E3446", "5A6680", "2A2620"
TIE, BANDAGE, ROPE, SHOE, SOLE, THREAD = "4A3A6A", "D8D2C0", "7C6C48", "5A4030", "2A2420", "2A2A24"
BRUISE, BRUISE_OLD = "6E5C80", "A0A862"
ZOUT = 0.045  # the zombie's black outline: thick enough to still read at the distance it is seen from


def _noise(i, seed):
    """A repeatable 0..1 jitter (no random module: the kit builds the same every time)."""
    return (math.sin(i * 12.9898 + seed * 78.233) * 43758.5453) % 1.0


def jagged(w, h, n, seed, amp=0.28):
    """A torn outline: n points round a w x h ellipse at uneven angles, every other one pulled in by
    up to `amp` (notches), the rest wobbling a little: no two edges alike."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * (i + 0.7 * (_noise(i, seed + 7) - 0.5)) / n
        r = 1 - (amp * (0.3 + 0.7 * _noise(i, seed)) if i % 2 else 0.2 * _noise(i, seed + 3))
        pts.append((math.cos(a) * w / 2 * r, math.sin(a) * h / 2 * r))
    return pts


def strip(w, length, seed):
    """A hanging shred: `w` wide at the top (y 0), torn to points `length` below."""
    j = lambda i: 0.75 + 0.25 * _noise(i, seed)
    return [(-w / 2, 0), (w / 2, 0), (w * 0.38, -length * 0.62 * j(1)), (w * 0.12, -length * j(2)),
            (-w * 0.1, -length * 0.7 * j(3)), (-w * 0.32, -length * 0.92 * j(4))]


FACES = {  # face -> (u axis, v axis, outward normal), Roblox part space
    "-z": ((1, 0, 0), (0, 1, 0), (0, 0, -1)), "+z": ((-1, 0, 0), (0, 1, 0), (0, 0, 1)),
    "-x": ((0, 0, 1), (0, 1, 0), (-1, 0, 0)), "+x": ((0, 0, -1), (0, 1, 0), (1, 0, 0)),
    "+y": ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
}


def plate(p, pts, at, face, depth, h, tilt=0.0):
    """A flat piece of outline `pts` ((u, v) on that face) `depth` thick, centred `at`, lying on
    `face` of the part; `tilt` degrees leans its bottom edge out from the surface (a flap)."""
    u, v, n = (Vector(a) for a in FACES[face])
    t = math.radians(tilt)
    v2 = (v * math.cos(t) - n * math.sin(t)).normalized()  # bottom out, top in
    n2 = (n * math.cos(t) + v * math.sin(t)).normalized()
    c = Vector(at)
    front = [p.bm.verts.new(R2B @ (c + u * a + v2 * b + n2 * depth / 2)) for a, b in pts]
    back = [p.bm.verts.new(R2B @ (c + u * a + v2 * b - n2 * depth / 2)) for a, b in pts]
    # each cap a fan of triangles from its middle: a torn outline is concave, and an n-gon of it
    # lost its notches when triangulated (the torn edge came out a plain hexagon)
    mu, mv = sum(a for a, _ in pts) / len(pts), sum(b for _, b in pts) / len(pts)
    cf = p.bm.verts.new(R2B @ (c + u * mu + v2 * mv + n2 * depth / 2))
    cb = p.bm.verts.new(R2B @ (c + u * mu + v2 * mv - n2 * depth / 2))
    k = len(pts)
    faces = []
    for i in range(k):
        j = (i + 1) % k
        faces.append(p.bm.faces.new((cf, front[i], front[j])))
        faces.append(p.bm.faces.new((cb, back[j], back[i])))
        faces.append(p.bm.faces.new((front[i], back[i], back[j], front[j])))
    bmesh.ops.recalc_face_normals(p.bm, faces=faces)
    i = p._col(h)
    for f in faces:
        f.material_index = i




def zombie():
    # -- head: thinning, matted hair with a bald patch, a stitched scar, a bruise on the temple
    hx, hy, hz = R15["Head"]
    p = Piece("Zombie_Head", exact=True, fit=("Head", "round"), outline=ZOUT)
    # matted hair: a torn mat over the whole crown (its notches still reach the band), down the back and sides
    top = hy * 0.5 + 0.03
    cap = jagged(hx * 1.14, hz * 1.12, 18, 21, 0.12)
    plate(p, cap, (0, top, 0), "+y", 0.07, HAIR)
    # the hair round the whole top edge: the strands hang from it, no bare strip between them and the mat
    p.cyl((hx * 1.06, hz * 1.06), 0.16, (0, hy * 0.5 - 0.06, 0.01), HAIR, segs=24)
    p.ref("box")  # flat strands lie on the faces
    # lank strands hanging from it: down the back, over the ears, a few over the left of the brow
    # (the face itself is a decal and changes: kept clear)
    hang = top - 0.02
    for i, x in enumerate((-0.42, -0.26, -0.1, 0.06, 0.22, 0.38)):
        plate(p, strip(0.2, 0.32 + 0.22 * _noise(i, 24), 90 + i), (x * hx, hang, hz * 0.5 + 0.03), "+z", 0.06, HAIR, tilt=2)
    for s, face in ((-1, "-x"), (1, "+x")):
        for i, z in enumerate((0.36, 0.14, -0.08)):
            plate(p, strip(0.2, 0.22 + 0.14 * _noise(i, 25 + s), 100 + i + 3 * s), (s * (hx * 0.5 + 0.03), hang, z * hz), face, 0.06, HAIR, tilt=3)
    for i, x in enumerate((-0.42, -0.29, -0.17)):
        plate(p, strip(0.14, 0.2 + 0.1 * _noise(i, 26), 110 + i), (x * hx, hang, -hz * 0.5 - 0.03), "-z", 0.05, HAIR, tilt=4)
    p.ref("round")
    # a few clumps standing up off the mat
    for i, (x, z, rx, rz) in enumerate(((-0.3, 0.3, 30, 40), (0.1, 0.4, 50, -20), (-0.05, 0.05, 10, 28), (0.3, 0.12, 20, -44))):
        p.cyl(0.2, 0.14 + 0.04 * _noise(i, 9), (x * hx, top + 0.06, z * hz), HAIR, rot=(rx, 0, rz), segs=6, d2=0.09)
    p.ref("box")
    # the scar, across the right of the forehead, and its stitches
    p.box((0.46, 0.05, 0.04), (hx * 0.18, hy * 0.36, -hz * 0.51), ZSKIN_DEEP, rot=(0, 0, -16), bevel=0)
    for i in range(4):
        x = hx * 0.18 + (-0.17 + i * 0.113) * math.cos(math.radians(16))
        y = hy * 0.36 + (0.17 - i * 0.113) * math.sin(math.radians(16))
        p.box((0.035, 0.15, 0.04), (x, y, -hz * 0.525), THREAD, rot=(0, 0, 18), bevel=0)
    plate(p, jagged(0.4, 0.3, 9, 1, 0.55), (hx * 0.505, -hy * 0.08, -hz * 0.16), "+x", 0.03, BRUISE)  # the cheek
    p.finish()

    # -- chest: holes torn in the shirt, the gaunt ribs bumping through, dirt, an open collar,
    # the tie hanging off to one side and long shreds at the hem
    tx, ty, tz = R15["UpperTorso"]
    p = Piece("Zombie_UpperTorso", exact=True, fit=("UpperTorso", "box"), outline=ZOUT)
    zf = -tz * 0.5 - 0.012
    hole = jagged(0.76, 0.64, 15, 3, 0.48)
    plate(p, hole, (-tx * 0.17, -ty * 0.06, zf), "-z", 0.03, ZSKIN)  # the big hole, its left side
    for i, y in enumerate((0.13, 0.0, -0.13)):  # ribs under the skin
        w = 0.42 - 0.06 * abs(i - 1)
        p.cyl(0.05, w, (-tx * 0.17 - 0.02, -ty * 0.06 + y, zf - 0.025), ZSKIN_DARK, axis="x", segs=8, rot=(0, 0, 6 - 6 * i))
    plate(p, jagged(0.36, 0.32, 11, 4, 0.5), (tx * 0.26, ty * 0.24, zf), "-z", 0.03, ZSKIN)
    plate(p, jagged(0.26, 0.22, 9, 5, 0.55), (tx * 0.3, -ty * 0.3, zf), "-z", 0.03, ZSKIN)
    plate(p, jagged(0.5, 0.22, 14, 6, 0.45), (tx * 0.1, -ty * 0.34, zf), "-z", 0.02, DIRT)  # grime
    plate(p, jagged(0.26, 0.5, 14, 7, 0.45), (-tx * 0.36, ty * 0.26, zf), "-z", 0.02, DIRT)
    # the back: a long tear with the spine's bumps, and grime
    zb = tz * 0.5 + 0.012
    plate(p, jagged(0.52, 0.92, 15, 8, 0.45), (tx * 0.05, -ty * 0.04, zb), "+z", 0.03, ZSKIN)
    for i in range(4):
        p.ball((0.13, 0.09, 0.07), (tx * 0.05, ty * (0.14 - i * 0.1), zb + 0.02), ZSKIN_DARK, segs=8, rings=5)
    plate(p, jagged(0.56, 0.3, 14, 9, 0.45), (-tx * 0.28, ty * 0.3, zb), "+z", 0.02, DIRT)
    # collar: two flaps folded open at the throat
    for s in (-1, 1):
        plate(p, [(-0.2, 0.1), (0.2, 0.1), (0.12 * s + 0.0, -0.18), (-0.02 * s, -0.08)],
              (s * 0.22, ty * 0.43, zf - 0.02), "-z", 0.05, RAG_DARK, tilt=-12)
    # the tie: knot pulled loose and the blade swung across, its end torn
    p.box((0.17, 0.15, 0.09), (0.04, ty * 0.34, zf - 0.05), TIE, rot=(0, 0, -12), bevel=0.03)
    plate(p, [(-0.08, 0.0), (0.08, 0.0), (0.12, -0.5), (0.04, -0.62), (-0.03, -0.54), (-0.1, -0.6), (-0.13, -0.48)],
          (0.11, ty * 0.28, zf - 0.04), "-z", 0.04, TIE, tilt=6)
    # where the reaching arms do not cover it: the sides, the shoulders and more of the back
    xs = tx * 0.5 + 0.012
    plate(p, jagged(0.62, 0.84, 15, 41, 0.42), (-xs, -ty * 0.08, 0.02), "-x", 0.02, DIRT)  # mud down the left side
    plate(p, jagged(0.5, 0.56, 14, 42, 0.46), (xs, ty * 0.04, -0.04), "+x", 0.03, ZSKIN)  # torn open on the right
    for i in range(3):  # ribs bumping through it
        p.ball((0.06, 0.07, 0.34 - 0.05 * abs(i - 1)), (xs + 0.02, ty * (0.13 - i * 0.11), -0.04), ZSKIN_DARK, segs=8, rings=5)
    plate(p, jagged(0.44, 0.36, 12, 43, 0.48), (-tx * 0.3, ty * 0.22, zb), "+z", 0.03, ZSKIN)  # the shoulder blade
    plate(p, jagged(0.62, 0.34, 14, 44, 0.42), (tx * 0.22, -ty * 0.32, zb), "+z", 0.02, DIRT)  # mud low on the back
    for s, seed in ((-1, 45), (1, 46)):  # grime over the shoulders
        plate(p, jagged(0.42, 0.34, 12, seed, 0.45), (s * tx * 0.33, ty * 0.5 + 0.012, 0.04 * s), "+y", 0.02, DIRT)
    p.finish()

    # -- waist: the shirt's torn hem hangs over the trousers (on the waist piece, so it follows the
    # hips instead of being bent round the chest's bottom edge), longer at the front left; every
    # other shred a layer further out (no two in one plane), and the rope belt goes round outside them
    lx, ly, lz = R15["LowerTorso"]
    p = Piece("Zombie_LowerTorso", exact=True, fit=("LowerTorso", "box"), outline=ZOUT)
    top = ly * 0.22 + 0.03  # tucked under the belt: it hides where they tear off
    for i, x in enumerate((-0.4, -0.22, -0.05, 0.12, 0.3, 0.42)):
        L = 0.46 - 0.04 * i + 0.1 * _noise(i, 11)
        z = -lz * 0.5 - 0.015 - 0.03 * (i % 2)
        plate(p, strip(0.24 + 0.06 * _noise(i, 12), L, 20 + i), (x * lx, top, z), "-z", 0.03, RAG, tilt=3 + 3 * _noise(i, 13))
    for i, x in enumerate((-0.36, -0.12, 0.14, 0.38)):
        z = lz * 0.5 + 0.015 + 0.03 * (i % 2)
        plate(p, strip(0.26, 0.4 + 0.1 * _noise(i, 14), 30 + i), (x * lx, top, z), "+z", 0.03, RAG, tilt=3)
    for s, face in ((-1, "-x"), (1, "+x")):
        plate(p, strip(0.3, 0.42, 40 + s), (s * (lx * 0.5 + 0.015), top, 0), face, 0.03, RAG, tilt=3)
    p.ref("round")
    by = ly * 0.22
    p.cyl((lx * 1.1, lz * 1.2), 0.12, (0, by, 0), ROPE, segs=24)  # outside the shreds
    zk = -lz * 0.6 - 0.04
    p.ball((0.2, 0.17, 0.14), (lx * 0.22, by, zk), ROPE, segs=10, rings=6)  # the knot
    p.cyl(0.08, 0.36, (lx * 0.2, -ly * 0.2, zk - 0.01), ROPE, rot=(0, 0, 8), segs=8)
    p.cyl(0.08, 0.28, (lx * 0.27, -ly * 0.14, zk - 0.03), ROPE, rot=(0, 0, -14), segs=8)
    p.finish()

    for side, sign in (("Left", -1), ("Right", 1)):
        # -- sleeves torn off above the elbow, the left lower than the right, shreds hanging
        ax, ay, az = R15["UpperArm"]
        p = Piece(f"Zombie_{side}UpperArm", exact=True, fit=(f"{side}UpperArm", "round"), outline=ZOUT)
        length = ay * (0.62 if side == "Left" else 0.44)
        top = ay * 0.5 + 0.02
        p.cyl((ax * 1.14, az * 1.1), length, (0, top - length / 2, 0), RAG, segs=16)
        p.ball((ax * 1.14, 0.3, az * 1.1), (0, top, 0), RAG, cut=0.5, segs=16, rings=8)  # over the shoulder
        rim = top - length
        for i, (face, off) in enumerate((("-z", -az * 0.56), ("+z", az * 0.56), ("-x", -ax * 0.58), ("+x", ax * 0.58))):
            at = (off, rim + 0.04, 0) if "x" in face else (0, rim + 0.04, off)
            if (side == "Right" and face == "-x") or (side == "Left" and face == "+x"):
                continue  # the side against the body
            plate(p, strip(0.22, 0.26 + 0.1 * _noise(i, 50 + sign), 60 + i + sign), at, face, 0.035, RAG, tilt=8)
        if side == "Right":  # a bruise on the bare arm under the sleeve
            plate(p, jagged(0.3, 0.26, 9, 15, 0.55), (0, -ay * 0.3, -az * 0.51), "-z", 0.03, BRUISE)
        p.finish()
        bx, by, bz = R15["LowerArm"]
        p = Piece(f"Zombie_{side}LowerArm", exact=True, fit=(f"{side}LowerArm", "round"), outline=ZOUT)
        if side == "Left":  # a bandage coming loose, its tail hanging
            for i, y in enumerate((0.28, 0.06, -0.16)):
                p.cyl((bx * 1.1, bz * 1.1), 0.13, (0, y * by, 0), BANDAGE, rot=(0, 0, 10 * (-1) ** i), segs=14)
            plate(p, [(-0.07, 0), (0.07, 0), (0.06, -0.42), (0.0, -0.5), (-0.06, -0.4)], (bx * 0.2, -0.2 * by, -bz * 0.56), "-z", 0.03, BANDAGE, tilt=14)
        else:  # stitched up the forearm
            p.box((0.05, by * 0.56, 0.04), (0, -by * 0.02, -bz * 0.51), ZSKIN_DEEP, bevel=0)
            for i in range(5):
                p.box((0.17, 0.035, 0.04), (0, by * (0.22 - i * 0.11), -bz * 0.525), THREAD, rot=(0, 0, 14), bevel=0)
            plate(p, jagged(0.26, 0.22, 9, 16, 0.55), (bx * 0.51, by * 0.2, 0), "+x", 0.03, BRUISE_OLD)
        p.finish()

        # -- trousers: a hole at the knee on the right, a sewn patch on the left thigh
        ux, uy, uz = R15["UpperLeg"]
        p = Piece(f"Zombie_{side}UpperLeg", exact=True, fit=(f"{side}UpperLeg", "round"), outline=ZOUT)
        if side == "Right":
            plate(p, jagged(0.44, 0.36, 13, 17, 0.5), (0, -uy * 0.38, -uz * 0.5 - 0.012), "-z", 0.03, ZSKIN)
        else:
            p.box((0.4, 0.38, 0.04), (0.02, uy * 0.06, -uz * 0.5 - 0.02), PATCH, rot=(0, 0, 7), bevel=0.02)
            for i in range(4):
                for s in (-1, 1):
                    p.box((0.03, 0.08, 0.03), (0.02 + s * 0.2, uy * 0.06 - 0.14 + i * 0.095, -uz * 0.5 - 0.045), THREAD, rot=(0, 0, 7), bevel=0)
        # mud up the outside of each thigh, and on the back of the left a tear
        out = sign * (ux * 0.5 + 0.012)
        plate(p, jagged(0.4, 0.7, 14, 47 + sign, 0.42), (out, -uy * 0.12, 0), "+x" if sign > 0 else "-x", 0.02, DIRT)
        if side == "Left":
            plate(p, jagged(0.34, 0.42, 12, 49, 0.5), (0, uy * 0.1, uz * 0.5 + 0.012), "+z", 0.03, ZSKIN)
        p.finish()

        # -- shins: the trouser leg torn off, raggedly, the left higher; bare skin under it
        kx, ky, kz = R15["LowerLeg"]
        p = Piece(f"Zombie_{side}LowerLeg", exact=True, fit=(f"{side}LowerLeg", "round"), outline=ZOUT)
        cut = ky * (0.06 if side == "Left" else -0.12)
        bare = ky * 0.5 + cut
        p.cyl((kx * 1.04, kz * 1.04), bare, (0, -ky * 0.5 + bare / 2, 0), ZSKIN, segs=16)
        for i, face in enumerate(("-z", "+z", "-x", "+x")):
            off = (kz if "z" in face else kx) * 0.52 * (1 if "+" in face else -1)
            for k, shift in enumerate((-0.16, 0.14)):
                at = (off, cut + 0.05, shift) if "x" in face else (shift, cut + 0.05, off)
                plate(p, strip(0.2, 0.2 + 0.12 * _noise(i * 2 + k, 70 + sign), 80 + i * 2 + k + sign), at, face, 0.03, TROUSER, tilt=6)
        p.finish()

    # -- feet: one worn shoe, its sole coming off at the toe; the other bare, green toes showing
    fx, fy, fz = R15["Foot"]
    p = Piece("Zombie_RightFoot", exact=True, fit=("RightFoot", "box"), outline=ZOUT)
    p.box((fx * 1.16, fy * 1.12, fz * 1.1), (0, 0, 0), SHOE, bevel=0.12)  # the whole foot: the fit hugs it to the real one
    p.box((fx * 1.08, 0.1, fz * 0.7), (0, -fy * 0.5 - 0.03, fz * 0.18), SOLE, bevel=0.04)
    p.box((fx * 1.06, 0.09, fz * 0.38), (0, -fy * 0.5 - 0.07, -fz * 0.36), SOLE, rot=(-14, 0, 0), bevel=0.03)  # flapping open
    for i in range(3):
        p.box((0.34, 0.05, 0.06), (0, fy * 0.54, -fz * (0.06 + i * 0.12)), RAG, rot=(0, 0, 8 * (-1) ** i), bevel=0.01)  # laces
    plate(p, jagged(0.22, 0.18, 9, 18, 0.5), (fx * 0.555, fy * 0.1, fz * 0.1), "+x", 0.03, SOLE)  # a hole in the side
    p.finish()
    p = Piece("Zombie_LeftFoot", exact=True, fit=("LeftFoot", "box"), outline=ZOUT)
    # bare skin over the whole foot (the body under it takes the trousers' colour): the toes and sole sit on it
    p.box((fx * 1.12, fy * 1.08, fz * 1.06), (0, 0, 0), ZSKIN, bevel=0.12)
    for i, x in enumerate((-0.28, -0.1, 0.07, 0.24)):
        s = 0.2 - 0.025 * i
        p.ball((s, s * 0.55, s * 1.2), (x * fx * 1.2, -fy * 0.26, -fz * 0.5 - 0.05), ZSKIN_DARK, segs=10, rings=6)  # toes
    p.box((fx * 1.04, 0.08, fz * 0.9), (0, -fy * 0.5 - 0.05, 0), ZSKIN_DEEP, bevel=0.03)  # a grimy sole
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


# ---------------------------------------------------------------- Police car -----------------
# A comic patrol car (black and white, light bar, push bar). Cop_Body's origin is the ground under
# the middle of the car; Cop_Wheel is one wheel round its hub, tyre face out to +X (the left ones
# are it turned half round). client/server PoliceCar.luau puts them on a constraint chassis.
COP_BODY, COP_WHITE, COP_TRIM, COP_BLUE = "2A2D36", "F2F2EE", "1C1C20", "3060FF"
WHEEL_AT = ((3.25, 1.4, -5.2), (3.25, 1.4, 5.3))  # right front, right rear hub (mirror x for left)


def police_car():
    p = Piece("Cop_Body", exact=True)
    # lower body: one side profile with both wheel arches cut out of it, across the car
    prof = [(8.2, 3.35), (8.55, 2.95), (8.6, 1.5), (8.3, 0.85)]
    for zc in (WHEEL_AT[1][2], WHEEL_AT[0][2]):  # rear arch, then front, going forward
        r = 1.8
        prof.append((zc + r, 0.85))
        prof += [(zc + r * math.cos(t * math.pi / 10), 1.35 + r * math.sin(t * math.pi / 10)) for t in range(11)]
        prof.append((zc - r, 0.85))
    prof += [(-8.3, 0.85), (-8.65, 1.5), (-8.6, 2.5), (-8.2, 2.95), (-4.3, 3.35), (5.4, 3.45)]
    p.prism(prof, 7.4, (0, 0, 0), COP_BODY, bevel=0.18)
    p.box((5.2, 1.3, 15.6), (0, 1.6, 0), "141416", bevel=0)  # underbody, seen through the arches
    # cabin: tinted glass all round, the roof, pillars
    p.prism([(-4.3, 3.3), (-1.5, 5.25), (2.7, 5.25), (5.5, 3.4)], 6.3, (0, 0, 0), GLASS, bevel=0.12)
    p.prism([(-1.65, 5.15), (-1.35, 5.5), (2.65, 5.5), (2.9, 5.15)], 6.45, (0, 0, 0), COP_BODY, bevel=0.1)
    for x in (-1, 1):
        p.box((0.3, 0.3, 3.45), (x * 3.08, 4.3, -2.9), COP_BODY, rot=(-34, 0, 0), bevel=0.06)  # A
        p.box((0.3, 1.95, 0.5), (x * 3.08, 4.3, 0.0), COP_BODY, bevel=0.06)  # B
        p.box((0.3, 0.3, 3.4), (x * 3.08, 4.33, 4.1), COP_BODY, rot=(33.5, 0, 0), bevel=0.06)  # C
        p.box((0.3, 0.32, 9.6), (x * 3.08, 3.45, 0.6), COP_BODY, bevel=0.06)  # window sill
        # white doors, front and rear, with the lettering across them, a seam, handles, the badge
        p.box((0.06, 2.3, 6.6), (x * 3.735, 2.15, 0), COP_WHITE, bevel=0.03)
        p.box((0.04, 2.2, 0.07), (x * 3.77, 2.15, 0.05), COP_TRIM, bevel=0)
        for z in (-0.65, 2.75):
            p.box((0.1, 0.16, 0.6), (x * 3.8, 2.95, z), "8A8E98", bevel=0.03)
        p.text("POLICE", 5.0, 0.06, (x * 3.79, 1.95, 0.25), COP_TRIM, x)
        p.star(0.42, 0.06, (x * 3.79, 2.9, -2.55), YELLOW)
        p.box((0.6, 0.4, 0.5), (x * 3.55, 3.75, -3.7), COP_BODY, bevel=0.1)  # mirror
        # lights: head, indicator, tail; bumpers carry the plates
        p.box((1.5, 0.45, 0.2), (x * 2.55, 2.45, -8.52), WHITE, rot=(0, x * 8, 0), bevel=0.08)
        p.box((0.4, 0.4, 0.2), (x * 3.45, 2.45, -8.32), ORANGE, bevel=0.06)
        p.box((1.6, 0.5, 0.2), (x * 2.55, 2.75, 8.56), RED, bevel=0.08)
        p.ball((0.32, 0.32, 0.12), (x * 0.75, 1.55, -9.33), x < 0 and COP_BLUE or RED)  # push-bar strobes
        # interior through the glass: front seats, the steering wheel on the left
        p.box((1.7, 1.6, 0.4), (x * 1.4, 4.0, 0.7), "34343A", rot=(-12, 0, 0), bevel=0.15)
        p.box((1.0, 0.5, 0.35), (x * 1.4, 5.0, 0.85), "34343A", bevel=0.12)
    p.box((5.6, 1.3, 0.4), (0, 3.95, 3.6), "34343A", rot=(-12, 0, 0), bevel=0.15)  # rear bench
    p.box((6.0, 0.55, 1.1), (0, 3.6, -3.3), COP_TRIM, bevel=0.15)  # dash
    p.ring(0.5, 0.08, (-1.4, 3.95, -2.55), COP_TRIM, rot=(-25, 0, 0))
    # nose: grille with slats, bumper, plate, push bar
    p.box((3.4, 0.75, 0.12), (0, 2.1, -8.62), "3A3C44", bevel=0.04)
    for y in (1.9, 2.1, 2.3):
        p.box((3.2, 0.07, 0.06), (0, y, -8.7), COP_TRIM, bevel=0)
    for z in (-1, 1):
        p.box((7.6, 0.7, 0.6), (0, 1.2, z * 8.62), COP_TRIM, bevel=0.15)
        p.box((1.5, 0.45, 0.08), (0, 1.2, z * 8.96), COP_WHITE, bevel=0.03)
    for x in (-1, 1):
        p.box((0.36, 1.9, 0.36), (x * 1.7, 1.75, -9.35), COP_TRIM, bevel=0.08)
        p.box((0.3, 0.3, 0.6), (x * 1.7, 1.3, -9.0), COP_TRIM, bevel=0.05)
    for y in (1.15, 2.35):
        p.box((4.2, 0.3, 0.3), (0, y, -9.45), COP_TRIM, bevel=0.08)
    # light bar: blue, white, red on a black base
    p.box((5.0, 0.22, 1.1), (0, 5.6, 0.6), COP_TRIM, bevel=0.06)
    p.box((1.9, 0.45, 0.95), (-1.45, 5.92, 0.6), COP_BLUE, bevel=0.12)
    p.box((0.85, 0.4, 0.9), (0, 5.9, 0.6), WHITE, bevel=0.12)
    p.box((1.9, 0.45, 0.95), (1.45, 5.92, 0.6), RED, bevel=0.12)
    p.finish()

    p = Piece("Cop_Wheel", exact=True)  # a right-hand wheel round its hub, axle along X
    p.cyl(2.8, 1.1, (0, 0, 0), COP_TRIM, axis="x", segs=24, bevel=0.22)
    p.cyl(1.75, 1.14, (0, 0, 0), "C8CCD4", axis="x", segs=24, bevel=0.05)
    p.cyl(0.55, 1.2, (0, 0, 0), "8A8E98", axis="x", segs=12, bevel=0.04)
    for i in range(5):
        a = i * 2 * math.pi / 5
        p.cyl(0.42, 1.17, (0, math.cos(a) * 0.58, math.sin(a) * 0.58), "3A3C44", axis="x", segs=10)
    p.finish()


# ---------------------------------------------------------------- Sport car ------------------
# A red hot hatch in a manga wrap: flat red with a darker cel-shade band, white highlight strokes and
# black ink hatching drawn on. It is built as separate PANELS so it can be smashed apart like the
# map's structures (server/PoliceCar.luau knocks off whatever a blast reaches): Sport_Body is the
# core (sides, fenders, skirts), the rest bolt onto it. Every panel's origin is the ground under the
# middle of the car, like Cop_Body; Sport_Wheel is one wheel round its hub, outer face +X.
SP_RED, SP_SHADE, SP_HL, SP_INK = "E3242B", "9E1018", "FFF1EA", "121214"
SP_GLASS, SP_TRIM, SP_RIM, SP_SPOKE = "1E232B", "18181C", "26262C", "3E4048"
SPORT_WHEEL_AT = ((3.2, 1.35, -5.0), (3.2, 1.35, 5.2))  # right front, right rear hub
HOOD_SLOPE = math.degrees(math.atan2(0.48, 3.7))


def hood_y(z):
    """Top of the hood panel at `z` (it rises from the nose to the windscreen)."""
    return 2.97 + (z + 7.75) * 0.48 / 3.7


def ink_side(p, side, x, marks):
    """Hatching on a car side facing `side` (+1 / -1) at |x|: each mark is (z, y, slant degrees, count, length)."""
    for z, y, slant, n, ln in marks:
        for i in range(n):
            p.box((0.025, ln * (1 - 0.18 * (i % 2)), 0.06), (side * (x + 0.012), y, z + i * 0.16), SP_INK, rot=(slant, 0, 0), bevel=0)


def ink_top(p, marks, top, slope):
    """Hatching lying on a top surface whose height at z is top(z): each mark is (x, z, count, length)."""
    for x, z, n, ln in marks:
        for i in range(n):
            p.box((0.06, 0.02, ln * (1 - 0.18 * (i % 2))), (x + i * 0.15, top(z) + 0.012, z), SP_INK, rot=(-slope, 0, 0), bevel=0)


def sport_car():
    arch = []
    for zc in (SPORT_WHEEL_AT[1][2], SPORT_WHEEL_AT[0][2]):  # rear arch, then front, going forward
        r = 1.7  # its top (2.95) stays under the hood line, else the profile folds over itself
        arch.append((zc + r, 0.85))
        arch += [(zc + r * math.cos(t * math.pi / 10), 1.25 + r * math.sin(t * math.pi / 10)) for t in range(11)]
        arch.append((zc - r, 0.85))

    # core: the body between the bumpers, with both arches, skirts and the fenders' marks
    p = Piece("Sport_Body", exact=True)
    p.prism([(7.6, 3.3), (7.6, 0.85)] + arch + [(-7.6, 0.85), (-7.6, 2.8), (-4.0, 3.25), (5.4, 3.35)], 7.2, (0, 0, 0), SP_RED, bevel=0.16)
    p.box((5.0, 1.2, 15.0), (0, 1.5, 0), "141416", bevel=0)  # underbody, seen through the arches
    for s in (-1, 1):
        p.box((0.22, 0.32, 6.4), (s * 3.66, 0.86, 0.05), SP_TRIM, bevel=0.06)  # skirt
        p.box((0.02, 0.05, 2.4), (s * 3.612, 2.85, -6.1), SP_HL, rot=(-7.1, 0, 0), bevel=0)  # fender highlights
        p.box((0.02, 0.05, 2.4), (s * 3.612, 3.1, 6.2), SP_HL, bevel=0)
        p.prism([(-7.5, 2.1), (-7.0, 2.45), (-6.85, 2.2), (-7.3, 1.0), (-7.5, 1.0)], 0.02, (s * 3.61, 0, 0), SP_SHADE, bevel=0)
        p.prism([(7.5, 2.0), (7.1, 2.5), (6.95, 2.25), (7.3, 1.0), (7.5, 1.0)], 0.02, (s * 3.61, 0, 0), SP_SHADE, bevel=0)
        ink_side(p, s, 3.6, [(-6.9, 2.55, 12, 3, 0.5), (6.3, 2.85, -12, 3, 0.55)])
    p.finish()

    # hood: a plate over the core's nose, scoop, cel-shade band, highlight strokes, hatching
    p = Piece("Sport_Hood", exact=True)
    p.prism([(-7.75, 2.75), (-4.05, 3.23), (-4.05, 3.45), (-7.75, 2.97)], 6.9, (0, 0, 0), SP_RED, bevel=0.08)
    p.box((2.0, 0.3, 1.1), (0, hood_y(-6.0) + 0.12, -6.0), SP_RED, rot=(-HOOD_SLOPE, 0, 0), bevel=0.1)
    p.box((1.6, 0.16, 0.06), (0, hood_y(-6.55) + 0.17, -6.57), SP_INK, rot=(-HOOD_SLOPE, 0, 0), bevel=0.03)
    for s in (-1, 1):
        p.box((1.1, 0.02, 3.3), (s * 1.05, hood_y(-5.9) + 0.012, -5.9), SP_SHADE, rot=(-HOOD_SLOPE, 0, 0), bevel=0)
        p.box((0.06, 0.02, 3.4), (s * 2.65, hood_y(-5.9) + 0.014, -5.9), SP_HL, rot=(-HOOD_SLOPE, 0, 0), bevel=0)
    ink_top(p, [(1.9, -7.1, 3, 0.6), (-2.6, -6.6, 3, 0.5), (0.4, -4.8, 2, 0.45), (-1.5, -7.4, 2, 0.4)], hood_y, HOOD_SLOPE)
    p.finish()

    # front bumper: splitter, grilles, headlights (a white LED brow), corner vents, fogs, a plain badge
    p = Piece("Sport_BumperF", exact=True)
    p.prism([(-7.55, 0.65), (-8.65, 0.65), (-8.75, 1.4), (-8.6, 2.45), (-8.2, 2.8), (-7.55, 2.8)], 7.5, (0, 0, 0), SP_RED, bevel=0.14)
    p.box((7.8, 0.1, 0.9), (0, 0.6, -8.55), SP_TRIM, bevel=0.04)
    p.box((3.6, 0.7, 0.06), (0, 1.32, -8.79), SP_TRIM, bevel=0.02)
    p.box((2.6, 0.22, 0.06), (0, 2.15, -8.7), SP_TRIM, bevel=0.02)
    p.box((0.32, 0.32, 0.06), (0, 1.84, -8.8), "C8CCD4", rot=(0, 0, 45), bevel=0.02)
    p.box((6.0, 0.03, 0.05), (0, 2.81, -7.9), SP_HL, bevel=0)
    for s in (-1, 1):
        p.box((1.8, 0.42, 0.3), (s * 2.5, 2.5, -8.4), "2A2A30", rot=(0, s * 10, 0), bevel=0.08)
        p.box((1.5, 0.07, 0.05), (s * 2.5, 2.6, -8.58), WHITE, rot=(0, s * 10, 0), bevel=0)
        p.box((1.0, 0.7, 0.06), (s * 2.85, 1.25, -8.79), SP_TRIM, bevel=0.02)
        p.cyl(0.3, 0.08, (s * 2.85, 1.25, -8.84), "C8CCD4", axis="z", segs=12)
        ink_side(p, s, 3.75, [(-8.3, 1.6, 10, 3, 0.5)])
    p.finish()

    # rear bumper: taillights, diffuser and fins, three tailpipes in the middle, vents, plate
    p = Piece("Sport_BumperR", exact=True)
    p.prism([(7.55, 0.7), (8.6, 0.75), (8.7, 1.6), (8.55, 2.9), (8.1, 3.35), (7.55, 3.35)], 7.5, (0, 0, 0), SP_RED, bevel=0.14)
    p.box((4.4, 0.5, 0.9), (0, 0.95, 8.45), SP_TRIM, bevel=0.05)
    for x in (-1.5, -0.75, 0.75, 1.5):
        p.box((0.06, 0.45, 0.9), (x, 0.92, 8.75), SP_TRIM, bevel=0)
    for x in (-0.65, 0, 0.65):
        p.cyl(0.5, 0.5, (x, 1.38, 8.78), "8A8E98", axis="z", segs=14, bevel=0.04)
        p.cyl(0.34, 0.52, (x, 1.38, 8.79), "0C0C0E", axis="z", segs=14)
    p.box((1.5, 0.45, 0.06), (0, 2.2, 8.66), "F2F2EE", bevel=0.02)
    p.box((6.6, 0.03, 0.05), (0, 3.36, 7.95), SP_HL, bevel=0)
    for s in (-1, 1):
        p.box((1.6, 0.42, 0.18), (s * 2.55, 2.88, 8.6), RED, rot=(0, 0, s * 8), bevel=0.06)
        p.box((1.1, 0.7, 0.06), (s * 2.55, 1.55, 8.73), SP_TRIM, bevel=0.02)
        ink_side(p, s, 3.75, [(8.1, 2.2, -10, 3, 0.55)])
    p.finish()

    # doors, one piece a side: skin, cel-shade band with a jagged top, highlight, seam, handles,
    # hatching, the mirror
    for s, name in ((-1, "Sport_DoorL"), (1, "Sport_DoorR")):
        p = Piece(name, exact=True)
        p.prism([(-3.05, 1.0), (3.2, 1.0), (3.2, 3.32), (-2.9, 3.18)], 0.22, (s * 3.71, 0, 0), SP_RED, bevel=0.06)
        jag = [(3.1, 1.05), (3.1, 1.95), (2.3, 2.3), (1.4, 1.9), (0.5, 2.35), (-0.5, 1.95), (-1.4, 2.3), (-2.2, 1.9), (-2.95, 2.1), (-2.95, 1.05)]
        p.prism(jag, 0.02, (s * 3.83, 0, 0), SP_SHADE, bevel=0)
        p.box((0.02, 0.06, 5.9), (s * 3.835, 2.95, 0.1), SP_HL, bevel=0)
        p.box((0.02, 2.15, 0.05), (s * 3.836, 2.1, 0.4), SP_INK, bevel=0)
        for z in (-0.6, 2.6):
            p.box((0.08, 0.14, 0.55), (s * 3.86, 2.72, z), SP_TRIM, bevel=0.03)
        ink_side(p, s, 3.83, [(-2.5, 1.7, 15, 3, 0.8), (1.6, 1.5, -12, 4, 0.6), (2.75, 2.6, 10, 2, 0.5), (-1.0, 2.75, -8, 3, 0.4)])
        p.box((0.55, 0.38, 0.6), (s * 3.98, 3.55, -2.7), SP_RED, bevel=0.1)
        p.box((0.3, 0.12, 0.2), (s * 3.72, 3.45, -2.6), SP_TRIM, bevel=0.03)
        p.finish()

    # cabin: dark tinted glass, red roof on black pillars (a floating roof), roof fins, glass glints
    p = Piece("Sport_Cabin", exact=True)
    p.prism([(-4.0, 3.22), (-1.0, 4.6), (2.5, 4.6), (6.4, 3.35)], 6.3, (0, 0, 0), SP_GLASS, bevel=0.1)
    p.prism([(-1.15, 4.5), (-0.9, 4.82), (2.5, 4.82), (2.85, 4.5)], 6.45, (0, 0, 0), SP_RED, bevel=0.08)
    p.box((6.4, 0.03, 0.05), (0, 4.83, 1.0), SP_HL, bevel=0)
    for s in (-1, 1):
        p.box((0.28, 0.28, 3.35), (s * 3.08, 3.925, -2.5), SP_TRIM, rot=(-24.2, 0, 0), bevel=0.05)
        p.box((0.28, 0.28, 4.1), (s * 3.08, 3.975, 4.45), SP_TRIM, rot=(17.8, 0, 0), bevel=0.05)
        p.box((0.28, 1.3, 0.4), (s * 3.08, 3.95, 0.6), SP_TRIM, bevel=0.05)
        p.box((0.3, 0.2, 10.2), (s * 3.08, 3.3, 1.2), SP_TRIM, bevel=0.05)
        p.box((0.02, 0.9, 0.1), (s * 3.165, 3.95, -1.6), SP_HL, rot=(20, 0, 0), bevel=0)
        p.box((0.02, 0.7, 0.1), (s * 3.165, 3.9, 1.9), SP_HL, rot=(20, 0, 0), bevel=0)
    for x, ln in ((1.3, 1.6), (1.75, 1.1)):  # windscreen glints
        p.box((0.12, 0.02, ln), (x, 3.851, -2.735), SP_HL, rot=(-24.2, 0, 0), bevel=0)
    for x, ln in ((-1.2, 1.6), (-1.6, 1.0)):  # hatch glass glints
        p.box((0.12, 0.02, ln), (x, 4.02, 4.41), SP_HL, rot=(17.8, 0, 0), bevel=0)
    for x in (-2.0, -1.2, -0.4, 0.4, 1.2, 2.0):  # roof fins
        p.box((0.06, 0.2, 0.4), (x, 4.92, 2.2), SP_TRIM, bevel=0)
    p.finish()

    # rear wing: two stalks, a wide blade with end plates and a gurney strip
    p = Piece("Sport_Wing", exact=True)
    for s in (-1, 1):
        p.box((0.18, 1.1, 0.5), (s * 2.3, 3.9, 7.25), SP_TRIM, bevel=0.04)
        p.box((0.1, 0.8, 1.7), (s * 3.55, 4.45, 7.35), SP_RED, bevel=0.04)
    p.box((7.0, 0.16, 1.5), (0, 4.5, 7.35), SP_RED, rot=(-6, 0, 0), bevel=0.05)
    p.box((6.9, 0.1, 0.06), (0, 4.6, 8.08), SP_TRIM, bevel=0)
    p.box((6.6, 0.02, 0.06), (0, 4.585, 6.7), SP_HL, bevel=0)
    ink_top(p, [(2.2, 7.3, 3, 0.5), (-2.8, 7.4, 2, 0.45)], lambda z: 4.58 - (z - 7.35) * math.tan(math.radians(6)), 6)
    p.finish()

    p = Piece("Sport_Wheel", exact=True)  # a right-hand wheel round its hub, axle along X
    p.cyl(2.7, 1.15, (0, 0, 0), "16161A", axis="x", segs=24, bevel=0.22)
    p.cyl(1.85, 1.18, (0, 0, 0), SP_RIM, axis="x", segs=24, bevel=0.04)
    p.cyl(0.45, 1.24, (0, 0, 0), "8A8E98", axis="x", segs=12, bevel=0.03)
    for i in range(5):
        a = i * 72
        rad = math.radians(a)
        p.box((0.08, 0.7, 0.21), (0.6, math.cos(rad) * 0.5, math.sin(rad) * 0.5), SP_SPOKE, rot=(a, 0, 0), bevel=0.02)
    p.finish()


SPORT_PIECES = ("Sport_Body", "Sport_Hood", "Sport_BumperF", "Sport_BumperR", "Sport_DoorL", "Sport_DoorR", "Sport_Cabin", "Sport_Wing")


# ---------------------------------------------------------------- Tank -----------------------
# A heavy WW2-era tank (the silhouette of the period, no markings of any side: only the number 131),
# cartoon-chunky like the cars: a boxy hull, a big turret with a rounded back, an over-long gun with a
# double muzzle brake, overlapping road wheels. Every piece's origin is the ground under the middle of
# the tank, front -Z (like Cop_Body), modelled with the turret straight ahead and the gun level:
# server/PoliceCar.luau turns Tank_Turret round TANK_TURRET (its ring, in the hull roof) and
# Tank_Mantlet / Tank_Barrel also round TANK_GUN (the trunnions). Tank_Wheel is one road wheel round
# its hub, outer face +X; TANK_WHEELS lists where they go (right side; mirror x for the left).
TK_SAND, TK_OLIVE, TK_BROWN, TK_DIRT = "C9B27C", "6B7A3A", "7A5A34", "8E7B52"
TK_METAL, TK_DARK, TK_RUST, TK_WOOD, TK_NUM = "2E2E30", "1E1E20", "5A4636", "8A6A40", "F0EADA"
TANK_TURRET = (0, 4.9, -0.4)
TANK_GUN = (0, 6.3, -4.1)
TANK_WHEEL_R = 1.4
TANK_WHEELS = tuple((4.4, 1.4, z) for z in (-5.4, -1.8, 1.8, 5.4)) + tuple((3.55, 1.4, z) for z in (-3.6, 0.0, 3.6))
TANK_PIECES = ("Tank_Hull", "Tank_FenderL", "Tank_FenderR", "Tank_TrackL", "Tank_TrackR", "Tank_Turret",
               "Tank_Mantlet", "Tank_Barrel", "Tank_Exhaust")


def blotch_pts(cx, cy, r, seed, n=8):
    """An irregular camouflage blob round (cx, cy), radius about r."""
    import random
    rnd = random.Random(seed)
    return [(cx + r * (0.65 + 0.5 * rnd.random()) * math.cos(2 * math.pi * i / n),
             cy + r * (0.55 + 0.45 * rnd.random()) * math.sin(2 * math.pi * i / n) * 0.75) for i in range(n)]


def camo_side(p, x, marks, seed):
    """Blobs on a face looking along +-X at `x`: each mark is (z, y, r, colour)."""
    for i, (z, y, r, h) in enumerate(marks):
        p.prism(blotch_pts(z, y, r, seed + i), 0.02, (x, 0, 0), h, bevel=0)


def camo_top(p, y, marks, seed):
    """Blobs lying on a top surface at height `y`: each mark is (x, z, r, colour)."""
    for i, (x, z, r, h) in enumerate(marks):
        p.slab(blotch_pts(x, z, r, seed + i), y, y + 0.02, (0, 0, 0), h, bevel=0)


def hull2d(pts):
    """Convex hull of 2D points, counter-clockwise (monotone chain)."""
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for q in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], q) <= 0:
            lo.pop()
        lo.append(q)
    for q in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], q) <= 0:
            hi.pop()
        hi.append(q)
    return lo[:-1] + hi[:-1]


def resample(loop, step):
    """Points every `step` along a closed polyline, with the outward normal (z, y) at each."""
    out, n = [], len(loop)
    seg = [(loop[i], loop[(i + 1) % n]) for i in range(n)]
    total = sum(math.dist(a, b) for a, b in seg)
    count = max(8, round(total / step))
    d, k, acc = total / count, 0, 0.0
    for i in range(count):
        t = i * d
        while acc + math.dist(*seg[k]) < t:
            acc += math.dist(*seg[k])
            k += 1
        a, b = seg[k]
        ln = math.dist(a, b)
        f = (t - acc) / ln
        tz, ty = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        out.append(((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f), (ty, -tz)))  # ccw loop: right of the tangent is out
    return out


def track_piece(name, s):
    """One track: the link band round the wheels, its cleats, the drive sprocket in front, the idler."""
    p = Piece(name, exact=True)
    x, w, t = s * 3.9, 2.2, 0.35
    circles = [(-7.5, 1.9, 1.1), (7.5, 1.8, 1.1)] + [(z, TANK_WHEEL_R, TANK_WHEEL_R) for z in (-5.4, 5.4)]
    pts = [(cz + (r + t / 2) * math.cos(a * math.pi / 12), cy + (r + t / 2) * math.sin(a * math.pi / 12)) for cz, cy, r in circles for a in range(24)]
    path = resample(hull2d(pts), 0.5)
    loops = []
    for (z, y), (nz, ny) in path:
        loops.append([(x - w / 2, y - ny * t / 2, z - nz * t / 2), (x + w / 2, y - ny * t / 2, z - nz * t / 2),
                      (x + w / 2, y + ny * t / 2, z + nz * t / 2), (x - w / 2, y + ny * t / 2, z + nz * t / 2)])
    faces = p._solid(loops, (0, 0, 0), TK_METAL, (0, 0, 0))
    bmesh.ops.recalc_face_normals(p.bm, faces=faces)
    for i, ((z, y), (nz, ny)) in enumerate(resample(hull2d(pts), 0.8)):
        ang = math.degrees(math.atan2(-nz, ny))  # turn the cleat to lie on the band
        p.box((w + 0.12, 0.16, 0.32), (x, y + ny * (t / 2 + 0.05), z + nz * (t / 2 + 0.05)), TK_DARK, rot=(ang, 0, 0), bevel=0)
    # sprocket (teeth round a sand hub) and idler
    p.cyl(2.0, 1.3, (x, 1.9, -7.5), TK_SAND, axis="x", segs=16, bevel=0.08)
    p.cyl(0.8, 1.45, (x, 1.9, -7.5), TK_METAL, axis="x", segs=10)
    for i in range(9):
        a = i * 2 * math.pi / 9
        p.box((1.4, 0.35, 0.35), (x, 1.9 + math.cos(a) * 1.05, -7.5 + math.sin(a) * 1.05), TK_METAL, rot=(math.degrees(-a), 0, 0), bevel=0)
    p.cyl(2.0, 1.2, (x, 1.8, 7.5), TK_SAND, axis="x", segs=16, bevel=0.08)
    p.cyl(0.7, 1.35, (x, 1.8, 7.5), TK_METAL, axis="x", segs=10)
    p.finish()


def tank():
    tx, ty, tz = TANK_TURRET
    gx, gy, gz = TANK_GUN

    # hull: the low tub between the tracks, the wide superstructure over them, deck details
    p = Piece("Tank_Hull", exact=True)
    p.prism([(-8.55, 3.4), (-8.8, 2.6), (-7.3, 0.9), (7.5, 0.9), (8.5, 2.3), (8.35, 3.4)], 5.6, (0, 0, 0), TK_DIRT, bevel=0.15)
    p.prism([(-8.75, 3.4), (-8.55, 4.9), (8.2, 4.9), (8.4, 3.4)], 8.4, (0, 0, 0), TK_SAND, bevel=0.15)
    p.box((7.2, 0.2, 6.4), (0, 4.95, 4.6), "B8A26E", bevel=0.05)  # engine deck
    for z in (2.6, 3.6, 5.6, 6.6):
        p.box((2.4, 0.12, 0.7), (0, 5.08, z), TK_DARK, bevel=0.03)  # grilles
    for s in (-1, 1):
        p.cyl(1.3, 0.18, (s * 2.4, 5.0, 4.6), TK_METAL, axis="y", segs=12)  # fan covers
        p.cyl(0.45, 0.6, (s * 3.4, 5.15, -8.0), TK_METAL, axis="z", segs=10, bevel=0.05)  # headlights
        p.cyl(0.32, 0.64, (s * 3.4, 5.15, -8.0), "FFF4C8", axis="z", segs=10)
        for z in (-8.85, 8.6):  # tow hooks
            p.box((0.5, 0.6, 0.5), (s * 2.3, 1.55, z), TK_METAL, bevel=0.08)
        p.box((0.35, 0.12, 15.0), (s * 4.1, 3.5, 0), TK_DIRT, bevel=0)  # dirt along the bottom edge
    p.box((1.8, 0.4, 0.25), (-2.1, 4.35, -8.68), TK_DARK, bevel=0.06)  # driver's visor
    p.box((1.6, 0.18, 0.2), (-2.1, 4.6, -8.7), TK_METAL, bevel=0.04)
    p.ball((0.9, 0.9, 0.6), (2.2, 4.2, -8.68), TK_METAL)  # hull machine gun (decoration)
    p.cyl(0.18, 1.0, (2.2, 4.2, -9.1), TK_DARK, axis="z", segs=8)
    for s in (-1, 1):
        p.box((1.2, 0.8, 0.6), (s * 1.0, 5.15, -6.8), TK_SAND, bevel=0.2)  # hatches
        p.cyl(0.8, 0.12, (s * 1.0, 5.6, -6.8), TK_METAL, axis="y", segs=10)
    camo_side(p, 4.215, [(-5.5, 4.2, 1.5, TK_OLIVE), (-1.0, 4.0, 1.3, TK_BROWN), (3.0, 4.3, 1.6, TK_OLIVE), (6.8, 4.0, 1.1, TK_BROWN)], 10)
    camo_side(p, -4.215, [(-6.2, 4.0, 1.2, TK_BROWN), (-2.4, 4.3, 1.5, TK_OLIVE), (1.8, 4.0, 1.2, TK_BROWN), (5.8, 4.2, 1.6, TK_OLIVE)], 20)
    camo_top(p, 4.905, [(-2.8, -4.5, 1.5, TK_OLIVE), (2.6, -3.2, 1.3, TK_BROWN), (-3.2, 1.2, 1.0, TK_BROWN), (3.4, 1.0, 1.0, TK_OLIVE)], 30)
    p.slab([(-3.6, -8.66), (-1.8, -8.7), (-2.4, -8.7), (-3.8, -8.64)], 3.7, 4.7, (0, 0, 0), TK_OLIVE, bevel=0)  # front plate streak
    p.finish()

    # fenders: a plate over each track with a mud flap in front; the shovel left, the pick right
    for s, name in ((-1, "Tank_FenderL"), (1, "Tank_FenderR")):
        p = Piece(name, exact=True)
        x = s * 4.7
        p.box((1.15, 0.12, 16.4), (x, 3.45, -0.2), TK_SAND, bevel=0.03)
        p.box((1.15, 0.12, 1.3), (x, 3.2, -8.9), TK_SAND, rot=(-25, 0, 0), bevel=0.03)
        p.box((1.15, 0.12, 0.9), (x, 3.25, 8.4), TK_SAND, rot=(20, 0, 0), bevel=0.03)
        for z in (-6.0, 0.0, 6.0):
            p.box((0.25, 0.25, 0.25), (s * 4.3, 3.62, z), TK_DARK, bevel=0.03)  # brackets
        if s < 0:
            p.cyl(0.18, 4.4, (x, 3.65, 0.6), TK_WOOD, axis="z", segs=8)  # shovel
            p.box((0.75, 0.08, 1.1), (x, 3.62, -2.2), TK_METAL, bevel=0.05)
        else:
            p.cyl(0.18, 4.0, (x, 3.65, -1.0), TK_WOOD, axis="z", segs=8)  # pick
            p.box((0.16, 0.16, 2.0), (x, 3.68, 1.0), TK_METAL, rot=(0, 90, 0), bevel=0.03)
        p.box((0.2, 0.2, 1.6), (x, 3.62, 4.6), TK_DARK, bevel=0.03)  # a tow cable coil
        p.finish()

    track_piece("Tank_TrackL", -1)
    track_piece("Tank_TrackR", 1)

    # turret: flat front, straight sides, a rounded back, cupola left rear, stowage bin, spare links, 131
    p = Piece("Tank_Turret", exact=True)
    outline = [(-3.5, tz - 3.6), (3.5, tz - 3.6), (3.5, tz + 0.9)] + [(3.5 * math.cos(a * math.pi / 10), tz + 0.9 + 3.3 * math.sin(a * math.pi / 10)) for a in range(1, 10)] + [(-3.5, tz + 0.9)]
    p.slab(outline, ty, ty + 2.8, (0, 0, 0), TK_SAND, bevel=0.22)
    p.slab([(x * 0.94, z) for x, z in outline[:2]] + [(3.2, tz + 0.9), (-3.2, tz + 0.9)], ty + 2.8, ty + 2.95, (0, 0, 0), "B8A26E", bevel=0.04)
    p.cyl(1.7, 0.9, (-1.7, ty + 3.2, tz + 2.0), TK_SAND, axis="y", segs=14, bevel=0.1)  # cupola
    p.cyl(1.4, 0.18, (-1.7, ty + 3.72, tz + 2.0), TK_METAL, axis="y", segs=14)  # its hatch
    for i in range(6):
        a = i * math.pi / 3
        p.box((0.35, 0.25, 0.1), (-1.7 + 0.85 * math.cos(a), ty + 3.25, tz + 2.0 + 0.85 * math.sin(a)), TK_DARK, rot=(0, -math.degrees(a) + 90, 0), bevel=0)
    p.box((1.2, 0.15, 1.0), (1.4, ty + 2.98, tz + 0.6), TK_METAL, bevel=0.05)  # loader's hatch
    p.box((4.2, 1.5, 1.4), (0, ty + 1.6, tz + 4.7), TK_SAND, bevel=0.15)  # stowage bin
    p.box((4.0, 0.12, 1.3), (0, ty + 2.4, tz + 4.7), TK_BROWN, bevel=0.03)
    for s in (-1, 1):
        for z in (tz - 0.1, tz + 0.75):
            p.box((0.22, 0.6, 0.75), (s * 3.62, ty + 1.5, z), TK_METAL, bevel=0.04)  # spare links
            p.box((0.1, 0.2, 0.8), (s * 3.72, ty + 1.5, z), TK_DARK, bevel=0)
        p.text("131", 2.0, 0.05, (s * 3.53, ty + 1.45, tz - 2.3), TK_NUM, s)
        for k in range(3):
            p.cyl(0.32, 0.6, (s * 3.1, ty + 2.2, tz - 3.4 + k * 0.4), TK_METAL, axis="y", rot=(-30, 0, 0), segs=8)  # smoke dischargers
        camo_side(p, s * 3.515, [(tz + 1.4, ty + 1.8, 0.9, TK_OLIVE), (tz - 0.8, ty + 0.6, 0.7, TK_BROWN)], 40 + s)
    camo_top(p, ty + 2.81, [(-2.2, tz - 2.2, 0.9, TK_OLIVE), (1.8, tz + 2.6, 1.0, TK_BROWN), (2.3, tz - 1.6, 0.7, TK_BROWN)], 50)
    p.finish()

    # mantlet: the gun shield round the trunnions, the sight beside the gun
    p = Piece("Tank_Mantlet", exact=True)
    p.box((4.3, 2.3, 0.9), (gx, gy, gz - 0.45), TK_SAND, bevel=0.3)
    p.cyl(1.25, 0.8, (gx, gy, gz - 1.25), TK_SAND, axis="z", segs=14, bevel=0.1)
    p.cyl(0.35, 0.2, (gx + 1.3, gy + 0.55, gz - 0.95), TK_DARK, axis="z", segs=8)
    camo_side(p, 2.16, [(gz - 0.45, gy, 0.6, TK_OLIVE)], 60)
    p.finish()

    # gun: a long fat tube and a two-chamber muzzle brake (its pivot is TANK_GUN)
    p = Piece("Tank_Barrel", exact=True)
    z0, z1 = gz - 1.6, gz - 12.4
    p.cyl(0.8, z0 - z1, (gx, gy, (z0 + z1) / 2), TK_METAL, axis="z", segs=14, d2=0.62)
    p.cyl(0.95, 1.4, (gx, gy, z0 - 0.5), TK_METAL, axis="z", segs=14, bevel=0.06)  # the thicker root
    for z in (z1 - 0.15, z1 - 1.05):
        p.cyl(1.25, 0.55, (gx, gy, z), TK_METAL, axis="z", segs=14, bevel=0.08)
    p.cyl(0.85, 1.3, (gx, gy, z1 - 0.6), TK_DARK, axis="z", segs=12)
    p.cyl(0.4, 0.05, (gx, gy, z1 - 1.34), "0A0A0C", axis="z", segs=10)  # the bore
    p.finish()

    # exhausts: two tall pipes on the rear plate, each in a guard
    p = Piece("Tank_Exhaust", exact=True)
    for s in (-1, 1):
        p.cyl(0.55, 2.4, (s * 1.7, 4.9, 8.65), TK_RUST, axis="y", segs=10, bevel=0.04)
        p.cyl(0.4, 0.1, (s * 1.7, 6.12, 8.65), "0A0A0C", axis="y", segs=10)
        p.box((0.9, 1.2, 0.12), (s * 1.7, 4.4, 8.98), TK_SAND, bevel=0.04)
    p.finish()

    # one road wheel: rubber tyre, a sand dish, a dark hub and its bolts
    p = Piece("Tank_Wheel", exact=True)
    p.cyl(2.8, 0.7, (0, 0, 0), TK_METAL, axis="x", segs=16, bevel=0.1)
    p.cyl(2.3, 0.76, (0, 0, 0), TK_SAND, axis="x", segs=16)
    p.cyl(0.8, 0.86, (0, 0, 0), TK_METAL, axis="x", segs=8)
    for i in range(4):
        a = i * math.pi / 2
        p.cyl(0.16, 0.9, (0, math.cos(a) * 0.62, math.sin(a) * 0.62), TK_DARK, axis="x", segs=6)
    p.finish()


# ---------------------------------------------------------------- Map vehicles ---------------
# The parked vehicles the maps used to build out of plain blocks, remade to the same footprint,
# heights and colours (Map.luau car / boats, City.luau car / Bus, Factory.luau Forklift) in the kit's
# comic style. PAINT is a stand-in: the game paints that mesh (and its cubes) each car's own colour.
# Origins are on the ground under the middle, front toward -Z; Map.luau shows these until a hit
# reaches them and then swaps in their cubes (assets/army/voxels.py), so they still break brick by brick.
PAINT = "FE01FE"
V_DARK, V_TYRE, V_HUB, V_INK, V_HL = "1C1C20", "18181A", "C8CCD4", "121214", "FFF1EA"
V_HEAD, V_TAIL = "FFF4C8", "FF3030"


def wheel(p, at, diameter, width, hub=V_HUB, segs=18):
    p.cyl(diameter, width, at, V_TYRE, axis="x", segs=segs, bevel=min(0.18, width * 0.2))
    p.cyl(diameter * 0.5, width + 0.04, at, hub, axis="x", segs=12, bevel=0.03)


def arched(length_half, bottom, top_front, top_back, arches, r, cy, nose=0.4):
    """A car side profile (z, y) with wheel arches: front at -length_half, a rounded nose and tail."""
    prof = [(length_half - 0.2, top_back), (length_half, top_back - 0.3), (length_half, bottom + 0.25), (length_half - 0.15, bottom)]
    for zc in sorted(arches, reverse=True):
        prof.append((zc + r, bottom))
        prof += [(zc + r * math.cos(t * math.pi / 8), cy + r * math.sin(t * math.pi / 8)) for t in range(9)]
        prof.append((zc - r, bottom))
    prof += [(-length_half + 0.15, bottom), (-length_half, bottom + 0.25), (-length_half, top_front - nose), (-length_half + nose, top_front)]
    return prof


def text_z(p, s, width, depth, at, h, side):
    """Lettering on a face looking along `side` Z (-1: the front), reading left to right from there."""
    font = None
    for f in ("ariblk.ttf", "impact.ttf", "arialbd.ttf"):
        path = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", f)
        if os.path.exists(path):
            font = bpy.data.fonts.load(path, check_existing=True)
            break
    cu = bpy.data.curves.new("_txt", "FONT")
    cu.body, cu.align_x, cu.align_y, cu.extrude, cu.resolution_u = s, "CENTER", "CENTER", depth / 2, 3
    if font:
        cu.font = font
    ob = bpy.data.objects.new("_txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    xs = [v.co.x for v in me.vertices]
    k = width / (max(xs) - min(xs))
    vmap = [p.bm.verts.new(R2B @ (Vector(at) + Vector((side * v.co.x * k, v.co.y * k, side * v.co.z)))) for v in me.vertices]
    faces = [p.bm.faces.new([vmap[i] for i in q.vertices]) for q in me.polygons]
    ob.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bmesh.ops.recalc_face_normals(p.bm, faces=faces)
    i = p._col(h)
    for f in faces:
        f.material_index = i


def park_car():
    """Map.luau car(): body 4.4 x 1.8 x 9 (y 0.8..2.6), a glass cabin 4 x 1.4 x 5 on it (z -2..3),
    0.8-wide wheels 1.6 across at x 1.9, z 2.9, headlights at the front."""
    p = Piece("Park_Car", exact=True)
    p.prism(arched(4.5, 0.8, 2.45, 2.6, (-2.9, 2.9), 0.95, 0.8, nose=0.3) + [(-2.4, 2.6)], 4.4, (0, 0, 0), PAINT, bevel=0.14)
    p.box((3.4, 0.6, 8.0), (0, 1.05, 0), V_DARK, bevel=0)  # floor, seen in the arches
    for s in (-1, 1):
        for z in (-2.9, 2.9):
            wheel(p, (s * 1.9, 0.8, z), 1.6, 0.8)
        p.box((0.9, 0.5, 0.1), (s * 1.4, 1.9, -4.53), V_HEAD, bevel=0.04)
        p.box((0.8, 0.35, 0.1), (s * 1.5, 2.15, 4.53), V_TAIL, bevel=0.03)
        p.box((0.02, 0.05, 6.2), (s * 2.212, 2.35, 0.2), V_HL, bevel=0)  # shoulder highlight
        p.box((0.02, 1.2, 0.05), (s * 2.212, 1.75, 0.6), V_INK, bevel=0)  # door seam
        p.box((0.06, 0.1, 0.4), (s * 2.24, 2.15, 0.0), V_DARK, bevel=0.02)  # handle
        p.box((0.32, 0.26, 0.36), (s * 2.3, 2.85, -1.75), PAINT, bevel=0.06)  # mirror
    for z in (-1, 1):
        p.box((4.5, 0.35, 0.3), (0, 1.05, z * 4.55), V_DARK, bevel=0.08)  # bumpers
    p.box((1.6, 0.36, 0.06), (0, 1.55, -4.54), V_DARK, bevel=0.02)  # grille
    # the glass cabin, as the old block had it, with a thin frame and two glints
    p.prism([(-2.0, 2.58), (-1.2, 4.0), (2.3, 4.0), (3.0, 2.58)], 4.0, (0, 0, 0), "364A66", bevel=0.1)
    for s in (-1, 1):
        p.box((0.12, 0.12, 5.1), (s * 2.0, 2.66, 0.5), V_DARK, bevel=0)
    for x, ln in ((0.8, 1.2), (1.15, 0.8)):
        p.box((0.1, 0.02, ln), (x, 3.32, -1.62), V_HL, rot=(-60, 0, 0), bevel=0)
    p.finish()


def city_car():
    """City.luau car(): 4 wide, 10 long; a black chassis row with the wheels at z 4 (y 0..2), the
    painted body (y 2..4), a tinted glass cabin z -3..3 (y 4..6). Roof pieces: a taxi sign, police lights."""
    p = Piece("City_Car", exact=True)
    p.prism(arched(5.0, 1.5, 3.75, 4.0, (-4.0, 4.0), 1.15, 1.0, nose=0.35) + [(-3.0, 4.0)], 4.0, (0, 0, 0), PAINT, bevel=0.15)
    p.box((3.4, 1.0, 5.4), (0, 1.1, 0), V_DARK, bevel=0.06)  # the old black chassis row between the wheels
    for s in (-1, 1):
        for z in (-4.0, 4.0):
            wheel(p, (s * 1.5, 1.0, z), 2.0, 1.0)
        p.box((1.0, 0.45, 0.1), (s * 1.3, 3.15, -5.03), V_HEAD, bevel=0.04)
        p.box((0.8, 0.4, 0.1), (s * 1.4, 3.3, 5.03), V_TAIL, bevel=0.03)
        p.box((0.02, 0.05, 7.0), (s * 2.012, 3.7, 0.0), V_HL, bevel=0)
        for z in (-2.6, 0.2, 2.9):
            p.box((0.02, 2.0, 0.05), (s * 2.012, 2.7, z), V_INK, bevel=0)  # door seams
        p.box((0.06, 0.12, 0.45), (s * 2.04, 3.25, -1.3), V_DARK, bevel=0.02)
        p.box((0.06, 0.12, 0.45), (s * 2.04, 3.25, 1.5), V_DARK, bevel=0.02)
        p.box((0.3, 0.28, 0.4), (s * 2.12, 4.3, -2.6), PAINT, bevel=0.06)
    for z in (-1, 1):
        p.box((4.1, 0.4, 0.35), (0, 1.75, z * 5.05), V_DARK, bevel=0.1)
    p.box((2.0, 0.4, 0.06), (0, 2.5, -5.04), V_DARK, bevel=0.02)
    p.prism([(-3.0, 3.98), (-2.3, 6.0), (2.5, 6.0), (3.0, 3.98)], 3.8, (0, 0, 0), "1E2634", bevel=0.12)
    for s in (-1, 1):
        p.box((0.12, 0.12, 6.1), (s * 1.9, 4.05, 0.0), V_DARK, bevel=0)
        p.box((0.12, 1.95, 0.25), (s * 1.9, 5.0, 0.1), V_DARK, bevel=0)  # B pillar
    for x, ln in ((0.7, 1.4), (1.1, 0.9)):
        p.box((0.1, 0.02, ln), (x, 5.05, -2.72), V_HL, rot=(-71, 0, 0), bevel=0)
    p.finish()

    p = Piece("City_TaxiSign", exact=True)  # the old white light cube on the roof, as a sign
    p.box((1.8, 0.65, 0.8), (0, 6.33, 0), "F4F4E6", bevel=0.12)
    for side in (-1, 1):
        text_z(p, "TAXI", 1.3, 0.04, (0, 6.33, side * 0.41), V_INK, side)
    p.finish()

    p = Piece("City_PoliceLights", exact=True)  # the old blue and red cubes over the roof
    p.box((3.4, 0.2, 0.8), (0, 6.1, 0), V_DARK, bevel=0.05)
    p.box((1.2, 0.5, 0.75), (-1.0, 6.45, 0), "3060FF", bevel=0.1)
    p.box((1.2, 0.5, 0.75), (1.0, 6.45, 0), "FF3030", bevel=0.1)
    p.finish()


def city_bus():
    """City.luau Bus: 6 wide, 22 long, 8 high; black chassis row with wheels at x 2, z 6; a blue band,
    a tinted window band, a white roof."""
    p = Piece("City_Bus", exact=True)
    p.prism(arched(11.0, 1.4, 4.0, 4.0, (-6.0, 6.0), 1.2, 1.0, nose=0.15), 6.0, (0, 0, 0), "2850BE", bevel=0.18)
    p.box((5.2, 1.0, 17.6), (0, 1.15, 0), V_DARK, bevel=0.05)
    for s in (-1, 1):
        for z in (-6.0, 6.0):
            wheel(p, (s * 2.4, 1.0, z), 2.0, 1.0)
    p.box((5.95, 2.0, 21.95), (0, 5.0, 0), "1E2634", bevel=0.1)  # window band
    p.box((6.0, 2.0, 22.0), (0, 7.0, 0), "E8E8E2", bevel=0.4)  # roof
    for s in (-1, 1):
        for z in range(-9, 10, 3):
            p.box((0.08, 2.0, 0.3), (s * 2.99, 5.0, z), "E8E8E2", bevel=0)  # window posts
        p.box((0.02, 0.06, 20.5), (s * 3.012, 3.7, 0), V_HL, bevel=0)
        p.box((1.0, 0.45, 0.1), (s * 2.1, 2.6, -11.03), V_HEAD, bevel=0.04)
        p.box((0.8, 0.5, 0.1), (s * 2.2, 2.8, 11.03), V_TAIL, bevel=0.03)
    p.box((0.06, 3.1, 1.6), (3.02, 3.0, -8.2), "1E2634", bevel=0.02)  # the door, curb side
    p.box((0.07, 3.1, 0.06), (3.04, 3.0, -8.2), V_INK, bevel=0)
    for z in (-1, 1):
        p.box((6.1, 0.5, 0.4), (0, 1.6, z * 11.05), V_DARK, bevel=0.12)
    p.box((3.6, 0.7, 0.08), (0, 6.5, -11.04), V_DARK, bevel=0.03)  # destination sign
    text_z(p, "CITY", 2.4, 0.04, (0, 6.5, -11.1), "FF8A20", -1)
    for x, ln in ((-1.6, 1.4), (-1.1, 0.9)):
        p.box((0.1, ln, 0.02), (x, 5.0, -11.0), V_HL, rot=(0, 0, 25), bevel=0)
    p.finish()


def park_boat():
    """Map.luau boats: a 5 x 1.6 x 12 red wooden hull (y -0.4..1.2) with a plank seat across it."""
    p = Piece("Park_Boat", exact=True)
    hull, plank = "C44834", "966E46"
    loops = []
    for z, half in ((-6.0, 0.05), (-5.3, 1.3), (-4.2, 2.1), (-2.6, 2.5), (0, 2.5), (3.5, 2.5), (6.0, 2.3)):
        lo = max(0.05, half * 0.6)
        loops.append([(-half, 1.2, z), (-half * 0.92, 0.2, z), (-lo, -0.4, z), (lo, -0.4, z), (half * 0.92, 0.2, z), (half, 1.2, z)])
    faces = p._solid(loops, (0, 0, 0), hull, (0, 0, 0), closed=False)
    # the cross-sections are closed (their top edge is the deck), so only the bow and the stern need capping
    for loop in (loops[0], loops[-1]):
        faces.append(p.bm.faces.new([p.bm.verts.new(R2B @ Vector(v)) for v in loop]))
    bmesh.ops.remove_doubles(p.bm, verts=list({v for f in faces for v in f.verts}), dist=0.001)
    i = p._col(hull)
    for f in faces:
        if f.is_valid:
            f.material_index = i
    for z in (-3.0, -1.0, 1.0, 3.0, 5.0):  # deck planks and the seat
        p.box((4.6 if z > -2 else 3.8, 0.06, 1.7), (0, 1.23, z), plank, bevel=0)
        p.box((4.62 if z > -2 else 3.82, 0.07, 0.04), (0, 1.235, z + 0.86), V_INK, bevel=0)
    p.box((4.6, 0.4, 1.4), (0, 1.4, 0), plank, bevel=0.08)
    for s in (-1, 1):
        p.box((0.02, 0.05, 9.0), (s * 2.52, 0.75, 0.8), V_INK, bevel=0)  # plank seams down the side
        p.box((0.02, 0.05, 7.5), (s * 2.52, 0.2, 1.4), V_INK, bevel=0)
        p.box((0.02, 0.06, 8.0), (s * 2.52, 1.05, 1.2), V_HL, bevel=0)
    p.finish()


def factory_forklift():
    """Factory.luau Forklift (cube units of 4): a yellow body 4 x 4 x 12, a dark seat on it, a dark
    overhead guard to y 16, the steel mast in front (z -8..-6, to y 14), chrome forks to z -12."""
    p = Piece("Factory_Forklift", exact=True)
    yellow, dark, steel, chrome = "EBB91E", "26282E", "464A52", "BEBEC3"
    p.prism([(6.0, 3.6), (6.0, 0.9), (4.9, 0.6), (-5.8, 0.6), (-6.0, 1.0), (-6.0, 3.6), (-5.6, 4.0), (5.6, 4.0)], 4.0, (0, 0, 0), yellow, bevel=0.25)
    p.box((3.6, 1.6, 2.4), (0, 4.6, 4.6), yellow, bevel=0.4)  # counterweight hump at the back
    for s in (-1, 1):
        for z, d in ((-3.8, 2.6), (3.6, 2.2)):
            wheel(p, (s * 1.75, d / 2, z), d, 0.9, hub="2A2A30")
        p.box((0.02, 0.06, 10.5), (s * 2.012, 3.6, 0), V_HL, bevel=0)
        for z in (-1.0, -0.8, -0.6):
            p.box((0.02, 0.9, 0.05), (s * 2.012, 2.0, z * 4), V_INK, bevel=0)  # hatching
    for x in (-1, 1):  # black and yellow chevrons on the back
        p.box((0.5, 2.2, 0.06), (x * 1.1, 2.2, 6.04), V_INK, rot=(0, 0, 30 * x), bevel=0)
    p.box((2.6, 0.8, 2.6), (0, 4.5, 2.0), dark, bevel=0.2)  # seat
    p.box((2.6, 2.4, 0.6), (0, 5.8, 3.3), dark, bevel=0.2)
    p.cyl(1.2, 0.12, (0, 6.0, -0.6), dark, axis="z", rot=(-35, 0, 0), segs=14)  # steering wheel
    p.box((0.2, 1.6, 0.2), (0, 5.0, -0.3), dark, rot=(-35, 0, 0), bevel=0.03)
    for x in (-1.75, 1.75):  # overhead guard: four posts and a slatted roof
        for z in (-1.8, 3.6):
            p.box((0.4, 8.4, 0.4), (x, 8.2, z), dark, bevel=0.06)
    p.box((4.0, 0.4, 6.4), (0, 12.6, 0.9), dark, bevel=0.12)
    for z in range(-1, 4):
        p.box((3.4, 0.12, 0.35), (0, 12.86, z * 1.1), steel, bevel=0)
    p.cyl(0.6, 0.6, (1.2, 13.2, 3.4), "FF8A20", segs=12, bevel=0.06)  # warning beacon
    for x in (-1.4, 1.4):  # mast: two channels with cross bars, the carriage, the forks
        p.box((0.6, 14.0, 0.8), (x, 7.0, -7.0), steel, bevel=0.08)
    for y in (2.0, 7.0, 13.4):
        p.box((3.4, 0.4, 0.5), (0, y, -7.0), steel, bevel=0.06)
    p.box((4.0, 2.2, 0.4), (0, 1.7, -7.6), dark, bevel=0.08)
    for x in (-1.1, 1.1):
        p.box((0.7, 0.35, 4.4), (x, 0.4, -9.8), chrome, bevel=0.05)
        p.box((0.7, 2.0, 0.35), (x, 1.2, -7.9), chrome, bevel=0.05)
    p.finish()


VEHICLE_PIECES = ("Park_Car", "City_Car", "City_TaxiSign", "City_PoliceLights", "City_Bus", "Park_Boat", "Factory_Forklift")


def vehicles():
    park_car()
    city_car()
    city_bus()
    park_boat()
    factory_forklift()
    for i, n in enumerate(VEHICLE_PIECES):
        bpy.data.objects[n].location = (80 + (i % 4) * 14, (i // 4) * 26, 0)
    for n in ("City_TaxiSign", "City_PoliceLights"):
        bpy.data.objects[n].location = bpy.data.objects["City_Car"].location


# ---------------------------------------------------------------- Bandages -------------------
# What a Medic (server Body.bandage) wraps a stump in, once a limb is gone. Modelled in STUMP space,
# not on a body part: the origin is the cut, +Y points out where the limb was, and the limb is 1 stud
# across in X and Z, so the game scales X / Z to the part it sits on (any arm or leg fits).
#  * Bandage_Stump: a limb end (wrist, elbow, ankle, knee): overlapping turns of crepe up the limb
#    and recurrent turns folded over the rounded end, as a stump is really dressed; tucked tail, clip.
#  * Bandage_Socket: the shoulder or hip (the limb gone at the torso): a domed gauze pad on a square
#    dressing, held with crossed strips of tape.
GAUZE, GAUZE_SHADE, TAPE, CLIP = "F1EDE3", "D9D1BF", "EDE3C8", "AEB4BE"


def bandages():
    p = Piece("Bandage_Stump", exact=True)
    p.cyl((1.05, 1.05), 0.74, (0, -0.39, 0), GAUZE_SHADE, segs=20)  # the under layer: no skin between the turns
    for i in range(5):  # the turns up the limb, each a little wider and tilted the other way
        d = 1.07 + 0.012 * i
        p.cyl((d, d), 0.17, (0, -0.66 + i * 0.13, 0), GAUZE if i % 2 == 0 else GAUZE_SHADE,
              rot=(9 * (-1) ** i, 0, 6 * (-1) ** (i + 1)), segs=20)
    p.ball((1.1, 0.64, 1.1), (0, -0.04, 0), GAUZE, cut=0.5, segs=20, rings=10)  # over the end
    for a in (0, 60, 120):  # recurrent turns crossing over the end
        p.ball((0.24, 0.7, 1.15), (0, -0.04, 0), GAUZE_SHADE, rot=(0, a, 0), cut=0.5, segs=12, rings=8)
    p.box((0.34, 0.2, 0.035), (0.08, -0.5, -0.565), GAUZE_SHADE, rot=(0, 0, 14), bevel=0.01)  # the tail
    p.box((0.17, 0.1, 0.04), (-0.12, -0.5, -0.585), CLIP, bevel=0.01)  # its clip
    p.box((0.1, 0.36, 0.03), (0.2, -0.47, -0.575), TAPE, bevel=0.01)  # tape over the tail
    p.finish()

    p = Piece("Bandage_Socket", exact=True)
    p.box((1.3, 0.05, 1.3), (0, 0.0, 0), GAUZE_SHADE, bevel=0.02)  # the dressing square
    p.ball((1.1, 0.56, 1.1), (0, 0.0, 0), GAUZE, cut=0.5, segs=20, rings=10)  # the pad
    for a in (45, -45):  # crossed tape
        p.ball((0.2, 0.62, 1.55), (0, 0.0, 0), TAPE, rot=(0, a, 0), cut=0.5, segs=12, rings=8)
    p.finish()


# ---------------------------------------------------------------- Casts ----------------------
# A plaster cast on a broken arm or leg (server Body.cast: a Medic or the player's Cast item), and what
# comes with it: an arm in a cast rides in a sling (Sling_*: the arm held bent across the chest, welded
# there in the game so it never swings: SLING_POSE), a leg in a cast is held stiff and the dummy goes
# on crutches (Crutch, one in each hand).
#
# The cast is a SHELL of the dummy's own body mesh (dummy_body.obj, the Roblox Boy parts the game uses):
# smoothed once, pushed out CAST_T along its normals, cut off with planes where the cast ends and closed
# back to the skin round each cut, so it follows the real hand (the thumb, the heel of the hand, the
# knuckles), the elbow and the ankle instead of a tube round a box. One piece per body part, in that
# part's space. Where the cast ends at the skin the stockinette under it is folded back over the edge:
# a rolled cotton lip. The plaster carries a texture (cast_texture.py: weave, turns, what friends wrote
# on it), UV-mapped round the limb (u) and along it (v, CAST_V: each piece its own stretch of the image).
PLASTER, COTTON, SHOE_GREY, SHOE_SOLE, VELCRO, BUCKLE = "F3F0E8", "F7F6F1", "4A505A", "2A2D33", "353A44", "AEB4BE"
CAST_T = 0.06  # studs of plaster over the skin
CAST_V = {"UpperArm": 0.0, "LowerArm": 1.0, "Hand": 2.1, "UpperLeg": 2.9, "LowerLeg": 4.0, "Foot": 5.2}  # studs into the image
AXIS = {"x": 0, "y": 1, "z": 2}
# what of each part the long cast covers, in the part's space: (axis, keep from, keep to; None: the
# part's own end), and the cut that shows (the stockinette lip): (axis, value, +1/-1 out of the cast)
CAST_CUTS = {
    "UpperArm": (("y", None, 0.14), ("y", 0.14, 1)),  # from the elbow to mid upper arm
    "LowerArm": (None, None),
    "Hand": (("y", 0.1, None), ("y", 0.1, -1)),  # the wrist and the heel of the hand, the fingers and thumb free
    "UpperLeg": (("y", None, 0.16), ("y", 0.16, 1)),  # from the knee to mid thigh
    "LowerLeg": (None, None),
    "Foot": (("z", -0.3, None), ("z", -0.3, -1)),  # heel to the ball of the foot, the toes out (front is -Z)
}


def body_shell(p, part, t, h, keep=None, lip=None, close=None, xf=None, smooth=0.5, clip=None):
    """Body part `part`'s own mesh as a shell `t` studs off the skin, kept to `keep` (axis, lo, hi in
    Roblox part space), each cut closed back to the skin (colour `close`, else `h`), the `lip` cut
    (axis, value, out) with a rolled cotton lip. `clip`: (point, normal), Roblox part space: all past
    that plane goes too. `xf`: a Roblox-space Matrix it is moved by after."""
    _, vs, fs, _ = _body(part)
    bm = bmesh.new()
    bv = [bm.verts.new(R2B @ v) for v in vs]
    for f in fs:
        try:
            bm.faces.new([bv[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=2e-4)  # stored per face corner: weld it
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if smooth:  # one rounder step: plaster is smoother than the faceted skin under it
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True, smooth=smooth)
    if keep:
        axis, lo, hi = keep
        for val, sign in ((lo, -1), (hi, 1)):
            if val is None:
                continue
            n, c = Vector((0, 0, 0)), Vector((0, 0, 0))
            n[AXIS[axis]], c[AXIS[axis]] = sign, val
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=R2B @ c,
                                   plane_no=R2B @ n, clear_outer=True)
    if clip:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=R2B @ clip[0],
                               plane_no=R2B @ clip[1], clear_outer=True)
    bm.normal_update()
    skin = {v: (v.co.copy(), v.normal.copy()) for v in bm.verts}
    for v in bm.verts:
        v.co += v.normal * t
    col, edge_col, lip_col = p._col(h), p._col(close or h), p._col(COTTON)
    for f in bm.faces:
        f.material_index = col
    out = None
    if lip:
        out = Vector((0, 0, 0))
        out[AXIS[lip[0]]] = lip[2]
        out = R2B @ out

    def on_lip(v):
        return lip is not None and abs((R2B @ skin[v][0])[AXIS[lip[0]]] - lip[1]) < 3e-3

    # round each cut: a chain of new rings from the shell's edge back down to the skin
    chains = {}
    for e in [e for e in bm.edges if e.is_boundary]:
        for v in e.verts:
            if v in chains:
                continue
            base, n = skin[v]
            if on_lip(v):  # folded back over the plaster's edge and down to the skin past it
                pts = [base + n * (t + 0.018) + out * 0.022, base + n * (t * 0.55) + out * 0.05, base + n * 0.005 + out * 0.055]
            else:
                pts = [base + n * 0.004]
            chains[v] = [v] + [bm.verts.new(q) for q in pts]
    for e in [e for e in bm.edges if e.is_boundary and len(e.link_faces) == 1]:
        a, b = chains[e.verts[0]], chains[e.verts[1]]
        lipped = len(a) == len(b) == 4
        if len(a) != len(b):
            a, b = a[:2], b[:2]
        for k in range(len(a) - 1):
            try:
                f = bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
            except ValueError:
                continue
            f.material_index = lip_col if lipped else edge_col
    if xf is not None:
        m = R2B.to_4x4() @ xf @ R2B.to_4x4()
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
    vmap = {v: p.bm.verts.new(v.co) for v in bm.verts}
    for f in bm.faces:
        nf = p.bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = f.material_index
    bm.free()


def casts():
    made = []
    for side in ("Left", "Right"):
        for part, (keep, lip) in CAST_CUTS.items():
            p = Piece(f"Cast_{side}{part}", exact=True)
            body_shell(p, side + part, CAST_T, PLASTER, keep, lip)
            out = -1 if side == "Left" else 1  # the outer side
            if part == "Foot":  # in a cast shoe: a rocker sole with tread, two velcro straps with D-rings
                sx, sy, sz = R15["Foot"]
                bottom = -sy / 2 - CAST_T
                p.box((sx * 0.92, 0.1, sz * 0.8), (0, bottom - 0.05, 0.1), SHOE_SOLE, bevel=0.045)
                for i in range(5):
                    p.box((sx * 0.86, 0.03, 0.06), (0, bottom - 0.105, -0.2 + i * 0.16), SHOE_GREY, bevel=0.01)
                body_shell(p, side + part, CAST_T + 0.03, VELCRO, ("z", -0.27, -0.13))  # over the forefoot
                p.box((0.035, 0.14, 0.1), ((sx / 2 + CAST_T + 0.03) * out, -0.06, -0.2), BUCKLE, bevel=0.01)
            elif part == "LowerLeg":  # and the shoe's other strap, round the ankle (the shin's cast hides the foot's there)
                body_shell(p, side + part, CAST_T + 0.03, VELCRO, ("y", -0.52, -0.38))
                p.box((0.035, 0.1, 0.14), ((R15["LowerLeg"][0] / 2 + CAST_T + 0.04) * out, -0.45, 0), BUCKLE, bevel=0.01)
            made.append((p.finish(), part))
    for ob, part in made:
        _cast_uv(ob, part)
    return [ob.name for ob, _ in made]


# -- the sling ---------------------------------------------------------------------------------
# The arm in a cast is held bent across the chest. SLING_POSE: where the arm's parts sit against the
# UpperTorso (Roblox CFrames, worked out here on the real body meshes, the left one mirrored), copied
# into the game (server Body.SLING, which welds the arm there: printed by sling_luau()). The sling, one
# piece in UpperTorso space: a fabric pouch cradling the forearm from the elbow to past the wrist (a
# shell of the forearm, over the cast, its top cut off level), its edge piped white, and a padded strap
# from the pouch's wrist end up to the neck, round the back of it and down to the elbow end.
SLING, SLING_DARK, SLING_HEM, STRAP_BLACK = "2F5DA8", "22467F", "E8EEF6", "1E2228"
# the joints' pivots on the standing dummy (against the UpperTorso, right side): Roblox R15 rig
# attachments, measured against the body meshes (RIG)
S_PIVOT, E_PIVOT, W_PIVOT = Vector((1.0, 0.56, 0.06)), Vector((1.25, -0.3, 0.12)), Vector((1.35, -0.84, 0.1))
# where the upper arm and the forearm point, held in the sling (right arm, UpperTorso axes; front is -Z):
# the upper arm down the side, a little forward; the forearm across the front of the belly, the hand a
# little higher than the elbow
SLING_UPPER, SLING_FORE = Vector((0.06, -1.0, -0.42)), Vector((-0.78, 0.1, -0.62))


def sling_pose(side="Right"):
    """{part: Matrix}: the slung arm's parts against the UpperTorso (Roblox space). The shoulder turns
    the arm so the elbow's hinge (the forearm swings about the upper arm's X) bends it onto SLING_FORE."""
    T = Matrix.Translation
    rig = {k: Vector(RIG["Right" + k]) for k in ("UpperArm", "LowerArm", "Hand")}
    rest_u = (E_PIVOT - S_PIVOT).normalized()
    u, f = SLING_UPPER.normalized(), SLING_FORE.normalized()
    y, z = -u, -(f - u * f.dot(u)).normalized()
    turn = Matrix((y.cross(z), y, z)).transposed()  # local axes: -Y down the arm, -Z where the forearm goes
    rest = Matrix(((1, 0, 0), (0, 1, 0), (0, 0, 1)))
    yr = -rest_u
    zr = Vector((0, 0, 1)) - yr * yr.z
    zr.normalize()
    rest = Matrix((yr.cross(zr), yr, zr)).transposed()  # the hanging arm's own frame
    shoulder = (turn @ rest.inverted()).to_4x4()
    elbow = Matrix.Rotation(math.acos(max(-1, min(1, f.dot(u)))), 4, "X")
    up = T(S_PIVOT) @ shoulder @ T(rig["UpperArm"] - S_PIVOT)
    lo = up @ T(E_PIVOT - rig["UpperArm"]) @ (rest.to_4x4() @ elbow @ rest.inverted().to_4x4()) @ T(rig["LowerArm"] - E_PIVOT)
    hand = lo @ T(rig["Hand"] - rig["LowerArm"])  # the wrist held straight in the cast
    out = {"UpperArm": up, "LowerArm": lo, "Hand": hand}
    if side == "Left":
        S = Matrix.Diagonal((-1, 1, 1, 1))
        out = {k: S @ m @ S for k, m in out.items()}
    return out


def sling_luau():
    """The Body.SLING table for the server, from SLING_POSE."""
    def cf(m):
        nums = list(m.translation) + [m[i][j] for i in range(3) for j in range(3)]
        return "CFrame.new(" + ", ".join(f"{x:.4f}" for x in nums) + ")"
    lines = []
    for side in ("Left", "Right"):
        pose = sling_pose(side)
        lines.append(f"\t{side} = {{ " + ", ".join(f"{k} = {cf(pose[k])}" for k in ("UpperArm", "LowerArm", "Hand")) + " },")
    return "Body.SLING = {\n" + "\n".join(lines) + "\n}"


def _band(p, pts, normals, width, thick, h):
    """A flat strap through `pts` (Roblox space), its face turned out along `normals`."""
    loops = []
    for i, (c, n) in enumerate(zip(pts, normals)):
        tng = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        across = tng.cross(n).normalized()
        n = across.cross(tng).normalized()
        w, d = across * width / 2, n * thick / 2
        loops.append([tuple(c - w - d), tuple(c + w - d), tuple(c + w + d), tuple(c - w + d)])
    p._solid(loops, (0, 0, 0), h, (0, 0, 0), closed=False)
    i = p._col(h)
    for loop in (loops[0], loops[-1]):
        vs = [p.bm.verts.new(R2B @ Vector(q)) for q in loop]
        p.bm.faces.new(vs).material_index = i


def _spline(ctrl, step):
    """Catmull-Rom through the control points, about `step` studs apart."""
    out = []
    pts = [ctrl[0]] + ctrl + [ctrl[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        n = max(2, int((p2 - p1).length / step))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(ctrl[-1])
    return out


def sling(side):
    from mathutils.bvhtree import BVHTree
    s = 1 if side == "Right" else -1
    pose = sling_pose(side)
    lo = pose["LowerArm"]
    p = Piece(f"Sling_{side}", exact=True)
    # the pouch: the forearm's shell over the cast, all of it above a level plane a little over the
    # arm's middle gone (world up, brought into the forearm's space)
    up = (lo.to_3x3().inverted() @ Vector((0, 1, 0))).normalized()
    body_shell(p, side + "LowerArm", CAST_T + 0.06, SLING, close=SLING_HEM, xf=lo, clip=(up * 0.08, up))
    # the strap: the pouch's wrist end, up the chest to the neck on the good side, round the back of the
    # neck, down the hurt side to the elbow end; laid on the torso's surface where it touches it
    _, vs, fs, _ = _body("UpperTorso")
    tree = BVHTree.FromPolygons(vs, fs)
    wrist = lo @ Vector((0, -0.38, 0))
    elbow = lo @ Vector((0, 0.42, 0))
    ctrl = [wrist + Vector((0, 0.2, 0)), Vector((-0.35 * s, 0.55, -0.66)), Vector((-0.36 * s, 0.93, -0.3)),
            Vector((-0.3 * s, 1.0, 0.12)), Vector((0.0, 0.98, 0.38)), Vector((0.3 * s, 1.0, 0.12)),
            Vector((0.4 * s, 0.93, -0.3)), Vector((0.5 * s, 0.55, -0.66)), elbow + Vector((0, 0.2, 0))]
    pts, nrm = [], []
    for q in _spline(ctrl, 0.06):
        loc, n, _, dist = tree.find_nearest(q)
        if loc is not None and dist < 0.22:
            pts.append(loc + n * 0.04)
            nrm.append(n)
        else:
            pts.append(q)
            nrm.append((q - Vector((0, 0.3, 0))).normalized())
    _band(p, pts, nrm, 0.2, 0.04, SLING_DARK)
    _band(p, pts[len(pts) // 3: 2 * len(pts) // 3], nrm[len(pts) // 3: 2 * len(pts) // 3], 0.26, 0.07, SLING_HEM)  # the neck pad
    # the buckle where the strap meets the pouch's wrist end
    i = 4
    tng = (pts[i + 1] - pts[i - 1]).normalized()
    m = Matrix((nrm[i].cross(tng).normalized(), tng, nrm[i])).transposed()
    rot = tuple(math.degrees(a) for a in m.to_euler("XYZ"))
    p.box((0.27, 0.17, 0.05), tuple(pts[i] + nrm[i] * 0.03), STRAP_BLACK, rot=rot, bevel=0.02)
    p.box((0.15, 0.06, 0.03), tuple(pts[i] + nrm[i] * 0.06), BUCKLE, rot=rot, bevel=0.01)
    return p.finish()


# -- the crutches ------------------------------------------------------------------------------
# A forearm crutch, in the HAND's space (one piece for either hand, the dummy's arm hanging): the moulded
# handle goes through the fist front to back, the aluminium shaft drops from behind it to a ridged rubber
# ferrule on the ground (CRUTCH_DROP below the fist) and rises behind the forearm to the cuff, a C of
# plastic round the back of the forearm below the elbow. The lower tube telescopes into the upper one
# (a lock ring, its push-button holes showing).
ALU, ALU_DARK, CRUTCH_BLUE, GRIP_GREY, RUBBER = "B8BEC8", "7C838F", "2F6BD8", "3A3F48", "1A1C20"
CRUTCH_GRIP = Vector((0.0, -0.1, -0.04))  # the middle of the fist's hole (hand space; x 0: either hand)
CRUTCH_DROP = 2.0  # studs from the fist down to the tip


def _tube(p, a, b, d, h, segs=12):
    dirv = (b - a).normalized()
    e = Vector((0, 1, 0)).rotation_difference(dirv).to_euler("XYZ")
    p.cyl(d, (b - a).length, tuple((a + b) / 2), h, rot=tuple(math.degrees(x) for x in e), segs=segs)


def crutch():
    p = Piece("Crutch", exact=True)
    g = CRUTCH_GRIP
    back = g + Vector((0, 0, 0.3))  # the shaft, behind the fist
    tip = back + Vector((0, -CRUTCH_DROP, 0))
    mid = back + Vector((0, -0.85, 0))  # where the lower tube goes into the upper one
    cuff_c = Vector((0.0, 0.8, 0.1))  # the forearm's axis where the cuff holds it (hand space)
    rx, rz = 0.33, 0.33
    top = cuff_c + Vector((0, -0.2, rz + 0.03))
    # the handle through the fist, a blue collar where it meets the shaft
    p.cyl((0.15, 0.13), 0.5, tuple(g + Vector((0, 0, 0.03))), GRIP_GREY, axis="z", segs=14, bevel=0.025)
    p.box((0.18, 0.3, 0.16), tuple(back + Vector((0, 0.02, 0))), CRUTCH_BLUE, bevel=0.04)
    # the shaft: the upper tube down to the lock ring, the lower one telescoped in, its holes
    _tube(p, back, mid, 0.12, ALU)
    _tube(p, mid, tip + Vector((0, 0.18, 0)), 0.1, ALU_DARK)
    p.cyl(0.15, 0.06, tuple(mid), CRUTCH_BLUE, segs=14, bevel=0.01)
    for i in range(5):
        p.cyl(0.03, 0.03, (back.x, mid.y - 0.16 - i * 0.12, back.z - 0.045), RUBBER, axis="z", segs=8)
    # the ferrule, ridged
    p.cyl(0.15, 0.22, tuple(tip + Vector((0, 0.11, 0))), RUBBER, segs=14, bevel=0.03)
    for k in range(3):
        p.cyl(0.17, 0.03, tuple(tip + Vector((0, 0.05 + k * 0.06, 0))), RUBBER, segs=14)
    # up behind the forearm to the cuff
    _tube(p, back, top, 0.12, ALU)
    # the cuff: a C round the back of the forearm, open in front, a thick rolled rim
    loops = []
    for k in range(17):
        a = math.radians(-120 + 240 * k / 16)  # 0: straight back (+Z)
        sa, ca = math.sin(a), math.cos(a)
        loops.append([(cuff_c.x + (rx + dr) * sa, cuff_c.y + dy, cuff_c.z + (rz + dr) * ca)
                      for dr, dy in ((0.0, -0.12), (0.05, -0.12), (0.05, 0.12), (0.0, 0.12))])
    p._solid(loops, (0, 0, 0), CRUTCH_BLUE, (0, 0, 0), closed=False)
    i = p._col(CRUTCH_BLUE)
    for loop in (loops[0], loops[-1]):
        p.bm.faces.new([p.bm.verts.new(R2B @ Vector(q)) for q in loop]).material_index = i
    p.box((0.14, 0.26, 0.07), tuple(top + Vector((0, 0.06, -0.01))), CRUTCH_BLUE, bevel=0.025)  # its mount
    return p.finish()


def medical():
    """The casts, both slings and the crutch."""
    return casts() + [sling("Right").name, sling("Left").name, crutch().name]


def _cast_uv(ob, part):
    """UVs for the plaster: u once round the limb (the image tiles across), v along it (cast_texture.py)."""
    me = ob.data
    uv = me.uv_layers.new(name="UVMap")
    plaster = next(i for i, m in enumerate(me.materials) if m.name == PLASTER)
    foot = part == "Foot"
    for poly in me.polygons:
        if poly.material_index != plaster:
            continue
        us, vs = [], []
        for li in poly.loop_indices:
            x, y, z = R2B @ me.vertices[me.loops[li].vertex_index].co  # Roblox space
            along, a, b = (z, x, y) if foot else (y, x, z)
            us.append((math.atan2(a, b) / (2 * math.pi)) % 1.0)
            vs.append((CAST_V[part] + along + 0.8) / 6.0)
        if max(us) - min(us) > 0.5:  # across the seam: keep the face whole (the texture tiles)
            us = [u + 1 if u < 0.5 else u for u in us]
        for li, u, v in zip(poly.loop_indices, us, vs):
            uv.data[li].uv = (u, v)
    m = me.materials[plaster]
    nodes, links = m.node_tree.nodes, m.node_tree.links
    if not any(n.type == "TEX_IMAGE" for n in nodes):
        path = os.path.join(REPO, "assets", "army", "cast_plaster.png") if REPO else bpy.path.abspath("//cast_plaster.png")
        img = bpy.data.images.load(path, check_existing=True)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        links.new(tex.outputs["Color"], bsdf.inputs[0])


PREFIXES = ("Soldier_", "Heavy_", "Worker_", "Zombie_", "Heli_", "Baton", "Cop_", "Sport_", "Park_", "City_", "Factory_", "Tank_", "Bandage_", "Cast_", "Sling_", "Crutch")


def build_all():
    for ob in list(bpy.data.objects):
        if ob.name in ("Cube",) or ob.name.startswith(PREFIXES + ("_wheel_view",)):
            bpy.data.objects.remove(ob)
    soldier()
    heavy()
    worker()
    zombie()
    helicopter()
    baton()
    police_car()
    sport_car()
    vehicles()
    tank()
    bandages()
    medical()
    # lay them out for a look (object origins stay at the attach point; only the display moves)
    x = 0
    for prefix in ("Soldier_", "Heavy_", "Worker_", "Zombie_"):
        for ob in bpy.data.objects:
            if ob.name.startswith(prefix):
                part = ob.name[len(prefix):]
                ob.location = Vector((x, 0, 0)) + R2B @ Vector(RIG.get(part, (0, 0, 0)))
        x -= 4
    bpy.data.objects["Heli_Body"].location = (12, 0, 4)
    bpy.data.objects["Heli_Rotor"].location = Vector((12, 0, 4)) + R2B @ Vector(ROTOR_PIVOT)
    bpy.data.objects["Heli_TailRotor"].location = Vector((12, 0, 4)) + R2B @ Vector(TAIL_PIVOT)
    bpy.data.objects["Baton"].location = (4, 0, 0.5)
    bpy.data.objects["Cop_Body"].location = (40, 0, 0)
    for i, (x, z) in enumerate(((1, 0), (1, 1), (-1, 0), (-1, 1))):  # a look at all four wheels
        w = bpy.data.objects["Cop_Wheel"] if i == 0 else bpy.data.objects["Cop_Wheel"].copy()
        if i:
            bpy.context.scene.collection.objects.link(w)
            w.name = "_wheel_view"
        w.location = Vector((40, 0, 0)) + R2B @ Vector((x * WHEEL_AT[z][0], WHEEL_AT[z][1], WHEEL_AT[z][2]))
        w.rotation_euler = (0, 0, 0 if x > 0 else math.pi)
    for n in SPORT_PIECES:
        bpy.data.objects[n].location = (60, 0, 0)
    for i, (x, z) in enumerate(((1, 0), (1, 1), (-1, 0), (-1, 1))):
        w = bpy.data.objects["Sport_Wheel"] if i == 0 else bpy.data.objects["Sport_Wheel"].copy()
        if i:
            bpy.context.scene.collection.objects.link(w)
            w.name = "_wheel_view"
        w.location = Vector((60, 0, 0)) + R2B @ Vector((x * SPORT_WHEEL_AT[z][0], SPORT_WHEEL_AT[z][1], SPORT_WHEEL_AT[z][2]))
        w.rotation_euler = (0, 0, 0 if x > 0 else math.pi)

    for n in TANK_PIECES:
        bpy.data.objects[n].location = (0, 60, 0)
    first = True
    for x in (1, -1):
        for at in TANK_WHEELS:
            w = bpy.data.objects["Tank_Wheel"] if first else bpy.data.objects["Tank_Wheel"].copy()
            if not first:
                bpy.context.scene.collection.objects.link(w)
                w.name = "_wheel_view"
            first = False
            w.location = Vector((0, 60, 0)) + R2B @ Vector((x * at[0], at[1], at[2]))
            w.rotation_euler = (0, 0, 0 if x > 0 else math.pi)

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
    print("built", len([o for o in bpy.data.objects if o.name.startswith(PREFIXES)]), "pieces")
