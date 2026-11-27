"""Slavic Captain's Shield, 90s comic style. Blender 5.3 (EEVEE, GPv3 Line Art, node-group compositor).

Run in Blender:  exec(open(p).read(), {"__file__": p}); build_all()      (p = path of this file)
Stage by stage: stage0(); m = materials(); planks(m); steel(m); boss(m); deco(m); fx(m); look()

Front faces -Y, up +Z, centred at the origin, metres. Diameter 0.79 m over the rim teeth,
0.10 m deep from the boss face to the back of the grip plates.
Planks and grip are built on +X with a Mirror modifier; round parts are lathed around Y.
Reuses the toon node helpers, world, line art and compositor of ../visor/build_visor.py.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
_ns = {"__file__": os.path.join(HERE, "..", "visor", "build_visor.py")}
exec(open(_ns["__file__"]).read(), _ns)
srgb, kill, _ramp, _math, _mix = _ns["srgb"], _ns["kill"], _ns["_ramp"], _ns["_math"], _ns["_mix"]
_toon_base, _hatch, _emit_out, _new_mat, mat_flat_toon = (_ns[k] for k in ("_toon_base", "_hatch", "_emit_out", "_new_mat", "mat_flat_toon"))

COLS = ["01_Wood_Planks", "02_Steel_Bands", "03_Central_Boss", "04_Slavic_Deco", "05_Energy_FX",
        "06_Studio_Lights_Camera"]
_ns["COLS"] = ["", "", "", COLS[5], COLS[5]]   # visor's line_art() / _cam() link into these slots

# ---------------------------------------------------------------- dimensions
R = 0.37          # dome reference radius
R_WOOD = 0.36     # planks end under the rim
DOME = 0.035      # front bulge at the centre
WOOD_T = 0.028
BAND_A = [math.radians(90 + 60 * k) for k in range(6)]      # radial straps (top, bottom and 4 diagonals)
SECT_A = [math.radians(60 * k) for k in range(6)]           # wood sectors between straps
RIM = [(0.326, 0.004), (0.326, -0.016), (0.338, -0.024), (0.368, -0.024), (0.382, -0.014),
       (0.382, 0.030), (0.374, 0.040), (0.344, 0.040), (0.344, 0.030)]          # (r, y), closed
BOSS = [(0, -0.090), (0.035, -0.088), (0.065, -0.082), (0.088, -0.072), (0.094, -0.064), (0.110, -0.062),
        (0.126, -0.054), (0.132, -0.044), (0.132, -0.020), (0, -0.020)]        # (r, y), pole to pole


def fy(r):
    """y of the wood front at radius r (front is -Y)."""
    r = min(r, R)
    return -DOME * (1 - (r / R) ** 2)


def P(r, a, d=0.0):
    """Point on the wood front at polar (r, a) in XZ, d metres in front of it."""
    return Vector((r * math.cos(a), fy(r) - d, r * math.sin(a)))


def yb(r):
    return fy(r) + WOOD_T


# ---------------------------------------------------------------- mesh helpers
def mk(name, bm, col, mats, mirror=False, bevel=0.0, recalc=True):
    kill(name)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.shade_flat()
    o = bpy.data.objects.new(name, me)
    bpy.data.collections[col].objects.link(o)
    for m in mats:
        me.materials.append(m)
    if mirror:
        md = o.modifiers.new("Mirror", 'MIRROR')
        md.use_axis = (True, False, False)
        md.use_clip = True
        md.use_mirror_merge = True
    if bevel:
        md = o.modifiers.new("Bevel", 'BEVEL')
        md.width = bevel
        md.segments = 1
        md.limit_method = 'ANGLE'
        md.angle_limit = math.radians(35)
    return o


def face_front(bm, f):
    """Flat decals and FX ribbons: normal towards the camera (-Y)."""
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()


def quad_strip(bm, rings, closed_ring=True, cap0=False, cap1=False, mi=0):
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for k in range(len(vs) - 1):
        a, b = vs[k], vs[k + 1]
        for i in range(n if closed_ring else n - 1):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i])).material_index = mi
    for flag, ring in ((cap0, vs[0]), (cap1, vs[-1])):
        if flag:
            bm.faces.new(ring).material_index = mi
    return vs


def lathe_y(bm, profile, segs, closed=False, rmod=None, mi=0):
    """Revolve (r, y) around Y. r == 0 makes a pole. rmod(k, j, r) -> r lets a ring be serrated."""
    rings = []
    for k, (r, y) in enumerate(profile):
        if r < 1e-9:
            rings.append([bm.verts.new((0, y, 0))] * segs)
            continue
        ring = []
        for j in range(segs):
            t = 2 * math.pi * j / segs
            rr = rmod(k, j, r) if rmod else r
            ring.append(bm.verts.new((rr * math.cos(t), y, rr * math.sin(t))))
        rings.append(ring)
    for k in range(len(rings) if closed else len(rings) - 1):
        a, b = rings[k], rings[(k + 1) % len(rings)]
        for i in range(segs):
            j = (i + 1) % segs
            f = []
            for v in (a[i], a[j], b[j], b[i]):
                if v not in f:
                    f.append(v)
            if len(f) >= 3:
                bm.faces.new(f).material_index = mi
    return rings


def rivet(bm, c, n=Vector((0, -1, 0)), r1=0.011, r2=0.006, h=0.009, segs=6, mi=0):
    """Chunky faceted rivet: a frustum standing on c along n."""
    rot = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    m = Matrix.Translation(c + n * (h / 2)) @ rot
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=h, matrix=m)
    for f in {f for v in g["verts"] for f in v.link_faces}:
        f.material_index = mi


def prism(bm, poly, y0, y1):
    """Closed prism from an XZ polygon between y0 and y1 (boolean cutters)."""
    quad_strip(bm, [[Vector((x, y0, z)) for x, z in poly], [Vector((x, y1, z)) for x, z in poly]],
               cap0=True, cap1=True)


def petal(phi, s0, L, W, n=12):
    """Lens-shaped rosette petal along angle phi: XZ outline."""
    ax, pe = Vector((math.cos(phi), math.sin(phi))), Vector((-math.sin(phi), math.cos(phi)))
    side = [(s0 + (L - s0) * t / n, W * math.sin(math.pi * t / n) ** 0.75) for t in range(n + 1)]
    pts = [ax * s + pe * w for s, w in side] + [ax * s - pe * w for s, w in reversed(side[1:-1])]
    return [(p.x, p.y) for p in pts]


# ================================================================ stage 0
def stage0():
    print("Blender", bpy.app.version_string)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    sc = bpy.context.scene
    for n in COLS + ["_Boss_Cutters"]:
        sc.collection.children.link(bpy.data.collections.new(n))
    try:
        sc.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        sc.render.engine = 'BLENDER_EEVEE'
    sc.eevee.taa_render_samples = 32
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    sc.unit_settings.system = 'METRIC'
    _ns["world_setup"]()
    cameras()


def cameras():
    _cam = _ns["_cam"]
    _cam("Cam_Front_Ortho", (0, -2.0, 0), (0, 0, 0), ortho=1.3)
    _cam("Cam_Side_Ortho", (-2.0, 0, 0), (0, 0, 0), ortho=1.3)
    hero = _cam("Cam_Hero_3_4", (-1.2, -1.9, 0.62), (0.0, 0.0, -0.01), lens=55)
    for c in ("Cam_Front_Ortho", "Cam_Side_Ortho", "Cam_Hero_3_4"):
        bpy.data.objects[c].data.clip_end = 20
    bpy.context.scene.camera = hero


# ================================================================ planks + grip (01)
def planks(m):
    rng = random.Random(7)
    bm = bmesh.new()
    NX, NZ = 4, 30
    for x0, x1 in ((0.002, 0.118), (0.122, 0.238), (0.242, R_WOOD - 0.001)):
        jit = rng.uniform(-0.0025, 0.0025)                # boards sit unevenly
        F, B = [], []
        for i in range(NX + 1):
            x = x0 + (x1 - x0) * i / NX
            zm = math.sqrt(max(R_WOOD ** 2 - x * x, 1e-6))
            fr, br = [], []
            for j in range(NZ + 1):
                z = zm * (2 * j / NZ - 1)
                xx = x + (rng.uniform(-0.0018, 0.0018) if i in (0, NX) else 0)   # chipped board edges
                y = fy(math.hypot(x, z)) + jit
                fr.append(bm.verts.new((xx, y, z)))
                br.append(bm.verts.new((xx, y + WOOD_T, z)))
            F.append(fr)
            B.append(br)
        for i in range(NX):
            for j in range(NZ):
                bm.faces.new((F[i][j], F[i + 1][j], F[i + 1][j + 1], F[i][j + 1]))
                bm.faces.new((B[i][j + 1], B[i + 1][j + 1], B[i + 1][j], B[i][j]))
        for i in (0, NX):
            for j in range(NZ):
                bm.faces.new((F[i][j], F[i][j + 1], B[i][j + 1], B[i][j]))
        for j in (0, NZ):
            for i in range(NX):
                bm.faces.new((F[i][j], F[i + 1][j], B[i + 1][j], B[i][j]))
    mk("Oak_Planks", bm, COLS[0], [m["wood"]], mirror=True)
    grip(m)


def sweep(bm, path, z, ht, hz, mi):
    """Rectangular bar along an XY path at height z; open at x=0 (mirror seam), capped at the far end."""
    rings = []
    for i, p in enumerate(path):
        d = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        d = Vector((d.x, d.y, 0)).normalized()
        n = Vector((-d.y, d.x, 0))
        c = Vector((p.x, p.y, z))
        rings.append([c + n * (sx * ht) + Vector((0, 0, sz * hz)) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    quad_strip(bm, rings, cap0=True, mi=mi)


def grip(m):
    bm = bmesh.new()
    V = lambda x, y: Vector((x, y, 0))
    # steel hand bar (low) and leather forearm strap (high), each from a riveted plate to the x=0 seam
    sweep(bm, [V(0.118, -0.006), V(0.115, 0.025), V(0.100, 0.042), V(0.060, 0.047), V(0.0, 0.047)], -0.07, 0.010, 0.013, 0)
    sweep(bm, [V(0.118, -0.004), V(0.116, 0.040), V(0.100, 0.064), V(0.050, 0.071), V(0.0, 0.071)], 0.09, 0.004, 0.028, 1)
    for z, h in ((-0.07, 0.035), (0.09, 0.040)):
        y = yb(math.hypot(0.118, z)) + 0.004
        g = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0.118, y, z)) @ Matrix.Diagonal((0.05, 0.008, h * 2, 1)))
        for zz in (z - h * 0.6, z + h * 0.6):
            rivet(bm, Vector((0.118, y + 0.004, zz)), Vector((0, 1, 0)), 0.007, 0.004, 0.006)
    mk("Grip_Steel_Leather", bm, COLS[0], [m["steel"], m["leather"]], mirror=True, bevel=0.0015)


# ================================================================ rim, straps, rivets (02)
def steel(m):
    rng = random.Random(11)
    bm = bmesh.new()
    segs = 144
    lathe_y(bm, RIM, segs, closed=True,
            rmod=lambda k, j, r: r + (0.012 if r > 0.38 and j % 4 < 2 else 0.0))   # square teeth
    nicks = [rng.uniform(0, 2 * math.pi) for _ in range(7)]
    for v in bm.verts:                                     # battle dents in the rim face
        if v.co.y < -0.02:
            a = math.atan2(v.co.z, v.co.x)
            if any(abs((a - n + math.pi) % (2 * math.pi) - math.pi) < 0.03 for n in nicks):
                v.co.y += 0.007
    for k in range(24):
        a = 2 * math.pi * k / 24
        rivet(bm, Vector((0.353 * math.cos(a), -0.024, 0.353 * math.sin(a))), r1=0.012, r2=0.007, h=0.010)
    mk("Steel_Outer_Rim", bm, COLS[1], [m["steel"]], bevel=0.0015)

    bm = bmesh.new()
    for a in BAND_A:
        t = Vector((-math.sin(a), 0, math.cos(a)))
        notch = {rng.randrange(2, 12): rng.choice((-1, 1)) for _ in range(2)}
        rings = []
        for i in range(14):
            r = 0.11 + (0.345 - 0.11) * i / 13
            hw = 0.022 + 0.008 * r / R                     # flares towards the rim
            sec = [(-hw, -0.002), (-hw + 0.005, 0.012), (hw - 0.005, 0.012), (hw, -0.002)]
            if i in notch:                                 # hammer nick bitten out of one top edge
                s = notch[i]
                sec = [(o + (0.009 if s < 0 and k == 1 else -0.009 if s > 0 and k == 2 else 0), d)
                       for k, (o, d) in enumerate(sec)]
            rings.append([P(r, a, d) + t * o for o, d in sec])
        quad_strip(bm, rings, cap0=True, cap1=True)
        for r in (0.175, 0.255, 0.315):
            rivet(bm, P(r, a, 0.012), r1=0.010, r2=0.006, h=0.008)
    mk("Steel_Radial_Straps", bm, COLS[1], [m["steel"]], bevel=0.0012)


# ================================================================ boss + rosette (03)
def boss(m):
    bm = bmesh.new()
    lathe_y(bm, BOSS, 64)
    o = mk("Iron_Boss", bm, COLS[2], [m["steel"]])
    # engraving cutters: six rosette petals and the ring round them
    cut_col = bpy.data.collections["_Boss_Cutters"]
    bm = bmesh.new()
    for k in range(6):
        prism(bm, petal(math.radians(90 + 60 * k), 0.007, 0.062, 0.014), -0.12, -0.078)
    circ = lambda r: [Vector((r * math.cos(2 * math.pi * i / 64), y, r * math.sin(2 * math.pi * i / 64))) for i in range(64)]
    rings = []
    for r, y in ((0.078, -0.12), (0.078, -0.071), (0.070, -0.071), (0.070, -0.12)):
        rings.append([Vector((p.x, y, p.z)) for p in circ(r)])
    quad_strip(bm, rings + [rings[0]])
    c = mk("Cutter_Rosette", bm, "_Boss_Cutters", [])
    c.display_type = 'WIRE'
    c.hide_render = True
    c.lineart.usage = 'EXCLUDE'
    md = o.modifiers.new("Engrave", 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.operand_type = 'COLLECTION'
    md.collection = cut_col
    try:
        md.solver = 'EXACT'
    except TypeError:
        pass
    bpy.context.view_layer.layer_collection.children["_Boss_Cutters"].hide_viewport = True

    # glowing inserts in the engraving, round studs on the flange, a hex knob in the middle
    bm = bmesh.new()
    for k in range(6):
        phi = math.radians(90 + 60 * k)
        for W, y, mi in ((0.011, -0.0790, 0), (0.0045, -0.0797, 1)):
            f = bm.faces.new([bm.verts.new((x, y, z)) for x, z in petal(phi, 0.010, 0.058, W)])
            f.material_index = mi
    ring = quad_strip(bm, [[Vector((p.x, -0.0722, p.z)) for p in circ(0.0765)],
                           [Vector((p.x, -0.0722, p.z)) for p in circ(0.0715)]])
    for f in bm.faces:
        face_front(bm, f)
    mk("Rosette_Glow", bm, COLS[2], [m["cyan"], m["yellow"]], recalc=False)

    bm = bmesh.new()
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.0068,
                                   matrix=Matrix.Translation((0.118 * math.cos(a), -0.062, 0.118 * math.sin(a))) @ Matrix.Diagonal((1, 0.6, 1, 1)))
    rivet(bm, Vector((0, -0.089, 0)), r1=0.014, r2=0.008, h=0.010)
    mk("Boss_Studs", bm, COLS[2], [m["steel"]])


# ================================================================ folk paint + carving (04)
def deco(m):
    bm = bmesh.new()
    lay = bm.edges.layers.bool.new("freestyle_edge")

    def poly(pts, d, mi):
        f = bm.faces.new([bm.verts.new(P(r, a, d)) for r, a in pts])
        f.material_index = mi
        face_front(bm, f)

    def diamond(rc, ac, hr, ht, d, mi):
        da = ht / rc
        poly([(rc + hr, ac), (rc, ac + da), (rc - hr, ac), (rc, ac - da)], d, mi)

    RED, WHITE, INK = 0, 1, 2
    for ac in SECT_A:
        # lozenge "sown field": red, white, red, with four white seeds at the tips
        diamond(0.205, ac, 0.046, 0.038, 0.003, RED)
        diamond(0.205, ac, 0.031, 0.025, 0.005, WHITE)
        diamond(0.205, ac, 0.014, 0.011, 0.007, RED)
        for dr, dt in ((0.058, 0), (-0.058, 0), (0, 0.050), (0, -0.050)):
            rc = 0.205 + dr
            diamond(rc, ac + dt / 0.205, 0.008, 0.006, 0.003, WHITE)
        # wolf-teeth border: red teeth out, white teeth in
        span, n, r0, r1 = math.radians(21), 8, 0.270, 0.306
        da = 2 * span / n
        for i in range(n):
            a0 = ac - span + i * da
            poly([(r0, a0), (r0, a0 + da), (r1, a0 + da / 2)], 0.003, RED)
            if i < n - 1:
                poly([(r1, a0 + da / 2), (r1, a0 + 1.5 * da), (r0, a0 + da)], 0.003, WHITE)
        # carved double groove under the rim, inked
        for rr in (0.313, 0.319):
            pts = [(rr, ac - span + 2 * span * i / 16) for i in range(17)]
            quad_strip(bm, [[P(rr - 0.0012, a, 0.0008), P(rr + 0.0012, a, 0.0008)] for _, a in pts],
                       closed_ring=False, mi=INK)
    for f in bm.faces:
        face_front(bm, f)
    for e in bm.edges:
        e[lay] = True
    mk("Folk_Paint_And_Carving", bm, COLS[3], [m["red"], m["white"], m["ink"]], recalc=False)


# ================================================================ energy (05)
def fx(m):
    rng = random.Random(23)
    bm = bmesh.new()
    CY, YE, KR = 0, 1, 2

    def ribbon(pts, w, mi, dy=0.0):
        n = len(pts) - 1
        rings = []
        for i, p in enumerate(pts):
            d = pts[min(i + 1, n)] - pts[max(i - 1, 0)]
            side = Vector((-d.z, 0, d.x)).normalized()
            ww = w * (1 - 0.75 * i / n) * 0.5
            q = p + Vector((0, dy, 0))
            rings.append([q - side * ww, q + side * ww])
        quad_strip(bm, rings, closed_ring=False, mi=mi)

    def jag(a, b, n, amp):
        side = Vector((-(b - a).z, 0, (b - a).x)).normalized()
        L = (b - a).length
        return [a.lerp(b, i / n) + (side * rng.uniform(-amp, amp) * L if 0 < i < n else Vector()) for i in range(n + 1)]

    def bolt(pts, w):
        ribbon(pts, w, CY)
        ribbon(pts, w * 0.4, YE, -0.002)

    def krackle(c, n, size):
        for _ in range(n):
            off = Vector((rng.uniform(-1, 1), 0, rng.uniform(-1, 1))) * size * 2.2
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size * rng.uniform(0.35, 1.0),
                                       matrix=Matrix.Translation(c + off + Vector((0, -0.004, 0))))

    # rosette arcs jumping over the flange onto the wood
    for k in range(6):
        a = math.radians(60 * k + rng.uniform(-10, 10))
        s = Vector((0.092 * math.cos(a), -0.070, 0.092 * math.sin(a)))
        e = P(0.19, a + rng.uniform(-0.25, 0.25), 0.022)
        pts = jag(s, e, 6, 0.18)
        bolt(pts, 0.026)
        br = pts[3]
        bolt(jag(br, P(0.16, a + rng.choice((-0.5, 0.5)), 0.018), 3, 0.25), 0.015)
        krackle(e, 4, 0.006)
    # crackle chasing round the rim teeth
    for k in range(5):
        a0 = math.radians(72 * k + 20 + rng.uniform(-8, 8))
        a1 = a0 + math.radians(rng.uniform(22, 34))
        pts = []
        for i in range(9):
            a = a0 + (a1 - a0) * i / 8
            r = 0.405 + rng.uniform(-0.012, 0.014) * (0 < i < 8)
            pts.append(Vector((r * math.cos(a), -0.032, r * math.sin(a))))
        bolt(pts, 0.024)
        krackle(pts[-1] * 1.03, 5, 0.007)
    # loose sparks flicking off the rim
    for k in range(12):
        a = 2 * math.pi * k / 12 + rng.uniform(-0.2, 0.2)
        s = Vector((0.40 * math.cos(a), -0.03, 0.40 * math.sin(a)))
        bolt(jag(s, s * rng.uniform(1.10, 1.18), 3, 0.35), 0.013)
    for f in bm.faces:                     # icosphere faces are the only triangles
        if len(f.verts) == 3:
            f.material_index = KR
        else:
            face_front(bm, f)
    o = mk("Energy_Bolts_Krackle", bm, COLS[4], [m["cyan"], m["yellow"], m["krackle"]], recalc=False)
    o.lineart.usage = 'INCLUDE'


# ================================================================ look (materials, lights, ink)
def mat_wood():
    m, nt = _new_mat("M_Oak_Toon")
    light = _toon_base(nt)
    lum = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(light, lum.inputs[0])
    L = lum.outputs[0]
    ramp = _ramp(nt, [(0.0, srgb("#000000")), (0.18, srgb("#261A10")), (0.45, srgb("#3D2B1F")), (0.85, srgb("#5E4430"))])
    nt.links.new(L, ramp.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = 'BANDS'
    wv.bands_direction = 'X'
    wv.inputs["Scale"].default_value = 9.0
    wv.inputs["Distortion"].default_value = 9.0
    wv.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    grain = _math(nt, 'GREATER_THAN', wv.outputs["Fac"], 0.84)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 4.0
    nz.inputs["Detail"].default_value = 9.0
    nz.inputs["Roughness"].default_value = 0.62
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    crack = _math(nt, 'LESS_THAN', _math(nt, 'ABSOLUTE', _math(nt, 'SUBTRACT', nz.outputs["Fac"], 0.5)), 0.007)
    band = _math(nt, 'MULTIPLY', _math(nt, 'GREATER_THAN', L, 0.16), _math(nt, 'LESS_THAN', L, 0.32))
    ink = _math(nt, 'MAXIMUM', _math(nt, 'MAXIMUM', grain, crack), _math(nt, 'MULTIPLY', band, _hatch(nt)))
    _emit_out(nt, _mix(nt, ink, ramp.outputs[0], srgb("#000000")))
    return m


def mat_steel():
    m, nt = _new_mat("M_Steel_Toon")
    light = _toon_base(nt)
    lum = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(light, lum.inputs[0])
    L = lum.outputs[0]
    ramp = _ramp(nt, [(0.0, srgb("#000000")), (0.20, srgb("#2A2E3D")), (0.45, srgb("#3D4454")), (0.88, srgb("#8C99A8"))])
    nt.links.new(L, ramp.inputs[0])
    col = ramp.outputs[0]
    # worn, cold-metal scuffs in the lit areas
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 22.0
    nz.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    wear = _math(nt, 'MULTIPLY', _math(nt, 'GREATER_THAN', nz.outputs["Fac"], 0.64), _math(nt, 'GREATER_THAN', L, 0.20))
    col = _mix(nt, wear, col, srgb("#8C99A8"))
    band = _math(nt, 'MULTIPLY', _math(nt, 'GREATER_THAN', L, 0.18), _math(nt, 'LESS_THAN', L, 0.32))
    col = _mix(nt, _math(nt, 'MULTIPLY', band, _hatch(nt)), col, srgb("#000000"))
    # hard white glints
    gl = nt.nodes.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.18
    gs = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(gl.outputs[0], gs.inputs[0])
    gbw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(gs.outputs["Color"], gbw.inputs[0])
    sramp = _ramp(nt, [(0.0, (0, 0, 0, 1)), (0.7, (1, 1, 1, 1))])
    nt.links.new(gbw.outputs[0], sramp.inputs[0])
    col = _mix(nt, 1.0, col, sramp.outputs[0], 'ADD')
    # cyan bounce off the energy, cel-stepped, rims only
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(light, sep.inputs[0])
    cy = _math(nt, 'GREATER_THAN', _math(nt, 'SUBTRACT', sep.outputs[2], sep.outputs[0]), 0.10)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    cy = _math(nt, 'MULTIPLY', cy, _math(nt, 'GREATER_THAN', lw.outputs["Facing"], 0.55))
    col = _mix(nt, cy, col, srgb("#00E5FF"))
    _emit_out(nt, col)
    return m


def mat_glow(name, hex_, strength):
    m, nt = _new_mat(name)
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = srgb(hex_)
    _emit_out(nt, rgb.outputs[0], strength)
    return m


def mat_krackle():
    m, nt = _new_mat("M_Kirby_Krackle")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    edge = _math(nt, 'GREATER_THAN', lw.outputs["Facing"], 0.62)
    _emit_out(nt, _mix(nt, edge, srgb("#000000"), srgb("#00E5FF")), 3.0)
    return m


def materials():
    return {
        "wood": mat_wood(),
        "steel": mat_steel(),
        "leather": mat_flat_toon("M_Leather", "#1E120A", "#4A2C17", "#6B4226"),
        "red": mat_flat_toon("M_Folk_Red", "#5A0003", "#B30006", "#E0262B"),
        "white": mat_flat_toon("M_Folk_White", "#6E6A62", "#E5E1D8", "#FFFFFF"),
        "ink": mat_flat_toon("M_Ink", "#000000", "#000000"),
        "cyan": mat_glow("M_Energy_Cyan", "#00E5FF", 4.0),
        "yellow": mat_glow("M_Energy_Yellow", "#FFEB3B", 4.0),
        "krackle": mat_krackle(),
    }


def lights():
    col = bpy.data.collections[COLS[5]]

    def L(name, typ, loc, energy, color, **kw):
        kill(name)
        ld = bpy.data.lights.get(name)
        if ld and ld.type != typ:
            bpy.data.lights.remove(ld)
            ld = None
        ld = ld or bpy.data.lights.new(name, typ)
        ld.energy = energy
        ld.color = srgb(color)[:3]
        for k, v in kw.items():
            setattr(ld, k, v)
        o = bpy.data.objects.new(name, ld)
        col.objects.link(o)
        o.location = loc
        o.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        return o
    L("Key_Sun_Top", 'SUN', (-0.4, -0.7, 1.6), 3.3, "#FFFFFF", angle=math.radians(0.3), specular_factor=0.0)
    L("Fill_Side", 'SUN', (1.0, -0.4, 0.2), 0.9, "#FFFFFF", angle=math.radians(0.3), specular_factor=0.0)
    L("Rim_Kicker", 'AREA', (1.3, 0.5, 0.35), 260.0, "#E8F4FF", size=0.6, specular_factor=0.0)
    L("Spec_Strip", 'AREA', (-0.55, -1.2, 0.3), 40.0, "#FFFFFF", shape='RECTANGLE', size=0.02, size_y=2.5,
      diffuse_factor=0.0, use_shadow=False)
    L("Energy_Bounce", 'POINT', (0.0, -0.22, 0.0), 6.0, "#00E5FF", shadow_soft_size=0.05, specular_factor=0.0)


def look(m=None):
    lights()
    gp = _ns["line_art"]()
    gp.modifiers["LA_Silhouette"].radius = 0.0032
    gp.modifiers["LA_Detail"].radius = 0.0013
    _ns["compositor"]()


def build_all():
    stage0()
    m = materials()
    planks(m)
    steel(m)
    boss(m)
    deco(m)
    fx(m)
    look()
    return m


def render(cam, name, res=(1600, 1200)):
    _ns["render"](cam, os.path.join(HERE, name), res)


def render_qa():
    for cam, name in (("Cam_Front_Ortho", "qa_front.png"), ("Cam_Side_Ortho", "qa_side.png"), ("Cam_Hero_3_4", "qa_hero.png")):
        render(cam, name)
