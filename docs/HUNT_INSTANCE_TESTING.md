# Hunt Instance - Testing Guide

## Prerequisites

- Server compiled with flood-fill zone support (`Zone:buildFromFloodFill`, `Game.populateInstanceFromZone`)
- GM/God account logged in

## Strategy: Flood-Fill Discovery

Hunts are defined by a single **caveSeed** position (first walkable tile inside the cave).
At registration time, the system runs a BFS flood-fill from that position to discover:
- All connected walkable tiles (the exact cave shape)
- All z-levels (multi-floor caves via internal stairs)
- All entry tiles (stairs/holes leading in from outside)
- All spawns whose center is inside the cave

This replaces the old specPos rectangle approach and avoids:
- Merging separate caves at the same z-level
- Missing walkable corridors between spawn rooms
- Including spawns from adjacent caves

## Phase 1: Discover a cave

### Option A: Stand on entrance (recommended)

Stand on a stair/hole leading to the cave, then:

```
/hunt discover
```

The system follows the floor-change to the destination tile and flood-fills from there.

### Option B: Already inside the cave

If you're already inside (z>=8):

```
/hunt discover
```

Uses your current position as the flood-fill seed.

### Option C: Global scan + accept

```
/hunt scan                   → grid-based cluster scan (for browsing)
/hunt scan, Dragon Lord      → filter by monster name
/hunt list                   → browse results
/hunt goto, N                → teleport to cluster N
/hunt accept, N              → flood-fill from cluster center
```

## Phase 2: Review discovery results

The discover output shows: tile count, z-levels, spawn count, entry tiles.

```
/hunt status                 → full session info
/hunt goto, entries          → cycle through detected entries
/hunt goto, exit             → teleport to auto-detected exit
/hunt goto, seed             → teleport to caveSeed position
```

If the cave is too large (hit tile limit):

```
/hunt discover, 10000        → increase maxTiles limit
```

## Phase 3: Set name and exit

```
/hunt name, Dragon Lords #3 - Darashia
/hunt exit                   → set exit to current position (or auto-detected)
```

## Phase 4: Test instance

```
/hunt test
```

Creates a real instance, flood-fills the zone, populates spawns via `populateInstanceFromZone` (only spawns whose center is inside the flood-filled area), and teleports the GM to the caveSeed.

Walk around to verify monsters are correct and the cave boundaries make sense.
Use `/instance leave` to return to global.

## Phase 5: Save and activate

```
/hunt save[, filename]       → writes to data/scripts/movements/hunt_<name>.lua
/reload scripts
```

The saved config is minimal:

```lua
local hunt = HuntInstance({
    name = "Dragon Lords #3 - Darashia",
    caveSeed = Position(32847, 32165, 8),
    exit = Position(32847, 32163, 7),
    requiredLevel = 0,
    cooldownTime = 0,
    maxInstances = 20,
})
hunt:register()
```

## Phase 6: Test auto-instancing

Walk into the cave normally (down the stairs/hole):

1. Player walks down stairs/hole (floor change)
2. Zone `afterEnter` fires (the stair landing tile IS inside the flood-filled zone)
3. `HuntInstance:onStepIn` creates instance + populates spawns
4. Player stays on the landing tile (no forced teleport)
5. Walking back to the stair (one step before going up) does NOT trigger leave — the stair tile is part of the zone

To leave: walk fully out of the cave zone, or `/instance leave`.
The instance is cleaned up after the **leave grace period** (default 5 min) with no players.

## Commands reference

| Command | Description |
|---|---|
| `/hunt discover[, maxTiles]` | Flood-fill from stair/hole or current pos |
| `/hunt scan[, filter]` | Global grid scan for browsing clusters |
| `/hunt list[, page]` | Browse scanned clusters |
| `/hunt nearby` | 10 nearest clusters |
| `/hunt goto, <N>` | Teleport to cluster N center |
| `/hunt accept, <N>` | Flood-fill from cluster N |
| `/hunt name, <name>` | Set hunt name |
| `/hunt exit` | Set exit position |
| `/hunt status` | Show session info |
| `/hunt goto, entries/exit/seed` | Navigate key positions |
| `/hunt test` | Create test instance |
| `/hunt print` | Show config in chat |
| `/hunt save[, filename]` | Save config to disk |
| `/hunt clear` | Reset session |

## Quick workflow

```
/hunt discover
/hunt name, Dragon Lords - Darashia
/hunt goto, entries
/hunt goto, exit
/hunt test
/instance leave
/hunt save
/reload scripts
```

Then walk down the stairs to trigger auto-instancing.
