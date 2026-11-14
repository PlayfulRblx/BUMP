"""Everything a fighter does outside a finisher: locomotion, stances, swings and states.

Swings are built by `swing`, which turns a move's Wind, Strike and Follow shapes into a full
performance: settle back, coil, snap through contact, overshoot, drag and recover. Its markers
are what the game retimes against each weapon's Startup, Active and Recovery, so weapons keep
their exact timing while sharing a performance.
"""

import math

from fias_pose import Clip, merge, mirror
from mathutils import Matrix, Vector


def lerp(a, b, t):
    """Pose a blended toward pose b. A joint only one of them names comes from that one."""
    out = {}
    for joint in set(a) | set(b):
        if joint in a and joint in b:
            out[joint] = tuple(x + (y - x) * t for x, y in zip(a[joint], b[joint]))
        else:
            out[joint] = a.get(joint, b.get(joint))
    return out


def lean(drop):
    """Weight forward on the right foot, into a blow."""
    return {
        "Root": (-8, 0, 0),
        "Move": (0, -drop, -0.25),
        "RH": (34, 0, 4),
        "RK": (-44, 0, 0),
        "RA": (10, 0, 0),
        "LH": (-14, 0, -4),
        "LK": (-20, 0, 0),
        "LA": (22, 0, 0),
    }


def coil(drop):
    """Weight back on the left foot, ready to go."""
    return {
        "Move": (0, -drop, 0.2),
        "RH": (-12, 0, 6),
        "RK": (-12, 0, 0),
        "RA": (14, 0, 0),
        "LH": (22, 0, -6),
        "LK": (-36, 0, 0),
        "LA": (8, 0, 0),
    }


READY = merge(
    {"Root": (-4, 0, 0), "Waist": (-2, -8, 0), "Neck": (0, 8, 0), "Move": (0, -0.2, 0)},
    {"RH": (10, 0, 5), "RK": (-22, 0, 0), "RA": (10, 0, 0), "LH": (-2, 0, -5), "LK": (-18, 0, 0), "LA": (14, 0, 0)},
)


def swing(name, wind, strike, follow, frames=(5, 8, 12, 22, 32), extra=None, two_hand=False):
    """A move's whole performance. `frames` are coil, wind peak, contact, follow, settle."""
    coil_at, wind_at, strike_at, follow_at, end_at = frames
    start = merge(READY, {"Grip": wind.get("Grip", (-60, 0, 0))})
    anticipate = lerp(wind, lerp(wind, strike, -0.12), 1)
    through = lerp(wind, strike, 0.62)
    overshoot = lerp(strike, follow, 0.5)
    overshoot = lerp(overshoot, lerp(strike, follow, 1.25), 0.5)
    settle = lerp(follow, READY, 0.45)
    keys = [
        (0, start),
        (coil_at, wind),
        (wind_at, anticipate),
        (wind_at + (strike_at - wind_at) // 2, through),
        (strike_at, strike),
        (strike_at + 2, overshoot),
        (follow_at, follow),
        (end_at, settle),
    ]
    return Clip(name, keys, {"Wind": wind_at, "Strike": strike_at + 1, "End": end_at}, two_hand=two_hand, **(extra or {}))


# The shapes. Angles carry over from the game's hand-tuned pose tables, now with feet and wrists.
SLASH_RIGHT = (
    merge(coil(0.25), {"Grip": (-52, 0, 0), "RS": (72, 0, 62), "RE": (40, 0, 0), "RW": (10, 0, 12), "LS": (24, 0, -18), "LE": (40, 0, 0), "Waist": (4, -46, 0), "Neck": (0, 34, 0), "Root": (2, -14, 0)}),
    merge(lean(0.35), {"Grip": (-86, 0, 0), "RS": (88, 0, -38), "RE": (8, 0, 0), "RW": (0, 0, -14), "LS": (-14, 0, -32), "LE": (20, 0, 0), "Waist": (-6, 40, 0), "Neck": (0, -26, 0), "Root": (-8, 16, 0)}),
    merge(lean(0.25), {"Grip": (-64, 0, 0), "RS": (62, 0, -66), "RE": (34, 0, 0), "RW": (-8, 0, -18), "LS": (-6, 0, -26), "LE": (18, 0, 0), "Waist": (-2, 48, 0), "Neck": (0, -30, 0), "Root": (-6, 20, 0)}),
)
SLASH_LEFT = (
    merge(coil(0.25), {"Grip": (-60, 0, 0), "RS": (82, 0, -56), "RE": (58, 0, 0), "RW": (6, 0, -14), "LS": (8, 0, -30), "LE": (26, 0, 0), "Waist": (4, 42, 0), "Neck": (0, -30, 0), "Root": (2, 14, 0)}),
    merge(lean(0.35), {"Grip": (-86, 0, 0), "RS": (86, 0, 52), "RE": (6, 0, 0), "RW": (0, 0, 14), "LS": (26, 0, -14), "LE": (44, 0, 0), "Waist": (-6, -38, 0), "Neck": (0, 26, 0), "Root": (-8, -16, 0)}),
    merge(lean(0.25), {"Grip": (-62, 0, 0), "RS": (60, 0, 74), "RE": (26, 0, 0), "RW": (-6, 0, 16), "LS": (18, 0, -12), "LE": (34, 0, 0), "Waist": (-2, -50, 0), "Neck": (0, 32, 0), "Root": (-6, -20, 0)}),
)
OVERHEAD = (
    merge(coil(0.15), {"Grip": (-34, 0, 0), "RS": (172, 0, 14), "RE": (54, 0, 0), "RW": (-14, 0, 0), "LS": (34, 0, -24), "LE": (30, 0, 0), "Waist": (16, -12, 0), "Neck": (12, 10, 0), "Root": (6, 0, 0)}),
    merge(lean(0.8), {"Grip": (-80, 0, 0), "RS": (84, 0, 4), "RE": (6, 0, 0), "RW": (18, 0, 0), "LS": (-16, 0, -30), "LE": (18, 0, 0), "Waist": (-30, 6, 0), "Neck": (-6, 0, 0)}),
    merge(lean(0.7), {"Grip": (-66, 0, 0), "RS": (44, 0, 8), "RE": (14, 0, 0), "RW": (8, 0, 0), "LS": (-10, 0, -26), "LE": (16, 0, 0), "Waist": (-36, 8, 0), "Neck": (-10, 0, 0)}),
)
UPPERCUT = (
    merge(lean(1.0), {"Grip": (-72, 0, 0), "RS": (-34, 0, 30), "RE": (26, 0, 0), "RW": (10, 0, 0), "LS": (30, 0, -16), "LE": (40, 0, 0), "Waist": (-22, -26, 0), "Neck": (8, 16, 0)}),
    merge(coil(0.0), {"Grip": (-62, 0, 0), "RS": (158, 0, -8), "RE": (8, 0, 0), "RW": (-16, 0, 0), "LS": (-18, 0, -30), "LE": (20, 0, 0), "Waist": (18, 22, 0), "Neck": (12, -8, 0), "Root": (8, 0, 0), "Move": (0, 0.45, 0)}),
    merge(coil(0.05), {"Grip": (-44, 0, 0), "RS": (176, 0, -14), "RE": (26, 0, 0), "LS": (-6, 0, -24), "LE": (20, 0, 0), "Waist": (14, 26, 0), "Neck": (8, -10, 0), "Move": (0, 0.2, 0)}),
)
THRUST = (
    merge(coil(0.3), {"Grip": (-88, 0, 0), "RS": (48, 0, 34), "RE": (112, 0, 0), "RW": (0, 0, 0), "LS": (36, 0, -16), "LE": (40, 0, 0), "Waist": (8, -40, 0), "Neck": (0, 28, 0), "Root": (2, -16, 0)}),
    merge(lean(0.55), {"Grip": (-92, 0, 0), "RS": (96, 0, -4), "RE": (2, 0, 0), "LS": (-22, 0, -24), "LE": (14, 0, 0), "Waist": (-14, 34, 0), "Neck": (-4, -24, 0), "Root": (-10, 16, 0)}),
    merge(lean(0.45), {"Grip": (-84, 0, 0), "RS": (84, 0, -10), "RE": (18, 0, 0), "LS": (-14, 0, -22), "LE": (18, 0, 0), "Waist": (-12, 30, 0), "Neck": (-4, -20, 0), "Root": (-8, 14, 0)}),
)
BIG_SWING = (
    merge(coil(0.4), {"Grip": (-48, 0, 0), "RS": (120, 0, 68), "RE": (72, 0, 0), "LS": (112, 0, 44), "LE": (84, 0, 0), "Waist": (12, -62, 0), "Neck": (0, 46, 0), "Root": (4, -22, 0)}),
    merge(lean(0.55), {"Grip": (-88, 0, 0), "RS": (86, 0, -34), "RE": (8, 0, 0), "LS": (74, 0, 22), "LE": (22, 0, 0), "Waist": (-8, 46, 0), "Neck": (0, -30, 0), "Root": (-8, 26, 0)}),
    merge(lean(0.35), {"Grip": (-58, 0, 0), "RS": (96, 0, -78), "RE": (44, 0, 0), "LS": (70, 0, -16), "LE": (52, 0, 0), "Waist": (-2, 66, 0), "Neck": (0, -40, 0), "Root": (-4, 36, 0)}),
)
GROUND_SLAM = (
    merge(coil(0.0), {"Grip": (-30, 0, 0), "RS": (178, 0, -6), "RE": (30, 0, 0), "LS": (170, 0, 8), "LE": (32, 0, 0), "Waist": (22, 0, 0), "Neck": (18, 0, 0), "Root": (12, 0, 0), "Move": (0, 0.5, 0.2)}),
    merge(lean(1.0), {"Grip": (-84, 0, 0), "RS": (46, 0, -6), "RE": (4, 0, 0), "LS": (42, 0, 6), "LE": (4, 0, 0), "Waist": (-42, 0, 0), "Neck": (-8, 0, 0)}),
    merge(lean(0.95), {"Grip": (-84, 0, 0), "RS": (30, 0, -4), "RE": (10, 0, 0), "LS": (26, 0, 4), "LE": (10, 0, 0), "Waist": (-46, 0, 0), "Neck": (-12, 0, 0)}),
)


def spin_clip(name, two_hand=False):
    arms = {"Grip": (-90, 0, 0), "RS": (90, 0, 60), "RE": (6, 0, 0), "LS": (84, 0, -60), "LE": (8, 0, 0), "Neck": (0, 0, 0), "Waist": (0, 0, 0)}
    low = merge(coil(0.5), {"Grip": (-80, 0, 0), "RS": (80, 0, 44), "RE": (18, 0, 0), "LS": (70, 0, -44), "LE": (22, 0, 0), "Waist": (0, -56, 0), "Neck": (0, 30, 0), "Root": (0, -30, 0)})
    keys = [(0, merge(READY, {"Grip": (-80, 0, 0)})), (6, low), (8, merge(low, {"Root": (0, -44, 0)}))]
    for step, yaw in enumerate((-20, 70, 160, 250, 340)):
        keys.append((9 + step * 3, merge(arms, {"Root": (0, yaw, 0), "Move": (0, -0.4, 0)})))
    end = merge(lean(0.25), {"Grip": (-60, 0, 0), "RS": (74, 0, 40), "RE": (26, 0, 0), "LS": (40, 0, -30), "LE": (30, 0, 0), "Waist": (0, 16, 0), "Root": (0, 360, 0)})
    keys.append((24, merge(end, {"Root": (0, 372, 0)})))
    keys.append((30, merge(end, {"Root": (0, 360, 0)})))
    return Clip(name, keys, {"Wind": 8, "Strike": 21, "End": 30}, two_hand=two_hand)


# Empty-handed and quick: the arm cocks wide with a bent elbow and whips flat across the body.
SLAP = (
    merge(SLASH_RIGHT[0], {"RS": (96, 0, 78), "RE": (62, 0, 0), "RW": (0, 0, 18)}),
    merge(SLASH_RIGHT[1], {"RS": (96, 0, -24), "RE": (4, 0, 0), "RW": (0, 0, -28)}),
    merge(SLASH_RIGHT[2], {"RS": (70, 0, -72), "RE": (30, 0, 0), "RW": (-8, 0, -20)}),
)
SLAP_FRAMES = (1, 3, 5, 10, 16)
# The way back: a backhand with the same arm, so the chain never has to reset the shoulder.
SLAP_BACK = (
    merge(SLASH_LEFT[0], {"RS": (100, 0, -70), "RE": (58, 0, 0), "RW": (0, 0, -14)}),
    merge(SLASH_LEFT[1], {"RS": (96, 0, 34), "RE": (6, 0, 0), "RW": (0, 0, 24)}),
    merge(SLASH_LEFT[2], {"RS": (74, 0, 74), "RE": (26, 0, 0), "RW": (-6, 0, 18)}),
)
# Scooped up from low, carrying them off the ground.
SLAP_RISE = (
    merge(UPPERCUT[0], {"RE": (30, 0, 0), "RW": (0, 0, 0)}),
    merge(UPPERCUT[1], {"RS": (150, 0, 8), "RE": (8, 0, 0), "RW": (10, 0, 0)}),
    merge(UPPERCUT[2], {"RS": (168, 0, 12), "RE": (20, 0, 0)}),
)
SLAP_RISE_FRAMES = (2, 5, 8, 14, 22)
# Thrown from a full sprint: the whole torso winds up behind a wide arm and carries on after it.
SLAP_CHARGE = (
    merge(BIG_SWING[0], {"RS": (110, 0, 84), "RE": (70, 0, 0), "RW": (0, 0, 20), "LS": (30, 0, -20), "LE": (40, 0, 0)}),
    merge(BIG_SWING[1], {"RS": (92, 0, -20), "RE": (2, 0, 0), "RW": (0, 0, -28), "LS": (-20, 0, -30), "LE": (20, 0, 0), "Waist": (-16, 52, 0), "Root": (-14, 28, 0)}),
    merge(BIG_SWING[2], {"RS": (70, 0, -84), "RE": (30, 0, 0), "RW": (-8, 0, -20), "LS": (-10, 0, -28), "LE": (24, 0, 0)}),
)
SLAP_CHARGE_FRAMES = (2, 4, 7, 14, 26)

ATTACKS = {
    "SlashRight": SLASH_RIGHT,
    "SlashLeft": SLASH_LEFT,
    "Overhead": OVERHEAD,
    "Uppercut": UPPERCUT,
    "Thrust": THRUST,
    "BigSwing": BIG_SWING,
    "GroundSlam": GROUND_SLAM,
}
# These two already swing with both arms, so the other hand is on the weapon for everyone.
ALWAYS_TWO_HANDED = ("BigSwing", "GroundSlam")
TWO_HANDED_VARIANTS = ("SlashRight", "SlashLeft", "Overhead", "Uppercut", "Thrust")


def idle():
    down = merge(READY, {"LS": (8, 0, -9), "LE": (20, 0, 0), "LW": (0, 0, 0), "Move": (0, -0.26, 0), "Waist": (-3, -8, 0)})
    up = merge(READY, {"LS": (10, 0, -8), "LE": (24, 0, 0), "LW": (0, 0, 0), "Move": (0, -0.17, 0), "Waist": (-1, -8, 0)})
    return Clip("Idle", [(0, down), (30, up), (60, down)], loop=True)


def run():
    """A sprint: 20 frames, two steps, right foot planting first."""
    contact = {
        "Root": (-14, -5, 0), "Waist": (2, 9, 0), "Neck": (6, -6, 0),
        "RH": (58, 0, 0), "RK": (-24, 0, 0), "RA": (-6, 0, 0),
        "LH": (-52, 0, 0), "LK": (-58, 0, 0), "LA": (24, 0, 0),
        "LS": (46, 0, -10), "LE": (72, 0, 0), "LW": (0, 0, 0),
        "Move": (0, -0.12, 0),
    }
    down = {
        "Root": (-14, -2, 0), "Waist": (2, 3, 0), "Neck": (6, -2, 0),
        "RH": (30, 0, 0), "RK": (-42, 0, 0), "RA": (6, 0, 0),
        "LH": (-16, 0, 0), "LK": (-92, 0, 0), "LA": (34, 0, 0),
        "LS": (16, 0, -10), "LE": (60, 0, 0),
        "Move": (0, -0.34, 0),
    }
    passing = {
        "Root": (-14, 2, 0), "Waist": (2, -3, 0), "Neck": (6, 2, 0),
        "RH": (-8, 0, 0), "RK": (-14, 0, 0), "RA": (22, 0, 0),
        "LH": (34, 0, 0), "LK": (-96, 0, 0), "LA": (20, 0, 0),
        "LS": (-20, 0, -10), "LE": (54, 0, 0),
        "Move": (0, -0.08, 0),
    }
    flight = {
        "Root": (-14, 4, 0), "Waist": (2, -7, 0), "Neck": (6, 5, 0),
        "RH": (-40, 0, 0), "RK": (-30, 0, 0), "RA": (36, 0, 0),
        "LH": (54, 0, 0), "LK": (-52, 0, 0), "LA": (-4, 0, 0),
        "LS": (-38, 0, -10), "LE": (64, 0, 0),
        "Move": (0, 0.14, 0),
    }
    keys = [(0, contact), (2, down), (5, passing), (7, flight)]
    keys += [(10, mirror(contact)), (12, mirror(down)), (15, mirror(passing)), (17, mirror(flight)), (20, contact)]
    return Clip("Run", keys, loop=True)


def strafe():
    """Stepping sideways to the right, chest square to the target."""
    wide = {
        "Root": (-6, 0, -5), "Waist": (0, 0, 4), "Neck": (0, 0, 2),
        "RH": (4, 0, 34), "RK": (-20, 0, 0), "RA": (6, 0, -10),
        "LH": (-2, 0, -14), "LK": (-30, 0, 0), "LA": (10, 0, 12),
        "LS": (12, 0, -22), "LE": (34, 0, 0), "LW": (0, 0, 0),
        "Move": (0, -0.36, 0),
    }
    pass_step = {
        "Root": (-6, 0, 0), "Waist": (0, 0, 0), "Neck": (0, 0, 0),
        "RH": (2, 0, 10), "RK": (-30, 0, 0), "RA": (8, 0, 0),
        "LH": (8, 0, -6), "LK": (-48, 0, 0), "LA": (18, 0, 0),
        "LS": (12, 0, -12), "LE": (30, 0, 0),
        "Move": (0, -0.12, 0),
    }
    narrow = {
        "Root": (-6, 0, 5), "Waist": (0, 0, -4), "Neck": (0, 0, -2),
        "RH": (-2, 0, -6), "RK": (-26, 0, 0), "RA": (10, 0, 6),
        "LH": (4, 0, 26), "LK": (-20, 0, 0), "LA": (6, 0, -8),
        "LS": (12, 0, -16), "LE": (34, 0, 0),
        "Move": (0, -0.3, 0),
    }
    keys = [(0, wide), (5, pass_step), (10, narrow), (15, pass_step), (20, wide)]
    right = Clip("StrafeRight", keys, loop=True)
    left = Clip("StrafeLeft", [(frame, mirror(pose)) for frame, pose in keys], loop=True)
    return [right, left]


def kick():
    """A front push kick off the right leg: knee up, drive the heel out, plant.

    Built as a swing so the game can retime it: the knee is up by Wind, the leg is out through
    the stretch to Strike, and it comes down by End. It names the legs, so it is a whole-body
    move even on the run. It doesn't name the grip: whatever is in the hand stays held.
    """
    chamber = {
        "Root": (8, 0, 0), "Waist": (4, 10, 0), "Neck": (-6, -8, 0), "Move": (0, -0.12, 0.12),
        "RH": (86, 0, 4), "RK": (-104, 0, 0), "RA": (12, 0, 0),
        "LH": (-6, 0, -5), "LK": (-16, 0, 0), "LA": (10, 0, 0),
        "RS": (26, 0, 30), "RE": (64, 0, 0), "RW": (0, 0, 0),
        "LS": (48, 0, -28), "LE": (74, 0, 0), "LW": (0, 0, 0),
    }
    strike = {
        "Root": (17, 0, 0), "Waist": (8, 14, 0), "Neck": (-16, -10, 0), "Move": (0, -0.06, -0.4),
        "RH": (88, 0, 2), "RK": (-4, 0, 0), "RA": (-20, 0, 0),
        "LH": (-16, 0, -5), "LK": (-8, 0, 0), "LA": (16, 0, 0),
        "RS": (-34, 0, 36), "RE": (28, 0, 0), "RW": (0, 0, 0),
        "LS": (58, 0, -40), "LE": (56, 0, 0), "LW": (0, 0, 0),
    }
    down = {
        "Root": (2, 0, 0), "Waist": (0, 6, 0), "Neck": (-2, -4, 0), "Move": (0, -0.24, -0.22),
        "RH": (34, 0, 5), "RK": (-46, 0, 0), "RA": (8, 0, 0),
        "LH": (-12, 0, -5), "LK": (-20, 0, 0), "LA": (20, 0, 0),
        "RS": (4, 0, 22), "RE": (40, 0, 0), "RW": (0, 0, 0),
        "LS": (24, 0, -18), "LE": (48, 0, 0), "LW": (0, 0, 0),
    }
    ready = merge(READY, {"RS": (10, 0, 16), "RE": (36, 0, 0), "RW": (0, 0, 0), "LS": (14, 0, -14), "LE": (36, 0, 0), "LW": (0, 0, 0)})
    keys = [
        (0, ready),
        (4, chamber),
        (6, lerp(chamber, strike, 0.55)),
        (8, strike),
        (10, lerp(strike, chamber, -0.06)),
        (16, down),
        (22, ready),
    ]
    return Clip("Kick", keys, {"Wind": 5, "Strike": 10, "End": 22})


def stances():
    one = {"Grip": (-58, 0, 0), "RS": (16, 0, 24), "RE": (44, 0, 0), "RW": (0, 0, 0)}
    heavy = {"Grip": (-72, 0, 0), "RS": (10, 0, 30), "RE": (40, 0, 0), "RW": (0, 0, 0)}
    two = {"Grip": (-62, 0, 0), "RS": (30, 0, 18), "RE": (52, 0, 0), "RW": (0, 0, 0)}
    out = []
    for name, base, two_hand in (("OneHand", one, False), ("Heavy", heavy, False), ("TwoHand", two, True)):
        rise = dict(base)
        rise["RS"] = (base["RS"][0] + 3, 0, base["RS"][2])
        rise["RE"] = (base["RE"][0] + 3, 0, 0)
        out.append(Clip("Stance" + name, [(0, base), (30, rise), (60, base)], loop=True, two_hand=two_hand))
    return out


def states():
    guard = {
        "Grip": (-12, 0, 0), "RS": (78, 0, -40), "RE": (92, 0, 0), "RW": (0, 0, 0),
        "LS": (74, 0, 34), "LE": (96, 0, 0), "LW": (0, 0, 0),
        "Waist": (-10, 8, 0), "Neck": (-6, 0, 0), "Root": (-6, 0, 0),
    }
    guard_legs = {"Move": (0, -0.5, 0.05), "RH": (22, 0, 8), "RK": (-40, 0, 0), "RA": (12, 0, 0), "LH": (-6, 0, -8), "LK": (-32, 0, 0), "LA": (20, 0, 0)}
    block_a = merge(guard, guard_legs)
    block_b = merge(block_a, {"Move": (0, -0.56, 0.05), "Neck": (-8, 0, 0)})

    def recoil(name, hit, hold, marker_end):
        return Clip(name, [(0, READY), (2, hit), (5, lerp(hit, hold, 1.15)), (marker_end, hold)], {"End": marker_end})

    stagger_hit = merge(coil(0.2), {"RS": (34, 0, 34), "RE": (26, 0, 0), "LS": (34, 0, -34), "LE": (26, 0, 0), "Waist": (24, 0, 12), "Neck": (28, 0, -10), "Root": (10, 0, 4)})
    stagger_hold = merge(coil(0.35), {"RS": (20, 0, 26), "RE": (40, 0, 0), "LS": (24, 0, -28), "LE": (44, 0, 0), "Waist": (12, 0, 6), "Neck": (18, 0, -6), "Root": (6, 0, 2)})
    parried_hit = merge(coil(0.1), {"Grip": (-20, 0, 0), "RS": (156, 0, 40), "RE": (24, 0, 0), "RW": (-20, 0, 0), "LS": (124, 0, -40), "LE": (30, 0, 0), "Waist": (30, 0, 8), "Neck": (30, 0, 0), "Root": (12, 0, 0)})
    parried_hold = merge(coil(0.3), {"Grip": (-30, 0, 0), "RS": (136, 0, 44), "RE": (36, 0, 0), "RW": (-10, 0, 0), "LS": (108, 0, -44), "LE": (40, 0, 0), "Waist": (22, 4, 10), "Neck": (20, 0, 4), "Root": (9, 0, 0)})

    downed_a = {
        "Root": (-68, 0, 0), "Move": (0, -2.0, 0), "Waist": (-10, 0, 8), "Neck": (40, 0, 0),
        "RS": (110, 0, 18), "RE": (20, 0, 0), "RW": (10, 0, 0), "LS": (120, 0, -14), "LE": (30, 0, 0), "LW": (10, 0, 0),
        "RH": (-10, 0, 8), "RK": (-14, 0, 0), "RA": (30, 0, 0), "LH": (6, 0, -8), "LK": (-30, 0, 0), "LA": (30, 0, 0),
        "Grip": (-70, 0, 0),
    }
    downed_b = merge(downed_a, {"Waist": (-14, 0, 6), "Neck": (46, 0, 0), "Move": (0, -2.05, 0)})
    crawl_a = merge(downed_a, {"RS": (150, 0, 18), "RE": (6, 0, 0), "LS": (84, 0, -14), "LE": (58, 0, 0), "RH": (-24, 0, 8), "RK": (-8, 0, 0), "LH": (18, 0, -8), "LK": (-58, 0, 0), "Waist": (-10, -8, 8)})
    crawl_b = mirror(crawl_a)
    getup = [
        (0, downed_a),
        (6, merge(downed_a, {"RS": (60, 0, 30), "RE": (50, 0, 0), "LS": (60, 0, -30), "LE": (50, 0, 0), "Root": (-52, 0, 0), "Move": (0, -1.7, 0)})),
        (13, merge(lean(1.2), {"RS": (20, 0, 24), "LS": (20, 0, -24), "RE": (40, 0, 0), "LE": (40, 0, 0), "Waist": (-30, 0, 0), "Neck": (20, 0, 0), "Root": (-22, 0, 0)})),
        (20, merge(lean(0.5), {"RS": (10, 0, 20), "LS": (10, 0, -20), "RE": (30, 0, 0), "LE": (30, 0, 0), "Waist": (-8, 0, 0), "Neck": (4, 0, 0), "Root": (-6, 0, 0)})),
        (26, READY),
    ]
    taunt_up = {"RS": (150, 0, 30), "RE": (20, 0, 0), "LS": (150, 0, -30), "LE": (20, 0, 0), "Waist": (8, 0, 0), "Neck": (14, 0, 0), "Grip": (-40, 0, 0)}
    taunt_low = merge(taunt_up, {"RS": (136, 0, 34), "LS": (136, 0, -34), "Move": (0, -0.3, 0), "RH": (10, 0, 6), "RK": (-20, 0, 0), "LH": (10, 0, -6), "LK": (-20, 0, 0)})
    taunt_high = merge(taunt_up, {"Move": (0, 0.5, 0), "RH": (0, 0, 6), "RK": (-4, 0, 0), "LH": (0, 0, -6), "LK": (-4, 0, 0)})
    point = {
        "RS": (92, 0, -6), "RE": (6, 0, 0), "RW": (0, 0, 0), "LS": (10, 0, -10), "LE": (70, 0, 0),
        "Waist": (-2, 24, 0), "Neck": (4, -18, 0), "Root": (0, 14, 0), "Grip": (-82, 0, 0),
        "Move": (0, -0.2, 0), "RH": (14, 0, 6), "RK": (-24, 0, 0), "LH": (-6, 0, -6), "LK": (-16, 0, 0),
    }
    laugh_a = merge(point, {"Waist": (10, 10, 0), "Neck": (18, -6, 0), "LS": (40, 0, 20), "LE": (100, 0, 0), "RS": (20, 0, 10), "RE": (40, 0, 0)})
    laugh_b = merge(laugh_a, {"Waist": (-14, 10, 0), "Neck": (-6, -6, 0), "Move": (0, -0.34, 0)})
    dash = merge({"Root": (-34, 0, 0), "Waist": (-12, 0, 0), "Neck": (26, 0, 0), "Move": (0, -0.7, 0)}, {"RH": (70, 0, 0), "RK": (-70, 0, 0), "RA": (0, 0, 0), "LH": (-40, 0, 0), "LK": (-50, 0, 0), "LA": (26, 0, 0), "LS": (-30, 0, -20), "LE": (40, 0, 0)})
    jump = {"Root": (-4, 0, 0), "Waist": (2, 0, 0), "RH": (46, 0, 0), "RK": (-66, 0, 0), "RA": (20, 0, 0), "LH": (-12, 0, 0), "LK": (-28, 0, 0), "LA": (24, 0, 0), "LS": (60, 0, -30), "LE": (30, 0, 0), "Move": (0, 0, 0)}
    fall = merge(jump, {"RH": (24, 0, 8), "RK": (-40, 0, 0), "LH": (10, 0, -8), "LK": (-50, 0, 0), "LS": (120, 0, -40), "LE": (20, 0, 0), "Waist": (10, 0, 0)})
    # One hand on the shelf and tugging, weapon kept low in the other.
    reach_a = merge(READY, {"LS": (122, 0, 10), "LE": (14, 0, 0), "LW": (0, 0, 0), "RS": (22, 0, -14), "RE": (34, 0, 0), "RW": (0, 0, 0), "Grip": (-24, 0, 0), "Waist": (-9, 10, 0), "Neck": (-8, -6, 0), "Root": (-7, 0, 0), "Move": (0, -0.3, 0)})
    reach_b = merge(reach_a, {"LS": (106, 0, 10), "LE": (46, 0, 0), "Waist": (-2, 6, 0), "Move": (0, -0.24, 0.14), "Root": (-1, 0, 0)})
    # Both hands up under something held over your head, taking its weight in the elbows.
    carry_a = merge(READY, {"Root": (-2, 0, 0), "Waist": (3, 0, 0), "Neck": (-6, 0, 0), "RS": (166, 0, 14), "RE": (38, 0, 0), "RW": (0, 0, 0), "LS": (166, 0, -14), "LE": (38, 0, 0), "LW": (0, 0, 0)})
    carry_b = merge(carry_a, {"RE": (46, 0, 0), "LE": (46, 0, 0), "Move": (0, -0.3, 0), "Neck": (-3, 0, 0)})
    return [
        Clip("Grab", [(0, reach_a), (8, reach_b), (16, reach_a)], loop=True),
        Clip("Block", [(0, block_a), (24, block_b), (48, block_a)], loop=True),
        Clip("Carry", [(0, carry_a), (20, carry_b), (40, carry_a)], loop=True),
        recoil("Stagger", stagger_hit, stagger_hold, 16),
        recoil("Parried", parried_hit, parried_hold, 20),
        Clip("Downed", [(0, downed_a), (36, downed_b), (72, downed_a)], loop=True),
        Clip("DownedCrawl", [(0, crawl_a), (15, crawl_b), (30, crawl_a)], loop=True),
        Clip("GetUp", getup, {"End": 26}),
        Clip("Taunt", [(0, READY), (8, taunt_high), (14, taunt_low), (20, taunt_high), (26, taunt_low), (32, taunt_high), (44, READY)], {"End": 44}),
        Clip("Laugh", [(0, READY), (6, point), (20, point), (26, laugh_a), (30, laugh_b), (34, laugh_a), (38, laugh_b), (42, laugh_a), (54, READY)], {"End": 54}),
        Clip("Dash", [(0, dash), (10, merge(dash, {"Root": (-30, 0, 0)}))], loop=True),
        Clip("Jump", [(0, jump), (12, merge(jump, {"RK": (-74, 0, 0)}))], loop=True),
        Clip("Fall", [(0, fall), (12, merge(fall, {"LS": (130, 0, -40), "RS": (120, 0, 40)}))], loop=True),
    ]


# Roblox CFrame.Angles(pitch, yaw, roll) of a 3x3, in degrees: the order fias_rig.euler_r undoes.
def angles_of(matrix):
    e = matrix.to_euler("ZYX")
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def turned(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 3, axis)


def angled(pitch, yaw, roll):
    return turned("X", pitch) @ turned("Y", yaw) @ turned("Z", roll)


# The hood roll: Root as a turn round the vertical by `spin` (left, so the right shoulder leads),
# then lying back by `tilt`, so the body goes round on its back rather than over its head. `arm` is
# where the right arm points in the world, which is what keeps the hand on the top while the body
# turns over it, and `elbow` how bent it is: the game's rig sits lower than Blender's, and a straight
# arm put the hand 0.9 into the top. Forward is -Z.
def hooded(spin, tilt, pose, drop=0, arm=None, elbow=4, shift=(0, 0)):
    body = turned("Y", spin) @ turned("X", tilt)
    out = merge(READY, pose, {"Root": angles_of(body), "Move": (shift[0], -drop, shift[1])})
    if arm:
        chest = body @ angled(*out.get("Waist", (0, 0, 0)))
        local = chest.transposed() @ Vector(arm).normalized()
        out["RS"] = angles_of(Vector((0, -1, 0)).rotation_difference(local).to_matrix())
        out["RE"] = (elbow, 0, 0)
    return out


def traversal():
    """Getting around the arena: ledges, walls, the air jump, and the moments your feet slip."""
    # Hands on the ledge. MovementClient places the body from the rig so the hands land there: the
    # shoulder sits below and back from the hand by a fixed share of the arm, which these angles
    # reach with the elbows a little bent. Root and Waist stay square, or the hands would move.
    hang_a = {
        "Root": (0, 0, 0), "Waist": (0, 0, 0), "Neck": (20, 0, 0), "Move": (0, 0, 0),
        "RS": (122, 0, 6), "RE": (34, 0, 0), "RW": (-20, 0, 0), "LS": (122, 0, -6), "LE": (34, 0, 0), "LW": (-20, 0, 0),
        "RH": (8, 0, 3), "RK": (-16, 0, 0), "RA": (24, 0, 0), "LH": (-4, 0, -3), "LK": (-30, 0, 0), "LA": (26, 0, 0),
        "Grip": (-50, 0, 0),
    }
    hang_b = merge(hang_a, {"RH": (-2, 0, 3), "RK": (-24, 0, 0), "LH": (6, 0, -3), "LK": (-18, 0, 0), "Neck": (24, 0, 0)})
    # Catching one: arms flung up, knees taking the weight, then the legs swing through and settle.
    catch_reach = merge(hang_a, {"RS": (158, 0, 10), "RE": (6, 0, 0), "LS": (158, 0, -10), "LE": (6, 0, 0), "Neck": (30, 0, 0), "RH": (-14, 0, 3), "RK": (-10, 0, 0), "LH": (-24, 0, -3), "LK": (-22, 0, 0)})
    catch_impact = merge(hang_a, {"RS": (128, 0, 6), "RE": (20, 0, 0), "LS": (128, 0, -6), "LE": (20, 0, 0), "Neck": (6, 0, 0), "RH": (58, 0, 6), "RK": (-82, 0, 0), "RA": (34, 0, 0), "LH": (48, 0, -6), "LK": (-92, 0, 0), "LA": (34, 0, 0)})
    catch_swing = merge(hang_a, {"Neck": (14, 0, 0), "RH": (26, 0, 3), "RK": (-20, 0, 0), "LH": (18, 0, -3), "LK": (-34, 0, 0)})
    catch_back = merge(hang_a, {"Neck": (24, 0, 0), "RH": (-12, 0, 3), "RK": (-26, 0, 0), "LH": (-20, 0, -3), "LK": (-40, 0, 0)})
    pull = merge(hang_a, {"Root": (-12, 0, 0), "Waist": (-14, 0, 0), "Neck": (6, 0, 0), "RS": (96, 0, 16), "RE": (100, 0, 0), "LS": (96, 0, -16), "LE": (100, 0, 0), "RH": (40, 0, 4), "RK": (-60, 0, 0), "LH": (64, 0, -4), "LK": (-96, 0, 0)})
    vault = merge(pull, {"Root": (-30, 0, 0), "Waist": (-20, 0, 0), "Neck": (24, 0, 0), "RS": (20, 0, 24), "RE": (40, 0, 0), "LS": (20, 0, -24), "LE": (40, 0, 0), "RH": (84, 0, 4), "RK": (-104, 0, 0), "LH": (20, 0, -4), "LK": (-50, 0, 0)})
    slide_a = {
        "Root": (8, 0, 0), "Waist": (10, 0, 0), "Neck": (-18, 0, 0), "Move": (0, -0.2, 0),
        "RS": (134, 0, 24), "RE": (34, 0, 0), "RW": (-20, 0, 0), "LS": (146, 0, -24), "LE": (22, 0, 0), "LW": (-20, 0, 0),
        "RH": (48, 0, 8), "RK": (-82, 0, 0), "RA": (34, 0, 0), "LH": (22, 0, -8), "LK": (-44, 0, 0), "LA": (24, 0, 0),
        "Grip": (-60, 0, 0),
    }
    slide_b = merge(slide_a, {"RS": (146, 0, 24), "RE": (22, 0, 0), "LS": (134, 0, -24), "LE": (34, 0, 0), "RH": (22, 0, 8), "RK": (-44, 0, 0), "LH": (48, 0, -8), "LK": (-82, 0, 0)})
    tuck = {
        "Waist": (-24, 0, 0), "Neck": (18, 0, 0), "Move": (0, 0.3, 0),
        "RS": (46, 0, 24), "RE": (108, 0, 0), "LS": (46, 0, -24), "LE": (108, 0, 0),
        "RH": (108, 0, 8), "RK": (-122, 0, 0), "RA": (24, 0, 0), "LH": (108, 0, -8), "LK": (-122, 0, 0), "LA": (24, 0, 0),
        "Grip": (-40, 0, 0),
    }
    skid = {
        "Root": (22, 16, 0), "Waist": (-8, -8, 6), "Neck": (-10, -8, 0), "Move": (0, -0.9, 0),
        "RS": (40, 0, 40), "RE": (40, 0, 0), "LS": (70, 0, -50), "LE": (30, 0, 0),
        "RH": (68, 0, 10), "RK": (-42, 0, 0), "RA": (-14, 0, 0), "LH": (-34, 0, -8), "LK": (-58, 0, 0), "LA": (30, 0, 0),
    }
    crouch = {
        "Root": (-16, 0, 0), "Waist": (-16, 0, 0), "Neck": (18, 0, 0), "Move": (0, -1.25, 0),
        "RH": (66, 0, 10), "RK": (-104, 0, 0), "RA": (38, 0, 0), "LH": (52, 0, -10), "LK": (-96, 0, 0), "LA": (40, 0, 0),
        "RS": (10, 0, 44), "RE": (30, 0, 0), "LS": (10, 0, -44), "LE": (30, 0, 0),
    }
    # Leaning back on the hips, lead leg out along the floor, rear knee up with its foot near the deck
    # (folded under, it goes through the floor on a player's shorter legs), one hand trailing.
    slide_a = {
        "Root": (52, 0, 0), "Waist": (-20, 0, 0), "Neck": (-24, 0, 0), "Move": (0, -1.0, 0),
        "RH": (34, 0, 8), "RK": (-6, 0, 0), "RA": (-20, 0, 0),
        "LH": (68, 0, -14), "LK": (-125, 0, 0), "LA": (30, 0, 0),
        "RS": (40, 0, 46), "RE": (24, 0, 0), "RW": (0, 0, 0),
        "LS": (-34, 0, -38), "LE": (18, 0, 0), "LW": (0, 0, 0),
        "Grip": (-50, 0, 0),
    }
    slide_b = merge(slide_a, {"Root": (50, 0, 0), "Waist": (-17, 0, 0), "RS": (46, 0, 48), "LS": (-40, 0, -38), "Move": (0, -0.96, 0)})
    # A long, flat dive: arms driving forward, legs trailing, head up to see the landing.
    leap_a = {
        "Root": (-58, 0, 0), "Waist": (4, 0, 0), "Neck": (36, 0, 0), "Move": (0, 0, 0),
        "RS": (166, 0, 10), "RE": (8, 0, 0), "RW": (0, 0, 0), "LS": (166, 0, -10), "LE": (8, 0, 0), "LW": (0, 0, 0),
        "RH": (-14, 0, 6), "RK": (-22, 0, 0), "RA": (30, 0, 0), "LH": (-4, 0, -6), "LK": (-46, 0, 0), "LA": (30, 0, 0),
        "Grip": (-40, 0, 0),
    }
    leap_b = merge(leap_a, {"Root": (-48, 0, 0), "RK": (-34, 0, 0), "LK": (-58, 0, 0), "Neck": (30, 0, 0)})
    leap_land = merge(leap_a, {"Root": (-14, 0, 0), "Neck": (8, 0, 0), "RS": (70, 0, 30), "LS": (70, 0, -30), "RE": (30, 0, 0), "LE": (30, 0, 0), "RH": (60, 0, 8), "RK": (-70, 0, 0), "LH": (36, 0, -8), "LK": (-60, 0, 0)})
    # Coiled against the wall: knees up, hands braced, ready to spring.
    stick_a = {
        "Root": (12, 0, 0), "Waist": (16, 0, 0), "Neck": (-26, 0, 0), "Move": (0, -0.4, 0),
        "RS": (118, 0, 42), "RE": (64, 0, 0), "RW": (-24, 0, 0), "LS": (118, 0, -42), "LE": (64, 0, 0), "LW": (-24, 0, 0),
        "RH": (84, 0, 12), "RK": (-112, 0, 0), "RA": (30, 0, 0), "LH": (70, 0, -12), "LK": (-100, 0, 0), "LA": (30, 0, 0),
        "Grip": (-60, 0, 0),
    }
    stick_b = merge(stick_a, {"Move": (0, -0.46, 0), "Neck": (-22, 0, 0), "RE": (70, 0, 0), "LE": (70, 0, 0)})
    # Coils harder into the wall, then drives off it with both legs.
    kick_coil = merge(stick_a, {"Root": (24, 0, 0), "Move": (0, -0.7, 0), "RH": (100, 0, 12), "RK": (-128, 0, 0), "LH": (92, 0, -12), "LK": (-124, 0, 0)})
    kick_drive = merge(stick_a, {"Root": (-18, 0, 0), "Waist": (-8, 0, 0), "Neck": (10, 0, 0), "Move": (0, 0.1, 0), "RS": (30, 0, 50), "LS": (30, 0, -50), "RE": (30, 0, 0), "LE": (30, 0, 0), "RH": (14, 0, 8), "RK": (-14, 0, 0), "LH": (-10, 0, -8), "LK": (-24, 0, 0)})
    soft = {
        "Root": (-7, 0, 0), "Waist": (-7, 0, 0), "Neck": (9, 0, 0), "Move": (0, -0.5, 0),
        "RH": (34, 0, 8), "RK": (-58, 0, 0), "RA": (24, 0, 0), "LH": (28, 0, -8), "LK": (-54, 0, 0), "LA": (24, 0, 0),
        "RS": (16, 0, 28), "RE": (24, 0, 0), "LS": (16, 0, -28), "LE": (24, 0, 0),
    }
    # Over the shoulders, and out one of two ways. Root turns on the hips, but a curled-up body turns on
    # its own middle, up in the chest, so each key moves the hips to keep that middle at one height and
    # in one place. Without that the body swings round its hips and the head goes through the floor.
    curled = {
        "Waist": (-36, 0, 0), "Neck": (-30, 0, 0),
        "RS": (58, 0, 20), "RE": (112, 0, 0), "RW": (0, 0, 0), "LS": (58, 0, -20), "LE": (112, 0, 0), "LW": (0, 0, 0),
        "RH": (118, 0, 6), "RK": (-128, 0, 0), "RA": (30, 0, 0), "LH": (112, 0, -6), "LK": (-128, 0, 0), "LA": (30, 0, 0),
        "Grip": (-40, 0, 0),
    }
    reach = merge(curled, {"Waist": (-30, 0, 0), "Neck": (-8, 0, 0), "RS": (112, 0, 16), "RE": (22, 0, 0), "LS": (112, 0, -16), "LE": (22, 0, 0), "RH": (100, 0, 8), "RK": (-116, 0, 0), "LH": (86, 0, -8), "LK": (-108, 0, 0)})
    come_up = merge(curled, {"Waist": (-24, 0, 0), "Neck": (6, 0, 0), "RS": (34, 0, 30), "RE": (60, 0, 0), "LS": (34, 0, -30), "LE": (60, 0, 0), "RH": (92, 0, 8), "RK": (-112, 0, 0), "LH": (78, 0, -8), "LK": (-104, 0, 0)})

    def rolled(pitch, pose, lift=0):
        turn = math.radians(pitch)
        up = 1.1 * math.cos(turn) - 1.0 * math.sin(turn)
        ahead = 1.0 * math.cos(turn) + 1.1 * math.sin(turn)
        return merge(pose, {"Root": (-pitch, 0, 0), "Move": (0, lift - 0.1 - up, ahead)})

    # The same trick sideways: turns on the chest, this far clockwise from behind, so the right side
    # goes down first.
    def swung(angle, pose, lift=0):
        turn = math.radians(angle)
        return merge(READY, pose, {"Root": (-10, 0, -angle), "Move": (-1.1 * math.sin(turn), lift + 1.1 * (1 - math.cos(turn)), 0)})

    roll_start = [
        (0, rolled(26, reach)),
        (2, rolled(64, reach, -0.25)),
        (4, rolled(126, curled, -0.1)),
        (6, rolled(194, curled, -0.05)),
        (8, rolled(262, curled, -0.7)),
    ]
    # A forward roll already passes through the lean of a slide on its way round: at 308 degrees it stops
    # there, sat back with the lead leg out, so the slide carries on with nothing to turn back through.
    settled = merge(slide_a, {"Root": (-308, 0, 0)})
    # Thrown back off a wall: head whipped up, arms flung out, legs going out from under you, then sat
    # flat on the deck, legs out and hands propped behind, with the head going round.
    sat = {
        "Root": (14, 0, 0), "Waist": (-12, 0, 0), "Neck": (-10, 0, 0), "Move": (0, -1.95, 0),
        "RS": (-38, 0, 26), "RE": (10, 0, 0), "RW": (0, 0, 0), "LS": (-38, 0, -26), "LE": (10, 0, 0), "LW": (0, 0, 0),
        "RH": (80, 0, 12), "RK": (-22, 0, 0), "RA": (-22, 0, 0), "LH": (86, 0, -14), "LK": (-38, 0, 0), "LA": (-16, 0, 0),
        "Grip": (-50, 0, 0),
    }
    thrown = merge(sat, {
        "Root": (34, 0, 0), "Waist": (12, 0, 0), "Neck": (32, 0, 0), "Move": (0, -0.5, 0),
        "RS": (118, 0, 58), "RE": (20, 0, 0), "LS": (104, 0, -58), "LE": (28, 0, 0),
        "RH": (34, 0, 10), "RK": (-34, 0, 0), "RA": (10, 0, 0), "LH": (16, 0, -10), "LK": (-52, 0, 0), "LA": (10, 0, 0),
    })
    falling_back = merge(thrown, {"Root": (46, 0, 0), "Waist": (4, 0, 0), "Neck": (12, 0, 0), "Move": (0, -1.1, 0), "RS": (150, 0, 50), "LS": (136, 0, -50), "RH": (62, 0, 12), "RK": (-24, 0, 0), "LH": (48, 0, -12), "LK": (-36, 0, 0)})
    slumped = merge(sat, {"Root": (6, 0, 0), "Waist": (-26, 0, 0), "Neck": (-26, 0, 0), "Move": (0, -2.05, 0), "RS": (-20, 0, 34), "LS": (-20, 0, -34), "RH": (86, 0, 12), "LH": (92, 0, -14)})
    def dizzy(pitch, yaw, roll, sway):
        return merge(sat, {"Neck": (pitch, yaw, roll), "Waist": (-12, sway * 5, sway * 4), "Root": (14, 0, sway * 2)})
    getting_up = merge(sat, {
        "Root": (-26, 0, 0), "Waist": (-24, 0, 0), "Neck": (10, 0, 0), "Move": (0, -1.6, 0),
        "RS": (30, 0, 30), "RE": (50, 0, 0), "LS": (-20, 0, -30), "LE": (20, 0, 0),
        "RH": (104, 0, 10), "RK": (-120, 0, 0), "RA": (30, 0, 0), "LH": (112, 0, -12), "LK": (-126, 0, 0), "LA": (30, 0, 0),
    })
    # Feet on the wall to your right, body leaning out from it. The legs run; the chest comes back
    # toward upright so you're looking where you're going, and the arms pump. Mirrored for the left.
    wall_lean = {"Root": (-10, 0, 46), "Waist": (-8, 0, -14), "Neck": (6, 0, -18), "Move": (0.45, -0.2, 0), "Grip": (-40, 0, 0)}
    wall_reach = merge(wall_lean, {"RH": (70, 0, 0), "RK": (-58, 0, 0), "RA": (12, 0, 0), "LH": (-34, 0, 0), "LK": (-52, 0, 0), "LA": (30, 0, 0), "RS": (-34, 0, 18), "RE": (86, 0, 0), "LS": (62, 0, -30), "LE": (74, 0, 0)})
    wall_pass = merge(wall_lean, {"Move": (0.45, -0.1, 0), "RH": (16, 0, 0), "RK": (-34, 0, 0), "RA": (22, 0, 0), "LH": (40, 0, 0), "LK": (-112, 0, 0), "LA": (24, 0, 0), "RS": (14, 0, 22), "RE": (80, 0, 0), "LS": (14, 0, -26), "LE": (80, 0, 0)})
    def swap_legs(pose):
        out = merge(pose)
        for right, left in (("RH", "LH"), ("RK", "LK"), ("RA", "LA"), ("RS", "LS"), ("RE", "LE")):
            r, l = pose[right], pose[left]
            out[right] = (l[0], l[1], abs(l[2]) if right == "RS" else l[2])
            out[left] = (r[0], r[1], -abs(r[2]) if left == "LS" else r[2])
        return out
    wall_run = [(0, wall_reach), (4, wall_pass), (8, swap_legs(wall_reach)), (12, swap_legs(wall_pass)), (16, wall_reach)]
    # Over a car's hood: the right hand reaches for the top and plants straight-armed, the body turns
    # side-on and drops onto its back across the top, and goes round on it, legs split and sweeping
    # over, until it comes off the far side facing the way it was going. Never upside down. Plant is
    # where the hand lands, which the game lines up with the body reaching the face. VaultLeft is it
    # mirrored.
    vault_right = [
        (0, merge(READY, {"Root": (-18, 0, 0), "Waist": (-8, 0, 0), "Neck": (10, 0, 0), "RS": (70, 0, 18), "RE": (16, 0, 0), "LS": (-34, 0, -18), "LE": (46, 0, 0), "RH": (64, 0, 4), "RK": (-78, 0, 0), "LH": (-22, 0, -4), "LK": (-30, 0, 0)})),
        (3, hooded(22, 18, {"Waist": (-6, 0, 0), "Neck": (8, 0, 0), "LS": (20, 0, -60), "LE": (40, 0, 0), "RH": (78, 0, 10), "RK": (-90, 0, 0), "LH": (30, 0, -8), "LK": (-70, 0, 0)}, 0.4, arm=(0.25, -0.75, -0.6))),
        (6, hooded(78, 58, {"Waist": (4, 0, 0), "Neck": (-14, 0, 0), "LS": (40, 0, -110), "LE": (20, 0, 0), "RH": (84, 0, 18), "RK": (-60, 0, 0), "LH": (50, 0, -26), "LK": (-40, 0, 0)}, 1.6, arm=(0.3, -0.85, -0.45), elbow=20)),
        (9, hooded(158, 76, {"Waist": (8, 0, 0), "Neck": (-20, 0, 0), "LS": (10, 0, -130), "LE": (14, 0, 0), "RH": (96, 0, 34), "RK": (-24, 0, 0), "LH": (60, 0, -40), "LK": (-30, 0, 0)}, 1.9, arm=(0.15, -1, 0.05), elbow=36)),
        (12, hooded(240, 66, {"Waist": (4, 0, 0), "Neck": (-10, 0, 0), "LS": (30, 0, -100), "LE": (20, 0, 0), "RH": (72, 0, 26), "RK": (-50, 0, 0), "LH": (36, 0, -30), "LK": (-60, 0, 0)}, 1.6, arm=(-0.1, -0.8, 0.5), elbow=30)),
        (15, hooded(318, 30, {"Waist": (-4, 0, 0), "Neck": (6, 0, 0), "RE": (30, 0, 0), "LS": (30, 0, -44), "LE": (40, 0, 0), "RH": (56, 0, 10), "RK": (-70, 0, 0), "LH": (10, 0, -8), "LK": (-40, 0, 0)}, 1.4, arm=(0.6, -0.5, 0.3))),
        (18, merge(soft, {"Root": (-12, 360, 0), "Waist": (-10, 0, 0), "Neck": (12, 0, 0), "Move": (0, -0.4, 0), "RS": (30, 0, 46), "LS": (36, 0, -40)})),
    ]
    return [
        Clip("WallBonk", [(0, thrown), (4, falling_back), (8, slumped), (11, sat)], {"End": 11}),
        Clip("Dazed", [(0, dizzy(-10, 0, 0, 0)), (10, dizzy(-4, 26, 12, 1)), (20, dizzy(8, 0, 0, 0)), (30, dizzy(-4, -26, -12, -1)), (40, dizzy(-10, 0, 0, 0))], loop=True),
        Clip("DazeUp", [(0, sat), (4, getting_up), (8, merge(crouch, {"Neck": (6, 0, 0)})), (12, READY)], {"End": 12}),
        Clip("WallRunRight", wall_run, loop=True),
        Clip("WallRunLeft", [(frame, mirror(pose)) for frame, pose in wall_run], loop=True),
        # Shares its start with RollSlide up to frame 8, where PoseAnimator.Fork can swap between them.
        Clip("Roll", roll_start + [
            (10, rolled(322, come_up, 0.45)),
            (12, merge(rolled(352, come_up, 0.45), {"Neck": (12, 0, 0)})),
            (14, merge(soft, {"Root": (-367, 0, 0), "Waist": (-12, 0, 0), "Neck": (14, 0, 0), "Move": (0, -0.38, 0)})),
        ], {"End": 14}),
        Clip("RollSlide", roll_start + [
            (10, merge(lerp(curled, slide_a, 0.6), {"Root": (-298, 0, 0), "Move": (0, -1.25, 0)})),
            (12, merge(lerp(curled, slide_a, 0.9), {"Root": (-313, 0, 0), "Move": (0, -1.05, 0)})),
            (14, settled),
        ], {"End": 14}),
        Clip("LandSoft", [(0, soft), (2, soft), (6, READY)], {"End": 6}),
        Clip("WallKick", [(0, stick_a), (2, kick_coil), (4, kick_drive), (8, READY)], {"End": 8}),
        Clip("WallStick", [(0, stick_a), (6, stick_b), (12, stick_a)], loop=True),
        Clip("Leap", [(0, merge(slide_a, {"Root": (20, 0, 0), "Move": (0, -0.8, 0)})), (3, leap_a), (10, leap_b), (15, leap_land)], {"End": 15}),
        Clip("Slide", [(0, slide_a), (3, slide_b), (6, slide_a)], loop=True),
        Clip("LedgeCatch", [(0, catch_reach), (2, catch_impact), (6, catch_swing), (10, catch_back), (14, hang_a)], {"End": 14}),
        Clip("Hang", [(0, hang_a), (26, hang_b), (52, hang_a)], loop=True),
        Clip("Climb", [(0, hang_a), (4, pull), (8, vault), (12, READY)], {"End": 12}),
        Clip("VaultRight", vault_right, {"Plant": 6, "End": 18}),
        Clip("VaultLeft", [(frame, mirror(pose)) for frame, pose in vault_right], {"Plant": 6, "End": 18}),
        # A knee driven up onto it, then the back leg following through.
        Clip("StepUp", [
            (0, merge(READY, {"Root": (-22, 0, 0), "Waist": (-8, 0, 0), "Neck": (10, 0, 0), "RS": (-24, 0, 8), "RE": (70, 0, 0), "LS": (64, 0, -8), "LE": (70, 0, 0), "RH": (102, 0, 4), "RK": (-112, 0, 0), "LH": (-14, 0, -3), "LK": (-30, 0, 0)})),
            (4, merge(READY, {"Root": (-26, 0, 0), "Waist": (-6, 0, 0), "Neck": (12, 0, 0), "Move": (0, 0.2, 0), "RS": (20, 0, 8), "RE": (60, 0, 0), "LS": (10, 0, -8), "LE": (60, 0, 0), "RH": (54, 0, 4), "RK": (-46, 0, 0), "LH": (-34, 0, -3), "LK": (-22, 0, 0)})),
            (7, merge(READY, {"Root": (-16, 0, 0), "Waist": (-4, 0, 0), "Neck": (8, 0, 0), "RS": (52, 0, 8), "RE": (70, 0, 0), "LS": (-20, 0, -8), "LE": (70, 0, 0), "RH": (-12, 0, 3), "RK": (-26, 0, 0), "LH": (84, 0, -4), "LK": (-96, 0, 0)})),
            (11, READY),
        ], {"End": 11}),
        Clip("WallSlide", [(0, slide_a), (5, slide_b), (10, slide_a)], loop=True),
        Clip("Flip", [
            (0, merge(tuck, {"Root": (0, 0, 0)})),
            (3, merge(tuck, {"Root": (-90, 0, 0)})),
            (6, merge(tuck, {"Root": (-180, 0, 0)})),
            (9, merge(tuck, {"Root": (-270, 0, 0)})),
            (12, merge(tuck, {"Root": (-360, 0, 0)})),
        ], {"End": 12}),
        Clip("Skid", [(0, READY), (3, skid), (8, skid), (12, READY)], {"End": 12}),
        # Pulling up out of a run: the front foot goes out and takes it, the body leans back against
        # the speed, the arms come up for balance, and it settles.
        Clip("RunStop", [
            (0, merge(READY, {"Root": (-14, 0, 0), "Waist": (-6, 0, 0), "RS": (24, 0, 16), "LS": (-20, 0, -16), "RE": (40, 0, 0), "LE": (40, 0, 0), "RH": (44, 0, 4), "RK": (-50, 0, 0), "LH": (-18, 0, -4), "LK": (-40, 0, 0)})),
            (3, merge(READY, {"Root": (16, 0, 4), "Waist": (10, 0, 0), "Neck": (-10, 0, 0), "Move": (0, -0.75, 0.3), "RS": (46, 0, 44), "RE": (34, 0, 0), "LS": (34, 0, -52), "LE": (28, 0, 0), "RH": (66, 0, 6), "RK": (-14, 0, 0), "RA": (-24, 0, 0), "LH": (8, 0, -6), "LK": (-74, 0, 0), "LA": (30, 0, 0)})),
            (8, merge(READY, {"Root": (20, 0, -2), "Waist": (12, 0, 0), "Neck": (-12, 0, 0), "Move": (0, -0.95, 0.4), "RS": (60, 0, 56), "RE": (24, 0, 0), "LS": (22, 0, -62), "LE": (24, 0, 0), "RH": (70, 0, 6), "RK": (-20, 0, 0), "RA": (-26, 0, 0), "LH": (14, 0, -6), "LK": (-86, 0, 0), "LA": (34, 0, 0)})),
            (12, merge(READY, {"Root": (6, 0, 0), "Waist": (2, 0, 0), "Move": (0, -0.5, 0.1), "RS": (20, 0, 26), "LS": (16, 0, -26), "RH": (30, 0, 5), "RK": (-30, 0, 0), "LH": (6, 0, -5), "LK": (-44, 0, 0)})),
            (16, READY),
        ], {"End": 16}),
        Clip("Land", [(0, crouch), (3, crouch), (10, READY)], {"End": 10}),
    ]


def all_clips():
    clips = [idle(), run()] + strafe() + stances() + states() + traversal() + [kick()]
    for name, (wind, strike, follow) in ATTACKS.items():
        clips.append(swing(name, wind, strike, follow, two_hand=name in ALWAYS_TWO_HANDED))
        if name in TWO_HANDED_VARIANTS:
            clips.append(swing(name + "_TwoHand", wind, strike, follow, two_hand=True))
    clips.append(swing("Slap", *SLAP, frames=SLAP_FRAMES))
    clips.append(swing("SlapBack", *SLAP_BACK, frames=SLAP_FRAMES))
    clips.append(swing("SlapRise", *SLAP_RISE, frames=SLAP_RISE_FRAMES))
    clips.append(swing("SlapCharge", *SLAP_CHARGE, frames=SLAP_CHARGE_FRAMES))
    clips.append(spin_clip("Spin"))
    clips.append(spin_clip("Spin_TwoHand", two_hand=True))
    # The Scramble's own weapons. Imported here, not at the top: that file builds on this one.
    import clips_weapons

    clips += clips_weapons.all_clips()
    return clips
