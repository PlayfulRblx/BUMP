#!/usr/bin/env python3
"""
Builds BUMP's five-minute video for the Cinnamon Software brief as a Final Cut Pro project
(FCPXML 1.11), and the narration script timed to it.

    python3 devlog/make_video.py

Writes, next to this file:
    BUMP_video.fcpxml        File > Import > XML in Final Cut Pro: one project, three long
                             stretches of the gameplay recording with hard cuts, no titles; the
                             game's own sound turned down under your voice; a marker at each beat
                             of the script carrying its lines (markers don't show in the export)
    BUMP_video_script.md     the narration, beat by beat, with the timecode each one starts at

Change the stretches or the lines below and run it again.
"""

import html
import os
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
RECORDING = "/Users/jjackson/Desktop/2026-11-14 10-57-34.mp4"
RECORDING_SECONDS = 563.766
FPS = 60
GAME_VOLUME = "-16dB"  # the game's own sound, under your voice

# The footage: (from, to) in the recording, in seconds, played in order.
STRETCHES = [
    (10.0, 227.0),  # lobby, BUMP, knocked out, the rim, Bomber, the shop, MELTDOWN, the lava from above
    (458.0, 526.0),  # final standings, the next lobby, the hero intro, BUMP, the knockout camera, results
    (552.0, 563.75),  # Bomber: Turbo, the bomb pops
]

# The narration: (timeline second it starts at, what's on screen, the lines). About 140 words a
# minute leaves room to breathe; each beat's words fit before the next one starts.
BEATS = [
    (0.0, "The lobby counts down; the BUMP card",
     "Hi, I'm [your name], and this is BUMP, a party game I built for the Cinnamon trial. You arrive "
     "in a neon city hub with the arena sunk into the middle, and a session is six quick minigames "
     "back to back. Any empty seats are filled by bots."),
    (20.0, "BUMP: riding, the dash, the hit, knocked off",
     "The first game is BUMP. There's one ball fewer than players: you ride a ball, charge a dash "
     "and roll everyone else off while the floor crumbles away. And... I'm out."),
    (36.0, "Back on the plaza, walking the rim",
     "Being knocked out isn't dead time. You're back on the rim, and the jumbotron keeps up with the "
     "round. I wanted a cartoony, Nintendo-ish feel with a minimal UI "
     "that stays out of the way. The bots wear your friends' avatars and names, so even a half-empty "
     "server feels like your mates are there."),
    (59.0, "Bomber's intro: the flyover, the hero pose, 3-2-1",
     "Every game opens with a camera flight past the whole line-up that lands on you for a hero "
     "pose, then a three, two, one."),
    (70.0, "Bomber Bloxians",
     "Bomber Bloxians: pass an enormous ticking bomb by touching someone. The fuse is hidden, so the "
     "ticking speeds up instead, and every blast bites a crater out of the arena."),
    (84.0, "Bomber, running and dodging",
     "Movement is the part I cared about most. It's a custom controller, a state machine for every "
     "move, with Roblox's stock jump turned off. Jumps rise quickly and fall heavier than they rise, "
     "and you can steer in the air to get yourself out of trouble. I had a triple jump for a while, "
     "but it felt awful and didn't fit, so it went. The shove started as a big lunge and became a "
     "short, snappy burst. Every movement number is live-tunable in Studio while you play, so it was "
     "tuned by feel rather than by guesswork."),
    (128.0, "The last of Bomber; the shop opens",
     "Placing earns gold and XP. Gold buys and upgrades power-ups: Shield, Turbo, Shockwave and "
     "Second Chance. Your level from XP unlocks the higher upgrades. That's the reason to come back: "
     "a short competitive session that also moves your character forward."),
    (150.0, "MELTDOWN: the card, the climb, melted",
     "The third game is Meltdown. Lava rises up a tower of floating platforms: crumbling ledges, "
     "moving platforms, bounce pads and wall-jump chimneys, with fireballs, surges and falling "
     "debris on the way up. The tiers are spaced so you need your float jump, and a ground pound "
     "shakes everyone off your platform. And there I go."),
    (182.0, "The lava tower from above",
     "On the technical side, systems are plain modules registered in a load-order list, the same "
     "pattern as my own framework. Movement, effects and anything that needs instant feedback run "
     "on the client so it feels immediate, with checks on the server to keep the responses valid. "
     "The UI kit was built in UI Labs first, from modular components and design tokens, so every "
     "screen stays consistent. And problems were tracked down by measuring rather than guessing."),
    (217.0, "Final standings; the next lobby; the hero intro; BUMP",
     "After six games you get the final standings, and it's straight into the next session. On AI "
     "and assets: Claude Code wrote a lot of the Luau from my direction, one feature at a time. I set "
     "the structure and the programming style, then reviewed it, staged it and sent it back. I made "
     "the simple assets in Blender, and used Nano Banana image models to expand on inspirations. The "
     "lobby is reworked from an unfinished project of mine from a couple of years ago. Animation is "
     "my weak spot: I know the feeling I'm after, and that's where I'd lean on great animators."),
    (269.0, "Run over; the camera swings to who did it; results",
     "When you're knocked out, the camera follows you down, then swings round to whoever did it. "
     "Egzekiel, there, running me over."),
    (281.0, "Results; Bomber; the bomb pops",
     "I've got more ideas in the same spirit: Silly Billies, The Scramble, Steal The Sky and Build a "
     "Boss. But that's BUMP: quick to pick up, easy to come back to, and built to grow. Thanks for "
     "watching."),
]


def frames(seconds: float) -> int:
    return int(round(seconds * FPS))


def tf(count: int) -> str:
    """A time FCP accepts: whole frames at 60 fps, in 100/6000 s units."""
    return f"{count * 100}/6000s"


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def clock(seconds: float) -> str:
    return f"{int(seconds // 60)}:{int(seconds % 60):02d}"


def build():
    clips = []
    cursor = 0
    for start, end in STRETCHES:
        assert 0 <= start < end <= RECORDING_SECONDS
        clips.append({"src": frames(start), "dur": frames(end - start), "offset": cursor})
        cursor += frames(end - start)
    total = cursor

    def clip_at(frame: int) -> int:
        for i, clip in enumerate(clips):
            if clip["offset"] <= frame < clip["offset"] + clip["dur"]:
                return i
        return len(clips) - 1

    markers = {i: [] for i in range(len(clips))}
    for at, shown, lines in BEATS:
        i = clip_at(frames(at))
        local = clips[i]["src"] + frames(at) - clips[i]["offset"]
        markers[i].append((local, shown, lines))

    out = []
    w = out.append
    w('<?xml version="1.0" encoding="UTF-8"?>')
    w('<!DOCTYPE fcpxml>')
    w('<fcpxml version="1.11">')
    w('  <resources>')
    w('    <format id="r1" name="FFVideoFormat2160p60" frameDuration="100/6000s" width="3840" height="2160" colorSpace="1-1-1 (Rec. 709)"/>')
    w(f'    <asset id="r2" name="BUMP gameplay 2026-11-14" start="0s" duration="{tf(frames(RECORDING_SECONDS))}" hasVideo="1" format="r1" hasAudio="1" audioSources="1" audioChannels="2" audioRate="48000">')
    w(f'      <media-rep kind="original-media" src="{esc("file://" + quote(RECORDING))}"/>')
    w('    </asset>')
    w('  </resources>')
    w('  <library>')
    w('    <event name="BUMP video">')
    w('      <project name="BUMP: narrated gameplay">')
    w(f'        <sequence format="r1" duration="{tf(total)}" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">')
    w('          <spine>')
    for i, clip in enumerate(clips):
        w(f'            <asset-clip ref="r2" name="BUMP gameplay" offset="{tf(clip["offset"])}" start="{tf(clip["src"])}" duration="{tf(clip["dur"])}" format="r1" tcFormat="NDF">')
        w(f'              <adjust-volume amount="{GAME_VOLUME}"/>')
        for local, shown, lines in markers[i]:
            w(f'              <marker start="{tf(local)}" duration="{tf(1)}" value="{esc(shown)}" note="{esc(lines)}"/>')
        w('            </asset-clip>')
    w('          </spine>')
    w('        </sequence>')
    w('      </project>')
    w('    </event>')
    w('  </library>')
    w('</fcpxml>')
    with open(os.path.join(HERE, "BUMP_video.fcpxml"), "w") as f:
        f.write("\n".join(out) + "\n")

    seconds = total / FPS
    first = STRETCHES[0][1] - STRETCHES[0][0]
    second = first + STRETCHES[1][1] - STRETCHES[1][0]
    doc = ["# BUMP: narration", ""]
    doc.append(f"{clock(seconds)} of gameplay in three stretches, with hard cuts at {clock(first)} and {clock(second)}. "
               "Each beat starts at its timecode, over what's on screen; the same lines sit in a marker's "
               "note in the timeline. Swap in your name in the first line.")
    doc.append("")
    for n, (at, shown, lines) in enumerate(BEATS):
        until = BEATS[n + 1][0] if n + 1 < len(BEATS) else seconds
        words = len(lines.split())
        doc.append(f"**{clock(at)}** · {shown} *({until - at:.0f} s, {words} words)*")
        doc.append("")
        doc.append(lines)
        doc.append("")
    with open(os.path.join(HERE, "BUMP_video_script.md"), "w") as f:
        f.write("\n".join(doc))

    print(f"{len(clips)} clips, {seconds:.1f} s")
    for n, (at, shown, lines) in enumerate(BEATS):
        until = BEATS[n + 1][0] if n + 1 < len(BEATS) else seconds
        words = len(lines.split())
        print(f"  {clock(at)} {until - at:5.1f}s {words:4d}w {words / (until - at) * 60:4.0f} wpm  {shown}")


if __name__ == "__main__":
    build()
