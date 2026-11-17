# Headless Blender: R15 rig with the player's own joint positions (read from Studio), IK on arms
# and legs, the grab animations posed key by key, a render per key, and the joint rotations
# exported as Roblox Pose CFrames (Luau).  Run:
#   blender -b --factory-startup --python grab_rig.py -- <keys.py> <outdir> [render]
import bpy, sys, math, json, os, importlib.util
from mathutils import Matrix, Vector

if "CFG" in globals():  # run inside a live Blender via exec()
    KEYS_FILE, OUT, RENDER = CFG
else:
    args = sys.argv[sys.argv.index("--") + 1:]
    KEYS_FILE, OUT = args[0], args[1]
    RENDER = len(args) > 2 and args[2] == "render"
os.makedirs(OUT, exist_ok=True)
spec = importlib.util.spec_from_file_location("keys", KEYS_FILE)
keys = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keys)

# --- rig data (Roblox space, studs) ------------------------------------------------------------
SIZE = {
    "HumanoidRootPart": (2, 2.1, 1), "LowerTorso": (1.678, .705, 1.069), "UpperTorso": (1.816, 2.201, 1.106),
    "Head": (1.159, 1.175, 1.161),
    "RightUpperArm": (.968, 1.413, .78), "RightLowerArm": (.833, 1.353, .927), "RightHand": (.755, 1, .823),
    "LeftUpperArm": (.967, 1.413, .78), "LeftLowerArm": (.833, 1.353, .927), "LeftHand": (.755, 1, .823),
    "RightUpperLeg": (.781, 2.161, .842), "RightLowerLeg": (.721, 1.541, .842), "RightFoot": (.737, .93, 1.276),
    "LeftUpperLeg": (.781, 2.161, .842), "LeftLowerLeg": (.721, 1.541, .842), "LeftFoot": (.737, .93, 1.276),
}
# child: (parent, att0 in parent, att1 in child)
JOINT = {
    "LowerTorso": ("HumanoidRootPart", (0, -1.05, 0), (0, -.366, -.021)),
    "UpperTorso": ("LowerTorso", (0, .08, -.021), (0, -.753, .02)),
    "Head": ("UpperTorso", (0, 1.099, .02), (0, -.572, .001)),
    "RightUpperArm": ("UpperTorso", (.905, .698, .02), (-.238, .395, -.077)),
    "RightLowerArm": ("RightUpperArm", (.109, -.279, -.077), (-.143, .344, .001)),
    "RightHand": ("RightLowerArm", (.07, -.525, -.21), (-.044, .262, .132)),
    "LeftUpperArm": ("UpperTorso", (-.905, .698, .02), (.238, .395, -.077)),
    "LeftLowerArm": ("LeftUpperArm", (-.11, -.279, -.077), (.143, .344, .001)),
    "LeftHand": ("LeftLowerArm", (-.07, -.525, -.21), (.044, .262, .132)),
    "RightUpperLeg": ("LowerTorso", (.502, -.366, -.021), (.11, .54, -.01)),
    "RightLowerLeg": ("RightUpperLeg", (.11, -.648, -.01), (.08, .346, -.01)),
    "RightFoot": ("RightLowerLeg", (.08, -.347, -.01), (.082, .069, .189)),
    "LeftUpperLeg": ("LowerTorso", (-.502, -.366, -.021), (-.11, .54, -.01)),
    "LeftLowerLeg": ("LeftUpperLeg", (-.11, -.649, -.01), (-.08, .346, -.01)),
    "LeftFoot": ("LeftLowerLeg", (-.08, -.347, -.01), (-.082, .069, .189)),
}
ORDER = ["HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
         "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
FLOOR = -3.466

R = lambda v: Vector(v)
center = {"HumanoidRootPart": Vector((0, 0, 0))}
pivot = {}
for name in ORDER[1:]:
    parent, a0, a1 = JOINT[name]
    pivot[name] = center[parent] + R(a0)
    center[name] = pivot[name] - R(a1)
pivot["HumanoidRootPart"] = Vector((0, 0, 0))

# Roblox (x right, y up, z back) -> Blender (x, -z, y); a proper rotation, so handedness holds
P = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
def B(v):
    v = Vector(v)
    return Vector((v.x, -v.z, v.y))
def to_R(m3):
    return P.transposed() @ m3 @ P
def to_B(m3):
    return P @ m3 @ P.transposed()
def angles(x=0, y=0, z=0):  # CFrame.Angles(x, y, z) in degrees, Roblox space
    r = math.radians
    return Matrix.Rotation(r(x), 3, 'X') @ Matrix.Rotation(r(y), 3, 'Y') @ Matrix.Rotation(r(z), 3, 'Z')

TAIL_OF = {"UpperTorso": "Head", "LowerTorso": "UpperTorso", "RightUpperArm": "RightLowerArm",
           "RightLowerArm": "RightHand", "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
           "RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot",
           "LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot"}

# --- scene ---------------------------------------------------------------------------------------
# a scene of its own (the user's scene is left alone); rebuilt from scratch on every run
old = bpy.data.scenes.get("GrabAnims")
if old:
    for ob in list(old.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.scenes.remove(old)
scene = bpy.data.scenes.new("GrabAnims")
bpy.context.window.scene = scene
arm_data = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for name in ORDER:
    eb = arm_data.edit_bones.new(name)
    head = pivot[name]
    if name in TAIL_OF:
        tail = pivot[TAIL_OF[name]]
    elif name == "HumanoidRootPart":
        tail = head + Vector((0, .6, 0))
    else:
        tail = center[name] + (center[name] - head)
    eb.head, eb.tail = B(head), B(tail)
    if name != "HumanoidRootPart":
        eb.parent = arm_data.edit_bones[JOINT[name][0]]
bpy.ops.object.mode_set(mode='POSE')

def mat(color):
    m = bpy.data.materials.new(str(color))
    m.diffuse_color = (*color, 1)
    return m
GREY, ORANGE, GROUND = mat((.75, .78, .85)), mat((.95, .55, .2)), mat((.35, .5, .3))

def box(name, size, color, parent_bone=None, world=None):
    me = bpy.data.meshes.new(name)
    sx, sy, sz = size
    verts = [(x * sx / 2, y * sy / 2, z * sz / 2) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    me.from_pydata(verts, [], faces)
    me.materials.append(color)
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    if parent_bone:
        ob.parent, ob.parent_type, ob.parent_bone = rig, 'BONE', parent_bone
    if world is not None:
        bpy.context.view_layer.update()
        ob.matrix_world = world
    return ob

# player body: a box per part (a little under size: the real parts are rounded)
for name in ORDER[1:]:
    s = SIZE[name]
    box("P_" + name, (s[0] * .92, s[2] * .9, s[1] * .95), GREY, name, Matrix.Translation(B(center[name])))
box("Ground", (60, 60, .1), GROUND, None, Matrix.Translation(B((0, FLOOR - .05, 0))))

# the held dummy (same build), placed per key: chest frame -> its parts
DUMMY = {}
for name in ORDER[1:]:
    s = SIZE[name]
    DUMMY[name] = box("D_" + name, (s[0] * .92, s[2] * .9, s[1] * .95), ORANGE)
def place_dummy(chest_cf_R, limp=0.0):
    """chest_cf_R: (position, rotation 3x3) of the dummy's UpperTorso in Roblox space, or None."""
    for name, ob in DUMMY.items():
        ob.hide_render = ob.hide_viewport = chest_cf_R is None
    if chest_cf_R is None:
        return
    pos, rot = chest_cf_R
    for name, ob in DUMMY.items():
        off = center[name] - center["UpperTorso"]
        # limbs hang: rotate legs/arms a little towards world down (limp)
        p = Vector(pos) + rot @ off
        ob.matrix_world = Matrix.Translation(B(p)) @ to_B(rot).to_4x4()

# IK: wrists and ankles on targets, elbows/knees aimed by poles
def empty(name):
    e = bpy.data.objects.new(name, None)
    scene.collection.objects.link(e)
    return e
IK = {}
POLE_REST = {"Right": {"arm": (2.2, .2, 1.5), "leg": (.5, -2.2, -2)}, "Left": {"arm": (-2.2, .2, 1.5), "leg": (-.5, -2.2, -2)}}
def signed_angle(u, v, n):
    a = u.angle(v)
    return -a if n.dot(u.cross(v)) < 0 else a
for side in ("Right", "Left"):
    for limb, upper, lower in (("arm", side + "UpperArm", side + "LowerArm"), ("leg", side + "UpperLeg", side + "LowerLeg")):
        t, p = empty(side + limb + "T"), empty(side + limb + "Pole")
        p.location = B(POLE_REST[side][limb])
        pb = rig.pose.bones[lower]
        c = pb.constraints.new('IK')
        c.target, c.pole_target, c.chain_count = t, p, 2
        base, ikb = arm_data.bones[upper], arm_data.bones[lower]
        axis = (ikb.tail_local - base.head_local).normalized()
        v = p.location - base.head_local
        proj = v - axis * v.dot(axis)
        x_axis = base.matrix_local.to_3x3() @ Vector((1, 0, 0))
        c.pole_angle = signed_angle(x_axis, proj, axis)
        IK[(side, limb)] = (c, t, p)

def rest(name):
    return arm_data.bones[name].matrix_local.copy()

def pose_key(k):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    ik_bones = set()
    for (side, limb), (c, t, p) in IK.items():
        spec_ = k.get(side[0] + ("W" if limb == "arm" else "A"))  # RW, LW, RA, LA: wrist / ankle target
        c.influence = 1 if spec_ else 0
        if spec_:
            t.location = B(spec_)
            pole = k.get(side[0] + ("E" if limb == "arm" else "K"))  # elbow / knee pole
            p.location = B(pole) if pole else B(POLE_REST[side][limb])
            ik_bones |= {side + ("UpperArm" if limb == "arm" else "UpperLeg"), side + ("LowerArm" if limb == "arm" else "LowerLeg")}
            # a straight chain gives the solver nothing to fold: start it a little bent
            lower = rig.pose.bones[side + ("LowerArm" if limb == "arm" else "LowerLeg")]
            lower.matrix_basis = Matrix.Rotation(0.5 if limb == "arm" else -0.5, 4, 'X')
    bpy.context.view_layer.update()
    for name in ORDER[1:]:
        if name in ik_bones:
            continue
        parent = JOINT[name][0]
        pp = rig.pose.bones[parent].matrix
        dp = pp.to_3x3() @ rest(parent).to_3x3().inverted()
        if name.endswith("Foot") and parent in ik_bones:
            dp = Matrix.Identity(3)  # a planted (IK) leg keeps its foot level; its angles turn it from there
        L = to_B(angles(*k.get(name, (0, 0, 0))))
        head = pp @ (rest(parent).inverted() @ rest(name).translation)
        if name == "LowerTorso" and "drop" in k:
            head = head + B(k["drop"])
        m = (dp @ L @ rest(name).to_3x3()).to_4x4()
        m.translation = head
        rig.pose.bones[name].matrix = m
        bpy.context.view_layer.update()
    bpy.context.view_layer.update()

def delta(name):
    return rig.pose.bones[name].matrix.to_3x3() @ rest(name).to_3x3().inverted()

def export_key():
    out = {}
    for name in ORDER[1:]:
        L = to_R(delta(JOINT[name][0]).inverted() @ delta(name))
        pos = (0, 0, 0)
        if name == "LowerTorso":
            # the root pivot's move, in the root's (unrotated) frame
            moved = rig.pose.bones[name].matrix.translation - arm_data.bones[name].head_local
            v = P.transposed() @ moved
            pos = tuple(round(c, 4) for c in v)
        out[name] = {"p": pos, "r": [round(L[i][j], 5) for i in range(3) for j in range(3)]}
    return out

def world_R(name, local=(0, 0, 0)):
    """Where a point given in a part's rest-relative coords is now (Roblox space)."""
    m = rig.pose.bones[name].matrix @ rest(name).inverted()
    return P.transposed() @ (m @ B(center[name] + Vector(local)))

# camera / light for renders
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 11
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
try:
    scene.render.engine = 'BLENDER_WORKBENCH'
except TypeError:
    pass
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'MATERIAL'
scene.display.shading.show_cavity = True
scene.render.resolution_x, scene.render.resolution_y = 420, 420
VIEWS = {"side": (10, -1.0, 0), "front": (0, -1.0, -10), "q": (7, 1.5, -7)}  # eye offsets (Roblox space) from (0,-1,-1)

def render(path):
    imgs = []
    for vn, eye in VIEWS.items():
        look = Vector((0, -1.2, -1.2))
        e = look + Vector(eye)
        d = B(look) - B(e)
        cam.location = B(e)
        cam.rotation_euler = d.to_track_quat('-Z', 'Z').to_euler()
        scene.render.filepath = f"{path}_{vn}.png"
        bpy.ops.render.render(write_still=True)

def show(anim_name, i):
    """Pose one key (and its dummy) for a look in the viewport."""
    anim = next(a for a in keys.ANIMS if a["name"] == anim_name)
    k = anim["keys"][i]
    pose_key(k)
    dk = k.get("dummy")
    if dk == "grip":
        g = world_R("RightHand", (0, -.2, -.15))
        place_dummy((g + Vector(k.get("dummyOff", (0, -.9, 0))), angles(*k.get("dummyRot", (0, 0, 0)))))
    elif dk:
        place_dummy((Vector(dk), angles(*k.get("dummyRot", (0, 0, 0)))))
    else:
        place_dummy(None)
    bpy.context.view_layer.update()

result = {}
log = []
for anim in keys.ANIMS:
    frames = []
    for i, k in enumerate(anim["keys"]):
        pose_key(k)
        frames.append({"t": k["t"], "pose": export_key()})
        # where the hand ended up vs. where it was asked to be
        wr = world_R("RightLowerArm", tuple(Vector(JOINT["RightHand"][1]) - (center["RightLowerArm"] - center["RightLowerArm"])))
        grip = world_R("RightHand", (0, -.2, -.15))
        foot = world_R("RightFoot")
        log.append(f"{anim['name']} t={k['t']}: grip={tuple(round(c,2) for c in grip)} rfoot={tuple(round(c,2) for c in foot)}")
        if "dummy" in k:
            dk = k["dummy"]
            if dk == "grip":
                g = world_R("RightHand", (0, -.2, -.15))
                place_dummy((g + Vector(k.get("dummyOff", (0, -.9, 0))), angles(*k.get("dummyRot", (0, 0, 0)))))
            elif dk:
                place_dummy((Vector(dk), angles(*k.get("dummyRot", (0, 0, 0)))))
            else:
                place_dummy(None)
        else:
            place_dummy(None)
        if RENDER:
            render(os.path.join(OUT, f"{anim['name']}_{i:02d}"))
    result[anim["name"]] = {"loop": anim.get("loop", False), "parts": anim.get("parts"), "frames": frames}

with open(os.path.join(OUT, "anims.json"), "w") as f:
    json.dump(result, f)
with open(os.path.join(OUT, "log.txt"), "w") as f:
    f.write("\n".join(log))
print("DONE")
