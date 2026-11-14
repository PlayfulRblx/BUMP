"""Keying poses into Blender actions.

A pose is a dict of joint -> (pitch, yaw, roll) in degrees, the game's conventions, plus an
optional "Move" of (x, y, z) studs for the hips. `merge` layers poses, so a clip reads as a list
of beats built from a few named shapes.

Clips are authored at 30 fps. A clip is:

    Clip("Name", keys=[(frame, pose), ...], markers={"Strike": 8}, loop=False)

Joints a clip never names are left alone by the game, which is how the upper body can swing while
the legs run. Markers carry timing the game needs, like where a swing connects.
"""

import bpy
from bpy_extras import anim_utils
from mathutils import Matrix, Quaternion

from fias_rig import delta_to_basis, euler_r, root_translation_to_location

FPS = 30
ALL_JOINTS = ("Root", "Waist", "Neck", "RS", "RE", "RW", "LS", "LE", "LW", "RH", "RK", "RA", "LH", "LK", "LA", "Grip")
HOT_INTERPOLATION = "BEZIER"


def merge(*poses):
    out = {}
    for pose in poses:
        out.update(pose)
    return out


def mirror(pose):
    """The same shape on the other side of the body: right joints swap with left."""
    swap = {"RS": "LS", "RE": "LE", "RW": "LW", "RH": "LH", "RK": "LK", "RA": "LA"}
    swap.update({v: k for k, v in swap.items()})
    out = {}
    for joint, value in pose.items():
        if joint in ("Grip",):
            out[joint] = value
        elif joint == "Move":
            out[joint] = (-value[0], value[1], value[2])
        else:
            pitch, yaw, roll = value
            out[swap.get(joint, joint)] = (pitch, -yaw, -roll)
    return out


class Clip:
    def __init__(self, name, keys, markers=None, loop=False, weapon=None, two_hand=False):
        self.name = name
        self.keys = keys
        self.markers = markers or {}
        self.loop = loop
        self.weapon = weapon
        self.two_hand = two_hand


def channelbag(action, armature):
    slot = armature.animation_data.action_slot
    return anim_utils.action_get_channelbag_for_slot(action, slot)


def author(armature, clip, action_name=None):
    """Writes a clip into an action on this armature, replacing any action of that name."""
    name = action_name or clip.name
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = action

    for pose_bone in armature.pose.bones:
        pose_bone.rotation_quaternion = Quaternion()
        pose_bone.location = (0, 0, 0)

    named = set()
    for _, pose in clip.keys:
        named.update(pose.keys())
    named.discard("TwoHand")
    joints = [joint for joint in ALL_JOINTS if joint in named]
    uses_move = "Move" in named

    previous = {}
    for frame, pose in clip.keys:
        for joint in joints:
            bone = armature.pose.bones[joint]
            # A joint a beat doesn't name holds its last value.
            angles = pose.get(joint, previous.get(joint, (0, 0, 0)))
            previous[joint] = angles
            q = delta_to_basis(bone.bone, euler_r(*angles))
            last = previous.get(joint + "_q")
            if last is not None and last.dot(q) < 0:
                q = Quaternion((-q.w, -q.x, -q.y, -q.z))
            previous[joint + "_q"] = q
            bone.rotation_quaternion = q
            bone.keyframe_insert("rotation_quaternion", frame=frame)
        if uses_move:
            bone = armature.pose.bones["Root"]
            move = pose.get("Move", previous.get("Move", (0, 0, 0)))
            previous["Move"] = move
            bone.location = root_translation_to_location(bone.bone, move)
            bone.keyframe_insert("location", frame=frame)

    # The left hand's IK. A clip can animate it with a "TwoHand" key of 0 to 1 on any beat.
    # two_hand="far" holds further up the weapon (a spear, an axe) through its own constraint.
    near = armature.pose.bones["LE"].constraints["LeftHand"]
    far = armature.pose.bones["LE"].constraints.get("LeftHandFar")
    use_far = clip.two_hand == "far" and far is not None
    held = 1.0 if clip.two_hand else 0.0
    for frame, pose in clip.keys:
        held = pose.get("TwoHand", held)
        near.influence = 0.0 if use_far else held
        near.keyframe_insert("influence", frame=frame)
        if far is not None:
            far.influence = held if use_far else 0.0
            far.keyframe_insert("influence", frame=frame)
    if far is not None:
        far.influence = 0.0

    bag = channelbag(action, armature)
    for curve in bag.fcurves:
        for point in curve.keyframe_points:
            point.interpolation = HOT_INTERPOLATION
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
        curve.update()

    for marker_name, frame in clip.markers.items():
        action.pose_markers.new(marker_name).frame = frame
    action["loop"] = bool(clip.loop)
    action["two_hand"] = bool(clip.two_hand)
    action["weapon"] = clip.weapon or ("BaseballBat" if clip.two_hand else "FryingPan")
    return action


_ = Matrix
