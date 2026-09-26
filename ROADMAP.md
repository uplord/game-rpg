# Uplord — Updated Development Roadmap

Uplord is a 2D MMORPG built around use-based skill progression: players improve skills by performing the related activity. The single-player game systems are completed first, then moved onto server-authoritative multiplayer architecture.

## Phase 1 — Foundation — Complete
- Godot project structure and local game services.
- Data-driven content repository and stable IDs.
- Local save/state foundation.
- No Firebase or multiplayer dependency yet.

## Phase 2 — Player + World — Complete
- CharacterBody2D movement with keyboard and click/tap controls.
- Hold-to-move support and facing.
- Camera framing, map bounds and Phantom Camera behaviour.
- Portrait/landscape, desktop/mobile and safe-area handling.
- Area loading, authored spawns and transitions.
- World coordinates remain 1:1; camera zoom handles presentation scaling.

## Phase 3 — Core UI — Complete / Polish as Features Arrive
- Player card with HP/MP and basic character information.
- Five-slot combat bar.
- Menu entry points for Inventory, Skills, Quests, Shop and More.
- Chat and Interact controls.
- Quest tracker shell.
- Reusable responsive modal system.
- Portrait solid bottom HUD and landscape overlay layout.

## Phase 4 — Character + Skill Progression — Complete
- Character identity and persistent progression data.
- Independent skill levels and XP rather than relying on one character level.
- Initial skill set: Attack, Defence, Mining, Woodcutting and Fishing.
- Shared XP curves, level-up events and max-level rules.
- Data-driven level requirements and unlocks.
- Skills overview UI showing level, XP progress and upcoming unlocks.
- Prepare additional skills such as Magic, Ranged, Cooking, Smithing and Crafting.

## Phase 5 — Items + Equipment ✅
- Data-driven item definitions and stable item IDs.
- Inventory and bank data models.
- Equipment slots and equipped-item state.
- Tool types such as pickaxes, axes and fishing equipment.
- Skill/level requirements on items and equipment.
- Stackable items, quantities and item actions.
- Real Inventory UI.

Implemented foundation: stable data-driven item IDs, starter weapon/tools/armour/resources, stack quantities, inventory and bank persistence, five equipment slots, equip/unequip actions, skill requirements, and shared tool queries for Phase 6 gathering.

## Phase 6 — Gathering
- Shared interactable-resource system.
- Mining, Woodcutting and Fishing loops.
- Skill-level and tool requirements.
- Gathering duration/progress and interruption.
- Data-driven loot tables, XP rewards and respawn timers.
- Resource targeting through the shared Interact system.
- Gathering progression unlocks higher-tier resources.

## Phase 7 — Combat + Abilities
- Enemy targeting and combat state.
- Attack, Defence, Magic and Ranged progression where applicable.
- Five equipped combat abilities with larger learned ability pools.
- Ability requirements based on relevant skill levels.
- HP/MP, damage, cooldowns, death and respawning.
- Enemy drops, combat XP and rewards.
- Enemies do not auto-attack until combat is initiated unless a definition explicitly says otherwise.

## Phase 8 — Production Skills
- Cooking, Smithing and Crafting foundations.
- Recipes with skill requirements and XP rewards.
- Gathered resources feed production skills.
- Crafted equipment/consumables feed combat and gathering.
- Data-driven recipes so future content can be managed by the Admin CMS.

## Phase 9 — NPCs + Quests
- Shared NPC interaction system.
- Dialogue and quest markers.
- Quest requirements can reference skill levels and previous quests.
- Objectives, rewards, skill XP and content unlocks.
- Quests complement skill progression rather than replacing it.

## Phase 10 — Shops + Economy
- NPC shops, buy/sell and currency.
- Skill/item requirements where appropriate.
- Item sinks and sensible vendor values.
- Prepare economy data for later player trading and marketplace systems.

## Phase 11 — Dungeons + Advanced PvE
- Instanced dungeon flow.
- Bosses and encounter mechanics.
- Skill/quest access requirements.
- Dungeon rewards and unique loot tables.

## Phase 12 — Content Expansion + Single-Player Polish
- Expand areas, resources, enemies, NPCs, quests, items and recipes.
- Audio, animation, feedback and accessibility polish.
- Replace temporary map visuals/collision with production assets and CollisionPolygon2D where appropriate.
- Balance progression rates, XP curves, economy and unlock pacing.
- Complete the core game loop locally before networking it.

## Phase 13 — Online Architecture
- Separate client presentation from authoritative gameplay logic.
- Define network messages and server-owned state.
- Map/room population architecture.
- Validate actions server-side.
- Keep content definitions compatible with the Admin CMS release model.

## Phase 14 — Firebase + Accounts
- Authentication and account/character persistence.
- Cloud character data and account services.
- Published content/release integration where appropriate.
- Migration path from local development saves.

## Phase 15 — Multiplayer
- Dedicated authoritative game server.
- Player presence and remote-player replication.
- Server-authoritative movement, combat, gathering, drops and progression.
- Area rooms split by map with population limits.
- Reconnection and synchronization handling.

## Phase 16 — MMO Systems
- Parties and social systems.
- Guilds.
- Player trading.
- Marketplace/economy services.
- Multiplayer dungeons and group content.
- Moderation/admin hooks.

## Core Progression Rule
A skill improves by using that skill. Levels primarily unlock new resources, equipment, recipes, abilities, areas and activities; passive numerical bonuses are secondary. Content should be data-driven so new progression content can eventually be created and released through the Uplord Admin CMS without changing gameplay code.
