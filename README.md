# Underwater Egg Heist (roblox_game)

Idle underwater egg-stealing game for Roblox, built with [Rojo](https://rojo.space).
Steal one egg per heist (Aquarium or Caviar type, shown before you steal), hatch it,
and earn coins passively from aquarium visitors or actively from caviar orders.

## Development

1. Install the toolchain: `rokit install`
2. Start syncing: `rojo serve`
3. In Roblox Studio, connect with the Rojo plugin (port 34872).
4. Press Play. The map is built at runtime by `World.luau`, so it only appears in play mode.

Saving requires the place to be **published** and **Game Settings → Security →
Enable Studio Access to API Services** turned on. Without that, Studio uses a
temporary profile (a warning shows bottom-left) and nothing saves.

## Structure

- `src/shared` → ReplicatedStorage/Shared
  - `Config` — tunables (phase, slots, offline cap, chase settings)
  - `GameData/` — creatures (all 25 tiers), rarities (income/hatch/caviar balance), shop (speed, trails)
  - `Economy` — pure rules shared by server and client (aquarium accrual, speed, trail unlocks)
- `src/server` → ServerScriptService/Server
  - `Systems/PlayerData` — session-locked DataStore saves, autosave, state sync to client
  - `Systems/World` — builds lighting, sea floor, plots, nests, safe line; renders pets
  - `Systems/Heist` — steal → chase → escape/caught (server-authoritative)
  - `Systems/Idle` — incubation, aquarium income, caviar feeding, orders
  - `Systems/Shop` — speed upgrades, trails
  - `Systems/DevTools` — Studio-only test commands
  - `Lib/Net` — remotes + per-action rate limiting
- `src/client` → StarterPlayerScripts/Client
  - `Controllers/Hud` — top bar, toasts, heist banner
  - `Controllers/Menus` — Eggs, Aquarium, Kitchen, Shop panels

## Studio test commands

While playtesting in Studio, run in the **server** command bar:

```lua
local D = game.ServerStorage.DevCommand
D:Invoke("coins", nil, 10000)        -- add coins
D:Invoke("egg", nil, "3:Caviar")     -- give an egg (tier:Aquarium|Caviar)
D:Invoke("skip")                     -- finish all hatch / caviar timers
D:Invoke("elapse", nil, 3600)        -- pretend 1h passed for aquarium income
D:Invoke("tier", nil, 5)             -- set highest tier stolen
```

## Checks

- Format: `stylua src`
- Lint: `selene src`
