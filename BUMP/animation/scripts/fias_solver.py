"""Makes blows land. A pose is only ever a guess at where a weapon ends up, so each finisher beat
is solved: forward kinematics in Roblox space finds the weapon's business end and the victim's
body at that frame, then coordinate descent nudges the pose until they meet, staying as close to
the authored shape as it can."""

import math

from mathutils import Matrix, Vector

from fias_rig import BONES, GRIP_FRAME, euler_r

CHAIN = {"RS": "Waist", "RE": "RS", "RW": "RE", "Grip": "RW", "Waist": "Root", "Neck": "Waist", "RH": "Root", "RK": "RH", "Root": None}
# Where a target sits, as (bone it moves with, point on that bone at rest in Roblox studs).
POINTS = {
    "head": ("Neck", (0, 4.7, 0)),
    "crown": ("Neck", (0, 5.3, 0)),
    "chest": ("Waist", (0, 3.3, -0.4)),
    "knee": ("RK", (0.5, 1.0, -0.5)),
}
HEAD_ALONG = {"Hand": 0.4, "FryingPan": 2.9, "Tuna": 5.0, "Watermelon": 1.3, "Broom": 6.4, "GoldAxe": 3.8, "BaseballBat": 3.6}
# (joint, axis index, how far it may stray from the authored angle, in degrees, and how much that costs).
FREEDOMS = (
    ("RS", 0, 70, 1.0),
    ("RS", 2, 80, 1.0),
    ("RE", 0, 60, 0.6),
    ("Grip", 0, 50, 0.4),
    ("Waist", 1, 40, 1.4),
    ("Waist", 0, 25, 1.6),
)
HOLD_SHAPE = 0.00012
MOVE_RANGE = (-3.0, 0.6)


def joint_matrix(pose, name):
    pivot = Vector(BONES[name][1])
    angles = pose.get(name, (0, 0, 0))
    turn = euler_r(*angles)
    if name == "Grip":
        turn = GRIP_FRAME @ turn @ GRIP_FRAME.inverted()
    local = Matrix.Translation(pivot) @ turn.to_4x4() @ Matrix.Translation(-pivot)
    if name == "Root":
        local = Matrix.Translation(Vector(pose.get("Move", (0, 0, 0)))) @ local
    return local


def world(pose, name):
    chain = []
    while name:
        chain.append(name)
        name = CHAIN[name]
    out = Matrix.Identity(4)
    for joint in reversed(chain):
        out = out @ joint_matrix(pose, joint)
    return out


def weapon_tip(pose, along):
    grip = Vector(BONES["Grip"][1])
    return world(pose, "Grip") @ (grip + GRIP_FRAME @ Vector((0, along, 0)))


def victim_point(pose, name, offset, yaw):
    bone, point = POINTS[name]
    local = world(pose, bone) @ Vector(point)
    return Vector(offset) + Matrix.Rotation(math.radians(yaw), 3, "Y") @ local


def pose_at(keys, frame):
    """A track's pose at any frame, blending between the keys either side."""
    from clips_core import lerp

    before, after = keys[0], keys[-1]
    for key in keys:
        if key[0] <= frame:
            before = key
        if key[0] >= frame:
            after = key
            break
    if after[0] == before[0]:
        return before[1]
    return lerp(before[1], after[1], (frame - before[0]) / (after[0] - before[0]))


def cost(pose, authored, along, target):
    miss = (weapon_tip(pose, along) - target).length_squared
    drift = 0
    for joint, axis, _, weight in FREEDOMS:
        drift += weight * (pose.get(joint, (0, 0, 0))[axis] - authored.get(joint, (0, 0, 0))[axis]) ** 2
    return miss + HOLD_SHAPE * drift


def land(authored, along, target):
    """A copy of `authored` with the weapon's end on `target`, and how far off it finished."""
    pose = dict(authored)
    pose.setdefault("Move", (0, 0, 0))
    for joint, _, _, _ in FREEDOMS:
        pose.setdefault(joint, authored.get(joint, (0, 0, 0)))
    step = 16.0
    best = cost(pose, authored, along, target)
    while step > 0.1:
        improved = False
        for joint, axis, reach, _ in FREEDOMS:
            base = authored.get(joint, (0, 0, 0))[axis]
            for direction in (step, -step):
                angles = list(pose[joint])
                angles[axis] = max(base - reach, min(base + reach, angles[axis] + direction))
                trial = dict(pose)
                trial[joint] = tuple(angles)
                score = cost(trial, authored, along, target)
                if score < best - 1e-6:
                    pose, best, improved = trial, score, True
        for direction in (step * 0.03, -step * 0.03):
            x, y, z = pose["Move"]
            trial = dict(pose)
            trial["Move"] = (x, y, max(MOVE_RANGE[0], min(MOVE_RANGE[1], z + direction)))
            score = cost(trial, authored, along, target)
            if score < best - 1e-6:
                pose, best, improved = trial, score, True
        if not improved:
            step *= 0.5
    return pose, (weapon_tip(pose, along) - target).length
