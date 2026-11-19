# The port kit (src/server/Port.luau): the ship-to-shore crane and the cargo ship's hull, modelled in
# code in Blender like the army kit (assets/army/build.py): chunky bevelled shapes, flat colours, one
# material per colour (named by its hex) so export.py can split each piece into one mesh per colour.
# No ink outline: these stand among the map's plain Plastic cubes. Run inside Blender:
#   exec(open(r"<repo>/assets/port/build.py").read(), {"__file__": r"<repo>/assets/port/build.py"})
# It rebuilds every Port_ piece in the open file and saves it as assets/port/port.blend.
#
# Everything is written in ROBLOX space, in studs (x right, y up, front -Z), relative to each piece's
# pivot in Port.luau, and converted on the way in: Blender = (-x, z, y) (as the army kit).
#  * Port_Crane*: pivot on the ground between the rails, under the middle of the portal (Port.luau
#    CRANE_X, z = 8). Sizes match Port.luau's stand-in parts, which stay as the invisible collision.
#  * Port_Hull: pivot at the ship's middle on the water line's ground level (Port.luau x = 56, z = 52).
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else None

R2B = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Roblox -> Blender (a rotation: det +1)

# palette (sRGB hex), the same colours as Port.luau's parts
BLUE, WHITE, YELLOW, STEEL, DARK = "2E6FB0", "EBEBE6", "EBB91E", "464A52", "2A2D33"
GLASS, NEON_RED, BRONZE = "96D2F5", "FF3030", "B08D57"
HULL, HULL_RED, INNER = "1C1C20", "962823", "5A5E66"

DECK = 8  # deck top (Port.luau DECK)
SEA = -6  # water surface


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
        bsdf.inputs["Roughness"].default_value = 0.6
    return m


class Piece:
    """Collects shapes for one object, in Roblox space, then bakes it into Blender."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.cols = []

    def _col(self, h):
        if h not in self.cols:
            self.cols.append(h)
        return self.cols.index(h)

    def _paint(self, faces, h):
        i = self._col(h)
        for f in faces:
            f.material_index = i

    def box(self, size, at, h, bevel=0.0, basis=None):
        """A block `size` (Roblox x, y, z) centred `at`, edges rounded by `bevel` studs. `basis`: a
        Roblox-space 3x3 matrix whose columns are the block's x, y, z directions."""
        sx, sy, sz = size
        before = set(self.bm.faces)
        res = bmesh.ops.create_cube(self.bm, size=1)
        vs = res["verts"]
        bmesh.ops.scale(self.bm, vec=(sx, sz, sy), verts=vs)  # Blender x, y(=Roblox z), z(=Roblox y)
        faces = list({f for v in vs for f in v.link_faces})
        b = min(bevel, 0.45 * min(size))
        if b > 0.005:
            edges = list({e for f in faces for e in f.edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=b, segments=2, profile=0.5, affect="EDGES")
            # the bevel rebuilds the block's own faces too, and its result lists only the new rounds:
            # take every face that was not there before (missed ones kept material 0, the first colour)
            faces = [f for f in self.bm.faces if f not in before]
            vs = list({v for f in faces for v in f.verts})
        rot = R2B @ (basis or Matrix.Identity(3)) @ R2B.inverted()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(R2B @ Vector(at)) @ rot.to_4x4(), verts=vs)
        self._paint([f for f in faces if f.is_valid], h)

    def bar(self, a, b, thick, h, up=(0, 1, 0)):
        """A square bar from `a` to `b` (Roblox space), `thick` across."""
        a, b = Vector(a), Vector(b)
        z = (b - a).normalized()
        x = Vector(up).cross(z)
        if x.length < 1e-4:
            x = Vector((1, 0, 0)).cross(z)
        x.normalize()
        y = z.cross(x)
        self.box((thick, thick, (b - a).length), (a + b) / 2, h, basis=Matrix((x, y, z)).transposed())

    def cyl(self, diameter, length, at, h, axis="y", segs=16):
        """A cylinder along Roblox `axis`, centred `at`."""
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=0.5, radius2=0.5, depth=1)
        vs = res["verts"]
        bmesh.ops.scale(self.bm, vec=(diameter, diameter, length), verts=vs)  # along Blender Z = Roblox Y
        turn = {"y": (0, 0, 0), "x": (0, 0, 90), "z": (90, 0, 0)}[axis]
        m = Euler([math.radians(a) for a in turn], "XYZ").to_matrix()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(R2B @ Vector(at)) @ (R2B @ m @ R2B.inverted()).to_4x4(), verts=vs)
        self._paint(list({f for v in vs for f in v.link_faces}), h)

    def quad(self, pts, h):
        """One face through Roblox-space points, in the order given (counter-clockwise seen from
        the side it faces)."""
        f = self.bm.faces.new([self.bm.verts.new(R2B @ Vector(p)) for p in pts])
        self._paint([f], h)
        return f

    def text(self, body, size, centre, u, v, h):
        """Flat-extruded letters centred `centre`, reading along Roblox `u`, up along `v`; they
        stand out of the surface along u x v, from 0.03 to 0.19 studs."""
        curve = bpy.data.curves.new("PortText", "FONT")
        curve.body, curve.size, curve.extrude = body, size, 0.08
        curve.align_x, curve.align_y = "CENTER", "CENTER"
        ob = bpy.data.objects.new("PortText", curve)
        bpy.context.scene.collection.objects.link(ob)
        me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        u, v = Vector(u), Vector(v)
        w = u.cross(v)
        vs = [self.bm.verts.new(R2B @ (Vector(centre) + u * p.co.x + v * p.co.y + w * (p.co.z + 0.11))) for p in me.vertices]
        faces = [self.bm.faces.new([vs[i] for i in p.vertices]) for p in me.polygons]
        ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(curve)
        self._paint(faces, h)

    def finish(self, recalc=True):
        bm = self.bm
        if recalc:
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
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
        col = bpy.data.collections.get("PortKit") or bpy.data.collections.new("PortKit")
        if col.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(col)
        col.objects.link(ob)
        return ob


# ---------------------------------------------------------------- Crane ----------------------
# Port.luau stand-ins, in crane space: legs 4x38x4 at x +-14, z +-10; top girders 4x4x24 along z at
# x +-14 and 24x4x4 along x at z +-10, all 38..42 up; house 28x12x12 at y 48; boom 4x4x124 at y 44.05
# from z -44 to 80; trolley 8x4x8 at (0, 40, 56); cab 6x5x6 at y 35.5; spreader 36x1x8 at y 24.5.
LEGS = [(x, z) for x in (-14, 14) for z in (-10, 10)]


def crane_portal():
    p = Piece("Port_CranePortal")
    for x, z in LEGS:
        p.box((8, 1.6, 3), (x, 1.65, z), STEEL, bevel=0.15)  # bogie on the rail
        for dx in (-2.5, 2.5):
            p.cyl(1.6, 3.4, (x + dx, 0.85, z), DARK, axis="z", segs=12)  # wheels
        p.box((4, 35.55, 4), (x, 2.45 + 35.55 / 2, z), BLUE, bevel=0.25)  # leg
        p.box((4.3, 1.2, 4.3), (x, 30, z), WHITE, bevel=0.1)  # white band near the top
    for x in (-14, 14):
        p.box((2.5, 2.5, 16), (x, 16, 0), BLUE, bevel=0.15)  # sill beam between the legs of a side
        p.box((4, 4, 24), (x, 40, 0), BLUE, bevel=0.3)  # top girder along z
        for s in (-1, 1):  # knee braces under the girder
            p.bar((x, 30, s * 8), (x, 38, s * 2), 1.2, BLUE)
    for z in (-10, 10):
        p.box((24, 4, 4), (0, 40, z), WHITE, bevel=0.3)  # cross girder along x
        p.box((24, 0.6, 4.2), (0, 38.5, z), YELLOW, bevel=0.05)  # warning band under it
    p.finish()


def crane_house():
    p = Piece("Port_CraneHouse")
    p.box((28, 12, 12), (0, 48, 0), WHITE, bevel=0.4)
    p.box((28.2, 2, 12.2), (0, 50.5, 0), BLUE, bevel=0.05)  # blue band
    for x in (-9, -3, 3, 9):  # vent grilles, front and back
        for s in (-1, 1):
            p.box((3.4, 2.2, 0.2), (x, 45.5, s * 6.15), DARK)
            for k in range(4):
                p.box((3.2, 0.18, 0.12), (x, 44.75 + k * 0.5, s * 6.3), STEEL)
    for s in (-1, 1):
        p.box((0.2, 4.6, 2.6), (s * 14.15, 44.6, -2), STEEL)  # doors on the ends
        p.box((0.2, 1.6, 3.2), (s * 14.15, 47.6, 2.5), GLASS)  # end windows
    p.box((27, 0.4, 0.4), (0, 54.6, 5.6), YELLOW)  # roof rail
    p.box((27, 0.4, 0.4), (0, 54.6, -5.6), YELLOW)
    for x in (-13.3, 13.3):
        for z in (-5.6, 5.6):
            p.box((0.3, 1.2, 0.3), (x, 54.6, z), YELLOW)
    p.finish()


def crane_boom():
    p = Piece("Port_CraneBoom")
    z0, z1 = -44, 80
    lo, hi = 42.45, 45.35  # bottom and top chord centres; the walkway sits on top
    for x in (-1.65, 1.65):
        p.box((0.7, 0.7, z1 - z0), (x, lo, (z0 + z1) / 2), BLUE)
        p.box((0.7, 0.7, z1 - z0), (x, hi, (z0 + z1) / 2), BLUE)
    p.box((4, 0.3, z1 - z0), (0, 45.9, (z0 + z1) / 2), STEEL)  # walkway, its top the collision box's top
    for x in (-1.9, 1.9):
        p.box((0.3, 0.3, z1 - z0), (x, 45.95, (z0 + z1) / 2), YELLOW)  # edge strips, a hair proud of the top and side
    for i in range((z1 - z0) // 4):
        z = z0 + i * 4
        for x in (-1.65, 1.65):  # each side: a post at the bay's start and a diagonal across it
            p.box((0.45, hi - lo - 0.7, 0.45), (x, (lo + hi) / 2, z + 0.4), BLUE)
            p.bar((x, lo + 0.35, z + 0.4), (x, hi - 0.35, z + 3.6), 0.4, BLUE, up=(1, 0, 0))
        p.bar((-1.3, lo, z + 0.4), (1.3, lo, z + 3.6), 0.35, BLUE)  # bottom diagonal
    p.box((4.4, 4.4, 1), (0, 44.05, z1 - 0.5), BLUE, bevel=0.2)  # end plates
    p.box((4.4, 4.4, 1), (0, 44.05, z0 + 0.5), BLUE, bevel=0.2)
    p.box((1, 1, 1), (0, 46.6, z1 - 0.5), NEON_RED)  # tip light
    # A-frame on the house, and the stays down to both ends of the boom
    apex = Vector((0, 66, 0))
    for s in (-1, 1):
        p.bar((s * 12, 54, 0), (s * 0.8, 66, 0), 1.8, BLUE)
    p.bar((-6.4, 60, 0), (6.4, 60, 0), 1.2, BLUE)
    p.box((3, 3, 3), apex, BLUE, bevel=0.3)
    for x in (-0.6, 0.6):
        p.bar((x, 65.5, 1), (x, 46.1, z1 - 2), 0.3, STEEL)
        p.bar((x, 65.5, -1), (x, 46.1, z0 + 2), 0.3, STEEL)
    p.finish()


def crane_trolley():
    p = Piece("Port_CraneTrolley")
    z = 56
    p.box((8, 4, 8), (0, 40, z), YELLOW, bevel=0.2)
    p.box((6, 5, 6), (0, 35.5, z), WHITE, bevel=0.25)  # cab
    p.box((4.6, 2, 0.2), (0, 36, z + 3.13), GLASS)  # front window
    for s in (-1, 1):
        p.box((0.2, 2, 4), (s * 3.13, 36, z), GLASS)
    p.box((6, 1.5, 4), (0, 25.75, z), STEEL, bevel=0.15)  # headblock
    p.box((36, 1, 8), (0, 24.5, z), YELLOW, bevel=0.15)  # spreader (sits on a container at 24)
    for x in (-15, 15):
        p.box((1.2, 0.6, 8.4), (x, 24.5, z), DARK)  # cross beams at the ends
    for x in (-2, 2):
        for dz in (-1.5, 1.5):
            p.bar((x, 26.5, z + dz), (x, 38, z + dz), 0.25, STEEL)
    p.finish()


# ---------------------------------------------------------------- Hull -----------------------
# A lofted shell, open on top (the deck is Map tiles), 2 studs thick like the stand-in plates: outer
# skin red below the water line, a white boot stripe, black above; a steel-grey inner wall down to
# the hold floor; a white rim along the top. Sides at z +-20 from x -80 (stern) to 64, then the bow
# narrows straight to a point at 80, as the stand-in bow plates do.
RINGS = [(8, 20), (-5, 20), (-6, 20), (-16, 19.4), (-19, 17.5), (-20, 14)]  # (y, half width) top->bottom
BANDS = [HULL, WHITE] + [HULL_RED] * 3  # between consecutive rings
STERN, BODY_END, BOW = -80, 64, 80


def section(x):
    """(y, z half width) of the outer skin's rings at x."""
    if x <= STERN:  # the transom: narrower at the bottom
        k = [1, 1, 1, 0.92, 0.8, 0.62]
        return [(y, w * f) for (y, w), f in zip(RINGS, k)]
    if x <= BODY_END:
        return list(RINGS)
    s = max((BOW - x) / (BOW - BODY_END), 0.02)
    rake = (x - BODY_END) / (BOW - BODY_END) * 6  # the forefoot rises toward the stem
    return [(y + (rake if i >= 3 else 0), w * s) for i, (y, w) in enumerate(RINGS)]


def hull():
    p = Piece("Port_Hull")
    outer, inner, rim = [], [], []
    xs = [STERN, -72, BODY_END, 72, BOW]
    secs = [section(x) for x in xs]
    for (xa, sa), (xb, sb) in zip(zip(xs, secs), zip(xs[1:], secs[1:])):
        for side in (-1, 1):
            for k in range(len(RINGS) - 1):
                (ya0, wa0), (ya1, wa1) = sa[k], sa[k + 1]
                (yb0, wb0), (yb1, wb1) = sb[k], sb[k + 1]
                outer.append(p.quad([(xa, ya0, side * wa0), (xb, yb0, side * wb0), (xb, yb1, side * wb1), (xa, ya1, side * wa1)], BANDS[k]))
        (ya, wa), (yb, wb) = sa[-1], sb[-1]
        outer.append(p.quad([(xa, ya, -wa), (xb, yb, -wb), (xb, yb, wb), (xa, ya, wa)], HULL_RED))  # bottom
    # transom and the stem: strips across each band
    for x, sec in ((STERN, secs[0]), (BOW, secs[-1])):
        for k in range(len(RINGS) - 1):
            (y0, w0), (y1, w1) = sec[k], sec[k + 1]
            outer.append(p.quad([(x, y0, -w0), (x, y0, w0), (x, y1, w1), (x, y1, -w1)], BANDS[k]))
    # inner wall: the outer top width less 2, from the deck down to the hold floor
    ixs = [STERN + 2] + xs[1:]
    iw = [max(section(x)[0][1] - 2, 0.05) for x in xs]
    for i in range(len(xs) - 1):
        for side in (-1, 1):
            inner.append(p.quad([(ixs[i], DECK, side * iw[i]), (ixs[i + 1], DECK, side * iw[i + 1]), (ixs[i + 1], -12, side * iw[i + 1]), (ixs[i], -12, side * iw[i])], INNER))
            ow = [section(x)[0][1] for x in xs]
            rim.append(p.quad([(xs[i], DECK, side * ow[i]), (xs[i + 1], DECK, side * ow[i + 1]), (ixs[i + 1], DECK, side * iw[i + 1]), (ixs[i], DECK, side * iw[i])], WHITE))
    inner.append(p.quad([(ixs[0], DECK, -iw[0]), (ixs[0], DECK, iw[0]), (ixs[0], -12, iw[0]), (ixs[0], -12, -iw[0])], INNER))
    rim.append(p.quad([(STERN, DECK, -20), (STERN, DECK, 20), (ixs[0], DECK, iw[0]), (ixs[0], DECK, -iw[0])], WHITE))
    # face the right way: the skin out from the ship's middle, the inner wall in, the rim up
    mid = Vector((0, SEA, 0))
    for f in outer + inner + rim:
        f.normal_update()
        c = R2B.inverted() @ f.calc_center_median()
        n = R2B.inverted() @ f.normal
        want = Vector((0, 1, 0)) if f in rim else (c - mid) * (1 if f in outer else -1)
        if f in inner:
            want = Vector((0, 0, -c.z)) if abs(c.x - ixs[0]) > 0.01 else Vector((1, 0, 0))
        if n.dot(want) < 0:
            f.normal_flip()
    # name on both sides near the bow and on the transom (made up, no real line)
    p.text("MAYHEM STAR", 3, (36, 2.5, -20), (-1, 0, 0), (0, 1, 0), WHITE)
    p.text("MAYHEM STAR", 3, (36, 2.5, 20), (1, 0, 0), (0, 1, 0), WHITE)
    p.text("MAYHEM STAR", 2.2, (STERN, 3.5, 0), (0, 0, 1), (0, 1, 0), WHITE)
    p.text("DOCK 7", 1.6, (STERN, 0.6, 0), (0, 0, 1), (0, 1, 0), WHITE)
    # rudder and propeller under the stern
    p.box((6, 10, 0.8), (STERN - 5, -13, 0), HULL_RED, bevel=0.2)
    p.cyl(1.6, 2.4, (STERN - 1.2, -14, 0), BRONZE, axis="x", segs=14)
    for i in range(4):
        a = math.radians(45 + i * 90)
        d = Vector((0, math.cos(a), math.sin(a)))
        p.box((0.35, 3.2, 1.4), Vector((STERN - 0.6, -14, 0)) + d * 2.2, BRONZE, basis=Matrix(((1, 0, 0), (0, math.cos(a), -math.sin(a)), (0, math.sin(a), math.cos(a)))))
    p.finish(recalc=False)


def build_all():
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Port_") or ob.name == "Cube":  # and the startup scene's cube
            bpy.data.objects.remove(ob)
    crane_portal()
    crane_house()
    crane_boom()
    crane_trolley()
    hull()
    # lay the hull beside the crane for a look (origins stay at the pivots; only the display moves)
    bpy.data.objects["Port_Hull"].location = R2B @ Vector((0, 0, 140))


build_all()
if HERE:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "port.blend"))
print("built", ", ".join(f"{o.name} {sum(len(p.vertices) - 2 for p in o.data.polygons)} tris" for o in bpy.data.objects if o.name.startswith("Port_")))
