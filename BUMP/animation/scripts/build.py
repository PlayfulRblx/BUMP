"""Authors BUMP's own clips (clips_bump.py) into animation/BUMP_Animations.blend.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P animation/scripts/build.py [-- ClipName ...]

The file came from The Scramble with its whole library already authored; BUMP reuses some of
those clips as they are (clips_bump.REUSED), and this only rewrites BUMP's own.

The .blend is the source of truth once it exists. Any action with a custom property `locked` set
to true has been hand-edited in Blender, and this leaves it alone.
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clips_bump  # noqa: E402
import fias_pose  # noqa: E402
import fias_rig  # noqa: E402

BLEND = os.path.join(HERE, "..", "BUMP_Animations.blend")
SHIRT_A = (0.92, 0.3, 0.27, 1)
SHIRT_B = (0.27, 0.58, 0.92, 1)


def scene_setup():
    scene = bpy.context.scene
    scene.render.fps = fias_pose.FPS
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    world = bpy.data.worlds.new("Store")
    world.color = (0.8, 0.82, 0.85)
    scene.world = world
    floor = bpy.data.meshes.new("Floor")
    floor.from_pydata([(-40, -40, 0), (40, -40, 0), (40, 40, 0), (-40, 40, 0)], [], [(0, 1, 2, 3)])
    floor.update()
    material = bpy.data.materials.new("Tiles")
    material.diffuse_color = (0.6, 0.78, 0.76, 1)
    floor.materials.append(material)
    scene.collection.objects.link(bpy.data.objects.new("Floor", floor))


def locked(name):
    action = bpy.data.actions.get(name)
    return action is not None and action.get("locked")


def main():
    only = [arg for arg in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else []
    if os.path.exists(BLEND):
        bpy.ops.wm.open_mainfile(filepath=BLEND)
        attacker, victim = bpy.data.objects["Fighter"], bpy.data.objects["Victim"]
        fias_rig.ensure_scramble(attacker)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene_setup()
        attacker = fias_rig.build_fighter("Fighter", SHIRT_A)
        fias_rig.build_weapons(attacker)
        victim = fias_rig.build_fighter("Victim", SHIRT_B, location=(0, -5, 0))
        fias_rig.ensure_scramble(attacker)
    authored = 0
    for clip in clips_bump.all_clips():
        if (not only or clip.name in only) and not locked(clip.name):
            fias_pose.author(attacker, clip)
            authored += 1
    attacker.animation_data.action = None
    if victim.animation_data:
        victim.animation_data.action = None
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(BLEND))
    print(f"[Build] authored {authored}, {len(bpy.data.actions)} actions in the blend")


main()
