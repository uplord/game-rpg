# Uplord Game — Phase 3 Core UI

This build keeps the Stage 1 local-only architecture and adds the first playable world layer.

## Stage 2 additions
- Area loading through stable local area IDs and ContentRepository.
- `CharacterBody2D` player with collision.
- WASD + arrow-key movement.
- Click/tap movement and press/drag/hold destination updates.
- Camera follows the player and clamps to area bounds.
- Authored spawn markers (`Spawns/default`, named transition spawns).
- Deterministic area transitions that specify both destination area and spawn.
- Starter Town and Starter Forest test areas with edge collision.
- Current area/spawn is saved locally after transitions.
- Existing responsive HUD/modal system remains in place.

## Test
Run the project. Move with WASD/arrows or click/tap the world. Walk through the right-side Starter Town gate to enter Starter Forest, then use the left-side forest gate to return.

Firebase, networking, multiplayer rooms and remote players remain intentionally absent.


## Roadmap
See `ROADMAP.md` for the updated use-based skill-progression roadmap.
