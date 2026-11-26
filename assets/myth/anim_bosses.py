# Keys the bosses' clips (boss_clips.py) on a bone rig laid on MythRig's joints, renders them, and bakes them
# for the game (src/shared/MythClips/<Kind>.luau, played by MythRig.pose on the same Motor6Ds: no Animation
# assets to upload, and the server stays the authority on the pose).
#   blender -b assets/myth/bosses.blend -P assets/myth/anim_bosses.py -- [options]
#     --kinds Cyclops,Minotaur        only these bosses (default: all)
#     --clips Walk,Attack             only these clips
#     --sheet DIR                     8 stills a clip: DIR/<Kind>_<Clip>_NN.png
#     --frames DIR                    every frame at 30 fps: DIR/<Kind>/<Clip>/NNNN.png (for the MP4 previews)
#     --bake DIR                      DIR/<Kind>.luau
#     --audit                         blender_anim.audit: turn rates (43 degrees a 1/60 s frame) and loop seams
#     --save PATH                     the rigged, keyed scene as a .blend (one action a clip, fake users)
# Bones sit on MythRig's pivots with identity rest matrices, so a bone's local rotation is the Motor6D's
# rotation in its parent's (axis-aligned) frame: C0 = RigRestC0 * CFrame(pos) * rotation.
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import boss_clips  # noqa: E402

FPS = 30
BAKE_FPS = 20
R2B = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Roblox -> Blender (build.py)
B2R = R2B.transposed()
KIND_X = {"Cyclops": 0.0, "Minotaur": 12.0, "Talos": 24.0}  # build_bosses.py lays them out 12 studs apart
PIVOT = {
    "Root": (0, 6, 0), "Waist": (0, 7, 0), "Neck": (0, 10.2, -0.3),
    "LeftShoulder": (-3.6, 9.6, 0), "LeftElbow": (-3.6, 6.7, 0), "LeftWrist": (-3.9, 4, -0.4),
    "RightShoulder": (3.6, 9.6, 0), "RightElbow": (3.6, 6.7, 0), "RightWrist": (3.9, 4, -0.4),
    "LeftHip": (-1.1, 5, 0), "LeftKnee": (-1.1, 2.6, 0), "LeftAnkle": (-1.2, 0.7, 0),
    "RightHip": (1.1, 5, 0), "RightKnee": (1.1, 2.6, 0), "RightAnkle": (1.2, 0.7, 0),
}
JOINTS = list(PIVOT)  # the order the baked data keeps (MythClips/init.luau JOINTS)
PARENT = {"Root": None, "Waist": "Root", "Neck": "Waist"}
for side in ("Left", "Right"):
    PARENT.update({side + "Shoulder": "Waist", side + "Elbow": side + "Shoulder", side + "Wrist": side + "Elbow",
                   side + "Hip": "Root", side + "Knee": side + "Hip", side + "Ankle": side + "Knee"})
PART = {"Root": "LowerTorso", "Waist": "UpperTorso", "Neck": "Head"}
for side in ("Left", "Right"):
    PART.update({side + "Shoulder": side + "UpperArm", side + "Elbow": side + "LowerArm", side + "Wrist": side + "Hand",
                 side + "Hip": side + "UpperLeg", side + "Knee": side + "LowerLeg", side + "Ankle": side + "Foot"})
EASE = {"smooth": ("BEZIER", None), "fast": ("QUART", "EASE_IN"), "snap": ("CUBIC", "EASE_OUT"), "back": ("BACK", "EASE_OUT"),
        "elastic": ("ELASTIC", "EASE_OUT"), "step": ("CONSTANT", None), "lin": ("LINEAR", None)}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


KINDS = (opt("--kinds") or "Cyclops,Minotaur,Talos").split(",")
ONLY = set(opt("--clips").split(",")) if opt("--clips") else None


# ------------------------------------------------------------------------------------------ poses
def rot_x(d):
    return Matrix.Rotation(math.radians(d), 3, "X")


def angles(x, y, z):
    """CFrame.Angles(x, y, z) in degrees: Rx * Ry * Rz, Roblox axes."""
    return Matrix.Rotation(math.radians(x), 3, "X") @ Matrix.Rotation(math.radians(y), 3, "Y") @ Matrix.Rotation(math.radians(z), 3, "Z")


def ankle_height(root_x, hip_x, knee_x):
    """The ankle's height under the root pivot, bent in the side view (rest: -5.3)."""
    v = Vector((0, -1.9, 0))
    v = rot_x(knee_x) @ v + Vector((0, -2.4, 0))
    v = rot_x(hip_x) @ v + Vector((0, -1.0, 0))
    return (rot_x(root_x) @ v).y


def resolve(spec, additive=False):
    """A spec (boss_clips) -> ({joint: (x, y, z) degrees}, root position in studs)."""
    g = lambda k, n: tuple(spec.get(k, (0,) * n))  # noqa: E731
    root, waist, neck = g("root", 3), g("waist", 3), g("neck", 3)
    rot = {"Root": root, "Waist": waist, "Neck": neck}
    heights = []
    for side, sg, arm, leg in (("Left", -1, g("la", 5), g("ll", 4)), ("Right", 1, g("ra", 5), g("rl", 4))):
        fwd, out, twist, elbow, wrist = arm
        rot[side + "Shoulder"] = (fwd, sg * twist, sg * out)
        rot[side + "Elbow"] = (elbow, 0, 0)
        rot[side + "Wrist"] = (wrist, 0, 0)
        hf, ho, knee, ankle = leg
        rot[side + "Hip"] = (hf, 0, sg * ho)
        rot[side + "Knee"] = (-knee, 0, 0)
        if additive:
            rot[side + "Ankle"] = (ankle, 0, 0)
        else:
            rot[side + "Ankle"] = (-(root[0] + hf - knee) + ankle, 0, -(root[2] + sg * ho))
            heights.append(ankle_height(root[0], hf, -knee) * math.cos(math.radians(ho + abs(root[2]))))
    px, py, pz = g("pos", 3)
    if not additive and spec.get("ground", True):
        py += -5.3 - min(heights)
    py += spec.get("lift", 0)
    return rot, (px, py, pz)


# ------------------------------------------------------------------------------------------ rig
def build_rig(kind):
    name = kind + "_Rig"
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(arm)
    arm.location = (-KIND_X[kind], 0, 0)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for j in JOINTS:
        b = data.edit_bones.new(j)
        b.head = R2B @ Vector(PIVOT[j])
        b.tail = b.head + Vector((0, 0.6, 0))
        b.roll = 0
    for j in JOINTS:
        if PARENT[j]:
            data.edit_bones[j].parent = data.edit_bones[PARENT[j]]
            data.edit_bones[j].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for b in data.bones:
        m = b.matrix_local.to_3x3()
        assert max(abs(m[r][c] - (r == c)) for r in range(3) for c in range(3)) < 1e-5, b.name
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for j in JOINTS:
        ob = bpy.data.objects.get(f"{kind}_{PART[j]}")
        if not ob:
            print("missing piece", kind, PART[j])
            continue
        world = ob.matrix_world.copy()
        bone = data.bones[j]
        ob.parent = arm
        ob.parent_type = "BONE"
        ob.parent_bone = j
        pm = arm.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
        ob.matrix_parent_inverse = pm.inverted()
        ob.matrix_world = world
    return arm


def channelbag(arm):
    from bpy_extras import anim_utils
    ad = arm.animation_data
    return anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)


def key_clip(arm, kind, clip_name, clip):
    ad = arm.animation_data_create()
    ad.action = None
    additive = clip.get("additive", False)
    keys = sorted(clip["keys"], key=lambda k: k[0])
    # A "step" key is a mechanical ratchet: hold the previous pose, then snap over 0.1 s. A true CONSTANT
    # jump pops in one frame and reads as a glitch in the engine; the snap keeps the hold-and-jerk look.
    stepped = []
    for i, (t, spec, ease) in enumerate(keys):
        if ease == "step" and i > 0:
            hold = t - 0.1
            if hold > keys[i - 1][0] + 0.02:
                stepped.append((hold, keys[i - 1][1], "smooth" if keys[i - 1][2] == "step" else "lin"))
            ease = "snap"
        stepped.append((t, spec, ease))
    keys = stepped
    if clip["loop"]:
        keys = [k for k in keys if k[0] < clip["len"] - 1e-6] + [(clip["len"], keys[0][1], "smooth")]
    previous = {}
    frames = []
    for t, spec, ease in keys:
        f = t * FPS
        frames.append((f, ease))
        rot, pos = resolve(spec, additive)
        for j in JOINTS:
            pb = arm.pose.bones[j]
            q = (R2B @ angles(*rot[j]) @ B2R).to_quaternion()
            if j in previous and previous[j].dot(q) < 0:
                q.negate()
            previous[j] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f, group=j)
            if j == "Root":
                pb.location = R2B @ Vector(pos)
                pb.keyframe_insert("location", frame=f, group=j)
    act = ad.action
    act.name = f"{kind}_{clip_name}"
    act.use_fake_user = True
    drag = clip.get("drag", {})
    for fc in channelbag(arm).fcurves:
        pts = sorted(fc.keyframe_points, key=lambda k: k.co.x)
        for i, kp in enumerate(pts):
            nxt = frames[i + 1][1] if i + 1 < len(frames) else "smooth"
            interp, easing = EASE[nxt]
            kp.interpolation = interp
            if easing:
                kp.easing = easing
            if interp == "BACK":
                kp.back = 1.6
            if interp == "ELASTIC":
                kp.amplitude, kp.period = 0.0, 6.0
        bone = fc.data_path.split('"')[1]
        shift = drag.get(bone, 0)
        if shift:
            for kp in (pts if clip["loop"] else pts[1:]):
                kp.co.x += shift
                kp.handle_left.x += shift
                kp.handle_right.x += shift
        if clip["loop"]:
            fc.modifiers.new("CYCLES")
        fc.update()
    length = clip["len"] if clip["loop"] else max(clip["len"] or 0, keys[-1][0]) + max(drag.values(), default=0) / FPS
    act["clip_len"] = length
    act["clip_loop"] = clip["loop"]
    act["clip_additive"] = additive
    act["clip_sections"] = str(clip.get("sections", {}))
    return act, length


def assign(arm, act):
    ad = arm.animation_data_create()
    ad.action = act
    if ad.action_slot is None and act.slots:
        ad.action_slot = act.slots[0]


def sample(arm, t):
    """The rig at t seconds: {joint: Quaternion (Roblox axes)}, root position (Roblox axes)."""
    f = t * FPS
    bpy.context.scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
    out = {}
    for j in JOINTS:
        m = arm.pose.bones[j].matrix_basis
        r = (B2R @ m.to_3x3() @ R2B).to_quaternion().normalized()
        if r.w < 0:
            r.negate()
        out[j] = r
    loc = B2R @ arm.pose.bones["Root"].matrix_basis.to_translation()
    return out, loc


# ------------------------------------------------------------------------------------------ bake
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def enc(v, lo, hi, chars):
    n = 64 ** chars - 1
    i = max(0, min(n, round((v - lo) / (hi - lo) * n)))
    s = ""
    for _ in range(chars):
        s = B64[i % 64] + s
        i //= 64
    return s


def bake(arm, kind, clips, out_dir):
    lines = [f"-- Generated by assets/myth/anim_bosses.py from boss_clips.py ({kind}): do not edit by hand.",
             "-- Each frame: the root's offset (3 x 3 chars, studs at scale 1, -32..32), then each joint's rotation",
             "-- (MythClips JOINTS order) as a quaternion's x, y, z (2 chars each, -1..1; w >= 0).",
             "return {", f"\tfps = {BAKE_FPS},", "\tclips = {"]
    for name, (act, length, clip) in clips.items():
        assign(arm, act)
        n = round(length * BAKE_FPS)
        count = n if clip["loop"] else n + 1
        data = []
        for i in range(count):
            rots, loc = sample(arm, min(i / BAKE_FPS, length))
            data.append("".join(enc(c, -32, 32, 3) for c in loc))
            for j in JOINTS:
                q = rots[j]
                data.append(enc(q.x, -1, 1, 2) + enc(q.y, -1, 1, 2) + enc(q.z, -1, 1, 2))
        sections = clip.get("sections", {})
        sec = ", ".join(f"{k} = {v:g}" for k, v in sections.items())
        extra = (f", sections = {{ {sec} }}" if sec else "") + (", additive = true" if clip.get("additive") else "")
        lines.append(f'\t\t{name} = {{ length = {length:.4f}, loop = {str(clip["loop"]).lower()}, frames = {count}{extra},')
        lines.append(f'\t\t\tdata = "{"".join(data)}" }},')
    lines += ["\t},", "}", ""]
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, kind + ".luau")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("BAKED", path, os.path.getsize(path), "bytes")


# ------------------------------------------------------------------------------------------ renders
def setup_render(size):
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        pass
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.fps = FPS
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.get("QA") or bpy.data.worlds.new("QA")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.42, 0.45, 0.52, 1)
    bg.inputs[1].default_value = 0.9
    scene.world = world

    def light(name, energy, direction):
        ob = bpy.data.objects.get(name)
        if not ob:
            ob = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
            scene.collection.objects.link(ob)
        ob.data.energy = energy
        ob.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()

    light("QAKey", 3.2, (-0.6, 0.8, -0.7))
    light("QARim", 2.2, (0.5, -0.9, -0.3))
    light("QAFill", 0.8, (0.8, 0.6, -0.2))
    for o in scene.objects:
        if o.type == "LIGHT" and not o.name.startswith("QA"):
            o.hide_render = True
    floor = bpy.data.objects.get("AnimFloor")
    if not floor:
        me = bpy.data.meshes.new("AnimFloor")
        me.from_pydata([(-60, -60, 0), (60, -60, 0), (60, 60, 0), (-60, 60, 0)], [], [(0, 1, 2, 3)])
        floor = bpy.data.objects.new("AnimFloor", me)
        scene.collection.objects.link(floor)
        mat = bpy.data.materials.new("AnimFloor")
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs[0].default_value = (0.2, 0.19, 0.18, 1)
        me.materials.append(mat)
    cam = bpy.data.objects.get("AnimCam") or bpy.data.objects.new("AnimCam", bpy.data.cameras.new("AnimCam"))
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam.data.lens = 40
    scene.camera = cam
    return cam


def show_only(kind):
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.name != "AnimFloor":
            o.hide_render = not (o.name.startswith(kind + "_") and "Pylon" not in o.name and "__" not in o.name)


def frame_camera(cam, kind):
    centre = Vector((-KIND_X[kind], 0, 7.0))
    d = Vector((0.62, -1, 0.2)).normalized()  # three-quarter front, a little above
    cam.location = centre + d * 29
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------------------------------ main
def main():
    sheet, frames_dir, bake_dir, save = opt("--sheet"), opt("--frames"), opt("--bake"), opt("--save")
    do_audit = "--audit" in argv
    cam = None
    if sheet or frames_dir:
        cam = setup_render(360 if sheet and not frames_dir else 720)
    if do_audit:
        sys.path.insert(0, os.path.join(HERE, "..", "..", ".claude", "skills", "roblox-dev", "scripts"))
        import blender_anim as ba
    for kind in KINDS:
        arm = build_rig(kind)
        clips = {}
        for name, clip in boss_clips.CLIPS[kind]().items():
            if ONLY and name not in ONLY:
                continue
            act, length = key_clip(arm, kind, name, clip)
            clips[name] = (act, length, clip)
            print(f"KEYED {kind} {name}: {length:.2f} s, {len(clip['keys'])} keys")
        if do_audit:
            for name, (act, length, clip) in clips.items():
                assign(arm, act)
                end = round(length * FPS)
                r = ba.audit(arm, action=act, stage="FINAL", loop=(0, end) if clip["loop"] else False, contacts=False, measure=arm)
                bad = [e for e in r.get("errors", []) if not any(w in e for w in ("Linear", "Constant", "other interpolation", "both loop ends"))]
                print(f"AUDIT {kind} {name}:", "ok" if not bad else bad[:4])
        if cam:
            show_only(kind)
            frame_camera(cam, kind)
            for name, (act, length, clip) in clips.items():
                assign(arm, act)
                if sheet:
                    os.makedirs(sheet, exist_ok=True)
                    n = 8
                    for i in range(n):
                        t = length * i / (n if clip["loop"] else n - 1)
                        bpy.context.scene.frame_set(int(t * FPS), subframe=t * FPS % 1)
                        render(os.path.join(sheet, f"{kind}_{name}_{i:02d}.png"))
                if frames_dir:
                    folder = os.path.join(frames_dir, kind, name)
                    os.makedirs(folder, exist_ok=True)
                    total = round(length * FPS) + (0 if clip["loop"] else 1)
                    reps = max(1, round(2.6 / length)) if clip["loop"] else 1  # short loops twice or more
                    k = 0
                    for _ in range(reps):
                        for f in range(total):
                            bpy.context.scene.frame_set(f)
                            render(os.path.join(folder, f"{k:04d}.png"))
                            k += 1
        if bake_dir:
            bake(arm, kind, clips, bake_dir)
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(save), copy=True)
        print("SAVED", save)


main()
