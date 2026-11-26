# Reasonable Doubt

An original procedural tech-noir detective game for Roblox. The design doc covers the plan and the reasons behind it.

## Layout

| Path | In Studio | What lives there |
| --- | --- | --- |
| `src/shared` | ReplicatedStorage.Shared | Config, seeded RNG, name pools |
| `src/server` | ServerScriptService.Server | World generation, citizen sim, schedules, saves |
| `src/client` | StarterPlayer.StarterPlayerScripts.Client | HUD |

`*.server.luau` files are Scripts, `*.client.luau` files are LocalScripts, and every other `.luau` file is a ModuleScript. The layout matches `default.project.json`, so Rojo works too.

## Syncing into Studio

Claude runs `python3 tools/sync_to_studio.py` and executes its output in Studio through the Studio connection. This mirrors `src/` into the place and removes scripts that were deleted from the repo. Never edit synced scripts inside Studio, because the next sync overwrites them.

## World

The city is rebuilt from a seed every session. Saves hold only the seed, the game clock and per-citizen changes (see `Persistence.luau`).
