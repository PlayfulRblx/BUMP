# BUMP

A Mario Party style party game on Roblox, built on ArcEngine: platformer controls in the spirit of
Super Mario Odyssey, and a series of minigames where winning earns gold. Early days: the blank
project only.

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

## Adding a system

Put a module with a `start()` function in `BUMP/src/Server/Systems` or `BUMP/src/Client/Systems`,
then list it in `BUMP/src/Shared/SystemList.lua`.
