# The factory kit (src/server/Factory.luau): the hall's machines, modelled in code in Blender like
# the port kit (assets/port/build.py, whose Piece class this copies): chunky shapes with small
# bevels, flat colours, one material per colour (named by its hex) so export.py can split each piece
# into one mesh per colour. The hall is studded Plastic bricks; these stay in that style (Plastic in
# Roblox, the palette 1:1), just with better proportions and detail. Run inside Blender:
#   exec(open(r"<repo>/assets/factory/build.py").read(), {"__file__": r"<repo>/assets/factory/build.py"})
# It rebuilds every Factory_ piece and saves assets/factory/factory.blend.
#
# Everything is written in ROBLOX space, in studs (x right, y up, front -Z), relative to the piece's
# pivot, and converted on the way in: Blender = (-x, z, y). A pivot is the CFrame Factory.luau gives
# the piece (or the stand-in part a moving piece is welded to), so the code's motion is unchanged:
#  * static pieces: PressFrame / SweeperHub / Grinder at their floor centre, Conveyor at the belt's
#    centre, Furnace at the lava pool's centre on the floor, PistonPlate at the piston's `look` frame
#    (-Z out of the wall), HammerBeam at the beam's centre.
#  * moving pieces, in their stand-in part's own frame: PressHead (head), GrinderRoller (roller,
#    axis X), SweeperArm* (arm, along X), SawBlade (blade, axis X), PistonRam (ram, pushes -Z),
#    HammerArm (the swing pivot: the arm hangs down -Y), CraneBeam / CraneTrolley / CraneHook.
# The stand-in parts stay in the game, invisible, as collision and damage zones.
import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else None

R2B = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Roblox -> Blender (a rotation: det +1)

# palette (sRGB hex), Factory.luau's colours
STEEL, DARK, YELLOW, RED = "464A52", "26282E", "EBB91E", "D22823"
BLUE, GREEN, RUST, LAVA, CHROME = "285AA0", "3C7846", "8C4628", "FF6E14", "BEBEC3"
CRUST, BASALT, BASALT2, RUBBER = "6E200C", "29262B", "3A363B", "1A1A1E"

H, L2 = 80, 40  # roof, upper deck (Factory.luau)


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


def collection(name, parent=None):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if col.name not in parent.children:
        parent.children.link(col)
    return col


def rot_x(a):
    """Roblox-space rotation about x (a 3x3 basis for Piece.box)."""
    return Matrix.Rotation(a, 3, "X")


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

    def cyl(self, diameter, length, at, h, axis="y", segs=16, top=None):
        """A cylinder along Roblox `axis`, centred `at` (`top`: the other end's diameter, a cone)."""
        r2 = (top if top is not None else diameter) / diameter * 0.5
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=0.5, radius2=r2, depth=1)
        vs = res["verts"]
        bmesh.ops.scale(self.bm, vec=(diameter, diameter, length), verts=vs)  # along Blender Z = Roblox Y
        turn = {"y": (0, 0, 0), "x": (0, 0, 90), "z": (90, 0, 0)}[axis]
        m = Euler([math.radians(a) for a in turn], "XYZ").to_matrix()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(R2B @ Vector(at)) @ (R2B @ m @ R2B.inverted()).to_4x4(), verts=vs)
        self._paint(list({f for v in vs for f in v.link_faces}), h)

    def stripes(self, size, at, axis, n, a=YELLOW, b=DARK):
        """A block cut into `n` bands along `axis`, alternately coloured `a` and `b` (warning paint as
        geometry, not a texture)."""
        i = "xyz".index(axis)
        step = size[i] / n
        for k in range(n):
            s, c = list(size), list(at)
            s[i] = step
            c[i] = at[i] - size[i] / 2 + step * (k + 0.5)
            self.box(tuple(s), tuple(c), a if k % 2 == 0 else b)

    def funnel(self, cx, cz, y0, y1, w0, w1, h, t=0.4):
        """A square funnel (a solidified frustum, open top and bottom): `w0` wide at `y0`, `w1` at `y1`."""
        def ring(y, w):
            s = w / 2
            return [self.bm.verts.new(R2B @ Vector((cx + x, y, cz + z))) for x, z in ((-s, -s), (s, -s), (s, s), (-s, s))]
        o0, o1, i0, i1 = ring(y0, w0), ring(y1, w1), ring(y0, w0 - 2 * t), ring(y1, w1 - 2 * t)
        faces = []
        for k in range(4):
            n = (k + 1) % 4
            for a, b in ((o0, o1), (i1, i0), (o1, i1), (i0, o0)):
                faces.append(self.bm.faces.new((a[k], a[n], b[n], b[k])))
        self._paint(faces, h)

    def finish(self, moving=False):
        bm = self.bm
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
        kit = collection("FactoryKit")
        collection("Factory_Moving" if moving else "Factory_Machines", kit).objects.link(ob)
        return ob


# Stand-in parts from Factory.luau, in each piece's pivot space (size, centre): the collision and
# damage zones the meshes must fit. Shown as wire boxes in Factory_Collision, never exported.
STANDINS = {}


def standin(piece, size, at):
    STANDINS.setdefault(piece, []).append((size, at))


# ---------------------------------------------------------------- Press ------------------------
# Factory.luau presses(): columns 2x22x2 at x +-7.5 (y 11), beam 18x3x7 at y 23.5; the head 12x3x12
# moves between y 2 and 15 with a chrome rod above it (the rod stays a part: its length changes).
def press_frame():
    p = Piece("Factory_PressFrame")
    for s in (-1, 1):
        x = s * 7.5
        standin("Factory_PressFrame", (2, 22, 2), (x, 11, 0))
        p.box((3.6, 0.6, 4.4), (x, 0.3, 0), DARK, bevel=0.1)  # foot plate
        for dx in (-1.3, 1.3):
            for dz in (-1.7, 1.7):
                p.cyl(0.5, 0.3, (x + dx, 0.75, dz), CHROME, segs=6)  # anchor bolts
        p.box((2, 21.4, 2), (x, 11.3, 0), DARK, bevel=0.15)  # column
        p.stripes((2.12, 4, 2.12), (x, 3, 0), "y", 5)  # hazard paint at shin height
        p.box((0.4, 17, 1.2), (x - s * 1.2, 12.5, 0), CHROME)  # guide rail the head runs in
        for y in (6, 20):
            p.box((1.2, 0.8, 2.4), (x - s * 0.4, y, 0), STEEL, bevel=0.1)  # rail clamps
        p.box((2.6, 1, 2.6), (x, 21.5, 0), STEEL, bevel=0.15)  # column capital
    standin("Factory_PressFrame", (18, 3, 7), (0, 23.5, 0))
    p.box((18, 3, 7), (0, 23.5, 0), RED, bevel=0.25)
    p.box((18.1, 0.5, 7.1), (0, 22.6, 0), DARK)  # dark lower lip of the crossbeam
    for z in (-3.56, 3.56):
        for i in range(8):
            p.cyl(0.45, 0.12, (-7 + i * 2, 24.2, z), CHROME, axis="z", segs=6)  # bolt row
    p.cyl(4, 1.6, (0, 21.6, 0), STEEL, segs=16)  # hydraulic cylinder housing over the rod
    p.cyl(3, 0.4, (0, 20.6, 0), DARK, segs=16)
    # motor on top, finned, with a cable bundle down the column
    p.box((6, 2.4, 3.4), (-3, 26.2, 0), STEEL, bevel=0.2)
    for i in range(6):
        p.box((0.25, 2.6, 3.8), (-5.4 + i * 0.96, 26.2, 0), DARK)
    p.cyl(1.6, 1.2, (1, 26.2, 0), CHROME, axis="x", segs=12)  # shaft end
    p.box((2, 1.2, 1.6), (4.5, 25.6, 0), YELLOW, bevel=0.1)  # junction box
    pts = [(4.5, 25.4, 0.9), (6.2, 24.6, 1.6), (7.0, 22.5, 1.25), (7.0, 18, 1.15), (7.0, 12, 1.15)]
    for a, b in zip(pts, pts[1:]):
        p.bar(a, b, 0.3, RUBBER, up=(0, 0, 1))
    p.finish()


def press_head():
    p = Piece("Factory_PressHead")
    standin("Factory_PressHead", (12, 3, 12), (0, 0, 0))
    p.box((12, 2.6, 12), (0, -0.2, 0), STEEL, bevel=0.2)
    p.box((12.2, 0.6, 12.2), (0, 0, 0), RED)  # the code's red stripe
    p.box((10.4, 0.4, 10.4), (0, 1.25, 0), DARK, bevel=0.1)
    for z in (-3.5, 0, 3.5):
        p.box((10, 0.7, 0.6), (0, 1.75, z), STEEL, bevel=0.1)  # ribs
    for x in (-3.5, 3.5):
        p.box((0.6, 0.7, 10), (x, 1.75, 0), STEEL, bevel=0.1)
    for x in (-5, 5):
        for z in (-5, 5):
            p.stripes((1.6, 0.15, 1.6), (x, 1.5, z), "x", 4)  # hazard corners
    p.cyl(3.6, 1.2, (0, 2.0, 0), CHROME, segs=16)  # rod collar
    for z in (-4.5, -1.5, 1.5, 4.5):
        p.box((11, 0.1, 0.5), (0, -1.55, z), DARK)  # grooves on the striking face
    p.finish(moving=True)


# ---------------------------------------------------------------- Conveyor + grinder -----------
# conveyor(): belt 60x1x8 at (30, 0.5, z) (the pivot), rails 60x1.6x0.8 at z +-4.4 (y 0.8), rollers
# every 8 from x 4. Grinder at x 67: base, red walls, open front at x 60, hopper, warning lamp.
def conveyor():
    p = Piece("Factory_Conveyor")
    standin("Factory_Conveyor", (60, 1, 8), (0, 0, 0))
    p.box((60, 0.9, 8), (0, -0.05, 0), RUBBER)
    for i in range(60):
        p.box((0.35, 0.14, 7.6), (-29.5 + i, 0.45, 0), DARK)  # cleats across the belt
    for s in (-1, 1):
        p.box((60, 1.6, 0.8), (0, 0.3, s * 4.4), YELLOW, bevel=0.1)
        p.box((60.1, 0.3, 0.9), (0, 1.05, s * 4.4), DARK)  # rail cap
        for i in range(30):
            p.cyl(0.32, 0.12, (-29 + i * 2, 0.35, s * 4.85), STEEL, axis="z", segs=6)  # rivets
        for x in range(-26, 27, 8):
            p.cyl(1.1, 0.2, (x, 0.1, s * 4.9), CHROME, axis="z", segs=10)  # roller ends
    for x in (-30, 30):
        p.cyl(1.6, 8.2, (x, 0, 0), CHROME, axis="z", segs=14)  # end drums
    for s in (-1, 1):
        p.stripes((0.9, 1.62, 1.0), (s * 29.55, 0.3, 4.4), "y", 3)
        p.stripes((0.9, 1.62, 1.0), (s * 29.55, 0.3, -4.4), "y", 3)
    p.finish()


def grinder():
    p = Piece("Factory_Grinder")
    standin("Factory_Grinder", (14, 1, 9), (0, 0.5, 0))
    standin("Factory_Grinder", (14, 12, 1), (0, 6, -5))
    standin("Factory_Grinder", (14, 12, 1), (0, 6, 5))
    standin("Factory_Grinder", (1, 12, 11), (7.5, 6, 0))
    standin("Factory_Grinder", (15, 1, 11), (0.5, 12.5, 0))
    p.box((14, 1, 9), (0, 0.5, 0), DARK, bevel=0.1)
    for s in (-1, 1):
        p.box((14, 12, 1), (0, 6, s * 5), RED, bevel=0.2)
        for x in (-4.5, -1.5, 1.5, 4.5):
            p.box((0.6, 11, 0.4), (x, 6, s * 5.65), RED, bevel=0.1)  # ribs
        p.stripes((0.4, 11, 1.08), (-6.85, 6, s * 5), "y", 11)  # hazard paint on the mouth's edge
        p.box((14.2, 0.6, 1.2), (0, 0.6, s * 5), DARK)  # skirt
    p.box((1, 12, 11), (7.5, 6, 0), RED, bevel=0.2)
    for y in (3, 6, 9):
        p.box((0.4, 0.6, 10), (8.15, y, 0), DARK)  # bands on the back
    p.box((15, 1, 11), (0.5, 12.5, 0), DARK, bevel=0.15)
    # hopper: a rusty funnel standing on the roof, wide end up
    p.funnel(2, 0, 13, 21, 3.6, 6.4, RUST, t=0.35)
    p.box((6.8, 0.5, 6.8), (2, 20.9, 0), DARK)  # rim
    # guard bars over the top of the mouth (the belt and the player still get in under them)
    for z in (-3.5, -1.75, 0, 1.75, 3.5):
        p.box((0.3, 3, 0.3), (-7.2, 10.5, z), CHROME)
    p.box((0.4, 0.4, 9), (-7.2, 9, 0), CHROME)
    standin("Factory_Grinder", (1, 1, 9), (-7, 12.6, 0))
    p.box((1, 1, 9), (-7, 13.4, 0), RED, bevel=0.2)  # warning lamp bar (its light is the part's)
    for z in (-4, 0, 4):
        p.box((1.2, 0.3, 0.6), (-7, 12.95, z), DARK)
    p.finish()


def grinder_roller():
    p = Piece("Factory_GrinderRoller")
    standin("Factory_GrinderRoller", (8.6, 3, 3), (0, 0, 0))
    p.cyl(2.1, 8.6, (0, 0, 0), CHROME, axis="x", segs=12)
    for k in range(12):
        a = k * math.tau / 12
        d = Vector((0, math.cos(a), math.sin(a)))
        for j in range(5):
            x = -3.4 + j * 1.7 + (0.85 if k % 2 else 0) * (j < 4)
            p.box((0.8, 0.5, 0.45), Vector((x, 0, 0)) + d * 1.22, STEEL, basis=rot_x(a))  # teeth
    for x in (-4.15, 4.15):
        p.cyl(2.7, 0.3, (x, 0, 0), RED, axis="x", segs=12)
    p.finish(moving=True)


# ---------------------------------------------------------------- Sweeper ----------------------
# sweeper(): hub 3 wide 8 tall (y 0..8), red lamp 5 wide at y 8.5; two arms 2r x 1.6 x 1.6 at y 2.4.
def sweeper_hub():
    p = Piece("Factory_SweeperHub")
    standin("Factory_SweeperHub", (3, 8, 3), (0, 4, 0))
    p.cyl(6, 0.6, (0, 0.3, 0), STEEL, segs=16)
    for k in range(8):
        a = k * math.tau / 8
        p.cyl(0.45, 0.3, (math.cos(a) * 2.5, 0.75, math.sin(a) * 2.5), CHROME, segs=6)
    p.cyl(3, 7.4, (0, 4.3, 0), DARK, segs=16)
    p.cyl(4.2, 0.6, (0, 1.2, 0), YELLOW, segs=16)  # collars above and below the arms
    p.cyl(4.2, 0.6, (0, 3.6, 0), YELLOW, segs=16)
    p.cyl(3.6, 0.5, (0, 7.75, 0), STEEL, segs=16)
    standin("Factory_SweeperHub", (5, 1, 5), (0, 8.5, 0))
    p.cyl(3.4, 1.4, (0, 8.7, 0), RED, segs=16, top=2.4)  # beacon
    for k in range(4):
        a = k * math.tau / 4 + math.pi / 4
        p.box((0.25, 1.8, 0.25), (math.cos(a) * 1.85, 8.9, math.sin(a) * 1.85), DARK)  # cage
    p.cyl(1.2, 0.3, (0, 9.85, 0), DARK, segs=8)
    p.finish()


def sweeper_arm(name, length):
    p = Piece(name)
    standin(name, (length, 1.6, 1.6), (0, 0, 0))
    half = length / 2
    stripe = 6 if length > 30 else 4  # striped tips, solid middle
    for y in (-0.65, 0.65):  # flanges
        p.box((length - 2 * stripe, 0.3, 1.6), (0, y, 0), YELLOW)
        for s in (-1, 1):
            p.stripes((stripe, 0.3, 1.6), (s * (half - stripe / 2), y, 0), "x", stripe)
    p.box((length - 1, 1.0, 0.4), (0, 0, 0), YELLOW)  # web
    for s in (-1, 1):
        p.box((0.6, 1.7, 1.7), (s * (half - 0.3), 0, 0), RUBBER, bevel=0.2)  # rubber bumpers
        p.box((0.2, 1.0, 1.4), (s * (half - 3), 0, 0), YELLOW)  # web stiffeners
    p.cyl(2.4, 1.8, (0, 0, 0), DARK, segs=12)  # boss on the hub
    p.finish(moving=True)


# ---------------------------------------------------------------- Saw ----------------------------
# saw(): blade cylinder 0.6 x 8 x 8 (axis x), red hub 0.8 x 2.4 x 2.4.
def saw_blade():
    p = Piece("Factory_SawBlade")
    standin("Factory_SawBlade", (0.6, 8, 8), (0, 0, 0))
    p.cyl(7.1, 0.4, (0, 0, 0), CHROME, axis="x", segs=24)
    for k in range(24):
        a = k * math.tau / 24
        d = Vector((0, math.cos(a), math.sin(a)))
        p.box((0.4, 0.75, 0.5), d * 3.58, CHROME, basis=rot_x(a) @ rot_x(0.5))  # hooked teeth
    for k in range(6):
        a = k * math.tau / 6 + math.pi / 6
        p.cyl(1.1, 0.44, (0, math.cos(a) * 2.15, math.sin(a) * 2.15), DARK, axis="x", segs=10)  # relief holes
    p.cyl(2.4, 0.8, (0, 0, 0), RED, axis="x", segs=14)
    for k in range(5):
        a = k * math.tau / 5
        p.cyl(0.3, 0.86, (0, math.cos(a) * 0.75, math.sin(a) * 0.75), CHROME, axis="x", segs=6)
    p.finish(moving=True)


# ---------------------------------------------------------------- Furnace ----------------------
# furnace(): lava 28x0.4x28, basalt rim at +-14.5, legs 2x14x2 at the corners, hood 30x5x30 at
# y 16.5, chimney 6 wide from y 19 to the roof (80). Here it carries on through the roof to 90.
def furnace():
    p = Piece("Factory_Furnace")
    rnd = random.Random(7)
    standin("Factory_Furnace", (28, 0.4, 28), (0, 0.2, 0))
    p.box((28, 0.4, 28), (0, 0.2, 0), LAVA)
    for _ in range(16):  # cooled crust floating on the lava
        w, d = rnd.uniform(1.4, 4), rnd.uniform(1.2, 3.2)
        x, z = rnd.uniform(-12, 12), rnd.uniform(-12, 12)
        p.box((w, 0.12, d), (x, 0.45, z), CRUST, basis=Matrix.Rotation(rnd.uniform(0, 3), 3, "Y"))
    for s in (-1, 1):  # rim: rough basalt blocks
        for axis in ("x", "z"):
            pos = -14.5
            while pos < 14.5:
                w = rnd.uniform(1.6, 2.6)
                w = min(w, 15 - pos)
                ht = rnd.uniform(1.0, 1.6)
                c = pos + w / 2
                at = (c, ht / 2, s * 14.5) if axis == "x" else (s * 14.5, ht / 2, c)
                size = (w, ht, 1.3) if axis == "x" else (1.3, ht, w)
                p.box(size, at, BASALT if rnd.random() < 0.6 else BASALT2)
                pos += w
    for sx in (-1, 1):
        for sz in (-1, 1):
            standin("Factory_Furnace", (2, 14, 2), (sx * 14, 7, sz * 14))
            p.box((2, 14, 2), (sx * 14, 7, sz * 14), DARK, bevel=0.15)
            p.box((3, 0.6, 3), (sx * 14, 1.9, sz * 14), STEEL, bevel=0.1)  # feet over the rim
            p.bar((sx * 14, 10, sz * 10), (sx * 14, 13.6, sz * 13.2), 0.6, DARK)  # knee braces
            p.bar((sx * 10, 10, sz * 14), (sx * 13.2, 13.6, sz * 14), 0.6, DARK)
    standin("Factory_Furnace", (30, 5, 30), (0, 16.5, 0))
    p.funnel(0, 0, 14, 19, 30, 12, RUST, t=0.4)  # hood
    p.box((30.6, 1, 30.6), (0, 14.5, 0), DARK)  # drip band
    for s in (-1, 1):
        for i in range(12):
            v = -13.75 + i * 2.5
            p.cyl(0.35, 0.15, (v, 14.5, s * 15.35), CHROME, axis="z", segs=6)
            p.cyl(0.35, 0.15, (s * 15.35, 14.5, v), CHROME, axis="x", segs=6)
    p.cyl(6, 71, (0, 19 + 71 / 2, 0), RUST, segs=16)  # chimney, through the roof to 90
    for y in range(23, 80, 8):
        p.cyl(6.6, 0.6, (0, y, 0), DARK, segs=16)  # hoops
    p.cyl(7, 0.8, (0, 83, 0), DARK, segs=16)  # roof flashing (just above the roof, 82)
    for k in range(4):
        a = k * math.tau / 4 + math.pi / 4
        p.box((0.3, 2.4, 0.3), (math.cos(a) * 2.6, 91.1, math.sin(a) * 2.6), DARK)  # rain cap posts
    p.cyl(8, 0.4, (0, 92.4, 0), DARK, segs=16, top=3)
    p.finish()


# ---------------------------------------------------------------- Pistons ----------------------
# piston(): look frame at the wall face (-Z out into the hall); plate 9x8x1 at z 0.5 (in the wall),
# ram 8x6x2 at z -1 - out * 14 with a yellow strip 8.2x0.5x2.2 on top.
def piston_plate():
    p = Piece("Factory_PistonPlate")
    standin("Factory_PistonPlate", (9, 8, 1), (0, 0, 0.5))
    p.box((9, 8, 0.6), (0, 0, -0.1), RED, bevel=0.2)  # 0.4 proud of the wall
    p.box((8.3, 6.3, 0.1), (0, 0, -0.42), RUBBER)  # the ram's port
    p.stripes((9, 0.8, 0.2), (0, 3.55, -0.45), "x", 9)
    p.stripes((9, 0.8, 0.2), (0, -3.55, -0.45), "x", 9)
    for x in (-4, 4):
        for y in (-3.55, 3.55):
            p.cyl(0.5, 0.2, (x, y, -0.6), CHROME, axis="z", segs=6)
    # hydraulic hoses from the plate's sides up the wall into a manifold
    for s in (-1, 1):
        pts = [(s * 4.5, 1.5, -0.35), (s * 5.6, 2.2, -0.45), (s * 6.0, 4.0, -0.45), (s * 5.2, 5.6, -0.45), (s * 3, 6.2, -0.45)]
        for a, b in zip(pts, pts[1:]):
            p.bar(a, b, 0.35, RUBBER, up=(0, 0, 1))
    p.box((7, 1, 0.8), (0, 6.3, -0.4), STEEL, bevel=0.15)
    p.finish()


def piston_ram():
    p = Piece("Factory_PistonRam")
    standin("Factory_PistonRam", (8, 6, 2), (0, 0, 0))
    p.box((7.6, 5.6, 1.6), (0, 0, 0.2), STEEL, bevel=0.2)
    p.box((8, 6, 0.5), (0, 0, -0.75), CHROME, bevel=0.12)  # face plate
    for x in (-2.7, 0, 2.7):
        p.box((2.2, 5, 0.12), (x, 0, -1.04), RUBBER)  # rubber pads on the face
    p.stripes((8.2, 0.5, 2.2), (0, 3, 0), "x", 8)  # the code's warning strip, as paint
    # trunk (the rod part takes it on to the wall); retracted it ends 0.4 short of the wall's outer face
    p.cyl(2, 3.6, (0, 0, 2.8), CHROME, axis="z", segs=12)
    p.cyl(2.8, 0.6, (0, 0, 1.3), DARK, axis="z", segs=12)
    p.finish(moving=True)


# ---------------------------------------------------------------- Hammer -----------------------
# hammer(): beam 12x2x2 at (x, H-1, z); pivot at H-2; arm 35 long hangs from it, head 4x6x9 at -35
# with a yellow band 4.2x1x9.2. The HammerArm piece is in pivot space (the arm part is welded).
def hammer_beam():
    p = Piece("Factory_HammerBeam")
    standin("Factory_HammerBeam", (12, 2, 2), (0, 0, 0))
    for y in (-0.85, 0.85):
        p.box((12, 0.3, 2), (0, y, 0), DARK, bevel=0.05)
    p.box((12, 1.4, 0.4), (0, 0, 0), DARK)
    for x in (-5.5, 5.5):
        p.box((0.3, 1.4, 1.8), (x, 0, 0), STEEL)
    p.box((3, 1.8, 2.8), (0, -1.4, 0), STEEL, bevel=0.2)  # bearing housing
    p.cyl(1.2, 3.4, (0, -1, 0), CHROME, axis="z", segs=12)  # axle
    p.finish()


def hammer_arm():
    p = Piece("Factory_HammerArm")
    length = H - 2 - (L2 + 3)
    standin("Factory_HammerArm", (0.8, length, 0.8), (0, -length / 2, 0))
    standin("Factory_HammerArm", (4, 6, 9), (0, -length, 0))
    p.cyl(2, 2.4, (0, 0, 0), STEEL, axis="z", segs=12)  # eye on the axle
    for z in (-0.9, 0.9):
        p.box((0.5, length - 4, 0.5), (0, -length / 2 - 0.6, z), DARK)  # chords
    n = 16
    for i in range(n):
        y0 = -1.2 - i * (length - 4.6) / n
        y1 = y0 - (length - 4.6) / n
        a, b = (-0.9, 0.9) if i % 2 == 0 else (0.9, -0.9)
        p.bar((0, y0, a), (0, y1, b), 0.3, DARK, up=(1, 0, 0))  # lacing
    p.box((2, 1.6, 2.6), (0, -length + 3.6, 0), DARK, bevel=0.15)  # socket
    p.box((3.6, 6, 9), (0, -length, 0), RED, bevel=0.3)
    p.stripes((4.2, 1, 9.2), (0, -length, 0), "z", 9)
    for s in (-1, 1):
        p.box((0.25, 4.6, 7.6), (s * 1.9, -length, 0), CHROME, bevel=0.08)  # striking faces
    p.finish(moving=True)


# ---------------------------------------------------------------- Crane ------------------------
# crane(): rails at y 74 on the north and south walls (z +-116); beam 4x3x234 at y 74 rolls along x;
# trolley 6x3x6 at y 71.5 runs along z under it; hook 4x4x4 spins as it drops to just over L2.
def crane_beam():
    p = Piece("Factory_CraneBeam")
    length = 234
    half = length / 2
    standin("Factory_CraneBeam", (4, 3, length), (0, 0, 0))
    for x in (-1.7, 1.7):
        for y in (-1.2, 1.2):
            p.box((0.6, 0.6, length - 2), (x, y, 0), YELLOW)  # chords
    bays = 39
    step = (length - 2) / bays
    for i in range(bays + 1):
        z = -half + 1 + i * step
        for x in (-1.7, 1.7):
            p.box((0.4, 1.8, 0.4), (x, 0, z), YELLOW)  # posts
        p.box((2.8, 0.35, 0.35), (0, -1.2, z), YELLOW)  # bottom ties
        p.box((2.8, 0.35, 0.35), (0, 1.2, z), YELLOW)
        if i < bays:
            for x in (-1.7, 1.7):
                a, b = (-1.0, 1.0) if i % 2 == 0 else (1.0, -1.0)
                p.bar((x, a, z + 0.2), (x, b, z + step - 0.2), 0.3, YELLOW, up=(1, 0, 0))
    p.box((3.4, 0.2, length - 2), (0, 1.6, 0), STEEL)  # walk plate on top
    for s in (-1, 1):
        p.stripes((4.4, 3.4, 4), (0, 0, s * (half - 2)), "z", 4, YELLOW, DARK)  # striped ends
        p.box((7, 1.4, 3.4), (0, 2.9, s * 116), DARK, bevel=0.2)  # end truck over the rail
        for x in (-2.5, 2.5):
            p.cyl(1.6, 0.6, (x, 1.8, s * 116), STEEL, axis="x", segs=12)  # wheels on the rail
        p.box((1.2, 1, 1), (3, 3.9, s * 116), RED, bevel=0.1)  # drive motors
    p.finish(moving=True)


def crane_trolley():
    p = Piece("Factory_CraneTrolley")
    standin("Factory_CraneTrolley", (6, 3, 6), (0, 0, 0))
    p.box((5.6, 2.2, 5.6), (0, -0.2, 0), STEEL, bevel=0.2)
    p.box((6, 0.5, 6), (0, 1.15, 0), DARK, bevel=0.1)
    for x in (-1.7, 1.7):
        for z in (-2, 2):
            p.cyl(0.9, 0.4, (x, 1.3, z), CHROME, axis="x", segs=10)  # wheels under the beam's chords
    p.cyl(2, 4.4, (0, -1.2, 0), CHROME, axis="x", segs=14)  # rope drum
    for x in (-2.3, 2.3):
        p.cyl(2.8, 0.25, (x, -1.2, 0), RED, axis="x", segs=14)
    p.box((2, 1.6, 1.2), (0, -0.2, 3.4), YELLOW, bevel=0.15)  # hoist motor
    p.stripes((5.7, 0.4, 5.7), (0, 0.85, 0), "x", 7)
    p.finish(moving=True)


def crane_hook():
    p = Piece("Factory_CraneHook")
    standin("Factory_CraneHook", (4, 4, 4), (0, 0, 0))
    p.box((3, 1.8, 1.6), (0, 1.0, 0), RED, bevel=0.2)  # sheave block
    for x in (-1.6, 1.6):
        p.box((0.2, 1.4, 1.2), (x, 1.0, 0), DARK)
    p.cyl(0.5, 1.9, (0, 1.2, 0), CHROME, axis="z", segs=8)
    p.box((1.4, 0.4, 1.4), (0, 0.0, 0), DARK)
    p.cyl(0.7, 0.8, (0, -0.4, 0), CHROME, segs=8)  # shank
    c, r = Vector((0.45, -1.45, 0)), 0.8
    pts = [Vector((-0.35, -0.8, 0))]
    for k in range(0, 8):
        a = math.radians(180 + k * 30)
        pts.append(c + Vector((math.cos(a), math.sin(a), 0)) * r)
    for a, b in zip(pts, pts[1:]):
        p.bar(a, b, 0.55 if b.y < -0.95 else 0.5, YELLOW, up=(0, 0, 1))
    p.cyl(0.55, 0.3, pts[-1] + Vector((0, 0.1, 0)), YELLOW, segs=6, top=0.1)  # tip
    p.finish(moving=True)


# ---------------------------------------------------------------- All ------------------------
PIECES = [press_frame, press_head, conveyor, grinder, grinder_roller, sweeper_hub,
          lambda: sweeper_arm("Factory_SweeperArm", 44), lambda: sweeper_arm("Factory_SweeperArmShort", 22),
          saw_blade, furnace, piston_plate, piston_ram, hammer_beam, hammer_arm, crane_beam, crane_trolley, crane_hook]


def reference():
    """Wire boxes: the stand-ins (Factory_Collision), the hall and a 2x5x1 player (Reference)."""
    for name in ("Factory_Collision", "Reference"):
        col = bpy.data.collections.get(name)
        if col:
            for ob in list(col.objects):
                bpy.data.objects.remove(ob)
    cols = collection("Factory_Collision")
    for piece, boxes in STANDINS.items():
        ob_piece = bpy.data.objects[piece]
        for i, (size, at) in enumerate(boxes):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1)
            bmesh.ops.scale(bm, vec=(size[0], size[2], size[1]), verts=bm.verts)
            bmesh.ops.translate(bm, vec=R2B @ Vector(at), verts=bm.verts)
            me = bpy.data.meshes.new(f"Col_{piece[8:]}_{i}")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new(me.name, me)
            ob.display_type = "WIRE"
            ob.parent = ob_piece
            cols.objects.link(ob)
    ref = collection("Reference")
    for name, size, at in (("Ref_Hall", (240, 80, 240), (0, 40, 0)), ("Ref_Player", (2, 5, 1), (0, 2.5, 0))):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(size[0], size[2], size[1]), verts=bm.verts)
        bmesh.ops.translate(bm, vec=R2B @ Vector(at), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        ob.display_type = "WIRE"
        ref.objects.link(ob)
    ref.hide_viewport = True


def build_all():
    for ob in list(bpy.data.objects):
        if ob.name.startswith(("Factory_", "Col_", "Ref_")) or ob.name == "Cube":
            bpy.data.objects.remove(ob)
    STANDINS.clear()
    for make in PIECES:
        make()
    reference()
    # spread the pieces out for a look (origins stay at the pivots; only the display moves)
    x = 0
    for ob in sorted((o for o in bpy.data.objects if o.name.startswith("Factory_")), key=lambda o: o.name):
        w = ob.dimensions.x
        ob.location = (x + w / 2, 0, 0)
        x += w + 6


build_all()
if HERE:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "factory.blend"))
print("built", ", ".join(f"{o.name} {sum(len(p.vertices) - 2 for p in o.data.polygons)}" for o in bpy.data.objects if o.name.startswith("Factory_")))
