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
    "TNT": (tnt, [("thick", 1.1)]),
    "C4": (c4, [("thick", 1.1)]),
    "Landmine": (landmine, []),
    "Bandage": (bandage, [("thick", 1.1)]),
    "Cast": (cast_roll, [("thick", 1.1)]),
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
