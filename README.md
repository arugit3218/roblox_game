# roblox_game

This repo is used for Roblox game development, built with [Rojo](https://rojo.space).

## Development

1. Install the toolchain: `rokit install`
2. Start syncing: `rojo serve`
3. In Roblox Studio, connect with the Rojo plugin.

## Structure

- `src/shared` → ReplicatedStorage/Shared — types, config, pure utilities
- `src/server` → ServerScriptService/Server — authoritative game systems
- `src/client` → StarterPlayerScripts/Client — rendering, input, UI

## Checks

- Format: `stylua src`
- Lint: `selene src`
