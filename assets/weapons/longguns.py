# Builds the detailed Shotgun (pump action) and Sniper (bolt action) meshes in weapons.blend, at the
# scale, origin (the grip) and support points of the older simple ones. comic.py runs this itself.
# Blender axes: X = thickness, -Y = forward (barrel), +Z = up. Colours are sRGB per face ("Col").
import math
from itertools import product

import bmesh
import bpy
from mathutils import Matrix, Vector

METAL = (0.102, 0.102, 0.11)
GREY = (0.2, 0.212, 0.231)
BLACK = (0.039, 0.039, 0.043)
HOLE = (0.02, 0.02, 0.02)
STEEL = (0.58, 0.6, 0.631)
SILVER = (0.8, 0.831, 0.878)
WOOD = (0.58, 0.361, 0.18)
WOOD_DARK = (0.42, 0.239, 0.122)
OD = (0.302, 0.349, 0.212)  # olive drab
OD_DARK = (0.188, 0.212, 0.149)
LENS = (0.451, 0.749, 0.949)
SHELL = (0.75, 0.12, 0.08)
BRASS = (0.85, 0.65, 0.25)

CUBE_FACES = [
    [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
    [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)],
    [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
    [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)],
    [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)],
    [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)],
]


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.layer = self.bm.faces.layers.int.new("Piece")  # moving pieces, see comic.py PIECES
        self.pieces, self.piece = [], 0

    def moving(self, name=None):
        """Parts made after this belong to the named moving piece (None: back to the body)."""
        if name and name not in self.pieces:
            self.pieces.append(name)
        self.piece = self.pieces.index(name) + 1 if name else 0

    def _part(self, make, rgb, bevel=0.0):
        before = set(self.bm.faces)
        make()
        faces = [f for f in self.bm.faces if f not in before]
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        if bevel:
            edges = list({e for f in faces for e in f.edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=1,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
            faces = [f for f in self.bm.faces if f not in before]
        for f in faces:
            f[self.layer] = self.piece
            for loop in f.loops:
                loop[self.col] = (*rgb, 1)

    def hexa(self, corners, rgb, bevel=0.0):
        """corners[(ix, iy, iz)] -> point, a deformed box."""
        def make():
            vs = {k: self.bm.verts.new(corners[k]) for k in corners}
            for quad in CUBE_FACES:
                self.bm.faces.new([vs[k] for k in quad])
        self._part(make, rgb, bevel)

    def box(self, lo, hi, rgb, bevel=0.0):
        self.hexa({k: Vector([(lo, hi)[k[i]][i] for i in range(3)]) for k in product((0, 1), repeat=3)}, rgb, bevel)

    def prism(self, x, y0, z0, y1, z1, rgb, bevel=0.0, x1=None):
        """Box between y0 and y1 whose z range changes from z0=(lo, hi) to z1 (stocks, grips)."""
        xs = (x, x if x1 is None else x1)
        c = {}
        for ix, iy, iz in product((0, 1), repeat=3):
            c[(ix, iy, iz)] = Vector(((-1, 1)[ix] * xs[iy], (y0, y1)[iy], (z0, z1)[iy][iz]))
        self.hexa(c, rgb, bevel)

    def cyl(self, centre, axis, length, r1, rgb, r2=None, seg=12):
        def make():
            m = Matrix.Translation(centre) @ {
                "x": Matrix.Rotation(math.pi / 2, 4, "Y"),
                "y": Matrix.Rotation(-math.pi / 2, 4, "X"),
                "z": Matrix.Identity(4),
            }[axis]
            bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1,
                                  radius2=r1 if r2 is None else r2, depth=length, matrix=m)
        self._part(make, rgb)

    def ball(self, centre, r, rgb):
        self._part(lambda: bmesh.ops.create_uvsphere(self.bm, u_segments=8, v_segments=6, radius=r,
                                                     matrix=Matrix.Translation(centre)), rgb)

    def into(self, name):
        bpy.data.objects[name]["pieces"] = self.pieces
        me = bpy.data.objects[name].data
        material = me.materials[0] if me.materials else None
        me.clear_geometry()
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        self.bm.to_mesh(me)
        self.bm.free()
        if material and not me.materials:
            me.materials.append(material)
        for p in me.polygons:
            p.use_smooth = False
        me.update()
        print(name, len(me.polygons), "faces")


V = Vector


def grip(b, ytop, ztop, ybot, zbot, x, rgb, bevel=0.0):
    """Raked pistol grip: top face spans ytop at height ztop, bottom face spans ybot at zbot."""
    b.hexa({(ix, iy, iz): V(((-x, x)[ix], (ybot, ytop)[iz][iy], (zbot, ztop)[iz]))
            for ix, iy, iz in product((0, 1), repeat=3)}, rgb, bevel)


def trigger_group(b, y0, metal):
    """Trigger guard loop + trigger, its front at y0."""
    b.box(V((-0.025, y0, 0.03)), V((0.025, y0 + 0.32, 0.06)), metal, 0.008)  # bottom bar
    b.box(V((-0.025, y0, 0.03)), V((0.025, y0 + 0.035, 0.18)), metal, 0.008)  # front post
    b.hexa({  # trigger, swept back
        (ix, iy, iz): V(((-0.012, 0.012)[ix], y0 + 0.13 + (0, 0.035)[iy] + (0.05, 0)[iz], (0.08, 0.18)[iz]))
        for ix, iy, iz in product((0, 1), repeat=3)
    }, STEEL)


def shotgun():
    b = Builder()
    # barrel + muzzle + bead + vent rib
    b.cyl(V((0, -1.4, 0.4)), "y", 1.9, 0.062, METAL, seg=16)
    b.cyl(V((0, -2.33, 0.4)), "y", 0.07, 0.074, BLACK, seg=16)
    b.cyl(V((0, -2.37, 0.4)), "y", 0.012, 0.042, HOLE, seg=16)
    b.box(V((-0.016, -2.29, 0.455)), V((0.016, -0.5, 0.475)), BLACK)
    for i in range(7):
        y = -2.2 + i * 0.25
        b.box(V((-0.01, y, 0.44)), V((0.01, y + 0.03, 0.46)), BLACK)
    b.ball(V((0, -2.3, 0.49)), 0.018, SILVER)
    # magazine tube, cap, barrel clamp
    b.cyl(V((0, -1.27, 0.25)), "y", 1.55, 0.052, GREY)
    b.cyl(V((0, -2.08, 0.25)), "y", 0.08, 0.062, STEEL)
    b.box(V((-0.072, -1.98, 0.19)), V((0.072, -1.9, 0.47)), BLACK, 0.012)
    # pump with grip grooves (slides back and forth when racked)
    b.moving("Pump")
    b.box(V((-0.1, -1.62, 0.14)), V((0.1, -0.98, 0.36)), WOOD, 0.03)
    for i in range(6):
        y = -1.55 + i * 0.09
        b.box(V((-0.104, y, 0.16)), V((0.104, y + 0.03, 0.34)), WOOD_DARK)
    b.moving()
    # receiver: body, ejection port, loading port, rear sight, bolt release
    b.box(V((-0.1, -0.5, 0.15)), V((0.1, 0.27, 0.48)), GREY, 0.025)
    b.box(V((-0.104, -0.34, 0.31)), V((-0.08, -0.06, 0.42)), HOLE)
    b.box(V((-0.07, -0.42, 0.145)), V((0.07, -0.08, 0.16)), HOLE)
    b.box(V((-0.03, 0.12, 0.47)), V((0.03, 0.22, 0.52)), BLACK, 0.008)
    b.box(V((0.098, -0.15, 0.2)), V((0.108, -0.08, 0.24)), STEEL)
    # side saddle with four red shells (left side)
    b.box(V((0.1, -0.44, 0.18)), V((0.115, -0.04, 0.44)), BLACK, 0.005)
    for i in range(4):
        y = -0.39 + i * 0.1
        b.cyl(V((0.14, y, 0.33)), "z", 0.18, 0.03, SHELL, seg=10)
        b.cyl(V((0.14, y, 0.215)), "z", 0.05, 0.032, BRASS, seg=10)
    # trigger group, safety button
    trigger_group(b, -0.22, GREY)
    b.cyl(V((0, 0.17, 0.22)), "x", 0.23, 0.018, SHELL, seg=8)
    # pistol grip (raked back) with cap
    grip(b, (0.04, 0.27), 0.2, (0.2, 0.42), -0.22, 0.085, WOOD, 0.03)
    grip(b, (0.19, 0.43), -0.21, (0.2, 0.44), -0.26, 0.09, BLACK, 0.01)
    # stock, butt pad, sling swivels
    b.prism(0.085, 0.25, (0.17, 0.46), 1.2, (-0.03, 0.46), WOOD, 0.03, x1=0.1)
    b.box(V((-0.105, 1.19, -0.05)), V((0.105, 1.27, 0.47)), BLACK, 0.015)
    b.cyl(V((0, 1.1, 0.0)), "x", 0.02, 0.028, STEEL, seg=8)
    b.cyl(V((0, -1.85, 0.19)), "x", 0.02, 0.03, STEEL, seg=8)
    b.into("Shotgun")


def sniper():
    b = Builder()
    # muzzle brake with ports, bore
    b.box(V((-0.08, -3.62, 0.23)), V((0.08, -3.4, 0.41)), BLACK, 0.02)
    for y in (-3.57, -3.5):
        b.box(V((-0.084, y, 0.27)), V((0.084, y + 0.04, 0.37)), HOLE)
    b.cyl(V((0, -3.625, 0.32)), "y", 0.012, 0.035, HOLE, seg=12)
    # barrel (thin front, heavy rear)
    b.cyl(V((0, -2.7, 0.32)), "y", 1.4, 0.05, METAL, seg=14)
    b.cyl(V((0, -1.45, 0.32)), "y", 1.1, 0.062, METAL, seg=14)
    # handguard: body, top rail with teeth, side vents
    b.box(V((-0.1, -2.05, 0.16)), V((0.1, -0.88, 0.42)), OD, 0.03)
    b.box(V((-0.045, -2.0, 0.42)), V((0.045, -0.95, 0.45)), BLACK)
    for i in range(10):
        y = -1.97 + i * 0.1
        b.box(V((-0.05, y, 0.45)), V((0.05, y + 0.045, 0.47)), BLACK)
    for i in range(4):
        y = -1.9 + i * 0.22
        b.box(V((-0.104, y, 0.25)), V((0.104, y + 0.13, 0.33)), OD_DARK, 0.01)
    # bipod: mount, folded legs, feet
    b.box(V((-0.07, -1.98, 0.1)), V((0.07, -1.86, 0.17)), BLACK, 0.01)
    for x in (-0.055, 0.055):
        b.cyl(V((x, -2.32, 0.13)), "y", 0.72, 0.022, GREY, seg=8)
        b.box(V((x - 0.03, -2.74, 0.1)), V((x + 0.03, -2.68, 0.16)), BLACK, 0.008)
    # receiver, ejection port, bolt (body out the back, handle and knob on the right)
    b.box(V((-0.1, -0.9, 0.12)), V((0.1, 0.35, 0.43)), OD_DARK, 0.025)
    b.box(V((-0.104, -0.3, 0.3)), V((-0.08, 0.0, 0.4)), HOLE)
    b.cyl(V((0, 0.36, 0.36)), "y", 0.1, 0.045, SILVER, seg=12)
    b.cyl(V((-0.17, 0.02, 0.34)), "x", 0.15, 0.018, SILVER, seg=8)
    b.ball(V((-0.27, 0.02, 0.34)), 0.045, BLACK)
    # magazine with baseplate, trigger group
    b.box(V((-0.075, -0.56, -0.13)), V((0.075, -0.26, 0.14)), BLACK, 0.015)
    b.box(V((-0.085, -0.58, -0.17)), V((0.085, -0.24, -0.12)), METAL, 0.012)
    trigger_group(b, -0.2, BLACK)
    # pistol grip, stock, cheek riser, butt pad
    grip(b, (0.06, 0.3), 0.15, (0.22, 0.46), -0.25, 0.085, METAL, 0.03)
    b.prism(0.09, 0.33, (0.12, 0.43), 1.35, (-0.05, 0.48), OD, 0.03, x1=0.1)
    b.box(V((-0.08, 0.6, 0.42)), V((0.08, 1.1, 0.53)), OD_DARK, 0.02)
    b.box(V((-0.105, 1.34, -0.06)), V((0.105, 1.42, 0.49)), BLACK, 0.015)
    b.cyl(V((0, 1.15, -0.02)), "x", 0.02, 0.028, STEEL, seg=8)
    # scope: objective bell, lenses, tube, rings on bases, turrets, eyepiece
    b.cyl(V((0, -1.0, 0.64)), "y", 0.3, 0.13, BLACK, r2=0.08, seg=16)
    b.cyl(V((0, -1.155, 0.64)), "y", 0.012, 0.11, LENS, seg=16)
    b.cyl(V((0, -0.35, 0.64)), "y", 1.0, 0.07, METAL, seg=16)
    for y in (-0.64, -0.04):
        b.box(V((-0.045, y - 0.04, 0.42)), V((0.045, y + 0.04, 0.57)), BLACK, 0.01)
        b.cyl(V((0, y, 0.64)), "y", 0.08, 0.085, BLACK, seg=16)
    b.cyl(V((0, -0.35, 0.73)), "z", 0.1, 0.04, BLACK, seg=12)
    b.cyl(V((-0.11, -0.35, 0.64)), "x", 0.1, 0.04, BLACK, seg=12)
    b.cyl(V((0, 0.25, 0.64)), "y", 0.2, 0.08, BLACK, r2=0.1, seg=16)
    b.cyl(V((0, 0.355, 0.64)), "y", 0.012, 0.08, LENS, seg=16)
    b.into("Sniper")


shotgun()
sniper()
