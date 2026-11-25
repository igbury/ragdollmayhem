# Mayhem Park 2.0: the arena's props and the three boss lairs' set pieces, modelled in code in the
# kit's comic style (assets/army/build.py: chunky bevelled shapes, flat saturated colours, a black
# inverted-hull outline). Run headless:
#   blender -b --factory-startup -P assets/arena/build.py
# It builds every Arena_* piece in a fresh file and saves assets/arena/arena.blend; then
# assets/arena/export.py writes ArenaKit.glb + manifest.json and assets/arena/voxels.py the cubes
# each piece breaks into (src/server/ArenaVoxels.luau).
#
# Roblox space, studs (x right, y up, front -Z); every piece stands on the ground at its origin.
# PAINT (FE01FE) is a stand-in: Map.luau paints that mesh (and its cubes) per placed piece, so one
# house model makes a street of different houses and one oak a park of greens.
import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

# the Piece toolkit, palette helpers and text_z from the army kit (everything before its first piece,
# plus the map vehicles' constants and helpers)
_src = open(os.path.join(REPO, "assets", "army", "build.py"), encoding="utf-8").read()
_head = _src.split("# ---------------------------------------------------------------- Soldier")[0]
_veh = re.search(r"PAINT = \"FE01FE\".*?(?=\ndef park_car)", _src, re.S).group(0)
exec(compile(_head + "\n" + _veh, "army_build_toolkit", "exec"))

# ---------------------------------------------------------------- palette --------------------
INK = "121214"
STONE_L, STONE, STONE_D, STONE_DD = "DCD5C6", "B9B1A2", "8F887D", "6A645C"
MARBLE, MARBLE_S = "F1EDE4", "D2CBBE"
GOLD, GOLD_D = "F2B53A", "C88A1E"
IRON, IRON_L = "2C2E36", "4E5260"
WOOD, WOOD_D, WOOD_L = "8A5A36", "5E3C24", "B98250"
TRUNK = "6E4A2E"
ROOF_R, ROOF_RD = "C8523C", "9C3A2C"
BRICK, BRICK_D = "B25C46", "8A4234"
TRIM = "F6F0E2"
WINDOW = "2C3C5C"
GLASS = "8FD0F0"  # see-through (export.py)
SHUTTER = "3C7A5C"
LEAF_L, PINE, PINE_L = "7ACC5A", "2C6E46", "3E8A56"
WATER, WATER_FALL = "4FB4EC", "BCE6FF"  # see-through
WARM = "FFE29A"  # lamp glass: neon
FIRE, FIRE_Y, LAVA = "FF7A1E", "FFD040", "FF4E1A"  # neon
BRONZE, BRONZE_D, BRONZE_L = "C8843A", "8E5A26", "EAB66A"
PATINA = "4FA88E"
TALOS_GLOW = "39D0E6"  # neon (Monsters THEME.Talos glow)
MINOAN, CAP_BLACK = "B8322A", "26262C"
ORANGE, YELLOW, CONCRETE = "F08A24", "F7C52E", "A9A9B0"
STRIPE, PINK, MINT, WAFER = "F6F2E8", "F49AC0", "8EE0C0", "DFA35A"
BONE, HORN, HORN_D = "ECE3CC", "E8DDC0", "6E6252"
ROCK, ROCK_D = "5C5864", "3C3942"
FLOWERS = ("E8506E", "F6C84A", "9A5ADC", "F4F4F4")
RED = "D63A32"
BLUE = "3A7AD8"

NEON = {WARM, FIRE, FIRE_Y, LAVA, TALOS_GLOW}
SEE_THROUGH = {GLASS: 0.45, WATER: 0.3, WATER_FALL: 0.45}
BIG = 0.07  # outline for map-sized pieces: the army kit's 0.024 vanishes at 60 studs


def rot_to(d):
    """Euler degrees (Roblox XYZ) turning +Y onto direction d."""
    q = Vector((0, 1, 0)).rotation_difference(Vector(d).normalized())
    return tuple(math.degrees(a) for a in q.to_euler("XYZ"))


def beam(p, a, b, w, h, bevel=0.04, depth=None):
    """A box of section w x (depth or w) from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    p.box((w, d.length, depth or w), tuple((a + b) / 2), h, rot=rot_to(d), bevel=bevel)


def rod(p, a, b, dia, h, segs=10):
    a, b = Vector(a), Vector(b)
    d = b - a
    p.cyl(dia, d.length, tuple((a + b) / 2), h, rot=rot_to(d), segs=segs)


def ngon(r, n, phase=0.0):
    return [(r * math.cos(phase + 2 * math.pi * i / n), r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def window(p, x, y, z, w, hgt, face, frame=TRIM, glass=WINDOW, shutters=None, box=None):
    """A framed window on a wall facing `face` (-1: -Z, +1: +Z, 'x-'/'x+': the sides); (x, y, z) is the
    wall's surface point at the window's centre."""
    if face in (-1, 1):
        p.box((w + 0.5, hgt + 0.5, 0.24), (x, y, z + face * 0.08), frame, bevel=0.06)
        p.box((w, hgt, 0.3), (x, y, z + face * 0.12), glass, bevel=0.02)
        p.box((0.14, hgt, 0.36), (x, y, z + face * 0.15), frame, bevel=0)
        p.box((w, 0.14, 0.36), (x, y + hgt * 0.12, z + face * 0.15), frame, bevel=0)
        p.box((w + 0.9, 0.24, 0.6), (x, y - hgt / 2 - 0.3, z + face * 0.24), frame, bevel=0.05)  # sill
        if shutters:
            for s in (-1, 1):
                p.box((w * 0.5, hgt + 0.2, 0.16), (x + s * (w * 0.75 + 0.35), y, z + face * 0.1), shutters, bevel=0.04)
        if box:
            p.box((w + 0.6, 0.6, 0.7), (x, y - hgt / 2 - 0.75, z + face * 0.45), WOOD_D, bevel=0.06)
            for i, fx in enumerate((-0.9, -0.3, 0.3, 0.9)):
                p.ball((0.6, 0.6, 0.6), (x + fx * w * 0.42, y - hgt / 2 - 0.3, z + face * 0.45), FLOWERS[(i + box) % 4], segs=8, rings=6)
    else:
        s = -1 if face == "x-" else 1
        p.box((0.24, hgt + 0.5, w + 0.5), (x + s * 0.08, y, z), frame, bevel=0.06)
        p.box((0.3, hgt, w), (x + s * 0.12, y, z), glass, bevel=0.02)
        p.box((0.36, hgt, 0.14), (x + s * 0.15, y, z), frame, bevel=0)
        p.box((0.36, 0.14, w), (x + s * 0.15, y + hgt * 0.12, z), frame, bevel=0)
        p.box((0.6, 0.24, w + 0.9), (x + s * 0.24, y - hgt / 2 - 0.3, z), frame, bevel=0.05)
        if shutters:
            for t in (-1, 1):
                p.box((0.16, hgt + 0.2, w * 0.5), (x + s * 0.1, y, z + t * (w * 0.75 + 0.35)), shutters, bevel=0.04)


def done(p):
    ob = p.finish()
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col = bpy.data.collections.get("ArenaKit") or bpy.data.collections.new("ArenaKit")
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    col.objects.link(ob)
    return ob


# ---------------------------------------------------------------- the plaza ------------------
def statue():
    """The plaza's hero: a marble ragdoll dummy on a stepped plinth, one fist punched at the sky, the
    other on its hip, a red cape flying behind and a gold laurel; a gold MAYHEM plaque in front."""
    p = Piece("Arena_Statue", exact=True, outline=BIG)
    p.box((13, 1.2, 13), (0, 0.6, 0), STONE_D, bevel=0.25)
    p.box((10.6, 1.0, 10.6), (0, 1.7, 0), STONE, bevel=0.2)
    p.box((8.0, 5.0, 8.0), (0, 4.7, 0), MARBLE_S, bevel=0.3)
    p.box((8.1, 0.45, 8.1), (0, 6.55, 0), GOLD, bevel=0.08)
    p.box((9.0, 0.8, 9.0), (0, 7.6, 0), STONE_L, bevel=0.2)
    p.box((5.2, 1.8, 0.24), (0, 4.4, -4.08), GOLD, bevel=0.08)
    text_z(p, "MAYHEM", 4.4, 0.12, (0, 4.4, -4.26), INK, -1)
    for s in (-1, 1):  # corner urns on the lower step
        p.cyl(1.0, 0.9, (s * 4.6, 2.65, -4.6), STONE_L, d2=1.5, segs=12)
        p.ball((1.1, 0.9, 1.1), (s * 4.6, 3.3, -4.6), LEAF_L, segs=10, rings=6)
    y0 = 8.0
    for s in (-1, 1):  # legs in a wide stance
        p.box((1.6, 0.9, 2.4), (s * 1.9, y0 + 0.45, -0.3), MARBLE_S, bevel=0.25)  # feet
        p.box((1.35, 2.8, 1.35), (s * 1.75, y0 + 2.2, 0), MARBLE, rot=(0, 0, s * 6), bevel=0.3)
        p.ball((1.6, 1.4, 1.6), (s * 1.6, y0 + 3.7, 0), MARBLE_S, segs=12, rings=8)  # knee
        p.box((1.5, 2.8, 1.5), (s * 1.4, y0 + 5.0, 0), MARBLE, rot=(0, 0, s * 8), bevel=0.35)
    p.box((3.8, 1.5, 2.3), (0, y0 + 6.8, 0), MARBLE_S, bevel=0.45)  # hips
    p.box((4.4, 4.6, 2.5), (0, y0 + 9.6, 0), MARBLE, bevel=0.6)  # chest
    p.box((4.5, 0.5, 2.6), (0, y0 + 7.75, 0), GOLD, bevel=0.15)  # belt
    p.box((1.2, 0.8, 0.3), (0, y0 + 7.75, -1.32), GOLD_D, bevel=0.1)  # buckle
    p.cyl(1.2, 0.8, (0, y0 + 12.1, 0), MARBLE_S, segs=12)  # neck
    p.ball((2.9, 3.0, 2.8), (0, y0 + 13.8, 0), MARBLE, segs=20, rings=12)  # head
    p.ring(1.42, 0.2, (0, y0 + 14.6, 0), GOLD, rot=(90, 0, 0), segs=24, sides=6)  # laurel
    for i in range(10):
        a = i / 10 * 2 * math.pi
        p.ball((0.7, 0.3, 0.45), (1.5 * math.cos(a), y0 + 14.75, 1.5 * math.sin(a)), GOLD, rot=(0, -math.degrees(a), 25), segs=6, rings=4)
    for s in (-1, 1):  # the dummy's crash-test target marks on the temples
        p.cyl(0.6, 0.06, (s * 1.43, y0 + 13.9, 0), GOLD, axis="x", segs=12)
    p.ball((1.9, 1.7, 1.9), (2.6, y0 + 11.3, 0), MARBLE_S, segs=12, rings=8)  # shoulders
    p.ball((1.9, 1.7, 1.9), (-2.6, y0 + 11.3, 0), MARBLE_S, segs=12, rings=8)
    beam(p, (2.8, y0 + 11.4, 0), (3.6, y0 + 14.2, 0), 1.25, MARBLE, bevel=0.3)  # the arm up: upper
    beam(p, (3.6, y0 + 14.2, 0), (4.1, y0 + 16.9, 0), 1.15, MARBLE, bevel=0.3)  # forearm
    p.ball((1.7, 1.8, 1.7), (4.2, y0 + 17.6, 0), MARBLE_S, segs=14, rings=10)  # fist
    p.ring(0.62, 0.18, (4.1, y0 + 16.95, 0), GOLD, rot=(90, 0, 0), segs=16, sides=6)  # wristband
    beam(p, (-2.8, y0 + 11.2, 0), (-4.0, y0 + 9.2, 0), 1.25, MARBLE, bevel=0.3)  # the arm on the hip
    beam(p, (-4.0, y0 + 9.2, 0), (-2.5, y0 + 7.9, 0), 1.15, MARBLE, bevel=0.3)
    p.ball((1.4, 1.4, 1.5), (-2.3, y0 + 7.9, 0), MARBLE_S, segs=12, rings=8)
    # the cape, blown back off the shoulders in three folds
    for i, (dx, tip) in enumerate(((-1.5, 5.0), (0.0, 5.8), (1.5, 4.6))):
        p.prism([(1.15, y0 + 12.2), (1.6, y0 + 12.4), (2.6 + tip * 0.35, y0 + 7.2), (2.2 + tip * 0.4, y0 + 5.0 + i * 0.4), (1.6 + tip * 0.3, y0 + 5.4 + i * 0.3)],
                1.5, (dx, 0, 0), RED if i != 1 else ROOF_RD, bevel=0.12)
    return done(p)


def lamp():
    """A cast-iron park lamp, 11 high: fluted post, a crossbar with two lanterns and a finial."""
    p = Piece("Arena_Lamp", exact=True, outline=0.04)
    p.cyl(1.5, 0.5, (0, 0.25, 0), IRON, segs=12, bevel=0.08)
    p.cyl(1.1, 1.0, (0, 1.0, 0), IRON_L, d2=0.6, segs=12)
    p.cyl(0.42, 8.2, (0, 5.5, 0), IRON, segs=10)
    for y in (1.6, 5.0, 9.2):
        p.cyl(0.7, 0.25, (0, y, 0), IRON_L, segs=12, bevel=0.05)
    p.box((3.8, 0.22, 0.22), (0, 9.6, 0), IRON, bevel=0.04)
    for s in (-1, 1):
        rod(p, (s * 0.2, 8.6, 0), (s * 1.5, 9.5, 0), 0.14, IRON, segs=6)  # scroll brace
        p.cyl(0.18, 0.4, (s * 1.7, 9.4, 0), IRON, segs=8)
        p.box((0.85, 1.05, 0.85), (s * 1.7, 8.65, 0), WARM, bevel=0.05)
        for dx in (-0.45, 0.45):
            for dz in (-0.45, 0.45):
                p.box((0.1, 1.1, 0.1), (s * 1.7 + dx, 8.65, dz), IRON, bevel=0)
        p.cyl(1.2, 0.55, (s * 1.7, 9.48, 0), IRON_L, d2=0.2, segs=4, rot=(0, 45, 0))
        p.box((1.0, 0.14, 1.0), (s * 1.7, 8.05, 0), IRON, bevel=0.03)
    p.ball((0.45, 0.6, 0.45), (0, 10.1, 0), GOLD, segs=8, rings=6)
    return done(p)


def bench():
    """A park bench, 6 long: wooden slats on two cast-iron frames, the back leaning out."""
    p = Piece("Arena_Bench", exact=True, outline=0.04)
    frame = [(-0.85, 0.0), (-0.55, 0.0), (-0.42, 1.3), (0.5, 1.3), (0.62, 0.0), (0.92, 0.0), (0.82, 1.42),
             (1.12, 3.2), (0.88, 3.25), (0.6, 1.58), (-0.78, 1.58)]
    for x in (-2.6, 2.6):
        p.prism(frame, 0.22, (x, 0, 0), IRON, bevel=0.04)
        p.box((0.3, 0.16, 1.5), (x, 2.05, -0.1), IRON_L, bevel=0.05)  # armrest
    for i, z in enumerate((-0.62, -0.22, 0.18, 0.58)):
        p.box((6.0, 0.16, 0.34), (0, 1.66, z), WOOD_L if i % 2 else WOOD, bevel=0.05)
    for i, y in enumerate((2.15, 2.55, 2.95)):
        p.box((6.0, 0.3, 0.14), (0, y, 0.82 + (y - 1.7) * 0.15), WOOD_L if i % 2 == 0 else WOOD, rot=(-12, 0, 0), bevel=0.05)
    return done(p)


def fountain():
    """The park's fountain: an octagonal basin with a marble rim, two tiered bowls on a stem, water
    standing in each and spilling over in streams, a gold finial."""
    p = Piece("Arena_Fountain", exact=True, outline=BIG)
    n, R = 8, 7.6
    side = 2 * R * math.tan(math.pi / n)
    for i in range(n):
        a = 2 * math.pi * i / n
        p.box((side + 0.02, 1.6, 1.0), (R * math.sin(a), 0.8, -R * math.cos(a)), STONE_L, rot=(0, -math.degrees(a), 0), bevel=0.1)
        p.box((side + 0.5, 0.3, 1.4), ((R + 0.05) * math.sin(a), 1.75, -(R + 0.05) * math.cos(a)), MARBLE, rot=(0, -math.degrees(a), 0), bevel=0.08)
    p.slab(ngon(R - 0.3, n, math.pi / 8), 0.0, 0.5, (0, 0, 0), STONE_D, bevel=0)
    p.slab(ngon(R - 0.45, n, math.pi / 8), 0.5, 1.25, (0, 0, 0), WATER, bevel=0)
    p.cyl(2.6, 0.6, (0, 1.5, 0), MARBLE_S, segs=16)
    p.cyl(2.0, 2.8, (0, 3.2, 0), MARBLE, d2=1.4, segs=16)
    p.cyl(1.8, 1.2, (0, 5.0, 0), MARBLE_S, d2=6.2, segs=20)  # lower bowl
    p.cyl(5.8, 0.24, (0, 5.62, 0), WATER, segs=20)
    p.ring(3.05, 0.18, (0, 5.62, 0), GOLD, rot=(90, 0, 0), segs=28, sides=6)
    p.cyl(1.1, 2.0, (0, 6.7, 0), MARBLE, segs=14)
    p.cyl(1.0, 0.9, (0, 8.1, 0), MARBLE_S, d2=3.6, segs=16)  # upper bowl
    p.cyl(3.2, 0.2, (0, 8.55, 0), WATER, segs=16)
    p.cyl(0.5, 0.9, (0, 9.05, 0), MARBLE, segs=10)
    p.ball((0.9, 0.9, 0.9), (0, 9.8, 0), GOLD, segs=12, rings=8)
    p.cyl(0.24, 0.9, (0, 10.6, 0), WATER_FALL, segs=8)
    for i in range(8):  # streams over the bowls' lips
        a = 2 * math.pi * (i + 0.5) / 8
        p.box((0.32, 3.4, 0.12), (3.05 * math.sin(a), 3.6, -3.05 * math.cos(a)), WATER_FALL, rot=(0, -math.degrees(a), 0), bevel=0)
        p.box((0.24, 2.3, 0.1), (1.75 * math.sin(a), 6.95, -1.75 * math.cos(a)), WATER_FALL, rot=(0, -math.degrees(a), 0), bevel=0)
    return done(p)


def ad_column():
    """A round advertising column, 4 across and 10 high, papered in posters, with a domed cap: cover
    at the plaza's corners."""
    p = Piece("Arena_AdColumn", exact=True, outline=BIG)
    p.cyl(4.6, 0.8, (0, 0.4, 0), STONE_D, segs=20, bevel=0.15)
    p.cyl(4.0, 8.0, (0, 4.8, 0), "2E5C48", segs=20)
    posters = (("E8506E", "F6C84A"), (BLUE, STRIPE), (YELLOW, RED), ("9A5ADC", MINT), (ORANGE, IRON), (MINT, PINK))
    for i, (a_col, b_col) in enumerate(posters):
        a = 2 * math.pi * i / 6
        x, z = 2.02 * math.sin(a), -2.02 * math.cos(a)
        p.box((1.75, 3.0, 0.12), (x, 3.6 + (i % 2) * 2.6, z), a_col, rot=(0, -math.degrees(a), 0), bevel=0.02)
        p.box((1.2, 0.5, 0.14), (x * 1.01, 4.3 + (i % 2) * 2.6, z * 1.01), b_col, rot=(0, -math.degrees(a), 0), bevel=0)
        p.box((1.2, 0.3, 0.14), (x * 1.01, 3.0 + (i % 2) * 2.6, z * 1.01), b_col, rot=(0, -math.degrees(a), 0), bevel=0)
    p.cyl(4.5, 0.5, (0, 9.05, 0), "234A3A", segs=20, bevel=0.1)
    p.ball((4.2, 2.4, 4.2), (0, 9.3, 0), "2E5C48", cut=0.5, segs=20, rings=10)
    p.ball((0.7, 0.9, 0.7), (0, 10.7, 0), GOLD, segs=10, rings=6)
    return done(p)


def gate():
    """The park gate on each path out: brick pillars at x +-8 with stone caps and lanterns, an iron
    arch between them and a hanging MAYHEM PARK sign, readable from both sides."""
    p = Piece("Arena_Gate", exact=True, outline=BIG)
    for s in (-1, 1):
        x = s * 8
        p.box((4.0, 1.0, 4.0), (x, 0.5, 0), STONE_D, bevel=0.2)
        p.box((3.2, 12.0, 3.2), (x, 7.0, 0), BRICK, bevel=0.15)
        for y in range(2, 13, 2):  # brick courses
            p.box((3.26, 0.12, 3.26), (x, y, 0), BRICK_D, bevel=0)
        p.box((3.9, 0.7, 3.9), (x, 13.35, 0), STONE_L, bevel=0.15)
        p.box((3.3, 0.5, 3.3), (x, 13.95, 0), STONE, bevel=0.1)
        p.cyl(0.6, 0.6, (x, 14.5, 0), IRON, segs=8)
        p.box((1.1, 1.3, 1.1), (x, 15.4, 0), WARM, bevel=0.06)
        p.cyl(1.6, 0.7, (x, 16.4, 0), IRON_L, d2=0.2, segs=4, rot=(0, 45, 0))
    # the arch: iron bars on a half circle over the opening, a lower bar straight across
    pts = [(6.4 * math.cos(math.pi * i / 14), 13.0 + 3.2 * math.sin(math.pi * i / 14)) for i in range(15)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        beam(p, (x0, y0, 0), (x1, y1, 0), 0.4, IRON, bevel=0.05)
    beam(p, (-6.4, 12.0, 0), (6.4, 12.0, 0), 0.34, IRON, bevel=0.04)
    for x in (-4.5, -1.5, 1.5, 4.5):  # the spindles between
        beam(p, (x, 12.0, 0), (x, 13.0 + 3.2 * math.sqrt(max(0.0, 1 - (x / 6.4) ** 2)), 0), 0.18, IRON_L, bevel=0)
    p.ball((0.8, 0.8, 0.8), (0, 16.6, 0), GOLD, segs=10, rings=6)
    for x in (-3.6, 3.6):
        beam(p, (x, 12.0, 0), (x, 11.0, 0), 0.08, IRON, bevel=0)
    p.box((9.4, 2.0, 0.36), (0, 10.0, 0), STRIPE, bevel=0.12)
    p.box((9.8, 0.24, 0.42), (0, 11.05, 0), RED, bevel=0.04)
    p.box((9.8, 0.24, 0.42), (0, 8.95, 0), RED, bevel=0.04)
    for side in (-1, 1):
        text_z(p, "MAYHEM PARK", 8.4, 0.1, (0, 10.0, side * 0.23), RED, side)
    return done(p)


# ---------------------------------------------------------------- town -----------------------
def house():
    """A two-storey townhouse, 16 wide (x) and 14 deep, its door on the front (-Z): PAINT walls on a
    stone plinth with corner quoins, a gable roof of red tiles with a chimney, shutters, flower boxes
    and a striped awning over the door."""
    p = Piece("Arena_House", exact=True, outline=BIG)
    W, D = 16.0, 14.0
    p.box((W + 0.6, 1.0, D + 0.6), (0, 0.5, 0), STONE_D, bevel=0.15)
    p.box((W, 13.0, D), (0, 7.5, 0), PAINT, bevel=0.1)
    p.box((W + 0.3, 0.5, D + 0.3), (0, 7.4, 0), TRIM, bevel=0.06)
    p.box((W + 0.4, 0.6, D + 0.4), (0, 13.7, 0), TRIM, bevel=0.08)
    for sx in (-1, 1):
        for sz in (-1, 1):
            for k in range(6):
                y = 1.6 + k * 2.0
                long = k % 2 == 0
                p.box((1.3 if long else 0.9, 0.9, 0.9 if long else 1.3), (sx * (W / 2 - 0.4), y, sz * (D / 2 - 0.4)), STONE_L, bevel=0.08)
    # the roof: tiles in rows down each slope, a ridge, the gables filled in wall colour
    p.prism([(-D / 2 - 0.9, 13.9), (D / 2 + 0.9, 13.9), (0, 19.6)], W + 1.0, (0, 0, 0), ROOF_R, bevel=0.1)
    slope = math.degrees(math.atan2(5.7, D / 2 + 0.9))
    for s in (-1, 1):
        for k in range(1, 5):
            t = k / 5
            z = s * (D / 2 + 0.9) * (1 - t)
            y = 13.9 + 5.7 * t
            p.box((W + 1.05, 0.12, 0.1), (0, y + 0.05, z + s * 0.04), ROOF_RD, rot=(s * slope, 0, 0), bevel=0)
    p.box((W + 1.3, 0.6, 0.8), (0, 19.65, 0), ROOF_RD, bevel=0.12)
    p.box((1.9, 5.0, 1.9), (4.5, 18.6, 2.8), BRICK, bevel=0.1)
    p.box((2.3, 0.5, 2.3), (4.5, 21.2, 2.8), STONE_L, bevel=0.08)
    p.cyl(0.8, 0.6, (4.5, 21.7, 2.8), IRON_L, segs=8)
    # front: door with frame, step and knob; awning; windows
    z = -D / 2
    p.box((3.4, 5.4, 0.3), (0, 3.7, z - 0.08), TRIM, bevel=0.08)
    p.box((2.6, 4.6, 0.36), (0, 3.3, z - 0.12), WOOD_D, bevel=0.05)
    p.box((2.0, 1.6, 0.42), (0, 4.3, z - 0.15), WOOD, bevel=0.04)
    p.ball((0.3, 0.3, 0.3), (0.9, 3.1, z - 0.36), GOLD, segs=8, rings=6)
    p.box((4.0, 0.5, 1.6), (0, 0.75, z - 0.8), STONE_L, bevel=0.08)
    for i in range(6):  # awning stripes
        x = -2.5 + i
        p.box((1.0, 0.12, 2.2), (x + 0.5, 6.7, z - 1.0), RED if i % 2 == 0 else STRIPE, rot=(20, 0, 0), bevel=0)
    p.box((6.1, 0.4, 0.3), (0, 6.25, z - 2.05), RED, bevel=0.06)
    for x in (-5.0, 5.0):
        window(p, x, 4.0, z, 2.4, 2.8, -1, shutters=SHUTTER)
    for i, x in enumerate((-5.2, 0.0, 5.2)):
        window(p, x, 10.4, z, 2.2, 2.8, -1, shutters=SHUTTER, box=i + 1)
    for face, x in (("x-", -W / 2), ("x+", W / 2)):
        for zz in (-3.0, 3.0):
            window(p, x, 4.0, zz, 2.2, 2.6, face)
            window(p, x, 10.4, zz, 2.2, 2.6, face)
    for x in (-4.5, 0.0, 4.5):
        window(p, x, 4.0, D / 2, 2.2, 2.6, 1)
        window(p, x, 10.4, D / 2, 2.2, 2.6, 1)
    return done(p)


def shop():
    """A corner shop, 16 x 14 x 15: a big shop window under a striped awning and a CAFE sign, flats
    above with a little balcony, a flat roof with a parapet, a water tank and a vent."""
    p = Piece("Arena_Shop", exact=True, outline=BIG)
    W, D = 16.0, 14.0
    p.box((W + 0.6, 1.0, D + 0.6), (0, 0.5, 0), STONE_D, bevel=0.15)
    p.box((W, 13.5, D), (0, 7.75, 0), PAINT, bevel=0.1)
    p.box((W + 0.2, 6.0, D + 0.2), (0, 4.0, 0), BRICK, bevel=0.08)  # brick ground floor
    for y in (2.0, 3.5, 5.0, 6.5):
        p.box((W + 0.26, 0.1, D + 0.26), (0, y, 0), BRICK_D, bevel=0)
    p.box((W + 0.4, 0.5, D + 0.4), (0, 7.2, 0), TRIM, bevel=0.06)
    # parapet round the flat roof
    for s in (-1, 1):
        p.box((W + 0.6, 1.4, 0.6), (0, 15.2, s * (D / 2)), TRIM, bevel=0.08)
        p.box((0.6, 1.4, D + 0.6), (s * (W / 2), 15.2, 0), TRIM, bevel=0.08)
    z = -D / 2
    p.box((10.6, 4.6, 0.3), (-2.0, 3.6, z - 0.1), TRIM, bevel=0.06)  # shop window
    p.box((10.0, 4.0, 0.36), (-2.0, 3.6, z - 0.14), GLASS, bevel=0.03)
    for x in (-5.4, -2.0, 1.4):
        p.box((0.2, 4.0, 0.42), (x, 3.6, z - 0.16), TRIM, bevel=0)
    for i, x in enumerate((-6.0, -4.0, 0.0, 2.0)):  # goods in the window
        p.box((1.2, 1.0 + (i % 2) * 0.6, 0.8), (x + 0.2, 2.2 + (i % 2) * 0.3, z + 0.6), (PINK, YELLOW, MINT, ORANGE)[i], bevel=0.1)
    p.box((2.8, 5.0, 0.3), (5.6, 3.5, z - 0.08), TRIM, bevel=0.06)  # the door
    p.box((2.2, 4.4, 0.36), (5.6, 3.2, z - 0.12), BLUE, bevel=0.05)
    p.box((1.4, 2.0, 0.42), (5.6, 3.9, z - 0.15), GLASS, bevel=0.02)
    for i in range(16):  # awning, stripes running out from the wall
        x = -7.5 + i
        p.box((1.0, 0.12, 2.6), (x + 0.5, 6.9, z - 1.15), RED if i % 2 == 0 else STRIPE, rot=(22, 0, 0), bevel=0)
    for i in range(16):
        x = -7.5 + i
        p.box((1.0, 0.7, 0.12), (x + 0.5, 6.1, z - 2.35), RED if i % 2 == 0 else STRIPE, bevel=0)  # valance
    p.box((8.0, 1.8, 0.4), (-2.0, 8.6, z - 0.2), IRON, bevel=0.1)  # sign board
    text_z(p, "CAFE", 5.2, 0.12, (-2.0, 8.6, z - 0.42), YELLOW, -1)
    for x in (-5.0, 0.5, 5.0):
        window(p, x, 11.2, z, 2.2, 2.8, -1, shutters=SHUTTER if x != 0.5 else None)
    p.box((4.6, 0.3, 1.6), (0.5, 9.4, z - 0.8), STONE_L, bevel=0.06)  # balcony
    for x in (-1.6, -0.8, 0.0, 0.8, 1.6, 2.4):
        p.box((0.12, 1.2, 0.12), (x + 0.1, 10.15, z - 1.5), IRON, bevel=0)
    p.box((4.6, 0.16, 0.16), (0.5, 10.8, z - 1.5), IRON, bevel=0.02)
    for face, x in (("x-", -W / 2), ("x+", W / 2)):
        for zz in (-3.2, 3.2):
            window(p, x, 4.0, zz, 2.0, 2.4, face, frame=STONE_L)
            window(p, x, 11.2, zz, 2.2, 2.6, face)
    for x in (-4.5, 0.0, 4.5):
        window(p, x, 11.2, D / 2, 2.2, 2.6, 1)
    p.box((W - 0.4, 0.2, D - 0.4), (0, 14.55, 0), "4A4A52", bevel=0)  # tar roof
    # roof kit
    for dx in (-1.2, 1.2):
        for dz in (-1.2, 1.2):
            p.box((0.3, 3.0, 0.3), (-4.0 + dx, 16.0, 2.5 + dz), IRON, bevel=0.03)
    p.cyl(3.4, 3.0, (-4.0, 18.9, 2.5), WOOD, segs=14)
    p.cyl(3.6, 1.2, (-4.0, 21.0, 2.5), WOOD_D, d2=0.4, segs=14)
    for y in (17.9, 19.9):
        p.cyl(3.5, 0.2, (-4.0, y, 2.5), IRON, segs=14)
    p.box((3.0, 1.8, 2.0), (4.0, 15.4, 3.0), CONCRETE, bevel=0.12)
    p.cyl(1.4, 0.3, (4.0, 16.45, 3.0), IRON_L, segs=10)
    return done(p)


def kiosk():
    """An ice-cream kiosk, 6 x 9 x 5: a pink booth with a serving hatch, a striped roof and a giant
    cone with three scoops on top; ICE CREAM over the hatch."""
    p = Piece("Arena_Kiosk", exact=True, outline=0.05)
    p.box((6.0, 0.5, 4.4), (0, 0.25, 0), STONE_D, bevel=0.1)
    p.box((5.6, 4.0, 4.0), (0, 2.5, 0), PINK, bevel=0.2)
    p.box((4.2, 1.8, 0.3), (0, 3.2, -2.05), IRON, bevel=0.05)  # hatch
    p.box((4.8, 0.3, 0.9), (0, 2.25, -2.35), STRIPE, bevel=0.06)  # counter
    for i, x in enumerate((-1.4, 0.0, 1.4)):
        p.ball((0.7, 0.7, 0.7), (x, 2.75, -2.35), (MINT, YELLOW, "7A4A2E")[i], segs=10, rings=6)
    for i in range(7):  # the roof: stripes along x, tilted back
        x = -2.85 + i * 0.95
        p.box((0.95, 0.2, 5.2), (x, 4.95, -0.2), MINT if i % 2 == 0 else STRIPE, rot=(-8, 0, 0), bevel=0.02)
    p.box((5.8, 0.9, 0.3), (0, 5.2, -2.75), STRIPE, bevel=0.08)
    text_z(p, "ICE CREAM", 5.0, 0.08, (0, 5.2, -2.92), RED, -1)
    p.cyl(0.4, 3.0, (0, 6.9, 0), WAFER, d2=2.6, segs=12)  # the cone, point down
    for i in range(4):
        p.box((0.08, 3.0, 0.08), (0.75 * math.sin(i * math.pi / 2 + 0.4), 6.9, -0.75 * math.cos(i * math.pi / 2 + 0.4)), "B07830", rot=(0, 0, 0), bevel=0)
    p.ball((2.5, 2.1, 2.5), (0, 8.8, 0), PINK, segs=14, rings=10)
    p.ball((2.2, 1.9, 2.2), (0, 10.3, 0), MINT, segs=14, rings=10)
    p.ball((1.8, 1.6, 1.8), (0, 11.6, 0), YELLOW, segs=12, rings=8)
    p.ball((0.6, 0.6, 0.6), (0, 12.5, 0), RED, segs=8, rings=6)  # the cherry
    return done(p)


# ---------------------------------------------------------------- trees ----------------------
def oak():
    """A round park oak, 15 high: a flared trunk with two limbs into a crown of PAINT leaf clumps,
    lighter clumps on top."""
    p = Piece("Arena_Oak", exact=True, outline=BIG)
    p.cyl(2.4, 1.2, (0, 0.6, 0), TRUNK, d2=1.5, segs=10)
    p.cyl(1.5, 6.2, (0, 4.2, 0), TRUNK, d2=1.1, segs=10)
    rod(p, (0, 5.5, 0), (2.6, 8.6, 0.6), 0.7, TRUNK, segs=8)
    rod(p, (0, 6.0, 0), (-2.4, 8.8, -0.8), 0.7, TRUNK, segs=8)
    for x, y, z, s in ((0, 10.6, 0, 7.4), (2.8, 9.4, 0.8, 5.0), (-2.7, 9.6, -1.0, 5.2), (0.6, 9.2, -2.8, 4.8),
                       (-0.6, 9.4, 2.8, 4.8), (1.6, 12.6, -0.6, 4.4), (-1.6, 12.4, 1.0, 4.2)):
        p.ball((s, s * 0.82, s), (x, y, z), PAINT, segs=12, rings=8)
    for x, y, z, s in ((0.8, 13.8, 0.4, 2.6), (-1.6, 13.0, -1.2, 2.2), (2.6, 11.6, -1.6, 2.0)):
        p.ball((s, s * 0.7, s), (x, y, z), LEAF_L, segs=10, rings=6)
    return done(p)


def pine():
    """A pine, 16 high: four tiers of needles on a straight trunk."""
    p = Piece("Arena_Pine", exact=True, outline=BIG)
    p.cyl(1.5, 3.0, (0, 1.5, 0), TRUNK, d2=1.0, segs=8)
    for i, (y, d, h) in enumerate(((5.2, 7.6, 4.6), (8.3, 6.0, 4.2), (11.1, 4.4, 3.8), (13.7, 2.8, 3.4))):
        p.cyl(d, h, (0, y, 0), PINE if i % 2 == 0 else PINE_L, d2=0.4, segs=10, rot=(0, i * 17, 0))
    return done(p)


# ---------------------------------------------------------------- building site --------------
def mixer():
    """A cement mixer: an orange drum tilted on a frame, two wheels, a tow bar."""
    p = Piece("Arena_Mixer", exact=True, outline=0.05)
    p.box((2.6, 0.4, 3.6), (0, 1.6, 0), IRON, bevel=0.05)
    for s in (-1, 1):
        p.cyl(1.8, 0.5, (s * 1.5, 0.9, 0.6), "1C1C20", axis="x", segs=14, bevel=0.1)
        p.cyl(0.9, 0.56, (s * 1.5, 0.9, 0.6), CONCRETE, axis="x", segs=10)
        beam(p, (s * 1.0, 1.7, -0.6), (s * 0.9, 3.6, -0.2), 0.3, IRON, bevel=0.03)
    beam(p, (0, 1.4, -1.8), (0, 0.6, -3.6), 0.3, IRON, bevel=0.03)
    p.ring(0.3, 0.08, (0, 0.6, -3.8), IRON_L, segs=10, sides=5)
    c = Vector((0, 3.4, 0.2))
    axis = Vector((0, 0.55, -0.83))
    p.cyl(2.4, 1.8, tuple(c), ORANGE, rot=rot_to(axis), segs=16)
    p.cyl(2.4, 1.2, tuple(c + axis * 1.5), ORANGE, d2=1.4, rot=rot_to(axis), segs=16)
    p.cyl(2.4, 1.2, tuple(c - axis * 1.5), ORANGE, d2=1.6, rot=rot_to(-axis), segs=16)
    for k in (-0.5, 0.5):
        p.cyl(2.52, 0.2, tuple(c + axis * k), IRON, rot=rot_to(axis), segs=16)
    p.cyl(1.3, 0.3, tuple(c + axis * 2.25), "4A4A50", rot=rot_to(axis), segs=12)  # the mouth
    p.box((0.8, 1.0, 0.6), (1.3, 2.2, 1.4), YELLOW, bevel=0.08)  # motor
    return done(p)


def crane():
    """A tower crane over the building site, 50 high: a lattice mast on a concrete base, a cab, the jib
    out over the front (-Z) with its trolley and hook, the counter-jib and weights behind, an A-frame
    with ties to both ends."""
    p = Piece("Arena_Crane", exact=True, outline=0.06)
    p.box((7.0, 2.0, 7.0), (0, 1.0, 0), CONCRETE, bevel=0.2)
    top = 40.0
    h = 1.5
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box((0.45, top - 2.0, 0.45), (sx * h, 2.0 + (top - 2.0) / 2, sz * h), YELLOW, bevel=0.04)
    y = 2.0
    k = 0
    while y < top - 0.1:
        y1 = min(top, y + 3.0)
        for side in range(4):
            if side == 0:
                a, b = (-h, y, -h), (h, y1, -h)
            elif side == 1:
                a, b = (h, y, -h), (h, y1, h)
            elif side == 2:
                a, b = (h, y, h), (-h, y1, h)
            else:
                a, b = (-h, y, h), (-h, y1, -h)
            if k % 2:
                a, b = (b[0], a[1], b[2]), (a[0], b[1], a[2])
            beam(p, a, b, 0.22, YELLOW, bevel=0)
        p.box((2 * h + 0.45, 0.25, 2 * h + 0.45), (0, y1, 0), YELLOW, bevel=0.02)
        y, k = y1, k + 1
    p.box((4.0, 0.6, 4.0), (0, top + 0.3, 0), IRON, bevel=0.08)  # slewing ring
    p.box((2.8, 2.6, 2.8), (2.4, top + 1.9, -1.8), YELLOW, bevel=0.15)  # the cab
    p.box((2.86, 1.2, 1.6), (2.4, top + 2.3, -2.5), GLASS, bevel=0.03)
    # jib: two bottom chords and a top chord, zig-zag braced, out to z = -28
    L = 28.0
    for x in (-0.8, 0.8):
        beam(p, (x, top + 0.8, 1.2), (x, top + 0.8, -L), 0.3, YELLOW, bevel=0.02)
    beam(p, (0, top + 2.4, 1.2), (0, top + 2.2, -L), 0.3, YELLOW, bevel=0.02)
    z = 1.2
    i = 0
    while z > -L + 0.5:
        z1 = max(-L, z - 2.0)
        for x in (-0.8, 0.8):
            beam(p, (x, top + 0.8, z), (0, top + 2.4 - 0.2 * (1.2 - z1) / (L + 1.2), z1), 0.14, YELLOW, bevel=0)
        z, i = z1, i + 1
    beam(p, (-0.8, top + 0.8, -L), (0.8, top + 0.8, -L), 0.2, YELLOW, bevel=0)
    # counter-jib with concrete weights
    for x in (-0.8, 0.8):
        beam(p, (x, top + 0.8, 1.2), (x, top + 0.8, 10.0), 0.3, YELLOW, bevel=0.02)
    p.box((2.2, 0.2, 8.6), (0, top + 0.95, 5.6), IRON_L, bevel=0)
    for zz in (7.4, 8.6):
        p.box((2.4, 2.4, 1.0), (0, top - 0.1, zz), CONCRETE, bevel=0.1)
    # A-frame and ties
    for x in (-0.8, 0.8):
        beam(p, (x, top + 0.8, 1.0), (0, top + 8.0, 0), 0.3, YELLOW, bevel=0.02)
    beam(p, (0, top + 8.0, 0), (0, top + 2.3, -18.0), 0.12, IRON, bevel=0)
    beam(p, (0, top + 8.0, 0), (0, top + 0.9, 9.6), 0.12, IRON, bevel=0)
    p.ball((0.5, 0.5, 0.5), (0, top + 8.3, 0), RED, segs=8, rings=6)
    # trolley, cable, hook block and a load of planks
    p.box((1.8, 0.6, 1.4), (0, top + 0.3, -18.0), IRON, bevel=0.06)
    p.box((0.08, 10.0, 0.08), (0, top - 5.0, -18.0), IRON, bevel=0)
    p.box((1.0, 1.2, 0.8), (0, top - 10.6, -18.0), YELLOW, bevel=0.1)
    rod(p, (0, top - 11.2, -18.0), (0, top - 12.0, -17.6), 0.25, IRON, segs=6)
    for s in (-1, 1):
        beam(p, (0, top - 12.1, -17.6), (s * 1.6, top - 14.0, -17.6), 0.06, IRON, bevel=0)
    for j in range(3):
        p.box((3.6, 0.3, 1.6), (0, top - 14.2 - j * 0.32, -17.6), WOOD_L if j % 2 else WOOD, bevel=0.04)
    return done(p)


# ---------------------------------------------------------------- Cyclops: the forge ---------
def forge_gate():
    """The Cyclops's arch over its ramp: rough basalt pillars at x +-11, cracks of lava in them, a
    lintel of fallen slabs with one great carved eye glowing in the middle. Inner opening 18 wide."""
    p = Piece("Arena_ForgeGate", exact=True, outline=BIG)
    for s in (-1, 1):
        x = s * 11.5
        for i, (w, hgt, dx, tilt) in enumerate(((5.0, 4.0, 0.2, 3), (4.4, 5.0, -0.3, -4), (4.8, 4.6, 0.25, 5), (4.2, 4.0, -0.2, -3))):
            y = sum((4.0, 5.0, 4.6, 4.0)[:i]) + hgt / 2
            p.box((w, hgt + 0.2, 4.4 - i * 0.2), (x + s * dx, y, 0), ROCK if i % 2 == 0 else ROCK_D, rot=(0, i * 7, tilt), bevel=0.35)
        p.box((0.25, 6.0, 0.3), (x - s * 0.6, 7.0, -2.2), LAVA, rot=(0, 0, s * 12), bevel=0)
        p.box((0.2, 4.0, 0.3), (x + s * 0.8, 12.0, -2.15), LAVA, rot=(0, 0, -s * 18), bevel=0)
        p.box((5.6, 1.2, 5.0), (x, 0.6, 0), ROCK_D, bevel=0.3)
    p.box((29.0, 4.2, 4.6), (0, 19.6, 0), ROCK, rot=(0, 0, 1.5), bevel=0.5)
    p.box((14.0, 2.0, 4.2), (-6.0, 22.6, 0.2), ROCK_D, rot=(0, 3, -3), bevel=0.4)
    p.box((12.0, 2.2, 4.0), (6.5, 22.7, -0.1), ROCK_D, rot=(0, -4, 4), bevel=0.4)
    # the eye: a carved socket, a white, a glowing iris
    p.ball((7.2, 4.8, 1.2), (0, 19.8, -2.4), ROCK_D, segs=20, rings=10)
    p.ball((5.6, 3.6, 1.0), (0, 19.8, -2.62), BONE, segs=20, rings=10)
    p.ball((2.6, 2.6, 0.8), (0, 19.8, -3.0), LAVA, segs=16, rings=8)
    p.ball((1.0, 1.4, 0.5), (0, 19.8, -3.32), INK, segs=12, rings=6)
    p.box((7.6, 0.7, 0.9), (0, 22.1, -2.5), ROCK, rot=(0, 0, -6), bevel=0.2)  # the brow
    return done(p)


def forge():
    """The Cyclops's forge beside its pit: a stone hearth with a glowing arched mouth, a tall banded
    chimney, a pair of bellows and a rack of giant tongs."""
    p = Piece("Arena_Forge", exact=True, outline=BIG)
    p.box((11.0, 1.0, 8.0), (0, 0.5, 0), ROCK_D, bevel=0.25)
    p.box((10.0, 6.0, 7.0), (0, 4.0, 0), STONE_D, bevel=0.35)
    for y in (2.4, 4.0, 5.6):
        p.box((10.06, 0.14, 7.06), (0, y, 0), STONE_DD, bevel=0)
    p.box((10.6, 0.8, 7.6), (0, 7.4, 0), STONE, bevel=0.2)
    # the mouth: a dark arch with coals glowing in it
    p.prism([(0.0, 1.2), (0.0, 5.2), (0.32, 5.2), (0.32, 1.2)], 5.6, (0, 0, -3.66), STONE_L, bevel=0.06)  # frame
    p.box((4.8, 3.4, 0.4), (0, 3.0, -3.72), INK, bevel=0.1)
    p.ball((4.6, 1.6, 1.2), (0, 1.9, -3.7), FIRE, segs=14, rings=8)
    p.ball((3.0, 1.0, 1.0), (0, 2.5, -3.9), FIRE_Y, segs=12, rings=6)
    for x in (-1.6, -0.4, 0.8, 1.7):
        p.box((0.7, 0.5, 0.6), (x, 1.5, -4.0), ROCK_D, rot=(0, x * 20, 10), bevel=0.1)
    p.box((5.6, 0.7, 0.6), (0, 5.4, -3.8), STONE_L, bevel=0.12)  # lintel
    # chimney
    p.box((4.2, 18.0, 4.2), (2.4, 16.0, 1.4), STONE_D, bevel=0.3)
    for y in (10.0, 15.0, 20.0, 24.6):
        p.box((4.5, 0.5, 4.5), (2.4, y, 1.4), IRON, bevel=0.08)
    p.box((5.0, 1.0, 5.0), (2.4, 25.5, 1.4), STONE, bevel=0.2)
    p.box((3.0, 0.3, 3.0), (2.4, 26.1, 1.4), INK, bevel=0)
    p.ball((2.6, 0.9, 2.6), (2.4, 26.3, 1.4), FIRE, segs=10, rings=6)
    # bellows on the left, a tong rack on the right
    p.prism([(-1.8, 0.0), (1.8, 0.0), (1.8, 0.4), (-1.6, 2.4), (-1.8, 2.4)], 3.0, (-6.8, 1.2, -1.0), "7A4A2E", bevel=0.15)
    p.box((3.2, 0.3, 3.8), (-6.8, 1.15, -1.0), WOOD_D, bevel=0.06)
    rod(p, (-6.8, 2.4, 0.8), (-6.8, 4.6, 2.8), 0.4, WOOD, segs=8)
    rod(p, (-6.8, 1.5, -2.8), (-4.8, 1.8, -3.4), 0.6, IRON, segs=8)
    p.box((0.4, 6.0, 0.4), (6.4, 3.0, -2.6), WOOD_D, bevel=0.05)
    p.box((0.4, 6.0, 0.4), (6.4, 3.0, 2.6), WOOD_D, bevel=0.05)
    p.box((0.5, 0.4, 5.6), (6.4, 5.6, 0), WOOD_D, bevel=0.05)
    for z in (-1.6, 0.0, 1.6):
        beam(p, (6.7, 5.4, z), (6.9, 1.2, z - 0.4), 0.26, IRON, bevel=0.02)
        beam(p, (6.7, 5.4, z), (6.9, 1.2, z + 0.4), 0.26, IRON, bevel=0.02)
    return done(p)


def anvil():
    """A giant's anvil on an oak stump, a sledgehammer the size of a man leaning on it."""
    p = Piece("Arena_Anvil", exact=True, outline=0.06)
    p.cyl(4.4, 3.0, (0, 1.5, 0), WOOD, d2=3.8, segs=14)
    for k in range(3):
        p.cyl(3.5 - k * 0.9, 0.06, (0, 3.02, 0), WOOD_L if k % 2 == 0 else WOOD_D, segs=14)
    p.box((2.4, 1.4, 3.0), (0, 3.7, 0), IRON, bevel=0.1)
    p.prism([(-4.6, 5.6), (-3.2, 5.0), (-1.6, 4.4), (1.4, 4.4), (1.8, 5.0), (2.6, 5.0), (2.6, 6.6), (-2.8, 6.6), (-3.8, 6.3)],
            2.4, (0, 0, 0), IRON, bevel=0.15)
    p.box((2.5, 0.12, 4.6), (0, 6.66, -0.3), IRON_L, bevel=0)
    beam(p, (1.8, 0.0, 2.6), (2.2, 6.4, 1.2), 0.5, WOOD_L, bevel=0.08)
    p.box((1.8, 1.4, 2.8), (2.25, 7.0, 1.05), IRON_L, rot=rot_to((0.4, 6.4, -1.4)), bevel=0.15)
    return done(p)


# ---------------------------------------------------------------- Minotaur: the labyrinth ----
def bull_skull(p, at, scale=1.0):
    x0, y0, z0 = at
    s = scale
    p.ball((3.4 * s, 3.0 * s, 3.2 * s), (x0, y0, z0), BONE, segs=16, rings=10)
    p.box((2.0 * s, 2.4 * s, 2.6 * s), (x0, y0 - 1.6 * s, z0 - 0.9 * s), BONE, rot=(25, 0, 0), bevel=0.6 * s)
    for sx in (-1, 1):
        p.ball((0.8 * s, 0.9 * s, 0.4 * s), (x0 + sx * 0.8 * s, y0 + 0.1 * s, z0 - 1.5 * s), INK, segs=10, rings=6)
        p.ball((0.35 * s, 0.4 * s, 0.3 * s), (x0 + sx * 0.4 * s, y0 - 2.8 * s, z0 - 2.0 * s), INK, segs=8, rings=4)
        # the horns: out, then up and forward, darkening to the tips
        pts = [(x0 + sx * (1.4 + 1.2 * t + 1.3 * t * t) * s, y0 + (0.6 + 3.4 * t * t) * s, z0 + (-0.2 - 1.0 * t * t) * s) for t in (i / 6 for i in range(7))]
        for i, (a, b) in enumerate(zip(pts, pts[1:])):
            rod(p, a, b, (1.0 - i * 0.13) * s, HORN if i < 4 else HORN_D, segs=10)


def bull_gate():
    """The Minotaur's gate over its ramp: two fluted marble columns at x +-11 carrying a lintel with a
    gold meander, double-axe emblems on the columns, and a bull skull with great horns on top."""
    p = Piece("Arena_BullGate", exact=True, outline=BIG)
    for s in (-1, 1):
        x = s * 11.5
        p.box((4.4, 1.0, 4.4), (x, 0.5, 0), STONE, bevel=0.2)
        p.cyl(3.4, 0.8, (x, 1.4, 0), MARBLE_S, segs=16, bevel=0.15)
        p.cyl(2.8, 13.0, (x, 8.3, 0), MARBLE, d2=2.5, segs=16)
        for i in range(12):  # flutes
            a = 2 * math.pi * i / 12
            p.box((0.18, 12.6, 0.18), (x + 1.33 * math.sin(a), 8.3, -1.33 * math.cos(a)), MARBLE_S, bevel=0)
        p.cyl(2.8, 0.6, (x, 15.1, 0), MARBLE_S, d2=3.6, segs=16)
        p.box((4.2, 0.8, 4.2), (x, 15.8, 0), MARBLE, bevel=0.15)
        # labrys: two crescent blades either side of a haft, gold, on the column's face
        p.box((0.3, 3.2, 0.3), (x, 8.0, -1.42), GOLD_D, bevel=0.04)
        for b in (-1, 1):
            p.ball((1.5, 2.2, 0.26), (x + b * 0.85, 8.6, -1.5), GOLD, segs=14, rings=8)
    p.box((28.0, 2.6, 4.0), (0, 17.5, 0), MARBLE, bevel=0.25)
    p.box((28.6, 0.6, 4.4), (0, 19.1, 0), MARBLE_S, bevel=0.12)
    p.box((26.0, 0.8, 0.2), (0, 17.5, -2.06), GOLD_D, bevel=0)
    for i in range(13):  # the meander, a key every two studs
        x = -12.0 + i * 2.0
        p.box((0.3, 1.4, 0.2), (x - 0.6, 17.5, -2.14), GOLD, bevel=0)
        p.box((1.2, 0.3, 0.2), (x, 18.05, -2.14), GOLD, bevel=0)
        p.box((0.3, 0.9, 0.2), (x + 0.6, 17.75, -2.14), GOLD, bevel=0)
        p.box((0.8, 0.3, 0.2), (x + 0.2, 17.0, -2.14), GOLD, bevel=0)
    bull_skull(p, (0, 22.4, 0.0), 1.2)
    return done(p)


def bull_statue():
    """A charging bull in bronze on a stone plinth (8 long): head down, horns forward (-Z)."""
    p = Piece("Arena_BullStatue", exact=True, outline=0.06)
    p.box((4.6, 2.0, 9.0), (0, 1.0, 0), STONE, bevel=0.2)
    p.box((4.8, 0.3, 9.2), (0, 2.05, 0), STONE_L, bevel=0.08)
    y = 2.2
    p.ball((3.6, 3.4, 6.4), (0, y + 3.9, 0.4), BRONZE, segs=18, rings=12)
    p.ball((3.9, 3.8, 3.6), (0, y + 4.4, -1.6), BRONZE, segs=16, rings=10)  # shoulders
    p.ball((2.4, 2.2, 2.8), (0, y + 3.2, -3.9), BRONZE, rot=(-25, 0, 0), segs=14, rings=10)  # head
    p.box((1.6, 1.2, 1.4), (0, y + 2.5, -5.0), BRONZE_D, rot=(-30, 0, 0), bevel=0.4)  # muzzle
    p.ring(0.45, 0.1, (0, y + 2.0, -5.5), GOLD, segs=12, sides=5)  # nose ring
    for s in (-1, 1):
        p.ball((0.4, 0.4, 0.3), (s * 0.95, y + 3.7, -4.6), INK, segs=8, rings=4)
        rod(p, (s * 1.0, y + 4.2, -3.6), (s * 2.0, y + 4.6, -4.2), 0.6, HORN, segs=8)
        rod(p, (s * 2.0, y + 4.6, -4.2), (s * 2.2, y + 4.8, -5.6), 0.42, HORN, segs=8)
        rod(p, (s * 2.2, y + 4.8, -5.6), (s * 1.9, y + 5.2, -6.4), 0.24, HORN_D, segs=6)
        for z, lean in ((-1.8, -25), (2.4, 20)):  # legs, front ones reaching forward
            beam(p, (s * 1.0, y + 3.0, z), (s * 1.0, y + 0.4, z + math.sin(math.radians(lean)) * 2.4), 0.9, BRONZE, bevel=0.2)
            p.box((0.95, 0.5, 1.1), (s * 1.0, y + 0.25, z + math.sin(math.radians(lean)) * 2.6), BRONZE_D, bevel=0.1)
    rod(p, (0, y + 4.8, 3.4), (0.4, y + 3.0, 5.0), 0.3, BRONZE_D, segs=6)  # tail
    p.ball((0.6, 0.9, 0.6), (0.45, y + 2.7, 5.2), BRONZE_D, segs=8, rings=4)
    return done(p)


# ---------------------------------------------------------------- Talos: the bronze island ---
def talos_gate():
    """Talos's gate, Minoan: red columns widening upward at x +-11 with black cushion capitals, a
    bronze lintel with rosettes, the horns of consecration in gold on top; two glowing teal lamps."""
    p = Piece("Arena_TalosGate", exact=True, outline=BIG)
    for s in (-1, 1):
        x = s * 11.5
        p.box((4.6, 1.0, 4.6), (x, 0.5, 0), STONE_L, bevel=0.2)
        p.cyl(3.4, 0.7, (x, 1.35, 0), CAP_BLACK, segs=16, bevel=0.15)
        p.cyl(2.2, 12.6, (x, 8.0, 0), MINOAN, d2=3.0, segs=16)
        p.ball((4.2, 1.8, 4.2), (x, 14.9, 0), CAP_BLACK, segs=18, rings=8)
        p.box((4.4, 1.0, 4.4), (x, 16.1, 0), CAP_BLACK, bevel=0.15)
        p.cyl(3.0, 0.3, (x, 13.6, 0), GOLD, segs=16)
        p.box((1.0, 1.2, 0.6), (x - s * 1.8, 11.0, -1.4), TALOS_GLOW, bevel=0.1)
        p.box((1.3, 0.3, 0.9), (x - s * 1.8, 11.75, -1.4), BRONZE_D, bevel=0.05)
    p.box((28.0, 2.8, 4.0), (0, 18.0, 0), BRONZE, bevel=0.25)
    p.box((28.4, 0.5, 4.3), (0, 16.7, 0), BRONZE_D, bevel=0.1)
    p.box((28.4, 0.5, 4.3), (0, 19.4, 0), BRONZE_D, bevel=0.1)
    for i in range(9):
        x = -10.0 + i * 2.5
        p.cyl(1.5, 0.2, (x, 18.0, -2.05), BRONZE_L, axis="z", segs=12)
        p.cyl(0.6, 0.24, (x, 18.0, -2.12), PATINA, axis="z", segs=8)
    # horns of consecration: a gold base with two horns flaring up and out
    p.box((10.0, 0.7, 1.6), (0, 19.95, 0), GOLD_D, bevel=0.1)
    p.box((6.4, 1.6, 1.3), (0, 21.1, 0), GOLD, bevel=0.15)
    for s in (-1, 1):
        rod(p, (s * 2.9, 21.6, 0), (s * 4.3, 24.8, 0), 1.3, GOLD, segs=10)
        rod(p, (s * 4.3, 24.8, 0), (s * 4.0, 26.0, 0), 0.8, GOLD, segs=8)
    return done(p)


def talos_head():
    """The head of an older bronze giant, fallen on the island and half sunk: a crested helmet, a
    straight nose, eyes still glowing teal, green patina in its seams. It leans over, sunk to the chin."""
    p = Piece("Arena_TalosHead", exact=True, outline=BIG)
    # built upright facing -Z, then the whole piece is tipped over at the end (see below)
    p.ball((7.2, 8.4, 7.6), (0, 6.0, 0), BRONZE, segs=24, rings=14)  # helmet bowl
    p.box((6.6, 3.6, 1.6), (0, 5.0, -3.4), BRONZE_D, bevel=0.6)  # face plate
    p.box((1.0, 2.6, 1.2), (0, 4.6, -4.4), BRONZE, rot=(-12, 0, 0), bevel=0.3)  # nose guard
    for s in (-1, 1):
        p.ball((1.8, 0.9, 0.6), (s * 1.7, 6.0, -4.2), TALOS_GLOW, segs=12, rings=6)
        p.box((2.6, 0.5, 0.8), (s * 1.7, 6.8, -4.15), BRONZE_L, rot=(0, 0, s * -8), bevel=0.15)  # brow
        p.box((1.6, 3.6, 1.4), (s * 2.9, 3.4, -2.8), BRONZE, rot=(0, s * 15, 0), bevel=0.4)  # cheek guards
    p.box((2.6, 0.6, 1.0), (0, 2.6, -3.9), BRONZE_D, bevel=0.2)  # lips
    p.prism([(-3.6, 9.4), (-2.4, 11.6), (0.6, 12.6), (3.6, 11.8), (5.2, 9.6), (4.2, 9.0), (-3.0, 9.0)], 1.4, (0, 0, 0), RED, bevel=0.2)  # crest
    p.box((1.6, 0.8, 8.0), (0, 9.2, 0.6), BRONZE_D, bevel=0.2)
    for z in (-2.0, 0.0, 2.0):
        p.box((7.3, 0.2, 0.3), (0, 7.4 + z * 0.2, z), PATINA, bevel=0)
    p.box((7.0, 1.0, 7.4), (0, 2.2, 0.4), BRONZE_D, bevel=0.3)  # neck rim
    ob = done(p)
    # lean it over (about Roblox Z = Blender Y) and sink it to the chin in the island
    import mathutils
    me = ob.data
    me.transform(mathutils.Matrix.Rotation(math.radians(16), 4, "Y"))
    xs = [v.co.x for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    me.transform(mathutils.Matrix.Translation((-(max(xs) + min(xs)) / 2, 0, -min(zs) - 2.2)))
    me.update()
    return ob


def brazier():
    """A bronze tripod brazier, 5 high, burning."""
    p = Piece("Arena_Brazier", exact=True, outline=0.05)
    for i in range(3):
        a = 2 * math.pi * i / 3
        rod(p, (1.5 * math.sin(a), 0.0, -1.5 * math.cos(a)), (0.7 * math.sin(a), 3.2, -0.7 * math.cos(a)), 0.3, BRONZE_D, segs=6)
        p.ball((0.5, 0.4, 0.5), (1.5 * math.sin(a), 0.2, -1.5 * math.cos(a)), BRONZE, segs=8, rings=4)
    p.cyl(1.6, 0.8, (0, 3.2, 0), BRONZE, d2=2.6, segs=14)
    p.cyl(2.7, 0.24, (0, 3.68, 0), BRONZE_L, segs=14)
    p.cyl(2.3, 0.14, (0, 3.6, 0), INK, segs=14)
    p.cyl(2.0, 1.6, (0, 4.5, 0), FIRE, d2=0.2, segs=7)
    p.cyl(1.2, 1.4, (0.2, 4.4, 0.1), FIRE_Y, d2=0.1, segs=6, rot=(0, 30, 0))
    return done(p)


def minoan_column():
    """A free-standing Minoan column, 12 high: red, wider at the top, black cushion capital."""
    p = Piece("Arena_Column", exact=True, outline=BIG)
    p.box((3.8, 0.8, 3.8), (0, 0.4, 0), STONE_L, bevel=0.15)
    p.cyl(2.8, 0.6, (0, 1.1, 0), CAP_BLACK, segs=14, bevel=0.1)
    p.cyl(1.8, 8.6, (0, 5.7, 0), MINOAN, d2=2.5, segs=14)
    p.cyl(2.6, 0.26, (0, 9.2, 0), GOLD, segs=14)
    p.ball((3.6, 1.6, 3.6), (0, 10.6, 0), CAP_BLACK, segs=16, rings=8)
    p.box((3.8, 0.8, 3.8), (0, 11.6, 0), CAP_BLACK, bevel=0.12)
    return done(p)


PIECES = (statue, lamp, bench, fountain, ad_column, gate, house, shop, kiosk, oak, pine, mixer, crane,
          forge_gate, forge, anvil, bull_gate, bull_statue, talos_gate, talos_head, brazier, minoan_column)


def layout():
    """Spread the pieces out on a grid for a look (origins stay at the pieces' own ground points: only the
    objects move; export.py works on the meshes)."""
    obs = sorted((o for o in bpy.data.collections["ArenaKit"].objects), key=lambda o: o.name)
    x = 0.0
    for ob in obs:
        xs = [v.co.x for v in ob.data.vertices]
        w = max(xs) - min(xs)
        ob.location = (x - min(xs), 0, 0)
        x += w + 4.0


def main():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    tris = {}
    for fn in PIECES:
        ob = fn()
        ob.data.calc_loop_triangles()
        tris[ob.name] = len(ob.data.loop_triangles)
    layout()
    for name, n in sorted(tris.items()):
        print(f"PIECE {name}: {n} tris")
    out = os.path.join(HERE, "arena.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("saved", out)


if __name__ == "__main__":
    main()
