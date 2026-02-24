# Instance System — Consolidated Roadmap

> **Project:** Instanced Hunts & Bosses for Crystal Server + OTClient
> **Version:** 2.0
> **Created:** 2026-01-28
> **Last updated:** 2026-02-07
> **Status:** Active development

---

## Table of Contents

1. [Repositories](#1-repositories)
2. [What Has Been Implemented](#2-what-has-been-implemented)
3. [Instance Hunt System Design](#3-instance-hunt-system-design)
4. [Implementation Phases](#4-implementation-phases)
5. [File Reference](#5-file-reference)

---

## 1. Repositories

| Repo | Path | Purpose |
|------|------|---------|
| Crystal Server | `/home/lucaslucas/repos/cs` | Backend C++ and Lua |
| OTClient | `/home/lucaslucas/repos/otclient` | Frontend C++ and Lua/OTUI |
| Canary | `/home/lucaslucas/repos/canary` | Historical docs only (no longer used for implementation) |

---

## 2. What Has Been Implemented

### 2.1 Instance Core (C++)

Full isolation by `instanceId` on all creatures:

- **Visibility:** `canSeeCreature()` filters by instance
- **Combat:** `canDoCombat()` blocks cross-instance attacks
- **Movement:** packets filtered by instance
- **Effects:** magic effects, distance effects, animated text, blood/splashes — all isolated
- **Items:** corpses, drops, loot — all tagged with `instanceid` custom attribute
- **Stackpos:** correct calculation filtering invisible items from other instances
- **Broadcasts:** speed, outfit, light, health — filtered by instance
- **Lua API:** `changeInstance()`, `createInstanceMonster()`, `createInstanceNpc()`, `clearMapInstance()`

### 2.2 BossLever Instanced (Lua)

- `instanced = true` flag on any BossLever config
- `maxInstances` configurable per boss
- Automatic instance creation/cleanup
- Boss spawn inside the instance
- Per-player cooldown functional
- Zone-based cleanup when all players leave
- Integration with `InstanceRegistry` for UI data

### 2.3 RaidInstance — Gaz'Haragoth (Lua)

- Instance created when descending stairs during active raid
- Automatic grouping by party/guild (same instance)
- Solo players pass through without instancing
- `timeToDefeat = 45 min`, `timeAfterKill = 5 min`
- No individual cooldown for raids
- Exit to z=10 functional
- Cleanup on zone leave

### 2.4 Instance UI (Server + Client)

- `InstanceRegistry` global table: register, unregister, sendUpdate, sendClear, broadcastUpdate
- Extended Opcode 210 with JSON payload:

```json
{
  "action": "update",
  "data": {
    "instanceId": 5,
    "type": "raid",
    "name": "Gaz'Haragoth",
    "outfit": { "type": 248, "head": 0, "body": 0, "legs": 0, "feet": 0, "addons": 0 },
    "players": [
      { "name": "Player1", "level": 350, "vocation": "Elite Knight" }
    ],
    "timeRemaining": 2700,
    "createdAt": 1770774239
  }
}
```

- `game_instance` OTClient module (MiniWindow, local timer, auto-open/close)
- `/instanceui` god command for debugging
- Live reload enabled on client

### 2.5 Already Working (no action needed)

- Monsters in instances — spawn and timers configured at instance creation
- NPCs in instances — functional
- **Note:** cleanup of ended instances needs review

---

## 3. Instance Hunt System Design

### 3.1 Concept

A system where the player selects a **Hunt** (zone/cave) from a list — similar to the Prey dialog — and enters a private instance of that zone. A separate **Instance Stamina** bar (e.g., 6h/day) limits farming time.

### 3.2 Architecture (Inspired by Prey)

The Prey system uses:

- 3 slots with states (Locked, Inactive, Active, Selection)
- Grid of 9 random monsters based on player level
- Reroll with gold or prey wildcard cards
- Active bonus with timer (2h default)
- Native opcodes (0xE7, 0xE8, 0xE9) with binary parsing
- `PreySlot` class in C++ with database persistence (`player_prey` table)

The Instance Hunt system adapts these concepts:

| Prey Concept | Instance Hunt Adaptation |
|---|---|
| Slots (3 simultaneous) | Hunt Slots (1 active at a time, expandable) |
| Monsters (individuals) | Hunts (zones with name, area, defined spawns) |
| Bonus timer (2h) | Instance Stamina (separate bar, 6h/day, regenerates) |
| Selection grid (9 random) | Available hunts list (by level/quest progression) |
| Reroll (random new list) | Not needed (fixed list based on progression) |
| Prey cards (premium currency) | Instance tokens or gold (entry cost) |
| Protocol (native binary) | Extended Opcode JSON (already working) |

### 3.3 Player Flow

```
Player opens Hunt Menu
    │
    ▼
Client sends request ──► Server returns available hunts list
    │
    ▼
Player selects a hunt
    │
    ▼
Client sends huntAction(select, huntId)
    │
    ▼
Server validates: stamina, level, cooldown, cost
    │
    ▼
Server creates instance of the zone
    │
    ▼
Server teleports player into instance
    │
    ▼
Server sends UI update with active hunt data
    │
    ▼
Every second: server decrements Instance Stamina
    │
    ├── Stamina runs out → warning 5 min before → teleport to exit → cleanup
    └── Player leaves voluntarily → return to global → cleanup if empty
```

### 3.4 Instance Stamina

- **Separate bar** from normal stamina
- **Duration:** 6h/day (21600 seconds) — configurable
- **Regeneration:** ~1 minute of stamina per 3 minutes offline — configurable
- **Does not affect** normal XP stamina
- **Persisted** in database
- **Visible** in client UI as an additional bar

### 3.5 Available Hunts

Each hunt is a pre-defined zone with:

- Name (e.g., "Rotworm Cave", "Dragon Lair", "Demon Forge")
- Area (from/to positions)
- Minimum level requirement
- Monsters that spawn (list or uses original map spawns)
- Max time per session (optional, in addition to stamina)
- Cooldown between sessions (optional)
- Entry cost (gold/tokens)

### 3.6 Protocol Decision

**Current approach: Extended Opcode (JSON)**

- Fast to implement, flexible, infrastructure already exists
- Module `game_instance` already receives and parses data

**Future option: Native opcodes (binary)**

- More performant, integrates with native client systems
- Requires C++ changes in both repos
- Only worth considering if performance becomes an issue

---

## 4. Implementation Phases

### Phase 1: Instance Hunt Infrastructure (MVP)

**Server (Lua):**

- Create `InstanceHunt` class in `data/libs/functions/instance_hunt.lua`
- Registry of available hunts (name, area, level req, monsters, cost)
- Selection and instance creation when player chooses a hunt
- Instance Stamina timer (decrement, warning, kick)

**Server (C++ if needed):**

- `instanceStamina` attribute on Player (database persistence)
- Offline stamina regeneration

**Client:**

- Expand `game_instance` or create `game_instance_hunt` with selection menu
- Hunt list with info (name, level, cost, remaining stamina)
- Instance Stamina bar

### Phase 2: UI Polish and Features

- Polished UI similar to Prey (hunt grid, zone preview, monster outfits)
- Stamina bar integrated in HUD
- Transition animations (fadeIn/fadeOut on enter/exit)
- Cooldown display
- Recent hunts history

### Phase 3: Testing and Balancing

- Test existing game functions inside instances (stairs, holes, NPCs, quests)
- Stress test with multiple simultaneous instances
- Stamina balancing (is 6h enough? fair regeneration?)
- Economic balancing (entry cost vs obtained loot)
- Instance cleanup review (memory leaks, orphan monsters)

### Phase 4: Production

- Global hard caps (max simultaneous instances)
- Metrics and monitoring (`/metrics` command)
- Feature flag (enable/disable without recompilation)
- Final documentation
- Database migrations

---

## 5. File Reference

### Server — Crystal Server

| File | Purpose |
|------|---------|
| `data/libs/functions/raid_instance.lua` | `InstanceRegistry` + `RaidInstance` class + `INSTANCE_OPCODE = 210` |
| `data/libs/functions/boss_lever.lua` | `BossLever` class with `instanced` flag |
| `data/scripts/creaturescripts/others/instance_opcode.lua` | ExtendedOpcode handler for client "fetch" requests |
| `data/scripts/creaturescripts/player/login.lua` | Registers `InstanceOpcode` event on player login |
| `data/scripts/talkactions/god/instanceui.lua` | `/instanceui` god command for testing |
| `data/scripts/movements/raid_instance_gaz_haragoth.lua` | Gaz'Haragoth raid instance config |

### Client — OTClient

| File | Purpose |
|------|---------|
| `modules/game_instance/instance.otmod` | Module definition (autoload, sandboxed) |
| `modules/game_instance/instance.lua` | Main logic: opcode handler, UI management, timer |
| `modules/game_instance/instance.otui` | UI layout (MiniWindow with labels and player list) |
| `modules/game_interface/interface.otmod` | Lists `game_instance` in load-later |

### Reference — Prey System (for Instance Hunt design)

| File | Purpose |
|------|---------|
| `src/io/ioprey.hpp` / `.cpp` | `PreySlot` class, `IOPrey` manager |
| `src/server/network/protocol/protocolgame.cpp` | `sendPreyData` (0xE8), `parsePreyAction` |
| `data/scripts/eventcallbacks/monster/ondroploot_prey.lua` | Loot bonus handler |
| `data/events/scripts/player.lua` | Experience bonus application |
| `modules/game_prey/prey.lua` (OTClient) | Client-side prey UI (1926 lines) |
| `modules/game_prey/prey.otui` (OTClient) | Prey UI layout (845 lines) |
| `docs/PREY_SYSTEM_ANALYSIS.md` | Full Prey system analysis |

---

*Document consolidates and supersedes previous roadmaps from the Canary repository:*
- *INSTANCED_HUNTS_ROADMAP.md (2026-01-28)*
- *INSTANCED_HUNTS_TECHNICAL_ROADMAP.md (2026-01-28)*
- *INSTANCED_HUNTS_KEY_CHANGES.md (2026-01-28)*
- *INSTANCE_SYSTEM_PLAN.md (2026-01-28)*
