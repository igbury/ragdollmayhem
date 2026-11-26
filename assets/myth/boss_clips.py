# The bosses' keyed clips, as poses for anim_bosses.py. Angles in degrees, Roblox rig space at scale 1:
#   root / waist / neck (x, y, z): x+ leans back (looks up), y+ turns to its own left, z+ tilts to its own left
#   la / ra (fwd, out, twist, elbow, wrist): fwd+ swings the arm forward and up, out+ away from the body,
#       elbow+ bends the forearm forward, wrist+ curls the fist
#   ll / rl (fwd, out, knee, ankle): fwd+ swings the thigh forward, knee+ bends the knee; the ankle keeps the
#       sole flat by itself and `ankle` adds to that (+ toes up)
#   pos (x, y, z) studs: moves the hips (z- forward); lift adds height on top of the automatic grounding (the
#       lowest sole stays on the floor unless ground=False)
# A clip: {"len": seconds or None (the last key), "loop": bool, "keys": [(seconds, spec, ease)], "drag": {joint: frames},
# "sections": {...}}. `ease` is how the curve comes INTO that key:
#   smooth (Bezier), fast (accelerates in: a blow landing), snap (bursts out, settles), back (overshoots),
#   elastic (rings: metal), step (holds, then jumps), lin
# Additive clips (Hit) hold offsets from the pose under them: ground and the sole keeping are off.

FPS = 30


def D(base, **kw):
    out = dict(base)
    for k, v in kw.items():
        if k in ("arms",):
            out["la"] = out["ra"] = v
        elif k == "legs":
            out["ll"] = out["rl"] = v
        else:
            out[k] = v
    return out


def S(**kw):
    return D({}, **kw)


def mirror(spec):
    """The same pose on the other side."""
    out = dict(spec)
    for a, b in (("la", "ra"), ("ll", "rl")):
        out[a], out[b] = spec.get(b), spec.get(a)
        if out[a] is None:
            del out[a]
        if out[b] is None:
            del out[b]
    for k in ("root", "waist", "neck"):
        if k in spec:
            x, y, z = spec[k]
            out[k] = (x, -y, -z)
    if "pos" in spec:
        x, y, z = spec["pos"]
        out["pos"] = (-x, y, z)
    return out


def shake(base, t0, t1, every, jitter, ease="lin"):
    """A tremble held from t0 to t1: alternate small offsets on waist and neck."""
    keys, t, i = [], t0, 0
    while t < t1 - 1e-6:
        s = 1 if i % 2 == 0 else -1
        k = dict(base)
        for j in ("waist", "neck"):
            x, y, z = base.get(j, (0, 0, 0))
            k[j] = (x + s * jitter * 0.6, y + s * jitter * 0.4, z - s * jitter)
        keys.append((t, k, ease))
        t += every
        i += 1
    return keys


def cycle(half, length):
    """A walk from its first half: (t, spec, ease) over [0, length/2) mirrored onto the second half."""
    keys = list(half)
    for t, spec, ease in half:
        keys.append((t + length / 2, mirror(spec), ease))
    return sorted(keys, key=lambda k: k[0])


ZERO = S()

# ------------------------------------------------------------------------------------------ Cyclops
# A lumbering brute: slow, heavy, top-heavy. Long anticipations, big drag on the arms and head, the fists
# swinging like wrecking balls, a waddle side to side.
CY_IDLE = S(waist=(-14, 0, 0), neck=(16, 0, 0), arms=(6, 10, 0, 18, 0), legs=(12, 6, 22, 0))
CY_CAGED = D(CY_IDLE, waist=(-20, 0, 0), neck=(4, 0, 0), la=(-14, 22, 0, 14, 0), ra=(-14, 22, 0, 14, 0),
             ll=(10, 9, 20, 0), rl=(10, 9, 20, 0))


def cyclops():
    c = {}
    I, C = CY_IDLE, CY_CAGED
    c["Idle"] = {"len": 3.0, "loop": True, "drag": {"Neck": 4, "LeftElbow": 3, "RightElbow": 3, "LeftWrist": 5, "RightWrist": 5}, "keys": [
        (0.0, I, "smooth"),
        (1.0, D(I, waist=(-10, 0, 2), neck=(13, 8, 0), la=(4, 13, 0, 16, 0), ra=(4, 13, 0, 16, 0)), "smooth"),
        (1.5, D(I, waist=(-11, 3, 2), neck=(11, 16, -3), la=(4, 13, 0, 16, 0), ra=(4, 13, 0, 16, 0)), "smooth"),
        (2.3, D(I, waist=(-17, -2, -1), neck=(18, -6, 2), la=(8, 9, 0, 22, 0), ra=(8, 9, 0, 22, 0),
                ll=(13, 6, 25, 0), rl=(13, 6, 25, 0)), "smooth"),
    ]}
    # contact, down, passing, up for the right foot; the left mirrors it
    L = 4 / 3
    stride = [
        (0.0, D(I, root=(0, 8, 0), waist=(-16, -14, 0), neck=(16, 6, 0), pos=(0.15, 0, 0),
                ra=(-22, 12, 0, 14, 0), la=(26, 10, 0, 34, 0), rl=(26, 7, 4, 12), ll=(-18, 5, 18, -10)), "smooth"),
        (5 / 30, D(I, root=(0, 6, -5), waist=(-19, -10, 4), neck=(19, 4, -4), pos=(0.35, 0, 0),
                   ra=(-14, 12, 0, 18, 0), la=(20, 10, 0, 30, 0), rl=(14, 7, 24, 0), ll=(-24, 5, 44, -15)), "smooth"),
        (10 / 30, D(I, root=(0, 0, -4), waist=(-15, 0, 3), neck=(16, 0, -3), pos=(0.4, 0, 0),
                    ra=(4, 11, 0, 18, 0), la=(4, 11, 0, 22, 0), rl=(0, 7, 10, 0), ll=(10, 5, 68, 8)), "smooth"),
        (15 / 30, D(I, root=(0, -5, -2), waist=(-13, 8, 1), neck=(14, -4, -1), pos=(0.25, 0, 0), lift=0.12,
                    ra=(18, 11, 0, 28, 0), la=(-12, 11, 0, 16, 0), rl=(-14, 7, 6, 0), ll=(24, 5, 34, 6)), "smooth"),
    ]
    c["Walk"] = {"len": L, "loop": True, "drag": {"Neck": 2, "LeftElbow": 2, "RightElbow": 2, "LeftWrist": 4, "RightWrist": 4},
                 "keys": cycle(stride, L)}
    c["Caged"] = {"len": 6.0, "loop": True, "drag": {"Neck": 3, "LeftWrist": 3, "RightWrist": 3}, "keys": [
        (0.0, C, "smooth"),
        (1.3, D(C, waist=(-19, -5, 0), neck=(2, -14, 4)), "smooth"),
        (2.7, C, "smooth"),
        (3.3, D(C, waist=(-13, 0, 0), neck=(10, 0, 0), la=(-18, 24, 0, 10, 0), ra=(-18, 24, 0, 10, 0)), "smooth"),
        (3.75, D(C, waist=(-31, 0, 0), neck=(26, 0, 0), la=(-6, 19, 0, 32, 0), ra=(-6, 19, 0, 32, 0),
                 ll=(12, 9, 27, 0), rl=(12, 9, 27, 0)), "fast"),
        *shake(D(C, waist=(-30, 0, 0), neck=(24, 0, 0), la=(-6, 19, 0, 32, 0), ra=(-6, 19, 0, 32, 0),
                 ll=(12, 9, 27, 0), rl=(12, 9, 27, 0)), 3.9, 4.3, 0.1, 2.5),
        (4.5, D(C, waist=(-25, 0, 0), neck=(-6, 0, 0)), "smooth"),
        (5.1, D(C, neck=(0, 8, 0)), "smooth"),
    ]}
    roar_up = D(I, waist=(14, 0, 0), neck=(34, 0, 0), la=(34, 52, -30, 88, 20), ra=(34, 52, -30, 88, 20), legs=(10, 10, 16, 0))
    c["Roar"] = {"len": 1.8, "loop": False, "drag": {"Neck": 2, "LeftElbow": 2, "RightElbow": 2}, "keys": [
        (0.0, C, "smooth"),
        (0.33, D(C, waist=(-32, 0, 0), neck=(-10, 0, 0), la=(-6, 8, 0, 52, 0), ra=(-6, 8, 0, 52, 0),
                 ll=(14, 9, 32, 0), rl=(14, 9, 32, 0)), "smooth"),
        (0.5, roar_up, "snap"),
        (0.62, D(roar_up, waist=(17, 0, 0), neck=(38, 0, 0), la=(38, 56, -34, 96, 24), ra=(38, 56, -34, 96, 24)), "back"),
        *shake(D(roar_up, waist=(15, 0, 0), neck=(35, 0, 0)), 0.72, 1.42, 0.08, 2.5),
        (1.55, D(C, waist=(-6, 0, 0), neck=(12, 0, 0), la=(16, 30, 0, 20, 0), ra=(16, 30, 0, 20, 0)), "smooth"),
        (1.8, C, "smooth"),
    ]}
    strain = D(C, waist=(-34, 0, 0), neck=(20, 0, 0), la=(-2, 18, 0, 42, 0), ra=(-2, 18, 0, 42, 0), legs=(14, 9, 30, 0))
    burst = D(I, waist=(14, 0, 0), neck=(30, 0, 0), la=(66, 72, -16, 24, 0), ra=(66, 72, -16, 24, 0), legs=(8, 8, 12, 0), lift=0.35)
    c["ChainBreak"] = {"len": 2.4, "loop": False, "drag": {"Neck": 2, "LeftElbow": 2, "RightElbow": 2, "LeftWrist": 3, "RightWrist": 3}, "keys": [
        (0.0, C, "smooth"),
        (0.2, D(C, waist=(-12, 0, 0), neck=(8, 0, 0), la=(-20, 24, 0, 12, 0), ra=(-20, 24, 0, 12, 0), legs=(12, 9, 24, 0)), "smooth"),
        (0.4, strain, "smooth"),
        *shake(strain, 0.44, 0.5, 0.05, 3),
        (0.6, burst, "snap"),  # the chains snap (Monsters CHAIN_SNAP)
        (0.72, D(burst, waist=(18, 0, 0), neck=(36, 0, 0), la=(70, 76, -20, 30, 0), ra=(70, 76, -20, 30, 0), lift=0), "back"),
        (0.92, D(I, waist=(6, 8, 0), neck=(22, 0, 0), ra=(72, 10, 0, 110, 0), la=(60, 40, 0, 30, 0)), "smooth"),
        (1.05, D(I, waist=(10, 4, 0), neck=(22, 0, 0), ra=(44, -18, 0, 122, 0), la=(60, 40, 0, 30, 0)), "fast"),  # thump
        (1.2, D(I, waist=(6, -8, 0), neck=(22, 0, 0), la=(72, 10, 0, 110, 0), ra=(52, 30, 0, 40, 0)), "smooth"),
        (1.33, D(I, waist=(10, -4, 0), neck=(22, 0, 0), la=(44, -18, 0, 122, 0), ra=(52, 30, 0, 40, 0)), "fast"),  # thump
        (1.5, D(I, waist=(-22, 0, 0), neck=(-6, 0, 0), la=(10, 20, 0, 62, 0), ra=(10, 20, 0, 62, 0), legs=(14, 7, 32, 0)), "smooth"),
        (1.62, D(I, waist=(14, 0, 0), neck=(38, 0, 0), la=(36, 70, 0, 30, 10), ra=(36, 70, 0, 30, 10), legs=(10, 8, 14, 0)), "snap"),
        *shake(D(I, waist=(14, 0, 0), neck=(36, 0, 0), la=(36, 70, 0, 30, 10), ra=(36, 70, 0, 30, 10), legs=(10, 8, 14, 0)), 1.72, 2.05, 0.08, 2.5),
        (2.2, D(I, waist=(-8, 0, 0), neck=(14, 0, 0), la=(10, 14, 0, 20, 0), ra=(10, 14, 0, 20, 0)), "smooth"),
        (2.4, I, "smooth"),
    ]}
    # The SLAM: windup 1.25 s, the blow lands as the strike starts, recovery 2.1 s (Mythology.Cyclops).
    W, ST, R = 1.25, 0.2, 2.1
    hit = D(I, waist=(-44, 14, 4), neck=(12, 8, 0), ra=(72, 8, 0, 2, 0), la=(-22, 30, 0, 30, 0),
            ll=(30, 8, 42, 0), rl=(-8, 6, 30, 0))
    c["Attack"] = {"len": W + ST + R, "loop": False, "sections": {"Windup": W, "Strike": ST},
                   "drag": {"Neck": 2, "LeftElbow": 2, "LeftWrist": 3, "RightWrist": 2}, "keys": [
        (0.0, I, "smooth"),
        (0.27, D(I, waist=(-22, 12, 0), neck=(20, 6, 0), ra=(-32, 20, 0, 32, 0), legs=(14, 6, 27, 0)), "smooth"),
        (0.8, D(I, waist=(14, -22, -6), neck=(22, -10, 0), ra=(150, 22, 0, 42, 0), la=(30, 30, 0, 20, 0),
                ll=(22, 8, 16, 0), rl=(4, 6, 18, 0)), "smooth"),
        (1.12, D(I, waist=(18, -26, -8), neck=(26, -8, 0), ra=(166, 16, 10, 58, 0), la=(34, 32, 0, 18, 0),
                 ll=(24, 8, 14, 0), rl=(2, 6, 16, 0), lift=0.15), "smooth"),
        (1.28, hit, "fast"),
        (1.36, D(hit, waist=(-48, 16, 5), ll=(32, 8, 48, 0), rl=(-8, 6, 34, 0)), "back"),
        (1.75, D(hit, waist=(-45, 15, 4), ra=(70, 9, 0, 6, 0)), "smooth"),
        (2.05, D(hit, waist=(-40, 12, 3), neck=(4, -14, 0), ra=(66, 10, 0, 10, 0)), "smooth"),
        (2.6, D(I, waist=(-24, 6, 2), neck=(16, 0, 0), ra=(30, 14, 0, 30, 0), la=(0, 14, 0, 20, 0),
                ll=(18, 7, 26, 0)), "smooth"),
        (3.05, D(I, waist=(-16, 0, 0), ll=(12, 6, 22, 0)), "smooth"),
        (W + ST + R, I, "smooth"),
    ]}
    slam = D(I, waist=(-50, 0, 0), neck=(8, 0, 0), la=(80, 10, 0, 0, 0), ra=(80, 10, 0, 0, 0), legs=(26, 12, 44, 0))
    c["HeavyAttack"] = {"len": W + ST + R, "loop": False, "sections": {"Windup": W, "Strike": ST},
                        "drag": {"Neck": 2, "LeftWrist": 3, "RightWrist": 3}, "keys": [
        (0.0, I, "smooth"),
        (0.27, D(I, waist=(-26, 0, 0), neck=(18, 0, 0), la=(-26, 14, 0, 42, 0), ra=(-26, 14, 0, 42, 0), legs=(16, 7, 32, 0)), "smooth"),
        (0.85, D(I, waist=(18, 0, 0), neck=(24, 0, 0), la=(160, 8, 0, 62, 0), ra=(160, 8, 0, 62, 0), legs=(8, 7, 12, 0), lift=0.45), "smooth"),
        (1.13, D(I, waist=(22, 0, 0), neck=(28, 0, 0), la=(170, 4, 0, 72, 0), ra=(170, 4, 0, 72, 0), legs=(6, 7, 10, 0), lift=0.7), "smooth"),
        (1.28, slam, "fast"),
        (1.36, D(slam, waist=(-54, 0, 0), legs=(28, 12, 50, 0)), "back"),
        *shake(D(slam, waist=(-52, 0, 0), legs=(28, 12, 48, 0)), 1.5, 1.9, 0.07, 1.8),
        (2.2, D(slam, waist=(-44, 0, 0), neck=(18, 0, 0)), "smooth"),
        (2.75, D(I, waist=(-22, 0, 0), la=(20, 16, 0, 30, 0), ra=(20, 16, 0, 30, 0), legs=(14, 7, 28, 0)), "smooth"),
        (W + ST + R, I, "smooth"),
    ]}
    # EAT: both fists up at the mouth, a bite every 0.7 s from 0.5 s (Monsters EAT_TIME 3.2, BITE_EVERY 0.7)
    hold = D(I, waist=(-6, 0, 0), neck=(4, 0, 0), la=(66, -4, 0, 52, 0), ra=(66, -4, 0, 52, 0))
    keys = [(0.0, I, "smooth"), (0.3, hold, "smooth")]
    for b in (0.5, 1.2, 1.9, 2.6):
        keys += [(b - 0.12, D(hold, neck=(16, 0, 0), waist=(-2, 0, 0)), "smooth"),
                 (b, D(hold, neck=(-14, 0, 0), waist=(-12, 0, 0), la=(60, -4, 0, 48, 0), ra=(60, -4, 0, 48, 0)), "fast"),
                 (b + 0.18, D(hold, neck=(2, 4, 0)), "back")]
    keys += [(3.0, D(I, la=(50, 10, 0, 40, 0), ra=(50, 10, 0, 40, 0)), "smooth"), (3.2, I, "smooth")]
    c["Eat"] = {"len": 3.2, "loop": False, "drag": {"Neck": 1}, "keys": keys}
    c["Stun"] = {"len": 1.6, "loop": False, "drag": {"Neck": 3, "LeftWrist": 4, "RightWrist": 4}, "keys": [
        (0.0, I, "smooth"),
        (0.12, D(I, waist=(8, 0, 0), neck=(30, 0, 0), la=(22, 30, 0, 10, 0), ra=(22, 30, 0, 10, 0)), "snap"),
        (0.4, D(I, waist=(-20, 10, 8), neck=(-10, 20, 14), la=(0, 8, 0, 8, 0), ra=(0, 8, 0, 8, 0), legs=(14, 6, 32, 0)), "smooth"),
        (0.72, D(I, root=(0, 0, 5), waist=(-22, -10, -8), neck=(-14, -22, -16), la=(0, 8, 0, 8, 0), ra=(0, 8, 0, 8, 0), legs=(14, 6, 32, 0)), "smooth"),
        (1.05, D(I, root=(0, 0, -5), waist=(-20, 10, 8), neck=(-10, 20, 14), la=(0, 8, 0, 8, 0), ra=(0, 8, 0, 8, 0), legs=(14, 6, 32, 0)), "smooth"),
        (1.3, D(I, neck=(8, -18, 0)), "smooth"),
        (1.42, D(I, neck=(8, 18, 0)), "smooth"),
        (1.6, I, "smooth"),
    ]}
    c["Hit"] = {"len": 0.5, "loop": False, "additive": True, "keys": [
        (0.0, ZERO, "smooth"),
        (0.08, S(waist=(12, 0, -4), neck=(22, 8, 0), la=(-14, 6, 0, -10, 0), ra=(-14, 6, 0, -10, 0)), "snap"),
        (0.26, S(waist=(-3, 0, 1), neck=(-6, 0, 0)), "back"),
        (0.5, ZERO, "smooth"),
    ]}
    sit = D(I, waist=(4, 0, 0), neck=(-14, 0, 10), la=(20, 40, 0, 20, 0), ra=(20, 40, 0, 20, 0),
            ll=(80, 14, 40, 0), rl=(80, 14, 40, 0), pos=(0, -3.9, 0.6), ground=False)
    c["Defeat"] = {"len": 1.4, "loop": False, "drag": {"Neck": 3, "LeftWrist": 3, "RightWrist": 3}, "keys": [
        (0.0, I, "smooth"),
        (0.2, D(I, waist=(-10, 0, 10), neck=(-6, 0, 18), la=(10, 30, 0, 10, 0), ra=(10, 30, 0, 10, 0)), "smooth"),
        (0.45, D(I, root=(0, 0, -6), waist=(-6, 0, -12), neck=(0, 0, -18), la=(10, 30, 0, 10, 0), ra=(10, 30, 0, 10, 0)), "smooth"),
        (0.8, D(sit, pos=(0, -4.1, 0.6)), "fast"),
        (0.93, D(sit, pos=(0, -3.6, 0.6), neck=(24, 0, 0), la=(60, 40, 0, 20, 0), ra=(60, 40, 0, 20, 0)), "snap"),
        (1.12, sit, "smooth"),
        (1.4, D(sit, neck=(-18, 0, -10)), "smooth"),
    ]}
    crouch = D(I, waist=(-40, 0, 0), neck=(-8, 0, 0), la=(40, 25, 0, 30, 0), ra=(40, 25, 0, 30, 0), legs=(46, 10, 92, 0))
    c["Spawn"] = {"len": 1.5, "loop": False, "drag": {"Neck": 2, "LeftWrist": 3, "RightWrist": 3}, "keys": [
        (0.0, crouch, "smooth"),
        (0.45, D(crouch, waist=(-46, 0, 0), neck=(22, 0, 0)), "smooth"),
        (0.85, D(I, waist=(-10, 0, 0), neck=(24, 0, 0), la=(-10, 30, 0, 20, 0), ra=(-10, 30, 0, 20, 0), legs=(10, 8, 18, 0), lift=0.3), "snap"),
        (1.05, D(C, waist=(-26, 0, 0), legs=(12, 9, 26, 0)), "back"),
        (1.5, C, "smooth"),
    ]}
    return c


# ------------------------------------------------------------------------------------------ Minotaur
# A bull: twitchy and aggressive. Head low with the horns forward, a snorting toss, short quick steps with a
# bounce, fists up; fast attacks, little drag but sharp overshoots.
MI_IDLE = S(waist=(-18, 0, 0), neck=(8, 0, 0), la=(16, 14, 0, 62, 0), ra=(16, 14, 0, 62, 0), ll=(14, 8, 26, 0), rl=(14, 8, 26, 0))
MI_CAGED = D(MI_IDLE, waist=(-24, 0, 0), neck=(-6, 0, 0), la=(-16, 24, 0, 20, 0), ra=(-16, 24, 0, 20, 0), legs=(10, 9, 22, 0))


def minotaur():
    c = {}
    I, C = MI_IDLE, MI_CAGED
    c["Idle"] = {"len": 2.0, "loop": True, "drag": {"Neck": 1}, "keys": [
        (0.0, I, "smooth"),
        (0.3, D(I, waist=(-21, 0, 0), neck=(-8, 0, 0)), "smooth"),  # snort: head dips
        (0.42, D(I, neck=(16, 0, 0)), "snap"),  # and tosses
        (0.65, D(I, neck=(6, -12, 0)), "smooth"),
        (1.0, D(I, waist=(-14, 0, 0), la=(12, 16, 0, 66, 0), ra=(12, 16, 0, 66, 0)), "smooth"),
        (1.35, D(I, neck=(4, 14, 0), root=(0, 0, 3), pos=(-0.2, 0, 0)), "smooth"),
        (1.7, D(I, root=(0, 0, -2), pos=(0.1, 0, 0)), "smooth"),
    ]}
    L = 0.8
    trot = [
        (0.0, D(I, root=(0, 9, 0), waist=(-26, -12, 0), neck=(16, 6, 0), la=(36, 14, 0, 80, 0), ra=(-24, 14, 0, 60, 0),
                rl=(28, 8, 6, 12), ll=(-20, 8, 22, -10)), "smooth"),
        (3 / 30, D(I, root=(0, 7, -4), waist=(-30, -8, 3), neck=(20, 4, -3), la=(26, 14, 0, 76, 0), ra=(-14, 14, 0, 62, 0),
                   rl=(14, 8, 30, 0), ll=(-24, 8, 52, -15), pos=(0.2, 0, 0)), "smooth"),
        (6 / 30, D(I, root=(0, 0, -3), waist=(-26, 0, 2), neck=(16, 0, -2), arms=(6, 14, 0, 70, 0),
                   rl=(0, 8, 12, 0), ll=(12, 8, 76, 8), pos=(0.25, 0, 0)), "smooth"),
        (9 / 30, D(I, root=(0, -6, -1), waist=(-23, 8, 1), neck=(13, -4, -1), la=(-14, 14, 0, 60, 0), ra=(24, 14, 0, 76, 0),
                   rl=(-16, 8, 6, 0), ll=(26, 8, 34, 8), lift=0.45, pos=(0.1, 0, 0)), "smooth"),
    ]
    c["Walk"] = {"len": L, "loop": True, "drag": {"Neck": 1, "LeftWrist": 1, "RightWrist": 1}, "keys": cycle(trot, L)}
    thrash = D(C, waist=(-30, 0, 0), neck=(-12, 26, 0), la=(-8, 22, 0, 34, 0), ra=(-8, 22, 0, 34, 0))
    c["Caged"] = {"len": 6.0, "loop": True, "drag": {"Neck": 1}, "keys": [
        (0.0, C, "smooth"),
        (1.2, D(C, waist=(-22, 0, 0), neck=(-2, 0, 0)), "smooth"),
        (2.4, C, "smooth"),
        (2.9, D(C, neck=(-16, 0, 0), waist=(-28, 0, 0)), "smooth"),
        (3.05, thrash, "snap"),
        (3.25, D(thrash, neck=(-12, -26, 0)), "snap"),
        (3.45, thrash, "snap"),
        (3.65, D(thrash, neck=(-12, -26, 0)), "snap"),
        (3.95, D(C, rl=(30, 9, 62, 10)), "smooth"),  # a hoof up...
        (4.1, C, "fast"),  # ...and down: STOMP
        (4.2, D(C, waist=(-27, 0, 0)), "back"),
        (4.9, D(C, neck=(4, 10, 0)), "smooth"),
    ]}
    rear = D(I, waist=(20, 0, 0), neck=(34, 0, 0), la=(110, 40, 0, 50, 0), ra=(110, 40, 0, 50, 0), legs=(6, 8, 10, 0))
    c["Roar"] = {"len": 1.8, "loop": False, "drag": {"Neck": 1}, "keys": [
        (0.0, C, "smooth"),
        (0.3, D(C, waist=(-34, 0, 0), neck=(-18, 0, 0), legs=(14, 9, 34, 0)), "smooth"),
        (0.45, rear, "snap"),
        (0.55, D(rear, waist=(24, 0, 0), neck=(40, 0, 0)), "back"),
        *shake(D(rear, waist=(22, 0, 0), neck=(38, 0, 0)), 0.65, 1.4, 0.07, 3),
        (1.55, D(C, waist=(-14, 0, 0), neck=(8, 0, 0)), "smooth"),
        (1.8, C, "smooth"),
    ]}
    pull = D(C, waist=(-40, 0, 0), neck=(-18, 0, 0), la=(-24, 20, 0, 24, 0), ra=(-24, 20, 0, 24, 0), legs=(22, 10, 34, 0))
    c["ChainBreak"] = {"len": 2.4, "loop": False, "drag": {"Neck": 1, "LeftWrist": 1, "RightWrist": 1}, "keys": [
        (0.0, C, "smooth"),
        (0.25, pull, "smooth"),
        *shake(pull, 0.3, 0.48, 0.05, 3.5),
        (0.6, rear, "snap"),
        (0.68, D(rear, waist=(26, 0, 0), neck=(42, 0, 0), lift=0.6), "back"),
        (0.85, D(I, rl=(34, 8, 66, 12)), "smooth"),
        (0.97, D(I, waist=(-24, 0, 0)), "fast"),  # stomp
        (1.1, D(I, ll=(34, 8, 66, 12)), "smooth"),
        (1.22, D(I, waist=(-24, 0, 0)), "fast"),  # stomp
        (1.38, D(I, waist=(-30, 0, 0), neck=(-16, 0, 0)), "smooth"),
        (1.5, D(I, waist=(16, 0, 0), neck=(36, 22, 0), la=(70, 50, 0, 60, 0), ra=(70, 50, 0, 60, 0)), "snap"),
        (1.68, D(I, waist=(16, 0, 0), neck=(36, -22, 0), la=(70, 50, 0, 60, 0), ra=(70, 50, 0, 60, 0)), "snap"),
        *shake(D(I, waist=(16, 0, 0), neck=(38, 0, 0), la=(70, 50, 0, 60, 0), ra=(70, 50, 0, 60, 0)), 1.8, 2.1, 0.07, 3),
        (2.4, I, "smooth"),
    ]}
    # The CHARGE: windup 1.1 s (paws the ground), charge 0.85 s head down, recovery 2.6 s (Mythology.Minotaur)
    W, CH, R = 1.1, 0.85, 2.6
    low = D(I, waist=(-44, 0, 0), neck=(14, 0, 0), la=(-30, 20, 0, 70, 0), ra=(-30, 20, 0, 70, 0), legs=(24, 8, 40, 0))

    def gallop(t0, t1):
        keys, t, i = [], t0, 0
        while t < t1 - 1e-6:
            s = 1 if i % 2 == 0 else -1
            keys.append((t, D(low, root=(0, 6 * s, 0), waist=(-46, -6 * s, 0), la=(-30 + 30 * s, 20, 0, 70, 0), ra=(-30 - 30 * s, 20, 0, 70, 0),
                              rl=(24 + 26 * s, 8, 30 - 10 * s, 0), ll=(24 - 26 * s, 8, 30 + 30 * s, 0), lift=0.35 if i % 2 else 0), "smooth"))
            t += 0.14
            i += 1
        return keys

    windup = [
        (0.0, I, "smooth"),
        (0.18, D(I, waist=(-30, 0, 0), neck=(-6, 0, 0), rl=(18, 8, 40, 0)), "smooth"),
        (0.32, D(I, waist=(-30, 0, 0), rl=(-22, 8, 30, 6)), "fast"),  # paws back
        (0.45, D(I, waist=(-32, 0, 0), rl=(18, 8, 40, 0)), "smooth"),
        (0.6, D(I, waist=(-32, 0, 0), rl=(-22, 8, 30, 6)), "fast"),  # paws again
        (0.82, D(low, neck=(-10, 0, 0)), "smooth"),
        (W, D(low, waist=(-48, 0, 0), legs=(28, 8, 52, 0)), "smooth"),  # coiled
    ]
    recover = [
        (W + CH + 0.08, D(I, waist=(4, 0, 0), neck=(26, 0, 0), la=(50, 40, 0, 30, 0), ra=(50, 40, 0, 30, 0), ll=(40, 10, 10, 0), rl=(-10, 10, 30, 0)), "snap"),  # skid
        (W + CH + 0.25, D(I, waist=(-6, 0, 0), neck=(10, 0, 0)), "back"),
        (W + CH + 0.6, D(I, neck=(-6, 26, 10)), "smooth"),  # shakes the head
        (W + CH + 0.75, D(I, neck=(-6, -26, -10)), "smooth"),
        (W + CH + 0.9, D(I, neck=(-6, 22, 8)), "smooth"),
        (W + CH + 1.05, D(I, neck=(-6, -16, -6)), "smooth"),
        (W + CH + 1.4, D(I, waist=(-22, 0, 0), neck=(-10, 0, 0)), "smooth"),
        (W + CH + 1.55, D(I, neck=(16, 0, 0)), "snap"),  # snort
        (W + CH + R, I, "smooth"),
    ]
    c["Attack"] = {"len": W + CH + R, "loop": False, "sections": {"Windup": W, "Charge": CH}, "drag": {"Neck": 1},
                   "keys": windup + gallop(W + 0.06, W + CH) + recover}
    heavy_windup = [
        (0.0, I, "smooth"),
        (0.25, D(I, waist=(-30, 0, 0), neck=(-12, 0, 0), legs=(18, 8, 38, 0)), "smooth"),
        (0.6, D(rear, waist=(26, 0, 0), neck=(30, 0, 0), la=(150, 30, 0, 40, 0), ra=(150, 30, 0, 40, 0), rl=(40, 8, 70, 10), lift=0.4), "snap"),
        (0.82, D(rear, waist=(28, 0, 0), neck=(34, 0, 0), la=(156, 30, 0, 44, 0), ra=(156, 30, 0, 44, 0), rl=(44, 8, 74, 10), lift=0.5), "smooth"),
        (W, D(low, waist=(-50, 0, 0), legs=(28, 8, 52, 0)), "fast"),  # slams down into the charge
    ]
    c["HeavyAttack"] = {"len": W + CH + R, "loop": False, "sections": {"Windup": W, "Charge": CH}, "drag": {"Neck": 1},
                        "keys": heavy_windup + gallop(W + 0.06, W + CH) + recover}
    hold = D(I, waist=(-8, 0, 0), neck=(-2, 0, 0), la=(70, -4, 0, 56, 0), ra=(70, -4, 0, 56, 0))
    keys = [(0.0, I, "smooth"), (0.25, hold, "snap")]
    for b in (0.5, 1.2, 1.9, 2.6):
        keys += [(b - 0.1, D(hold, neck=(14, 0, 0)), "smooth"),
                 (b, D(hold, neck=(-16, 0, 0), waist=(-14, 0, 0)), "fast"),
                 (b + 0.1, D(hold, neck=(-8, 18, 0)), "snap"),  # worries it like a dog
                 (b + 0.2, D(hold, neck=(-8, -18, 0)), "snap"),
                 (b + 0.3, D(hold, neck=(0, 0, 0)), "smooth")]
    keys += [(3.0, D(I, la=(50, 10, 0, 50, 0), ra=(50, 10, 0, 50, 0)), "smooth"), (3.2, I, "smooth")]
    c["Eat"] = {"len": 3.2, "loop": False, "keys": keys}
    c["Stun"] = {"len": 1.6, "loop": False, "drag": {"Neck": 2}, "keys": [
        (0.0, I, "smooth"),
        (0.1, D(I, waist=(6, 0, 0), neck=(30, 0, 0)), "snap"),
        (0.35, D(I, root=(0, 0, 6), waist=(-12, 0, 10), neck=(0, 30, 12), arms=(10, 30, 0, 20, 0), legs=(14, 10, 30, 0)), "smooth"),
        (0.6, D(I, root=(0, 0, -6), waist=(-12, 0, -10), neck=(0, -30, -12), arms=(10, 30, 0, 20, 0), legs=(14, 10, 30, 0)), "smooth"),
        (0.85, D(I, root=(0, 0, 6), waist=(-12, 0, 10), neck=(0, 30, 12), arms=(10, 30, 0, 20, 0), legs=(14, 10, 30, 0)), "smooth"),
        (1.1, D(I, root=(0, 0, -4), waist=(-12, 0, -8), neck=(0, -20, -8), arms=(10, 30, 0, 20, 0), legs=(14, 10, 30, 0)), "smooth"),
        (1.35, D(I, neck=(-12, 0, 0)), "smooth"),
        (1.47, D(I, neck=(16, 0, 0)), "snap"),
        (1.6, I, "smooth"),
    ]}
    c["Hit"] = {"len": 0.5, "loop": False, "additive": True, "keys": [
        (0.0, ZERO, "smooth"),
        (0.07, S(waist=(10, -6, -3), neck=(18, -12, 0), la=(-10, 6, 0, -12, 0), ra=(-10, 6, 0, -12, 0)), "snap"),
        (0.22, S(waist=(-4, 2, 1), neck=(-8, 4, 0)), "back"),
        (0.5, ZERO, "smooth"),
    ]}
    knees = D(I, root=(0, 0, 0), waist=(-30, 0, 0), neck=(-20, 0, 0), la=(40, 20, 0, 20, 0), ra=(40, 20, 0, 20, 0),
              ll=(0, 10, 90, -40), rl=(0, 10, 90, -40), pos=(0, -2.6, 1.2), ground=False)
    c["Defeat"] = {"len": 1.4, "loop": False, "drag": {"Neck": 2}, "keys": [
        (0.0, I, "smooth"),
        (0.25, D(I, root=(0, 60, 0), neck=(0, 20, 12)), "smooth"),  # spins dizzy
        (0.5, D(I, root=(0, -30, 0), neck=(0, -20, -12)), "smooth"),
        (0.72, D(I, root=(0, 0, 0), neck=(-10, 0, 0), legs=(20, 10, 40, 0)), "smooth"),
        (0.92, knees, "fast"),
        (1.0, D(knees, pos=(0, -2.4, 1.2)), "back"),
        (1.4, D(knees, waist=(-46, 0, 0), neck=(-26, 0, 0), la=(70, 20, 0, 10, 0), ra=(70, 20, 0, 10, 0)), "smooth"),
    ]}
    c["Spawn"] = {"len": 1.5, "loop": False, "drag": {"Neck": 1}, "keys": [
        (0.0, D(knees, waist=(-46, 0, 0), neck=(-26, 0, 0), la=(70, 20, 0, 10, 0), ra=(70, 20, 0, 10, 0)), "smooth"),
        (0.4, D(knees, waist=(-36, 0, 0), neck=(20, 0, 0)), "smooth"),
        (0.62, D(I, waist=(-30, 0, 0), legs=(20, 9, 46, 0)), "snap"),
        (0.8, D(C, rl=(30, 9, 60, 10)), "smooth"),
        (0.92, C, "fast"),  # stomp
        (1.05, D(C, neck=(14, 0, 0)), "snap"),  # snort
        (1.5, C, "smooth"),
    ]}
    return c


# ------------------------------------------------------------------------------------------ Talos
# A bronze automaton: upright, deliberate, mechanical. Moves in ratcheting steps with holds, lands with a
# metallic ring (elastic), glitches when stunned; no organic drag at all.
TA_IDLE = S(waist=(-4, 0, 0), neck=(-8, 0, 0), la=(4, 12, 0, 14, 0), ra=(4, 12, 0, 14, 0), ll=(4, 7, 8, 0), rl=(4, 7, 8, 0))
TA_CAGED = D(TA_IDLE, waist=(-10, 0, 0), neck=(-24, 0, 0), la=(-12, 20, 0, 6, 0), ra=(-12, 20, 0, 6, 0), legs=(6, 8, 12, 0))


def talos():
    c = {}
    I, C = TA_IDLE, TA_CAGED
    c["Idle"] = {"len": 4.0, "loop": True, "keys": [
        (0.0, I, "smooth"),
        (0.6, I, "smooth"),
        (0.75, D(I, neck=(-8, 24, 0)), "snap"),  # a sharp scan left
        (1.6, D(I, neck=(-8, 22, 0), waist=(-3, 0, 0)), "smooth"),
        (1.75, D(I, neck=(-8, -24, 0)), "snap"),
        (2.7, D(I, neck=(-8, -22, 0), waist=(-5, 0, 0)), "smooth"),
        (2.85, D(I, neck=(-8, 0, 0)), "snap"),
        (3.3, D(I, waist=(-2, 0, 0), la=(4, 13, 0, 14, 0), ra=(4, 13, 0, 14, 0)), "smooth"),  # a pulse through the core
    ]}
    L = 1.6
    stomp = [
        (0.0, D(I, root=(0, 4, 0), waist=(-4, -5, 0), la=(-14, 12, 0, 16, 0), ra=(14, 12, 0, 20, 0),
                rl=(20, 7, 2, 6), ll=(-14, 7, 6, -6)), "smooth"),
        (4 / 30, D(I, root=(0, 4, -3), waist=(-6, -5, 2), la=(-12, 12, 0, 16, 0), ra=(12, 12, 0, 20, 0),
                   rl=(16, 7, 10, 0), ll=(-16, 7, 16, -6), lift=-0.12, pos=(0.15, 0, 0)), "fast"),  # the thud
        (8 / 30, D(I, root=(0, 3, -3), waist=(-4, -4, 2), la=(-10, 12, 0, 16, 0), ra=(10, 12, 0, 20, 0),
                   rl=(12, 7, 6, 0), ll=(-12, 7, 34, -8), pos=(0.2, 0, 0)), "elastic"),
        (14 / 30, D(I, root=(0, 0, -2), waist=(-4, 0, 1), arms=(0, 12, 0, 16, 0),
                    rl=(0, 7, 4, 0), ll=(6, 7, 52, 6), pos=(0.22, 0, 0)), "smooth"),
        (19 / 30, D(I, root=(0, -3, -1), waist=(-4, 4, 0), la=(10, 12, 0, 20, 0), ra=(-10, 12, 0, 16, 0),
                    rl=(-12, 7, 4, 0), ll=(20, 7, 18, 6), lift=0.08, pos=(0.1, 0, 0)), "smooth"),
    ]
    c["Walk"] = {"len": L, "loop": True, "keys": cycle(stomp, L)}
    surge = D(C, waist=(-2, 0, 0), neck=(10, 0, 0), la=(-4, 26, 0, 16, 0), ra=(-4, 26, 0, 16, 0), legs=(5, 8, 8, 0))
    c["Caged"] = {"len": 6.0, "loop": True, "keys": [
        (0.0, C, "smooth"),
        (2.5, D(C, neck=(-22, 0, 0)), "smooth"),
        (2.6, surge, "step"),  # power surge: snaps awake
        (2.7, D(surge, neck=(8, 6, 0)), "step"),
        (2.8, D(surge, neck=(10, -6, 0)), "step"),
        (2.9, surge, "step"),
        (3.6, D(surge, neck=(6, 0, 0)), "smooth"),
        (3.9, D(C, neck=(-10, 0, 0)), "step"),  # winds down in steps
        (4.2, D(C, neck=(-18, 0, 0), waist=(-8, 0, 0)), "step"),
        (4.5, C, "step"),
        (5.4, C, "smooth"),
    ]}
    # Power up: chest out, forearms up and in, fists clenched by the head (not a T-pose).
    power = D(I, waist=(12, 0, 0), neck=(22, 0, 0), la=(40, 58, -26, 92, 16), ra=(40, 58, -26, 92, 16), legs=(4, 10, 10, 0))
    c["Roar"] = {"len": 1.8, "loop": False, "keys": [
        (0.0, C, "smooth"),
        (0.25, D(C, neck=(-30, 0, 0), waist=(-14, 0, 0)), "smooth"),
        (0.35, D(C, neck=(6, 0, 0)), "step"),
        (0.45, D(power, la=(26, 50, -12, 40, 6), ra=(26, 50, -12, 40, 6)), "smooth"),
        (0.55, power, "elastic"),
        *shake(power, 0.7, 1.45, 0.05, 1.2),
        (1.5, D(I, waist=(-6, 0, 0)), "smooth"),
        (1.8, C, "smooth"),
    ]}
    clang = D(I, waist=(-8, 0, 0), neck=(-4, 0, 0), la=(80, -30, 0, 70, 0), ra=(80, -30, 0, 70, 0))
    c["ChainBreak"] = {"len": 2.4, "loop": False, "keys": [
        (0.0, C, "smooth"),
        (0.12, D(C, waist=(-10, 12, 0), la=(-18, 20, 0, 10, 0)), "step"),  # ratchets against the chains
        (0.24, D(C, waist=(-10, -12, 0), ra=(-18, 20, 0, 10, 0)), "step"),
        (0.36, D(C, waist=(-14, 12, 0), la=(-22, 18, 0, 20, 0)), "step"),
        (0.48, D(C, waist=(-14, -12, 0), ra=(-22, 18, 0, 20, 0), neck=(-30, 0, 0)), "step"),
        (0.58, D(power, la=(40, 80, 0, 4, 0), ra=(40, 80, 0, 4, 0)), "snap"),  # BANG: the chains go
        (0.7, D(power, la=(36, 76, 0, 8, 0), ra=(36, 76, 0, 8, 0)), "elastic"),
        (1.0, D(I, la=(60, 40, 0, 60, 0), ra=(60, 40, 0, 60, 0)), "smooth"),
        (1.12, clang, "fast"),  # fists together: CLANG
        (1.22, D(I, la=(64, 30, 0, 64, 0), ra=(64, 30, 0, 64, 0)), "elastic"),
        (1.36, clang, "fast"),  # CLANG
        (1.46, D(clang, la=(76, -26, 0, 70, 0), ra=(76, -26, 0, 70, 0)), "elastic"),
        (1.7, D(power, neck=(18, 0, 0)), "smooth"),
        *shake(power, 1.8, 2.15, 0.05, 1.0),
        (2.4, I, "smooth"),
    ]}
    # The HAMMER: windup 1.6 s, the blow, recovery 2.4 s (Mythology.Talos). Raised in three ratchet steps.
    W, ST, R = 1.6, 0.2, 2.4
    smash = D(I, waist=(-36, 10, 4), neck=(-2, 6, 0), ra=(74, 6, 0, 4, 0), la=(-14, 24, 0, 20, 0), ll=(26, 8, 34, 0), rl=(-6, 8, 22, 0))
    c["Attack"] = {"len": W + ST + R, "loop": False, "sections": {"Windup": W, "Strike": ST}, "keys": [
        (0.0, I, "smooth"),
        (0.25, D(I, ra=(40, 18, 0, 40, 0), waist=(2, -6, 0)), "snap"),
        (0.5, D(I, ra=(42, 18, 0, 42, 0), waist=(2, -6, 0)), "smooth"),
        (0.62, D(I, ra=(95, 18, 0, 50, 0), waist=(6, -12, -2), neck=(-2, -4, 0)), "snap"),
        (0.9, D(I, ra=(97, 18, 0, 50, 0), waist=(6, -12, -2), neck=(-2, -4, 0)), "smooth"),
        (1.02, D(I, ra=(150, 16, 0, 56, 0), waist=(12, -18, -4), neck=(4, -6, 0), la=(24, 22, 0, 20, 0), ll=(14, 8, 10, 0)), "snap"),
        (1.5, D(I, ra=(154, 16, 0, 58, 0), waist=(13, -19, -4), neck=(6, -6, 0), la=(26, 22, 0, 20, 0), ll=(16, 8, 12, 0)), "smooth"),
        (1.63, smash, "fast"),
        (1.75, D(smash, waist=(-38, 10, 4)), "elastic"),
        *shake(smash, 1.9, 2.6, 0.05, 0.8),
        (2.9, D(smash, neck=(4, 0, 0)), "smooth"),
        (3.1, D(I, ra=(40, 12, 0, 30, 0), waist=(-14, 4, 2)), "step"),  # retracts in steps
        (3.4, D(I, ra=(18, 12, 0, 20, 0), waist=(-8, 2, 0)), "step"),
        (3.7, I, "step"),
        (W + ST + R, I, "smooth"),
    ]}
    pound = D(I, waist=(-42, 0, 0), neck=(-6, 0, 0), la=(78, -12, 0, 10, 0), ra=(78, -12, 0, 10, 0), legs=(24, 10, 40, 0))
    c["HeavyAttack"] = {"len": W + ST + R, "loop": False, "sections": {"Windup": W, "Strike": ST}, "keys": [
        (0.0, I, "smooth"),
        (0.3, D(I, la=(60, -10, 0, 60, 0), ra=(60, -10, 0, 60, 0)), "snap"),  # fists clasped
        (0.62, D(I, la=(64, -10, 0, 62, 0), ra=(64, -10, 0, 62, 0)), "smooth"),
        (0.75, D(I, la=(120, -12, 0, 50, 0), ra=(120, -12, 0, 50, 0), waist=(6, 0, 0)), "snap"),
        (1.05, D(I, la=(122, -12, 0, 50, 0), ra=(122, -12, 0, 50, 0), waist=(6, 0, 0)), "smooth"),
        (1.18, D(I, la=(168, -10, 0, 30, 0), ra=(168, -10, 0, 30, 0), waist=(14, 0, 0), neck=(8, 0, 0), lift=0.5), "snap"),
        (1.5, D(I, la=(170, -10, 0, 30, 0), ra=(170, -10, 0, 30, 0), waist=(15, 0, 0), neck=(10, 0, 0), lift=0.65), "smooth"),
        (1.63, pound, "fast"),
        (1.75, D(pound, waist=(-44, 0, 0)), "elastic"),
        *shake(pound, 1.9, 2.7, 0.05, 0.9),
        (3.0, D(pound, neck=(6, 0, 0)), "smooth"),
        (3.2, D(I, waist=(-20, 0, 0), la=(30, 10, 0, 30, 0), ra=(30, 10, 0, 30, 0), legs=(12, 8, 20, 0)), "step"),
        (3.5, D(I, waist=(-8, 0, 0)), "step"),
        (W + ST + R, I, "smooth"),
    ]}
    hold = D(I, waist=(-4, 0, 0), neck=(-4, 0, 0), la=(74, -6, 0, 50, 0), ra=(74, -6, 0, 50, 0))
    keys = [(0.0, I, "smooth"), (0.15, D(hold, la=(60, -8, 0, 60, 0), ra=(60, -8, 0, 60, 0)), "step"), (0.3, hold, "step")]
    for b in (0.5, 1.2, 1.9, 2.6):
        keys += [(b - 0.1, D(hold, neck=(10, 0, 0)), "step"),
                 (b, D(hold, neck=(-14, 0, 0), waist=(-8, 0, 0)), "fast"),
                 (b + 0.12, D(hold, neck=(-12, 0, 0), waist=(-7, 0, 0)), "elastic"),
                 (b + 0.35, hold, "step")]
    keys += [(3.0, D(I, la=(40, 10, 0, 40, 0), ra=(40, 10, 0, 40, 0)), "step"), (3.2, I, "step")]
    c["Eat"] = {"len": 3.2, "loop": False, "keys": keys}
    glitch = [(0.0, I, "smooth")]
    twitches = [((-30, 18, 10), (40, 30), (-10, 20)), ((10, -24, -6), (-10, 20), (50, 30)), ((-20, 6, -14), (20, 40), (0, 12)),
                ((14, -10, 12), (60, 10), (-20, 30)), ((-26, 20, 0), (0, 20), (30, 40)), ((6, -18, 8), (30, 30), (10, 10))]
    for i, (n, l, r) in enumerate(twitches):
        glitch.append((0.08 + i * 0.2, D(I, neck=n, la=(l[0], l[1], 0, 20, 0), ra=(r[0], r[1], 0, 20, 0), waist=(-6 - i, 0, 0)), "step"))
    glitch += [(1.3, D(I, neck=(-30, 0, 0), waist=(-16, 0, 0)), "step"), (1.45, D(I, neck=(4, 0, 0)), "snap"), (1.6, I, "smooth")]
    c["Stun"] = {"len": 1.6, "loop": False, "keys": glitch}
    c["Hit"] = {"len": 0.5, "loop": False, "additive": True, "keys": [
        (0.0, ZERO, "smooth"),
        (0.05, S(waist=(6, 0, -2), neck=(12, 6, 0), la=(-8, 4, 0, -6, 0), ra=(-8, 4, 0, -6, 0)), "step"),
        (0.12, S(waist=(-2, 0, 1), neck=(-3, 0, 0)), "elastic"),
        (0.5, ZERO, "smooth"),
    ]}
    slump = D(I, waist=(-38, 0, 0), neck=(-36, 0, 0), la=(6, 6, 0, 4, 0), ra=(6, 6, 0, 4, 0), legs=(30, 8, 60, 0))
    c["Defeat"] = {"len": 1.4, "loop": False, "keys": [
        (0.0, I, "smooth"),
        (0.1, D(I, neck=(10, 20, 0)), "step"),
        (0.2, D(I, neck=(-10, -20, 0), la=(30, 20, 0, 10, 0)), "step"),
        (0.45, D(I, waist=(-14, 0, 0), neck=(-16, 0, 0), legs=(12, 8, 22, 0)), "step"),  # powering down in steps
        (0.75, D(I, waist=(-26, 0, 0), neck=(-26, 0, 0), la=(8, 8, 0, 6, 0), ra=(8, 8, 0, 6, 0), legs=(20, 8, 40, 0)), "step"),
        (1.05, slump, "step"),
        (1.15, D(slump, waist=(-40, 0, 0)), "elastic"),
        (1.4, slump, "smooth"),
    ]}
    c["Spawn"] = {"len": 1.5, "loop": False, "keys": [
        (0.0, slump, "smooth"),
        (0.3, D(slump, neck=(10, 0, 0)), "step"),  # reboots: the head first
        (0.55, D(slump, waist=(-24, 0, 0), neck=(4, 0, 0), legs=(20, 8, 40, 0)), "step"),
        (0.8, D(C, waist=(-12, 0, 0), legs=(10, 8, 18, 0)), "step"),
        (0.95, D(C, neck=(-6, 0, 0)), "elastic"),
        (1.5, C, "smooth"),
    ]}
    return c


CLIPS = {"Cyclops": cyclops, "Minotaur": minotaur, "Talos": talos}
