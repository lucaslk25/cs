# Hunt Discover — Review Fixes Tracker

Issues found during senior code review of the hunt discover system.
All 7 issues have been fixed and verified.

---

## Fix 1: `expandFromFloodFill` stale 50-tile hardcoded distance cap
**File:** `src/game/zones/zone.cpp`
**Severity:** Medium | **Effort:** Low

The C++ `expandFromFloodFill` had `static constexpr int maxDistance = 50` measured from the
seed bbox of each batch of destinations. But the Lua expansion loop already filters destinations
to `seedPos ± maxDistance` (Chebyshev 300) before calling this function. The 50-tile cap was
a stale artifact that silently truncated expansion for rooms larger than 50 tiles.

**Fix:** Removed the hardcoded distance cap and seed-bbox computation entirely. The function
now trusts the seeds it receives (Lua-side distance filter is the canonical constraint) and
only bounds by `maxTiles` and map walls/PZ.

**Status:** `[x] done`

---

## Fix 2: Unused `border` set in `buildFromFloodFill`
**File:** `src/game/zones/zone.cpp` (was lines 265-275)
**Severity:** Low | **Effort:** Low

A `border` set was computed (all 4-neighbor positions outside the zone) but never iterated or
used by any code path. Dead code left over from a planned feature.

**Fix:** Removed the dead border computation block (10 lines).

**Status:** `[x] done`

---

## Fix 3: Stale "200-tile" comment
**File:** `src/game/zones/zone.cpp` (neighbor loop block comment)
**Severity:** Low | **Effort:** Trivial

Comment said "followed with the 200-tile distance guard" but the code was changed to use
`distCap` (which defaults to 300). Misleading for future readers.

**Fix:** Updated comment to reference `distCap`.

**Status:** `[x] done`

---

## Fix 4: `doBuildZone` log under-reports tile count
**File:** `data/libs/functions/hunt_instance.lua`
**Severity:** Low | **Effort:** Low

The startup log reported `result.tiles` which was only from the initial `buildFromFloodFill`.
After the expansion loop added tiles via script teleports, the zone could be larger but the
log didn't reflect it. E.g., logged 3923 tiles but zone actually had 4100+.

**Fix:** After expansion loop, get actual zone positions, count them, extract z-levels, and
use in the log. Now shows e.g. "4100 tiles (3923 initial + 177 expanded)".

**Status:** `[x] done`

---

## Fix 8: Expansion loop re-queries teleport registry each iteration
**Files:** `hunt_zone_helper.lua` (discover/test/accept), `hunt_instance.lua` (doBuildZone)
**Severity:** Low | **Effort:** Low

`getScriptTeleportsWithSourceInArea()` was called inside the `for _ = 1, 5` loop with
identical `searchFrom`/`searchTo` each time. The result is the same every iteration — only
the `zone:contains()` checks change.

**Fix:** Hoisted the query outside the loop (`local allScriptTeleports = ...` before the
`for` loop) in all 4 expansion sites: discover, test, accept, doBuildZone.

**Status:** `[x] done`

---

## Fix 9: Spawn count not updated after expansion
**File:** `hunt_zone_helper.lua` (discover action, post-expansion recalculation block)
**Severity:** Medium | **Effort:** Medium

`result.spawns` was from the initial `buildFromFloodFill` only. After expansion added tiles
(e.g., Feaster of Souls slab rooms on z=9), spawns in those areas were not counted. Output
understated actual spawn count.

**Fix:** After expansion, call `Game.getSpawnsInArea` on the full post-expansion bbox and
update `result.spawns`. This uses the rectangular bbox which may slightly overcount (if spawns
exist in the bbox but outside the irregular zone shape), but it's more accurate than ignoring
expanded areas entirely.

**Status:** `[x] done`

---

## Fix 12: `accept` action missing explicit `maxDistance`
**File:** `hunt_zone_helper.lua` (accept action)
**Severity:** Low | **Effort:** Trivial

`buildFromFloodFill(seedPos, 5000)` relied on C++ default 300 instead of passing it explicitly.
`acceptRadius` was a separate local (300) used only for the expansion loop. Inconsistent with
`discover` which passes `maxDistance` to both `buildFromFloodFill` and the expansion filter.

**Fix:** Created `acceptMaxTiles` and `acceptRadius` variables upfront. Passed `acceptRadius`
explicitly to `buildFromFloodFill`. Stored both in session for `/hunt test` reuse.

**Status:** `[x] done`

---

## Architectural Notes (all implemented)

1. **No spatial index on ScriptTeleportRegistry** — was O(n) per lookup.

**Fix:** Added sector-based spatial index (32×32 grid buckets) to `teleport.lua`. Both
`getScriptTeleportSourcesToArea` and `getScriptTeleportsWithSourceInArea` now only check
sectors that overlap the query rectangle, turning O(n) into O(sectors × entries/sector).

**Status:** `[x] done`

2. **Monster breakdown uses rectangular bbox, not actual zone tiles** — showed monsters from
   outside the zone for L-shaped caves.

**Fix:** `getMonsterBreakdown` now accepts an optional `zone` parameter. When provided, each
spawn position is checked with `zone:contains()` before counting. The `discover` action passes
`tempZone` for precise filtering.

**Status:** `[x] done`

3. **`computeFloorchangeDestination` duplicated between C++ and Lua** — maintenance risk.

**Fix:** Exposed C++ `computeFloorchangeDestination()` as a free function in `zone.hpp`.
Added `Tile:getFloorchangeDestination()` Lua binding in `tile_functions.cpp`. Replaced the
40-line Lua duplicate with a one-liner delegating to the C++ method.

**Status:** `[x] done`

4. **`mapOnLoad` guard uses Lua local** — resets on `/reload scripts`.

**Fix:** Changed from `local _zonesBuilt` to `_G._huntZonesBuilt` so the guard survives
`/reload scripts` without re-triggering `buildPendingZones`.

**Status:** `[x] done`

5. **Zones are never destroyed** — `"hunt._discover_"` zones persist in global map.

**Fix:** Added `Zone::removeZone(name)` static method in C++ and `Zone.removeByName(name)` Lua
binding. `clearSession()` now calls `Zone.removeByName("hunt._discover_" .. guid)` to free the
temporary zone from the global registry.

**Status:** `[x] done`

6. **`generateConfig` doesn't output discovered entries/exits** — less self-documenting.

**Fix:** `generateConfig` now appends teleport entries, exit teleports, and internal teleport
count as Lua comments at the bottom of the generated config file.

**Status:** `[x] done`
