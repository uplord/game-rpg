# Uplord Game

## Current stage: Stage 1 — Single-player foundation

This build intentionally has no Firebase, game server, networking, rooms or multiplayer systems.

The foundation now separates local persistence, content definitions, runtime game state and character-facing gameplay APIs so those backends can be replaced or extended later without rewriting the UI/gameplay features.

### Added in Stage 1

- `LocalSave` — JSON persistence at `user://savegame.json`.
- `ContentRepository` — loads local ID-driven JSON definitions from `res://data/definitions/`.
- `GameState` — owns the current local character/progression/inventory/equipment/skills/quests/gold/world state.
- `CharacterService` — first gameplay-facing service boundary; callers should avoid mutating `GameState` directly.
- Stable starter area ID: `area.starter_town`.
- New-game defaults and save-version field for future migrations.

### Next stage

Stage 2 should build the playable world layer: area loading, spawn markers, player `CharacterBody2D`, click/tap + hold movement, keyboard movement, collision, Phantom Camera follow/limits, and deterministic area transitions.
