"""The Scramble's own weapon animations: for each of the four weapons, how it is held and its moves.

Every weapon gets a stance (a loop of the arms and a little of the body, played over whatever the
legs are doing) and four moves: the three swings of its light chain and its charged heavy. Moves
are built by clips_core.swing, so each carries the Wind, Strike and End markers the game retimes
to that move's own Startup, Active and Recovery.

Reading a pose: shoulders and hips +pitch swing forward, elbows bend with +pitch, knees with
-pitch; Root and Waist -pitch lean forward and +yaw turn left; a right shoulder's +roll carries
the arm out to the right, -roll across the body. The weapon's tip sits roughly (shoulder pitch +
elbow pitch + Grip pitch) degrees above level, so Grip is what aims it.

The sword and knife are one-handed. The axe and spear are held in both hands with the front
hand well up the haft (two_hand="far"); the right hand is the back hand.
"""

from clips_core import READY, coil, lean, lerp, swing
from fias_pose import Clip, merge


def stance(name, base, weapon, two_hand=False, breath=3):
    """A held pose that breathes: the arms rise and settle over two seconds."""
    rise = dict(base)
    rise["RS"] = (base["RS"][0] + breath, base["RS"][1], base["RS"][2])
    rise["RE"] = (base["RE"][0] + breath, 0, 0)
    return Clip("Stance" + name, [(0, base), (30, rise), (60, base)], loop=True, two_hand=two_hand, weapon=weapon)


def move(name, weapon, wind, strike, follow, frames, two_hand=False):
    return swing(name, wind, strike, follow, frames=frames, extra={"weapon": weapon}, two_hand=two_hand)


# ---------------------------------------------------------------- sword
#
# Held up and forward, point at the other fighter's face, off hand out for balance. Two cuts that
# cross (down from the right shoulder, back up from the left hip), a chop, and a lunge.


def sword():
    w = "Sword"
    hold = {
        "Grip": (-34, 0, 0), "RS": (24, 0, 20), "RE": (58, 0, 0), "RW": (0, 0, 0),
        "LS": (26, 0, -22), "LE": (52, 0, 0), "LW": (0, 0, 0),
        "Waist": (-2, -12, 0), "Neck": (0, 10, 0),
    }
    off_back = {"LS": (-24, 0, -30), "LE": (34, 0, 0)}
    off_guard = {"LS": (40, 0, -24), "LE": (70, 0, 0)}
    cut_down = (
        merge(coil(0.25), off_guard, {"Grip": (-20, 0, 0), "RS": (128, 0, 56), "RE": (76, 0, 0), "RW": (8, 0, 10), "Waist": (6, -44, 0), "Neck": (0, 34, 0), "Root": (2, -14, 0)}),
        merge(lean(0.4), off_back, {"Grip": (-84, 0, 0), "RS": (74, 0, -34), "RE": (10, 0, 0), "RW": (0, 0, -12), "Waist": (-10, 42, 0), "Neck": (0, -28, 0), "Root": (-8, 16, 0)}),
        merge(lean(0.3), off_back, {"Grip": (-66, 0, 0), "RS": (38, 0, -62), "RE": (30, 0, 0), "RW": (-6, 0, -16), "Waist": (-6, 50, 0), "Neck": (0, -32, 0), "Root": (-6, 20, 0)}),
    )
    cut_up = (
        merge(coil(0.3), off_guard, {"Grip": (-58, 0, 0), "RS": (46, 0, -62), "RE": (72, 0, 0), "RW": (4, 0, -14), "Waist": (-4, 44, 0), "Neck": (0, -30, 0), "Root": (0, 14, 0)}),
        merge(lean(0.3), off_back, {"Grip": (-84, 0, 0), "RS": (96, 0, 46), "RE": (8, 0, 0), "RW": (0, 0, 14), "Waist": (-4, -38, 0), "Neck": (0, 26, 0), "Root": (-6, -16, 0)}),
        merge(lean(0.2), off_back, {"Grip": (-52, 0, 0), "RS": (126, 0, 70), "RE": (28, 0, 0), "RW": (-6, 0, 16), "Waist": (2, -50, 0), "Neck": (0, 32, 0), "Root": (-2, -20, 0)}),
    )
    chop = (
        merge(coil(0.15), off_guard, {"Grip": (-30, 0, 0), "RS": (174, 0, 12), "RE": (58, 0, 0), "RW": (-14, 0, 0), "Waist": (16, -12, 0), "Neck": (12, 10, 0), "Root": (6, 0, 0)}),
        merge(lean(0.8), off_back, {"Grip": (-80, 0, 0), "RS": (82, 0, 2), "RE": (6, 0, 0), "RW": (18, 0, 0), "Waist": (-30, 6, 0), "Neck": (-6, 0, 0)}),
        merge(lean(0.7), off_back, {"Grip": (-64, 0, 0), "RS": (42, 0, 6), "RE": (14, 0, 0), "RW": (8, 0, 0), "Waist": (-36, 8, 0), "Neck": (-10, 0, 0)}),
    )
    lunge = (
        merge(coil(0.45), off_guard, {"Grip": (-74, 0, 0), "RS": (-28, 28, 20), "RE": (104, 0, 0), "RW": (0, 0, 0), "Waist": (8, -40, 0), "Neck": (0, 30, 0), "Root": (2, -16, 0)}),
        merge(lean(0.85), off_back, {"Grip": (-62, 0, 0), "RS": (98, 0, 22), "RE": (0, 0, 0), "Waist": (-20, 36, 0), "Neck": (-2, -24, 0), "Root": (-14, 16, 0), "Move": (0, -0.85, -0.75)}),
        merge(lean(0.7), off_back, {"Grip": (-64, 0, 0), "RS": (84, 0, 16), "RE": (18, 0, 0), "Waist": (-16, 30, 0), "Neck": (-2, -20, 0), "Root": (-10, 14, 0), "Move": (0, -0.7, -0.55)}),
    )
    return [
        stance("Sword", hold, w),
        move("SwordCutDown", w, *cut_down, frames=(5, 8, 12, 21, 30)),
        move("SwordCutUp", w, *cut_up, frames=(5, 8, 12, 21, 30)),
        move("SwordChop", w, *chop, frames=(6, 9, 13, 23, 32)),
        move("SwordLunge", w, *lunge, frames=(6, 10, 14, 24, 34)),
    ]


# ---------------------------------------------------------------- knife
#
# A low guard, the blade out in front and the empty hand up. Everything is short and tight: a
# flick across, a flick back, a straight stab from the hip, and a lunge behind the point.


def knife():
    w = "Knife"
    hold = {
        "Grip": (-112, 0, 0), "RS": (38, 0, 8), "RE": (98, 0, 0), "RW": (0, 0, 0),
        "LS": (52, 0, -8), "LE": (104, 0, 0), "LW": (0, 0, 0),
        "Waist": (-8, -10, 0), "Neck": (6, 8, 0),
    }
    guard_up = {"LS": (56, 0, -10), "LE": (108, 0, 0)}
    guard_back = {"LS": (20, 0, -26), "LE": (84, 0, 0)}
    flick_in = (
        merge(coil(0.3), guard_up, {"Grip": (-104, 0, 0), "RS": (74, 0, 52), "RE": (92, 0, 0), "RW": (0, 0, 14), "Waist": (-4, -30, 0), "Neck": (4, 24, 0), "Root": (-2, -10, 0)}),
        merge(lean(0.35), guard_back, {"Grip": (-106, 0, 0), "RS": (84, 0, -30), "RE": (30, 0, 0), "RW": (0, 0, -18), "Waist": (-10, 30, 0), "Neck": (4, -22, 0), "Root": (-8, 12, 0)}),
        merge(lean(0.3), guard_back, {"Grip": (-104, 0, 0), "RS": (66, 0, -54), "RE": (72, 0, 0), "RW": (0, 0, -20), "Waist": (-8, 36, 0), "Neck": (4, -26, 0), "Root": (-6, 14, 0)}),
    )
    flick_out = (
        merge(coil(0.3), guard_up, {"Grip": (-104, 0, 0), "RS": (70, 0, -56), "RE": (96, 0, 0), "RW": (0, 0, -16), "Waist": (-6, 32, 0), "Neck": (4, -24, 0), "Root": (-2, 10, 0)}),
        merge(lean(0.35), guard_back, {"Grip": (-106, 0, 0), "RS": (86, 0, 34), "RE": (26, 0, 0), "RW": (0, 0, 18), "Waist": (-8, -28, 0), "Neck": (4, 20, 0), "Root": (-8, -12, 0)}),
        merge(lean(0.3), guard_back, {"Grip": (-104, 0, 0), "RS": (70, 0, 60), "RE": (64, 0, 0), "RW": (0, 0, 20), "Waist": (-6, -34, 0), "Neck": (4, 24, 0), "Root": (-6, -14, 0)}),
    )
    stab = (
        merge(coil(0.35), guard_up, {"Grip": (-88, 0, 0), "RS": (-26, 0, 18), "RE": (112, 0, 0), "RW": (0, 0, 0), "Waist": (-4, -36, 0), "Neck": (4, 28, 0), "Root": (0, -12, 0)}),
        merge(lean(0.5), guard_back, {"Grip": (-64, 0, 0), "RS": (86, 0, 18), "RE": (4, 0, 0), "Waist": (-14, 34, 0), "Neck": (2, -24, 0), "Root": (-10, 14, 0), "Move": (0, -0.5, -0.4)}),
        merge(lean(0.4), guard_back, {"Grip": (-84, 0, 0), "RS": (70, 0, 12), "RE": (40, 0, 0), "Waist": (-10, 26, 0), "Neck": (2, -18, 0), "Root": (-8, 10, 0), "Move": (0, -0.4, -0.3)}),
    )
    lunge = (
        merge(coil(0.55), guard_up, {"Grip": (-84, 0, 0), "RS": (-40, 0, 22), "RE": (120, 0, 0), "RW": (0, 0, 0), "Waist": (4, -50, 0), "Neck": (0, 36, 0), "Root": (2, -20, 0)}),
        merge(lean(1.0), guard_back, {"Grip": (-52, 0, 0), "RS": (100, 0, 22), "RE": (0, 0, 0), "Waist": (-24, 40, 0), "Neck": (4, -26, 0), "Root": (-18, 18, 0), "Move": (0, -1.0, -0.9)}),
        merge(lean(0.8), guard_back, {"Grip": (-74, 0, 0), "RS": (80, 0, 16), "RE": (34, 0, 0), "Waist": (-18, 30, 0), "Neck": (4, -20, 0), "Root": (-12, 14, 0), "Move": (0, -0.8, -0.65)}),
    )
    quick = (3, 5, 8, 14, 20)
    return [
        stance("Knife", hold, w, breath=2),
        move("KnifeFlickIn", w, *flick_in, frames=quick),
        move("KnifeFlickOut", w, *flick_out, frames=quick),
        move("KnifeStab", w, *stab, frames=(3, 6, 9, 15, 22)),
        move("KnifeLunge", w, *lunge, frames=(6, 10, 13, 22, 32)),
    ]


# ---------------------------------------------------------------- axe
#
# Carried across the body in both hands, head up by the right shoulder. Two big level swings that
# drag the whole torso round, a chop over the head, and a cleave that ends on the floor.


def axe():
    w = "Axe"
    hold = {
        "Grip": (-22, 0, 0), "RS": (4, 0, 12), "RE": (74, 0, 0), "RW": (0, 0, 0),
        "Waist": (0, -16, 0), "Neck": (0, 12, 0),
    }
    swing_in = (
        merge(coil(0.4), {"Grip": (-50, 0, 0), "RS": (112, 0, 70), "RE": (74, 0, 0), "Waist": (12, -64, 0), "Neck": (0, 48, 0), "Root": (4, -24, 0)}),
        merge(lean(0.55), {"Grip": (-88, 0, 0), "RS": (84, 0, -30), "RE": (10, 0, 0), "Waist": (-10, 48, 0), "Neck": (0, -32, 0), "Root": (-8, 26, 0)}),
        merge(lean(0.4), {"Grip": (-62, 0, 0), "RS": (88, 0, -72), "RE": (44, 0, 0), "Waist": (-4, 68, 0), "Neck": (0, -42, 0), "Root": (-4, 36, 0)}),
    )
    swing_out = (
        merge(coil(0.4), {"Grip": (-56, 0, 0), "RS": (92, 0, -74), "RE": (64, 0, 0), "Waist": (8, 66, 0), "Neck": (0, -46, 0), "Root": (4, 26, 0)}),
        merge(lean(0.55), {"Grip": (-88, 0, 0), "RS": (86, 0, 36), "RE": (8, 0, 0), "Waist": (-10, -44, 0), "Neck": (0, 30, 0), "Root": (-8, -24, 0)}),
        merge(lean(0.4), {"Grip": (-60, 0, 0), "RS": (104, 0, 76), "RE": (40, 0, 0), "Waist": (-4, -64, 0), "Neck": (0, 42, 0), "Root": (-4, -34, 0)}),
    )
    chop = (
        merge(coil(0.1), {"Grip": (-26, 0, 0), "RS": (176, 0, 4), "RE": (48, 0, 0), "Waist": (20, -6, 0), "Neck": (16, 4, 0), "Root": (10, 0, 0), "Move": (0, 0.25, 0.15)}),
        merge(lean(0.85), {"Grip": (-82, 0, 0), "RS": (70, 0, -2), "RE": (6, 0, 0), "Waist": (-34, 4, 0), "Neck": (-6, 0, 0)}),
        merge(lean(0.8), {"Grip": (-76, 0, 0), "RS": (48, 0, -2), "RE": (12, 0, 0), "Waist": (-40, 4, 0), "Neck": (-10, 0, 0)}),
    )
    cleave = (
        merge(coil(0.0), {"Grip": (-20, 0, 0), "RS": (184, 0, -4), "RE": (40, 0, 0), "Waist": (26, 0, 0), "Neck": (20, 0, 0), "Root": (14, 0, 0), "Move": (0, 0.55, 0.25)}),
        merge(lean(1.15), {"Grip": (-46, 0, 0), "RS": (44, 0, -4), "RE": (4, 0, 0), "Waist": (-46, 0, 0), "Neck": (-6, 0, 0), "Move": (0, -1.15, -0.5)}),
        merge(lean(1.1), {"Grip": (-48, 0, 0), "RS": (30, 0, -4), "RE": (10, 0, 0), "Waist": (-50, 0, 0), "Neck": (-12, 0, 0), "Move": (0, -1.1, -0.45)}),
    )
    heavy = (7, 11, 15, 26, 36)
    return [
        stance("Axe", hold, w, two_hand="far"),
        move("AxeSwingIn", w, *swing_in, frames=heavy, two_hand="far"),
        move("AxeSwingOut", w, *swing_out, frames=heavy, two_hand="far"),
        move("AxeChop", w, *chop, frames=heavy, two_hand="far"),
        move("AxeCleave", w, *cleave, frames=(8, 12, 16, 28, 40), two_hand="far"),
    ]


# ---------------------------------------------------------------- spear
#
# Couched at the right hip, point forward, body side-on behind it. The back hand does the work:
# two jabs (the second higher), a sweep with the shaft, and a full lunge.


def spear():
    w = "Spear"
    side_on = {"Waist": (-2, -34, 0), "Neck": (0, 30, 0)}
    hold = merge(side_on, {"Grip": (-42, 0, 0), "RS": (-22, 30, 14), "RE": (66, 0, 0), "RW": (0, 0, 0)})
    jab = (
        merge(coil(0.3), {"Grip": (-36, 0, 0), "RS": (-48, 46, 16), "RE": (86, 0, 0), "Waist": (2, -40, 0), "Neck": (0, 36, 0), "Root": (2, -10, 0)}),
        merge(lean(0.5), {"Grip": (-64, 0, 0), "RS": (62, 0, 14), "RE": (22, 0, 0), "Waist": (-12, 10, 0), "Neck": (0, -4, 0), "Root": (-8, 8, 0), "Move": (0, -0.5, -0.45)}),
        merge(lean(0.4), {"Grip": (-70, 0, 0), "RS": (30, 0, 0), "RE": (40, 0, 0), "Waist": (-8, -6, 0), "Neck": (0, 8, 0), "Root": (-6, 4, 0), "Move": (0, -0.4, -0.3)}),
    )
    jab_high = (
        merge(coil(0.25), {"Grip": (-30, 0, 0), "RS": (-40, 46, 18), "RE": (92, 0, 0), "Waist": (4, -40, 0), "Neck": (0, 36, 0), "Root": (2, -10, 0)}),
        merge(lean(0.4), {"Grip": (-64, 0, 0), "RS": (78, 0, 14), "RE": (16, 0, 0), "Waist": (-8, 12, 0), "Neck": (4, -6, 0), "Root": (-6, 8, 0), "Move": (0, -0.4, -0.45)}),
        merge(lean(0.35), {"Grip": (-68, 0, 0), "RS": (40, 0, 0), "RE": (40, 0, 0), "Waist": (-6, -6, 0), "Neck": (2, 8, 0), "Root": (-4, 4, 0), "Move": (0, -0.35, -0.3)}),
    )
    sweep = (
        merge(coil(0.4), {"Grip": (-70, 0, 0), "RS": (30, 0, 64), "RE": (60, 0, 0), "Waist": (6, -70, 0), "Neck": (0, 52, 0), "Root": (2, -26, 0)}),
        merge(lean(0.45), {"Grip": (-88, 0, 0), "RS": (70, 0, -18), "RE": (20, 0, 0), "Waist": (-8, 40, 0), "Neck": (0, -28, 0), "Root": (-6, 22, 0)}),
        merge(lean(0.35), {"Grip": (-80, 0, 0), "RS": (64, 0, -52), "RE": (36, 0, 0), "Waist": (-4, 62, 0), "Neck": (0, -40, 0), "Root": (-4, 32, 0)}),
    )
    lunge = (
        merge(coil(0.55), {"Grip": (-34, 0, 0), "RS": (-56, 50, 18), "RE": (90, 0, 0), "Waist": (6, -44, 0), "Neck": (0, 40, 0), "Root": (4, -12, 0), "Move": (0, -0.55, 0.3)}),
        merge(lean(1.0), {"Grip": (-50, 0, 0), "RS": (88, 0, 16), "RE": (2, 0, 0), "Waist": (-22, 22, 0), "Neck": (6, -10, 0), "Root": (-16, 12, 0), "Move": (0, -1.0, -1.0)}),
        merge(lean(0.8), {"Grip": (-58, 0, 0), "RS": (60, 0, 8), "RE": (26, 0, 0), "Waist": (-16, 10, 0), "Neck": (4, -2, 0), "Root": (-10, 8, 0), "Move": (0, -0.8, -0.7)}),
    )
    return [
        stance("Spear", hold, w, two_hand="far", breath=2),
        move("SpearJab", w, *jab, frames=(4, 7, 10, 18, 26), two_hand="far"),
        move("SpearJabHigh", w, *jab_high, frames=(4, 7, 10, 18, 26), two_hand="far"),
        move("SpearSweep", w, *sweep, frames=(6, 10, 14, 24, 34), two_hand="far"),
        move("SpearLunge", w, *lunge, frames=(6, 10, 14, 25, 36), two_hand="far"),
    ]


# ---------------------------------------------------------------- fists
#
# What you fight with when nothing is in hand. A boxer's guard, left side forward, both fists by
# the chin. A left jab, a right cross, a left hook round the side, and a charged right haymaker
# thrown over the top. A left shoulder mirrors the right: -roll carries it out to the left, +roll
# across the body.


def fists():
    guard_r = {"RS": (62, 0, -12), "RE": (112, 0, 0), "RW": (0, 0, 0)}
    guard_l = {"LS": (68, 0, 10), "LE": (114, 0, 0), "LW": (0, 0, 0)}
    hold = merge(guard_r, guard_l, {"Waist": (-4, -16, 0), "Neck": (4, 14, 0)})
    jab = (
        merge(coil(0.15), guard_r, {"LS": (54, 0, 12), "LE": (124, 0, 0), "Waist": (0, -22, 0), "Neck": (4, 18, 0), "Root": (0, -6, 0)}),
        merge(lean(0.3), guard_r, {"LS": (92, 0, 6), "LE": (2, 0, 0), "Waist": (-8, -34, 0), "Neck": (4, 26, 0), "Root": (-4, -8, 0)}),
        merge(lean(0.25), guard_r, {"LS": (86, 0, 6), "LE": (24, 0, 0), "Waist": (-6, -30, 0), "Neck": (4, 22, 0), "Root": (-4, -6, 0)}),
    )
    cross = (
        merge(coil(0.25), guard_l, {"RS": (46, 0, -8), "RE": (126, 0, 0), "Waist": (2, -32, 0), "Neck": (2, 24, 0), "Root": (0, -10, 0)}),
        merge(lean(0.4), guard_l, {"RS": (102, 0, -6), "RE": (2, 0, 0), "Waist": (-10, 38, 0), "Neck": (2, -28, 0), "Root": (-6, 14, 0)}),
        merge(lean(0.35), guard_l, {"RS": (86, 0, -8), "RE": (22, 0, 0), "Waist": (-8, 42, 0), "Neck": (2, -30, 0), "Root": (-6, 16, 0)}),
    )
    hook = (
        merge(coil(0.3), guard_r, {"LS": (74, 0, -58), "LE": (86, 0, 0), "Waist": (4, 30, 0), "Neck": (2, -22, 0), "Root": (2, 12, 0)}),
        merge(lean(0.35), guard_r, {"LS": (86, 0, 14), "LE": (84, 0, 0), "Waist": (-8, -42, 0), "Neck": (2, 32, 0), "Root": (-6, -16, 0)}),
        merge(lean(0.3), guard_r, {"LS": (80, 0, 34), "LE": (92, 0, 0), "Waist": (-6, -50, 0), "Neck": (2, 36, 0), "Root": (-4, -20, 0)}),
    )
    haymaker = (
        merge(coil(0.45), guard_l, {"RS": (112, 0, 58), "RE": (94, 0, 0), "Waist": (6, -48, 0), "Neck": (2, 34, 0), "Root": (2, -16, 0)}),
        merge(lean(0.55), guard_l, {"RS": (114, 0, -8), "RE": (10, 0, 0), "Waist": (-16, 44, 0), "Neck": (0, -30, 0), "Root": (-10, 18, 0)}),
        merge(lean(0.65), guard_l, {"RS": (74, 0, -38), "RE": (32, 0, 0), "Waist": (-12, 52, 0), "Neck": (0, -34, 0), "Root": (-8, 20, 0)}),
    )
    return [
        stance("Fists", hold, None, breath=2),
        move("FistsJab", None, *jab, frames=(3, 5, 8, 14, 20)),
        move("FistsCross", None, *cross, frames=(3, 6, 9, 15, 22)),
        move("FistsHook", None, *hook, frames=(4, 7, 11, 19, 28)),
        move("FistsHaymaker", None, *haymaker, frames=(6, 10, 14, 24, 34)),
    ]


# ---------------------------------------------------------------- throw, pull, finisher
#
# The spear thrown overarm off the right hand (it leaves the hand at frame 5 of 16, the game's
# WindupSeconds share of the throw); both hands yanking a stuck spear out of someone; and the
# finisher, one blow driven down into someone on the floor, landing at frame 18 of 33 (the
# game's FinishLandsAt share of FinishSeconds). The throw's grip angles were found by searching
# on the rig for the spear pointing forward and a little up (cocked) and level (release). The finisher names no grip of its own beyond
# pointing it down, so it reads with any weapon or a bare fist.


def specials():
    aim_arm = {"LS": (70, 0, -6), "LE": (14, 0, 0), "LW": (0, 0, 0)}
    cocked = merge(coil(0.3), aim_arm, {"Grip": (105, 0, 60), "RS": (156, 0, 34), "RE": (54, 0, 0), "RW": (0, 0, 0), "Waist": (6, -42, 0), "Neck": (0, 32, 0), "Root": (2, -14, 0)})
    release = merge(lean(0.5), {"Grip": (-30, 30, -60), "RS": (104, 0, 4), "RE": (8, 0, 0), "LS": (-12, 0, -30), "LE": (30, 0, 0), "Waist": (-12, 40, 0), "Neck": (0, -28, 0), "Root": (-8, 16, 0)})
    through = merge(lean(0.45), {"Grip": (-90, 0, 0), "RS": (58, 0, -30), "RE": (24, 0, 0), "LS": (-18, 0, -34), "LE": (34, 0, 0), "Waist": (-10, 48, 0), "Neck": (0, -32, 0), "Root": (-6, 18, 0)})
    throw = Clip("SpearThrow", [
        (0, READY),
        (3, cocked),
        (5, release),
        (8, through),
        (16, lerp(through, READY, 0.6)),
    ], {"Wind": 3, "Strike": 5, "End": 16})

    reach = merge(lean(0.45), {"RS": (88, 0, -12), "RE": (12, 0, 0), "LS": (88, 0, 12), "LE": (12, 0, 0), "RW": (0, 0, 0), "LW": (0, 0, 0), "Waist": (-14, 0, 0), "Neck": (6, 0, 0)})
    yank = merge(coil(0.45), {"RS": (34, 0, 14), "RE": (104, 0, 0), "LS": (34, 0, -14), "LE": (104, 0, 0), "Waist": (14, 0, 0), "Neck": (8, 0, 0), "Root": (8, 0, 0), "Move": (0, -0.45, 0.45)})
    pull = Clip("SpearPull", [
        (0, READY),
        (4, reach),
        (7, lerp(reach, yank, 1.1)),
        (9, yank),
        (14, lerp(yank, READY, 0.7)),
    ], {"Wind": 4, "Strike": 8, "End": 14})

    raised = merge(coil(0.1), {"Grip": (-40, 0, 0), "RS": (172, 0, 12), "RE": (50, 0, 0), "LS": (60, 0, -24), "LE": (40, 0, 0), "Waist": (14, -10, 0), "Neck": (10, 6, 0), "Root": (4, 0, 0)})
    driven = merge(lean(1.3), {"Grip": (-96, 0, 0), "RS": (42, 0, 4), "RE": (4, 0, 0), "LS": (20, 0, -30), "LE": (30, 0, 0), "Waist": (-42, 4, 0), "Neck": (-10, 0, 0), "Root": (-14, 0, 0)})
    finisher = Clip("Finisher", [
        (0, READY),
        (11, raised),
        (14, lerp(raised, driven, -0.06)),
        (18, driven),
        (26, lerp(driven, raised, 0.12)),
        (33, READY),
    ], {"Wind": 14, "Strike": 18, "End": 33})
    return [throw, pull, finisher]


def all_clips():
    return sword() + knife() + axe() + spear() + fists() + specials()


_ = (READY, lerp)
