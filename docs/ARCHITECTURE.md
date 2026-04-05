# Crystal Server — Instance System Architecture

> Reference document for AI sessions. Updated as the system evolves.
> Last updated: 2026-02-25

---

## System Overview

Crystal Server is a C++/Lua MMORPG emulator. The **instance system** allows private copies of game zones where players fight independently. Three instance types exist: **Hunt Instances** (cave farming), **Boss Instances** (lever-triggered boss fights), and **Raid Instances** (event-triggered encounters).

---

## C++ Layer

### Core Classes

| Class | File | Role |
|-------|------|------|
| `InstanceManager` | `src/game/instances/instance_manager.{hpp,cpp}` | Singleton — creates/destroys instances, moves players, populates spawns |
| `WorldInstance` | `src/game/instances/instance_manager.hpp` | Data holder — ID, owner, cloned spawns |
| `Zone` | `src/game/zones/zone.{hpp,cpp}` | Named set of positions with BFS flood-fill, spatial queries, creature/item caches |
| `Creature` | `src/creatures/creature.{hpp,cpp}` | Base entity — carries `instanceId` (1=global, 2+=private, UINT32_MAX=visible-to-all) |
| `SpawnMonster` | `src/creatures/monsters/spawns/spawn_monster.{hpp,cpp}` | Monster spawn definition — `cloneForInstance()` for private copies |

### Zone Flood-Fill (`zone.cpp`)

```
buildFromFloodFill(seedPos, maxTiles=5000, maxDistance=300)
  → 4-neighbor BFS from seed, same Z-level only
  → Chebyshev distance cap from seed
  → Follows same-Z item teleports within distance
  → Does NOT follow stairs/holes (cross-Z left to Lua expansion)
  → Post-pass: detects stair entries, teleport entries/exits, spawns
  → Returns FloodFillResult with full metadata

expandFromFloodFill(startPositions, maxTiles)
  → Additive BFS from multiple seeds
  → Starts with existing zone positions as "visited"
  → Same neighbor rules, no teleport/floorchange following
  → Used by Lua expansion loops for script-teleport destinations
```

### Instance Isolation

Every game system filters by `creature->getInstanceID()`:

| System | File(s) | Filtering |
|--------|---------|-----------|
| Visibility | `creature.hpp` | `canSeeCreature()` — same instance or VISIBLE_TO_ALL |
| Combat | `combat.cpp` | `canDoCombat()` blocks cross-instance |
| Movement | `map.cpp` | Spectator lists filtered by instance |
| Effects | `game.cpp` | Magic effects, distance, animated text — instance-tagged |
| Items | `tile.cpp` | `instanceid` custom attribute on drops/corpses |
| Network | `protocolgame.cpp` | Item packets filtered by instance |
| NPCs | `npc.cpp` | Set to `INSTANCE_VISIBLE_TO_ALL` |

### Lua Bindings

| Lua API | C++ Method | File |
|---------|-----------|------|
| `Game.createInstance()` | `InstanceManager::createInstance` | `game_functions.cpp` |
| `Game.destroyInstance(id)` | `InstanceManager::destroyInstance` | `game_functions.cpp` |
| `Game.populateInstanceFromZone(id, zone)` | `InstanceManager::populateFromZone` | `game_functions.cpp` |
| `player:changeInstance(id)` | `InstanceManager::movePlayerToInstance` | `player_functions.cpp` |
| `Zone:buildFromFloodFill(seed, max, dist)` | `Zone::buildFromFloodFill` | `zone_functions.cpp` |
| `Zone:expandFromFloodFill(posTable, max)` | `Zone::expandFromFloodFill` | `zone_functions.cpp` |
| `Zone.removeByName(name)` | `Zone::removeZone` | `zone_functions.cpp` |
| `Tile:getFloorchangeDestination()` | `computeFloorchangeDestination` | `tile_functions.cpp` |
| `Game.getSpawnsInArea(from, to)` | scan global+custom spawns | `game_functions.cpp` |

---

## Lua Layer

### Loading Order

```
1. data/libs/functions/load.lua
   → teleport.lua (ScriptTeleportRegistry + spatial index)
   → teleport_registry_extra.lua (manual teleport registrations)
   → hunt_instance.lua (HuntInstance class)
   → instance_registry.lua (InstanceRegistry shared by all instance types)

2. revscriptsys.lua (EventCallback metatables)

3. data/scripts/ (all game scripts)
   → movements/hunt_*.lua (HuntInstance:register() → _pendingZones)
   → eventcallbacks/hunt_main_map_on_load.lua (deferred zone build)
   → talkactions/gm/hunt_zone_helper.lua (/hunt GM command)
   → creaturescripts/others/instance_opcode.lua (client UI data)
```

### HuntInstance Lifecycle

```
register() → queue in _pendingZones
              ↓ (mapOnLoad fires)
doBuildZone() → buildFromFloodFill + expansion loop
              → ZoneEvent afterEnter/afterLeave registered
              ↓ (player walks into zone while instanceId==1)
onStepIn()  → validate level/cooldown/stamina
            → Game.createInstance() + populateInstanceFromZone()
            → player:changeInstance(newId)
            → InstanceRegistry.register()
              ↓ (player leaves zone or timeout)
afterLeave() → grace period timer
              ↓ (grace expires with no one inside)
cleanupInstance() → teleport players out
                  → Game.destroyInstance()
                  → InstanceRegistry.unregister()
```

### ScriptTeleportRegistry

Sector-based spatial index (32x32 grid) for O(1) area queries.
Two indexes: `_srcSectors` (by source position), `_dstSectors` (by destination position).
Lazy-populated from `TeleportUnique` table on first query.

### GM /hunt Command

| Action | Purpose |
|--------|---------|
| `discover` | Flood-fill from nearby entry, expand via teleports |
| `name, X` | Set hunt name |
| `exit` | Set exit position to current pos |
| `goto, X` | Teleport to entries/exit/seed |
| `status` | Show session state |
| `test` | Create real instance and enter |
| `print` | Display generated config |
| `save` | Write hunt file |
| `clear` | Discard session + destroy temp zone |
| `scan` | Grid-based cluster discovery |
| `list` | Show scan results |
| `accept, N` | Accept cluster N |

---

## Teleport Taxonomy

| Type | Detection | Followed By |
|------|-----------|-------------|
| Item Teleport (OTBM map) | `TILESTATE_TELEPORT` | C++ BFS (same-Z, within distance) |
| Script Teleport (registered) | `ScriptTeleportRegistry` lookup | Lua expansion loop |
| Script Teleport (unregistered) | Manual entry in `teleport_registry_extra.lua` | Lua expansion loop (after registration) |
| Boss Teleport | Intentionally excluded | Nothing — boss rooms stay outside hunt zones |
| Floor Change (stair/hole) | `TILESTATE_FLOORCHANGE*` | NOT followed by BFS (cross-Z by design); detected as entries |

---

## Database

- `player_prey` — Prey slot persistence (reference for hunt stamina design)
- Instance data is **not persisted** — instances are ephemeral, recreated per session
- Player instance tracking: `Game.trackInstancePlayer(guid, id)` for relog reconnection
