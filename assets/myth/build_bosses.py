# The three bosses (Cyclops, Minotaur, Talos) at 3x size, the chains that hold them in their pits and
# the pylons either side of each lair's way out, modelled in code in the kit's comic style: chunky
# rounded shapes, flat saturated colours and the black inverted-hull outline every kit uses
# (assets/army/build.py's Piece). Half cartoon, half scary: angry brows, a glowing eye, tusks, horns.
#
# Run in a live Blender (MCP: it builds in its own scene "MythBosses", never touching the others):
#   exec(open(r"<repo>/assets/myth/build_bosses.py").read())
# or headless, which also saves assets/myth/bosses.blend:
#   blender -b --factory-startup -P assets/myth/build_bosses.py
# then assets/myth/export_bosses.py writes MythKit.glb + manifest.json.
#
# Boss pieces are in RIG space at scale 1 (src/shared/MythRig.luau: feet on y 0, the root at y 6, the
# front -Z, studs): one object per rig part, "<Kind>_<RigPart>", welded to that part in the game, which
# then scales the whole model (Mythology scale ~3). Chain and pylon pieces are in studs as placed.
import math
import os
import re

import bmesh
import bpy
from mathutils import Vector

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:  # exec() from the MCP: the path is given beforehand
    HERE = MYTH_DIR  # noqa: F821
REPO = os.path.dirname(os.path.dirname(HERE))

_src = open(os.path.join(REPO, "assets", "army", "build.py"), encoding="utf-8").read()
_head = _src.split("# ---------------------------------------------------------------- Soldier")[0]
exec(compile(_head, "army_build_toolkit", "exec"))

# ---------------------------------------------------------------- palette --------------------
INK = "121214"
IRON, IRON_L = "3C3E46", "5E626E"
BRONZE, BRONZE_D, BRONZE_L = "C8843A", "8E5A26", "EAB66A"
GOLD = "F2B53A"
BONE = "ECE3CC"
LEATHER, LEATHER_D = "6A4428", "4A2E1A"
EYE_W = "F4F0E0"
MOUTH = "3A1E2A"
WHITE = "FFFFFF"
# Cyclops: cold blue-grey hide, one amber eye
CY, CY_D, CY_L = "7E8CA0", "5E6A7C", "A9B4C2"
CY_IRIS = "FFB020"
FUR, FUR_D = "5E4A3A", "3E3028"
# Minotaur: brown bull, red eyes, ivory horns
MI, MI_D, MI_L = "7A4A30", "48291A", "B98A64"
MI_NOSE, HORN, HORN_D, HOOF = "2E2224", "ECE0C4", "5A4E40", "2A2226"
RED_EYE, KILT = "FF3A2A", "9E2E26"
# Talos: bronze automaton, teal glow, red crest
TA_DARK, PATINA, TEAL, CREST = "2C2E36", "4FA88E", "39D0E6", "B8322A"
TB, TB_D, TB_L = "B06A2C", "6E4420", "D69A4C"  # darker, older bronze than the props
# lair pylons
ROCK, ROCK_D, LAVA, FIRE, FIRE_Y = "5C5864", "3C3942", "FF4E1A", "FF7A1E", "FFD040"
MARBLE, MARBLE_S, MINOAN, CAP_BLACK, STONE = "F1EDE4", "D2CBBE", "B8322A", "26262C", "B9B1A2"

NEON = {CY_IRIS, RED_EYE, TEAL, LAVA, FIRE, FIRE_Y}
OUT = 0.04  # rig-space outline: x3 in the game, like the arena's map-sized pieces
OUT_WORLD = 0.07  # chains and pylons (studs)
KINDS = ("Cyclops", "Minotaur", "Talos")


# ---------------------------------------------------------------- shapes -------------------
def rot_to(d):
    """Euler degrees (Roblox XYZ) turning +Y onto direction d."""
    q = Vector((0, 1, 0)).rotation_difference(Vector(d).normalized())
    return tuple(math.degrees(a) for a in q.to_euler("XYZ"))


def _frame(t):
    t = t.normalized()
    ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
    s = ref.cross(t).normalized()
    return s, t.cross(s).normalized()


def tube(p, pts, radii, h, segs=14, closed=False, caps=True):
    """A loft through Roblox-space points; radii per point: r or (r along side, r along the other
    axis). Ends are fanned shut (open tubes) or joined (closed loops)."""
    pts = [Vector(q) for q in pts]
    n = len(pts)
    loops = []
    for i, c in enumerate(pts):
        if closed:
            t = pts[(i + 1) % n] - pts[i - 1]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        s, v = _frame(t)
        r = radii[i]
        ra, rb = (r, r) if isinstance(r, (int, float)) else r
        loops.append([p.bm.verts.new(R2B @ (c + s * (ra * math.cos(2 * math.pi * k / segs)) + v * (rb * math.sin(2 * math.pi * k / segs)))) for k in range(segs)])
    faces = []
    pairs = list(zip(loops, loops[1:])) + ([(loops[-1], loops[0])] if closed else [])
    for a, b in pairs:
        for k in range(segs):
            faces.append(p.bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k])))
    if caps and not closed:
        for loop, c in ((loops[0], pts[0]), (loops[-1], pts[-1])):
            mid = p.bm.verts.new(R2B @ c)
            for k in range(segs):
                faces.append(p.bm.faces.new((loop[k], loop[(k + 1) % segs], mid)))
    bmesh.ops.recalc_face_normals(p.bm, faces=faces)
    i = p._col(h)
    for f in faces:
        f.material_index = i


def limb(p, a, b, r0, r1, h, bulge=0.12, segs=14, steps=6, flat=1.0):
    """A muscled limb from a to b, rounded at both ends; radius r0 -> r1 swelling by `bulge` in the
    middle; `flat` squashes it front to back."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    pts, radii = [], []
    for phi in (88, 70, 45, 20):  # a's dome
        f = math.radians(phi)
        pts.append(a - d * r0 * math.sin(f) * 0.9)
        radii.append((r0 * math.cos(f), r0 * math.cos(f) * flat))
    for i in range(steps + 1):
        t = i / steps
        r = (r0 + (r1 - r0) * t) * (1 + bulge * math.sin(math.pi * t))
        pts.append(a + (b - a) * t)
        radii.append((r, r * flat))
    for phi in (20, 45, 70, 88):
        f = math.radians(phi)
        pts.append(b + d * r1 * math.sin(f) * 0.9)
        radii.append((r1 * math.cos(f), r1 * math.cos(f) * flat))
    tube(p, pts, radii, h, segs=segs)


def horn(p, pts, r0, h, tip=None, split=0.7, segs=12):
    """A tapering horn, tusk or claw along pts, `tip` colouring its last part."""
    n = len(pts)
    radii = [max(r0 * (1 - i / (n - 1)) ** 0.8, 0.015) for i in range(n)]
    cut = max(2, int(round((n - 1) * split))) if tip else n - 1
    tube(p, pts[:cut + 1], radii[:cut + 1], h, segs=segs)
    if tip:
        tube(p, pts[cut:], radii[cut:], tip, segs=segs)


def curve(a, b, c, n=6):
    """n+1 points on the quadratic curve a -> b (pulled toward c)."""
    a, b, c = Vector(a), Vector(b), Vector(c)
    return [tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * c + t * t * b) for t in (i / n for i in range(n + 1))]


def mirror(fn):
    for s in (-1, 1):
        fn(s)


def tufts(p, ring, h, length=0.7, width=0.45, droop=0.6):
    """Cartoon fur: cones from each (point, outward direction) of `ring`, drooping."""
    for at, out in ring:
        at, out = Vector(at), Vector(out).normalized()
        tip = at + (out + Vector((0, -droop, 0))).normalized() * length
        horn(p, [tuple(at), tuple(at + (tip - at) * 0.5), tuple(tip)], width / 2, h, segs=7)


def grow(p, pivot, k, shift=(0, 0, 0)):
    """Scales everything in the piece so far by k about `pivot`, then moves it by `shift` (Roblox)."""
    piv, sh = R2B @ Vector(pivot), R2B @ Vector(shift)
    for v in p.bm.verts:
        v.co = piv + (v.co - piv) * k + sh


def pauldron(p, s, x, y, col, rim, size=3.1, tilt=22):
    """A domed shoulder guard over the deltoid, tipped outward, a rim round its edge and a lame below."""
    p.ball((size, size * 0.85, size), (s * x, y, 0.05), col, rot=(0, 0, -s * tilt), cut=0.42, segs=20, rings=10)
    p.ring(size * 0.47, 0.13, (s * (x + 0.12), y - 0.1, 0.05), rim, rot=(90, 0, -s * tilt), segs=22, sides=6)
    p.ball((size * 0.92, size * 0.5, size * 0.92), (s * (x + 0.35), y - 0.75, 0.05), col, rot=(0, 0, -s * (tilt + 10)), cut=0.45, segs=18, rings=8)


def arm_muscles(p, s, skin, x=3.62):
    """Bicep in front, tricep behind, a forearm swell: the upper arm stops reading as a tube."""
    p.ball((1.5, 1.9, 1.3), (s * x, 8.05, -0.55), skin, segs=14, rings=8)
    p.ball((1.5, 2.1, 1.3), (s * (x + 0.05), 8.3, 0.5), skin, segs=14, rings=8)


def body_piece(kind, part):
    return Piece(f"{kind}_{part}", exact=True, outline=OUT)


# ---------------------------------------------------------------- shared bits --------------
def shackle(p, at, dia, axis_dir, ring_side):
    """An iron cuff round a limb at `at`, rivets, and a ring on `ring_side` for its chain."""
    at = Vector(at)
    p.cyl(dia, 0.75, tuple(at), IRON, rot=rot_to(axis_dir), segs=18, bevel=0.08)
    p.cyl(dia + 0.16, 0.18, tuple(at + Vector(axis_dir).normalized() * 0.3), IRON_L, rot=rot_to(axis_dir), segs=18)
    p.cyl(dia + 0.16, 0.18, tuple(at - Vector(axis_dir).normalized() * 0.3), IRON_L, rot=rot_to(axis_dir), segs=18)
    side = Vector(ring_side).normalized()
    eye = at + side * (dia / 2 + 0.38)
    p.box((0.5, 0.5, 0.5), tuple(at + side * (dia / 2 + 0.05)), IRON, bevel=0.12)
    p.ring(0.32, 0.11, tuple(eye), IRON_L, rot=(0, 90, 0) if abs(side.z) > 0.7 else (0, 0, 0), segs=14, sides=6)


def collar(p, y, z, r, back):
    """An iron collar round the neck, a ring at the back for the big chain."""
    p.cyl((2 * r, 2 * r * 0.85), 0.8, (0, y, z), IRON, segs=24, bevel=0.1)
    p.cyl((2 * r + 0.18, (2 * r + 0.18) * 0.85), 0.2, (0, y + 0.3, z), IRON_L, segs=24)
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        p.ball((0.22, 0.22, 0.22), (r * 1.02 * math.sin(a), y - 0.05, z - r * 0.87 * math.cos(a)), IRON_L, segs=8, rings=5)
    p.ring(0.42, 0.13, (0, y - 0.1, back), IRON_L, rot=(0, 90, 0), segs=14, sides=6)


# ---------------------------------------------------------------- Cyclops ------------------
# v2 silhouette: top-heavy brute. A huge head slung low in front of a hunched back, one eye the size of
# the face, gorilla shoulders and Popeye forearms ending in fists that nearly drag, short bowed legs.
CY_WRIST_DIA = 3.3  # the wrist shackles: MythRig.RINGS follows (x = 3.9 + dia / 2 + 0.38)


def crack(p, pts, h, r=0.09):
    """A glowing crack: a thin tube over the surface, jagged by its points."""
    tube(p, pts, [r] * len(pts), h, segs=6)


def cyclops():
    K = "Cyclops"
    out = []
    p = body_piece(K, "Head")
    p.ball((3.5, 2.9, 3.1), (0, 11.55, -0.45), CY, segs=24, rings=14)  # a low, flat skull
    p.ball((4.1, 2.1, 3.0), (0, 10.15, -1.0), CY, segs=22, rings=12)  # the jaw, far wider than the skull
    p.ball((3.1, 3.1, 1.1), (0, 11.7, -1.8), CY_D, segs=24, rings=12)  # socket
    p.ball((2.8, 2.8, 1.3), (0, 11.7, -2.0), EYE_W, segs=26, rings=14)  # the eye: the whole face
    p.ball((1.75, 1.75, 0.5), (0, 11.62, -2.6), CY_IRIS, segs=22, rings=12)
    p.ring(0.86, 0.07, (0, 11.62, -2.8), "C0601A", segs=24, sides=5)  # the iris rim
    p.ball((0.34, 1.35, 0.22), (0, 11.62, -2.86), INK, segs=12, rings=8)  # slit pupil
    p.ball((0.4, 0.4, 0.14), (0.5, 12.1, -2.78), WHITE, segs=10, rings=6)
    p.ball((3.4, 1.5, 1.9), (0, 12.62, -1.85), CY, rot=(-24, 0, 0), segs=22, rings=10)  # upper lid, half shut
    p.ball((3.0, 0.75, 1.5), (0, 10.62, -1.95), CY_D, rot=(16, 0, 0), segs=20, rings=8)  # lower lid: a squint
    for s in (-1, 1):  # the brow: a hard V, inner ends right down on the lid
        p.box((2.0, 0.62, 1.0), (s * 0.92, 12.62, -2.42), CY_D, rot=(-18, 0, s * 24), bevel=0.24)
        p.ball((1.3, 0.9, 1.1), (s * 1.55, 12.35, -1.85), CY, segs=14, rings=8)  # the lid's heavy outer corners
    horn(p, curve((0, 12.95, -0.9), (0, 14.9, -1.6), (0, 14.4, -0.5), 6), 0.55, BONE, tip=HORN_D, split=0.8)
    for s in (-1, 1):  # no nose: two slits between the eye and the snarl
        p.ball((0.22, 0.32, 0.12), (s * 0.3, 10.55, -2.62), INK, rot=(0, 0, s * 25), segs=8, rings=4)
    p.ball((3.3, 1.15, 0.85), (0, 9.95, -2.25), MOUTH, segs=22, rings=10)  # a wide snarl
    for i, x in enumerate((-1.25, -0.85, -0.45, -0.05, 0.38, 0.8, 1.2)):  # top fangs, uneven
        z = -2.55 + abs(x) * 0.22
        drop = 0.42 if i % 2 else 0.3
        horn(p, [(x, 10.45, z), (x, 10.45 - drop * 0.5, z - 0.05), (x, 10.45 - drop, z)], 0.19, BONE, segs=8)
    for s in (-1, 1):  # the underbite: tusks up out of the lower jaw, past the nose
        horn(p, curve((s * 1.15, 9.55, -2.35), (s * 1.6, 11.35, -2.75), (s * 1.45, 10.4, -2.95), 5), 0.34, BONE, tip=HORN_D, split=0.85)
        tube(p, [(s * 1.6, 11.35, -0.3), (s * 2.2, 11.75, -0.2), (s * 2.6, 12.25, -0.1)],
             [(0.55, 0.22), (0.4, 0.16), (0.05, 0.04)], CY_D, segs=10)  # pointed ears
        p.ball((0.5, 0.18, 0.12), (s * 1.75, 12.35, -1.55), CY_D, rot=(0, 0, s * 35), segs=8, rings=4)  # frown crease
    grow(p, (0, 10.3, -0.3), 1.38, (0, -0.65, -0.55))  # a huge head, slung low and forward of the neck
    out.append(p)

    p = body_piece(K, "UpperTorso")
    p.ball((5.8, 4.4, 3.8), (0, 8.6, 0.2), CY, segs=24, rings=14)
    p.ball((5.2, 4.1, 3.9), (0, 7.1, -0.75), CY_L, segs=22, rings=12)  # a pot belly
    p.ball((5.6, 3.6, 3.4), (0, 9.8, 1.35), CY, segs=22, rings=12)  # the hunch, up behind the head
    for s in (-1, 1):
        p.ball((2.9, 2.0, 1.5), (s * 1.35, 9.2, -1.25), CY, segs=18, rings=10)  # pecs
        p.ball((3.0, 2.6, 2.8), (s * 2.05, 10.45, 0.35), CY, segs=18, rings=10)  # traps up to the ears
        p.ball((0.9, 0.35, 0.3), (s * 1.0, 6.4, -2.35), CY_D, rot=(0, 0, s * 20), segs=10, rings=4)  # belly folds
    p.ball((0.45, 0.32, 0.2), (0, 6.85, -2.6), CY_D, segs=8, rings=4)
    ring = []
    for i in range(20):  # the fur mantle over the hunch
        a = 2 * math.pi * i / 20
        x, z = 2.9 * math.sin(a), 0.3 - 1.9 * math.cos(a)
        ring.append(((x, 10.5 + 0.15 * math.cos(a), z), (math.sin(a), 0.2, -math.cos(a))))
    p.cyl((5.9, 4.3), 0.9, (0, 10.45, 0.3), FUR, segs=24, d2=4.8)
    tufts(p, ring, FUR, length=1.2, width=0.8, droop=0.9)
    tufts(p, [((x * 0.8, y - 0.1, z * 0.8), d) for (x, y, z), d in ring[::2]], FUR_D, length=0.9, width=0.6, droop=1.2)
    collar(p, 10.75, -0.25, 1.55, 1.3)
    out.append(p)

    p = body_piece(K, "LowerTorso")
    p.ball((3.9, 2.6, 3.0), (0, 5.75, 0.1), CY, segs=20, rings=10)
    p.cyl((4.9, 3.9), 2.3, (0, 5.05, 0.05), FUR, segs=24, d2=4.3)  # a longer kilt: the legs look shorter
    hem = []
    for i in range(18):
        a = 2 * math.pi * i / 18
        hem.append(((2.4 * math.sin(a), 4.0, 0.05 - 1.9 * math.cos(a)), (math.sin(a), -1.5, -math.cos(a))))
    tufts(p, hem, FUR, length=0.95, width=0.8, droop=0.4)
    p.cyl((4.6, 3.6), 0.85, (0, 6.3, 0.05), LEATHER, segs=24, bevel=0.1)
    p.cyl(1.5, 0.32, (0, 6.3, -1.85), BRONZE, axis="z", segs=16, bevel=0.06)
    p.ball((0.7, 0.7, 0.3), (0, 6.3, -2.02), BRONZE_D, segs=12, rings=6)  # a skull-less boss on the buckle
    out.append(p)

    for side, s in (("Left", -1), ("Right", 1)):
        p = body_piece(K, side + "UpperArm")
        p.ball((3.3, 3.1, 3.2), (s * 3.75, 9.45, 0.05), CY, segs=20, rings=12)  # boulder shoulders
        limb(p, (s * 3.65, 9.0, 0), (s * 3.65, 6.8, -0.05), 1.35, 1.0, CY, bulge=0.22)
        p.ball((1.8, 2.2, 1.6), (s * 3.7, 8.0, -0.6), CY, segs=14, rings=8)
        p.ball((1.8, 2.3, 1.6), (s * 3.75, 8.3, 0.55), CY, segs=14, rings=8)
        if s < 0:  # an iron pauldron with bone spikes on the left only
            pauldron(p, s, 3.85, 9.9, IRON, IRON_L, size=3.4)
            for dz, dx in ((-0.85, 0.1), (0.0, 0.5), (0.85, 0.1)):
                base = Vector((s * (3.85 + dx), 11.0 - dx * 0.4, 0.05 + dz))
                horn(p, [tuple(base), tuple(base + Vector((s * 0.4, 0.7, 0))), tuple(base + Vector((s * 0.8, 1.55, 0)))], 0.36, BONE, segs=8)
        else:  # the right: bare, a rope of stitched leather and a bronze band
            p.cyl(2.75, 0.45, (s * 3.66, 7.55, -0.03), BRONZE, segs=18, bevel=0.06)
            p.box((0.35, 2.6, 0.3), (s * 3.75, 8.6, -1.35), LEATHER_D, rot=(0, 0, s * 18), bevel=0.08)
        out.append(p)
        p = body_piece(K, side + "LowerArm")
        p.ball((2.1, 2.0, 2.1), (s * 3.6, 6.7, 0), CY, segs=16, rings=10)
        limb(p, (s * 3.62, 6.6, -0.05), (s * 3.88, 4.55, -0.38), 1.05, 1.55, CY, bulge=0.22)  # Popeye forearms
        shackle(p, (s * 3.9, 4.45, -0.4), CY_WRIST_DIA, (s * 0.12, 1, -0.15), (s, 0, 0))
        out.append(p)
        p = body_piece(K, side + "Hand")
        hand(p, s, CY, CY, BONE, x=3.95)
        grow(p, (s * 3.9, 4.0, -0.4), 1.45)  # fists that nearly drag on the ground
        out.append(p)
        p = body_piece(K, side + "UpperLeg")
        limb(p, (s * 1.25, 5.4, 0), (s * 1.18, 2.7, 0), 1.5, 1.0, CY, bulge=0.2)
        out.append(p)
        p = body_piece(K, side + "LowerLeg")
        p.ball((1.95, 1.7, 1.9), (s * 1.12, 2.6, -0.05), CY, segs=16, rings=10)
        limb(p, (s * 1.14, 2.55, 0), (s * 1.22, 0.9, 0), 1.0, 0.8, CY, bulge=0.12)
        p.ball((1.5, 1.6, 1.3), (s * 1.17, 2.05, 0.38), CY, segs=14, rings=8)
        for y in (1.6, 2.1):
            p.cyl(2.0 - (2.1 - y) * 0.15, 0.22, (s * 1.17, y, 0.02), LEATHER, segs=16)
        shackle(p, (s * 1.2, 1.05, 0), 1.85, (0, 1, 0), (s, 0, 0))
        out.append(p)
        p = body_piece(K, side + "Foot")
        foot(p, s, CY, CY, BONE)
        grow(p, (s * 1.2, 0.0, 0.0), 1.2)
        out.append(p)
    return out


def hand(p, s, skin, finger, nail, x=3.95, fist=False):
    """A big three-fingered hand hanging from the wrist, fingers half curled, a thumb inside."""
    p.ball((2.0, 1.7, 2.0), (s * x, 3.35, -0.55), skin, segs=18, rings=10)
    for d in (-0.62, 0.0, 0.62):
        fx = s * x + d
        pts = [(fx, 2.95, -1.0), (fx, 2.35, -1.35), (fx, 1.85, -1.15), (fx, 1.65, -0.8)]
        tube(p, pts, [0.4, 0.37, 0.34, 0.3], finger, segs=12)
        p.ball((0.62, 0.62, 0.62), (fx, 2.35, -1.35), finger, segs=10, rings=6)  # knuckle
        p.ball((0.58, 0.58, 0.58), (fx, 1.65, -0.8), finger, segs=10, rings=6)
        if nail:
            horn(p, [(fx, 1.6, -0.62), (fx, 1.5, -0.4), (fx, 1.6, -0.2)], 0.2, nail, segs=8)
    tx = s * x - s * 0.95
    tube(p, [(tx, 3.4, -0.8), (tx - s * 0.1, 2.85, -1.35), (tx + s * 0.05, 2.45, -1.6)], [0.42, 0.38, 0.33], finger, segs=12)
    p.ball((0.6, 0.6, 0.6), (tx + s * 0.05, 2.45, -1.6), finger, segs=10, rings=6)
    if nail:
        horn(p, [(tx + s * 0.05, 2.3, -1.75), (tx + s * 0.05, 2.15, -1.6)], 0.17, nail, segs=8)


def foot(p, s, skin, toe, nail):
    p.ball((2.0, 1.4, 3.0), (s * 1.2, 0.5, -0.5), skin, cut=0.12, segs=20, rings=10)
    for d in (-0.62, 0.0, 0.62):
        p.ball((0.78, 0.7, 0.85), (s * 1.2 + d, 0.35, -1.9), toe, segs=12, rings=8)
        if nail:
            p.ball((0.48, 0.32, 0.4), (s * 1.2 + d, 0.42, -2.25), nail, segs=10, rings=6)


# ---------------------------------------------------------------- Minotaur ------------------
# v2 silhouette: a bull built like a V. Horns twice as wide sweeping forward, the head down to charge on
# a huge hump, a barrel chest over a narrow waist, a heavy square underbite with fangs, thick thighs.
def minotaur():
    K = "Minotaur"
    out = []
    p = body_piece(K, "Head")
    p.ball((3.0, 2.6, 2.8), (0, 11.7, -0.45), MI, segs=22, rings=12)  # skull
    p.ball((2.9, 2.3, 3.1), (0, 10.7, -2.0), MI_L, rot=(18, 0, 0), segs=22, rings=12)  # muzzle
    p.box((2.8, 1.05, 2.4), (0, 9.7, -1.85), MI, rot=(-8, 0, 0), bevel=0.42)  # a square, jutting jaw
    p.box((2.4, 0.35, 0.6), (0, 10.2, -2.95), MOUTH, bevel=0.12)  # the snarl line
    for s in (-1, 1):
        horn(p, curve((s * 0.85, 9.95, -2.85), (s * 1.0, 11.0, -3.05), (s * 0.95, 10.6, -3.15), 4), 0.26, BONE, segs=8)  # fangs up
    p.ball((1.9, 0.95, 0.85), (0, 10.6, -3.25), "7A4A44", segs=18, rings=10)  # a moist pink-brown nose pad
    for s in (-1, 1):
        p.ball((0.48, 0.36, 0.22), (s * 0.5, 10.6, -3.68), INK, rot=(0, 0, s * 20), segs=10, rings=5)  # flared nostrils
    p.ring(0.62, 0.15, (0, 10.05, -3.55), GOLD, segs=18, sides=6)
    p.box((2.7, 0.45, 0.8), (0, 12.2, -1.55), MI_D, rot=(-10, 0, 0), bevel=0.2)  # one heavy brow ridge
    for s in (-1, 1):
        p.ball((1.15, 0.6, 0.32), (s * 0.95, 11.62, -2.05), EYE_W, rot=(0, s * -22, s * -16), segs=14, rings=7)
        p.ball((0.75, 0.52, 0.26), (s * 0.9, 11.58, -2.2), RED_EYE, rot=(0, s * -22, s * -16), segs=12, rings=6)  # glowing eyes
        p.ball((0.22, 0.34, 0.12), (s * 0.88, 11.58, -2.32), INK, segs=8, rings=4)
        p.box((1.5, 0.5, 0.8), (s * 0.85, 12.0, -1.95), MI_D, rot=(-12, s * -15, s * 26), bevel=0.2)  # angry brows
        tube(p, [(s * 1.35, 11.4, -0.2), (s * 2.0, 11.25, -0.05), (s * 2.6, 10.95, 0.05)],
             [(0.5, 0.24), (0.42, 0.2), (0.06, 0.05)], MI_D, segs=10)  # ears, pinned back
        # the horns: out wide, then up and forward like a charging bull's, darkening at the tips
        pts = curve((s * 1.2, 12.3, -0.35), (s * 4.1, 15.7, -2.9), (s * 5.6, 12.3, 0.3), 10)
        horn(p, pts, 0.9, HORN, tip=HORN_D, split=0.74, segs=16)
        p.cyl(1.7, 0.45, (s * 1.45, 12.35, -0.3), BRONZE, rot=(0, 0, s * -58), segs=14, bevel=0.06)  # bronze horn bands
        p.cyl(1.45, 0.3, (s * 2.35, 12.75, -0.1), BRONZE_D, rot=(0, 0, s * -40), segs=14)
    tufts(p, [((x, 12.95, -0.8 + 0.1 * abs(x)), (x * 0.3, 1, -0.5)) for x in (-0.5, 0.0, 0.5)], MI_D, length=1.0, width=0.55, droop=-0.2)
    tufts(p, [((x, 9.2, -1.6), (x * 0.2, -1, -0.3)) for x in (-0.4, 0.0, 0.4)], MI_D, length=0.9, width=0.5, droop=0.2)  # chin beard
    grow(p, (0, 10.3, -0.3), 1.26, (0, -0.3, -0.45))  # a big head, lowered to charge
    out.append(p)

    p = body_piece(K, "UpperTorso")
    p.ball((6.8, 4.6, 3.9), (0, 8.85, 0.1), MI, segs=26, rings=14)  # barrel chest
    p.ball((5.4, 4.0, 3.8), (0, 10.25, 1.05), MI, segs=22, rings=12)  # the bull's hump
    p.ball((3.2, 2.8, 2.7), (0, 7.0, -0.2), MI, segs=20, rings=10)  # a narrow waist
    for s in (-1, 1):
        p.ball((3.3, 2.4, 1.6), (s * 1.5, 9.2, -1.3), MI, rot=(0, 0, s * -8), segs=18, rings=10)  # slab pecs
        p.ball((2.6, 2.4, 2.6), (s * 2.3, 10.5, 0.4), MI, segs=16, rings=10)  # traps
        for y, w in ((8.0, 1.05), (7.25, 0.95), (6.55, 0.85)):
            p.ball((w, 0.65, 0.5), (s * 0.55, y, -1.45), MI_L, segs=10, rings=6)  # abs
    p.ball((1.7, 2.0, 0.7), (0, 9.3, -1.95), MI_L, segs=12, rings=8)
    tufts(p, [((x, 9.5 - abs(x) * 0.2, -2.1), (x * 0.4, -0.2, -1)) for x in (-0.6, 0.0, 0.6)], MI_L, length=0.9, width=0.55, droop=1.0)
    mane = []
    for i in range(10):
        t = i / 9
        mane.append(((0, 11.6 - t * 3.0, 0.7 + t * 1.5 + math.sin(t * 3) * 0.2), (0, 0.4, 1)))
    tufts(p, mane, MI_D, length=1.1, width=0.8, droop=0.8)
    p.box((0.55, 6.0, 0.3), (0, 8.7, -1.95), LEATHER_D, rot=(0, 0, 38), bevel=0.08)  # a harness strap
    p.cyl(0.9, 0.3, (0.0, 8.7, -2.12), BRONZE, axis="z", segs=14, bevel=0.05)
    collar(p, 10.9, -0.15, 1.5, 1.25)
    out.append(p)

    p = body_piece(K, "LowerTorso")
    p.ball((3.4, 2.4, 2.6), (0, 5.8, 0.1), MI, segs=20, rings=10)
    p.cyl((3.9, 3.1), 0.7, (0, 6.3, 0.05), BRONZE, segs=24, bevel=0.1)
    for i in range(14):  # pteruges
        a = 2 * math.pi * (i + 0.5) / 14
        x, z = 1.95 * math.sin(a), 0.05 - 1.5 * math.cos(a)
        col = KILT if i % 2 == 0 else LEATHER_D
        rot = (-12 * math.cos(a), math.degrees(-a), 12 * math.sin(a))
        p.box((0.8, 2.2, 0.18), (x * 1.05, 4.9, z * 1.05), col, rot=rot, bevel=0.06)
        p.box((0.8, 0.25, 0.22), (x * 1.13, 3.85, z * 1.13), BRONZE_L, rot=rot, bevel=0.05)
    p.cyl(1.3, 0.32, (0, 6.3, -1.55), GOLD, axis="z", segs=16, bevel=0.06)
    tube(p, curve((0, 5.9, 1.3), (0.6, 2.9, 2.2), (0.2, 5.2, 2.8), 6), [0.24] * 7, MI, segs=10)
    p.ball((0.8, 1.3, 0.8), (0.62, 2.65, 2.2), MI_D, segs=10, rings=6)
    out.append(p)

    for side, s in (("Left", -1), ("Right", 1)):
        p = body_piece(K, side + "UpperArm")
        p.ball((2.9, 2.8, 2.9), (s * 3.75, 9.4, 0.05), MI, segs=18, rings=10)
        limb(p, (s * 3.65, 9.0, 0), (s * 3.65, 6.8, -0.05), 1.3, 0.95, MI, bulge=0.25)
        p.ball((1.8, 2.3, 1.6), (s * 3.7, 8.05, -0.65), MI, segs=14, rings=8)  # bicep
        p.ball((1.7, 2.3, 1.5), (s * 3.75, 8.35, 0.55), MI, segs=14, rings=8)
        if s < 0:  # one bronze pauldron, the other shoulder bare
            pauldron(p, s, 3.85, 9.9, BRONZE, BRONZE_L, size=3.2)
            for dz in (-0.7, 0.0, 0.7):
                base = Vector((s * 4.5, 10.85, 0.05 + dz))
                horn(p, [tuple(base), tuple(base + Vector((s * 0.5, 0.7, 0))), tuple(base + Vector((s * 0.9, 1.35, 0)))], 0.27, BRONZE_L, segs=8)
        else:
            for y in (8.9, 8.3):
                p.cyl(2.55, 0.22, (s * 3.67, y, -0.02), LEATHER_D, segs=16)
        out.append(p)
        p = body_piece(K, side + "LowerArm")
        p.ball((1.9, 1.9, 1.9), (s * 3.6, 6.7, 0), MI, segs=16, rings=10)
        limb(p, (s * 3.62, 6.6, -0.05), (s * 3.88, 4.35, -0.38), 1.05, 1.15, MI, bulge=0.18)
        p.cyl(2.4, 1.0, (s * 3.75, 5.65, -0.2), BRONZE, rot=(-8, 0, s * 6), segs=18, d2=2.65, bevel=0.06)
        for k in range(3):
            a = math.radians(-60 + k * 60)
            base = Vector((s * 3.75 + s * 1.25 * math.cos(a), 5.65, -0.2 + 1.25 * math.sin(a)))
            horn(p, [tuple(base), tuple(base + Vector((s * 0.7 * math.cos(a), 0.1, 0.7 * math.sin(a))))], 0.22, BRONZE_L, segs=8)
        shackle(p, (s * 3.9, 4.45, -0.4), 2.45, (s * 0.12, 1, -0.15), (s, 0, 0))
        out.append(p)
        p = body_piece(K, side + "Hand")
        hand(p, s, MI_D, MI_D, HOOF, x=3.95)
        grow(p, (s * 3.9, 4.0, -0.4), 1.15)
        out.append(p)
        p = body_piece(K, side + "UpperLeg")
        limb(p, (s * 1.2, 5.4, 0), (s * 1.12, 2.7, 0.1), 1.45, 0.9, MI, bulge=0.22)  # huge thighs
        p.ball((1.7, 2.0, 1.5), (s * 1.25, 4.2, -0.55), MI, segs=14, rings=8)
        out.append(p)
        p = body_piece(K, side + "LowerLeg")
        p.ball((1.7, 1.6, 1.7), (s * 1.1, 2.6, -0.05), MI, segs=16, rings=10)
        limb(p, (s * 1.12, 2.55, 0.15), (s * 1.2, 1.0, 0), 0.85, 0.6, MI, bulge=0.12)
        p.ball((1.4, 1.7, 1.3), (s * 1.15, 2.1, 0.45), MI, segs=14, rings=8)  # calves set back: a bull's hock
        fet = []
        for i in range(10):
            a = 2 * math.pi * i / 10
            fet.append(((s * 1.2 + 0.72 * math.sin(a), 0.95, -0.72 * math.cos(a)), (math.sin(a), -0.6, -math.cos(a))))
        tufts(p, fet, MI_D, length=0.65, width=0.6, droop=0.6)
        shackle(p, (s * 1.2, 1.35, 0), 1.75, (0, 1, 0), (s, 0, 0))
        out.append(p)
        p = body_piece(K, side + "Foot")
        for d in (-0.5, 0.5):
            p.ball((1.05, 1.35, 2.6), (s * 1.2 + d, 0.5, -0.6), HOOF, cut=0.12, segs=16, rings=10)
        p.box((0.25, 0.95, 1.3), (s * 1.2, 0.45, -1.35), INK, bevel=0.05)
        out.append(p)
    return out


# ---------------------------------------------------------------- Talos --------------------
# v2 silhouette: a walking monument. A wide armoured block with towering layered pauldrons, a narrow
# glowing visor under a V brow, a fin of crest spikes, hammer fists, pillar legs, and glowing teal
# cracks running out of the core across the bronze.
def talos():
    K = "Talos"
    out = []
    p = body_piece(K, "Head")
    p.ball((3.1, 3.5, 3.2), (0, 11.5, -0.45), TB, segs=24, rings=14)
    p.box((2.8, 2.9, 0.9), (0, 11.15, -1.75), TB_D, bevel=0.35)  # the face plate
    for s in (-1, 1):
        p.box((1.55, 0.6, 0.7), (s * 0.78, 12.2, -2.2), TB_L, rot=(0, 0, s * 24), bevel=0.15)  # a V brow, low over the eyes
        p.box((1.15, 0.3, 0.32), (s * 0.7, 11.72, -2.24), TEAL, rot=(0, 0, s * 18), bevel=0.06)  # slit eyes, angled down
        p.box((1.05, 2.1, 0.55), (s * 1.0, 10.5, -1.95), TB, rot=(0, s * 20, 0), bevel=0.2)  # cheek guards
        p.ball((0.32, 0.32, 0.32), (s * 1.5, 11.25, -1.35), TB_L, segs=8, rings=4)
    p.box((1.7, 0.95, 0.3), (0, 10.55, -2.25), INK, bevel=0.08)  # the mouth grille
    for x in (-0.55, -0.18, 0.18, 0.55):
        p.box((0.16, 0.7, 0.2), (x, 10.55, -2.38), TEAL, bevel=0.03)
    p.box((0.32, 1.1, 0.4), (0, 11.45, -2.25), TB_L, bevel=0.1)  # nose guard
    for i in range(7):  # the crest: a fin of red spikes from brow to nape
        t = i / 6
        y, z = 13.0 + math.sin(t * math.pi) * 0.5, -1.4 + t * 3.0
        h = 1.6 + math.sin(t * math.pi) * 1.4
        horn(p, [(0, y, z), (0, y + h * 0.55, z + 0.35), (0, y + h, z + 0.8)], 0.5, CREST, segs=8)
    p.box((0.55, 0.6, 3.6), (0, 13.0, -0.3), TB_D, bevel=0.15)
    crack(p, [(0.9, 12.7, -1.62), (1.15, 12.2, -1.95), (1.0, 11.95, -2.1)], TEAL, r=0.07)
    grow(p, (0, 10.3, -0.3), 1.22, (0, -0.25, -0.25))
    out.append(p)

    p = body_piece(K, "UpperTorso")  # a monumental cuirass, a glowing core cracked open
    p.ball((6.6, 4.8, 3.8), (0, 8.75, 0.05), TB, segs=26, rings=14)
    p.ball((5.4, 3.4, 3.0), (0, 9.7, 1.0), TB, segs=20, rings=10)
    p.ball((4.2, 3.2, 3.0), (0, 7.15, -0.45), TB, segs=20, rings=10)
    for s in (-1, 1):
        p.box((2.9, 2.3, 0.9), (s * 1.45, 9.25, -1.55), TB_L, rot=(8, s * 12, s * -6), bevel=0.35)  # chest plates
        for k in range(5):
            p.ball((0.24, 0.24, 0.24), (s * 2.85, 7.4 + k * 0.6, -0.5), TB_D, segs=8, rings=4)
    for y, w, z in ((7.9, 2.9, -1.85), (7.2, 2.7, -1.95), (6.5, 2.4, -1.85)):
        p.box((w, 0.55, 0.45), (0, y, z), TB_L, bevel=0.18)
    p.cyl(1.9, 0.5, (0, 9.05, -2.3), TEAL, axis="z", segs=20)  # the core
    p.ring(1.1, 0.24, (0, 9.05, -2.48), TB_D, segs=22, sides=6)
    for pts in (  # cracks out of the core
        [(0.6, 9.5, -2.1), (1.2, 10.1, -1.95), (1.0, 10.6, -1.85), (1.6, 11.0, -1.5)],
        [(-0.6, 9.4, -2.1), (-1.3, 9.0, -2.0), (-1.9, 9.5, -1.8), (-2.5, 9.0, -1.4)],
        [(0.3, 8.4, -2.12), (0.75, 7.95, -2.15), (0.5, 7.45, -2.2), (1.1, 6.9, -2.1)],
        [(-0.5, 8.5, -2.1), (-1.6, 7.9, -1.95), (-2.1, 7.2, -1.7)],
    ):
        crack(p, pts, TEAL)
    p.cyl(2.0, 1.2, (0, 10.4, -0.15), TA_DARK, segs=16)
    collar(p, 10.75, -0.15, 1.35, 1.1)
    out.append(p)

    p = body_piece(K, "LowerTorso")
    p.ball((3.8, 2.6, 2.9), (0, 5.75, 0.1), TA_DARK, segs=20, rings=10)
    p.cyl((4.6, 3.6), 0.9, (0, 6.3, 0.05), TB_D, segs=24, bevel=0.1)
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        x, z = 2.2 * math.sin(a), 0.05 - 1.7 * math.cos(a)
        rot = (-10 * math.cos(a), math.degrees(-a), 10 * math.sin(a))
        p.box((1.05, 2.0, 0.22), (x * 1.06, 5.0, z * 1.06), TB if i % 2 else TB_D, rot=rot, bevel=0.07)
        p.ball((0.26, 0.26, 0.26), (x * 1.12, 4.25, z * 1.12), TB_D, segs=8, rings=4)
    p.cyl(1.1, 0.3, (0, 6.3, -1.8), TEAL, axis="z", segs=14)
    out.append(p)

    for side, s in (("Left", -1), ("Right", 1)):
        p = body_piece(K, side + "UpperArm")
        p.ball((2.3, 2.3, 2.3), (s * 3.6, 9.3, 0.0), TA_DARK, segs=14, rings=8)
        pauldron(p, s, 3.95, 10.0, TB, TB_L, size=4.2, tilt=24)  # towering, layered pauldrons
        p.ball((3.6, 1.6, 3.6), (s * 4.45, 8.85, 0.05), TB_D, rot=(0, 0, -s * 34), cut=0.45, segs=18, rings=8)
        for dz in (-0.9, 0.0, 0.9):  # bronze spikes up the pauldron's ridge
            base = Vector((s * 3.75, 11.85, 0.05 + dz))
            horn(p, [tuple(base), tuple(base + Vector((s * 0.25, 0.6, 0))), tuple(base + Vector((s * 0.55, 1.3 - abs(dz) * 0.35, 0)))], 0.3, TB_L, segs=8)
        p.ball((0.5, 0.5, 0.5), (s * 4.6, 11.25, 0.05), TEAL, segs=10, rings=6)
        limb(p, (s * 3.6, 9.0, 0), (s * 3.62, 6.9, -0.05), 1.05, 0.95, TA_DARK, bulge=0.08)
        p.cyl(2.45, 1.6, (s * 3.62, 7.7, -0.03), TB_D, segs=18, d2=2.15, bevel=0.08)
        crack(p, [(s * 3.0, 8.2, -1.1), (s * 3.3, 7.8, -1.2), (s * 3.1, 7.3, -1.15)], TEAL, r=0.08)
        out.append(p)
        p = body_piece(K, side + "LowerArm")
        p.ball((1.8, 1.8, 1.8), (s * 3.6, 6.7, 0), TA_DARK, segs=14, rings=8)
        p.cyl(2.05, 0.22, (s * 3.6, 6.7, 0), TEAL, segs=16)
        p.cyl(2.5, 2.2, (s * 3.75, 5.4, -0.22), TB, rot=(-8, 0, s * 6), segs=18, d2=3.0, bevel=0.1)  # gauntlets
        crack(p, [(s * 3.2, 6.2, -1.45), (s * 3.55, 5.7, -1.55), (s * 3.3, 5.2, -1.6), (s * 3.6, 4.7, -1.6)], TEAL, r=0.08)
        for k in range(4):
            a = math.radians(-90 + k * 60)
            p.ball((0.26, 0.26, 0.26), (s * 3.75 + 1.4 * math.cos(a) * s, 5.0, -0.22 + 1.4 * math.sin(a)), TB_D, segs=8, rings=4)
        shackle(p, (s * 3.9, 4.45, -0.4), 2.95, (s * 0.12, 1, -0.15), (s, 0, 0))
        out.append(p)
        p = body_piece(K, side + "Hand")  # hammer fists
        p.box((2.2, 1.8, 2.2), (s * 3.95, 3.25, -0.6), TB, bevel=0.35)
        for d in (-0.6, 0.0, 0.6):
            p.box((0.6, 0.55, 0.75), (s * 3.95 + d, 3.05, -1.75), TB_L, bevel=0.15)
            p.box((0.55, 0.55, 0.6), (s * 3.95 + d, 2.45, -1.4), TB, bevel=0.15)
        p.box((0.75, 1.0, 0.8), (s * 3.95 - s * 1.15, 3.1, -1.25), TB_L, bevel=0.2)
        grow(p, (s * 3.9, 4.0, -0.4), 1.35)
        out.append(p)
        p = body_piece(K, side + "UpperLeg")
        limb(p, (s * 1.25, 5.3, 0), (s * 1.15, 2.8, 0), 1.25, 1.0, TB_D, bulge=0.1)
        p.cyl(2.7, 1.6, (s * 1.2, 4.1, -0.05), TB, segs=18, d2=2.35, bevel=0.08)
        crack(p, [(s * 0.6, 4.6, -1.2), (s * 0.95, 4.2, -1.3), (s * 0.7, 3.7, -1.25)], TEAL, r=0.08)
        out.append(p)
        p = body_piece(K, side + "LowerLeg")
        p.ball((1.7, 1.7, 1.7), (s * 1.1, 2.6, 0), TA_DARK, segs=14, rings=8)
        p.ball((1.45, 1.3, 0.9), (s * 1.1, 2.6, -0.8), TB_L, segs=12, rings=8)
        p.cyl(2.3, 1.85, (s * 1.18, 1.6, -0.02), TB_L, segs=18, d2=1.95, bevel=0.08)  # pillar greaves
        if s > 0:  # the ankle seal (MythRig AnkleSeal, the weak point): a great bronze nail, glowing
            p.cyl(1.45, 0.3, (1.1, 1.15, -1.1), TB_L, axis="z", segs=16, bevel=0.05)
            p.ball((0.95, 0.95, 0.5), (1.1, 1.15, -1.25), TEAL, segs=14, rings=8)
        shackle(p, (s * 1.2, 0.95, 0.12), 1.95, (0, 1, 0), (s, 0, 0))
        out.append(p)
        p = body_piece(K, side + "Foot")
        p.box((2.3, 1.05, 3.2), (s * 1.2, 0.52, -0.55), TB_D, bevel=0.3)
        p.box((2.35, 0.55, 1.3), (s * 1.2, 0.8, -1.6), TB, bevel=0.2)
        out.append(p)
    return out


# ---------------------------------------------------------------- chains and pylons --------
def chain_link():
    """One chain link, 3 studs long, 1.8 wide, its wire 0.55 thick, in the XY plane (long along Y)."""
    p = Piece("Chain_Link", exact=True, outline=OUT_WORLD)
    pts = []
    L, W = 1.2, 0.62  # half straight length, half width (centre of the wire)
    for i in range(8):
        a = math.pi * i / 7
        pts.append((W * math.cos(a), L * 0.5 + W * math.sin(a), 0))
    for i in range(8):
        a = math.pi + math.pi * i / 7
        pts.append((W * math.cos(a), -L * 0.5 + W * math.sin(a), 0))
    tube(p, pts, [0.27] * len(pts), IRON, segs=8, closed=True)
    return p


def chain_anchor():
    """The wall plate a chain hangs from: a riveted iron plate facing -Z with a big ring bolt."""
    p = Piece("Chain_Anchor", exact=True, outline=OUT_WORLD)
    p.box((3.2, 3.2, 0.6), (0, 0, 0), IRON, bevel=0.2)
    for x in (-1.15, 1.15):
        for y in (-1.15, 1.15):
            p.ball((0.45, 0.45, 0.3), (x, y, -0.32), IRON_L, segs=10, rings=5)
    p.cyl(1.2, 0.8, (0, 0, -0.6), IRON_L, axis="z", segs=14, bevel=0.1)
    p.ring(0.75, 0.24, (0, -0.55, -1.15), IRON_L, rot=(0, 90, 0), segs=16, sides=7)
    return p


def pylon(kind):
    """One of a pair either side of a lair's way out, 26 studs high, its origin on the ground."""
    p = Piece(f"{kind}_Pylon", exact=True, outline=OUT_WORLD)
    if kind == "Cyclops":  # stacked basalt with lava in the cracks and a fire on top
        y = 0.0
        for i, (w, hgt, tilt) in enumerate(((6.4, 4.5, 2), (5.8, 5.0, -3), (5.6, 4.6, 4), (5.0, 4.4, -2), (4.6, 3.8, 3))):
            p.box((w, hgt + 0.2, w * 0.92), (0.15 * (-1) ** i, y + hgt / 2, 0), ROCK if i % 2 == 0 else ROCK_D, rot=(0, i * 9, tilt), bevel=0.45)
            p.box((0.3, hgt * 0.7, 0.3), (w * 0.32 * (-1) ** i, y + hgt / 2, -w * 0.47), LAVA, rot=(0, 0, 14 * (-1) ** i), bevel=0)
            y += hgt
        p.cyl(5.2, 1.6, (0, y + 0.8, 0), IRON, segs=16, d2=6.2, bevel=0.15)
        p.cyl(5.4, 0.3, (0, y + 1.6, 0), IRON_L, segs=16)
        p.cyl(4.6, 3.6, (0, y + 3.2, 0), FIRE, segs=9, d2=0.4)
        p.cyl(2.8, 3.0, (0.3, y + 3.0, 0.2), FIRE_Y, segs=7, d2=0.2, rot=(0, 25, 0))
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            horn(p, [(2.6 * math.cos(a), y + 1.2, 2.6 * math.sin(a)), (3.4 * math.cos(a), y + 2.4, 3.4 * math.sin(a))], 0.35, IRON_L, segs=8)
    elif kind == "Minotaur":  # a fluted marble column carrying a gold labrys
        p.box((5.6, 1.4, 5.6), (0, 0.7, 0), STONE, bevel=0.25)
        p.cyl(4.6, 1.0, (0, 1.9, 0), MARBLE_S, segs=18, bevel=0.2)
        p.cyl(3.8, 16.0, (0, 10.4, 0), MARBLE, d2=3.4, segs=18)
        for i in range(14):
            a = 2 * math.pi * i / 14
            p.box((0.24, 15.4, 0.24), (1.8 * math.sin(a), 10.4, -1.8 * math.cos(a)), MARBLE_S, bevel=0)
        p.cyl(3.6, 0.8, (0, 18.8, 0), MARBLE_S, d2=4.8, segs=18)
        p.box((5.4, 1.0, 5.4), (0, 19.7, 0), MARBLE, bevel=0.2)
        p.box((0.6, 6.0, 0.6), (0, 23.2, 0), BRONZE_D, bevel=0.1)  # the labrys
        for b in (-1, 1):
            p.ball((3.2, 4.6, 0.55), (b * 1.7, 23.9, 0), GOLD, segs=18, rings=10)
            p.ball((1.6, 3.4, 0.62), (b * 0.75, 23.9, 0), "C88A1E", segs=14, rings=8)
        p.ball((0.9, 0.9, 0.9), (0, 26.4, 0), GOLD, segs=10, rings=6)
    else:  # a red Minoan column widening upward, black cushion capital, gold horns of consecration
        p.box((5.6, 1.2, 5.6), (0, 0.6, 0), STONE, bevel=0.25)
        p.cyl(4.6, 0.9, (0, 1.65, 0), CAP_BLACK, segs=18, bevel=0.2)
        p.cyl(3.0, 15.0, (0, 9.6, 0), MINOAN, d2=4.0, segs=18)
        p.cyl(4.2, 0.35, (0, 16.2, 0), GOLD, segs=18)
        p.ball((5.6, 2.4, 5.6), (0, 18.2, 0), CAP_BLACK, segs=20, rings=10)
        p.box((5.8, 1.2, 5.8), (0, 19.8, 0), CAP_BLACK, bevel=0.2)
        p.box((1.2, 1.4, 0.7), (0, 12.0, -1.85), TEAL, bevel=0.12)
        p.box((1.6, 0.35, 1.0), (0, 12.85, -1.85), BRONZE_D, bevel=0.06)
        p.box((4.6, 1.6, 1.8), (0, 21.2, 0), GOLD, bevel=0.2)
        for s in (-1, 1):
            horn(p, curve((s * 1.4, 21.6, 0), (s * 2.0, 26.0, 0), (s * 2.8, 23.5, 0), 5), 0.75, GOLD, segs=12)
    return p


# ---------------------------------------------------------------- build --------------------
def done(p, col):
    ob = p.finish()
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col.objects.link(ob)
    return ob


def scene_and_collection():
    if bpy.app.background:
        scene = bpy.context.scene
    else:
        scene = bpy.data.scenes.get("MythBosses") or bpy.data.scenes.new("MythBosses")
        win = bpy.context.window or bpy.context.window_manager.windows[0]
        win.scene = scene
    col = bpy.data.collections.get("MythBosses")
    if not col:
        col = bpy.data.collections.new("MythBosses")
    if col.name not in scene.collection.children:
        scene.collection.children.link(col)
    for ob in list(col.objects):
        bpy.data.objects.remove(ob)
    return scene, col


def main(only=None):
    had_army = bpy.data.collections.get("ArmyKit") is not None
    scene, col = scene_and_collection()
    groups = {"Cyclops": cyclops, "Minotaur": minotaur, "Talos": talos}
    tris = {}
    x = 0.0
    for kind in KINDS:
        if only and kind not in only:
            continue
        for p in groups[kind]():
            ob = done(p, col)
            ob.location = (-x, 0, 0)  # Roblox +x is Blender -x: side by side, 12 studs apart
            ob["kind"] = kind
            tris[ob.name] = sum(len(f.vertices) - 2 for f in ob.data.polygons)
        x += 12.0
    if not only:
        extra = [chain_link(), chain_anchor()] + [pylon(k) for k in KINDS]
        for i, p in enumerate(extra):
            ob = done(p, col)
            ob.location = (-(x + 8.0 * i), 0, 0)
            tris[ob.name] = sum(len(f.vertices) - 2 for f in ob.data.polygons)
    army = bpy.data.collections.get("ArmyKit")
    if army and not had_army and not army.objects:
        bpy.data.collections.remove(army)
    black = bpy.data.materials.get("000000")
    if black:
        black.use_backface_culling = True  # the inverted hull reads as an outline in the viewport too
    for name, n in sorted(tris.items()):
        print(f"PIECE {name}: {n} tris")
    print("total", sum(tris.values()), "tris in", len(tris), "pieces")
    if bpy.app.background:
        out = os.path.join(HERE, "bosses.blend")
        bpy.ops.wm.save_as_mainfile(filepath=out)
        print("saved", out)
    return scene


if __name__ == "__main__" or bpy.app.background:
    main(globals().get("ONLY"))
