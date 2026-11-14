# Animation

Clips are authored in Blender by script and played by the client joint by joint
(`src/Client/Systems/Animator.lua`), so nothing is uploaded to Roblox.

```
BUMP_Animations.blend  ->  scripts/export.py  ->  src/Shared/Movement/AnimationData/Core.lua
```

The .blend and the scripts came from The Scramble (and Smash Arena and Fight in a Supermarket
before it), with that whole library still inside. BUMP authors its own platformer clips in
`scripts/clips_bump.py` and reuses a few of the library's as they are (`clips_bump.REUSED`: Idle,
Jump, Fall, Roll, Flip, Land, LandSoft, WallStick). Only those clips are exported.
`AnimationData/Imported.lua` is Playful's Run (with Dash and the dodges), copied from The Scramble
and not regenerated here; an imported clip wins over a Blender one of the same name.

## Adding or changing a clip

Write it in `scripts/clips_bump.py` (a clip is a list of poses on frames at 30 fps, each pose a
table of joint to pitch, yaw, roll in degrees; the conventions are at the top of that file), add it
to `all_clips()`, then from `BUMP/`:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P animation/scripts/build.py -- Backflip
```

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b animation/BUMP_Animations.blend -P animation/scripts/export.py
```

`build.py` with no names after `--` rewrites every BUMP clip. An action with a custom property
`locked` set to true has been edited by hand in Blender and is left alone.

To look at clips without opening Blender (the frying pan in the renders is a leftover prop from
The Scramble's file; it isn't exported):

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b animation/BUMP_Animations.blend -P animation/scripts/preview.py -- OUT_DIR Backflip TripleFlip
```

```bash
python3 animation/scripts/sheet.py OUT_DIR
```
