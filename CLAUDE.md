# BUMP: instructions for Claude sessions

A Roblox game on ArcEngine: a party game in the spirit of Mario Party, where players move with
Super Mario Odyssey style platformer controls and play a series of minigames; winning a minigame
earns gold. That is everything the user has said about it so far (2026-11-13); ask rather than
guess the rest (player count, whether there is a board, which minigames, what gold buys).

Right now it is the blank project: the engine, a baseplate with a spawn pad (`Workspace` in the
project files), and no game systems.

Fusion is 0.3. `processed-src/` and `processed-resources/` are generated: never read or write them,
edit `src/`.

## Layout

| Folder | What it holds |
| --- | --- |
| `BUMP/` | The game project: `src/Client`, `src/Server`, `src/Shared`, tools, Rojo/darklua config |
| `BUMPResources/` | The ResourceManager stub the engine requires (empty getters) |
| `../../ArcEngine` (from here) | The shared engine. Do not change it without saying so |

This folder is one git repo holding both projects, checked out as `Games/BUMP`. Scaffolding
(tools, project files, engine glue) was copied from The Scramble's blank project (itself from
Silly Billies's, Steal The Sky's and Tech Demos before that) and renamed. Paths assume each
project sits two levels under `Games/` (`../../../ArcEngine` from inside `BUMP/`).

## Adding a system

A system is a plain module with `start()` (and optional `init`, `playerAdded`, `characterAdded`),
the engine's usual shape. Put it in `src/Server/Systems` or `src/Client/Systems` and add its path
to `src/Shared/SystemList.lua` (`@GameServer/Systems/<Name>` or `@GameClient/Systems/<Name>`).
The master scripts build their load orders from that list.

## Day to day

- `python3 BUMP/tools/dev_tasks.py dev-all`, then connect Studio's Rojo plugin to
  `127.0.0.1:1355`. Add `--shared-engine` if another game's stack is running. Resources serves
  on 13418.
- No watchers: `python3 BUMP/tools/dev_tasks.py prepare --shared-engine` (sourcemap and
  darklua; proves every file parses and every require resolves).
- The game has no place yet. When the user makes one, add its place id to `Constants.GamePlaces`
  and record the place id, universe and Studio window title here.
- `zsh BUMP/tools/open_place.sh` builds `$TMPDIR/BUMP.rbxl` and opens it in Studio.
  Its `pkill` doesn't close the old window, so each run adds one: close your own old test windows
  and leave any the user may be in.
- A local place file from `open_place.sh` has PlaceId 0: profiles are in memory, and a few engine
  server systems (social, codes, world sync, referrals) fail to load there; that's expected
  noise in a local file.
- Terrain `Decoration` and `GrassLength` can't be set by scripts; they're in the project files
  (`Workspace.Terrain`), as is `Lighting.Technology = Future`.
- Specs (`*.spec.lua`) use the Nevermore Jest loader like the other games and aren't built.
