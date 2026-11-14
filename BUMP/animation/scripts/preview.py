"""Renders contact sheets of clips, one frame strip per clip, for checking animation by eye.

    Blender -b animation/BUMP_Animations.blend -P animation/scripts/preview.py -- OUT_DIR Clip Clip...

--back shows it from behind, which is the view for anything that rolls sideways.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import fias_rig  # noqa: E402

SIZE = 240
COUNT = 14


def aim(camera, eye, target):
    camera.location = eye
    camera.rotation_mode = "QUATERNION"
    camera.rotation_quaternion = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y")


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir, names = args[0], args[1:]
    view = "side"
    if names and names[0] in ("--camera", "--back"):
        view, names = names[0][2:], names[1:]
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.image_settings.file_format = "PNG"
    fighter = bpy.data.objects["Fighter"]
    victim = bpy.data.objects["Victim"]
    camera = bpy.data.objects.new("Preview", bpy.data.cameras.new("Preview"))
    camera.data.lens = 50
    scene.collection.objects.link(camera)
    scene.camera = camera
    for name in names:
        paired = name.startswith("FIN_")
        action = bpy.data.actions[name + "_A" if paired else name]
        fighter.animation_data_create()
        fighter.animation_data.action = action
        if fighter.animation_data.action_suitable_slots:
            fighter.animation_data.action_slot = fighter.animation_data.action_suitable_slots[0]
        fias_rig.show_weapon(fighter, action.get("weapon", "FryingPan"))
        far = fighter.pose.bones["LE"].constraints.get("LeftHandFar")
        if far is not None and not action.get("two_hand"):
            far.influence = 0.0
        for child in victim.children_recursive:
            child.hide_render = not paired
        if paired:
            other = bpy.data.actions[name + "_V"]
            victim.animation_data_create()
            victim.animation_data.action = other
            if victim.animation_data.action_suitable_slots:
                victim.animation_data.action_slot = victim.animation_data.action_suitable_slots[0]
            offset = action.get("victim_offset", (0, 0, -5))
            victim.location = fias_rig.r2b(offset)
            victim.rotation_mode = "XYZ"
            victim.rotation_euler = (0, 0, math.radians(action.get("victim_yaw", 180)))
        first, last = (int(round(v)) for v in action.frame_range)
        frames = sorted({first + round((last - first) * i / (COUNT - 1)) for i in range(COUNT)})
        for marker in action.pose_markers:
            frames.append(int(marker.frame))
        frames = sorted(set(frames))
        centre = (0, -2.5, 2.4) if paired else (0, 0, 2.6)
        eye = (-11, -13, 5.5) if not paired else (-17, -9, 6)
        if view == "back":
            eye = (0, 15, 4)
        aim(camera, eye, centre)
        shot = bpy.data.objects.get("FinishCamera") if paired and view == "camera" else None
        if shot:
            shot.animation_data.action = bpy.data.actions[name + "_C"]
            if shot.animation_data.action_suitable_slots:
                shot.animation_data.action_slot = shot.animation_data.action_suitable_slots[0]
            scene.camera = shot
        for frame in frames:
            scene.frame_set(frame)
            if shot:
                shot.data.sensor_fit = "VERTICAL"
                shot.data.lens = shot.data.sensor_height / (2 * math.tan(math.radians(shot["fov"]) / 2))
            scene.render.filepath = os.path.join(out_dir, f"{name}__{frame:03d}.png")
            bpy.ops.render.render(write_still=True)
    print("[Preview] done")


main()
