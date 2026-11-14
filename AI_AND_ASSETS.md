# BUMP: tools, assets and how AI was used

This file covers what the brief asks to be explained: which tools and assets were used, where AI
contributed, and what was changed. The code in `BUMP/src` is the game. The engine underneath it
(ArcEngine) is shared with my other Roblox games and isn't part of this repo.

## Tools

| Tool | What it did |
| --- | --- |
| **Claude Code** (Anthropic) | Wrote most of the Luau in `BUMP/src` from my direction, one feature at a time, and the animation scripts in `BUMP/animation/scripts` |
| **Roblox Studio + Studio MCP** | Claude ran Play sessions, read the log, measured things (jump heights, ball speeds, game lengths, how far a knock throws) and took screenshots to check its own work before handing it to me |
| **Blender (headless, scripted)** | Every animation clip is written as a Python script, rendered to preview sheets (`design/animation/`), shown to me, and only exported to Lua data once approved. Nothing is uploaded to Roblox |
| **Rojo + darklua** | Files on disk synced into Studio; `dev_tasks.py prepare` checks every file parses and every require resolves |
| **UI Labs** | The HUD kit is built as stories (`UIFusion/Stories`) so screens can be checked on their own |
| **ArcEngine** | My own engine: systems loader, data saving, money, input chips, camera layers, UI host |

## Where AI contributed, and where I steered

Claude wrote the code. I set the design, played each stage, and sent back what was wrong. Every
number is a first guess until I've played it, and many features went through several rounds.
Quotes are mine, from the sessions:

- **Jumping.** First an Odyssey-style single/double/triple chain. I found the animations "terrible"
  and had them rebuilt from scratch; a double flip was tried and dropped; a star pose after the flip
  "sticks ... a bit too long" and was removed. Then I replaced the triple jump altogether: "a jump
  and then a floaty jump if I try to jump again whilst in the air", and when the first float spun
  and glided, "No I want it to be like a running on air kind of float".
- **Feel.** "I still don't like the movement ... They're not polished enough" led to heavier jump
  arcs, a jump buffer and coyote time, air turning ("loosely control our rotation whilst jumping"),
  and springy lean, bank and landing dips. The sprint was "too fast for the speed the player's
  running at", so the run cycle was slowed.
- **Riding a ball.** Remade three times: "looks terrible", then "running matching momentum with the
  ball", then "It should look intense as if the player is trying for dear god to stay on the ball".
  That last round also found a real bug: a rider's body reports no velocity, so the animation always
  thought they were standing still.
- **Hits.** "There's not really that feel good feeling behind the impact": faster balls, hit-stop, a
  camera punch, sparks and comic words. Diving into a rider now steals their ball. A ball running
  someone over throws them far ("at the moment it looks like they only ragdoll").
- **Bomber Bloxians.** The bomb "doesn't look fun to carry at all", so each client now draws its own
  bomb, sprung to the holder's hands. The holder "should just pop and disappear almost instantly".
- **The floor.** "Instead of deleting the outer edge of the arena as a whole ... remove individual
  cells one by one." I chose edge first, holes later, speeding up.
- **The lobby.** I turned down six Blender lobby concepts (`design/lobby/A`–`F`) for "a more standard
  roblox lobby experience" built from my own AR place's neon city. I then had its leftover areas
  removed, the world brightened, the neon arena toned down ("It's hard for the players to see
  eachother"), and a visible spotlight cone removed ("We just need the light itself").
- **Presentation.** Arena build-in and fly-out. That was reordered after I saw it overlap ("It needs
  to visibly unload, and then reload the new map before the round even starts"). The intro was
  re-cut to focus on the player, and the countdown made "a lot more tasteful".
- **Bots.** "Let's get 4 more AIs in and improve the AI massively": 8 seats, and each bot gets a
  personality (Bully, Opportunist, Coward, Wildcard) and a skill level. Games went from 8–27 s
  (bots rolling themselves off) to 50–90 s.
- **Reasons to come back.** Gold buys power-ups and their upgrades, levels gate the higher upgrades,
  a daily reward builds a streak, and the leaderboard boards show the server's winners.
- **Taken out at my word.** A revenge launcher for spectators ("Let's remove it"), a board between
  games (turned down), the thrown hat (not picked).

`CLAUDE.md` keeps the full log of each request, what was built, what was measured and what hasn't
been checked yet.

## Assets

| Asset | Where it comes from |
| --- | --- |
| The lobby city | My own place **AR**: its hub copied in, re-centred, with its walk-in halls and anime branding removed and BUMP's signs added |
| Animation library (Idle, Fall, Roll, Land, Carry, WallBonk, Dazed...) | My earlier games (The Scramble, Smash Arena), as scripted Blender data |
| Run cycle | The Playful animation pack, imported as data from an `.rbxm` |
| Particle sprites (cloud, ring, stars, sparkles) | My VFX IKEA library place |
| UI kit | Ported from my game The Scramble, built on ArcEngine's input chip look |
| Music | APM Music from Roblox's licensed audio library: "Silly Chase", "Comedy Clip (a)", "Shooting Stars" |
| Sound effects | Pro Sound Effects from Roblox's licensed library (whistle, whooshes, pops, tyre swerve, skateboard roll), and Roblox's built-in sounds |
| Everything else in the arenas | Built by code: hex tiles, balls, the bomb, effects |

No Nintendo or other third-party game art, music or characters are used. The KO blast, the pop
and the comic words are our own take on the feel I wanted.

## What's checked and what isn't

Each feature was measured in Play with one player and bots, and the numbers are in `CLAUDE.md`.
Not yet done: a session with two or more real players, a phone, and a gamepad.
