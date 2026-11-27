"""Ruby-quartz visor, 90s comic style. Blender 5.3 (EEVEE, GPv3 Line Art, node-group compositor).

Run in Blender:  exec(open(r"<this file>").read()); build_all()
Or stage by stage: stage0(); stage1(); ... (each stage rebuilds its own objects).

Front faces -Y, up +Z, centred at the origin, metres.
Shell and lens are generated across the centre then bisected at x=0 and mirrored;
arms, pods, dials and trim are built on +X and mirrored.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- dimensions
T = 0.018          # front shell thickness
B_FRONT = 0.035    # half height of the front shell at the centre
B_END = 0.029      # half height at the seam
R_CORNER = 0.012   # 2D corner radius of the front shell outline
NOTCH_D, NOTCH_W = 0.021, 0.027   # nose cut: depth, half width
SLIT_B, SLIT_Z = 0.0068, 0.004    # slit half height, centre height
LENS_D = 0.0095    # lens depth behind the front face
ARM_T, ARM_H0, ARM_H1 = 0.0062, 0.0215, 0.0185   # arm half thickness, half height start/end
POD_C = Vector((0.0935, 0.050, 0.0))  # pod centre (+X side)
POD_TOE = math.radians(7)            # pod turned so its front edge tucks in
ARM_STEPS, ARM_SEGS = 28, 20   # arm sweep resolution
BULGE = 3.0        # vertical convexity of the front (offset = -BULGE*z^2)

# Top-view centreline (cubic Bezier, +X half): front centre -> pod
BEZ = [Vector((0, -0.081)), Vector((0.058, -0.081)), Vector((0.0895, -0.050)), Vector((0.0895, 0.051))]

COLS = ["01_Visor_Front_Shell", "02_Ruby_Lens_And_Interior", "03_Side_Pods_And_Dials",
        "04_Line_Art_And_FX", "05_Studio_Lights_Camera"]


def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


# ---------------------------------------------------------------- path
def _bez(t):
    p0, p1, p2, p3 = BEZ
    m = 1 - t
    return p0 * m ** 3 + p1 * 3 * m * m * t + p2 * 3 * m * t * t + p3 * t ** 3


_TAB = []
def _table():
    if _TAB:
        return _TAB
    pts = [_bez(i / 2000) for i in range(2001)]
    s = 0.0
    for i, p in enumerate(pts):
        if i:
            s += (p - pts[i - 1]).length
        _TAB.append((s, p))
    return _TAB


def path_len():
    return _table()[-1][0]


def path(u):
    """(point, outward normal) in XY at arc length u; negative u mirrors."""
    sgn = -1 if u < 0 else 1
    u = abs(u)
    tab = _table()
    L = tab[-1][0]
    if u >= L:   # extrapolate straight
        p, q = tab[-1][1], tab[-2][1]
        t = (p - q).normalized()
        pt = p + t * (u - L)
    else:
        lo, hi = 0, len(tab) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if tab[mid][0] < u: lo = mid
            else: hi = mid
        (s0, a), (s1, b) = tab[lo], tab[hi]
        f = (u - s0) / max(s1 - s0, 1e-12)
        pt = a.lerp(b, f)
        t = (b - a).normalized()
    n = Vector((t.y, -t.x))
    if u < 1e-9:   # exact centre: keeps the x=0 seam vertices on the mirror plane
        return Vector((0.0, pt.y)), Vector((0.0, -1.0))
    return Vector((pt.x * sgn, pt.y)), Vector((n.x * sgn, n.y))


def wrap(u, z, d):
    """2D (u along the band, z up) + depth d behind the outer face -> 3D."""
    c, n = path(u)
    off = T / 2 - d - BULGE * z * z
    return Vector((c.x + n.x * off, c.y + n.y * off, z))


def seam_u():
    # where the band starts turning back: y of the centreline reaches -0.042
    for s, p in _table():
        if p.y > -0.042:
            return s
    return path_len()


# ---------------------------------------------------------------- 2D outlines
N1, N2 = 26, 9   # points per quadrant: along the straight, around the corner


def rrect(A, B, r, cz=0.0):
    """Rounded rect outline, CCW from top centre, 4*(N1+N2) points, correspondence-stable."""
    r = min(r, B, A)
    q = []
    for i in range(N1):                       # top straight, x 0 -> A-r
        q.append(((A - r) * i / N1, B))
    for i in range(N2):                       # corner arc, 90 -> 0 deg
        a = math.pi / 2 * (1 - i / N2)
        q.append((A - r + r * math.cos(a), B - r + r * math.sin(a)))
    right = q + [(x, -y) for x, y in reversed(q)]      # top centre -> bottom centre
    left = [(-x, y) for x, y in reversed(right)]       # bottom centre -> top centre
    full = right + left[1:-1]                          # drop the duplicated centre points
    return [(x, y + cz) for x, y in full]


def plate_outline(ext=1.0):
    U = seam_u()
    pts = rrect(U, B_FRONT, R_CORNER)
    out = []
    for x, y in pts:
        f = abs(x) / U
        y *= 1 - (1 - B_END / B_FRONT) * f * f          # taper towards the seam
        if y < 0 and abs(x) < NOTCH_W:                   # nose cut
            y += NOTCH_D * 0.5 * (1 + math.cos(math.pi * x / NOTCH_W))
        out.append((x, y))
    return out


def pill(e=0.0):
    U = seam_u()
    A = U - 0.0165
    return rrect(A + e, SLIT_B + e, SLIT_B + e, SLIT_Z)


def lerp2(a, b, w):
    return [(p[0] + (q[0] - p[0]) * w, p[1] + (q[1] - p[1]) * w) for p, q in zip(a, b)]


# ---------------------------------------------------------------- mesh helpers
def coll(name):
    return bpy.data.collections[name]


def kill(name):
    o = bpy.data.objects.get(name)
    if o:
        me = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)


def new_obj(name, bm, col, mats=(), mirror=False, subsurf=2, bisect=False):
    kill(name)
    if bisect:
        # every ring has exact x=0 vertices, so dropping the -X half leaves a clean seam
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.x < -1e-7], context='VERTS')
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    o = bpy.data.objects.new(name, me)
    coll(col).objects.link(o)
    for m in mats:
        me.materials.append(m)
    if mirror:
        md = o.modifiers.new("Mirror", 'MIRROR')
        md.use_axis = (True, False, False)
        md.use_clip = True
        md.use_mirror_merge = True
        md.merge_threshold = 1e-5
    if subsurf:
        md = o.modifiers.new("Subsurf", 'SUBSURF')
        md.levels = subsurf
        md.render_levels = subsurf
    return o


def loft(rings, closed=True):
    """rings: list of lists of 3D points (same count). Returns bmesh, all quads."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    nr = len(rings)
    for k in range(nr if closed else nr - 1):
        a, b = vs[k], vs[(k + 1) % nr]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return bm, vs


def ring3(pts2, d):
    return [wrap(x, z, d) for x, z in pts2]


def mark_ring(bm, ring_verts):
    """Freestyle edge mark on the edges of a vertex ring (Line Art edge marks)."""
    lay = bm.edges.layers.bool.get("freestyle_edge") or bm.edges.layers.bool.new("freestyle_edge")
    s = set(ring_verts)
    for e in bm.edges:
        if e.verts[0] in s and e.verts[1] in s:
            e[lay] = True


def cap_strip(bm, ring):
    """Close an rrect ring with quads bridging top to bottom (symmetric, no n-gon)."""
    M = N1 + N2
    def top(k, side): return ring[0 if k == 0 else (k if side else 4 * M - 2 - k)]
    def bot(k, side): return ring[2 * M - 1 if k == 0 else (2 * M - 1 - k if side else 2 * M + k - 1)]
    for side in (True, False):
        for k in range(M - 1):
            bm.faces.new((top(k, side), top(k + 1, side), bot(k + 1, side), bot(k, side)))


def lathe(profile, segs=48):
    """profile: (r, a) pairs; axis = local X (a), theta 90 deg = +Z. r==0 points become poles."""
    bm = bmesh.new()
    rings = []
    for r, a in profile:
        if r < 1e-9:
            rings.append([bm.verts.new((a, 0, 0))] * segs)
        else:
            rings.append([bm.verts.new((a, r * math.cos(2 * math.pi * i / segs + math.pi / 2),
                                        r * math.sin(2 * math.pi * i / segs + math.pi / 2))) for i in range(segs)])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(segs):
            j = (i + 1) % segs
            f = [a[i], a[j], b[j], b[i]]
            uniq = []
            for v in f:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                bm.faces.new(uniq)
    return bm, rings


def pod_matrix():
    return Matrix.Translation(POD_C) @ Matrix.Rotation(POD_TOE, 4, 'Z')


# ================================================================ stage 0
def stage0():
    print("Blender", bpy.app.version_string)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights, bpy.data.grease_pencils):
        for d in list(blk):
            if d.users == 0:
                blk.remove(d)
    sc = bpy.context.scene
    for n in COLS:
        sc.collection.children.link(bpy.data.collections.new(n))
    try:
        sc.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        sc.render.engine = 'BLENDER_EEVEE'
    ee = sc.eevee
    ee.use_shadows = True
    ee.shadow_resolution_scale = 1.0
    ee.shadow_ray_count = 1
    ee.use_shadow_jitter_viewport = False
    ee.taa_render_samples = 32
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0
    sc.view_settings.gamma = 1
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 1.0
    sc.render.film_transparent = False
    world_setup()
    cameras()


def world_setup():
    w = bpy.data.worlds.get("Comic_Paper") or bpy.data.worlds.new("Comic_Paper")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    lp = nt.nodes.new("ShaderNodeLightPath")
    bg_cam = nt.nodes.new("ShaderNodeBackground")
    bg_cam.inputs["Color"].default_value = srgb("#F3E6C4")   # paper, seen by the camera only
    bg_lit = nt.nodes.new("ShaderNodeBackground")
    bg_lit.inputs["Color"].default_value = (0, 0, 0, 1)       # no ambient: keeps blacks pure
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(bg_lit.outputs[0], mix.inputs[1])
    nt.links.new(bg_cam.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def _cam(name, loc, target, ortho=None, lens=48):
    kill(name)
    cd = bpy.data.cameras.get(name) or bpy.data.cameras.new(name)
    o = bpy.data.objects.new(name, cd)
    coll(COLS[4]).objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cd.clip_start, cd.clip_end = 0.005, 10
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
    else:
        cd.type = 'PERSP'
        cd.lens = lens
    return o


def cameras():
    _cam("Cam_Front_Ortho", (0, -1.0, 0.0), (0, 0, 0), ortho=0.27)
    _cam("Cam_Side_Ortho", (1.0, 0.0, 0.0), (0, 0, 0), ortho=0.27)
    hero = _cam("Cam_Hero_3_4", (-0.29, -0.40, 0.11), (0.0, -0.005, -0.004), lens=48)
    _cam("Cam_Slit_Closeup", (-0.07, -0.20, 0.03), (0.0, -0.08, 0.004), lens=50)
    bpy.context.scene.camera = hero


# ================================================================ stage 1 (blockout)
def stage1():
    """U-shape blockout: front band, slit strip, pod discs. Replaced by stages 2-4."""
    U = seam_u()
    # front band as a single loft without the slit
    outl = plate_outline()
    rings = [ring3(outl, 0.0), ring3(outl, T)]
    bm, _ = loft(rings + [ring3(lerp2(outl, [(0, 0)] * len(outl), 1.0), T)], closed=False)
    o = new_obj("BLK_Front", bm, COLS[0], subsurf=0)
    # slit strip
    p = pill()
    bm, _ = loft([ring3(p, -0.001), ring3(lerp2(p, [(0, SLIT_Z)] * len(p), 0.999), -0.001)], closed=False)
    new_obj("BLK_Slit", bm, COLS[1], subsurf=0)
    # pods
    bm, _ = lathe([(0, 0.0125), (0.035, 0.0125), (0.035, -0.0135), (0, -0.0135)], 32)
    bm.transform(pod_matrix())
    new_obj("BLK_Pod", bm, COLS[2], mirror=True, subsurf=0)
    print("seam u", round(U, 4), "path len", round(path_len(), 4))


def clear_blockout():
    for n in ("BLK_Front", "BLK_Slit", "BLK_Pod"):
        kill(n)


# ================================================================ stage 2 (front shell)
def shell_rings():
    """Closed torus loft: slit tunnel -> bezel -> front face -> rim -> back face -> tunnel."""
    P = plate_outline()
    spec = [  # (shape, d)
        (pill(0.0), 0.0032),            # 0 tunnel top
        (pill(0.0022), 0.0007),         # 1 bezel chamfer
        (pill(0.0040), 0.0),            # 2 bezel outer edge   (edge mark)
        (pill(0.0058), 0.0),            # 3 support
        (lerp2(pill(0.0058), P, 0.45), 0.0),
        (lerp2(pill(0.0058), P, 0.88), 0.0),
        (lerp2(pill(0.0058), P, 0.96), 0.0),   # support before the rim
        (lerp2(pill(0.0058), P, 1.0), 0.0016),
        (lerp2(pill(0.0058), P, 1.035), T * 0.5),   # rim apex
        (lerp2(pill(0.0058), P, 1.0), T - 0.0016),
        (lerp2(pill(0.0058), P, 0.96), T),
        (lerp2(pill(0.0058), P, 0.6), T),
        (pill(0.0045), T),
        (pill(0.0018), T - 0.0006),     # back chamfer
        (pill(0.0), T - 0.0030),
        (pill(0.0), T * 0.5 + 0.0016),  # tunnel mid
    ]
    return [ring3(s, d) for s, d in spec]


def stage2(mats=None):
    clear_blockout()
    gold = (mats or {}).get("gold")
    bm, vs = loft(shell_rings(), closed=True)
    mark_ring(bm, vs[2])
    mark_ring(bm, vs[8])
    new_obj("Visor_Front_Shell", bm, COLS[0], mats=[gold] if gold else (), mirror=True, bisect=True)
    arms(mats)


def arm_section(h, n=None):
    n = n or ARM_SEGS
    """rounded-rect cross-section in (d_offset, z), CCW."""
    pts = []
    w, r = ARM_T, ARM_T * 0.9
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        # superellipse for a chunky, rounded box
        e = 0.55
        x = w * math.copysign(abs(c) ** e, c)
        y = h * math.copysign(abs(s) ** e, s)
        pts.append((x, y))
    return pts


def arms(mats=None):
    gold = (mats or {}).get("gold")
    U = seam_u()
    u0, u1 = U - 0.007, path_len() - 0.0
    steps = ARM_STEPS
    rings = []
    for k in range(steps + 1):
        f = k / steps
        u = u0 + (u1 - u0) * f
        h = ARM_H0 + (ARM_H1 - ARM_H0) * f
        sec = arm_section(h)
        rings.append([wrap(u, z, T / 2 + dx) for dx, z in sec])
    bm, vs = loft(rings, closed=False)
    new_obj("Visor_Side_Arms", bm, COLS[0], mats=[gold] if gold else (), mirror=True)


# ================================================================ stage 3 (pods)
POD_PROFILE = [  # (radius, axial) ; +axial = outward face
    (0.0, 0.0112), (0.0060, 0.0112), (0.0120, 0.0111), (0.0158, 0.0108), (0.0172, 0.0098),
    (0.0180, 0.0076), (0.0188, 0.0068), (0.0200, 0.0068), (0.0208, 0.0078),            # groove
    (0.0214, 0.0108), (0.0228, 0.0124), (0.0270, 0.0127), (0.0310, 0.0115), (0.0336, 0.0080),
    (0.0347, 0.0020), (0.0345, -0.0045), (0.0333, -0.0098), (0.0305, -0.0128), (0.0262, -0.0140),
    (0.0225, -0.0138), (0.0195, -0.0122), (0.0174, -0.0090), (0.0163, -0.0045), (0.0157, -0.0005),
    (0.0140, 0.0010), (0.0080, 0.0012), (0.0, 0.0012),
]


def stage3(mats=None):
    m = mats or {}
    bm, rings = lathe(POD_PROFILE)
    for idx in (6, 7):              # groove floor edges -> ink marks
        mark_ring(bm, rings[idx])
    bm.transform(pod_matrix())
    new_obj("Side_Pod", bm, COLS[2], mats=[m["gold"]] if m else (), mirror=True)
    # dial notch at 12 o'clock: a short dark slot sunk into the dial face
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.0030 + 0.0102, v.co.y * 0.0024, v.co.z * 0.0075 + 0.0128))
    bm.transform(pod_matrix())
    o = new_obj("Dial_Notch", bm, COLS[2], mats=[m["ink"]] if m else (), mirror=True, subsurf=0)
    o.data.shade_flat()


# ================================================================ stage 4 (lens + interior)
def stage4(mats=None):
    m = mats or {}
    # lens: pill rings shrinking to a strip, then capped, sits in the tunnel
    rings = []
    for e, d in ((-0.0004, LENS_D + 0.0016), (-0.0004, LENS_D), (-0.0018, LENS_D - 0.0003),
                 (-0.0045, LENS_D - 0.0006), (-0.0065, LENS_D - 0.0007)):
        rings.append(ring3(pill(e), d))
    bm, vs = loft(rings, closed=False)
    cap_strip(bm, vs[-1])
    cap_strip(bm, vs[0])
    new_obj("Ruby_Lens", bm, COLS[1], mats=[m["ruby"]] if m else (), mirror=True, bisect=True, subsurf=1)

    # inner red frame behind the lens (angular: no subsurf rounding beyond level 1)
    spec = [(pill(0.0012), T - 0.0025), (pill(0.0012), T + 0.0028), (pill(0.0035), T + 0.0042),
            (pill(0.0105), T + 0.0042), (pill(0.0120), T + 0.0020), (pill(0.0120), T - 0.0025)]
    bm, vs = loft([ring3(s, d) for s, d in spec], closed=True)
    new_obj("Inner_Red_Frame", bm, COLS[1], mats=[m["red"]] if m else (), mirror=True, bisect=True, subsurf=1)

    # red floors of the pod cushions
    bm, _ = lathe([(0.0, 0.0004), (0.0150, 0.0004), (0.0150, 0.0009), (0.0, 0.0009)])
    bm.transform(pod_matrix())
    new_obj("Pod_Red_Floor", bm, COLS[1], mats=[m["red"]] if m else (), mirror=True, subsurf=0)

    # dark trim strips on the inner top edge of the arms
    U = seam_u()
    rings = []
    for k in range(17):
        u = U - 0.004 + (path_len() - 0.030 - (U - 0.004)) * k / 16
        rings.append([wrap(u, z, T / 2 + ARM_T + dd) for dd, z in
                      ((-0.0012, 0.0070), (0.0012, 0.0080), (0.0012, 0.0165), (-0.0012, 0.0185))])
    bm2 = bmesh.new()
    vv = [[bm2.verts.new(p) for p in r] for r in rings]
    for k in range(len(vv) - 1):
        for i in range(4):
            j = (i + 1) % 4
            bm2.faces.new((vv[k][i], vv[k][j], vv[k + 1][j], vv[k + 1][i]))
    bm2.faces.new(vv[0][::-1])
    bm2.faces.new(vv[-1])
    new_obj("Inner_Dark_Trim", bm2, COLS[1], mats=[m["trim"]] if m else (), mirror=True, subsurf=1)


# ================================================================ stage 5 (look)
def _ramp(nt, stops, interp='CONSTANT'):
    r = nt.nodes.new("ShaderNodeValToRGB")
    cr = r.color_ramp
    cr.interpolation = interp
    while len(cr.elements) > 1:
        cr.elements.remove(cr.elements[-1])
    cr.elements[0].position = stops[0][0]
    cr.elements[0].color = stops[0][1]
    for pos, col in stops[1:]:
        e = cr.elements.new(pos)
        e.color = col
    return r


def _math(nt, op, a=None, b=None):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _mix(nt, fac, a, b, blend='MIX'):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = 'RGBA'
    n.blend_type = blend
    n.clamp_result = True
    ins = [s for s in n.inputs if s.type == 'RGBA']
    fs = n.inputs[0]
    for sock, v in ((fs, fac), (ins[0], a), (ins[1], b)):
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = v
        else:
            nt.links.new(v, sock)
    return n.outputs[2] if n.outputs[2].type == 'RGBA' else [o for o in n.outputs if o.type == 'RGBA'][0]


def _toon_base(nt):
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    return s2r.outputs["Color"]


def _hatch(nt, scale=170.0):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = 'BANDS'
    wv.bands_direction = 'DIAGONAL'
    wv.wave_profile = 'SIN'
    wv.inputs["Scale"].default_value = scale
    wv.inputs["Distortion"].default_value = 0.0
    nt.links.new(tc.outputs["Window"], wv.inputs["Vector"])
    return _math(nt, 'GREATER_THAN', wv.outputs["Fac"], 0.62)


def _emit_out(nt, color, strength=1.0):
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength if isinstance(strength, float) else 1.0
    nt.links.new(color, em.inputs["Color"])
    if not isinstance(strength, float):
        nt.links.new(strength, em.inputs["Strength"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])


def _new_mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    return m, m.node_tree


def mat_gold():
    m, nt = _new_mat("M_Comic_Gold")
    light = _toon_base(nt)
    lum = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(light, lum.inputs[0])
    L = lum.outputs[0]
    ramp = _ramp(nt, [(0.0, srgb("#000000")), (0.24, srgb("#8A5106")), (0.45, srgb("#E3A818")), (0.84, srgb("#FFE066"))])
    nt.links.new(L, ramp.inputs[0])
    col = ramp.outputs[0]
    # pen hatching in the shadow-transition band
    band = _math(nt, 'MULTIPLY', _math(nt, 'GREATER_THAN', L, 0.22), _math(nt, 'LESS_THAN', L, 0.34))
    hatch = _math(nt, 'MULTIPLY', band, _hatch(nt))
    col = _mix(nt, hatch, col, srgb("#000000"))
    # hard specular bands
    gl = nt.nodes.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.15
    gl.inputs["Color"].default_value = (1, 1, 1, 1)
    gs = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(gl.outputs[0], gs.inputs[0])
    gbw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(gs.outputs["Color"], gbw.inputs[0])
    sramp = _ramp(nt, [(0.0, (0, 0, 0, 1)), (0.82, (1, 1, 1, 1))])
    nt.links.new(gbw.outputs[0], sramp.inputs[0])
    soft = _ramp(nt, [(0.0, (0, 0, 0, 1)), (0.45, srgb("#FFF8C9"))])   # pale-yellow fringe round the white
    nt.links.new(gbw.outputs[0], soft.inputs[0])
    col = _mix(nt, 1.0, col, soft.outputs[0], 'LIGHTEN')
    col = _mix(nt, 1.0, col, sramp.outputs[0], 'ADD')
    # coloured rim lights, cel-stepped: red bounce from the slit, cool blue kicker
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(light, sep.inputs[0])
    red = _math(nt, 'GREATER_THAN', _math(nt, 'SUBTRACT', sep.outputs[0], sep.outputs[1]), 0.10)
    blue = _math(nt, 'GREATER_THAN', _math(nt, 'SUBTRACT', sep.outputs[2], sep.outputs[0]), 0.12)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    blue = _math(nt, 'MULTIPLY', blue, _math(nt, 'GREATER_THAN', lw.outputs["Facing"], 0.62))   # rim only
    col = _mix(nt, red, col, srgb("#FF3A1A"))
    col = _mix(nt, blue, col, srgb("#7FB2FF"))
    _emit_out(nt, col)
    return m


def mat_ruby():
    m, nt = _new_mat("M_Ruby_Quartz")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    gl = nt.nodes.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.08
    gs = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(gl.outputs[0], gs.inputs[0])
    gbw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(gs.outputs["Color"], gbw.inputs[0])
    # darker toward the slit ends: |object x| / half length
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sx = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sx.inputs[0])
    ends = _math(nt, 'MULTIPLY', _math(nt, 'ABSOLUTE', sx.outputs[0]), 1.0 / 0.07)
    ends = _math(nt, 'POWER', ends, 3.0)
    face = _math(nt, 'SUBTRACT', 1.0, lw.outputs["Facing"])
    v = _math(nt, 'SUBTRACT', _math(nt, 'MULTIPLY', face, 0.75), _math(nt, 'MULTIPLY', ends, 0.45))
    v = _math(nt, 'ADD', v, _math(nt, 'MULTIPLY', gbw.outputs[0], 0.35))
    # diagonal glints
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = 'BANDS'
    wv.bands_direction = 'DIAGONAL'
    wv.inputs["Scale"].default_value = 9.0
    wv.inputs["Distortion"].default_value = 0.0
    nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    streak = _math(nt, 'GREATER_THAN', wv.outputs["Fac"], 0.96)
    v = _math(nt, 'ADD', v, _math(nt, 'MULTIPLY', streak, 0.5))
    ramp = _ramp(nt, [(0.0, srgb("#9E000C")), (0.30, srgb("#FF1414")), (0.62, srgb("#FF6666")), (0.86, srgb("#FFFFFF"))])
    nt.links.new(v, ramp.inputs[0])
    strength = _math(nt, 'ADD', 1.0, _math(nt, 'MULTIPLY', _math(nt, 'GREATER_THAN', v, 0.30), 2.2))
    _emit_out(nt, ramp.outputs[0], strength)
    return m


def mat_flat_toon(name, dark, mid, light_hex=None):
    m, nt = _new_mat(name)
    light = _toon_base(nt)
    lum = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(light, lum.inputs[0])
    stops = [(0.0, srgb("#000000")), (0.18, srgb(dark)), (0.45, srgb(mid))]
    if light_hex:
        stops.append((0.85, srgb(light_hex)))
    ramp = _ramp(nt, stops)
    nt.links.new(lum.outputs[0], ramp.inputs[0])
    _emit_out(nt, ramp.outputs[0])
    return m


def materials():
    return {
        "gold": mat_gold(),
        "ruby": mat_ruby(),
        "red": mat_flat_toon("M_Inner_Red", "#5A0008", "#B80010", "#FF1A1A"),
        "trim": mat_flat_toon("M_Dark_Trim", "#0A0A0C", "#2A2A30", "#55555E"),
        "ink": mat_flat_toon("M_Ink", "#000000", "#000000"),
    }


def lights():
    for n in ("Key_Sun", "Fill_Side", "Spec_Strip", "Spec_Strip_2", "Ruby_Bounce", "Blue_Rim"):
        kill(n)
    def L(name, typ, loc, rot_target, energy, color, **kw):
        ld = bpy.data.lights.get(name)
        if ld and ld.type != typ:
            bpy.data.lights.remove(ld); ld = None
        ld = ld or bpy.data.lights.new(name, typ)
        ld.energy = energy
        ld.color = srgb(color)[:3]
        for k, v in kw.items():
            setattr(ld, k, v)
        o = bpy.data.objects.new(name, ld)
        coll(COLS[4]).objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector(rot_target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        return o
    L("Key_Sun", 'SUN', (-0.35, -0.6, 1.0), (0, 0, 0), 3.2, "#FFFFFF", angle=math.radians(0.3), specular_factor=0.0)
    # weak +X fill: lifts the far side into the ochre band, crevices stay black
    L("Fill_Side", 'SUN', (1.0, 0.15, 0.45), (0, 0, 0), 1.15, "#FFFFFF", angle=math.radians(0.3), specular_factor=0.0)
    # two tall thin strips -> inked vertical highlight bands on the polished gold
    L("Spec_Strip", 'AREA', (-0.22, -0.55, 0.05), (0, 0, 0), 5.0, "#FFFFFF", shape='RECTANGLE',
      size=0.010, size_y=0.9, diffuse_factor=0.0, use_shadow=False)
    L("Spec_Strip_2", 'AREA', (-0.17, -0.58, 0.05), (0, 0, 0), 5.0, "#FFFFFF", shape='RECTANGLE',
      size=0.004, size_y=0.9, diffuse_factor=0.0, use_shadow=False)
    # inside the slit, just in front of the lens: only the bezel/tunnel walls face it
    p = wrap(0, SLIT_Z, LENS_D - 0.004)
    L("Ruby_Bounce", 'AREA', tuple(p), tuple(p + Vector((0, -1, 0))), 0.05, "#FF1A1A", shape='RECTANGLE',
      size=0.05, size_y=0.004, specular_factor=0.0, use_shadow=False)
    L("Blue_Rim", 'AREA', (0.10, 0.45, 0.10), (0, 0, 0), 9.0, "#4D94FF", size=0.2, specular_factor=0.0)


def line_art():
    sc = bpy.context.scene
    name = "Ink_LineArt"
    kill(name)
    gp = bpy.data.grease_pencils.get(name) or bpy.data.grease_pencils.new(name)
    o = bpy.data.objects.new(name, gp)
    coll(COLS[3]).objects.link(o)
    if not gp.layers:
        gp.layers.new("Ink")
    lay = gp.layers[0]
    mat = bpy.data.materials.get("GP_Ink")
    if not mat:
        mat = bpy.data.materials.new("GP_Ink")
        bpy.data.materials.create_gpencil_data(mat)
    mat.grease_pencil.color = (0, 0, 0, 1)
    if not gp.materials:
        gp.materials.append(mat)
    def mod(nm, radius, **flags):
        md = o.modifiers.new(nm, 'LINEART')
        md.source_type = 'SCENE'
        md.target_layer = lay.name
        md.target_material = mat
        md.radius = radius
        for k in ('use_contour', 'use_crease', 'use_intersection', 'use_edge_mark', 'use_material', 'use_loose'):
            setattr(md, k, flags.get(k, False))
        md.crease_threshold = math.radians(130)
        md.use_crease_on_smooth = True
        md.smooth_tolerance = 0.0
        md.use_cache = False
        return md
    mod("LA_Silhouette", 0.0011, use_contour=True)
    mod("LA_Detail", 0.00045, use_crease=True, use_intersection=True, use_edge_mark=True)
    o.show_in_front = False
    return o


def compositor():
    sc = bpy.context.scene
    ng = bpy.data.node_groups.get("Comic_Comp") or bpy.data.node_groups.new("Comic_Comp", "CompositorNodeTree")
    ng.nodes.clear()
    if not ng.interface.items_tree:
        ng.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    rl = ng.nodes.new("CompositorNodeRLayers")
    gl = ng.nodes.new("CompositorNodeGlare")
    gl.inputs["Type"].default_value = 'Fog Glow'
    gl.inputs["Quality"].default_value = 'High'
    gl.inputs["Highlights Threshold"].default_value = 1.9
    gl.inputs["Strength"].default_value = 0.6
    gl.inputs["Size"].default_value = 0.45
    out = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
    ng.links.new(gl.outputs[0], out.inputs[0])
    sc.compositing_node_group = ng
    sc.render.use_compositing = True


def stage5():
    m = materials()
    stage2(m)
    stage3(m)
    stage4(m)
    lights()
    line_art()
    compositor()


def build_all():
    stage0()
    stage5()


def render(cam, path, res=(1600, 900)):
    sc = bpy.context.scene
    sc.camera = bpy.data.objects[cam]
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
