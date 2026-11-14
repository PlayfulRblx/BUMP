"""The R15 fighter rig, and the maths that keeps Blender and Roblox agreeing.

Roblox: X right, Y up, Z back; a character faces -Z.
Blender: Z up; the rig faces -Y, the way Blender's Front view looks at it.

A joint's Roblox `Motor6D.Transform` is a rotation in axes aligned with the character at rest,
applied at the joint. Blender stores pose bones in the bone's own axes, and bones point down
their limbs, so `delta_to_basis` and `basis_to_delta` convert between the two. Everything else
in the pipeline talks in Roblox terms, which is why clips read like the game's old pose tables:
shoulders and hips +pitch swing forward, elbows bend with +pitch, knees with -pitch, Root and
Waist -pitch lean forward and +yaw turn left.

Grip is different: `WeaponGrip.C0` turns it -90 degrees about X, so its Transform is in that
turned frame. JOINT_FRAME carries that, and it is why a weapon's +Y points forward at rest.
"""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector

# Roblox vector -> Blender vector.
C = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
C_INV = C.inverted()

HRP_HEIGHT = 3.0


def r2b(v):
    return C @ Vector(v)


def b2r(v):
    return C_INV @ Vector(v)


def euler_r(pitch, yaw, roll):
    """Roblox CFrame.Angles(pitch, yaw, roll), in degrees, as a 3x3 in Roblox axes."""
    return (
        Matrix.Rotation(math.radians(pitch), 3, "X")
        @ Matrix.Rotation(math.radians(yaw), 3, "Y")
        @ Matrix.Rotation(math.radians(roll), 3, "Z")
    )


GRIP_FRAME = Matrix.Rotation(math.radians(-90), 3, "X")
JOINT_FRAME = {"Grip": GRIP_FRAME}

# name: (parent, joint position, end position), both in Roblox studs with the feet at y=0.
BONES = {
    "HRP": (None, (0, 3, 0), (0, 3.6, 0)),
    "Root": ("HRP", (0, 2.2, 0), (0, 2.45, 0)),
    "Waist": ("Root", (0, 2.45, 0), (0, 4.0, 0)),
    "Neck": ("Waist", (0, 4.0, 0), (0, 5.15, 0)),
    "RS": ("Waist", (1.0, 3.75, 0), (1.5, 2.85, 0)),
    "RE": ("RS", (1.5, 2.85, 0), (1.5, 1.95, 0)),
    "RW": ("RE", (1.5, 1.95, 0), (1.5, 1.6, 0)),
    "LS": ("Waist", (-1.0, 3.75, 0), (-1.5, 2.85, 0)),
    "LE": ("LS", (-1.5, 2.85, 0), (-1.5, 1.95, 0)),
    "LW": ("LE", (-1.5, 1.95, 0), (-1.5, 1.6, 0)),
    "RH": ("Root", (0.5, 2.05, 0), (0.5, 1.2, 0)),
    "RK": ("RH", (0.5, 1.2, 0), (0.5, 0.35, 0)),
    "RA": ("RK", (0.5, 0.35, 0), (0.5, 0.0, -0.5)),
    "LH": ("Root", (-0.5, 2.05, 0), (-0.5, 1.2, 0)),
    "LK": ("LH", (-0.5, 1.2, 0), (-0.5, 0.35, 0)),
    "LA": ("LK", (-0.5, 0.35, 0), (-0.5, 0.0, -0.5)),
    "Grip": ("RW", (1.5, 1.65, 0), (1.5, 1.65, -0.6)),
    # Not joints: where the left hand reaches on a two-handed hold, and which way its elbow points.
    "GripL": ("Grip", (1.5, 1.65, -1.0), (1.5, 1.65, -1.3)),
    "LPole": ("Waist", (-3.0, 2.2, 2.5), (-3.0, 2.2, 2.9)),
}
HELPER_BONES = ("GripL", "GripFar", "LPole")

# bone: (centre, size), in Roblox studs at rest. Corners stay square so poses read in silhouette.
BLOCKS = {
    "Root": ((0, 2.3, 0), (2, 0.4, 1)),
    "Waist": ((0, 3.3, 0), (2, 1.6, 1)),
    "Neck": ((0, 4.6, 0), (1.25, 1.2, 1.25)),
    "RS": ((1.5, 3.3, 0), (1, 1.1, 1)),
    "RE": ((1.5, 2.3, 0), (0.95, 1.1, 0.95)),
    "RW": ((1.5, 1.65, 0), (0.9, 0.55, 0.9)),
    "LS": ((-1.5, 3.3, 0), (1, 1.1, 1)),
    "LE": ((-1.5, 2.3, 0), (0.95, 1.1, 0.95)),
    "LW": ((-1.5, 1.65, 0), (0.9, 0.55, 0.9)),
    "RH": ((0.5, 1.6, 0), (1, 1.0, 1)),
    "RK": ((0.5, 0.75, 0), (0.95, 1.0, 0.95)),
    "RA": ((0.5, 0.15, -0.2), (1, 0.3, 1.4)),
    "LH": ((-0.5, 1.6, 0), (1, 1.0, 1)),
    "LK": ((-0.5, 0.75, 0), (0.95, 1.0, 0.95)),
    "LA": ((-0.5, 0.15, -0.2), (1, 0.3, 1.4)),
}

SKIN = (0.96, 0.8, 0.67, 1)
PANTS = (0.17, 0.18, 0.28, 1)
SHOE = (0.1, 0.1, 0.13, 1)
BLOCK_COLOURS = {
    "Neck": "Skin",
    "RE": "Skin",
    "RW": "Skin",
    "LE": "Skin",
    "LW": "Skin",
    "RS": "Shirt",
    "LS": "Shirt",
    "Root": "Pants",
    "RH": "Pants",
    "LH": "Pants",
    "RK": "Pants",
    "LK": "Pants",
    "RA": "Shoe",
    "LA": "Shoe",
    "Waist": "Shirt",
}

# name: (length along the blade, list of (offset along +Y, size x, size y, size z, colour)).
WEAPONS = {
    "FryingPan": [(1.1, 0.3, 2.3, 0.3, (0.1, 0.1, 0.11, 1)), (2.9, 2.0, 1.6, 0.25, (0.14, 0.14, 0.16, 1))],
    "Tuna": [(3.0, 1.1, 6.2, 1.5, (0.2, 0.32, 0.5, 1)), (6.1, 1.5, 0.7, 0.25, (0.85, 0.75, 0.2, 1))],
    "Watermelon": [(1.3, 2.4, 3.6, 2.4, (0.2, 0.55, 0.2, 1))],
    "Broom": [(3.2, 0.26, 6.4, 0.26, (0.65, 0.45, 0.25, 1)), (6.6, 1.5, 1.0, 0.45, (0.85, 0.72, 0.35, 1))],
    "GoldAxe": [(2.0, 0.3, 4.0, 0.3, (0.5, 0.3, 0.15, 1)), (3.8, 1.8, 1.2, 0.3, (0.95, 0.75, 0.2, 1))],
    "BaseballBat": [(2.2, 0.42, 4.4, 0.42, (0.8, 0.62, 0.38, 1))],
    # The Scramble's four, at the sizes the game builds them: the hand closes at offset 0.
    "Sword": [(0.0, 0.2, 0.9, 0.2, (0.25, 0.19, 0.16, 1)), (0.5, 1.1, 0.16, 0.26, (0.93, 0.72, 0.28, 1)), (2.2, 0.42, 3.3, 0.1, (0.8, 0.83, 0.86, 1))],
    "Knife": [(0.0, 0.2, 0.62, 0.2, (0.25, 0.19, 0.16, 1)), (0.36, 0.56, 0.1, 0.2, (0.36, 0.38, 0.42, 1)), (0.92, 0.3, 1.05, 0.08, (0.8, 0.83, 0.86, 1))],
    "Axe": [(1.8, 0.26, 5.0, 0.26, (0.48, 0.34, 0.23, 1)), (3.7, 1.5, 1.1, 0.26, (0.8, 0.83, 0.86, 1))],
    "Spear": [(2.55, 0.2, 7.0, 0.2, (0.48, 0.34, 0.23, 1)), (5.75, 0.6, 1.2, 0.12, (0.8, 0.83, 0.86, 1))],
}
# Where the front hand closes on a long weapon, studs up from the back hand.
FAR_GRIP = 2.1


def _material(name, colour):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = colour
    material.use_nodes = False
    return material


def _box(name, centre_b, size_b, material):
    half = [s / 2 for s in size_b]
    verts = [(sx * half[0], sy * half[1], sz * half[2]) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = centre_b
    return obj


def _attach(obj, armature, bone_name):
    world = obj.matrix_basis.copy()
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    bone = armature.data.bones[bone_name]
    bone_tail = armature.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    obj.matrix_parent_inverse = bone_tail.inverted()
    obj.matrix_basis = world


def _ensure_collection(name):
    collection = bpy.data.collections.get(name)
    if not collection:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def build_fighter(name, shirt, location=(0, 0, 0)):
    """An armature named `name` with blocks for a body, standing on the ground at `location`."""
    collection = _ensure_collection(name)
    data = bpy.data.armatures.new(name)
    armature = bpy.data.objects.new(name, data)
    collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, (parent, head, tail) in BONES.items():
        bone = data.edit_bones.new(bone_name)
        bone.head = r2b(head)
        bone.tail = r2b(tail)
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
    # Two-handed holds: the left arm follows the weapon, keyed on and off per clip.
    elbow = armature.pose.bones["LE"]
    reach = elbow.constraints.new("IK")
    reach.name = "LeftHand"
    reach.target = armature
    reach.subtarget = "GripL"
    reach.pole_target = armature
    reach.pole_subtarget = "LPole"
    reach.pole_angle = math.radians(0)
    reach.chain_count = 2
    reach.influence = 0

    colours = {
        "Skin": _material("Skin", SKIN),
        "Pants": _material("Pants", PANTS),
        "Shoe": _material("Shoe", SHOE),
        "Shirt": _material(name + "_Shirt", shirt),
    }
    for bone_name, (centre, size) in BLOCKS.items():
        size_b = (size[0], size[2], size[1])
        block = _box(f"{name}_{bone_name}", r2b(centre), size_b, colours[BLOCK_COLOURS[bone_name]])
        collection.objects.link(block)
        _attach(block, armature, bone_name)
    # A nose, so which way the head is facing can be read in a render.
    nose = _box(f"{name}_Nose", r2b((0, 4.65, -0.72)), (0.3, 0.3, 0.3), colours["Skin"])
    collection.objects.link(nose)
    _attach(nose, armature, "Neck")
    armature.location = location
    return armature


def build_weapons(armature):
    """One hidden prop per weapon on the grip. Set `show_weapon` to choose which is out."""
    collection = _ensure_collection(armature.name)
    grip = armature.data.bones["Grip"]
    pivot = armature.matrix_world.inverted() @ armature.matrix_world @ grip.head_local
    for weapon, pieces in WEAPONS.items():
        for index, (offset, sx, sy, sz, colour) in enumerate(pieces):
            material = _material(f"Weapon_{weapon}_{index}", colour)
            # Handle +Y lies along Roblox forward at rest, which is Blender -Y.
            centre = pivot + Vector((0, -offset, 0))
            part = _box(f"{armature.name}_{weapon}_{index}", centre, (sx, sy, sz), material)
            collection.objects.link(part)
            _attach(part, armature, "Grip")
            part["weapon"] = weapon
            part.hide_render = True
            part.hide_viewport = True


def ensure_scramble(armature):
    """Brings a rig built before The Scramble up to date: its four weapons as props, and a second
    left-hand reach further up the weapon (GripFar) for a spear or an axe."""
    have = {child["weapon"] for child in armature.children if "weapon" in child}
    collection = _ensure_collection(armature.name)
    grip = armature.data.bones["Grip"]
    for weapon, pieces in WEAPONS.items():
        if weapon in have:
            continue
        for index, (offset, sx, sy, sz, colour) in enumerate(pieces):
            material = _material(f"Weapon_{weapon}_{index}", colour)
            centre = Vector(grip.head_local) + Vector((0, -offset, 0))
            part = _box(f"{armature.name}_{weapon}_{index}", centre, (sx, sy, sz), material)
            collection.objects.link(part)
            _attach(part, armature, "Grip")
            part["weapon"] = weapon
            part.hide_render = True
            part.hide_viewport = True
    if "GripFar" not in armature.data.bones:
        bpy.context.view_layer.objects.active = armature
        armature.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bone = armature.data.edit_bones.new("GripFar")
        bone.head = r2b((1.5, 1.65, -FAR_GRIP))
        bone.tail = r2b((1.5, 1.65, -FAR_GRIP - 0.3))
        bone.parent = armature.data.edit_bones["Grip"]
        bpy.ops.object.mode_set(mode="OBJECT")
        armature.pose.bones["GripFar"].rotation_mode = "QUATERNION"
    elbow = armature.pose.bones["LE"]
    if "LeftHandFar" not in elbow.constraints:
        reach = elbow.constraints.new("IK")
        reach.name = "LeftHandFar"
        reach.target = armature
        reach.subtarget = "GripFar"
        reach.pole_target = armature
        reach.pole_subtarget = "LPole"
        reach.pole_angle = math.radians(0)
        reach.chain_count = 2
        reach.influence = 0


def show_weapon(armature, weapon):
    for child in armature.children:
        if "weapon" in child:
            hidden = child["weapon"] != weapon
            child.hide_render = hidden
            child.hide_viewport = hidden


def delta_to_basis(bone, delta_r):
    """A Roblox joint rotation (3x3, in Roblox axes) as this bone's pose quaternion."""
    frame = JOINT_FRAME.get(bone.name)
    if frame is not None:
        delta_r = frame @ delta_r @ frame.inverted()
    delta_b = C @ delta_r @ C_INV
    rest = bone.matrix_local.to_3x3()
    return (rest.inverted() @ delta_b @ rest).to_quaternion()


def pose_to_delta(armature, pose_bone):
    """The bone's current pose as (rotation 3x3 in Roblox axes, translation in Roblox studs)."""
    rest = pose_bone.bone.matrix_local
    parent = pose_bone.parent
    if parent:
        frame = parent.matrix @ parent.bone.matrix_local.inverted()
    else:
        frame = Matrix.Identity(4)
    delta_b = frame.inverted() @ pose_bone.matrix @ rest.inverted()
    rotation = C_INV @ delta_b.to_3x3() @ C
    joint_frame = JOINT_FRAME.get(pose_bone.name)
    if joint_frame is not None:
        rotation = joint_frame.inverted() @ rotation @ joint_frame
    moved = (frame.inverted() @ pose_bone.head) - rest.to_translation()
    return rotation, b2r(moved)


def quaternion_r(rotation):
    """(x, y, z, w), ready for Roblox's CFrame.new(px, py, pz, qx, qy, qz, qw)."""
    q = rotation.to_quaternion()
    return (q.x, q.y, q.z, q.w)


def root_translation_to_location(bone, translation_r):
    rest = bone.matrix_local.to_3x3()
    return rest.inverted() @ r2b(translation_r)


__all__ = ["build_fighter", "build_weapons", "show_weapon", "delta_to_basis", "pose_to_delta", "quaternion_r"]
_ = Quaternion
