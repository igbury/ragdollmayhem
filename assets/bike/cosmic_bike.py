# "COSMIC" comic hardtail MTB for Roblox: 5 MeshParts, one 1024 atlas with baked two-tone AO, ink
# hatching, cel highlight strokes and the COSMIC decals, plus a black inverted-hull outline.
# Headless (does not touch an open Blender session):
#   blender -b --factory-startup -P assets/bike/cosmic_bike.py
# Writes next to this file: CosmicBike.fbx (texture embedded), Bike_Albedo_1024.png, Cosmic_Decal.png,
# cosmic_bike.blend, preview_side.png, preview_34.png.
# Axes: metres, +Z up, the bike faces -Y, tyres rest on Z = 0, drivetrain on the right (-X).
# The FBX is pre-scaled so Roblox imports it at 1 stud = 0.28 m (~6.6 studs long). Outline faces are reversed and
# UV'd onto the atlas's ink corner, so keep DoubleSided = false.
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector as V

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 1024
INK_TILE = 0.97  # body UVs live in [0, INK_TILE]; the corner above it is flat ink for the outline
X, Z = V((1, 0, 0)), V((0, 0, 1))
SQ2 = math.sqrt(2)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


GRAPHITE, NEON, DARK = hexc("#3D464D"), hexc("#D4F024"), hexc("#1C1F24")
ORANGE, RED, WHITE, INK = hexc("#FF7A00"), hexc("#E62429"), hexc("#F7F9FA"), hexc("#050505")
STEEL, MID, COG = hexc("#AEB6BE"), hexc("#30363D"), hexc("#8A939B")


def lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


# ---------------------------------------------------------------- geometry layout (side view y, z)
R_MAJ, R_MIN, KNOB = 0.315, 0.048, 0.014
R_OUT = R_MAJ + 0.9 * R_MIN + KNOB  # the lowest knob's face is exactly on Z = 0
REAR, FRONT, BB = V((0, 0.52, R_OUT)), V((0, -0.51, R_OUT)), V((0, 0.08, 0.30))
AXIS = V((0, 0.391, 0.921)).normalized()  # steering axis (67 deg head angle), through the front hub
ST_DIR = V((0, 0.16, 0.50)).normalized()  # seat tube


def ax(t):
    return FRONT + AXIS * t


def st(z):
    return BB + ST_DIR * ((z - BB.z) / ST_DIR.z)


def rho(a):
    return V((0, math.cos(a), math.sin(a)))  # a = 0 points backwards (+Y), pi/2 up


def line(a, b, k=1):
    return [a.lerp(b, i / k) for i in range(k + 1)]


def bezier(p0, p1, p2, p3, k=10):
    return [p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3 for t in (i / k for i in range(k + 1))]


# ---------------------------------------------------------------- mesh builder
class Part:
    def __init__(self, name, pivot, hull):
        self.name, self.pivot, self.hull_t = name, pivot, hull
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.dec = self.bm.faces.layers.int.new("Dec")  # 1 down-tube text, 2/3 fork text (+X/-X leg), 4 stripe
        self.hl = self.bm.faces.layers.int.new("Hull")  # 1 = gets the outline, 2 = is the outline

    def v(self, p):
        return self.bm.verts.new(p)

    def face(self, vs, c, out, hull, dec=0):
        f = self.bm.faces.new(vs)
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - out) < 0:
            f.normal_flip()
        for lp in f.loops:
            lp[self.col] = lin(c)
        f[self.dec], f[self.hl] = dec, int(hull)
        return f


def frames(pts, closed):
    m, out, s = len(pts), [], None
    for i in range(m):
        a = pts[i - 1] if (i or closed) else pts[i]
        b = pts[(i + 1) % m] if (i < m - 1 or closed) else pts[i]
        t = (b - a).normalized()
        s = s or (X if abs(t.x) < 0.9 else Z)
        s = (s - t * s.dot(t)).normalized()  # parallel transport: no twist on bent cables
        out.append((t, s, t.cross(s)))
    return out


def loft(P, rings, centers, c, closed=False, caps=(False, False), hull=False, paint=None):
    m = len(rings)
    for i in range(m if closed else m - 1):
        i2 = (i + 1) % m
        mid = (centers[i] + centers[i2]) / 2
        n = len(rings[i])
        for j in range(n):
            vs = [rings[i][j], rings[i][(j + 1) % n], rings[i2][(j + 1) % n], rings[i2][j]]
            col, dec = c, 0
            if paint:
                cen = sum((v.co for v in vs), V()) / 4
                col, dec = paint((i + 0.5) / (m if closed else m - 1), (cen - mid).normalized()) or (c, 0)
            P.face(vs, col, mid, hull, dec)
    for k, on in ((0, caps[0]), (m - 1, caps[1])):
        if on:
            P.face(rings[k], c, centers[1] if k == 0 else centers[m - 2], hull)


def tube(P, pts, r, c, n=8, caps=(False, False), hull=False, paint=None, closed=False, ry=None):
    rings = []
    for p, (t, s, u) in zip(pts, frames(pts, closed)):
        angs = [2 * math.pi * j / n + math.pi / n for j in range(n)]  # faces centred on +s, +u, -s, -u
        rings.append([P.v(p + s * math.cos(a) * r + u * math.sin(a) * (ry or r)) for a in angs])
    loft(P, rings, pts, c, closed, caps, hull, paint)


def box(P, a, b, hs, hu, c, hull=False):
    tube(P, [a, b], hs * SQ2, c, n=4, caps=(True, True), hull=hull, ry=hu * SQ2)


def cyl_x(P, c, x0, x1, r, col, n=8, hull=False):
    tube(P, [c + X * x0, c + X * x1], r, col, n=n, caps=(True, True), hull=hull)


def annulus(P, c, r0, r1, x0, x1, col, seg=24, paint=None):
    rings, cents = [], []
    for k in range(seg):
        d = rho(2 * math.pi * k / seg)
        rings.append([P.v(c + d * r + X * x) for r, x in ((r0, x0), (r1, x0), (r1, x1), (r0, x1))])
        cents.append(c + d * (r0 + r1) / 2 + X * (x0 + x1) / 2)
    loft(P, rings, cents, col, closed=True, paint=paint)


def fender(P, hub, a0, a1, seg, red_end):
    prof = [(0, -0.055), (0.014, -0.032), (0.018, 0), (0.014, 0.032), (0, 0.055), (0.006, 0.03), (0.009, 0), (0.006, -0.03)]
    rings, cents = [], []
    for k in range(seg + 1):
        d = rho(a0 + (a1 - a0) * k / seg)
        rings.append([P.v(hub + d * (0.395 + dr) + X * x) for dr, x in prof])
        cents.append(hub + d * 0.407)
    # the end away from the wheel's top gets the red reflector band
    paint = (lambda t, n: (RED, 0) if (t > 0.84 if red_end else t < 0.16) else None)
    loft(P, rings, cents, DARK, caps=(True, True), hull=True, paint=paint)


def hull2d(pts):
    pts = sorted(set(pts))
    def half(seq):
        h = []
        for p in seq:
            while len(h) > 1 and (h[-1][0] - h[-2][0]) * (p[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(p)
        return h[:-1]
    return half(pts) + half(pts[::-1])


# ---------------------------------------------------------------- parts
def wheel(name, hub, front):
    P = Part(name, hub, 0.014)
    ring = [hub + rho(2 * math.pi * k / 24) * R_MAJ for k in range(24)]
    tube(P, ring, R_MIN, DARK, n=8, closed=True, hull=True)
    for k in range(24):  # tread knobs, one per tyre segment, the first one on the ground
        a = -math.pi / 2 + 2 * math.pi * k / 24
        d, tau = rho(a), V((0, -math.sin(a), math.cos(a)))
        c = hub + d * (R_OUT - KNOB / 2 - 0.003) + X * (0.008 if k % 2 else -0.008)
        n0 = len(P.bm.faces)
        box(P, c - tau * 0.022, c + tau * 0.022, 0.03, KNOB / 2 + 0.003, DARK)
        P.bm.faces.ensure_lookup_table()  # the knob's underside is buried in the tyre: drop it
        bmesh.ops.delete(P.bm, geom=[f for f in P.bm.faces[n0:] if f.normal.dot(d) < -0.9], context="FACES_ONLY")
    annulus(P, hub, 0.245, 0.272, -0.02, 0.02, DARK,
            paint=lambda t, n: (WHITE, 0) if round(t * 24 - 0.5) % 6 in (0, 1) and abs(n.x) > 0.7 else None)
    cyl_x(P, hub, -0.075, 0.075, 0.028, MID)
    for k in range(10):
        d = rho(2 * math.pi * k / 10 + 0.15)
        sx = 0.04 if k % 2 else -0.04
        tube(P, [hub + d * 0.026 + X * sx, hub + d * 0.25], 0.006, STEEL, n=4)
        if k in (0, 5):  # spoke reflectors
            box(P, hub + d * 0.13 + X * sx * 0.48, hub + d * 0.19 + X * sx * 0.24, 0.009, 0.016, ORANGE)
    if front:
        annulus(P, hub, 0.052, 0.085, 0.052, 0.058, STEEL, seg=16)
        for k in range(5):
            d = rho(2 * math.pi * k / 5)
            box(P, hub + d * 0.026 + X * 0.055, hub + d * 0.054 + X * 0.055, 0.004, 0.007, STEEL)
    else:
        for x0, x1, r in ((-0.046, -0.052, 0.072), (-0.055, -0.061, 0.062), (-0.064, -0.071, 0.052)):
            cyl_x(P, hub, x0, x1, r, COG, n=10)
    return P


def frame():
    P = Part("Bike_Frame", BB, 0.012)
    tube(P, line(ax(0.46), ax(0.60)), 0.033, GRAPHITE, caps=(True, True), hull=True)
    tube(P, line(ax(0.575), st(0.76), 6), 0.026, GRAPHITE, hull=True,
         paint=lambda t, n: (NEON, 4) if 0.12 < t < 0.88 and abs(n.x) > 0.7 else None)
    tube(P, line(ax(0.49), BB, 6), 0.034, GRAPHITE, hull=True,
         paint=lambda t, n: (GRAPHITE, 1) if abs(n.x) > 0.35 else None)
    tube(P, line(BB, st(0.80), 3), 0.029, GRAPHITE, caps=(False, True), hull=True)
    cyl_x(P, BB, -0.045, 0.045, 0.036, GRAPHITE, hull=True)
    for sx in (1, -1):
        tube(P, line(BB + X * sx * 0.045, REAR + X * sx * 0.075, 3), 0.016, GRAPHITE, hull=True)
        tube(P, line(st(0.74) + X * sx * 0.022, REAR + X * sx * 0.075 + V((0, -0.005, 0.012)), 3), 0.014, GRAPHITE,
             hull=True, paint=lambda t, n, sx=sx: (NEON, 4) if n.x * sx > 0.7 else None)
        cyl_x(P, REAR, sx * 0.07, sx * 0.084, 0.022, GRAPHITE, n=6)  # dropouts
    tube(P, line(st(0.80), st(0.905)), 0.017, MID)  # seatpost
    seat = st(0.905) + V((0, 0.005, 0))
    rows = ((-0.15, 0.022, 0.016, -0.004), (-0.09, 0.03, 0.022, -0.012), (-0.02, 0.05, 0.024, -0.014),
            (0.05, 0.07, 0.027, -0.016), (0.10, 0.075, 0.026, -0.014), (0.125, 0.06, 0.02, -0.01))
    rings, cents = [], []
    for y, w, top, bot in rows:
        o = seat + V((0, y, 0))
        rings.append([P.v(o + V(p)) for p in ((-w, 0, 0), (-0.6 * w, 0, top), (0.6 * w, 0, top), (w, 0, 0), (0.6 * w, 0, bot), (-0.6 * w, 0, bot))])
        cents.append(o + V((0, 0, (top + bot) / 2)))
    loft(P, rings, cents, DARK, caps=(True, True), hull=True)
    box(P, seat + V((0, 0.122, 0.004)), seat + V((0, 0.134, 0.004)), 0.022, 0.007, RED)  # saddle reflector
    fender(P, REAR, math.radians(128), math.radians(-12), 12, red_end=True)
    tube(P, [st(0.69), REAR + rho(math.radians(128)) * 0.402], 0.007, MID)  # fender mount
    # chain: one belt round the chainring, the smallest cog and the lower jockey wheel
    circles = ((BB, 0.098), (REAR, 0.054), (REAR + V((0, 0.005, -0.12)), 0.022))
    pts = [(c.y + r * math.cos(a), c.z + r * math.sin(a)) for c, r in circles for a in (2 * math.pi * k / 16 for k in range(16))]
    belt = [V((-0.068, y, z)) for y, z in hull2d(pts)]
    tube(P, belt, 0.004 * SQ2, MID, n=4, closed=True, ry=0.006 * SQ2)
    r = REAR
    box(P, r + V((-0.082, 0, -0.005)), r + V((-0.082, 0.012, -0.05)), 0.006, 0.012, MID)  # derailleur hanger
    box(P, r + V((-0.086, 0.012, -0.045)), r + V((-0.086, 0.0, -0.125)), 0.007, 0.016, DARK)  # cage
    cyl_x(P, r + V((0, 0.005, -0.12)), -0.078, -0.07, 0.02, MID)  # jockey wheel
    box(P, V((0.05, 0.19, 0.30)), V((0.07, 0.215, 0.29)), 0.012, 0.012, DARK)  # kickstand (folded, left)
    tube(P, [V((0.065, 0.205, 0.29)), V((0.085, 0.46, 0.33))], 0.009, DARK, caps=(False, True))
    box(P, V((0.087, 0.45, 0.322)), V((0.087, 0.49, 0.328)), 0.004, 0.016, DARK)
    return P


def steering():
    P = Part("Bike_Steering", ax(0.53), 0.008)
    crown = ax(0.43)
    box(P, crown - X * 0.095, crown + X * 0.095, 0.022, 0.03, DARK, hull=True)
    for sx in (1, -1):
        leg = X * sx * 0.078
        tube(P, line(crown + leg, ax(0.25) + leg), 0.017, MID, hull=True)
        tube(P, line(ax(0.0) + leg, ax(0.27) + leg, 5), 0.025, DARK, caps=(True, True), hull=True,
             paint=lambda t, n, sx=sx: (DARK, 2 if sx > 0 else 3) if n.x * sx > 0.35 else None)
    tube(P, line(ax(0.60), ax(0.66)), 0.02, MID, caps=(False, True))  # steerer + spacers
    s0 = ax(0.645)
    bar = s0 + V((0, -0.085, 0.025))
    box(P, s0, bar, 0.02, 0.018, DARK, hull=True)  # stem
    tube(P, line(bar - X * 0.34, bar + X * 0.34, 2), 0.0125, DARK, caps=(True, True), hull=True)
    for sx in (1, -1):
        tube(P, line(bar + X * sx * 0.25, bar + X * sx * 0.345), 0.019, DARK, caps=(True, True), hull=True)
        l0 = bar + X * sx * 0.215
        cyl_x(P, l0, -0.012, 0.012, 0.02, MID, n=6)
        box(P, l0 + V((0, -0.015, -0.005)), l0 + X * sx * 0.085 + V((0, -0.06, -0.03)), 0.006, 0.012, MID)
        box(P, bar + X * sx * 0.175 + V((0, 0, -0.02)), bar + X * sx * 0.175 + V((0, -0.02, -0.045)), 0.012, 0.012, MID)
        p0 = l0 + V((0, -0.015, 0.012))
        if sx > 0:  # front brake: loops down to the caliper on the left leg
            end = ax(0.25) + X * 0.078 + V((0, -0.03, 0))
            pts = bezier(p0, p0 + V((0, -0.2, 0.03)), end + V((0, -0.14, 0.17)), end)
        else:  # rear brake: loops into the down tube
            end = ax(0.50) + V((-0.03, -0.03, -0.02))
            pts = bezier(p0, p0 + V((0, -0.2, 0.03)), end + V((0, -0.16, 0.03)), end)
        tube(P, pts, 0.0045, DARK, n=4)
    cal = FRONT + X * 0.06 + rho(math.radians(62)) * 0.082
    tau = V((0, -math.sin(math.radians(62)), math.cos(math.radians(62))))
    box(P, cal - tau * 0.025, cal + tau * 0.025, 0.012, 0.016, MID)  # brake caliper
    fender(P, FRONT, math.radians(40), math.radians(165), 10, red_end=True)
    return P


def crankset():
    P = Part("Bike_Crankset", BB, 0)
    annulus(P, BB, 0.03, 0.098, -0.071, -0.065, DARK, seg=20)
    annulus(P, BB, 0.098, 0.112, -0.079, -0.074, MID, seg=20)  # chain guard
    cyl_x(P, BB, -0.09, 0.09, 0.013, MID)
    for sx, sy in ((-1, -1), (1, 1)):
        a = BB + X * sx * 0.088
        box(P, a, a + V((0, sy * 0.17, 0)), 0.008, 0.016, DARK)
        p = BB + V((sx * 0.098, sy * 0.17, 0))
        box(P, p, p + X * sx * 0.092, 0.012, 0.045, MID)  # flat pedal
    return P


# ---------------------------------------------------------------- decals, UVs, bake, outline
def decal_uv(P):
    """Second UV map "Decal" puts the COSMIC image on the down tube and the fork lowers; elsewhere off-image."""
    P.bm.loops.layers.uv.new("UVMap")  # first, so it is the FBX's UV0
    uv = P.bm.loops.layers.uv.new("Decal")
    a, b = ax(0.49), BB
    d, L = (b - a).normalized(), (b - a).length
    up = V((0, -d.z, d.y))
    w = V((0, -AXIS.z, AXIS.y))  # perpendicular to the fork, pointing forward
    for f in P.bm.faces:
        k = f[P.dec]
        for lp in f.loops:
            p = lp.vert.co
            if k == 1:
                u = ((p - a).dot(d) / L - 0.3) / 0.4
                lp[uv].uv = (u if p.x > 0 else 1 - u, 0.5 + (p - a).dot(up) / 0.07)
            elif k in (2, 3):
                sx = 1 if k == 2 else -1
                q = ax(0.0) + X * sx * 0.078
                lp[uv].uv = (((p - q).dot(AXIS) - 0.04) / 0.2, 0.5 + sx * (p - q).dot(w) / 0.05)
            else:
                lp[uv].uv = (-5, -5)


def to_object(P, coll):
    bmesh.ops.remove_doubles(P.bm, verts=P.bm.verts[:], dist=1e-5)
    me = bpy.data.meshes.new(P.name)
    P.bm.to_mesh(me)
    me.uv_layers["UVMap"].active = True
    me.uv_layers["UVMap"].active_render = True
    me.transform(Matrix.Translation(-P.pivot))
    ob = bpy.data.objects.new(P.name, me)
    ob.location = P.pivot
    ob["hull"] = P.hull_t
    coll.objects.link(ob)
    smooth(me)
    return ob


def smooth(me):
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(50))  # 8-sided tubes stay round, boxes/rims/fenders stay crisp


def uv_islands(bm, uv):
    bm.faces.index_update()
    seen, out = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        seen.add(f.index)
        stack, isl = [f], []
        while stack:
            g = stack.pop()
            isl.append(g)
            for lp in g.loops:
                o = lp.link_loop_radial_next
                if o is lp or o.face.index in seen:
                    continue
                a, b = (o, o.link_loop_next) if o.vert is lp.vert else (o.link_loop_next, o)
                if (a[uv].uv - lp[uv].uv).length < 1e-5 and (b[uv].uv - lp.link_loop_next[uv].uv).length < 1e-5:
                    seen.add(o.face.index)
                    stack.append(o.face)
        out.append(isl)
    return out


def boost(me):
    """Text and stripe islands get twice the texel density."""
    bm = bmesh.new()
    bm.from_mesh(me)
    uv, dec = bm.loops.layers.uv["UVMap"], bm.faces.layers.int["Dec"]
    for isl in uv_islands(bm, uv):
        if any(f[dec] for f in isl):
            loops = [lp for f in isl for lp in f.loops]
            c = sum((lp[uv].uv for lp in loops), V((0, 0))) / len(loops)
            for lp in loops:
                lp[uv].uv = c + (lp[uv].uv - c) * 2
    bm.to_mesh(me)
    bm.free()


def unwrap(objs):
    ts = bpy.context.scene.tool_settings
    ts.use_uv_select_sync = True
    select(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.0, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        boost(o.data)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        for d in o.data.uv_layers["UVMap"].data:
            d.uv = d.uv * INK_TILE


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def make_decal():
    """COSMIC in white, slanted, with a thin black outline, rendered flat to a 4:1 transparent PNG."""
    sc = bpy.data.scenes.new("Decal")
    path = r"C:\Windows\Fonts\ariblk.ttf"
    font = bpy.data.fonts.load(path) if os.path.exists(path) else None
    obs = []
    for z, c, off in ((0.01, WHITE, 0.0), (0.0, INK, 0.045)):
        cu = bpy.data.curves.new("COSMIC", "FONT")
        cu.body, cu.align_x, cu.align_y, cu.shear, cu.offset = "COSMIC", "CENTER", "CENTER", 0.3, off
        if font:
            cu.font = font
        m = bpy.data.materials.new("Decal")
        m.diffuse_color = lin(c)
        cu.materials.append(m)
        ob = bpy.data.objects.new("COSMIC", cu)
        ob.location.z = z
        sc.collection.objects.link(ob)
        obs.append(ob)
    cam = bpy.data.objects.new("DecalCam", bpy.data.cameras.new("DecalCam"))
    cam.data.type = "ORTHO"
    cam.location = (0, 0, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.view_layers[0].update()
    dg = sc.view_layers[0].depsgraph
    cam.data.ortho_scale = obs[1].evaluated_get(dg).dimensions.x * 1.06
    r = sc.render
    r.engine, r.resolution_x, r.resolution_y, r.film_transparent = "BLENDER_WORKBENCH", SIZE, SIZE // 4, True
    r.image_settings.file_format, r.image_settings.color_mode = "PNG", "RGBA"
    sc.display.shading.light, sc.display.shading.color_type = "FLAT", "MATERIAL"
    sc.display.shading.show_object_outline = False
    sc.view_settings.view_transform = "Standard"
    r.filepath = os.path.join(HERE, "Cosmic_Decal.png")
    bpy.ops.render.render(write_still=True, scene=sc.name)
    return bpy.data.images.load(r.filepath)


def feed(nt, sock, v):
    if isinstance(v, bpy.types.NodeSocket):
        nt.links.new(v, sock)
    else:
        sock.default_value = v


def math_node(nt, op, a, b):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    feed(nt, n.inputs[0], a)
    feed(nt, n.inputs[1], b)
    return n.outputs[0]


def mix(nt, fac, a, b, blend="MIX"):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type, m.blend_type = "RGBA", blend
    ins = [i for i in m.inputs if i.type == "RGBA"]
    feed(nt, m.inputs[0], fac)
    feed(nt, ins[0], a)
    feed(nt, ins[1], b)
    return next(o for o in m.outputs if o.type == "RGBA")


def bake_material(decal, target):
    """Flat colour + decal, AO through a hard step (two-tone shadow), ink hatching in creases,
    a lighter cel band and a white stroke where the normal faces the key light. Emission only."""
    mat = bpy.data.materials.new("BikeBake")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    uvd = nt.nodes.new("ShaderNodeUVMap")
    uvd.uv_map = "Decal"
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image, img.extension = decal, "CLIP"
    nt.links.new(uvd.outputs[0], img.inputs[0])
    base = mix(nt, img.outputs["Alpha"], attr.outputs["Color"], img.outputs["Color"])
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples, ao.only_local = 16, False
    ao.inputs["Distance"].default_value = 0.07
    lit = math_node(nt, "GREATER_THAN", ao.outputs["AO"], 0.55)
    crease = math_node(nt, "LESS_THAN", ao.outputs["AO"], 0.3)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type, wave.bands_direction = "BANDS", "DIAGONAL"
    wave.inputs["Scale"].default_value = 9.0
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    hatch = math_node(nt, "MULTIPLY", crease, math_node(nt, "GREATER_THAN", wave.outputs["Fac"], 0.8))
    shade = mix(nt, lit, mix(nt, 1.0, base, (0.58, 0.58, 0.58, 1), "MULTIPLY"), base)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    dot.inputs[1].default_value = V((0.25, -0.35, 0.9)).normalized()
    facing = dot.outputs["Value"]
    band = math_node(nt, "MULTIPLY", lit, math_node(nt, "GREATER_THAN", facing, 0.8))
    stroke = math_node(nt, "MULTIPLY", lit, math_node(nt, "GREATER_THAN", facing, 0.95))
    c = mix(nt, band, shade, mix(nt, 1.0, base, (1.6, 1.6, 1.6, 1), "MULTIPLY"))
    c = mix(nt, math_node(nt, "MULTIPLY", stroke, 0.8), c, lin(WHITE))
    c = mix(nt, hatch, c, lin(INK))
    em = nt.nodes.new("ShaderNodeEmission")
    feed(nt, em.inputs["Color"], c)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    tgt = nt.nodes.new("ShaderNodeTexImage")
    tgt.image = target
    nt.nodes.active = tgt
    return mat


def bake(objs, decal):
    img = bpy.data.images.new("Bike_Albedo", SIZE, SIZE, alpha=False)
    mat = bake_material(decal, img)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    sc = bpy.context.scene
    try:
        sc.render.engine = "CYCLES"
    except TypeError as e:
        raise SystemExit(f"no Cycles: {e}")
    sc.cycles.device, sc.cycles.samples = "CPU", 32
    select(objs)
    bpy.ops.object.bake(type="EMIT", margin=6, use_clear=True)
    px = np.empty(SIZE * SIZE * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(SIZE, SIZE, 4)
    k = int(SIZE * (INK_TILE + 0.004))
    px[k:, k:, :3] = INK  # the outline's corner
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(HERE, "Bike_Albedo_1024.png")
    img.file_format = "PNG"
    img.save()
    return img


def add_hull(ob):
    t = ob["hull"]
    if not t:
        return
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    hl, uv = bm.faces.layers.int["Hull"], bm.loops.layers.uv["UVMap"]
    src = [f for f in bm.faces if f[hl] == 1]
    bm.normal_update()
    acc = {}  # averaged normal per position, so split edges don't crack the shell
    for f in src:
        for v in f.verts:
            k = tuple(round(c, 4) for c in v.co)
            acc[k] = acc.get(k, V()) + v.normal
    geom = bmesh.ops.duplicate(bm, geom=list({v for f in src for v in f.verts}) + list({e for f in src for e in f.edges}) + src)["geom"]
    faces = [g for g in geom if isinstance(g, bmesh.types.BMFace)]
    for g in geom:
        if isinstance(g, bmesh.types.BMVert):
            g.co += acc[tuple(round(c, 4) for c in g.co)].normalized() * t
    bmesh.ops.reverse_faces(bm, faces=faces)
    ink = (INK_TILE + 1) / 2
    for f in faces:
        f[hl] = 2
        for lp in f.loops:
            lp[uv].uv = (ink, ink)
    bm.to_mesh(ob.data)
    bm.free()
    smooth(ob.data)


def final_material(img):
    mat = bpy.data.materials.new("Bike_Toon")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.nodes.active = tex
    return mat


def report(objs):
    total = 0
    for o in objs:
        me = o.data
        me.calc_loop_triangles()
        hl = me.attributes["Hull"].data
        hull = sum(1 for tri in me.loop_triangles if hl[tri.polygon_index].value == 2)
        n = len(me.loop_triangles)
        total += n
        print(f"{o.name:16} tris {n:5} (body {n - hull:5}, outline {hull:4})  loc {tuple(round(c, 3) for c in o.location)}  rot {tuple(o.rotation_euler)} scale {tuple(o.scale)}")
    print("TOTAL tris", total)


def preview(objs):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_backface_culling, sh.show_object_outline = "FLAT", "TEXTURE", True, False
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = 1400, 900
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("W")
    sc.world.color = (0.75, 0.78, 0.82)
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    target = V((0, 0, 0.52))
    for name, pos, ortho in (("side", V((-4, 0, 0.52)), 2.05), ("34", V((2.4, -2.6, 1.5)), 0)):
        cam.location = pos
        cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
        cam.data.type = "ORTHO" if ortho else "PERSP"
        cam.data.ortho_scale, cam.data.lens = ortho or 1, 55
        sc.render.filepath = os.path.join(HERE, f"preview_{name}.png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    coll = bpy.data.collections.new("CosmicBike")
    bpy.context.scene.collection.children.link(coll)
    parts = [frame(), steering(), wheel("Bike_Wheel_Front", FRONT, True), wheel("Bike_Wheel_Rear", REAR, False), crankset()]
    for P in parts:
        decal_uv(P)
    objs = [to_object(P, coll) for P in parts]
    unwrap(objs)
    decal = make_decal()
    img = bake(objs, decal)
    mat = final_material(img)
    for o in objs:
        add_hull(o)
        me = o.data
        me.uv_layers.remove(me.uv_layers["Decal"])
        me.color_attributes.remove(me.color_attributes["Col"])
        me.materials.clear()
        me.materials.append(mat)
    objs[1]["steer_axis"] = tuple(AXIS)  # HingeConstraint axis for steering (Blender axes)
    report(objs)
    preview(objs)
    select(objs)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(HERE, "CosmicBike.fbx"), use_selection=True, object_types={"MESH"},
        use_mesh_modifiers=True, mesh_smooth_type="OFF", use_triangles=True, path_mode="COPY",
        embed_textures=True, add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y",
        global_scale=1 / 28)  # Roblox reads this FBX as cm (1 m = 100 studs); 1/28 gives 1 stud = 0.28 m
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "cosmic_bike.blend"))


main()
