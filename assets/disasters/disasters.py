# The disasters' meshes (client/Disasters): the bomb, meteor, wave, UFO, volcano, bolt, ice, cloud and tombstone, built in code
# in the weapons' comic style (assets/weapons/comic_weapons.py: Builder parts, flat shading, comic.punch
# colours, the black inverted-hull outline) and written by assets/weapons/export.py to
# src/client/DisasterMeshes/<Name>.luau (EditableMesh data, no upload). Axes as export.py: Blender +Z up,
# -Y forward. 1 unit = 1 stud at modelling scale; the game sets each MeshPart's Size.
# Headless:  blender -b --factory-startup --python assets/disasters/disasters.py [-- render]
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CW = {"__file__": os.path.join(REPO, "assets", "weapons", "comic_weapons.py"), "__name__": "comic_weapons"}
exec(open(CW["__file__"]).read(), CW)
Builder, punch, outline, material = CW["Builder"], CW["punch"], CW["outline"], CW["material"]
METAL, GREY, BLACK, OD, OD_DARK = CW["METAL"], CW["GREY"], CW["BLACK"], CW["OD"], CW["OD_DARK"]
YELLOW, RED, STEEL = CW["YELLOW"], CW["RED"], CW["STEEL"]
V = Vector

ROCK = [(0.29, 0.22, 0.18), (0.36, 0.29, 0.23), (0.22, 0.18, 0.16), (0.42, 0.36, 0.3)]
LAVA = [(1.0, 0.45, 0.08), (1.0, 0.7, 0.15)]
SEA = [(0.04, 0.2, 0.55), (0.1, 0.38, 0.8), (0.25, 0.6, 0.95), (0.55, 0.82, 1.0)]
FOAM = (0.95, 0.98, 1.0)
SILVER, PURPLE, GLASS, BEAM, LIGHT = (0.75, 0.78, 0.83), (0.45, 0.2, 0.62), (0.4, 0.9, 0.95), (0.45, 1.0, 0.5), (1.0, 0.95, 0.6)
ZAP = (1.0, 0.88, 0.15)
ICE_LIGHT, ICE_TIP, ICE_DARK = (0.66, 0.9, 1.0), (0.92, 0.98, 1.0), (0.42, 0.66, 0.86)
PUFF, PUFF_SHADE = (0.97, 0.97, 0.98), (0.8, 0.82, 0.86)
STONE, STONE_DARK, DIRT = (0.55, 0.56, 0.6), (0.36, 0.37, 0.42), (0.36, 0.25, 0.17)


def lathe(b, profile, rgb, seg=16):
    """A solid of revolution round Z: profile = [(z, r)] bottom to top; r = 0 closes an end in a point."""
    def make():
        rings = []
        for z, r in profile:
            if r == 0:
                rings.append([b.bm.verts.new((0, 0, z))])
            else:
                rings.append([b.bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z))
                              for k in range(seg)])
        for a, c in zip(rings, rings[1:]):
            for k in range(seg):
                if len(a) == 1:
                    b.bm.faces.new([a[0], c[(k + 1) % seg], c[k]])
                elif len(c) == 1:
                    b.bm.faces.new([a[k], a[(k + 1) % seg], c[0]])
                else:
                    b.bm.faces.new([a[k], a[(k + 1) % seg], c[(k + 1) % seg], c[k]])
        if len(rings[0]) > 1:
            b.bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            b.bm.faces.new(rings[-1])
    b._part(make, rgb)


def sector(b, centre, normal, up, r0, r1, a0, a1, rgb, depth=0.03, steps=4):
    """A flat ring sector (a radiation-sign blade) standing out of a surface along `normal`."""
    n, u = V(normal).normalized(), V(up).normalized()
    w = n.cross(u)
    c = V(centre)

    def make():
        pts = []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            d = math.cos(a) * u + math.sin(a) * w
            pts.append((c + d * r0, c + d * r1))
        inner = [p[0] for p in pts]
        outer = [p[1] for p in pts]
        ring = outer + list(reversed(inner)) if r0 > 0 else outer + [c]
        bottom = [b.bm.verts.new(p) for p in ring]
        top = [b.bm.verts.new(p + n * depth) for p in ring]
        b.bm.faces.new(top)
        b.bm.faces.new(list(reversed(bottom)))
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            b.bm.faces.new([bottom[i], bottom[j], top[j], top[i]])
    b._part(make, rgb)


def nuke(b):
    """A fat cartoon bomb, nose down (-Z), origin at its middle, ~3.4 long."""
    body = [(-1.62, 0), (-1.55, 0.36), (-1.4, 0.6), (-1.15, 0.76), (-0.8, 0.84), (-0.2, 0.86), (0.4, 0.82),
            (0.85, 0.68), (1.15, 0.46), (1.32, 0.3)]
    lathe(b, body, OD)
    lathe(b, [(-0.25, 0.875), (0.15, 0.875)], YELLOW)  # the hazard band
    for z in (-1.05, 0.62):
        lathe(b, [(z - 0.035, 0.83 if z < 0 else 0.79), (z + 0.035, 0.83 if z < 0 else 0.79)], GREY)  # seams
    lathe(b, [(-1.75, 0.0), (-1.72, 0.1), (-1.6, 0.16), (-1.5, 0.16)], METAL, seg=10)  # nose fuze
    for k in range(4):  # tail fins and the box shroud round their tips
        a = math.pi / 4 + k * math.pi / 2
        d = V((math.cos(a), math.sin(a), 0))
        s = V((-d.y, d.x, 0))
        b.hexa({(ix, iy, iz): d * ((0.18, 1.02)[ix] if iz else (0.6, 0.9)[ix]) + s * (-0.035, 0.035)[iy]
                + V((0, 0, (0.75, 1.62)[iz])) for ix in (0, 1) for iy in (0, 1) for iz in (0, 1)}, OD_DARK)
    for k in range(4):
        a = k * math.pi / 2
        d = V((math.cos(a), math.sin(a), 0))
        s = V((-d.y, d.x, 0))
        lo = d * 0.66 - s * 0.72 + V((0, 0, 1.2))
        hi = d * 0.74 + s * 0.72 + V((0, 0, 1.62))
        b.box(V((min(lo.x, hi.x), min(lo.y, hi.y), lo.z)), V((max(lo.x, hi.x), max(lo.y, hi.y), hi.z)), OD_DARK, 0.02)
    lathe(b, [(1.3, 0.22), (1.5, 0.22)], METAL, seg=10)  # tail cap
    for side in (-1, 1):  # the radiation sign on both flanks: yellow plate, three black blades, a dot
        n = V((0, side, 0))
        c = V((0, side * 0.86, 0.45))
        sector(b, c, n, (0, 0, 1), 0, 0.3, 0, 360, YELLOW, 0.02, steps=12)
        for k in range(3):
            sector(b, c + n * 0.02, n, (0, 0, 1), 0.07, 0.27, 120 * k - 30, 120 * k + 30, BLACK, 0.02)
        sector(b, c + n * 0.02, n, (0, 0, 1), 0, 0.045, 0, 360, BLACK, 0.02, steps=8)


def meteor(b):
    """A lumpy rock, radius ~1, glowing cracks in its lows; origin at its middle."""
    rnd = random.Random(7)

    def make():
        bmesh.ops.create_icosphere(b.bm, subdivisions=3, radius=1.0)
    b._part(make, ROCK[0])
    craters = [V((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized() for _ in range(4)]
    for v in b.bm.verts:
        d = v.co.normalized()
        h = 1 + 0.3 * noise.noise(d * 1.6 + V((3, 1, 2))) + 0.1 * noise.noise(d * 4.2)
        for c in craters:
            k = max(0.0, 1 - (d - c).length / 0.45)
            h -= 0.16 * k * k
        v.co = d * h
    b.bm.normal_update()
    for f in b.bm.faces:
        c = f.calc_center_median()
        crack = noise.noise(c * 2.4 + V((9, 4, 1)))
        rgb = LAVA[1] if crack > 0.45 else LAVA[0] if crack > 0.32 else ROCK[rnd.randrange(len(ROCK))]
        for loop in f.loops:
            loop[b.col] = (*rgb, 1)


def wave(b, width=28.0, slices=24):
    """A curling breaker, rolling toward -Y: its face's foot along y = 0, the body behind it (+Y), ~3.3
    high; it shrinks at both ends so it has no cut-off sides. Foam balls ride its lip."""
    # the cross-section, going round: back foot, up the back, crest, lip, under the curl, down the face
    prof = [(7.5, 0.0), (5.6, 0.35), (3.8, 1.0), (2.3, 1.9), (1.2, 2.8), (0.3, 3.35), (-0.7, 3.5),
            (-1.7, 3.3), (-2.5, 2.8), (-2.7, 2.3), (-2.3, 2.05), (-1.6, 2.1), (-1.0, 1.8), (-0.75, 1.2),
            (-0.85, 0.55), (-1.3, 0.0)]
    rnd = random.Random(3)
    rings, fades = [], []
    for i in range(slices + 1):
        t = i / slices
        x = (t - 0.5) * width
        edge = min(t, 1 - t) / 0.18
        fade = 0.12 + 0.88 * (min(edge, 1) ** 0.7)  # 1 in the middle, small at the ends
        wob = 1 + 0.08 * math.sin(t * 11.0) + 0.05 * math.sin(t * 23.0 + 1)
        curl = fade * wob
        ring = []
        for j, (y, z) in enumerate(prof):
            yy = y * (0.55 + 0.45 * fade) if y > 0 else y * curl  # the curl reaches out only mid-wave
            ring.append(V((x, yy, z * fade * wob)))
        rings.append(ring)
        fades.append(fade)

    def color(z, y):
        if z > 3.0 or y < -2.05:
            return FOAM  # the crest and the lip
        return SEA[min(int(z / 3.5 * 4), 3)]

    def make():
        vs = [[b.bm.verts.new(p) for p in ring] for ring in rings]
        n = len(prof)
        for a, c in zip(vs, vs[1:]):
            for j in range(n):
                k = (j + 1) % n
                b.bm.faces.new([a[j], c[j], c[k], a[k]])
        b.bm.faces.new(vs[0])
        b.bm.faces.new(list(reversed(vs[-1])))
    b._part(make, SEA[1])
    for f in b.bm.faces:
        c = f.calc_center_median()
        for loop in f.loops:
            loop[b.col] = (*color(c.z, c.y), 1)
    for i in range(2, slices - 1):  # chunky foam on the lip
        if rnd.random() < 0.85:
            ring = rings[i]
            lip = ring[7]
            b.ball(lip + V((rnd.uniform(-0.4, 0.4), rnd.uniform(-0.2, 0.3), rnd.uniform(-0.15, 0.25))),
                   0.32 * fades[i] + rnd.uniform(0.05, 0.25) * fades[i], FOAM, seg=6, rings=4)


def ufo(b):
    """A comic flying saucer, ~6.6 across, origin at its middle: silver hull, a purple band of lights,
    a cyan glass dome with an antenna, the green beam ring underneath."""
    lathe(b, [(-0.62, 0), (-0.56, 1.2), (-0.36, 2.4), (-0.12, 3.2), (0.06, 3.26), (0.26, 2.6), (0.42, 1.6), (0.46, 0)],
          SILVER, seg=24)
    lathe(b, [(-0.14, 3.3), (0.1, 3.3)], PURPLE, seg=24)  # the band
    lathe(b, [(0.4, 1.5), (0.8, 1.42), (1.2, 1.12), (1.48, 0.62), (1.58, 0)], GLASS, seg=20)  # the dome
    lathe(b, [(-0.8, 0), (-0.74, 0.62), (-0.58, 0.9)], BEAM, seg=16)  # the beam's lens
    for k in range(12):  # the running lights
        a = 2 * math.pi * k / 12
        b.ball((3.36 * math.cos(a), 3.36 * math.sin(a), -0.02), 0.2, YELLOW if k % 2 else RED, seg=8, rings=6)
    for k in range(6):  # portholes along the dome's foot
        a = 2 * math.pi * k / 6 + 0.3
        b.ball((1.62 * math.cos(a), 1.62 * math.sin(a), 0.48), 0.14, LIGHT, seg=6, rings=4)
    b.tube((0, 0, 1.5), (0, 0, 2.3), 0.05, GREY, seg=6)  # antenna
    b.ball((0, 0, 2.38), 0.13, RED, seg=8, rings=6)


def volcano(b):
    """A lumpy comic volcano, ~9 across and 3.2 high, origin at the middle of its foot: dark rock, a
    lava-filled crater and three lava streams running down its flanks, boulders round the base."""
    rnd = random.Random(11)
    prof = [(0.0, 4.6), (0.5, 4.0), (1.2, 3.1), (1.9, 2.25), (2.5, 1.65), (2.95, 1.3), (3.1, 1.2), (2.95, 1.0),
            (2.6, 0.6), (2.45, 0)]
    lathe(b, prof, ROCK[0], seg=28)
    for v in b.bm.verts:  # lumps, more toward the foot
        r = math.hypot(v.co.x, v.co.y)
        if r > 0.3:
            k = 1 + 0.1 * noise.noise(V((v.co.x * 0.8, v.co.y * 0.8, v.co.z * 0.6)))
            v.co.x, v.co.y = v.co.x * k, v.co.y * k
            v.co.z += 0.12 * noise.noise(V((v.co.x, v.co.y, 3.0))) * min(1.0, r / 2)
    streams = [0.4, 2.5, 4.4]  # angles of the lava streams
    for f in b.bm.faces:
        c = f.calc_center_median()
        r, a = math.hypot(c.x, c.y), math.atan2(c.y, c.x) % (2 * math.pi)
        width = 0.16 + 0.1 * (c.z / 3)  # the streams narrow as they run down
        lava = r < 1.15 and c.z > 2.3 or any(min(abs(a - s), 2 * math.pi - abs(a - s)) < width and c.z > 0.5 for s in streams)
        rgb = (LAVA[1] if r < 0.9 else LAVA[0]) if lava else ROCK[rnd.randrange(len(ROCK))]
        for loop in f.loops:
            loop[b.col] = (*rgb, 1)
    for _ in range(9):  # boulders round the foot
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(4.2, 4.9)
        b.ball((r * math.cos(a), r * math.sin(a), 0.15), rnd.uniform(0.25, 0.5), ROCK[rnd.randrange(len(ROCK))], seg=6, rings=4)


def bolt(b):
    """A comic lightning bolt, 10 tall, flat (0.5 thick), its tip at the origin and its top at +Z."""
    pts = [(-0.9, 10.0), (1.3, 10.0), (0.3, 6.2), (1.5, 6.2), (-0.3, 0.0), (0.1, 4.6), (-1.1, 4.6)]

    def make():
        front = [b.bm.verts.new((x, -0.25, z)) for x, z in pts]
        back = [b.bm.verts.new((x, 0.25, z)) for x, z in pts]
        b.bm.faces.new(front)
        b.bm.faces.new(list(reversed(back)))
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            b.bm.faces.new([front[i], back[i], back[j], front[j]])
    b._part(make, ZAP)


def ice(b):
    """A cluster of ice crystals, ~2.6 across and 3 high, origin at its foot: tilted hexagonal prisms
    with pointed tips round a frozen lump."""
    rnd = random.Random(5)
    b.ball((0, 0, 0.1), 0.7, ICE_DARK, seg=8, rings=5)
    for k in range(7):
        a = 2 * math.pi * k / 7 + rnd.uniform(-0.3, 0.3)
        tilt = 0.15 + 0.35 * (k > 0)
        d = V((math.cos(a) * tilt, math.sin(a) * tilt, 1)).normalized() if k else V((0, 0, 1))
        base = V((math.cos(a) * 0.35, math.sin(a) * 0.35, 0)) if k else V((0, 0, 0))
        length = rnd.uniform(1.2, 1.9) if k else 2.6
        r = rnd.uniform(0.18, 0.28) if k else 0.36
        b.cyl(base + d * length / 2, d, length, r, ICE_LIGHT, seg=6)
        b.cyl(base + d * (length + r * 1.1), d, r * 2.2, r, ICE_TIP, r2=0.0, seg=6)


def cloud(b):
    """A comic cloud puff, ~3 across: overlapping lumpy balls, near-white so the game can tint it
    (MeshPart.Color multiplies the vertex colours). Origin at its middle."""
    rnd = random.Random(2)
    blobs = [((0, 0, 0.1), 1.0), ((0.95, 0.2, -0.1), 0.72), ((-0.9, -0.15, -0.12), 0.75), ((0.25, 0.85, 0.0), 0.68),
             ((-0.3, -0.85, -0.05), 0.66), ((0.4, -0.2, 0.75), 0.6), ((-0.45, 0.35, 0.6), 0.55)]
    for (x, y, z), r in blobs:
        def make(x=x, y=y, z=z, r=r):
            bmesh.ops.create_icosphere(b.bm, subdivisions=2, radius=r, matrix=Matrix.Translation(V((x, y, z))))
        b._part(make, PUFF)
    for f in b.bm.faces:  # a touch of shade underneath, the comic way: two tones
        rgb = PUFF_SHADE if f.calc_center_median().z < -0.35 else PUFF
        for loop in f.loops:
            loop[b.col] = (*rgb, 1)


def tombstone(b):
    """A crooked comic tombstone on a dirt mound, ~2.4 high, origin at its foot, the stone's face toward -Y."""
    b.hexa({(ix, iy, iz): V(((-0.6, 0.6)[ix] + 0.08 * iz, (-0.18, 0.18)[iy], (0.0, 1.6)[iz])) for ix in (0, 1) for iy in (0, 1)
            for iz in (0, 1)}, STONE, 0.05)
    b.cyl((0.13, 0, 1.6), "y", 0.36, 0.6, STONE, seg=12)  # the rounded top
    b.box(V((-0.08, -0.22, 0.75)), V((0.08, -0.17, 1.55)), STONE_DARK)  # the cross
    b.box(V((-0.32, -0.22, 1.18)), V((0.32, -0.17, 1.32)), STONE_DARK)
    b.hexa({(ix, iy, iz): V(((-0.75, 0.75)[ix] * (1 - 0.3 * iz), (-2.0, -0.2)[iy] * (1 - 0.15 * iz), (0.0, 0.35)[iz]))
            for ix in (0, 1) for iy in (0, 1) for iz in (0, 1)}, DIRT, 0.1)  # the grave's mound


MODELS = {"NukeBomb": nuke, "Meteor": meteor, "TsunamiWave": wave, "Ufo": ufo, "Volcano": volcano, "Bolt": bolt,
          "IceShards": ice, "CloudPuff": cloud, "Tombstone": tombstone}


def build(name):
    b = Builder()
    MODELS[name](b)
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    me = bpy.data.meshes.new(name)
    b.bm.to_mesh(me)
    b.bm.free()
    ob = bpy.data.objects.new(name, me)
    ob["pieces"] = []
    bpy.context.scene.collection.objects.link(ob)
    punch(me)
    outline(me)
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(material())
    me.update()
    return ob


def render(ob, path, view=(1, -1, 0.6), zoom=1.0, ortho=None):
    """A Workbench picture of one model (vertex colours, backface culling) to check its look."""
    sc = bpy.context.scene
    for o in sc.objects:
        o.hide_render = o is not ob and o.type == "MESH"
    ob.data.color_attributes.active_color = ob.data.color_attributes["Col"]
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "VERTEX"
    sc.display.shading.show_backface_culling = True
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    cam = bpy.data.objects.get("Cam") or bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    if cam.name not in sc.objects:
        sc.collection.objects.link(cam)
    sc.camera = cam
    lo = V([min((ob.matrix_world @ V(c))[i] for c in ob.bound_box) for i in range(3)])
    hi = V([max((ob.matrix_world @ V(c))[i] for c in ob.bound_box) for i in range(3)])
    mid, size = (lo + hi) / 2, (hi - lo).length
    d = V(view).normalized()
    cam.location = mid + d * size * 1.6 / zoom
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO" if ortho else "PERSP"
    if ortho:  # (scale, centre): a straight side view of one region
        cam.data.ortho_scale = ortho[0]
        cam.location = V(ortho[1]) + d * 50
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs = {name: build(name) for name in MODELS}
    for name, ob in obs.items():
        print(name, sum(len(p.vertices) - 2 for p in ob.data.polygons), "tris")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "disasters.blend"))
    ex = {"__name__": "export", "NAMES": []}
    exec(open(os.path.join(REPO, "assets", "weapons", "export.py")).read(), ex)
    ex["OUT"] = os.path.join(REPO, "src", "client", "DisasterMeshes")
    os.makedirs(ex["OUT"], exist_ok=True)
    for ob in obs.values():
        ex["export"](ob)
        path = os.path.join(ex["OUT"], ob.name + ".luau")  # export.py's header names the weapons' blend
        text = open(path, encoding="utf8").read().replace("assets/weapons/weapons.blend", "assets/disasters/disasters.py")
        open(path, "w", encoding="utf8", newline="\n").write(text)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv and argv[0] == "render":
        out = argv[1] if len(argv) > 1 else HERE
        views = {"NukeBomb": [(1, -1, 0.3)], "Meteor": [(1, -1, 0.6)], "TsunamiWave": [(0.35, -1, 0.25), (1, 0, 0.05)],
                 "Ufo": [(1, -1, 0.35)], "Volcano": [(1, -1, 0.5)], "Bolt": [(0.3, -1, 0.1)], "IceShards": [(1, -1, 0.4)],
                 "CloudPuff": [(1, -1, 0.3)], "Tombstone": [(1, -1, 0.3)]}
        for name, ob in obs.items():
            for i, view in enumerate(views[name]):
                render(ob, os.path.join(out, f"{name}{i}.png"), view, 1.0, (12, (0, 2.5, 1.8)) if view == (1, 0, 0.05) else None)


main()
