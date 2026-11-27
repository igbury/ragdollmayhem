# The fifteen newer weapons, built in code in the style of the older ones (longguns.py + comic.py):
# hard-surface parts with one-segment bevels, flat shading, real-world colours made punchier
# (comic.punch), the comic exaggeration (comic.shape: thicker across X, swollen heads) and the black
# inverted-hull outline (comic.outline). Conventions as export.py: the origin is the grip, guns point
# -Y, melee weapons +Z up, X is the thickness, 1 unit = 1 stud, colours are sRGB per face ("Col"),
# moving pieces are tagged in the "Piece" face attribute (names in ob["pieces"]; WeaponMeshes.pose).
# Run inside Blender (adds a "ComicWeapons" collection to the open file):
#   ns = {"__file__": r"<repo>/assets/weapons/comic_weapons.py"}
#   exec(open(ns["__file__"]).read(), ns); ns["build_all"](); ns["save"]()
# then export.py with NAMES = list(ns["WEAPONS"]) writes src/client/WeaponMeshes/<Name>.luau.
import math
import os
from itertools import product

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
_comic = {"__name__": "comic"}
exec(open(os.path.join(HERE, "comic.py")).read(), _comic)  # shape / punch / outline, shared with the older weapons
shape, punch, outline = _comic["shape"], _comic["punch"], _comic["outline"]

V = Vector

# palette (sRGB), the older weapons' (longguns.py) plus a few
METAL = (0.102, 0.102, 0.11)
GREY = (0.2, 0.212, 0.231)
BLACK = (0.039, 0.039, 0.043)
HOLE = (0.02, 0.02, 0.02)
STEEL = (0.58, 0.6, 0.631)
SILVER = (0.8, 0.831, 0.878)
WOOD = (0.58, 0.361, 0.18)
WOOD_DARK = (0.42, 0.239, 0.122)
OD = (0.302, 0.349, 0.212)
OD_DARK = (0.188, 0.212, 0.149)
RED = (0.75, 0.12, 0.08)
BRASS = (0.85, 0.65, 0.25)
ORANGE = (0.93, 0.42, 0.08)
YELLOW = (0.96, 0.76, 0.1)
RUBBER = (0.07, 0.07, 0.08)
ROPE = (0.76, 0.6, 0.37)
ROPE_DARK = (0.5, 0.36, 0.2)
COPPER = (0.72, 0.38, 0.18)
ICE = (0.62, 0.88, 0.98)
ICE_BLUE = (0.16, 0.42, 0.8)
WHITE = (0.9, 0.9, 0.88)
PUTTY = (0.86, 0.83, 0.72)
LED = (0.3, 0.95, 0.35)
BLADE = (0.45, 0.85, 1.0)
PAPER = (0.88, 0.8, 0.62)
BLUE = (0.12, 0.3, 0.75)
BAND = (0.55, 0.08, 0.06)

CUBE_FACES = [
    [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
    [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)],
    [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
    [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)],
    [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)],
    [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)],
]
AXES = {"x": V((1, 0, 0)), "y": V((0, 1, 0)), "z": V((0, 0, 1))}


def turn(axis):
    """The rotation taking +Z to `axis` ("x" / "y" / "z" or a vector)."""
    a = AXES[axis] if isinstance(axis, str) else V(axis).normalized()
    return V((0, 0, 1)).rotation_difference(a).to_matrix().to_4x4()


class Builder:
    """One weapon mesh: parts with their colour, the Piece tag of moving parts (longguns.Builder's API)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.layer = self.bm.faces.layers.int.new("Piece")
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
        """corners[(ix, iy, iz)] -> point: a deformed box."""
        def make():
            vs = {k: self.bm.verts.new(corners[k]) for k in corners}
            for quad in CUBE_FACES:
                self.bm.faces.new([vs[k] for k in quad])
        self._part(make, rgb, bevel)

    def box(self, lo, hi, rgb, bevel=0.0):
        self.hexa({k: V([(lo, hi)[k[i]][i] for i in range(3)]) for k in product((0, 1), repeat=3)}, rgb, bevel)

    def cyl(self, centre, axis, length, r1, rgb, r2=None, seg=12, scale=None):
        """A cylinder (a cone when r2 is given) along `axis`; r1 is at the -axis end, r2 at +axis.
        scale: (sx, sy, sz) in the part's own frame before it is turned (flattens a blade)."""
        def make():
            m = Matrix.Translation(V(centre)) @ turn(axis)
            if scale:
                m = m @ Matrix.Diagonal((*scale, 1))
            bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1,
                                  radius2=r1 if r2 is None else r2, depth=length, matrix=m)
        self._part(make, rgb)

    def tube(self, p0, p1, r, rgb, r2=None, seg=8):
        p0, p1 = V(p0), V(p1)
        self.cyl((p0 + p1) / 2, p1 - p0, (p1 - p0).length, r, rgb, r2, seg)

    def ball(self, centre, r, rgb, seg=8, rings=6):
        self._part(lambda: bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r,
                                                     matrix=Matrix.Translation(V(centre))), rgb)

    def sweep(self, points, r, rgb, seg=8, closed=False, r_end=None):
        """A round tube along a polyline (bent handles, hoses, rope); closed: a ring."""
        pts = [V(p) for p in points]
        n = len(pts)

        def tangent(i):
            if closed:
                return (pts[(i + 1) % n] - pts[i - 1]).normalized()
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
            return (b - a).normalized()

        def make():
            t = tangent(0)
            nrm = t.cross(V((0, 0, 1)) if abs(t.z) < 0.9 else V((1, 0, 0))).normalized()
            rings = []
            for i, p in enumerate(pts):
                ti = tangent(i)
                if i:
                    nrm = (t.rotation_difference(ti) @ nrm).normalized()
                t = ti
                bi = t.cross(nrm)
                ri = r if r_end is None else r + (r_end - r) * i / (n - 1)
                rings.append([self.bm.verts.new(p + ri * (math.cos(2 * math.pi * k / seg) * nrm
                                                         + math.sin(2 * math.pi * k / seg) * bi))
                              for k in range(seg)])
            for i in range(n if closed else n - 1):
                a, b = rings[i], rings[(i + 1) % n]
                for k in range(seg):
                    self.bm.faces.new([a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]])
            if not closed:
                self.bm.faces.new(rings[0])
                self.bm.faces.new(list(reversed(rings[-1])))
        self._part(make, rgb)

    def ring(self, centre, u, v, R, r, rgb, seg=6, steps=16):
        """A torus in the plane of the unit vectors u, v."""
        c, u, v = V(centre), V(u), V(v)
        self.sweep([c + R * (math.cos(2 * math.pi * k / steps) * u + math.sin(2 * math.pi * k / steps) * v)
                    for k in range(steps)], r, rgb, seg, closed=True)


def grip(b, ytop, ztop, ybot, zbot, x, rgb, bevel=0.0):
    """Raked pistol grip: top face spans ytop at height ztop, bottom face spans ybot at zbot."""
    b.hexa({(ix, iy, iz): V(((-x, x)[ix], (ybot, ytop)[iz][iy], (zbot, ztop)[iz]))
            for ix, iy, iz in product((0, 1), repeat=3)}, rgb, bevel)


def trigger_group(b, y0, metal):
    """Trigger guard loop + trigger, its front at y0 (longguns.py)."""
    b.box(V((-0.025, y0, 0.03)), V((0.025, y0 + 0.32, 0.06)), metal, 0.008)
    b.box(V((-0.025, y0, 0.03)), V((0.025, y0 + 0.035, 0.18)), metal, 0.008)
    b.hexa({(ix, iy, iz): V(((-0.012, 0.012)[ix], y0 + 0.13 + (0, 0.035)[iy] + (0.05, 0)[iz], (0.08, 0.18)[iz]))
            for ix, iy, iz in product((0, 1), repeat=3)}, STEEL)


def arc(c, u, v, R, a0, a1, n):
    """Points on an arc round c in the plane of u, v, from angle a0 to a1 (degrees)."""
    c, u, v = V(c), V(u), V(v)
    return [c + R * (math.cos(math.radians(a)) * u + math.sin(math.radians(a)) * v)
            for a in (a0 + (a1 - a0) * i / (n - 1) for i in range(n))]


# ---- melee (+Z up from the grip) ----

def crowbar(b):
    b.tube((0, 0, -0.55), (0, 0, 1.75), 0.068, RED, seg=6)  # hex bar
    b.hexa({  # flat chisel end, bent a little forward
        (ix, iy, iz): V((((-0.014, 0.014), (-0.05, 0.05))[iz][ix],
                         ((-0.1, 0.03), (-0.05, 0.05))[iz][iy],
                         (-0.85, -0.5)[iz]))
        for ix, iy, iz in product((0, 1), repeat=3)}, STEEL)
    hook = arc((0, -0.24, 1.75), (0, 1, 0), (0, 0, 1), 0.24, 0, 205, 12)  # the gooseneck
    b.sweep([V((0, 0, 1.7))] + hook, 0.068, RED, seg=6)
    end = hook[-1]
    b.hexa({  # the split claw, tapering back towards the bar
        (ix, iy, iz): V((((-0.05, 0.05), (-0.014, 0.014))[iz][ix],
                         end.y + ((-0.05, 0.05), (0.05, 0.13))[iz][iy],
                         end.z + (0.0, -0.26)[iz]))
        for ix, iy, iz in product((0, 1), repeat=3)}, STEEL)
    b.box(V((-0.06, end.y + 0.06, end.z - 0.27)), V((0.06, end.y + 0.1, end.z - 0.12)), HOLE)  # the nail slot
    b.tube((0, 0, -0.3), (0, 0, 0.45), 0.085, BLACK, seg=8)  # rubber grip
    for z in (-0.22, -0.02, 0.18, 0.38):
        b.cyl((0, 0, z), "z", 0.035, 0.093, RUBBER, seg=8)


def sledgehammer(b):
    b.tube((0, 0, -0.55), (0, 0, 2.0), 0.06, WOOD, seg=8)
    b.tube((0, 0, -0.5), (0, 0, 0.5), 0.07, BLACK, seg=8)  # rubber grip
    for z in (-0.35, -0.1, 0.15, 0.4):
        b.cyl((0, 0, z), "z", 0.03, 0.077, RUBBER, seg=8)
    b.cyl((0, 0, -0.6), "z", 0.1, 0.09, BLACK, seg=8)  # end knob
    b.box(V((-0.09, -0.13, 1.8)), V((0.09, 0.13, 1.97)), METAL, 0.02)  # overstrike collar
    b.box(V((-0.21, -0.58, 1.95)), V((0.21, 0.58, 2.42)), GREY, 0.06)  # head
    b.box(V((-0.24, -0.16, 1.99)), V((0.24, 0.16, 2.38)), RED, 0.02)  # painted band
    for y in (-0.62, 0.62):  # striking faces
        b.cyl((0, y, 2.185), "y", 0.08, 0.215, STEEL, seg=8)


def spear(b):
    b.tube((0, 0, -1.3), (0, 0, 2.55), 0.042, WOOD, seg=8)
    b.cyl((0, 0, -1.33), "z", 0.08, 0.05, METAL, seg=8)  # butt cap
    b.tube((0, 0, -0.25), (0, 0, 0.35), 0.05, ROPE_DARK, seg=8)  # leather grip
    for z in (-0.25, 0.05, 0.35):
        b.cyl((0, 0, z), "z", 0.03, 0.055, ROPE, seg=8)
    for z in (2.42, 2.49):
        b.cyl((0, 0, z), "z", 0.04, 0.05, ROPE, seg=8)  # binding
    b.cyl((0, 0, 2.66), "z", 0.28, 0.05, STEEL, r2=0.035, seg=8)  # socket
    b.cyl((0, 0, 2.95), "z", 0.3, 0.03, STEEL, r2=0.13, seg=4, scale=(0.35, 1, 1))  # leaf blade
    b.cyl((0, 0, 3.33), "z", 0.46, 0.13, SILVER, r2=0.004, seg=4, scale=(0.35, 1, 1))
    for dy, lean in ((-0.03, -0.06), (0.0, 0.0), (0.03, 0.06)):  # red tassel
        b.tube((0, dy, 2.45), (0.02, dy + lean, 2.1), 0.018, RED, seg=4)


def lightsaber(b):
    b.cyl((0, 0, -0.06), "z", 0.1, 0.085, METAL, seg=12)  # pommel
    b.cyl((0, 0, 0.45), "z", 0.9, 0.075, SILVER, seg=12)  # hilt
    for i in range(6):
        b.cyl((0, 0, 0.12 + i * 0.1), "z", 0.045, 0.082, BLACK, seg=12)  # grip ridges
    b.box(V((0.065, -0.04, 0.72)), V((0.11, 0.04, 0.82)), RED, 0.008)  # activation button
    b.cyl((0, 0, 0.98), "z", 0.16, 0.095, STEEL, seg=12)  # emitter shroud
    b.box(V((-0.11, -0.03, 0.93)), V((-0.08, 0.03, 1.03)), HOLE)  # vent window
    b.cyl((0, 0, 1.075), "z", 0.03, 0.07, BLACK, seg=12)  # emitter lip
    b.moving("Blade")
    b.cyl((0, 0, 2.45), "z", 2.7, 0.055, BLADE, seg=12)
    b.cyl((0, 0, 3.84), "z", 0.08, 0.055, BLADE, r2=0.03, seg=12)
    b.moving()


def chainsaw(b):
    # rear D-handle round the origin, throttle trigger
    b.box(V((-0.045, -0.16, -0.045)), V((0.045, 0.16, 0.045)), RUBBER, 0.015)
    b.box(V((-0.045, 0.12, -0.04)), V((0.045, 0.2, 0.36)), ORANGE, 0.015)
    b.box(V((-0.045, -0.25, 0.3)), V((0.045, 0.2, 0.38)), ORANGE, 0.015)
    b.box(V((-0.015, -0.1, -0.09)), V((0.015, -0.02, -0.04)), BLACK)
    # engine body, top cover, starter, fins, stripe
    b.box(V((-0.21, -0.95, -0.12)), V((0.21, -0.15, 0.42)), ORANGE, 0.05)
    b.box(V((-0.17, -0.88, 0.4)), V((0.17, -0.3, 0.5)), BLACK, 0.03)
    b.cyl((0.23, -0.55, 0.17), "x", 0.06, 0.14, GREY, seg=12)
    b.box(V((0.25, -0.62, 0.27)), V((0.3, -0.48, 0.31)), BLACK, 0.01)
    for i in range(4):
        y = -0.85 + i * 0.1
        b.box(V((-0.24, y, 0.0)), V((-0.2, y + 0.04, 0.3)), BLACK)
    b.box(V((0.2, -0.9, -0.02)), V((0.24, -0.3, 0.05)), WHITE)
    # wrap-round front handle, chain brake
    over = [V((0.29 * math.cos(math.radians(a)), -0.62, 0.18 + 0.42 * math.sin(math.radians(a))))
            for a in range(0, 181, 20)]  # an arch over the top cover
    b.sweep([V((0.29, -0.62, -0.1))] + over + [V((-0.29, -0.62, -0.1))], 0.032, BLACK)
    b.box(V((-0.18, -1.0, 0.05)), V((0.18, -0.96, 0.62)), BLACK, 0.01)
    # guide bar with its nose and stripe, the chain's cutters round it
    b.box(V((-0.025, -2.45, 0.0)), V((0.025, -0.9, 0.26)), STEEL, 0.01)
    b.cyl((0, -2.45, 0.13), "x", 0.05, 0.13, STEEL, seg=12)
    b.box(V((-0.045, -2.2, 0.1)), V((0.045, -1.2, 0.16)), BLACK)
    for i in range(19):
        y = -2.4 + i * 0.08
        b.box(V((-0.035, y, 0.25)), V((0.035, y + 0.045, 0.31)), METAL)
        b.box(V((-0.035, y, -0.05)), V((0.035, y + 0.045, 0.01)), METAL)
    for a in (-60, -30, 0, 30, 60):  # cutters round the nose
        p = V((0, -2.45 - 0.16 * math.cos(math.radians(a)), 0.13 + 0.16 * math.sin(math.radians(a))))
        b.box(p - V((0.035, 0.025, 0.025)), p + V((0.035, 0.025, 0.025)), METAL)


def lasso(b):
    for i, x in enumerate((-0.06, -0.02, 0.02, 0.06)):  # the coil, hanging from the hand
        b.ring((x, 0, -0.33), (0, 1, 0), (0, 0, 1), 0.3 + 0.015 * (i % 2), 0.03, ROPE)
    b.box(V((-0.09, -0.06, -0.06)), V((0.09, 0.06, 0.06)), ROPE_DARK, 0.02)  # binding in the fist
    b.ring((0.14, 0.05, -0.56), (0, 1, 0), (0, 0, 1), 0.48, 0.028, ROPE, steps=20)  # the running loop
    b.ball((0.14, 0.05, -0.07), 0.055, ROPE_DARK)  # honda knot
    b.sweep([(0, 0, 0.0), (0, 0.04, 0.12), (0, 0.1, 0.22), (0.02, 0.16, 0.28)], 0.028, ROPE)  # tail


# ---- guns (-Y forward from the grip) ----

def taser(b):
    b.box(V((-0.1, -0.95, 0.12)), V((0.1, 0.2, 0.42)), YELLOW, 0.03)  # frame
    b.box(V((-0.085, -0.9, 0.42)), V((0.085, 0.15, 0.5)), BLACK, 0.02)  # top
    grip(b, (0.0, 0.28), 0.14, (0.12, 0.4), -0.42, 0.085, BLACK, 0.025)
    for i in range(3):  # finger grooves on the grip's front strap
        z = -0.3 + i * 0.12
        yf = 0.12 * (0.14 - z) / 0.56
        b.box(V((-0.09, yf - 0.025, z)), V((0.09, yf + 0.03, z + 0.04)), RUBBER)
    trigger_group(b, -0.2, BLACK)
    b.box(V((-0.115, -1.2, 0.1)), V((0.115, -0.93, 0.44)), BLACK, 0.02)  # cartridge
    for x0, x1 in ((-0.09, -0.01), (0.01, 0.09)):
        b.box(V((x0, -1.23, 0.28)), V((x1, -1.19, 0.4)), STEEL)  # blast doors
    for x in (-0.08, 0.08):
        b.box(V((x - 0.02, -1.23, 0.12)), V((x + 0.02, -1.19, 0.16)), SILVER)  # electrodes
    b.box(V((-0.05, -0.98, 0.02)), V((0.05, -0.8, 0.12)), BLACK, 0.01)  # laser
    b.cyl((0, -0.99, 0.07), "y", 0.02, 0.025, RED, seg=8)
    b.box(V((-0.07, 0.2, 0.28)), V((0.07, 0.23, 0.38)), LED)  # charge display


def frostgun(b):
    b.box(V((-0.12, -0.9, 0.1)), V((0.12, 0.3, 0.42)), ICE_BLUE, 0.035)
    b.cyl((0, -0.35, 0.58), "y", 0.65, 0.12, ICE, seg=12)  # coolant canister
    for y in (-0.7, 0.0):
        b.cyl((0, y, 0.58), "y", 0.06, 0.135, STEEL, seg=12)
    for y in (-0.55, -0.15):
        b.box(V((-0.05, y - 0.04, 0.4)), V((0.05, y + 0.04, 0.48)), METAL)
    b.cyl((0, -1.35, 0.27), "y", 0.9, 0.06, STEEL, seg=12)  # barrel
    for i in range(4):
        b.cyl((0, -1.0 - i * 0.2, 0.27), "y", 0.04, 0.085, WHITE, seg=12)  # cooling rings
    b.cyl((0, -1.87, 0.27), "y", 0.14, 0.13, METAL, r2=0.09, seg=12)  # flared muzzle
    b.cyl((0, -1.945, 0.27), "y", 0.01, 0.06, ICE, seg=12)
    for a in (40, 160, 280):  # ice crystals round the muzzle
        d = V((math.cos(math.radians(a)), 0, math.sin(math.radians(a))))
        p = V((0, -1.9, 0.27)) + d * 0.1
        b.tube(p, p + d * 0.12 + V((0, -0.12, 0)), 0.035, ICE, r2=0.003, seg=4)
    grip(b, (0.04, 0.3), 0.12, (0.16, 0.44), -0.36, 0.085, BLACK, 0.025)
    trigger_group(b, -0.14, METAL)
    b.cyl((0.13, 0.05, 0.28), "x", 0.03, 0.07, WHITE, seg=12)  # gauge
    b.box(V((0.14, 0.04, 0.28)), V((0.15, 0.06, 0.33)), RED)
    b.box(V((-0.09, 0.3, 0.14)), V((0.09, 0.62, 0.38)), METAL, 0.03)  # stub stock


def boilgun(b):
    b.cyl((0, 0.15, 0.62), "y", 0.8, 0.18, COPPER, seg=14)  # boiler
    b.cyl((0, -0.29, 0.62), "y", 0.08, 0.1, COPPER, r2=0.18, seg=14)
    b.cyl((0, 0.59, 0.62), "y", 0.08, 0.18, COPPER, r2=0.1, seg=14)
    for y in (-0.15, 0.15, 0.45):
        b.cyl((0, y, 0.62), "y", 0.03, 0.19, BRASS, seg=14)  # riveted bands
    b.box(V((-0.1, -0.7, 0.15)), V((0.1, 0.35, 0.44)), BRASS, 0.03)  # receiver
    b.cyl((0, -1.15, 0.3), "y", 0.9, 0.055, BRASS, seg=12)  # barrel
    b.cyl((0, -1.68, 0.3), "y", 0.18, 0.13, COPPER, r2=0.06, seg=12)  # bell muzzle
    b.sweep([(0, -0.25, 0.5), (0, -0.45, 0.48), (0, -0.62, 0.42), (0, -0.72, 0.34)], 0.03, BRASS)  # steam pipe
    b.cyl((0, 0.3, 0.82), "z", 0.03, 0.08, BRASS, seg=12)  # gauge
    b.cyl((0, 0.3, 0.84), "z", 0.02, 0.07, WHITE, seg=12)
    b.box(V((-0.005, 0.28, 0.845)), V((0.005, 0.35, 0.86)), RED)
    b.ring((0.22, -0.05, 0.62), (0, 1, 0), (0, 0, 1), 0.07, 0.016, RED, seg=6, steps=12)  # valve wheel
    b.box(V((0.21, -0.12, 0.61)), V((0.23, 0.02, 0.63)), RED)
    b.box(V((0.21, -0.06, 0.55)), V((0.23, -0.04, 0.69)), RED)
    b.cyl((0.19, -0.05, 0.62), "x", 0.05, 0.02, BRASS, seg=8)
    b.cyl((0, -0.05, 0.84), "z", 0.08, 0.03, BRASS, seg=8)  # whistle
    grip(b, (0.04, 0.3), 0.15, (0.16, 0.44), -0.36, 0.085, WOOD, 0.025)
    trigger_group(b, -0.12, BRASS)


def flamethrower(b):
    grip(b, (0.0, 0.24), 0.12, (0.12, 0.38), -0.38, 0.085, BLACK, 0.025)
    trigger_group(b, -0.18, METAL)
    b.box(V((-0.1, -0.75, 0.1)), V((0.1, 0.45, 0.36)), GREY, 0.03)  # body
    b.box(V((-0.08, 0.45, 0.08)), V((0.08, 0.95, 0.33)), METAL, 0.03)  # stock
    b.box(V((-0.09, 0.95, 0.05)), V((0.09, 1.02, 0.35)), RUBBER, 0.015)
    b.cyl((0, -1.45, 0.3), "y", 1.5, 0.055, STEEL, seg=12)  # wand
    b.cyl((0, -1.85, 0.3), "y", 0.55, 0.09, METAL, seg=12)  # heat shroud
    for y in (-2.05, -1.85, -1.65):
        b.cyl((0, y, 0.3), "y", 0.03, 0.095, BLACK, seg=12)
    b.cyl((0, -2.18, 0.3), "y", 0.12, 0.045, BLACK, r2=0.07, seg=12)  # nozzle
    b.box(V((-0.03, -2.15, 0.38)), V((0.03, -2.05, 0.44)), ORANGE)  # igniter
    b.ball((0, -2.2, 0.43), 0.03, YELLOW)  # pilot flame
    b.box(V((-0.04, -1.25, -0.15)), V((0.04, -1.12, 0.26)), BLACK, 0.015)  # front grip
    b.cyl((0, -1.65, 0.08), "y", 0.7, 0.11, RED, seg=12)  # fuel tank
    for y in (-2.0, -1.3):
        b.cyl((0, y, 0.08), "y", 0.04, 0.115, BLACK, seg=12)
    b.cyl((0, -1.65, 0.2), "z", 0.04, 0.03, STEEL, seg=8)  # valve
    b.sweep([(0.08, -1.3, 0.05), (0.09, -1.2, -0.08), (0.09, -1.0, -0.1), (0.08, -0.85, 0.0), (0.06, -0.75, 0.12)],
            0.025, BLACK, seg=6)  # hose


def minigun(b):
    b.moving("Barrels")  # turns round (x 0, z 0.35) when it fires
    for k in range(6):
        a = math.radians(k * 60)
        x, z = 0.12 * math.cos(a), 0.35 + 0.12 * math.sin(a)
        b.cyl((x, -1.55, z), "y", 2.0, 0.035, METAL, seg=8)
        b.cyl((x, -2.555, z), "y", 0.01, 0.022, HOLE, seg=8)
    for y in (-2.45, -1.6):
        b.cyl((0, y, 0.35), "y", 0.06, 0.17, BLACK, seg=12)  # barrel clamps
    b.cyl((0, -0.4, 0.35), "y", 0.3, 0.2, GREY, seg=12)  # rotor
    b.moving()
    b.cyl((0, -0.22, 0.35), "y", 0.06, 0.22, METAL, seg=12)
    b.box(V((-0.2, -0.25, 0.1)), V((0.2, 0.45, 0.6)), OD, 0.04)  # receiver and motor housing
    b.cyl((0.22, 0.15, 0.35), "x", 0.1, 0.12, BLACK, seg=12)  # motor
    b.sweep([(0, -0.15, 0.6), (0, -0.12, 0.78), (0, 0.25, 0.78), (0, 0.28, 0.6)], 0.03, BLACK)  # carry handle
    b.sweep([(-0.2, 0.05, 0.25), (-0.3, 0.1, 0.1), (-0.32, 0.15, -0.12), (-0.32, 0.2, -0.26)], 0.05, METAL, seg=6)  # feed chute
    b.box(V((-0.5, -0.05, -0.6)), V((-0.15, 0.45, -0.25)), OD, 0.03)  # ammo box
    b.box(V((-0.52, -0.07, -0.3)), V((-0.13, 0.47, -0.25)), OD_DARK, 0.01)
    for i in range(3):
        y = 0.08 + i * 0.07
        b.box(V((-0.36, y, -0.25)), V((-0.28, y + 0.04, -0.19)), BRASS)
    grip(b, (0.04, 0.27), 0.12, (0.2, 0.42), -0.3, 0.085, BLACK, 0.025)
    trigger_group(b, -0.22, METAL)
    b.box(V((-0.06, -0.98, 0.13)), V((0.06, -0.78, 0.2)), METAL, 0.01)  # front handle mount
    b.box(V((-0.04, -0.95, -0.2)), V((0.04, -0.82, 0.14)), BLACK, 0.015)  # front handle


def harpoon(b):
    grip(b, (0.04, 0.27), 0.14, (0.16, 0.4), -0.32, 0.085, BLACK, 0.025)
    trigger_group(b, -0.2, METAL)
    b.box(V((-0.09, -0.45, 0.1)), V((0.09, 0.35, 0.34)), GREY, 0.03)  # handle housing
    b.box(V((-0.08, 0.35, 0.06)), V((0.08, 0.8, 0.3)), BLACK, 0.03)  # stock
    b.cyl((0, -1.6, 0.24), "y", 2.3, 0.045, STEEL, seg=10)  # barrel
    b.box(V((-0.11, -2.8, 0.15)), V((0.11, -2.68, 0.34)), BLACK, 0.02)  # muzzle
    for s in (-1, 1):  # rubber bands, stretched back to the shaft's notch
        b.sweep([(0.1 * s, -2.74, 0.26), (0.08 * s, -2.0, 0.34), (0.05 * s, -1.4, 0.4), (0.03 * s, -1.12, 0.42)],
                0.022, BAND, seg=6)
    b.box(V((-0.04, -1.14, 0.4)), V((0.04, -1.08, 0.45)), STEEL)  # wishbone
    b.cyl((0, -1.75, 0.4), "y", 2.2, 0.022, SILVER, seg=8)  # the spear
    b.tube((0, -2.85, 0.4), (0, -3.1, 0.4), 0.045, STEEL, r2=0.003, seg=6)
    for s in (-1, 1):  # barbs
        b.tube((0, -2.92, 0.4), (0.075 * s, -2.8, 0.4), 0.014, STEEL, r2=0.003, seg=4)
    b.cyl((0, -0.62, 0.02), "x", 0.12, 0.1, YELLOW, seg=12)  # line reel
    b.cyl((0, -0.62, 0.02), "x", 0.14, 0.03, METAL, seg=8)
    b.sweep([(0, -0.62, 0.12), (0, -0.7, 0.3), (0, -0.66, 0.4)], 0.008, WHITE, seg=4)  # line
    b.box(V((-0.03, -0.66, 0.08)), V((0.03, -0.58, 0.12)), METAL)


NAVY = (0.14, 0.17, 0.25)
NAVY_DARK = (0.09, 0.11, 0.16)
GRAPHITE = (0.29, 0.32, 0.37)


def grapple(b):
    """The grapple gun from assets/weapons/grappling_hook (the NPR hero model, metres, +X forward) at
    4.5 studs a metre: an AR-style receiver, a fat launch cannon over a line canister, two double
    clamps, a ladder sight, and the hook sitting just out of the muzzle. The hook, its claws and the
    line are the "Hook" piece: the client pulls it back into the barrel while it is out (Fx Grapple)."""
    S = 4.5

    def Y(mx):  # metres forward -> studs along -Y, the grip at the origin
        return -(mx + 0.098) * S + 0.155

    def Z(mz):
        return (mz - 0.02) * S + 0.14

    def P(mx, my, mz):
        return V((my * S, Y(mx), Z(mz)))

    def bx(x0, x1, y0, y1, z0, z1, rgb, bevel=0.0):
        b.box(P(x1, y0, z0), P(x0, y1, z1), rgb, bevel)

    def cy(x0, x1, r, mz, rgb, seg=12, r2=None):  # a cylinder along the barrel, metres
        b.cyl(V((0, (Y(x0) + Y(x1)) / 2, Z(mz))), "y", abs(Y(x1) - Y(x0)), r * S, rgb, None if r2 is None else r2 * S, seg)

    # receiver
    bx(-0.150, 0.035, -0.030, 0.030, 0.058, 0.142, NAVY, 0.02)  # upper
    bx(-0.082, -0.024, -0.0315, -0.020, 0.088, 0.116, HOLE)  # ejection port
    bx(-0.150, 0.032, -0.026, 0.026, 0.018, 0.064, GRAPHITE, 0.015)  # lower
    bx(-0.036, 0.031, -0.029, 0.029, -0.076, 0.040, GRAPHITE, 0.02)  # magwell
    bx(-0.030, 0.026, -0.023, 0.023, -0.078, -0.060, HOLE)
    b.cyl(P(-0.012, -0.031, 0.004), "x", 0.05, 0.03, STEEL, seg=8)  # mag release
    grip(b, (0.04, 0.31), 0.14, (0.22, 0.44), -0.40, 0.075, GRAPHITE, 0.025)
    trigger_group(b, -0.124, METAL)
    cy(-0.214, -0.150, 0.0172, 0.084, NAVY, seg=8)  # buffer tube
    cy(-0.163, -0.151, 0.0225, 0.084, NAVY_DARK, seg=8)  # castle nut
    # rail: base and chunky teeth up to the sight
    bx(-0.146, 0.300, -0.0125, 0.0125, 0.128, 0.1525, NAVY_DARK, 0.01)
    for i in range(12):
        x = -0.138 + i * 0.0365
        bx(x, x + 0.016, -0.0135, 0.0135, 0.1525, 0.160, NAVY_DARK)
    # the launch cannon, its bore, the line canister and its knurled nut
    cy(0.030, 0.380, 0.042, 0.100, NAVY, seg=12)
    cy(0.379, 0.3815, 0.034, 0.100, HOLE, seg=12)
    cy(0.046, 0.335, 0.036, 0.014, NAVY, seg=10)
    cy(0.024, 0.048, 0.026, 0.014, NAVY_DARK, seg=10)
    cy(0.330, 0.372, 0.0435, 0.014, NAVY_DARK, seg=12)
    for k in range(8):  # knurl ribs
        a = 2 * math.pi * k / 8
        c = P(0.351, 0.0445 * math.cos(a), 0.014 + 0.0445 * math.sin(a))
        b.cyl(c, "y", 0.17, 0.022, NAVY_DARK, seg=4)
    cy(0.372, 0.378, 0.033, 0.014, NAVY, seg=10)
    cy(0.377, 0.3795, 0.011, 0.014, HOLE, seg=8)
    # two double clamps: a ring round each barrel, a bridge between, a bolt each side
    for xc in (0.112, 0.255):
        cy(xc - 0.016, xc + 0.016, 0.0505, 0.100, NAVY_DARK, seg=12)
        cy(xc - 0.016, xc + 0.016, 0.0445, 0.014, NAVY_DARK, seg=10)
        bx(xc - 0.016, xc + 0.016, -0.021, 0.021, 0.040, 0.075, NAVY_DARK)
        for s in (-1, 1):
            b.cyl(P(xc, 0.025 * s, 0.057), "x", 0.04, 0.038, STEEL, seg=6)
    bx(0.150, 0.250, -0.0435, -0.034, 0.092, 0.122, GRAPHITE)  # stencil plate
    b.cyl(P(0.268, -0.042, 0.107), "x", 0.02, 0.04, YELLOW, seg=6)  # hex badge
    # ladder sight: low base, tall notched frame at its back, front post at its front
    bx(0.300, 0.372, -0.015, 0.015, 0.134, 0.154, OD)
    for s in (-1, 1):
        bx(0.302, 0.318, 0.011 * s, 0.017 * s, 0.150, 0.222, NAVY)
    bx(0.303, 0.313, -0.017, 0.017, 0.214, 0.224, NAVY)
    for z in (0.170, 0.186, 0.202):
        bx(0.3055, 0.3105, -0.012, 0.012, z, z + 0.004, NAVY)
    bx(0.360, 0.366, -0.003, 0.003, 0.150, 0.176, OD)
    # the hook (moving piece): piston disk, shaft, dome, rope eye, four barbed claws, the line
    b.moving("Hook")
    cy(0.425, 0.438, 0.031, 0.100, NAVY_DARK, seg=10)
    cy(0.425, 0.429, 0.0345, 0.100, STEEL, seg=10)
    cy(0.437, 0.500, 0.0115, 0.100, STEEL, seg=8)
    b.ball(P(0.506, 0, 0.100), 0.021 * S, STEEL, seg=8, rings=5)
    bx(0.439, 0.457, -0.0055, 0.0055, 0.066, 0.089, STEEL)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        ca, sa = math.cos(a), math.sin(a)

        def at(t, inward=0.0):
            mx = 0.508 - 0.075 * (1 - math.cos(t * math.pi / 2))
            r = 0.013 + 0.058 * math.sin(t * math.pi / 2) - inward
            return P(mx, r * ca, 0.100 + r * sa)

        b.sweep([at(1.25 * i / 5) for i in range(6)], 0.010 * S, STEEL, seg=5, r_end=0.0015 * S)
        for t in (0.6, 0.95):  # saw barbs on the inner edge, raked back
            root = at(t, 0.006)
            tip = at(t - 0.12, 0.020)
            b.tube(root, tip, 0.006 * S, STEEL, r2=0.001 * S, seg=4)
    b.sweep([P(0.379, 0, 0.014), P(0.405, 0, 0.022), P(0.430, 0, 0.045), P(0.448, 0, 0.070)], 0.0045 * S, ROPE, seg=5)
    b.moving()


GG_STEEL = (0.37, 0.42, 0.45)
GG_ARMOR = (0.23, 0.27, 0.31)
GG_DARK = (0.12, 0.13, 0.17)
GG_YOKE = (0.2, 0.15, 0.14)
GG_COPPER = (0.22, 0.36, 0.62)
GG_TAPE = (0.68, 0.7, 0.72)
GG_GLOW = (0.1, 0.55, 1.0)
GG_HOT = (0.7, 0.92, 1.0)
GG_CLAW_HINGE = []  # filled by gravgun(): per claw (hinge point, hinge axis) in Roblox mesh space


def gravgun(b):
    """The gravity gun from assets/weapons/gravity_gun (the NPR hero model, metres, +X forward, -Y left)
    at 4 studs a metre: rear stalk grip (raked down to pistol-like, the origin), dark double yoke
    between two steel drums, ribbed side grip on the left drum (the support hand), a faceted armour
    block with glowing vents, copper collar, the glowing core in a three-frame cage, the emitter, and
    five truss claws, each its own moving piece ("Claw1".."Claw5": they open wider while it holds a
    body, client Fx; GG_CLAW_HINGE gives each one's hinge)."""
    S = 4.0
    gx, gz = -0.268, -0.064  # the grip's middle (hero metres)

    def P(mx, my, mz):  # hero metres -> builder studs: -Y forward, +X right (hero +Y is left)
        return V((-my * S, -(mx - gx) * S, (mz - gz) * S))

    def H(v):
        return P(v[0], v[1], v[2])

    def cx(x0, x1, r, rgb, seg=12, r_front=None, y=0.0, z=0.0):  # along the barrel: r at the back
        b.cyl(P((x0 + x1) / 2, y, z), "y", abs(x1 - x0) * S, (r if r_front is None else r_front) * S, rgb,
              r * S, seg)

    def cy(y0, y1, r, rgb, x, z, seg=12, r2=None):  # across (hero Y): r at y0... symmetric use only
        b.cyl(P(x, (y0 + y1) / 2, z), "x", abs(y1 - y0) * S, r * S, rgb, None if r2 is None else r2 * S, seg)

    def obox(c, ax, half, rgb, bevel=0.0):  # an oriented box: centre, 3 unit axes, half sizes (hero)
        c = V(c)
        b.hexa({k: H(c + sum(((-1, 1)[k[i]] * half[i] * V(ax[i]) for i in range(3)), V((0, 0, 0))))
                for k in product((0, 1), repeat=3)}, rgb, bevel)

    X, Y, Z = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
    YX = -0.17
    # rear stalk grip, raked 60 deg down from the yoke, black tape at its root, steel spine, round foot
    g0 = V((YX - 0.068, 0, -0.012))
    gd = V((-0.5, 0, -0.866))
    gu = gd.cross(Y).normalized()  # 'up' across the stalk (its back)
    obox(g0 + gd * 0.052, (gd, Y, gu), (0.048, 0.021, 0.026), GG_DARK, 0.01)
    obox(g0 + gd * 0.012, (gd, Y, gu), (0.014, 0.025, 0.03), BLACK)
    obox(g0 + gd * 0.055, (gd, Y, gu), (0.036, 0.011, 0.004), GG_STEEL)  # spine on the back
    obox(g0 + gd * 0.104, (gd, Y, gu), (0.008, 0.027, 0.031), GG_DARK, 0.008)  # the foot
    obox(g0 + gd * -0.008, (gd, Y, gu), (0.018, 0.025, 0.034), GG_YOKE)  # mount into the yoke
    # yoke: two dark plates, a groove between; the drums either side, stepped flanges, hubs
    for s in (-1, 1):
        cy(s * 0.006, s * 0.031, 0.088, GG_YOKE, YX, 0, seg=14)
        cy(s * 0.030, s * 0.098, 0.079, GG_STEEL, YX, 0, seg=14)
        cy(s * 0.098, s * 0.112, 0.06, GG_STEEL, YX, 0, seg=12)
        cy(s * 0.110, s * 0.118, 0.028, GG_DARK, YX, 0, seg=8)
    cy(-0.007, 0.007, 0.07, GG_DARK, YX, 0, seg=12)
    # side grip on the left drum (-Y), ribbed; red switch at its root; the taped-on gauge on top
    cy(-0.104, -0.12, 0.032, GG_STEEL, YX, -0.008, seg=10)
    cy(-0.12, -0.24, 0.022, GG_DARK, YX, -0.008, seg=8)
    for k in range(6):
        y = -0.13 - k * 0.018
        cy(y, y - 0.007, 0.0255, BLACK, YX, -0.008, seg=8)
    cy(-0.236, -0.244, 0.018, GG_DARK, YX, -0.008, seg=8)
    b.box(P(YX + 0.033, -0.11, 0.016), P(YX + 0.047, -0.126, 0.036), RED)
    b.cyl(P(YX - 0.004, -0.072, 0.086), "z", 0.023 * S, 0.024 * S, GG_STEEL, seg=10)
    b.cyl(P(YX - 0.004, -0.072, 0.098), "z", 0.003 * S, 0.019 * S, PAPER, seg=10)
    b.box(P(YX - 0.004, -0.0735, 0.0995), P(YX + 0.01, -0.0705, 0.101), RED)  # needle
    for a0, a1 in ((40, 72), (108, 140)):  # tape over the drum top, either side of the gauge
        a, c = math.radians((a0 + a1) / 2), V((YX, -0.072, 0))
        rad = V((math.cos(a), 0, math.sin(a)))
        tan = V((-math.sin(a), 0, math.cos(a)))
        obox(c + rad * 0.081, (tan, Y, rad), (0.083 * math.radians(a1 - a0) / 2, 0.017, 0.002), GG_TAPE)
    # armour block: octagonal, tapered front; top plate and lamp; vents; radiator fins; copper collar
    cx(-0.125, -0.108, 0.07, GG_ARMOR, seg=8, r_front=0.094)
    cx(-0.108, 0.03, 0.094, GG_ARMOR, seg=8)
    cx(0.03, 0.05, 0.094, GG_ARMOR, seg=8, r_front=0.078)
    b.box(P(-0.095, -0.035, 0.088), P(0.015, 0.035, 0.104), GG_ARMOR, 0.02)
    b.box(P(-0.014, -0.013, 0.104), P(0.004, 0.013, 0.11), GG_GLOW)
    sl = V((math.sin(math.radians(22)), 0, math.cos(math.radians(22))))  # slanted slots
    for s in (-1, 1):
        for i in range(3):
            c = V((-0.07 + 0.032 * i, s * 0.0885, -0.004))
            obox(c, (X, Y, sl), (0.0085, 0.004, 0.032), BLACK)
            obox(c + Y * s * 0.0035, (X, Y, sl), (0.005, 0.002, 0.027), GG_GLOW)
    for i in range(6):
        x = -0.095 + i * 0.022
        b.box(P(x - 0.003, -0.042, -0.112), P(x + 0.003, 0.042, -0.086), GG_STEEL)
    cx(0.04, 0.084, 0.094, GG_COPPER, seg=14)
    # the core: glowing cylinder, hot ribs, in a cage of three frames and three rods; the front collar
    cx(0.08, 0.33, 0.052, GG_GLOW, seg=12)
    for k in range(6):
        a = 2 * math.pi * k / 6 + math.pi / 6
        n = V((0, math.cos(a), math.sin(a)))
        obox(V((0.205, 0, 0)) + n * 0.054, (X, n.cross(X), n), (0.12, 0.004, 0.003), GG_HOT)

    def rot(ang):  # local (x, t, r) of a radial frame at angle ang (deg, 90 = top) -> hero
        p = math.radians(ang - 90)
        return lambda x, t, r: V((x, t * math.cos(p) - r * math.sin(p), t * math.sin(p) + r * math.cos(p)))

    for ang in (90, 210, 330):
        R = rot(ang)
        ax, at, ar = X, (R(0, 1, 0) - R(0, 0, 0)), (R(0, 0, 1) - R(0, 0, 0))
        for t in (-1, 1):
            obox(R(0.205, t * 0.022, 0.074), (ax, at, ar), (0.125, 0.006, 0.006), GG_STEEL)
        for x in (0.088, 0.205, 0.322):
            obox(R(x, 0, 0.074), (ax, at, ar), (0.007, 0.028, 0.006), GG_STEEL)
        Rr = rot(ang + 60)
        b.tube(H(Rr(0.08, 0, 0.068)), H(Rr(0.33, 0, 0.068)), 0.005 * S, GG_DARK, seg=6)
    cx(0.325, 0.333, 0.088, GG_ARMOR, seg=12, r_front=0.098)
    cx(0.333, 0.352, 0.098, GG_ARMOR, seg=12)
    cx(0.352, 0.36, 0.098, GG_ARMOR, seg=12, r_front=0.088)
    cx(0.358, 0.364, 0.052, GG_DARK, seg=12)
    cx(0.362, 0.367, 0.034, GG_GLOW, seg=12)
    cx(0.364, 0.369, 0.021, GG_STEEL, seg=10)
    b.ball(P(0.37, 0, 0), 0.01 * S, GG_HOT, seg=8, rings=5)
    # five claws: bracket and axle on the collar stay; the truss arms, elbow, tip and LED move
    HX, HR = 0.352, 0.104
    a1, l1 = math.radians(58), 0.11
    a2, l2 = math.radians(-36), 0.09
    E = (HX + l1 * math.cos(a1), HR + l1 * math.sin(a1))
    Tp = (E[0] + l2 * math.cos(a2), E[1] + l2 * math.sin(a2))
    Tip = (Tp[0] + 0.01, Tp[1] - 0.03)
    GG_CLAW_HINGE.clear()
    for k, ang in enumerate((90, 162, 234, 306, 18)):
        R = rot(ang)
        at, ar = R(0, 1, 0) - R(0, 0, 0), R(0, 0, 1) - R(0, 0, 0)
        obox(R(HX - 0.008, 0, HR - 0.008), (X, at, ar), (0.017, 0.02, 0.01), GG_ARMOR)
        b.tube(H(R(HX, -0.026, HR)), H(R(HX, 0.026, HR)), 0.0085 * S, GG_STEEL, seg=8)
        g = [R(HX - 0.012, -0.03, HR + 0.004), R(HX - 0.03, -0.03, HR + 0.07),
             R(HX - 0.03, 0.03, HR + 0.07), R(HX - 0.012, 0.03, HR + 0.004)]
        b.sweep([H(p) for p in g], 0.0038 * S, GG_STEEL, seg=4)  # wire guard
        hinge, axis = H(R(HX, 0, HR)), H(R(HX, 1, HR)) - H(R(HX, 0, HR))
        GG_CLAW_HINGE.append(((-hinge.x, hinge.z, hinge.y), (-axis.x, axis.z, axis.y)))  # Roblox space
        b.moving(f"Claw{k + 1}")
        for t in (-1, 1):
            b.tube(H(R(HX, t * 0.017, HR)), H(R(E[0], t * 0.007, E[1])), 0.005 * S, GG_STEEL, seg=4)
            b.tube(H(R(E[0], t * 0.007, E[1])), H(R(Tp[0], t * 0.003, Tp[1])), 0.0045 * S, GG_STEEL, seg=4)
        for f in (0.35, 0.68):
            mx, mr = HX + (E[0] - HX) * f, HR + (E[1] - HR) * f
            h = 0.017 + (0.007 - 0.017) * f
            b.tube(H(R(mx, -h, mr)), H(R(mx, h, mr)), 0.0035 * S, GG_STEEL, seg=4)
        b.tube(H(R(E[0], -0.014, E[1])), H(R(E[0], 0.014, E[1])), 0.009 * S, GG_DARK, seg=8)
        b.tube(H(R(Tp[0], 0, Tp[1])), H(R(Tip[0], 0, Tip[1])), 0.0048 * S, GG_STEEL, r2=0.002 * S, seg=4)
        b.ball(H(R(Tip[0], 0, Tip[1] + 0.003)), 0.005 * S, GG_HOT, seg=6, rings=4)
        b.moving()


# ---- thrown (held in the fist) ----

def tnt(b):
    for x in (-0.135, 0.0, 0.135):
        b.cyl((x, 0, 0.1), "z", 0.84, 0.072, RED, seg=10)
        for z in (-0.35, 0.55):
            b.cyl((x, 0, z), "z", 0.06, 0.072, PAPER, seg=10)
    for z in (-0.12, 0.32):
        b.box(V((-0.225, -0.085, z)), V((0.225, 0.085, z + 0.08)), BLACK, 0.02)  # tape
    b.box(V((-0.06, -0.1, -0.02)), V((0.06, -0.07, 0.22)), WHITE)  # label
    b.sweep([(0, 0, 0.56), (0, 0, 0.7), (0.05, -0.03, 0.8), (0.12, -0.05, 0.85)], 0.015, BLACK, seg=6)  # fuse
    b.ball((0.13, -0.05, 0.86), 0.04, ORANGE)
    b.ball((0.16, -0.08, 0.9), 0.022, YELLOW)


def c4(b):
    b.box(V((-0.28, -0.16, -0.1)), V((0.28, 0.16, 0.12)), PUTTY, 0.03)
    for x in (-0.18, 0.12):
        b.box(V((x, -0.175, -0.115)), V((x + 0.06, 0.175, 0.135)), OD, 0.01)  # wrap
    b.box(V((-0.12, -0.1, 0.12)), V((0.12, 0.1, 0.22)), BLACK, 0.02)  # detonator
    b.box(V((-0.08, -0.115, 0.145)), V((0.03, -0.095, 0.2)), LED)  # screen
    b.ball((0.07, -0.1, 0.175), 0.025, RED)
    b.tube((0.09, 0.06, 0.22), (0.14, 0.12, 0.5), 0.012, BLACK, seg=6)  # antenna
    b.ball((0.14, 0.12, 0.5), 0.022, RED)
    b.sweep([(0.12, 0.0, 0.18), (0.2, 0.03, 0.24), (0.24, 0.04, 0.12)], 0.013, RED, seg=6)
    b.sweep([(-0.12, 0.0, 0.18), (-0.2, 0.03, 0.24), (-0.24, 0.04, 0.12)], 0.013, BLUE, seg=6)


def landmine(b):
    b.cyl((0, 0, 0.0), "z", 0.14, 0.42, OD, seg=16)
    b.cyl((0, 0, 0.0), "z", 0.04, 0.44, YELLOW, seg=16)  # stencil band
    b.cyl((0, 0, 0.1), "z", 0.06, 0.42, OD, r2=0.34, seg=16)
    b.cyl((0, 0, 0.15), "z", 0.04, 0.26, OD_DARK, seg=16)  # pressure plate
    for k in range(8):
        a = math.radians(k * 45)
        d = V((math.cos(a), math.sin(a), 0))
        b.tube(V((0, 0, 0.175)) + d * 0.09, V((0, 0, 0.175)) + d * 0.22, 0.012, BLACK, seg=4)
    b.cyl((0, 0, 0.19), "z", 0.05, 0.07, METAL, seg=12)  # fuze
    b.cyl((0, 0, 0.22), "z", 0.02, 0.04, YELLOW, seg=12)
    b.sweep([(0.38, -0.12, 0.0), (0.5, -0.1, 0.0), (0.5, 0.1, 0.0), (0.38, 0.12, 0.0)], 0.02, BLACK, seg=6)  # handle


GAUZE = (0.95, 0.93, 0.88)
GAUZE_SHADE = (0.8, 0.77, 0.7)


def bandage(b):
    """A roll of crepe bandage held in the fist (the player's Bandage: dresses a stump), its axis across X,
    a red cross on the end, the loose end hanging off the front with a clip."""
    b.cyl((0, 0, 0.12), "x", 0.38, 0.27, GAUZE, seg=16)
    b.cyl((-0.196, 0, 0.12), "x", 0.012, 0.1, PAPER, seg=12)  # the cardboard core
    b.cyl((-0.2, 0, 0.12), "x", 0.012, 0.06, HOLE, seg=10)
    for k in range(3):  # the edges of the turns, showing on the roll
        b.cyl((-0.12 + k * 0.12, 0, 0.12), "x", 0.03, 0.275, GAUZE_SHADE, seg=16)
    b.cyl((0.196, 0, 0.12), "x", 0.012, 0.2, WHITE, seg=16)  # the label on the outer end, a red cross on it
    b.box(V((0.2, -0.04, 0.0)), V((0.212, 0.04, 0.24)), RED)
    b.box(V((0.2, -0.12, 0.08)), V((0.212, 0.12, 0.16)), RED)
    b.hexa({  # the loose end, off the front of the roll and curling down
        (ix, iy, iz): V(((-0.17, 0.17)[ix], (-0.27, -0.245)[iy] + (0, -0.06)[iz], (0.12, -0.34)[iz]))
        for ix, iy, iz in product((0, 1), repeat=3)}, GAUZE_SHADE)
    b.box(V((-0.06, -0.33, -0.27)), V((0.06, -0.3, -0.2)), STEEL, 0.008)  # its clip


PLASTER_ROLL = (0.93, 0.92, 0.88)
PLASTER_MESH = (0.74, 0.73, 0.69)
FOIL = (0.7, 0.74, 0.8)
WATER = (0.45, 0.75, 0.95)


def cast_roll(b):
    """A roll of plaster bandage (the player's Cast: sets a broken arm or leg), wet from the bowl: half out
    of its torn foil pack, the soaked end hanging, two drops falling off it."""
    b.cyl((0, 0, 0.14), "x", 0.46, 0.25, PLASTER_ROLL, seg=16)
    for k in range(5):  # the open weave of the plaster gauze, showing as bands round the roll
        b.cyl((-0.18 + k * 0.09, 0, 0.14), "x", 0.018, 0.255, PLASTER_MESH, seg=16)
    b.cyl((0.236, 0, 0.14), "x", 0.012, 0.09, PAPER, seg=12)  # the core
    b.cyl((0.24, 0, 0.14), "x", 0.012, 0.05, HOLE, seg=10)
    b.hexa({  # the foil pack, torn open, round the back half
        (ix, iy, iz): V(((-0.25, -0.02)[ix], (-0.29, 0.29)[iy] * (1 if iz else 0.95), (-0.14, 0.42)[iz]))
        for ix, iy, iz in product((0, 1), repeat=3)}, FOIL, 0.02)
    b.box(V((-0.255, -0.12, 0.2)), V((-0.245, 0.12, 0.3)), BLUE)  # the pack's label
    b.hexa({  # the soaked end, hanging off the front
        (ix, iy, iz): V(((-0.2, 0.2)[ix], (-0.26, -0.235)[iy] + (0, -0.05)[iz], (0.14, -0.3)[iz]))
        for ix, iy, iz in product((0, 1), repeat=3)}, PLASTER_MESH)
    b.ball((0.05, -0.31, -0.38), 0.035, WATER, seg=8, rings=6)
    b.ball((-0.08, -0.3, -0.48), 0.025, WATER, seg=8, rings=6)


GLASS = (0.78, 0.9, 0.96)
GLASS_RIM = (0.6, 0.78, 0.9)
SERUM = (0.3, 0.95, 0.35)  # only the default: the game tints the "Liquid" piece per item (client/WeaponMeshes TINT)


def syringe(b):
    """A big comic syringe, needle forward (-Y), held round the barrel like a pistol (the origin): the
    death and the healing syringe share it, the serum in the barrel is the moving piece "Liquid" so the
    client can colour it per item."""
    b.moving("Liquid")
    b.cyl((0, -0.17, 0), "y", 0.46, 0.105, SERUM, seg=14)  # the serum, the front of the barrel
    b.moving(None)
    b.cyl((0, 0.2, 0), "y", 0.28, 0.105, GLASS, seg=14)  # the empty glass behind it
    b.cyl((0, 0.075, 0), "y", 0.05, 0.11, RUBBER, seg=14)  # the plunger's rubber stopper on the serum
    for y in (-0.41, 0.33):  # the glass rims at both ends
        b.cyl((0, y, 0), "y", 0.04, 0.118, GLASS_RIM, seg=14)
    for k in range(5):  # the scale marks along the top and both sides
        y = -0.33 + k * 0.13
        w = 0.05 if k % 2 else 0.09
        b.box(V((-w / 2, y - 0.012, 0.1)), V((w / 2, y + 0.012, 0.115)), BLACK)
        for s in (-1, 1):
            b.box(V((s * 0.1 - 0.008, y - 0.012, -w / 2)), V((s * 0.1 + 0.008, y + 0.012, w / 2)), BLACK)
    b.cyl((0, -0.46, 0), "y", 0.06, 0.06, GLASS_RIM, r2=0.035, seg=10)  # the nozzle
    b.cyl((0, -0.52, 0), "y", 0.07, 0.045, ORANGE, seg=8)  # the needle's hub
    b.tube((0, -0.555, 0), (0, -0.98, 0), 0.014, STEEL, seg=6)  # the needle
    b.cyl((0, -1.01, 0), "y", 0.06, 0.014, SILVER, r2=0.002, seg=6)  # its point
    b.box(V((-0.27, 0.35, -0.045)), V((0.27, 0.39, 0.045)), WHITE, 0.012)  # the finger flange
    b.box(V((-0.025, 0.1, -0.025)), V((0.025, 0.66, 0.025)), WHITE)  # the plunger rod, a cross
    b.box(V((-0.07, 0.1, -0.012)), V((0.07, 0.66, 0.012)), WHITE)
    b.cyl((0, 0.68, 0), "y", 0.04, 0.12, WHITE, seg=14)  # the thumb pad


BG_COLOURS = {"M_Red": (0.78, 0.1, 0.13), "M_Teal": (0.05, 0.64, 0.61), "M_Steel": (0.78, 0.79, 0.79),
              "M_Yellow": (0.9, 0.77, 0.08), "Ink": HOLE}
# the hero model's densest parts, collapsed for the game (the grip loft, its pads, the screw heads)
BG_DECIMATE = {"Grip_Body": 0.3, "Grip_Insert_L": 0.3, "Grip_Insert_R": 0.3, "Grip_BackStrap": 0.3,
               "Shroud_Rivets": 0.35, "Receiver_Screws": 0.35, "Grip_Screw": 0.35}


def from_hero(b, blend, colours, grip, S, decimate=None, ratio=None, mirror=False, turn=None):
    """Read an NPR hero model (assets/weapons/<blend>: metres, +X forward, -Y left) into the builder face
    by face, at S studs a metre with `grip` (metres) at the origin, without its bevels and ink hulls (the
    outline here is comic.outline's). Colours come from each face's toon material (`colours`, by name);
    `decimate` collapses named dense parts (0 leaves one out), `ratio` every other part. mirror: the hero's -Y side ends up
    on the hand's left (the side a first-person view sees). turn: a Matrix that first turns a hero modelled
    another way round into +X forward (`grip` is then in the turned frame). Boolean cutters ("Cutter_")
    come along only as their modifier's operands."""
    decimate = decimate or {}
    path = os.path.join(HERE, blend)
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = [n for n in src.objects if n and not n.startswith(("Cam_", "Key_", "Rim_", "Ink_", "Cutter_"))]
    tmp = bpy.data.collections.new("_hero_tmp")
    bpy.context.scene.collection.children.link(tmp)
    obs = [o for o in dst.objects if o and o.type == "MESH"]
    for o in [o for o in obs if decimate.get(o.name) == 0]:  # 0: left out of the game mesh
        obs.remove(o)
        bpy.data.objects.remove(o)
    for o in obs:
        tmp.objects.link(o)
        for m in o.modifiers:
            if m.name in ("Bevel", "InkHull"):
                m.show_viewport = False
        r = decimate.get(o.name, ratio)
        if r:
            o.modifiers.new("Game", "DECIMATE").ratio = r
    dg = bpy.context.evaluated_depsgraph_get()
    sy = -1 if mirror else 1
    for o in obs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = turn @ o.matrix_world if turn else o.matrix_world
        names = [ms.material.name.split(".")[0] if ms.material else "" for ms in ev.material_slots]
        for poly in me.polygons:
            i = poly.material_index
            rgb = colours.get(names[i] if i < len(names) else "", HOLE)
            vs = []
            for vi in poly.vertices:
                c = mw @ me.vertices[vi].co - grip
                vs.append(b.bm.verts.new((sy * c.y * S, -c.x * S, c.z * S)))
            try:
                f = b.bm.faces.new(vs)
            except ValueError:
                continue
            f[b.layer] = 0
            for loop in f.loops:
                loop[b.col] = (*rgb, 1)
        ev.to_mesh_clear()
    for o in obs:
        me = o.data
        bpy.data.objects.remove(o)
        if me.users == 0:
            bpy.data.meshes.remove(me)
    bpy.data.collections.remove(tmp)
    bmesh.ops.remove_doubles(b.bm, verts=b.bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)


def balloongun(b):
    """The balloon gun: the 90s-comic snub revolver from revolver_90s.blend at 5 studs a metre."""
    from_hero(b, "revolver_90s.blend", BG_COLOURS, V((-0.096, 0.0, -0.045)), 5.0, BG_DECIMATE)  # grip: under the hammer


LB_COLOURS = {"M_Housing": (0.86, 0.88, 0.9), "M_Orange": (1.0, 0.35, 0.0), "M_Graphite": (0.18, 0.22, 0.27),
              "M_Tube": (0.18, 0.22, 0.27), "M_Graphite2": (0.13, 0.15, 0.19), "M_Steel": (0.7, 0.74, 0.78),
              "M_Yellow": (1.0, 0.82, 0.1), "Ink": HOLE}
# the hero's screw heads and seam groove are too small to read at game size; its rings and bosses are dense
LB_DECIMATE = {"Housing_Screws": 0, "Housing_Seam": 0, "Tube_BoreFloor": 0, "Housing_ScrewBosses": 0.2,
               "Grille_Rings": 0.4, "Grille_BaseRing": 0.5, "Impeller": 0.5, "Rear_FilterCover": 0.5,
               "Tube_ClampScrew": 0.4, "Handle_GripSleeve": 0.5}


def leafblower(b):
    """The leaf blower: the 90s-comic blower from leafblower_90s.blend at 4 studs a metre, the origin on
    the top handle's grip (the hand hangs it under the fist), the orange grille on the hand's left."""
    from_hero(b, "leafblower_90s.blend", LB_COLOURS, V((-0.005, 0.0, 0.459)), 4.0, LB_DECIMATE, ratio=0.7,
              mirror=True)


SH_COLOURS = {"M_Oak_Toon": (0.42, 0.28, 0.17), "M_Steel_Toon": (0.4, 0.42, 0.45), "M_Leather": (0.42, 0.25, 0.13),
              "M_Folk_Red": (0.75, 0.02, 0.04), "M_Folk_White": (0.9, 0.88, 0.85), "M_Ink": HOLE,
              "M_Energy_Cyan": (0.0, 0.9, 1.0), "M_Energy_Yellow": (1.0, 0.92, 0.23)}
# the bolts and krackle are the thrown shield's own effect in the game (client Fx Shield), not mesh; the
# flange studs are too small to read; the rim's 144 steps, the planks' grid and the boolean-cut boss are dense
SH_DECIMATE = {"Energy_Bolts_Krackle": 0, "Boss_Studs": 0, "Steel_Outer_Rim": 0.14, "Oak_Planks": 0.05,
               "Steel_Radial_Straps": 0.2, "Iron_Boss": 0.22, "Grip_Steel_Leather": 0.3}


def shield(b):
    """The Slavic Captain's Shield from assets/shield/slavic_shield.blend (face -Y there) at 3.6 studs a
    metre: turned face forward (+X), the origin on the hand bar behind the boss."""
    from_hero(b, os.path.join("..", "shield", "slavic_shield.blend"), SH_COLOURS, V((-0.047, 0.0, -0.07)), 3.6,
              SH_DECIMATE, turn=Matrix.Rotation(math.radians(90), 4, "Z"))


BALLOON_RED = (0.92, 0.16, 0.2)
BALLOON_BLUE = (0.16, 0.47, 0.92)
BALLOON_YELLOW = (0.98, 0.78, 0.12)


def balloons(b):
    """The player's Balloon item: a bunch of three party balloons, their strings gathered in the fist (the
    origin) and running up (+Z) to the knots; what a click ties to the limb it is aimed at (server
    Specials tieByHand), the same balloons the Balloon Gun shoots."""
    for (x, y, z), rgb in (((0.0, 0.0, 2.1), BALLOON_RED), ((-0.42, 0.12, 1.75), BALLOON_BLUE),
                           ((0.4, -0.1, 1.8), BALLOON_YELLOW)):
        top = V((x, y, z))
        b._part(lambda top=top: bmesh.ops.create_uvsphere(  # an egg, not a ball
            b.bm, u_segments=12, v_segments=8, radius=0.36,
            matrix=Matrix.Translation(top) @ Matrix.Diagonal((1, 1, 1.22, 1))), rgb)
        b.ball(top + V((-0.12, -0.2, 0.16)), 0.07, WHITE, seg=6, rings=4)  # the shine
        b.cyl(top - V((0, 0, 0.46)), "z", 0.08, 0.03, rgb, r2=0.07, seg=8)  # the knot
        b.tube((0, 0, 0.0), top - V((0, 0, 0.5)), 0.012, WHITE, seg=4)  # the string
    b.ball((0, 0, 0.0), 0.04, WHITE, seg=6, rings=4)  # the strings' knot in the fist


# Power icons (hotbar / wheel / arsenal only: powers are in no HOLD / GRIP table, so never held).
# Blender axes here: the icon camera looks from -X, Z is up.
FLAME_RGB = [(1.0, 0.47, 0.12), (1.0, 0.78, 0.24), (1.0, 0.27, 0.08)]  # client/Fx FLAME
FIRE_CORE = (1.0, 0.96, 0.78)
SMOKE = (0.08, 0.07, 0.07)


def spun_box(b, centre, half, rot, rgb, bevel=0.0):
    c = V(centre)
    b.hexa({k: c + rot @ V([(-half, half)[k[i]] for i in range(3)]) for k in product((0, 1), repeat=3)}, rgb, bevel)


def supernova(b):
    """Super Nova (FlameOn): the game's fire as it renders, a column of tumbling flame cubes (client/Fx
    burnFx: big and red low down, smaller and yellower as they rise, a white-hot core, a puff of smoke)."""
    import random
    rng = random.Random(7)
    for k in range(5):  # the white-hot core at the foot
        a = k / 5 * 2 * math.pi
        spun_box(b, (0.12 * math.cos(a), 0.12 * math.sin(a), 0.1 + 0.12 * k), 0.16,
                 Matrix.Rotation(rng.uniform(0, 3), 3, rng.choice("XYZ")), FIRE_CORE, 0.02)
    for k in range(40):
        t = k / 39  # 0 at the foot, 1 at the tip
        r = 0.5 * math.sin(math.pi * (0.25 + 0.75 * t)) * (1 - t) ** 0.5 + 0.05  # a flame: bulges, then tapers
        a = rng.uniform(0, 2 * math.pi)
        out = rng.uniform(0.4, 1)
        at = (r * math.cos(a) * out, r * math.sin(a) * out, -0.1 + 2.3 * t)
        half = 0.2 * (1 - t) + 0.06
        rot = Matrix.Rotation(rng.uniform(0, 3), 3, "X") @ Matrix.Rotation(rng.uniform(0, 3), 3, "Z")
        rgb = FLAME_RGB[1] if t > 0.45 else FLAME_RGB[2] if out > 0.93 else FLAME_RGB[0]
        spun_box(b, at, half, rot, rgb, 0.02)
    for at, half in (((0.05, 0.1, 2.45), 0.09), ((-0.1, -0.05, 2.65), 0.06)):  # the smoke off the tip
        spun_box(b, at, half, Matrix.Rotation(0.6, 3, "Y"), SMOKE, 0.01)


WEB = (0.95, 0.95, 0.97)


def webshot(b):
    """Web Shot: a spider web facing the camera (the YZ plane), eight spokes and four rings of thread,
    each thread sagging in towards the middle."""
    R, n = 1.25, 8
    spoke = [V((0, R * math.cos(2 * math.pi * k / n + 0.2), R * math.sin(2 * math.pi * k / n + 0.2))) for k in range(n)]
    for p in spoke:
        b.tube((0, 0, 0), p * 1.04, 0.035, WEB, seg=4)
    for ring in (0.25, 0.48, 0.7, 0.92):
        for k in range(n):
            p0, p1 = spoke[k] * ring, spoke[(k + 1) % n] * ring
            mid = (p0 + p1) / 2 * 0.86  # the sag
            b.sweep([p0, (p0 + mid) / 2 * 1.01, mid, (mid + p1) / 2 * 1.01, p1], 0.028, WEB, seg=4)
    b.ball((0, 0, 0), 0.08, WEB, seg=6, rings=4)


SLAM_GREEN = (0.22, 0.78, 0.2)


def groundslam(b):
    """Ground Slam: a blocky green Roblox fist raised like the fist emoji, knuckles up, wrist down, the
    curled fingers and the thumb across them facing the camera (-X)."""
    b.box((-0.3, -0.32, -1.15), (0.3, 0.32, -0.3), SLAM_GREEN, 0.04)  # the wrist
    b.box((-0.36, -0.44, -0.4), (0.36, 0.44, 0.38), SLAM_GREEN, 0.05)  # the palm / back of the hand
    for i in range(4):  # the fingers, curled over: a knuckle on top, the finger down the front
        y0 = -0.44 + i * 0.22
        drop = 0.04 if i == 3 else 0.0
        b.box((-0.42, y0 + 0.01, 0.22 - drop), (0.3, y0 + 0.21, 0.56 - drop), SLAM_GREEN, 0.05)
        b.box((-0.6, y0 + 0.01, -0.12 - drop), (-0.3, y0 + 0.21, 0.5 - drop), SLAM_GREEN, 0.05)
    b.box((-0.76, -0.5, -0.3), (-0.5, 0.12, -0.04), SLAM_GREEN, 0.05)  # the thumb across them


COSMIC_GREEN = (0.2, 0.67, 0.24)  # client/Fx COSMIC_MID
COSMIC_PALE = (0.8, 1.0, 0.69)  # client/Fx COSMIC_PALE
BOLT = [(-0.35, 1.3), (0.45, 1.3), (0.05, 0.3), (0.55, 0.3), (-0.45, -1.3), (-0.1, -0.15), (-0.6, -0.15)]


def prism(b, outline, x0, x1, rgb):
    """The (y, z) outline pushed out from x0 to x1 (an outline in the camera's plane, given thickness)."""
    def make():
        front = [b.bm.verts.new((x0, y, z)) for y, z in outline]
        back = [b.bm.verts.new((x1, y, z)) for y, z in outline]
        b.bm.faces.new(front)
        b.bm.faces.new(list(reversed(back)))
        n = len(outline)
        for i in range(n):
            b.bm.faces.new([front[i], back[i], back[(i + 1) % n], front[(i + 1) % n]])
    b._part(make, rgb)


def cosmicpower(b):
    """Cosmic Power: a green comic lightning bolt facing the camera (-X), a pale core down its middle."""
    prism(b, BOLT, -0.15, 0.15, COSMIC_GREEN)
    cy = sum(y for y, _ in BOLT) / len(BOLT)
    cz = sum(z for _, z in BOLT) / len(BOLT)
    core = [(cy + (y - cy) * 0.55, cz + (z - cz) * 0.7) for y, z in BOLT]
    prism(b, core, -0.18, -0.14, COSMIC_PALE)
    prism(b, core, 0.14, 0.18, COSMIC_PALE)  # both faces: the arsenal card turns it round


# name -> (builder, comic.shape ops) ; the ops as comic.RULES gives the older ones
WEAPONS = {
    "Crowbar": (crowbar, [("thick", 1.25)]),
    "Sledgehammer": (sledgehammer, [("thick", 1.2), ("swell", "z", 1.85, 2.1, 1.15)]),
    "Spear": (spear, [("thick", 1.2), ("cross", "z", 2.7, 3.0, 1.25)]),
    "Lightsaber": (lightsaber, [("thick", 1.15)]),
    "Chainsaw": (chainsaw, [("thick", 1.2)]),
    "Lasso": (lasso, []),
    "Taser": (taser, [("thick", 1.3)]),
    "Frostgun": (frostgun, [("thick", 1.3), ("cross", "y", -1.6, -1.95, 1.25)]),
    "Boilgun": (boilgun, [("thick", 1.25), ("cross", "y", -1.5, -1.75, 1.2)]),
    "Flamethrower": (flamethrower, [("thick", 1.3), ("cross", "y", -1.6, -2.2, 1.2)]),
    "Minigun": (minigun, [("thick", 1.15)]),
    "Harpoon": (harpoon, [("thick", 1.3), ("cross", "y", -2.6, -3.1, 1.3)]),
    "Grapple": (grapple, [("thick", 1.1)]),
    "Gravgun": (gravgun, [("thick", 1.05)]),
    "BalloonGun": (balloongun, []),
    "LeafBlower": (leafblower, []),
    "TNT": (tnt, [("thick", 1.1)]),
    "C4": (c4, [("thick", 1.1)]),
    "Landmine": (landmine, []),
    "Bandage": (bandage, [("thick", 1.1)]),
    "Cast": (cast_roll, [("thick", 1.1)]),
    "Syringe": (syringe, [("thick", 1.15)]),
    "Balloon": (balloons, []),
    "Shield": (shield, []),
    "FlameOn": (supernova, []),
    "WebShot": (webshot, []),
    "GroundSlam": (groundslam, []),
    "CosmicPower": (cosmicpower, []),
}


def collection():
    col = bpy.data.collections.get("ComicWeapons")
    if col is None:
        col = bpy.data.collections.new("ComicWeapons")
        bpy.context.scene.collection.children.link(col)
    return col


def material():
    m = bpy.data.materials.get("WeaponVertexColor")
    if m is None:
        m = bpy.data.materials.new("WeaponVertexColor")
        m.use_backface_culling = True  # the inverted-hull shell shows only from outside
        m.use_nodes = True
        nodes, links = m.node_tree.nodes, m.node_tree.links
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        attr = nodes.new("ShaderNodeAttribute")
        attr.attribute_name = "Col"
        links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.6
    return m


def build(name):
    make, ops = WEAPONS[name]
    b = Builder()
    make(b)
    old = bpy.data.objects.get(name)
    if old:
        old_me = old.data
        bpy.data.objects.remove(old)
        if old_me.users == 0:
            bpy.data.meshes.remove(old_me)
    me = bpy.data.meshes.new(name)
    b.bm.to_mesh(me)
    b.bm.free()
    ob = bpy.data.objects.new(name, me)
    ob["pieces"] = b.pieces
    collection().objects.link(ob)
    i = list(WEAPONS).index(name)
    ob.location = ((i % 5) * 4.0 - 8.0, -(i // 5) * 5.0, 0.0)
    shape(me, ops)
    punch(me)
    outline(me)
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material())
    me.update()
    return sum(len(p.vertices) - 2 for p in me.polygons)


def build_all(names=None):
    out = {}
    for name in names or WEAPONS:
        out[name] = build(name)
    print(out)
    return out


def save(path=None):
    bpy.ops.wm.save_as_mainfile(filepath=path or os.path.join(HERE, "comic_weapons.blend"), copy=True)
