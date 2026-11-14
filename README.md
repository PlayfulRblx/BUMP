# BUMP

A Mario Party style party game on Roblox, built on ArcEngine: platformer controls in the spirit of
Super Mario Odyssey, and a series of minigames where winning earns gold. A neon city lobby (built
from the AR place's hub) with the arena in its middle, so everyone on the plaza watches the round;
eight seats with bots filling the empty ones, five games a session, alternating:

- **BUMP**: ride a ball on a crumbling hex platform and knock everyone else off.
- **Bomber Bloxians**: pass the enormous ticking bomb by running into someone before its hidden
  fuse runs out; every blast bites a hole in the arena.

Gold buys power-ups (Shield, Turbo, Shockwave, Second Chance) and their upgrades; levels from XP
unlock the higher upgrades; the REWARDS store pays a daily reward that grows with a streak. How
tools, assets and AI were used is in [AI_AND_ASSETS.md](AI_AND_ASSETS.md).

## Controls

| Move | Keyboard and mouse |
| --- | --- |
| Jump; press again in the air to run on air while you hold it | Space |
| Backflip (standing) or long jump (running) | Hold C, then Space |
| Ground pound; Space just after it lands for a high jump | C in the air |
| Dive (also out of a ground pound); Space in the belly slide to hop out | Click or E in the air |
| Roll | Hold C and click while moving |
| Bump (shove whoever is in front) | Click or E on the ground |
| Wall cling, then a slide down, then you let go; wall jump off it | Jump or fall into a wall, then Space (C drops you) |
| On a ball: steer, pull back to skrrt, hold to charge a dash | Move keys; click or E |
| Use your power-up (once a game) | Q |
| Open the shop | B, or the SHOP and LOCKER stores in the lobby |
| Lobby stores (shop, daily reward) | F at the glowing pad |

Gamepad: A jump, L2/R2 crouch, X/B attack, Y power-up, Select shop, D-pad up for the lobby stores.
In Studio, every movement number is an attribute on `ReplicatedStorage.BumpTuning` (Server view)
and can be changed while playing.

## Layout

| Folder | What it holds |
| --- | --- |
| `BUMP/` | The game project: `src/Client`, `src/Server`, `src/Shared`, tools, Rojo and darklua config |
| `BUMPResources/` | The ResourceManager the engine requires (item data and empty getters) |

The engine is not in this repo. Both projects expect it at `../../../ArcEngine` from inside
`BUMP/`, which is where it sits when this repo is checked out as `Games/BUMP` in the ArcEngine
folder.

## Run it

Open `BUMP/BUMP.code-workspace` in VS Code and use the **Dev: Start All** button, or:

```bash
python3 BUMP/tools/dev_tasks.py dev-all
```

Then connect Studio's Rojo plugin to `127.0.0.1:1355`. If another ArcEngine game's dev stack is
already running, add `--shared-engine`.

Or build a place file and open it straight in Studio:

```bash
zsh BUMP/tools/open_place.sh
```

The game's place is a Team Create, placeId 105611532229008.

## Adding a system

Put a module with a `start()` function in `BUMP/src/Server/Systems` or `BUMP/src/Client/Systems`,
then list it in `BUMP/src/Shared/SystemList.lua`.
