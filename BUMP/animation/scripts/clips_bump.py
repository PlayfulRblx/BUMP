"""BUMP's own clips: the platformer moves The Scramble's library doesn't have.

Conventions (from fias_pose): a pose is joint -> (pitch, yaw, roll) degrees, plus "Move" for the
hips in studs. A negative Root pitch tips the body forward (so -360 is a front flip), positive
tips it back. Hips and shoulders pitch forward/up when positive; knees bend negative, elbows
positive. Neck positive looks up. 30 fps. Turns are keyed at most 90 degrees apart, as Blender
blends the quaternion between keys.

Reused from the shared library instead of authored here: Idle, Run (Playful's, imported), Jump,
Fall, Roll (also the big-fall roll), Flip (the rollout), Land, LandSoft, and Smash Arena's
WallBonk, Dazed and DazeUp (the bonk, as Sunshine Valley plays it).
"""

from fias_pose import Clip, merge, mirror

READY = {
    "Root": (-4, 0, 0), "Waist": (-2, 0, 0), "Neck": (2, 0, 0), "Move": (0, -0.2, 0),
    "RH": (10, 0, 5), "RK": (-22, 0, 0), "RA": (10, 0, 0), "LH": (-2, 0, -5), "LK": (-18, 0, 0), "LA": (14, 0, 0),
    "RS": (10, 0, 12), "RE": (20, 0, 0), "RW": (0, 0, 0), "LS": (10, 0, -12), "LE": (20, 0, 0), "LW": (0, 0, 0),
}

CROUCH = {
    "Root": (-12, 0, 0), "Waist": (-14, 0, 0), "Neck": (16, 0, 0), "Move": (0, -1.3, 0),
    "RH": (72, 0, 10), "RK": (-110, 0, 0), "RA": (40, 0, 0), "LH": (62, 0, -10), "LK": (-104, 0, 0), "LA": (40, 0, 0),
    "RS": (16, 0, 30), "RE": (44, 0, 0), "RW": (0, 0, 0), "LS": (16, 0, -30), "LE": (44, 0, 0), "LW": (0, 0, 0),
}

# Knees to the chest, hands on the shins: the shape every flip turns through.
TUCK = {
    "Waist": (-26, 0, 0), "Neck": (16, 0, 0), "Move": (0, 0.3, 0),
    "RS": (52, 0, 22), "RE": (104, 0, 0), "RW": (0, 0, 0), "LS": (52, 0, -22), "LE": (104, 0, 0), "LW": (0, 0, 0),
    "RH": (110, 0, 8), "RK": (-124, 0, 0), "RA": (24, 0, 0), "LH": (110, 0, -8), "LK": (-124, 0, 0), "LA": (24, 0, 0),
}

# Arms and legs flung wide: the top of a big jump, opening out of a flip.
SPREAD = {
    "Waist": (4, 0, 0), "Neck": (12, 0, 0), "Move": (0, 0, 0),
    "RS": (120, 0, 70), "RE": (10, 0, 0), "RW": (0, 0, 0), "LS": (120, 0, -70), "LE": (10, 0, 0), "LW": (0, 0, 0),
    "RH": (14, 0, 16), "RK": (-24, 0, 0), "RA": (20, 0, 0), "LH": (4, 0, -16), "LK": (-30, 0, 0), "LA": (20, 0, 0),
}

# Straight as an arrow, arms up and together.
ARROW = {
    "Waist": (0, 0, 0), "Neck": (6, 0, 0), "Move": (0, 0.2, 0),
    "RS": (176, 0, 6), "RE": (4, 0, 0), "RW": (0, 0, 0), "LS": (176, 0, -6), "LE": (4, 0, 0), "LW": (0, 0, 0),
    "RH": (2, 0, 2), "RK": (-4, 0, 0), "RA": (30, 0, 0), "LH": (2, 0, -2), "LK": (-4, 0, 0), "LA": (30, 0, 0),
}

# Flat out, reaching ahead: dives and the long jump.
REACH = {
    "Waist": (-4, 0, 0), "Neck": (48, 0, 0),
    "RS": (172, 0, 10), "RE": (6, 0, 0), "RW": (0, 0, 0), "LS": (172, 0, -10), "LE": (6, 0, 0), "LW": (0, 0, 0),
    "RH": (-8, 0, 5), "RK": (-14, 0, 0), "RA": (40, 0, 0), "LH": (-8, 0, -5), "LK": (-20, 0, 0), "LA": (40, 0, 0),
}


def lerp_pose(a, b, t):
    """Pose a blended toward pose b; a joint only one names comes from that one."""
    out = {}
    for joint in set(a) | set(b):
        if joint in a and joint in b:
            out[joint] = tuple(x + (y - x) * t for x, y in zip(a[joint], b[joint]))
        else:
            out[joint] = a.get(joint, b.get(joint))
    return out


def flip(pose, start, end, first, last, steps):
    """Keys turning `pose` from Root pitch `start` to `end` over frames first..last."""
    keys = []
    for i in range(steps + 1):
        t = i / steps
        keys.append((round(first + (last - first) * t), merge(pose, {"Root": (start + (end - start) * t, 0, 0)})))
    return keys


def crouch():
    low = merge(CROUCH, {"Move": (0, -1.36, 0), "Neck": (18, 0, 0)})
    return Clip("Crouch", [(0, CROUCH), (24, low), (48, CROUCH)], loop=True)


def crouch_walk():
    a = merge(CROUCH, {"RH": (90, 0, 10), "RK": (-104, 0, 0), "LH": (40, 0, -10), "LK": (-118, 0, 0), "Root": (-14, -6, 0), "Move": (0, -1.25, 0)})
    b = merge(CROUCH, {"RH": (64, 0, 10), "RK": (-124, 0, 0), "LH": (64, 0, -10), "LK": (-96, 0, 0), "Move": (0, -1.18, 0)})
    return Clip("CrouchWalk", [(0, a), (6, b), (12, mirror(a)), (18, mirror(b)), (24, a)], loop=True)


# The jump chain, rebuilt from scratch (2026-11-13). The user on the first set: "the jump and
# triple jump animations looks terrible ... restart them from scratch"; what was wrong: awkward
# poses, jerky transitions, and the flip itself. So:
# - each jump is one continuous clip: takeoff, rise, top, fall, ready to land. The game stretches
#   it so its Land marker meets the real landing (Animator, from Platformer.AirTime), so nothing
#   switches clips mid-air;
# - calmer, readable shapes: a reach rather than a fist pump, arms out for balance coming down;
# - the triple's somersault turns about the middle of the body (the hips move as it turns), not
#   about the hips, which swung the whole body round in a wide circle.
# Made for the right side; mirror() makes the left, and a chain alternates.

# Coming down: arms out and a little forward for balance, legs together and soft.
FALL_OPEN = {
    "Root": (-2, 0, 0), "Waist": (0, 0, 0), "Neck": (6, 0, 0), "Move": (0, 0, 0),
    "RS": (55, 0, 48), "RE": (18, 0, 0), "RW": (0, 0, 0), "LS": (55, 0, -48), "LE": (18, 0, 0), "LW": (0, 0, 0),
    "RH": (22, 0, 4), "RK": (-30, 0, 0), "RA": (18, 0, 0), "LH": (16, 0, -4), "LK": (-26, 0, 0), "LA": (18, 0, 0),
}

# Feet reaching for the ground: knees forward and bent, arms a touch lower.
LAND_READY = merge(FALL_OPEN, {
    "Root": (-4, 0, 0), "Neck": (2, 0, 0),
    "RS": (40, 0, 40), "LS": (40, 0, -40),
    "RH": (38, 0, 4), "RK": (-52, 0, 0), "RA": (22, 0, 0), "LH": (32, 0, -4), "LK": (-48, 0, 0), "LA": (22, 0, 0),
})

# The push off the ground: legs straightening, arms starting to swing up, a slight forward lean.
TAKEOFF = merge(READY, {
    "Root": (-8, 0, 0), "Waist": (-6, 0, 0), "Neck": (6, 0, 0), "Move": (0, -0.35, 0),
    "RH": (28, 0, 4), "RK": (-40, 0, 0), "RA": (24, 0, 0), "LH": (24, 0, -4), "LK": (-36, 0, 0), "LA": (24, 0, 0),
    "RS": (30, 0, 14), "RE": (34, 0, 0), "LS": (10, 0, -14), "LE": (34, 0, 0),
})


def jump_single():
    """Right arm reaching up and forward, left arm back, left knee lifting; easing open at the
    top; arms out for balance on the way down; knees forward for the landing."""
    reach = {
        "Root": (-3, 0, 0), "Waist": (5, -3, 0), "Neck": (12, 2, 0), "Move": (0, 0.15, 0),
        "RS": (160, 0, 32), "RE": (18, 0, 0), "RW": (0, 0, 0),
        "LS": (-22, 0, -16), "LE": (28, 0, 0), "LW": (0, 0, 0),
        "RH": (-6, 0, 4), "RK": (-14, 0, 0), "RA": (30, 0, 0),
        "LH": (62, 0, -4), "LK": (-74, 0, 0), "LA": (18, 0, 0),
    }
    top = lerp_pose(reach, FALL_OPEN, 0.4)
    keys = [
        (0, TAKEOFF),
        (3, reach),
        (6, merge(reach, {"RS": (152, 0, 36), "LH": (56, 0, -4), "LK": (-68, 0, 0), "Move": (0, 0.1, 0)})),
        (8, top),
        (11, FALL_OPEN),
        (14, LAND_READY),
    ]
    right = Clip("JumpSingleR", keys, {"Land": 14, "End": 14})
    left = Clip("JumpSingleL", [(f, mirror(pose)) for f, pose in keys], {"Land": 14, "End": 14})
    return [right, left]


# The air jump, second take (2026-11-13: "a running on air kind of float, the player runs on air as
# if they're trying to float up"): a fast cartoon run in mid-air, played as a loop while you hold
# jump. Leaning back a little with the head up, big pedalling strides, the knee driven high and
# the back leg kicking, arms pumping hard and flung out a bit with the effort. Eight frames a stride
# pair: quick, frantic.
def air_run():
    stride = {
        "Root": (10, 0, 0), "Waist": (6, 0, 0), "Neck": (22, 0, 0), "Move": (0, 0.15, 0),
        "RH": (92, 0, 6), "RK": (-58, 0, 0), "RA": (10, 0, 0),
        "LH": (-34, 0, -6), "LK": (-84, 0, 0), "LA": (30, 0, 0),
        "RS": (-46, 0, 26), "RE": (64, 0, 0), "RW": (0, 0, 0),
        "LS": (96, 0, -30), "LE": (72, 0, 0), "LW": (0, 0, 0),
    }
    passing = {
        "Root": (8, 0, 0), "Waist": (4, 0, 0), "Neck": (20, 0, 0), "Move": (0, 0.35, 0),
        "RH": (44, 0, 6), "RK": (-118, 0, 0), "RA": (20, 0, 0),
        "LH": (34, 0, -6), "LK": (-112, 0, 0), "LA": (20, 0, 0),
        "RS": (24, 0, 34), "RE": (82, 0, 0), "RW": (0, 0, 0),
        "LS": (30, 0, -34), "LE": (82, 0, 0), "LW": (0, 0, 0),
    }
    keys = [(0, stride), (2, passing), (4, mirror(stride)), (6, mirror(passing)), (8, stride)]
    return Clip("AirRun", keys, loop=True)


# Landing out of the triple: a deep squash with the arms still out, then up.
def land_big():
    deep = merge(CROUCH, {
        "Root": (-14, 0, 0), "Waist": (-18, 0, 0), "Neck": (6, 0, 0), "Move": (0, -1.6, 0),
        "RH": (98, 0, 16), "RK": (-128, 0, 0), "LH": (94, 0, -16), "LK": (-126, 0, 0),
        "RS": (80, 0, 70), "RE": (10, 0, 0), "LS": (80, 0, -70), "LE": (10, 0, 0),
    })
    return Clip("LandBig", [(0, deep), (4, merge(deep, {"Move": (0, -1.5, 0)})), (10, merge(CROUCH, {"Move": (0, -0.6, 0), "RS": (30, 0, 40), "LS": (30, 0, -40)})), (16, READY)], {"End": 16})


def backflip():
    """Crouch and spring up and back: arched open over the top, folding into a tuck as it comes
    round, then opening with the legs reaching for the floor. About 0.72 s in the air
    (Backflip.Height 15 studs); the turn speeds up through the middle and eases into the landing.
    """
    coil = merge(CROUCH, {"Root": (-8, 0, 0), "Move": (0, -1.1, 0), "RS": (-40, 0, 16), "LS": (-40, 0, -16), "RE": (20, 0, 0), "LE": (20, 0, 0)})
    spring = merge(ARROW, {"Root": (16, 0, 0), "Waist": (12, 0, 0), "Neck": (26, 0, 0), "RS": (150, 0, 24), "LS": (150, 0, -24)})
    arch = merge(ARROW, {"Waist": (22, 0, 0), "Neck": (40, 0, 0), "RS": (176, 0, 30), "LS": (176, 0, -30), "RH": (-16, 0, 4), "LH": (-16, 0, -4), "RK": (-30, 0, 0), "LK": (-30, 0, 0)})
    fold = merge(TUCK, {"Neck": (30, 0, 0)})
    keys = [
        (0, coil),
        (3, spring),
        (6, merge(arch, {"Root": (50, 0, 0)})),
        (8, merge(arch, {"Root": (110, 0, 0)})),
        (10, merge(lerp_pose(arch, fold, 0.6), {"Root": (180, 0, 0)})),
        (12, merge(fold, {"Root": (250, 0, 0)})),
        (14, merge(fold, {"Root": (310, 0, 0)})),
        (17, merge(lerp_pose(fold, SPREAD, 0.7), {"Root": (348, 0, 0)})),
        (21, merge(SPREAD, {"Root": (360, 0, 0), "Neck": (6, 0, 0), "RH": (44, 0, 12), "RK": (-56, 0, 0), "LH": (36, 0, -12), "LK": (-50, 0, 0), "RS": (90, 0, 70), "LS": (90, 0, -70)})),
        (26, merge(READY, {"Root": (360, 0, 0)})),
    ]
    return Clip("Backflip", keys, {"Land": 21, "End": 26})


def long_jump():
    a = merge(REACH, {"Root": (-52, 0, 0), "RH": (-20, 0, 6), "RK": (-30, 0, 0), "LH": (26, 0, -6), "LK": (-70, 0, 0)})
    b = merge(a, {"Root": (-46, 0, 0), "RH": (-12, 0, 6), "LH": (16, 0, -6), "LK": (-60, 0, 0), "Neck": (42, 0, 0)})
    takeoff = merge(READY, {"Root": (-30, 0, 0), "RS": (120, 0, 14), "LS": (120, 0, -14), "RH": (60, 0, 6), "RK": (-70, 0, 0), "LH": (-30, 0, -6), "LK": (-30, 0, 0)})
    return Clip("LongJump", [(0, takeoff), (4, a), (14, b), (24, a)], {"End": 24})


def dive():
    out = merge(REACH, {"Root": (-82, 0, 0)})
    wind = merge(READY, {"Root": (-24, 0, 0), "RS": (-40, 0, 20), "LS": (-40, 0, -20), "RE": (30, 0, 0), "LE": (30, 0, 0), "RH": (50, 0, 6), "RK": (-60, 0, 0)})
    return Clip("Dive", [(0, wind), (3, merge(out, {"Root": (-60, 0, 0)})), (7, out), (14, merge(out, {"Root": (-86, 0, 0), "RK": (-24, 0, 0), "LK": (-30, 0, 0)}))], {"End": 14})


def belly_slide():
    # Lying on the belly: the hips drop by about their own height, head and arms up off the floor.
    flat = merge(REACH, {"Root": (-88, 0, 0), "Move": (0, -1.75, 0), "Neck": (62, 0, 0), "RS": (164, 0, 18), "LS": (164, 0, -18), "RA": (60, 0, 0), "LA": (60, 0, 0), "RK": (-20, 0, 0), "LK": (-36, 0, 0)})
    kick = merge(flat, {"RK": (-48, 0, 0), "LK": (-14, 0, 0)})
    return Clip("BellySlide", [(0, flat), (6, kick), (12, flat)], loop=True)


def pound_spin():
    keys = [(0, merge(ARROW, {"Root": (0, 0, 0)}))]
    keys += flip(TUCK, -60, -360, 2, 8, 4)
    return Clip("PoundSpin", keys, {"End": 8})


def pound_fall():
    # Bottom first, knees up, arms up: dropping like a stone.
    seat = merge(TUCK, {
        "Root": (8, 0, 0), "Waist": (-8, 0, 0), "Neck": (-6, 0, 0), "Move": (0, 0.5, 0),
        "RS": (160, 0, 36), "RE": (30, 0, 0), "LS": (160, 0, -36), "LE": (30, 0, 0),
        "RH": (96, 0, 10), "RK": (-104, 0, 0), "LH": (96, 0, -10), "LK": (-104, 0, 0),
    })
    shake = merge(seat, {"RS": (166, 0, 30), "LS": (166, 0, -30), "Move": (0, 0.55, 0)})
    return Clip("PoundFall", [(0, seat), (3, shake), (6, seat)], loop=True)


def pound_land():
    impact = merge(CROUCH, {
        "Root": (-6, 0, 0), "Move": (0, -1.7, 0), "Waist": (-20, 0, 0), "Neck": (-4, 0, 0),
        "RH": (104, 0, 22), "RK": (-134, 0, 0), "LH": (104, 0, -22), "LK": (-134, 0, 0),
        "RS": (60, 0, 84), "RE": (10, 0, 0), "LS": (60, 0, -84), "LE": (10, 0, 0),
    })
    rise = merge(impact, {"Move": (0, -1.4, 0), "Neck": (10, 0, 0), "RS": (40, 0, 70), "LS": (40, 0, -70)})
    return Clip("PoundLand", [(0, impact), (5, impact), (9, rise)], {"End": 9})


def pound_jump():
    # Shot straight up, spinning twice round, then opening out.
    keys = []
    for i in range(9):
        keys.append((i * 2, merge(ARROW, {"Root": (0, -90 * i, 0)})))
    keys.append((22, merge(SPREAD, {"Root": (0, -720, 0)})))
    return Clip("PoundJump", keys, {"End": 22})


# On the wall, facing it: hands up on it, one knee up with the foot against it.
WALL_HOLD = {
    "Root": (10, 0, 0), "Waist": (4, 0, 0), "Neck": (14, 0, 0), "Move": (0, -0.3, 0.1),
    "RS": (158, 0, 14), "RE": (38, 0, 0), "RW": (-30, 0, 0), "LS": (128, 0, -20), "LE": (60, 0, 0), "LW": (-30, 0, 0),
    "RH": (74, 0, 8), "RK": (-92, 0, 0), "RA": (20, 0, 0), "LH": (30, 0, -8), "LK": (-60, 0, 0), "LA": (30, 0, 0),
}


def wall_cling():
    catch = merge(WALL_HOLD, {"RS": (170, 0, 18), "LS": (150, 0, -24), "RE": (14, 0, 0), "LE": (30, 0, 0), "Move": (0, 0.1, 0.1), "RK": (-70, 0, 0)})
    settle = merge(WALL_HOLD, {"Move": (0, -0.4, 0.1), "RK": (-100, 0, 0), "LK": (-70, 0, 0)})
    return Clip("WallCling", [(0, catch), (4, settle), (9, WALL_HOLD)], {"End": 9})


def wall_slide():
    # Dragging down the wall: hands grabbing at it in turn, feet braced and skidding.
    a = merge(WALL_HOLD, {"RS": (164, 0, 12), "RE": (26, 0, 0), "LS": (120, 0, -22), "LE": (70, 0, 0), "Neck": (20, 0, 0)})
    b = merge(WALL_HOLD, {"RS": (124, 0, 16), "RE": (66, 0, 0), "LS": (160, 0, -14), "LE": (28, 0, 0), "RK": (-80, 0, 0), "LK": (-74, 0, 0), "Move": (0, -0.36, 0.1)})
    return Clip("WallSlideDown", [(0, a), (5, b), (10, a)], loop=True)


def wall_leap():
    # Facing out from the wall (the body has turned already): coiled, then driven off it with
    # both legs, arms flung up and out, opening into the jump.
    coil = merge(CROUCH, {"Root": (12, 0, 0), "Move": (0, -0.5, 0), "Neck": (20, 0, 0), "RS": (60, 0, 50), "LS": (60, 0, -50), "RE": (60, 0, 0), "LE": (60, 0, 0)})
    drive = merge(ARROW, {"Root": (-14, 0, 0), "Waist": (-6, 0, 0), "Neck": (24, 0, 0), "RS": (150, 0, 50), "LS": (150, 0, -50), "RH": (-24, 0, 6), "RK": (-10, 0, 0), "LH": (-30, 0, -6), "LK": (-16, 0, 0)})
    out = merge(SPREAD, {"Root": (-6, 0, 0), "Neck": (16, 0, 0), "RH": (50, 0, 12), "RK": (-80, 0, 0), "LH": (-10, 0, -10), "LK": (-30, 0, 0)})
    return Clip("WallLeap", [(0, coil), (3, drive), (9, out), (16, merge(out, {"RS": (130, 0, 50), "LS": (130, 0, -50)}))], {"End": 16})


def shove():
    # The user (2026-11-13): "the shove needs a lot of polish ... The animation is weak". A beat of
    # coiling back, weight on the back foot and both hands drawn to the chest, palms out; then
    # the whole body thrown into it: front knee bent, back leg driving straight, arms locked out
    # at shoulder height, head forward; held a moment, then easing back.
    wind = merge(READY, {
        "Root": (10, 0, 0), "Waist": (6, 0, 0), "Neck": (6, 0, 0), "Move": (0, -0.55, 0),
        "RS": (40, 0, 22), "RE": (124, 0, 0), "RW": (-50, 0, 0), "LS": (40, 0, -22), "LE": (124, 0, 0), "LW": (-50, 0, 0),
        "LH": (34, 0, -5), "LK": (-44, 0, 0), "LA": (10, 0, 0), "RH": (-18, 0, 5), "RK": (-36, 0, 0), "RA": (20, 0, 0),
    })
    strike = merge(READY, {
        "Root": (-26, 0, 0), "Waist": (-10, 0, 0), "Neck": (18, 0, 0), "Move": (0, -0.6, 0),
        "RS": (96, 0, 6), "RE": (2, 0, 0), "RW": (-62, 0, 0), "LS": (96, 0, -6), "LE": (2, 0, 0), "LW": (-62, 0, 0),
        "LH": (58, 0, -6), "LK": (-62, 0, 0), "LA": (24, 0, 0), "RH": (-38, 0, 6), "RK": (-6, 0, 0), "RA": (34, 0, 0),
    })
    over = merge(strike, {"Root": (-31, 0, 0), "Neck": (22, 0, 0), "RS": (100, 0, 4), "LS": (100, 0, -4)})
    ease = lerp_pose(over, READY, 0.55)
    return Clip("Shove", [(0, READY), (3, wind), (6, strike), (10, over), (15, ease), (21, READY)], {"Strike": 6, "End": 21})


def hero_pose():
    # The intro's moment on you (the user, 2026-11-13: the intro "should take a little bit longer
    # when showing the final player, which is the player's character itself"; they asked for a hero
    # pose): a dip of anticipation, then popping up into a cocky pose, chest out, the right fist
    # punched straight up, the left arm pointing out at the camera, head cocked, weight on the
    # right leg; a small bounce as it settles, then held.
    dip = merge(READY, {
        "Root": (6, 0, 0), "Waist": (6, 0, 0), "Neck": (-12, 0, 0), "Move": (0, -0.65, 0),
        "RS": (-18, 0, 14), "RE": (40, 0, 0), "LS": (-18, 0, -14), "LE": (40, 0, 0),
        "RH": (44, 0, 6), "RK": (-70, 0, 0), "RA": (26, 0, 0), "LH": (40, 0, -6), "LK": (-66, 0, 0), "LA": (26, 0, 0),
    })
    pose = merge(READY, {
        "Root": (2, 0, 4), "Waist": (12, 8, 0), "Neck": (8, -10, 12), "Move": (0, -0.05, 0),
        "RS": (178, 0, 4), "RE": (8, 0, 0), "RW": (0, 0, 0),
        "LS": (84, 0, -8), "LE": (4, 0, 0), "LW": (-10, 0, 0),
        "RH": (4, 0, 4), "RK": (-6, 0, 0), "RA": (6, 0, 0),
        "LH": (-8, 0, -16), "LK": (-30, 0, 0), "LA": (24, 0, 0),
    })
    pop = merge(pose, {"Root": (-4, 0, 4), "Move": (0, 0.25, 0), "RS": (186, 0, 6), "LS": (96, 0, -8), "Neck": (14, -10, 12)})
    settle = merge(pose, {"Move": (0, -0.18, 0), "RK": (-14, 0, 0), "LK": (-38, 0, 0)})
    return Clip("HeroPose", [(0, READY), (5, dip), (9, pop), (13, pose), (18, settle), (24, pose), (51, pose)], {"End": 51})


def stagger():
    # Shoved (the user: "Victim reaction is dull"): the hit caves the chest in and whips the head
    # back, arms flung up; then a cartoon stumble backwards, arms windmilling, feet scrambling,
    # until they catch their balance arms out wide, leaning forward, and settle.
    hit = merge(READY, {
        "Root": (22, 0, 0), "Waist": (16, 0, 0), "Neck": (34, 0, 0), "Move": (0, -0.3, 0),
        "RS": (130, 0, 40), "RE": (30, 0, 0), "LS": (110, 0, -50), "LE": (40, 0, 0),
        "RH": (44, 0, 8), "RK": (-62, 0, 0), "LH": (-10, 0, -6), "LK": (-20, 0, 0),
    })
    mill1 = merge(hit, {
        "Root": (26, 0, 0), "Neck": (22, 0, 0),
        "RS": (210, 0, 30), "RE": (20, 0, 0), "LS": (30, 0, -60), "LE": (60, 0, 0),
        "RH": (-20, 0, 6), "RK": (-50, 0, 0), "LH": (36, 0, -6), "LK": (-46, 0, 0),
    })
    mill2 = merge(hit, {
        "Root": (20, 0, 0), "Neck": (26, 0, 0),
        "RS": (290, 0, 30), "RE": (30, 0, 0), "LS": (110, 0, -60), "LE": (20, 0, 0),
        "RH": (34, 0, 6), "RK": (-56, 0, 0), "LH": (-22, 0, -6), "LK": (-40, 0, 0),
    })
    mill3 = merge(hit, {
        "Root": (14, 0, 0), "Neck": (18, 0, 0),
        "RS": (370, 0, 40), "RE": (24, 0, 0), "LS": (200, 0, -50), "LE": (24, 0, 0),
        "RH": (-16, 0, 6), "RK": (-40, 0, 0), "LH": (30, 0, -6), "LK": (-50, 0, 0),
    })
    catch = merge(READY, {
        "Root": (-10, 0, 0), "Waist": (-6, 0, 0), "Neck": (10, 0, 0), "Move": (0, -0.5, 0),
        "RS": (100, 0, 80), "RE": (10, 0, 0), "LS": (100, 0, -80), "LE": (10, 0, 0),
        "RH": (40, 0, 8), "RK": (-60, 0, 0), "LH": (-14, 0, -8), "LK": (-30, 0, 0),
    })
    return Clip("Stagger", [(0, hit), (4, mill1), (8, mill2), (12, mill3), (17, catch), (24, READY)], {"End": 24})


def tumble():
    splayed = merge(SPREAD, {"RS": (130, 0, 80), "LS": (90, 0, -50), "RE": (40, 0, 0), "LE": (20, 0, 0), "RH": (50, 0, 20), "RK": (-60, 0, 0), "LH": (-10, 0, -20), "LK": (-20, 0, 0), "Neck": (-20, 0, 0)})
    other = merge(splayed, {"RS": (90, 0, 50), "LS": (130, 0, -80), "RH": (-10, 0, 20), "RK": (-20, 0, 0), "LH": (50, 0, -20), "LK": (-60, 0, 0)})
    keys = []
    for i in range(5):
        keys.append((i * 4, merge(splayed if i % 2 == 0 else other, {"Root": (90 * i, 0, 0)})))
    return Clip("Tumble", keys, loop=True)


def flail():
    # Thrown without turning over (the dummies, whose bodies already tumble for real).
    a = merge(SPREAD, {"Neck": (-20, 0, 0), "RS": (150, 0, 80), "LS": (60, 0, -40), "RH": (50, 0, 20), "RK": (-60, 0, 0)})
    b = merge(SPREAD, {"Neck": (-14, 0, 0), "RS": (60, 0, 40), "LS": (150, 0, -80), "LH": (50, 0, -20), "LK": (-60, 0, 0)})
    return Clip("Flail", [(0, a), (4, b), (8, a)], loop=True)


# Riding a ball (BUMP), remade 2026-11-13 (the user: "The animation when rolling on a ball looks
# terrible. Can we remake it", and "the dash on the ball should charge up like the player's
# running in spot on the ball ... and then a launch"). The rider's whole body is tilted into the
# roll by the game (BallRider), so these keep the body upright and do the work in the legs and arms.

# Over the ball: knees soft, weight centred, arms out low for balance.
BALL_BASE = {
    "Root": (-4, 0, 0), "Waist": (-2, 0, 0), "Neck": (8, 0, 0), "Move": (0, -0.3, 0),
    "RS": (34, 0, 52), "RE": (22, 0, 0), "RW": (0, 0, 0), "LS": (34, 0, -52), "LE": (22, 0, 0), "LW": (0, 0, 0),
}


def ball_balance():
    """Scrambling for dear life on top of the ball (the user, 2026-11-13: "It should look intense
    as if the player is trying for dear god to stay on the ball. Extremely cartoonish-exaggerated
    nintendo feeling"): knees pumping high, both arms windmilling in big circles half a turn
    apart, the chest twisting against the legs, the head bobbing. The game ties the cycle to the
    ball's speed (never slower than a scramble) and throws a balance struggle on top (Animator)."""
    def arm(pitch, side):
        return (pitch, 0, 62 * side)

    # the right arm goes round: up, forward, down, back, up again; the left half a turn behind
    right = [170, 80, -10, -100, -190]
    left = [-10, -100, -190, 80, -10]
    legs = [
        {"RH": (98, 0, 6), "RK": (-118, 0, 0), "RA": (8, 0, 0), "LH": (-22, 0, -6), "LK": (-36, 0, 0), "LA": (36, 0, 0)},
        {"RH": (44, 0, 6), "RK": (-70, 0, 0), "RA": (20, 0, 0), "LH": (44, 0, -6), "LK": (-88, 0, 0), "LA": (20, 0, 0)},
        {"LH": (98, 0, -6), "LK": (-118, 0, 0), "LA": (8, 0, 0), "RH": (-22, 0, 6), "RK": (-36, 0, 0), "RA": (36, 0, 0)},
        {"RH": (44, 0, 6), "RK": (-88, 0, 0), "RA": (20, 0, 0), "LH": (44, 0, -6), "LK": (-70, 0, 0), "LA": (20, 0, 0)},
    ]
    torso = [
        {"Root": (-16, 0, 0), "Waist": (-8, -16, 0), "Neck": (24, 10, 0), "Move": (0, -0.05, 0)},
        {"Root": (-12, 0, 0), "Waist": (-4, 0, 0), "Neck": (16, 0, 0), "Move": (0, -0.35, 0)},
        {"Root": (-16, 0, 0), "Waist": (-8, 16, 0), "Neck": (24, -10, 0), "Move": (0, -0.05, 0)},
        {"Root": (-12, 0, 0), "Waist": (-4, 0, 0), "Neck": (16, 0, 0), "Move": (0, -0.35, 0)},
    ]
    keys = []
    for i in range(5):
        pose = merge(legs[i % 4], torso[i % 4], {
            "RS": arm(right[i], 1), "RE": (30, 0, 0), "RW": (0, 0, 0),
            "LS": arm(left[i], -1), "LE": (30, 0, 0), "LW": (0, 0, 0),
        })
        keys.append((i * 4, pose))
    return Clip("BallBalance", keys, loop=True)


def ball_charge():
    """Running on the spot on top of the ball: knees driven high, arms pumping, leaning into it,
    head down. The game plays it faster as the charge builds."""
    drive = {
        "Root": (-16, 0, 0), "Waist": (-10, 0, 0), "Neck": (18, 0, 0), "Move": (0, -0.25, 0),
        "RH": (78, 0, 4), "RK": (-96, 0, 0), "RA": (20, 0, 0), "LH": (-8, 0, -4), "LK": (-22, 0, 0), "LA": (28, 0, 0),
        "RS": (-44, 0, 12), "RE": (84, 0, 0), "RW": (0, 0, 0), "LS": (64, 0, -12), "LE": (84, 0, 0), "LW": (0, 0, 0),
    }
    passing = merge(drive, {
        "RH": (34, 0, 4), "RK": (-80, 0, 0), "LH": (34, 0, -4), "LK": (-80, 0, 0), "Move": (0, -0.05, 0),
        "RS": (10, 0, 14), "LS": (10, 0, -14),
    })
    keys = [(0, drive), (3, passing), (6, mirror(drive)), (9, mirror(passing)), (12, drive)]
    return Clip("BallCharge", keys, loop=True)


def ball_dash():
    """The launch: thrown forward over the ball, arms swept back, one leg kicked out behind; held
    while the dash carries."""
    burst = {
        "Root": (-26, 0, 0), "Waist": (-14, 0, 0), "Neck": (32, 0, 0), "Move": (0, -0.2, 0),
        "RS": (-62, 0, 24), "RE": (16, 0, 0), "RW": (0, 0, 0), "LS": (-62, 0, -24), "LE": (16, 0, 0), "LW": (0, 0, 0),
        "RH": (40, 0, 4), "RK": (-60, 0, 0), "RA": (16, 0, 0), "LH": (-40, 0, -4), "LK": (-30, 0, 0), "LA": (40, 0, 0),
    }
    keys = [
        (0, merge(burst, {"Root": (-10, 0, 0), "Move": (0, -0.5, 0), "RS": (20, 0, 20), "LS": (20, 0, -20)})),
        (3, burst),
        (12, merge(burst, {"Root": (-20, 0, 0), "RS": (-50, 0, 30), "LS": (-50, 0, -30), "LH": (-28, 0, -4)})),
    ]
    return Clip("BallDash", keys, {"End": 12})


def ball_skrrt():
    """Skidding to a stop: sitting back, both feet braced forward against the roll, arms thrown
    forward and up."""
    brace = {
        "Root": (18, 0, 0), "Waist": (6, 0, 0), "Neck": (-6, 0, 0), "Move": (0, -0.55, 0.15),
        "RS": (96, 0, 34), "RE": (18, 0, 0), "RW": (0, 0, 0), "LS": (96, 0, -34), "LE": (18, 0, 0), "LW": (0, 0, 0),
        "RH": (54, 0, 6), "RK": (-34, 0, 0), "RA": (-12, 0, 0), "LH": (44, 0, -6), "LK": (-44, 0, 0), "LA": (-6, 0, 0),
    }
    keys = [(0, brace), (3, merge(brace, {"Root": (20, 0, 2), "RS": (102, 0, 30)})), (6, brace)]
    return Clip("BallSkrrt", keys, loop=True)


def ball_wobble():
    """Hit and losing it: tipping side to side, arms windmilling, a foot slipping off."""
    a = merge(BALL_BASE, {
        "Root": (2, 0, 12), "Waist": (4, 0, -8), "Neck": (-6, 0, 10),
        "RS": (150, 0, 40), "RE": (10, 0, 0), "LS": (20, 0, -80), "LE": (24, 0, 0),
        "RH": (8, 0, 4), "RK": (-26, 0, 0), "LH": (36, 0, -22), "LK": (-48, 0, 0),
    })
    keys = [(0, a), (5, merge(BALL_BASE, {"Root": (2, 0, 0), "RS": (90, 0, 70), "LS": (90, 0, -70)})), (10, mirror(a)),
            (15, merge(BALL_BASE, {"Root": (2, 0, 0), "RS": (90, 0, 70), "LS": (90, 0, -70)})), (20, a)]
    return Clip("BallWobble", keys, loop=True)


def all_clips():
    return [
        crouch(), crouch_walk(), *jump_single(), air_run(), land_big(), backflip(), long_jump(), dive(),
        belly_slide(), pound_spin(), pound_fall(), pound_land(), pound_jump(), wall_cling(), wall_slide(), wall_leap(), shove(), stagger(), hero_pose(),
        tumble(), flail(), ball_balance(), ball_charge(), ball_dash(), ball_skrrt(), ball_wobble(),
    ]


# The names the game plays. export.py writes only these, plus the shared ones BUMP reuses.
REUSED = ("Idle", "Run", "Jump", "Fall", "Roll", "Flip", "Land", "LandSoft", "WallBonk", "Dazed", "DazeUp", "Carry")


def exported_names():
    return set(REUSED) | {clip.name for clip in all_clips()}
