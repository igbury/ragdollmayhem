# 90s-comic backpack-less leaf blower (hero model + the source of the in-game LeafBlower mesh):
# modular parts in named collections, the revolver's procedural toon shader (hard bands, hatching,
# halftone), inverted-hull + Grease Pencil Line Art ink. Metres, tube +X, handle +Z, grille -Y,
# feet on z = 0. Shares its helpers with revolver_90s.py. Run inside Blender (or headless):
#   ns = {"__file__": r"<repo>/assets/weapons/leafblower_90s.py"}; exec(open(ns["__file__"]).read(), ns); ns["build"]()
#   ns["render_all"](r"<out dir>")  # the four check shots
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "leafblower_90s.blend")

R = {"__name__": "revolver_90s", "__file__": os.path.join(HERE, "revolver_90s.py")}
exec(open(R["__file__"]).read(), R)
srgb, toon, ink_mat, prism, box, cyl, screw, boolean = (R[k] for k in (
    "srgb", "toon", "ink_mat", "prism", "box", "cyl", "screw", "boolean"))

COLLS = ["01_Housing_And_Handle", "02_Intake_Grille_And_Impeller", "03_Rear_Engine_And_Tank",
         "04_Blower_Tube", "05_Line_Art_And_FX", "06_Studio_Lights_Camera"]
R["COLLS"] = COLLS  # revolver reset() makes these

WHITE = srgb("DCE1E6")
ORANGE = srgb("FF5A00")
GRAPHITE = srgb("2F3845")
DARKGREY = srgb("202630")
YELLOW = srgb("FFD21A")
STEEL = srgb("B4BDC7")
BLACK = (0, 0, 0, 1)

CZ = 0.22          # fan axis height
HW = 0.075         # half width of the volute (y)
R0, R1 = 0.105, 0.165
PHI0, PHI1 = -55.0, 270.0
TUBE_Z = 0.105     # outlet axis height
GRIP = Vector((-0.005, 0.0, 0.455))  # where the hand closes on the top bar (the game mesh's origin)


def coll(n):
    return bpy.data.collections[n]


def part(bm, name, collection, mat, bevel=0.004, segs=2, hull=0.003):
    ob = R["obj_from_bm"](bm, name, collection, mat, bevel=bevel, segs=segs, hull=hull)
    return ob


def ink_faces(ob, test):
    for p in ob.data.polygons:
        if test(p.center, p.normal):
            p.material_index = 1


def annulus(c, axis, r_in, r_out, depth, segs=32, bm=None):
    """A flat ring (washer) along axis 'X' / 'Y' / 'Z' centred at c."""
    bm = bm or bmesh.new()
    rot = {"X": Matrix.Rotation(math.pi / 2, 3, "Y"), "Y": Matrix.Rotation(math.pi / 2, 3, "X"),
           "Z": Matrix.Identity(3)}[axis]
    rings = []
    for z in (-depth / 2, depth / 2):
        for r in (r_out, r_in):
            rings.append([bm.verts.new(Vector(c) + rot @ Vector((math.cos(a) * r, math.sin(a) * r, z)))
                          for a in (2 * math.pi * i / segs for i in range(segs))])
    oa, ia, ob_, ib = rings
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((oa[i], oa[j], ob_[j], ob_[i]))   # outer wall
        bm.faces.new((ia[j], ia[i], ib[i], ib[j]))     # inner wall
        bm.faces.new((oa[j], oa[i], ia[i], ia[j]))     # back face
        bm.faces.new((ob_[i], ob_[j], ib[j], ib[i]))   # front face
    return bm


def sweep(points, half_w, half_h, bm=None, round_=0.6, segs=12, closed=False):
    """A tube with a rounded-rectangle section along a polyline in XZ (y = 0); half_w along Y."""
    bm = bm or bmesh.new()
    pts = [Vector((p[0], 0.0, p[1])) for p in points]
    rings = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = (b - a).normalized()
        n = Vector((-t.z, 0, t.x))  # in-plane normal
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            ca, sa = math.cos(ang), math.sin(ang)
            ex = 2 / (2 + 4 * (1 - round_))  # superellipse: 1 = ellipse, smaller = boxier
            sx = math.copysign(abs(ca) ** ex, ca)
            sy = math.copysign(abs(sa) ** ex, sa)
            ring.append(bm.verts.new(p + n * (half_h * sx) + Vector((0, 1, 0)) * (half_w * sy)))
        rings.append(ring)
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
    for r0, r1 in pairs:
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return bm


# ---------------------------------------------------------------- 01 housing, handle, feet

def volute_outline():
    pts = []
    n = 40
    for i in range(n + 1):
        phi = PHI0 + (PHI1 - PHI0) * i / n
        r = R0 + (R1 - R0) * (phi - PHI0) / (PHI1 - PHI0)
        pts.append((r * math.cos(math.radians(phi)), CZ + r * math.sin(math.radians(phi))))
    bottom = pts[-1][1]
    pts += [(0.2, bottom), (0.2, bottom + 0.1)]  # the outlet duct running forward to the collar
    return pts


def build_housing():
    m = toon("M_Housing", WHITE)
    bm = prism(list(reversed(volute_outline())), -HW, HW)
    ob = part(bm, "Housing_Volute", "01_Housing_And_Handle", m, bevel=0.016, segs=3)
    ob.modifiers["Bevel"].angle_limit = math.radians(60)
    # the fan well behind the grille (dark, deep) and the outlet bore
    boolean(ob, cyl((0, -HW - 0.01, CZ), 0.083, 0.09, "Y", 40))
    boolean(ob, cyl((0.16, 0, TUBE_Z), 0.043, 0.12, "X", 32))
    ink_faces(ob, lambda c, n: (-HW + 0.004 < c.y < -HW + 0.04 and math.hypot(c.x, c.z - CZ) < 0.0835)
              or (c.x > 0.1 and abs(c.y) < HW - 0.004 and math.hypot(c.y, c.z - TUBE_Z) < 0.0435))
    # the seam between the two shell halves: an inked groove running round the outline at y = 0
    seam = bmesh.new()
    outline = volute_outline()
    for (x0, z0), (x1, z1) in zip(outline, outline[1:]):
        mid, d = Vector(((x0 + x1) / 2, 0, (z0 + z1) / 2)), Vector((x1 - x0, 0, z1 - z0))
        nrm = Vector((d.z, 0, -d.x)).normalized()  # outward (outline runs counter-clockwise)
        r = bmesh.ops.create_cube(seam, size=1)
        bmesh.ops.scale(seam, vec=(d.length + 0.002, 0.005, 0.006), verts=r["verts"])
        ang = math.atan2(d.z, d.x)
        bmesh.ops.rotate(seam, verts=r["verts"], matrix=Matrix.Rotation(-ang, 3, "Y"))
        bmesh.ops.translate(seam, vec=mid + nrm * 0.0015, verts=r["verts"])
    part(seam, "Housing_Seam", "01_Housing_And_Handle", ink_mat(), bevel=0, hull=0)
    # screw bosses round the rim: deep sockets on both faces, a screw head sunk in each
    bosses, heads = bmesh.new(), bmesh.new()
    for phi in (20, 95, 160, 215, 255):
        r = R0 + (R1 - R0) * (phi - PHI0) / (PHI1 - PHI0) - 0.022
        x, z = r * math.cos(math.radians(phi)), CZ + r * math.sin(math.radians(phi))
        for s in (-1, 1):
            annulus((x, s * (HW + 0.002), z), "Y", 0.0085, 0.014, 0.008, 16, bosses)
            cyl((x, s * (HW + 0.0005), z), 0.0086, 0.004, "Y", 16, heads)  # the dark socket floor
            screw((x, s * (HW + 0.001), z), 0.0065, "Y", s, heads)
    for x in (0.08, 0.17):
        for s in (-1, 1):
            annulus((x, s * (HW + 0.002), 0.075), "Y", 0.0085, 0.014, 0.008, 16, bosses)
            screw((x, s * (HW + 0.001), 0.075), 0.0065, "Y", s, heads)
    part(bosses, "Housing_ScrewBosses", "01_Housing_And_Handle", m, bevel=0.0015, hull=0.0015)
    sh = part(heads, "Housing_Screws", "01_Housing_And_Handle", toon("M_Graphite", GRAPHITE), bevel=0, hull=0.001)
    # brand plate over the grille (black bar, white lettering blocks) on the -Y side
    logo = bmesh.new()
    box((0.035, -HW - 0.004, 0.33), (0.13, 0.004, 0.026), logo)
    part(logo, "Housing_LogoPlate", "01_Housing_And_Handle", ink_mat(), bevel=0.002, hull=0)
    letters = bmesh.new()
    for i, w in enumerate((0.012, 0.012, 0.016, 0.012, 0.012, 0.012)):
        box((-0.017 + i * 0.019, -HW - 0.0065, 0.33), (w, 0.002, 0.014), letters)
    part(letters, "Housing_LogoLetters", "01_Housing_And_Handle", toon("M_Housing", WHITE), bevel=0, hull=0)
    return ob


HANDLE_PATH = [(-0.104, 0.30), (-0.112, 0.37), (-0.098, 0.425), (-0.065, 0.455), (0.0, 0.462),
               (0.055, 0.455), (0.085, 0.425), (0.09, 0.37), (0.075, 0.30)]


def build_handle():
    m = toon("M_Housing", WHITE)
    part(sweep(HANDLE_PATH, 0.026, 0.024, segs=16, round_=0.55), "Handle_Loop", "01_Housing_And_Handle",
         m, bevel=0, hull=0.003)
    # the black rubber grip sleeve on the top bar, with three chunky ribs
    g = cyl((-0.005, 0, 0.459), 0.03, 0.11, "X", 20)
    for x in (-0.04, -0.005, 0.03):
        cyl((x, 0, 0.459), 0.033, 0.008, "X", 20, g)
    part(g, "Handle_GripSleeve", "01_Housing_And_Handle", toon("M_Graphite", DARKGREY), bevel=0.002, hull=0.0025)
    # throttle lever under the bar (inside the loop) and a stop switch on top
    lever = prism([(-0.035, 0.43), (0.025, 0.43), (0.02, 0.405), (-0.015, 0.395), (-0.035, 0.41)], -0.009, 0.009)
    part(lever, "Handle_Throttle", "01_Housing_And_Handle", toon("M_Graphite", GRAPHITE), bevel=0.002, hull=0.002)
    sw = box((-0.07, 0, 0.452), (0.022, 0.016, 0.03))
    part(sw, "Handle_StopSwitch", "01_Housing_And_Handle", toon("M_Orange", ORANGE), bevel=0.003, hull=0.002)


def build_feet():
    m = toon("M_Housing", WHITE)
    bm = bmesh.new()
    for x0, x1, top in ((0.085, 0.17, 0.07), (-0.215, -0.135, 0.045)):
        for s in (-1, 1):
            y0, y1 = s * 0.048, s * 0.082
            pts = [(x0, top), (x1, top), (x1 - 0.008, 0.0), (x0 + 0.012, 0.0)]  # tapered, chamfered block
            prism(pts, min(y0, y1), max(y0, y1), bm)
    part(bm, "Housing_Feet", "01_Housing_And_Handle", m, bevel=0.006, segs=1)


# ---------------------------------------------------------------- 02 grille + impeller

GR_Y = -HW - 0.006   # base ring plane
GR_R = 0.094


def dome_y(rho):
    rr = min(rho / 0.088, 1.0)
    return GR_Y - 0.05 * math.sqrt(max(0.0, 1 - rr * rr))


def build_grille():
    o = toon("M_Orange", ORANGE)
    # impeller in the well: hub + 14 swept blades, dark steel
    imp = cyl((0, -0.045, CZ), 0.026, 0.05, "Y", 20)
    for i in range(14):
        a = 2 * math.pi * i / 14
        r = bmesh.ops.create_cube(imp, size=1)
        bmesh.ops.scale(imp, vec=(0.055, 0.032, 0.004), verts=r["verts"])
        bmesh.ops.rotate(imp, verts=r["verts"], matrix=Matrix.Rotation(math.radians(25), 3, "Y"))
        bmesh.ops.translate(imp, vec=(0.052, 0, 0), verts=r["verts"])
        bmesh.ops.rotate(imp, verts=r["verts"], matrix=Matrix.Rotation(a, 3, "Y"))
        bmesh.ops.translate(imp, vec=(0, -0.05, CZ), verts=r["verts"])
    part(imp, "Impeller", "02_Intake_Grille_And_Impeller", toon("M_Steel", STEEL), bevel=0.0015, hull=0.0015)
    # base ring with clip tabs on its rim
    base = annulus((0, GR_Y + 0.002, CZ), "Y", 0.08, GR_R, 0.012, 40)
    for i in range(6):
        a = 2 * math.pi * (i + 0.5) / 6
        r = bmesh.ops.create_cube(base, size=1)
        bmesh.ops.scale(base, vec=(0.02, 0.014, 0.016), verts=r["verts"])
        bmesh.ops.translate(base, vec=(GR_R + 0.004, 0, 0), verts=r["verts"])
        bmesh.ops.rotate(base, verts=r["verts"], matrix=Matrix.Rotation(a, 3, "Y"))
        bmesh.ops.translate(base, vec=(0, GR_Y + 0.003, CZ), verts=r["verts"])
    part(base, "Grille_BaseRing", "02_Intake_Grille_And_Impeller", o, bevel=0.002, hull=0.0025)
    # five concentric rings stepping up the dome
    rings = bmesh.new()
    for rho in (0.07, 0.056, 0.042, 0.03):
        annulus((0, dome_y(rho) + 0.002, CZ), "Y", rho - 0.0045, rho + 0.0045, 0.009, 36, rings)
    part(rings, "Grille_Rings", "02_Intake_Grille_And_Impeller", o, bevel=0.0015, hull=0.0018)
    # eight radial ribs over the dome, from the hub to the base ring
    ribs = bmesh.new()
    for i in range(8):
        a = 2 * math.pi * i / 8 + math.radians(22.5)
        ca, sa = math.cos(a), math.sin(a)
        prof = [0.012 + (0.086 - 0.012) * k / 7 for k in range(8)]
        seg_rings = []
        for rho in prof:
            c = Vector((ca * rho, dome_y(rho) - 0.002, CZ + sa * rho))
            side = Vector((-sa, 0, ca)) * 0.0045
            up = Vector((0, 1, 0)) * 0.005
            seg_rings.append([ribs.verts.new(v) for v in (c + side - up, c - side - up, c - side + up, c + side + up)])
        for r0, r1 in zip(seg_rings, seg_rings[1:]):
            for k in range(4):
                j = (k + 1) % 4
                ribs.faces.new((r0[k], r0[j], r1[j], r1[k]))
        ribs.faces.new(list(reversed(seg_rings[0])))
        ribs.faces.new(seg_rings[-1])
    part(ribs, "Grille_Ribs", "02_Intake_Grille_And_Impeller", o, bevel=0, hull=0.0018)
    cap = cyl((0, dome_y(0) - 0.002, CZ), 0.019, 0.014, "Y", 24)
    cyl((0, dome_y(0) - 0.011, CZ), 0.012, 0.006, "Y", 24, cap)
    part(cap, "Grille_HubCap", "02_Intake_Grille_And_Impeller", o, bevel=0.002, hull=0.002)
    # flat rectangular hinge/latch block at the rear of the grille + a bent wire clip
    latch = box((-0.104, GR_Y - 0.003, CZ), (0.03, 0.022, 0.05))
    part(latch, "Grille_Latch", "02_Intake_Grille_And_Impeller", o, bevel=0.003, hull=0.002)
    wire = sweep([(-0.096, CZ + 0.03), (-0.124, CZ + 0.03), (-0.13, CZ), (-0.124, CZ - 0.03), (-0.096, CZ - 0.03)],
                 0.0028, 0.0028, segs=8, round_=1.0)
    bmesh.ops.translate(wire, vec=(0, GR_Y - 0.016, 0), verts=wire.verts)
    part(wire, "Grille_WireClip", "02_Intake_Grille_And_Impeller", toon("M_Steel", STEEL), bevel=0, hull=0.0012)


# ---------------------------------------------------------------- 03 rear engine + tank

def build_rear():
    g = toon("M_Graphite", GRAPHITE)
    # filter cover on the back: ribbed drum with a twist handle across its face
    cap = cyl((-0.175, 0, 0.255), 0.062, 0.07, "X", 28)
    for i in range(12):
        a = 2 * math.pi * i / 12
        r = bmesh.ops.create_cube(cap, size=1)
        bmesh.ops.scale(cap, vec=(0.06, 0.008, 0.01), verts=r["verts"])
        bmesh.ops.translate(cap, vec=(0, 0, 0.064), verts=r["verts"])
        bmesh.ops.rotate(cap, verts=r["verts"], matrix=Matrix.Rotation(a, 3, "X"))
        bmesh.ops.translate(cap, vec=(-0.178, 0, 0.255), verts=r["verts"])
    part(cap, "Rear_FilterCover", "03_Rear_Engine_And_Tank", g, bevel=0.003)
    knob = box((-0.215, 0, 0.255), (0.024, 0.026, 0.1))
    part(knob, "Rear_FilterKnob", "03_Rear_Engine_And_Tank", toon("M_Graphite2", DARKGREY), bevel=0.006)
    # the orange cylinder shroud in the recess under the handle, with vent slots
    o = toon("M_Orange", ORANGE)
    sh = cyl((-0.01, 0, 0.352), 0.046, 0.12, "X", 24)
    part(sh, "Rear_CylinderShroud", "03_Rear_Engine_And_Tank", o, bevel=0.004)
    vents = bmesh.new()
    for s in (-1, 1):
        for x in (-0.045, -0.025, -0.005, 0.015):
            box((x, s * 0.044, 0.365), (0.008, 0.008, 0.03), vents)
    part(vents, "Rear_ShroudVents", "03_Rear_Engine_And_Tank", ink_mat(), bevel=0, hull=0)
    # fuel tank: blocky lower-rear module, a flat face on -Y for the warning stickers, a fuel cap
    w = toon("M_Housing", WHITE)
    tank = prism([(-0.245, 0.04), (-0.07, 0.04), (-0.07, 0.165), (-0.21, 0.165), (-0.245, 0.13)], -0.07, 0.07)
    part(tank, "Rear_Tank", "03_Rear_Engine_And_Tank", toon("M_Graphite", GRAPHITE), bevel=0.008, segs=2)
    fc = cyl((-0.225, 0, 0.165), 0.02, 0.03, "Z", 16)
    part(fc, "Rear_FuelCap", "03_Rear_Engine_And_Tank", toon("M_Orange", ORANGE), bevel=0.003)
    # warning stickers: yellow plate, black triangle sign, black/yellow stripes
    y = -0.0745
    st = bmesh.new()
    box((-0.165, y - 0.002, 0.1), (0.1, 0.003, 0.08), st)
    part(st, "Rear_StickerPlate", "03_Rear_Engine_And_Tank", toon("M_Yellow", YELLOW), bevel=0, hull=0)
    sign = bmesh.new()
    tri = prism([(-0.205, 0.075), (-0.165, 0.075), (-0.185, 0.123)], y - 0.0048, y - 0.0036)
    sign.free()
    part(tri, "Rear_StickerSign", "03_Rear_Engine_And_Tank", ink_mat(), bevel=0, hull=0)
    bars = bmesh.new()
    for i in range(4):
        x = -0.14 + i * 0.016
        prism([(x, 0.065), (x + 0.008, 0.065), (x + 0.02, 0.135), (x + 0.012, 0.135)], y - 0.0048, y - 0.0036, bars)
    part(bars, "Rear_StickerStripes", "03_Rear_Engine_And_Tank", ink_mat(), bevel=0, hull=0)
    # pull-start handle on top rear
    ps = sweep([(-0.17, 0.33), (-0.17, 0.35), (-0.13, 0.35), (-0.13, 0.33)], 0.012, 0.008, segs=8, round_=0.8)
    bmesh.ops.translate(ps, vec=(0, 0.04, -0.01), verts=ps.verts)
    part(ps, "Rear_PullStart", "03_Rear_Engine_And_Tank", toon("M_Graphite2", DARKGREY), bevel=0, hull=0.002)


# ---------------------------------------------------------------- 04 tube

def build_tube():
    g = toon("M_Tube", GRAPHITE)
    collar = cyl((0.215, 0, TUBE_Z), 0.058, 0.05, "X", 32)
    boss = box((0.215, 0, TUBE_Z + 0.062), (0.026, 0.03, 0.018))
    part(collar, "Tube_Collar", "04_Blower_Tube", g, bevel=0.004)
    part(boss, "Tube_ClampBoss", "04_Blower_Tube", g, bevel=0.003)
    part(screw((0.215, 0, TUBE_Z + 0.071), 0.009, "Z", 1), "Tube_ClampScrew", "04_Blower_Tube",
         toon("M_Steel", STEEL), bevel=0, hull=0.0012)
    # first section: thicker, slight taper, two raised ribs and a raised name panel on its -Y side
    s1 = cyl((0.345, 0, TUBE_Z), 0.05, 0.22, "X", 32, r2=0.044)
    for x in (0.27, 0.42):
        r = 0.05 - (x - 0.235) / 0.22 * 0.006
        cyl((x, 0, TUBE_Z), r + 0.004, 0.01, "X", 32, s1)
    ob = part(s1, "Tube_Section1", "04_Blower_Tube", g, bevel=0.002)
    pan = box((0.345, -0.046, TUBE_Z), (0.1, 0.012, 0.03))
    part(pan, "Tube_NamePanel", "04_Blower_Tube", toon("M_Graphite2", DARKGREY), bevel=0.003, hull=0.0015)
    lt = bmesh.new()
    for i in range(5):
        box((0.31 + i * 0.018, -0.053, TUBE_Z), (0.011, 0.003, 0.016), lt)
    part(lt, "Tube_NameLetters", "04_Blower_Tube", toon("M_Orange", ORANGE), bevel=0, hull=0)
    # snap coupling with two bayonet lugs
    cp = cyl((0.462, 0, TUBE_Z), 0.054, 0.036, "X", 32)
    for s in (-1, 1):
        box((0.462, 0, TUBE_Z + s * 0.058), (0.024, 0.02, 0.014), cp)
    part(cp, "Tube_Coupling", "04_Blower_Tube", toon("M_Graphite2", DARKGREY), bevel=0.003)
    # nozzle: long, narrowing, hollow (the bore inked black)
    nz = cyl((0.585, 0, TUBE_Z), 0.041, 0.215, "X", 32, r2=0.033)
    lip = cyl((0.688, 0, TUBE_Z), 0.036, 0.012, "X", 32)
    nzo = part(nz, "Tube_Nozzle", "04_Blower_Tube", g, bevel=0.002)
    boolean(nzo, cyl((0.64, 0, TUBE_Z), 0.026, 0.2, "X", 32))
    ink_faces(nzo, lambda c, n: math.hypot(c.y, c.z - TUBE_Z) < 0.0265)
    lo = part(lip, "Tube_NozzleLip", "04_Blower_Tube", g, bevel=0.002)
    boolean(lo, cyl((0.69, 0, TUBE_Z), 0.026, 0.05, "X", 32))
    ink_faces(lo, lambda c, n: math.hypot(c.y, c.z - TUBE_Z) < 0.0265)
    part(cyl((0.56, 0, TUBE_Z), 0.0262, 0.004, "X", 24), "Tube_BoreFloor", "04_Blower_Tube", ink_mat(), bevel=0, hull=0)


# ---------------------------------------------------------------- 05/06 ink, lights, cameras

def build_ink():
    """Grease Pencil Line Art: contour / crease / intersection over the inverted hulls."""
    try:
        gp = bpy.data.grease_pencils_v3.new("Ink_LineArt")
    except AttributeError:
        gp = bpy.data.grease_pencils.new("Ink_LineArt")
    ob = bpy.data.objects.new("Ink_LineArt", gp)
    coll("05_Line_Art_And_FX").objects.link(ob)
    mat = bpy.data.materials.new("GP_Ink")
    bpy.data.materials.create_gpencil_data(mat)
    mat.grease_pencil.color = BLACK
    gp.materials.append(mat)
    for n in ("05_Line_Art_And_FX", "06_Studio_Lights_Camera"):
        coll(n).lineart_usage = "EXCLUDE"
    lay = gp.layers.new("Lines")
    md = ob.modifiers.new("LineArt", "LINEART")
    md.source_type = "SCENE"
    md.target_layer = lay.name
    md.target_material = mat
    md.radius = 0.0019  # GPv3: world-space radius
    md.use_contour = md.use_crease = md.use_intersection = True
    md.crease_threshold = math.radians(130)
    md.use_material = md.use_edge_mark = md.use_loose = False
    # the grille: contour only (no crease lines) so its ribs and slots never fill up with black
    for o in coll("02_Intake_Grille_And_Impeller").objects:
        o.lineart.use_crease_override = True
        o.lineart.crease_threshold = 0.0
    try:
        nm = ob.modifiers.new("Wobble", "GREASE_PENCIL_NOISE")
        nm.factor = 0.002
        nm.factor_thickness = 0.4
        nm.noise_scale = 0.5
    except Exception as e:
        print("noise modifier skipped:", e)


def aim(ob, at):
    ob.rotation_euler = (Vector(at) - ob.location).to_track_quat("-Z", "Y").to_euler()


def build_stage():
    sc = bpy.context.scene
    lc = coll("06_Studio_Lights_Camera")
    # world: warm comic paper to the camera, near-black ambient for the shading
    w = sc.world
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    paper = nt.nodes.new("ShaderNodeBackground")
    paper.inputs[0].default_value = srgb("EFE2C4")
    amb = nt.nodes.new("ShaderNodeBackground")
    amb.inputs[0].default_value = (0.1, 0.1, 0.12, 1)  # just enough fill that turned-away faces band, not blank
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(amb.outputs[0], mix.inputs[1])
    nt.links.new(paper.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])

    def cam(name, loc, at, lens=None, ortho=None):
        c = bpy.data.cameras.new(name)
        if ortho:
            c.type, c.ortho_scale = "ORTHO", ortho
        else:
            c.lens = lens
        c.clip_start = 0.01
        o = bpy.data.objects.new(name, c)
        o.location = loc
        lc.objects.link(o)
        aim(o, at)
        return o

    cam("Cam_Side_Ortho", (0.22, -2.0, 0.24), (0.22, 0, 0.24), ortho=1.05)
    hero = cam("Cam_Hero_3_4", (1.0, -1.05, 0.14), (0.22, 0, 0.22), lens=38)
    cam("Cam_Rear_3_4", (-0.85, -0.7, 0.55), (-0.08, 0, 0.2), lens=38)
    cam("Cam_Grille_Close", (0.12, -0.6, 0.36), (0, -0.09, 0.22), lens=50)
    sc.camera = hero
    sun = bpy.data.lights.new("Key_Sun", "SUN")
    sun.energy = 2.8
    sun.angle = 0.0
    so = bpy.data.objects.new("Key_Sun", sun)
    so.rotation_euler = (-Vector((0.55, -0.6, 0.62))).to_track_quat("-Z", "Y").to_euler()
    rim = bpy.data.lights.new("Rim_Area", "AREA")
    rim.energy, rim.size, rim.color = 120, 0.6, (0.35, 0.85, 1.0)
    ro = bpy.data.objects.new("Rim_Area", rim)
    ro.location = (-0.6, 0.8, -0.2)
    aim(ro, (0.2, 0, 0.15))
    for o in (so, ro):
        lc.objects.link(o)


def finish():
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.validate()
            assert tuple(ob.scale) == (1.0, 1.0, 1.0), ob.name
    print({c: len(coll(c).objects) for c in COLLS})


def build(save=True):
    R["reset"]()
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    for k in ("use_shadows", "shadow_ray_count"):
        try:
            setattr(sc.eevee, k, True if k == "use_shadows" else 2)
        except (AttributeError, TypeError):
            pass
    build_housing()
    build_handle()
    build_feet()
    build_grille()
    build_rear()
    build_tube()
    build_stage()
    try:
        build_ink()
    except Exception as e:
        print("line art failed:", repr(e))
    # the ink hulls must not cast shadows: close up, EEVEE's shadow maps resolve the 3 mm shell and
    # it shades the whole body black (light-facing hull faces are back faces, so culling drops them)
    ink = bpy.data.materials["Ink"]
    if hasattr(ink, "use_backface_culling_shadow"):
        ink.use_backface_culling_shadow = True
    finish()
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=OUT)


def render_all(out_dir, cams=("Cam_Side_Ortho", "Cam_Hero_3_4", "Cam_Grille_Close", "Cam_Rear_3_4")):
    sc = bpy.context.scene
    keep = sc.camera
    for name in cams:
        sc.camera = bpy.data.objects[name]
        sc.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
    sc.camera = keep


if __name__ == "__main__" and bpy.app.background:  # headless: blender -b --python leafblower_90s.py -- <out dir>
    import sys
    build()
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args:
        render_all(args[0])
