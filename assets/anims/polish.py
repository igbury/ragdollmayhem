"""Author and export the movement polish clips. Run: python assets/anims/polish.py.

One source generates the Luau pose data and uploadable RBXMX, so Studio previews
and published animations use the same poses, easing and event markers.
Angles are degrees; transforms are [x, y, z, pitch, yaw, roll].
"""
import argparse
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ORDER = ["HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
         "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
         "RightUpperLeg", "RightLowerLeg", "RightFoot"]
PARENT = dict(LowerTorso="HumanoidRootPart", UpperTorso="LowerTorso", Head="UpperTorso")
for side in ("Left", "Right"):
    PARENT.update({side+"UpperArm": "UpperTorso", side+"LowerArm": side+"UpperArm",
                   side+"Hand": side+"LowerArm", side+"UpperLeg": "LowerTorso",
                   side+"LowerLeg": side+"UpperLeg", side+"Foot": side+"LowerLeg"})
PRIORITY = dict(Core=1000, Idle=0, Movement=1, Action=2, Action2=3, Action3=4, Action4=5)
EASING = dict(Linear=0, Constant=1, Elastic=2, Cubic=3, Bounce=4, CubicV2=5)
DIRECTION = dict(In=0, Out=1, InOut=2)


def r(x=0, y=0, z=0, *, at=(0, 0, 0)):
    return [*at, x, y, z]


def frame(t, poses=None, ease="CubicV2", direction="InOut", markers=None):
    return dict(time=t, poses=poses or {}, easing=ease, direction=direction, markers=markers or [])


CLIPS = {}


def clip(name, keys, *, base=None, loop=False, priority="Action4", partial=False,
         referenceSpeed=None, impactTime=None, linearParts=None):
    expanded = []
    for key in keys:
        expanded.append({**key, "poses": {**(base or {}), **key["poses"]}})
    spec = dict(loop=loop, priority=priority, partial=partial, keys=expanded)
    for field, value in dict(referenceSpeed=referenceSpeed, impactTime=impactTime,
                             linearParts=linearParts).items():
        if value is not None:
            spec[field] = value
    CLIPS[name] = spec


# Athletic but deliberately loose-armed sprint. Contact, compression, passing,
# lift-off and flight are separate keys. Knees never bend backwards.
sprint = []
for i in range(9):
    phase = i / 8
    a = phase * math.tau
    poses = {
        "LowerTorso": r(-4, 0, 2*math.sin(a), at=(0, -0.06+0.07*math.cos(2*a), 0)),
        "UpperTorso": r(-18, 7*math.cos(a), -2*math.sin(a)),
        "Head": r(15, -4*math.cos(a), 1.5*math.sin(a)),
    }
    # Half a cycle offset: the opposite arm leads each leg.
    for side, offset, sign in (("Left", 0, -1), ("Right", math.pi, 1)):
        q = a + offset
        hip = 40*math.cos(q)
        # High heel recovery on the forward swing; a soft knee on contact.
        knee = -12 - 88*max(0, math.sin(q)) - 12*max(0, -math.cos(q))
        poses.update({
            side+"UpperLeg": r(hip, 0, 2*sign),
            side+"LowerLeg": r(knee),
            side+"Foot": r(-12*math.cos(q)-8*math.sin(q)),
            side+"UpperArm": r(-44*math.cos(q), 5*sign, sign*(24+8*math.sin(q))),
            side+"LowerArm": r(65+20*math.cos(q)),
            side+"Hand": r(8*math.sin(q), 0, 4*sign),
        })
    # Exact seam, rather than tiny trigonometric rounding differences.
    if i == 8:
        poses = sprint[0]["poses"].copy()
    sprint.append(frame(round(phase*0.56, 5), poses, "Linear",
                        markers=["StepLeft"] if i == 0 else ["StepRight"] if i == 4 else []))
clip("SprintFlail", sprint, loop=True, priority="Movement", referenceSpeed=16)

low = dict(LowerTorso=r(-15), UpperTorso=r(-10), Head=r(23),
           LeftUpperArm=r(22, 0, -8), RightUpperArm=r(22, 0, 8),
           LeftLowerArm=r(65), RightLowerArm=r(65),
           LeftUpperLeg=r(82), RightUpperLeg=r(82),
           LeftLowerLeg=r(-116), RightLowerLeg=r(-116),
           LeftFoot=r(49), RightFoot=r(49))
slide = {**low, "LowerTorso": r(24, -8, -5, at=(0, 0.02, 0)),
         "UpperTorso": r(5, 8, 3), "Head": r(-24),
         "LeftUpperArm": r(-48, -8, -18), "LeftLowerArm": r(15),
         "LeftHand": r(-18, 0, -8),
         "RightUpperArm": r(40, 0, 12), "RightLowerArm": r(68),
         "LeftUpperLeg": r(98, 0, -6), "LeftLowerLeg": r(-126), "LeftFoot": r(30),
         "RightUpperLeg": r(56, 0, 4), "RightLowerLeg": r(-10), "RightFoot": r(-8)}
clip("SlideEnter", [
    frame(0, low, direction="Out"),
    frame(.065, {**slide, "LowerTorso": r(14, -5, -3), "RightLowerLeg": r(-42)}, direction="Out"),
    frame(.16, slide),
], priority="Action2")
clip("slide", [
    frame(0, slide),
    frame(.16, {"LowerTorso": r(25, -9, -5.5, at=(0, 0, 0)),
                "Head": r(-23), "RightLowerArm": r(72)}),
    frame(.34, {"LowerTorso": r(23, -7, -4, at=(0, .035, 0)),
                "LeftLowerArm": r(18), "RightFoot": r(-5)}),
    frame(.5, {"UpperTorso": r(6, 10, 4), "Head": r(-25), "RightUpperArm": r(42, 0, 14)}),
    frame(.68, slide),
], base=slide, loop=True, priority="Action")
clip("SlideExit", [
    frame(0, slide, direction="Out"),
    frame(.08, {**low, "LowerTorso": r(2, -4, -3), "RightUpperLeg": r(70),
                 "RightLowerLeg": r(-80), "LeftUpperArm": r(-8)}, direction="Out"),
    frame(.2, low),
], priority="Action2")

crouch = []
for i in range(9):
    a = i/8*math.tau
    poses = {"LowerTorso": r(-15, 0, 2.5*math.sin(a), at=(0, .035*math.cos(2*a), 0)),
             "UpperTorso": r(-10, 4*math.cos(a), -2*math.sin(a)),
             "Head": r(23, -3*math.cos(a))}
    for side, off, sign in (("Left", 0, -1), ("Right", math.pi, 1)):
        q = a+off
        poses.update({side+"UpperLeg": r(82+18*math.cos(q), 0, 3*sign),
                      side+"LowerLeg": r(-112-15*max(0, math.sin(q))),
                      side+"Foot": r(15-(82+18*math.cos(q))-(-112-15*max(0, math.sin(q)))),
                      side+"UpperArm": r(22-10*math.cos(q), 0, sign*8),
                      side+"LowerArm": r(65+8*math.cos(q))})
    if i == 8:
        poses = crouch[0]["poses"].copy()
    crouch.append(frame(i*.1, poses, "Linear",
                         markers=["StepLeft"] if i == 0 else ["StepRight"] if i == 4 else []))
clip("crouch", crouch, base=low, loop=True, priority="Action", referenceSpeed=5)
clip("CrouchIdle", [
    frame(0, low),
    frame(.48, {"UpperTorso": r(-9), "Head": r(24), "LeftLowerArm": r(67), "RightLowerArm": r(67)}),
    frame(.96, low),
], base=low, loop=True, priority="Action")

cling = dict(LowerTorso=r(4, 0, -2, at=(0, 0, -.3)), UpperTorso=r(5), Head=r(12),
             LeftUpperArm=r(148, 0, -19), RightUpperArm=r(140, 0, 21),
             LeftLowerArm=r(32), RightLowerArm=r(25),
             LeftHand=r(-6), RightHand=r(-9),
             LeftUpperLeg=r(48, 0, -6), LeftLowerLeg=r(-78), LeftFoot=r(22),
             RightUpperLeg=r(12, 0, 6), RightLowerLeg=r(-38), RightFoot=r(12))
clip("WallCling", [
    frame(0, cling), frame(.32, {"UpperTorso": r(6), "Head": r(14),
                               "LeftLowerArm": r(35), "RightLowerLeg": r(-42)}),
    frame(.64, {"UpperTorso": r(4), "Head": r(11), "RightLowerArm": r(28)}),
    frame(.96, cling),
], base=cling, loop=True, priority="Action")
clip("Mantle", [
    frame(0, cling, direction="Out"),
    frame(.08, {**cling, "UpperTorso": r(-12), "LeftLowerArm": r(75), "RightLowerArm": r(68),
                "RightUpperLeg": r(55), "RightLowerLeg": r(-90)}, direction="Out"),
    frame(.19, {"LowerTorso": r(-24, 0, -8), "UpperTorso": r(-18), "Head": r(28),
                 "LeftUpperArm": r(90, 0, -20), "RightUpperArm": r(95, 0, 16),
                 "LeftLowerArm": r(65), "RightLowerArm": r(55),
                 "RightUpperLeg": r(108, 0, 18), "RightLowerLeg": r(-112),
                 "LeftUpperLeg": r(28), "LeftLowerLeg": r(-75)}, markers=["Plant"]),
    frame(.31, {"LowerTorso": r(-20, 0, 5), "UpperTorso": r(-12), "Head": r(24),
                 "LeftUpperArm": r(35, 0, -15), "RightUpperArm": r(50, 0, 15),
                 "LeftLowerArm": r(25), "RightLowerArm": r(40),
                 "RightUpperLeg": r(68), "RightLowerLeg": r(-75),
                 "LeftUpperLeg": r(62), "LeftLowerLeg": r(-105)}),
    frame(.42, {"LowerTorso": r(-10), "UpperTorso": r(-8), "Head": r(12),
                 "LeftUpperArm": r(-12), "RightUpperArm": r(25),
                 "LeftLowerArm": r(45), "RightLowerArm": r(50),
                 "LeftUpperLeg": r(25), "LeftLowerLeg": r(-35),
                 "RightUpperLeg": r(-12), "RightLowerLeg": r(-18)}),
    frame(.5),
])

guard = dict(UpperTorso=r(-8), Head=r(6), LeftUpperArm=r(55, -20, 10),
             LeftLowerArm=r(115), RightUpperArm=r(45, 20, -10), RightLowerArm=r(120))
clip("HighKick", [
    frame(0, {"LeftUpperArm": r(25, 0, -10), "RightUpperArm": r(20, 0, 10),
              "LeftLowerArm": r(55), "RightLowerArm": r(55)}, direction="In"),
    frame(.075, {"LowerTorso": r(0, 30, 7), "UpperTorso": r(-4, -9), "Head": r(5, -21),
                  "RightUpperLeg": r(65, 0, 28), "RightLowerLeg": r(-108),
                  "LeftUpperLeg": r(0, 0, -8), "LeftLowerLeg": r(-15)}, direction="In"),
    frame(.13, {"LowerTorso": r(0, 68, 23), "UpperTorso": r(0, -20), "Head": r(2, -48, -10),
                 "RightUpperLeg": r(60, 0, 70), "RightLowerLeg": r(-72),
                 "LeftUpperLeg": r(0, 0, -22), "LeftLowerLeg": r(-14)}, direction="Out"),
    frame(.18, {"LowerTorso": r(0, 80, 30), "UpperTorso": r(0, -24), "Head": r(0, -56, -15),
                 "RightUpperLeg": r(12, 0, 108), "RightLowerLeg": r(-5), "RightFoot": r(-12),
                 "LeftUpperLeg": r(0, 0, -27), "LeftLowerLeg": r(-12), "LeftFoot": r(12)},
          direction="Out", markers=["Hit"]),
    frame(.225, {"LowerTorso": r(0, 82, 31), "UpperTorso": r(0, -25), "Head": r(0, -57, -15),
                  "RightUpperLeg": r(14, 0, 105), "RightLowerLeg": r(-12),
                  "LeftUpperLeg": r(0, 0, -27), "LeftLowerLeg": r(-12), "LeftFoot": r(12)}),
    frame(.32, {"LowerTorso": r(0, 58, 18), "UpperTorso": r(0, -17), "Head": r(3, -41, -8),
                 "RightUpperLeg": r(68, 0, 32), "RightLowerLeg": r(-104),
                 "LeftUpperLeg": r(0, 0, -16), "LeftLowerLeg": r(-16)}),
    frame(.49, {"LowerTorso": r(0, 12, 3), "UpperTorso": r(-6, -4), "Head": r(6, -8),
                 "RightUpperLeg": r(15), "RightLowerLeg": r(-35), "LeftLowerLeg": r(-6)}),
    frame(.7, {"LeftUpperArm": r(25, 0, -10), "RightUpperArm": r(20, 0, 10),
               "LeftLowerArm": r(55), "RightLowerArm": r(55)}),
], base=guard, impactTime=.18)

dive = dict(LowerTorso=r(-155, at=(0, .65, 0)), UpperTorso=r(-6), Head=r(21),
            LeftUpperArm=r(168, 0, -9), RightUpperArm=r(171, 0, 9),
            LeftLowerArm=r(6), RightLowerArm=r(4),
            LeftHand=r(5), RightHand=r(5), LeftUpperLeg=r(-5, 0, -3),
            RightUpperLeg=r(-7, 0, 3), LeftLowerLeg=r(-12), RightLowerLeg=r(-9),
            LeftFoot=r(-12), RightFoot=r(-10))
clip("DiveEnter", [
    frame(0, {"LowerTorso": r(-8), "UpperTorso": r(-12),
              "LeftUpperArm": r(65, 0, -15), "RightUpperArm": r(65, 0, 15),
              "LeftLowerArm": r(85), "RightLowerArm": r(85),
              "LeftUpperLeg": r(45), "RightUpperLeg": r(40),
              "LeftLowerLeg": r(-85), "RightLowerLeg": r(-80)}, direction="In"),
    frame(.07, {"LowerTorso": r(-50, at=(0, .2, 0)), "UpperTorso": r(-20), "Head": r(12),
                 "LeftUpperArm": r(130, 0, -12), "RightUpperArm": r(133, 0, 12),
                 "LeftLowerArm": r(35), "RightLowerArm": r(30),
                 "LeftUpperLeg": r(20), "RightUpperLeg": r(16),
                 "LeftLowerLeg": r(-55), "RightLowerLeg": r(-48)}, direction="Out"),
    frame(.16, {**dive, "LowerTorso": r(-132, at=(0, .5, 0))}, direction="Out"),
    frame(.23, dive),
])
clip("SupermanDive", [
    frame(0, dive), frame(.16, {"UpperTorso": r(-7), "Head": r(23),
                               "LeftLowerLeg": r(-15), "RightUpperArm": r(172, 0, 10)}),
    frame(.32, {"UpperTorso": r(-5), "Head": r(20), "RightLowerLeg": r(-13),
                "LeftUpperArm": r(170, 0, -10)}),
    frame(.48, {"Head": r(22), "LeftLowerLeg": r(-10), "RightLowerLeg": r(-8)}),
    frame(.64, dive),
], base=dive, loop=True)
land = dict(LowerTorso=r(-12, at=(0, -.8, 0)), UpperTorso=r(-28), Head=r(25),
            LeftUpperArm=r(65, 0, -20), RightUpperArm=r(65, 0, 20),
            LeftLowerArm=r(18), RightLowerArm=r(18),
            LeftUpperLeg=r(68, 0, -8), RightUpperLeg=r(68, 0, 8),
            LeftLowerLeg=r(-108), RightLowerLeg=r(-108),
            LeftFoot=r(25), RightFoot=r(25))
clip("SlamLand", [
    frame(0, land, direction="Out", markers=["Impact"]),
    frame(.065, {**land, "LowerTorso": r(-18, at=(0, -1, 0)), "UpperTorso": r(-32)}, direction="Out"),
    frame(.18, {**land, "LowerTorso": r(-8, at=(0, -.5, 0)), "UpperTorso": r(-16),
                 "LeftUpperArm": r(35, 0, -12), "RightUpperArm": r(35, 0, 12)}),
    frame(.34, {"LowerTorso": r(-2, at=(0, -.08, 0)), "UpperTorso": r(-4),
                 "LeftUpperLeg": r(12), "RightUpperLeg": r(12),
                 "LeftLowerLeg": r(-22), "RightLowerLeg": r(-22)}),
    frame(.44),
])

# The root keeps rolling forwards; only its interpolation is linear. Limb
# compression and release have their own timing, not a constant-speed tumble.
roll = []
for t, drop, pitch, hip, knee, arm, elbow, chest in [
    (0, -.55, -18, 55, -85, 55, 50, -16),
    (.055, -.8, -42, 80, -115, 85, 85, -32),
    (.13, -.55, -104, 110, -132, 110, 110, -42),
    (.205, -.3, -180, 115, -138, 105, 115, -44),
    (.28, -.4, -260, 110, -135, 95, 105, -40),
    (.36, -.65, -320, 85, -118, 75, 80, -28),
    (.44, -.7, -354, 62, -90, 40, 40, -16),
    (.53, -.32, -364, 28, -48, 15, 25, -8),
    (.65, 0, -360, 0, 0, 0, 0, 0),
]:
    roll.append(frame(t, dict(LowerTorso=r(pitch, at=(0, drop, 0)),
                             UpperTorso=r(chest), Head=r(-min(30, abs(chest)*.7)),
                             LeftUpperArm=r(arm, 0, 12), RightUpperArm=r(arm, 0, -12),
                             LeftLowerArm=r(elbow), RightLowerArm=r(elbow),
                             LeftUpperLeg=r(hip), RightUpperLeg=r(hip-4 if hip else 0),
                             LeftLowerLeg=r(knee), RightLowerLeg=r(knee),
                             LeftFoot=r(12 if knee else 0), RightFoot=r(12 if knee else 0)),
                      markers=["Contact"] if t == .44 else []))
# Zero the final limbs for a clean hand-off to locomotion.
roll[-1]["poses"] = {"LowerTorso": r(-360)}
clip("RollForward", roll, linearParts=["LowerTorso"])

clip("DummyStagger", [
    frame(0, guard, direction="Out"),
    frame(.045, {"UpperTorso": r(10, -4), "Head": r(10),
                  "LeftUpperArm": r(38, -12, -15), "RightUpperArm": r(35, 12, 15),
                  "LeftLowerArm": r(85), "RightLowerArm": r(90)}, direction="Out"),
    frame(.1, {"UpperTorso": r(23, -9), "Head": r(28, 4),
                "LeftUpperArm": r(22, 0, -35), "RightUpperArm": r(30, 0, 30),
                "LeftLowerArm": r(52), "RightLowerArm": r(62)}),
    frame(.19, {"UpperTorso": r(10, -5), "Head": r(17),
                 "LeftUpperArm": r(35, -10, -15), "RightUpperArm": r(40, 10, 15),
                 "LeftLowerArm": r(80), "RightLowerArm": r(90)}),
    frame(.29, {"UpperTorso": r(-12, 2), "Head": r(2)}),
    frame(.43, guard),
], base=guard, partial=True)

dig = dict(LowerTorso=r(-14, 0, -3, at=(0, -.9, 0)), UpperTorso=r(-22, -8), Head=r(16),
           LeftUpperLeg=r(28, 0, -6), RightUpperLeg=r(34, 0, 6),
           LeftLowerLeg=r(-95), RightLowerLeg=r(-100), LeftFoot=r(75), RightFoot=r(80),
           LeftUpperArm=r(68, -12, -12), LeftLowerArm=r(22), LeftHand=r(-12),
           RightUpperArm=r(72, 15, 10), RightLowerArm=r(25), RightHand=r(-15))
clip("Dig", [
    frame(0, dig, direction="In"),
    frame(.18, {"UpperTorso": r(-30, -5), "Head": r(20),
                 "RightUpperArm": r(96, 10, 8), "RightLowerArm": r(8),
                 "RightHand": r(-28), "LeftUpperArm": r(76, -8, -12)}, markers=["Scoop"]),
    frame(.34, {"LowerTorso": r(-12, 4, -1, at=(0, -.85, 0)), "UpperTorso": r(-18, 8),
                 "RightUpperArm": r(64, 18, 10), "RightLowerArm": r(85), "RightHand": r(5),
                 "LeftUpperArm": r(60, -8, -12), "LeftLowerArm": r(55)}, direction="Out"),
    frame(.5, {"LowerTorso": r(-8, 8, 3, at=(.07, -.82, 0)), "UpperTorso": r(-6, 26),
                "Head": r(5, -12), "RightUpperArm": r(35, 35, 45),
                "RightLowerArm": r(42), "RightHand": r(18), "LeftLowerArm": r(65)},
          direction="Out", markers=["Toss"]),
    frame(.7, {"UpperTorso": r(-16, 10), "RightUpperArm": r(50, 18, 20),
                "RightLowerArm": r(65), "LeftUpperArm": r(72, -10, -12)}),
    frame(.94, {"UpperTorso": r(-27, -6), "RightUpperArm": r(88, 12, 10),
                 "RightLowerArm": r(15), "LeftUpperArm": r(85, -10, -10),
                 "LeftLowerArm": r(15)}),
    frame(1.2, dig),
], base=dig, loop=True, priority="Action3")

limp = []
for t, bad_hip, bad_knee, good_hip, good_knee, sway, drop in [
    (0, -8, -10, 28, -18, 3, -.04),
    (.16, -5, -12, 5, -24, 5, -.1),
    (.34, 2, -15, -26, -35, 3, -.06),
    (.5, 10, -14, -8, -82, -2, -.14),
    (.65, 12, -8, 24, -56, -4, -.18),
    (.8, 2, -8, 38, -24, 0, -.08),
    (.96, -8, -10, 28, -18, 3, -.04),
]:
    limp.append(frame(t, dict(LowerTorso=r(-3, 0, sway, at=(0, drop, 0)),
                             UpperTorso=r(-5, 0, -sway*.7), Head=r(3, 0, -sway*.3),
                             LeftUpperLeg=r(bad_hip, 0, -5), LeftLowerLeg=r(bad_knee),
                             LeftFoot=r(12), RightUpperLeg=r(good_hip),
                             RightLowerLeg=r(good_knee), RightFoot=r(-good_hip*.25)),
                      "Linear", markers=["StepGood"] if t == 0 else ["StepHurt"] if t == .65 else []))
clip("LimpLeft", limp, loop=True, priority="Action", partial=True, referenceSpeed=3.5)


def mirrored(spec):
    def side(name):
        return name.replace("Left", "#").replace("Right", "Left").replace("#", "Right")
    out = json.loads(json.dumps(spec))
    for key in out["keys"]:
        key["poses"] = {side(name): [-p[0], p[1], p[2], p[3], -p[4], -p[5]]
                        for name, p in key["poses"].items()}
    return out


CLIPS["LimpRight"] = mirrored(CLIPS["LimpLeft"])

# Separate impact directions keep a hit from always throwing the head backwards.
for direction in ("Back", "Left", "Right"):
    variant = json.loads(json.dumps(CLIPS["DummyStagger"]))
    for key in variant["keys"][1:-1]:
        weight = math.sin(math.pi * key["time"] / .43)
        if direction == "Back":
            key["poses"]["UpperTorso"] = r(-8-24*weight, 5*weight)
            key["poses"]["Head"] = r(6-26*weight, -3*weight)
        else:
            sign = 1 if direction == "Left" else -1
            key["poses"]["UpperTorso"] = r(-8+4*weight, 5*sign*weight, 22*sign*weight)
            key["poses"]["Head"] = r(6, -5*sign*weight, 24*sign*weight)
    CLIPS["DummyStagger"+direction] = variant


# Pelvis contact corrections measured on the R15 preview rig in Studio.
# These compensate for the support foot, knee or shoulder through each pose.
# They are authored into the clip, so playback does not fight Humanoid physics.
GROUND_LIFT = {"RollForward":[0.6097,0.6397,1.2316,0.7913,-0.9054,-0.6807,0.3102,0.4246,0.025],"slide":[0.4855,0.4895,0.4696,0.4855,0.4855],"LimpRight":[0.1696,0.3493,0.1582,0.2112,0.5007,0.1508,0.1696],"SlamLand":[0.5239,0.8075,0.1578,0.2353,0.025],"SlideExit":[0.4855,0.9688,0.7163],"crouch":[0.8216,0.8362,0.7808,0.727,0.8216,0.8362,0.7807,0.727,0.8216],"SlideEnter":[0.7163,0.9005,0.4855],"SprintFlail":[-0.1251,0.2727,0.2465,0.14200000000000002,-0.1251,0.2727,0.2465,0.14200000000000002,-0.1251],"Dig":[0.5211,0.5211,0.4604,0.4296,0.5211,0.5211,0.5211],"HighKick":[0.025,0.2665,0.389,0.2746,0.2849,0.3699,0.1992,0.025],"CrouchIdle":[0.7163,0.7163,0.7163],"LimpLeft":[0.1696,0.3493,0.1582,0.2113,0.5007,0.1508,0.1696]}
for ground_name, offsets in GROUND_LIFT.items():
    for key, lift in zip(CLIPS[ground_name]["keys"], offsets):
        pelvis = list(key["poses"].get("LowerTorso", r()))
        pelvis[1] += lift
        key["poses"]["LowerTorso"] = pelvis


# Extra breakdowns keep the rotating body on the floor between the principal
# roll poses. Preserve the unwrapped pelvis pitch so it still makes a full turn.
roll_keys = CLIPS["RollForward"]["keys"]
roll_breakdowns = []
for first, last in zip(roll_keys, roll_keys[1:]):
    for step in range(4):
        u = step / 4
        smooth = 4*u**3 if u < .5 else 1-(-2*u+2)**3/2
        poses = {}
        for part in ORDER:
            if part not in first["poses"] and part not in last["poses"]:
                continue
            a, b = first["poses"].get(part, r()), last["poses"].get(part, r())
            amount = u if part == "LowerTorso" else smooth
            poses[part] = [x+(y-x)*amount for x, y in zip(a, b)]
        roll_breakdowns.append(frame(round(first["time"]+(last["time"]-first["time"])*u, 6),
                                     poses, "Linear", markers=first["markers"] if step == 0 else []))
roll_breakdowns.append(roll_keys[-1])
CLIPS["RollForward"]["keys"] = roll_breakdowns
ROLL_CONTACT = [0.015,0.0859,0.0479,-0.0195,0.015,-0.2745,-0.5177,-0.0899,0.015,0.4715,0.6813,0.5057,0.015,0.0407,-0.2331,-0.3131,0.015,-0.101,-0.0983,-0.0173,0.015,-0.1211,-0.1075,0.0237,0.015,-0.0266,0.0671,0.0953,0.015,0.0289,0.0513,0.0189,0.015]
for key, lift in zip(roll_breakdowns, ROLL_CONTACT):
    key["poses"]["LowerTorso"][1] += lift


def lua(value):
    if isinstance(value, dict):
        return "{" + ", ".join("["+json.dumps(k)+"] = "+lua(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ", ".join(lua(v) for v in value) + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    return format(value, ".8g")


def matrix(p):
    x, y, z = map(math.radians, p[3:])
    a, b, c, d, e, f = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return [c*e, -c*f, d, a*f+b*d*e, a*e-b*d*f, -b*c, b*f-a*d*e, b*e+a*d*f, a*c]


def export_xml(name, spec):
    root = ET.Element("roblox", version="4")
    counter = 0

    def item(parent, cls):
        nonlocal counter
        counter += 1
        node = ET.SubElement(parent, "Item", {"class": cls, "referent": "RBX"+str(counter)})
        ET.SubElement(node, "Properties")
        return node

    def prop(node, kind, name, value):
        ET.SubElement(node.find("Properties"), kind, name=name).text = str(value)

    seq = item(root, "KeyframeSequence")
    prop(seq, "string", "Name", name)
    prop(seq, "bool", "Loop", str(spec["loop"]).lower())
    prop(seq, "token", "Priority", PRIORITY[spec["priority"]])
    driven = {part for key in spec["keys"] for part in key["poses"]}
    for key in spec["keys"]:
        keyframe = item(seq, "Keyframe")
        prop(keyframe, "string", "Name", "Keyframe")
        prop(keyframe, "float", "Time", key["time"])
        parents = {}
        for part in ORDER:
            node = item(parents.get(PARENT.get(part), keyframe), "Pose")
            parents[part] = node
            prop(node, "string", "Name", part)
            p = key["poses"].get(part, [0]*6)
            cf = ET.SubElement(node.find("Properties"), "CoordinateFrame", name="CFrame")
            for tag, val in zip(["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"],
                                p[:3]+matrix(p)):
                ET.SubElement(cf, tag).text = format(val, ".9g")
            linear = part in spec.get("linearParts", [])
            prop(node, "token", "EasingStyle", EASING["Linear" if linear else key["easing"]])
            prop(node, "token", "EasingDirection", DIRECTION[key["direction"]])
            prop(node, "float", "Weight", int(part != "HumanoidRootPart" and (not spec["partial"] or part in driven)))
        for marker in key["markers"]:
            node = item(keyframe, "KeyframeMarker")
            prop(node, "string", "Name", marker)
            prop(node, "string", "Value", "")
    return ET.tostring(root, encoding="unicode")+"\n"


def validate():
    for name, spec in CLIPS.items():
        keys = spec["keys"]
        assert keys[0]["time"] == 0 and all(a["time"] < b["time"] for a, b in zip(keys, keys[1:])), name
        if spec["loop"]:
            assert keys[0]["poses"] == keys[-1]["poses"], name+" has an open seam"
        for key in keys:
            assert key["poses"].keys() <= set(ORDER), name
            for part, p in key["poses"].items():
                assert len(p) == 6 and all(math.isfinite(v) for v in p), (name, part)
                if part.endswith("LowerLeg"):
                    assert -145 <= p[3] <= 0, (name, part, "backwards knee")
        for a, b in zip(keys, keys[1:]):
            if "LowerTorso" in spec.get("linearParts", []):
                assert abs(a["poses"].get("LowerTorso", [0]*6)[3] -
                           b["poses"].get("LowerTorso", [0]*6)[3]) < 180, name
    assert any("Hit" in k["markers"] and k["time"] == CLIPS["HighKick"]["impactTime"]
               for k in CLIPS["HighKick"]["keys"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify generated files without writing")
    args = parser.parse_args()
    validate()
    lines = ["-- Generated by assets/anims/polish.py; edit the authoring data there.", "return {"]
    for name, spec in CLIPS.items():
        lines.append("\t["+json.dumps(name)+"] = {")
        for field, val in spec.items():
            if field != "keys":
                lines.append("\t\t"+field+" = "+lua(val)+",")
        lines.append("\t\tkeys = {")
        lines.extend("\t\t\t"+lua(key)+"," for key in spec["keys"])
        lines.extend(["\t\t},", "\t},"])
    lines.append("}\n")
    outputs = {ROOT/"src/shared/AnimationData.luau": "\n".join(lines)}
    outputs.update({ROOT/"assets/anims/polished"/(name+".rbxmx"): export_xml(name, spec)
                    for name, spec in CLIPS.items()})
    for path, content in outputs.items():
        if args.check:
            assert path.read_text(encoding="utf-8") == content, "Regenerate "+str(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    print(f"{len(CLIPS)} clips validated; {'verified' if args.check else 'generated'} {len(outputs)} files")


if __name__ == "__main__":
    main()
