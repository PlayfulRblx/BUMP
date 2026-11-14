"""Measures every finisher beat: how far the weapon's business end is from the victim's body.

    Blender -b animation/BUMP_Animations.blend -P animation/scripts/contact.py

A blow that lands should read under about 1.2 studs from what it is aimed at. Also reports how
close the two fighters' hips get, because bodies walking through each other reads worst of all.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fias_rig  # noqa: E402

HEAD_ALONG = {"FryingPan": 2.9, "Tuna": 5.0, "Watermelon": 1.3, "Broom": 6.4, "GoldAxe": 3.8, "BaseballBat": 3.6}


def use(obj, action):
    obj.animation_data_create()
    obj.animation_data.action = action
    if obj.animation_data.action_suitable_slots:
        obj.animation_data.action_slot = obj.animation_data.action_suitable_slots[0]


def main():
    scene = bpy.context.scene
    fighter, victim = bpy.data.objects["Fighter"], bpy.data.objects["Victim"]
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        if not (action.name.startswith("FIN_") and action.name.endswith("_A")):
            continue
        base = action.name[:-2]
        use(fighter, action)
        use(victim, bpy.data.actions[base + "_V"])
        victim.location = fias_rig.r2b(action.get("victim_offset"))
        victim.rotation_mode = "XYZ"
        victim.rotation_euler = (0, 0, math.radians(action.get("victim_yaw")))
        along = HEAD_ALONG[action["weapon"]]
        print(f"[Contact] {base} {action['weapon']} seconds={action.frame_range[1] / 30:.2f}")
        closest = (99, 0)
        first, last = (int(v) for v in action.frame_range)
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            a = (fighter.matrix_world @ fighter.pose.bones["Root"].head)
            b = (victim.matrix_world @ victim.pose.bones["Root"].head)
            flat = math.hypot(a.x - b.x, a.y - b.y)
            if flat < closest[0]:
                closest = (flat, frame)
        for marker in sorted(action.pose_markers, key=lambda m: m.frame):
            if not marker.name.startswith("Beat"):
                continue
            scene.frame_set(marker.frame)
            bpy.context.view_layer.update()
            grip = fighter.pose.bones["Grip"]
            direction = (grip.tail - grip.head).normalized()
            tip = fighter.matrix_world @ (grip.head + direction * along)
            head = victim.matrix_world @ victim.pose.bones["Neck"].tail.lerp(victim.pose.bones["Neck"].head, 0.5)
            chest = victim.matrix_world @ victim.pose.bones["Waist"].head.lerp(victim.pose.bones["Waist"].tail, 0.5)
            legs = victim.matrix_world @ victim.pose.bones["RK"].head
            t = fias_rig.b2r(tip)
            print(
                f"  {marker.name} f{marker.frame}: head {(tip - head).length:.2f}  chest {(tip - chest).length:.2f}  knee {(tip - legs).length:.2f}"
                f"   tip=({t.x:.1f},{t.y:.1f},{t.z:.1f}) victimHead=({fias_rig.b2r(head).x:.1f},{fias_rig.b2r(head).y:.1f},{fias_rig.b2r(head).z:.1f})"
            )
        print(f"  closest hips {closest[0]:.2f} at f{closest[1]}")
        camera = bpy.data.objects.get("FinishCamera")
        shot = bpy.data.actions.get(base + "_C")
        if camera and shot:
            use(camera, shot)
            nearest = (99, 0)
            for frame in range(first, last + 1):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                eye = camera.matrix_world.to_translation()
                for rig in (fighter, victim):
                    for bone in ("Waist", "Neck", "RK", "LK", "RE", "LE"):
                        distance = (eye - rig.matrix_world @ rig.pose.bones[bone].head).length
                        if distance < nearest[0]:
                            nearest = (distance, frame)
            print(f"  camera nearest body {nearest[0]:.2f} at f{nearest[1]}")


main()
_ = Vector
