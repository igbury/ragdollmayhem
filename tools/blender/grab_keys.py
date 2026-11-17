# Key poses for the F grab animations, in Roblox space relative to the HumanoidRootPart (studs,
# x right, y up, z back; floor at y -3.47). RW/LW: wrist targets, RE/LE: elbow poles, RA/LA:
# ankle targets, RK/LK: knee poles (IK). Part names: CFrame.Angles degrees on that joint (FK).
# drop: the hips' move. dummy: "grip" (hangs from the hand, + dummyOff) or a chest position.

STAND_RA, STAND_LA = (.5, -2.93, 0), (-.5, -2.93, 0)
KNEE_R, KNEE_L = (.6, -1.6, -3), (-.6, -1.6, -3)
HELD = {"dummy": "grip", "dummyOff": (0, -.77, .36), "dummyRot": (-25, 180, 0)}  # collar in the fist, leaning back
RAKED = {"dummy": "grip", "dummyOff": (0, -.43, .74), "dummyRot": (-60, 180, 0)}  # on its back, ploughing
HANG = {"dummy": "grip", "dummyOff": (0, -.85, .1)}
DRAGGED = {"dummy": "grip", "dummyOff": (.3, -.35, 1.05), "dummyRot": (-90, 180, 0)}  # on its back, legs trailing

def k(t, **kw):
    d = {"t": t}
    for key, v in kw.items():
        d[key] = v
    return d

ANIMS = [
    # held at your side by the collar in a straight-ish arm, the body leaning back off the fist with its
    # heels dragging; you lean a touch away from the weight. Upper body only: the legs and the left arm
    # keep walking / sprinting.
    {"name": "hold", "loop": True, "parts": ["UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand"], "keys": [
        k(0, UpperTorso=(0, -6, 6), Head=(0, 4, -4), RW=(1.7, -.25, -1.2), RE=(3, -.5, 1), RightHand=(-15, 0, 0), **HELD),
        k(.6, UpperTorso=(-2, -7, 7), Head=(0, 5, -5), RW=(1.7, -.35, -1.15), RE=(3, -.5, 1), RightHand=(-15, 0, 0), **HELD),
        k(1.2, UpperTorso=(0, -6, 6), Head=(0, 4, -4), RW=(1.7, -.25, -1.2), RE=(3, -.5, 1), RightHand=(-15, 0, 0), **HELD),
    ]},
    # looking a little down with the mouse held: no crouch - you keep running upright, the right shoulder
    # drops as you lean into the weight and the straight arm drives it down and back into the ground
    # beside you, juddering with the drag. Upper body only, like "hold".
    {"name": "scrape", "loop": True, "parts": ["UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand"], "keys": [
        k(0, UpperTorso=(-20, -14, -18), Head=(18, 10, 14), RW=(1.75, -1.75, -.75), RE=(3, .5, 2), RightHand=(-30, 0, 0), **RAKED),
        k(.12, UpperTorso=(-22, -15, -20), Head=(20, 11, 16), RW=(1.8, -1.9, -.6), RE=(3, .5, 2), RightHand=(-32, 0, 0), **RAKED),
        k(.24, UpperTorso=(-19, -13, -17), Head=(17, 10, 13), RW=(1.7, -1.7, -.85), RE=(3, .5, 2), RightHand=(-28, 0, 0), **RAKED),
        k(.36, UpperTorso=(-20, -14, -18), Head=(18, 10, 14), RW=(1.75, -1.75, -.75), RE=(3, .5, 2), RightHand=(-30, 0, 0), **RAKED),
    ]},
    # looking ahead, one click: swing it down and back, heave it up over your head and let go, chamber
    # the knee as it drops and drive a front kick through its chest (contact at 0.52 s)
    {"name": "punt", "loop": False, "keys": [
        k(0, UpperTorso=(0, 0, 5), RW=(1.95, 0, -.85), RE=(3, 0, 1), RA=STAND_RA, LA=STAND_LA, RK=KNEE_R, LK=KNEE_L, **HELD),
        k(.14, drop=(0, -.55, 0), LowerTorso=(-8, 0, 0), UpperTorso=(-18, -12, 4), Head=(14, 8, 0),
          RW=(1.5, -1.7, .7), RE=(3, 0, 2), LW=(-1.3, -.6, -1.3), LE=(-3, 0, 1),
          RA=STAND_RA, LA=STAND_LA, RK=KNEE_R, LK=KNEE_L, **HELD),
        k(.3, drop=(0, .1, 0), LowerTorso=(4, 0, 0), UpperTorso=(10, 8, 0), Head=(-6, 0, 0),
          RW=(.95, 1.75, -1.45), RE=(3, 1, .5), LW=(-1.6, -.2, -.6), LE=(-3, 0, 1),
          RA=(.5, -2.85, .05), LA=STAND_LA, RK=KNEE_R, LK=KNEE_L, dummy=(.7, 2.6, -2.3)),
        k(.42, drop=(0, -.15, 0), LowerTorso=(6, 0, 0), UpperTorso=(12, 0, -4), Head=(-10, 0, 0),
          RW=(2.3, .1, .4), RE=(3, 0, 2), LW=(-2.2, 0, -.4), LE=(-3, 0, 1),
          RA=(.5, -1.5, -1.0), LA=(-.45, -2.93, .15), RK=(.6, -.2, -3), LK=KNEE_L, RightFoot=(25, 0, 0), dummy=(.6, .9, -2.8)),
        k(.52, drop=(0, -.1, 0), LowerTorso=(20, 0, 0), UpperTorso=(16, 0, -6), Head=(-16, 0, 0),
          RW=(2.4, -.2, .8), RE=(3, 0, 2), LW=(-2.1, .1, -.9), LE=(-3, 0, 1),
          RA=(.5, -.05, -2.05), LA=(-.45, -2.93, .2), RK=(.6, 1.2, -1.6), LK=KNEE_L, RightFoot=(45, 0, 0), dummy=(.5, .35, -2.9)),
        k(.68, drop=(0, -.3, 0), LowerTorso=(14, 0, 0), UpperTorso=(10, 0, -4), Head=(-10, 0, 0),
          RW=(2.0, -.8, .3), RE=(3, 0, 2), LW=(-1.8, -.6, -.6), LE=(-3, 0, 1),
          RA=(.5, -.45, -2.0), LA=(-.45, -2.93, .2), RK=(.6, .9, -1.7), LK=KNEE_L, RightFoot=(35, 0, 0), dummy=None),
        k(.95, RW=(1.55, -1.05, -.15), RE=(3, 0, 2), LW=(-1.55, -1.05, -.15), LE=(-3, 0, 1),
          RA=STAND_RA, LA=STAND_LA, RK=KNEE_R, LK=KNEE_L, dummy=None),
    ]},
]
