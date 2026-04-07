# Crystal Server — Session Log

> Append-only learning journal. Each session adds an entry. Never overwrite existing entries.
> Newest entries at the bottom.

---

## 2026-02-25 — Deep Review, Architectural Improvements, Workflow System

**Summary:** Completed a senior-level code review of the entire hunt discover mechanism. Fixed 7 bugs, implemented 6 architectural improvements, and built the AI workflow system (rules, skills, living documents).

**Completed:**
- Fixed `expandFromFloodFill` stale 50-tile hardcoded distance cap
- Removed dead `border` set computation from `buildFromFloodFill`
- Added sector-based spatial index (32x32) to `ScriptTeleportRegistry`
- Added zone-filtered monster breakdown via `zone:contains()` parameter
- Exposed C++ `computeFloorchangeDestination` to Lua as `Tile:getFloorchangeDestination()`
- Changed `mapOnLoad` guard from file-local to `_G._huntZonesBuilt`
- Added `Zone::removeZone(name)` / `Zone.removeByName(name)` for zone cleanup
- Enhanced `generateConfig` with entry/exit documentation comments
- Optimized expansion loops to query teleports once per iteration
- Fixed spawn count not updated after expansion
- Fixed `accept` action missing explicit `maxDistance`
- Built complete AI workflow: coordinator rule, convention rules, skills, ARCHITECTURE.md, HANDOFF.md, SESSION_LOG.md

**Learnings:**
- `replace_all` in StrReplace can cause double-substitution if the replacement contains the search string (e.g., `computeFloorchangeDest` → `computeFloorchangeDestination` caused `computeFloorchangeDestinationination` because the replacement was applied to itself)
- `tile->getItems()` does not exist in this codebase — use `tile->getItemList()` or iterate items
- `PositionHasher` is the correct name, not `PositionHash`, for `unordered_set<Position>`
- Sector-based spatial indexing is trivial to implement in Lua and provides significant speedup for area queries
- The `mapOnLoad` event fires for raid monster spawns too (every ~2 min), not just initial boot — hence the guard

**Decisions:**
- Chose 32x32 sector size for spatial index to match game's internal SECTOR_SIZE
- Used `_G` table for mapOnLoad guard instead of a local, because locals reset on `/reload scripts`
- Exposed `computeFloorchangeDestination` as a `Tile` method rather than a `Zone` static — it operates on a tile, so `Tile` is the natural home
- Built cursor rules as the primary "coordinator" mechanism — they inject automatically into every session without explicit invocation

**Next Session Should:**
- Test all changes in-game (restart server, `/hunt discover`, verify monster breakdown, zone cleanup)
- Start registering more hunts if testing passes
- Consider beginning Phase 1 of Instance Stamina (C++ `instanceStamina` attribute)

---

## 2026-03-27 — Zone Discovery Fixes: Diagonal, Teleport Expansion, Floor Changes

**Summary:** Fixed 3 bugs found during in-game testing of the hunt discover system. Diagonal-only SQMs, far-away teleport destinations, and floor-change cross-z transitions are now all correctly discovered and instanced.

**Completed:**
- Changed BFS from 4-neighbor to 8-neighbor (cardinal + diagonal) in both `buildFromFloodFill` and `expandFromFloodFill`, matching the game engine's actual movement/pathfinding behavior
- Removed destination distance cap from expansion loop — teleports with source in zone are followed regardless of destination distance
- Added floor-change (holes/stairs) following to the Lua expansion loop — detects `TILESTATE_FLOORCHANGE` / `TILESTATE_FLOORCHANGE_DOWN` tiles, computes destinations via `Tile:getFloorchangeDestination()`, and expands from them
- Fixed exit teleport classification: now queries both `getScriptTeleportSourcesToArea` and `getScriptTeleportsWithSourceInArea`
- Expansion loop now re-queries teleports each iteration using zone's actual bbox
- Added `checkedPositions` optimization so each tile is only checked for floor changes once across iterations
- Increased iteration cap from 5 to 10 for cascading z-levels

**Learnings:**
- The game engine (Map::getPathMatching, Game::internalMoveCreature) does NOT check adjacent cardinal tiles for diagonal movement. My initial fix added a check the game doesn't have, which is why it didn't work. Always match the engine's actual behavior.
- `cmake --build` fails with "rebuilding build.ninja: subcommand failed" when the cmake snap auto-updates — the old `build.ninja` hardcodes the snap version path. Fix: `cmake --preset linux-debug` to regenerate (triggers full vcpkg rebuild).
- The Feaster of Souls `actions_entrances.lua` registers teleports via `registerScriptTeleport()` alongside MoveEvents — so they ARE in ScriptTeleportRegistry. Boss portals (`actions_portal_minis_feaster.lua`) are NOT registered (intentionally).
- Floor changes in OTBM maps can connect to enormous z=9 underground networks. Handling them in the Lua expansion loop (bounded by maxTiles) is safer than in the C++ BFS where the entire underground would be walked.

**Decisions:**
- 8-neighbor without adjacent checks matches game engine — the risk of wall-crossing is mitigated by null-tile checks and BLOCKSOLID checks on the target tile itself
- No distance cap on teleport expansion — `zone:contains(source)` is sufficient proof the teleport is part of the cave. maxTiles and wall boundaries prevent runaway
- Floor changes handled in Lua loop, not C++ — keeps C++ BFS fast and same-z-bounded; cross-z complexity lives in the more flexible Lua loop

**Next Session Should:**
- Register 10+ hunts across different level ranges using `/hunt discover` + `/hunt save`
- Implement gold coin payment system for hunt entry (entryCost field + validation)
- Begin hunt selection UI (client-side menu for players)

---

## 2026-03-29 — Batch Hunt Registration: Exp Filter, Headless Mode, Disconnect Fix

**Summary:** Extended `/hunt batch` with a monster experience filter (`expN`) to target mid/late-game caves, then fixed the recurring client disconnect problem by making the batch run headlessly — writing results to a log file and continuing regardless of player connection state.

**Completed:**
- Added `expN` argument to `/hunt batch` — checks `MonsterType(cluster.monsters[1].name):experience()` against threshold before doing any expensive flood-fill. `exp2000` keeps Dragon Lords+, skips early-game trash
- Made batch fully headless: removed `if not p then return end` abort, replaced with graceful continue; all results go to `data/hunt_batch_results.txt` via `batchLog(s, line)` which also messages the player if still online
- Player is now told at batch start: "Running headlessly — results in hunt_batch_results.txt. You can disconnect."
- Increased post-flood-fill `addEvent` delay from 100ms → 2000ms; initial delay 100ms → 3000ms
- Added `lowExp` to skip reason counters and summary output
- Dry run validated: 161 clusters → 45 qualifiers with `exp2000, 20/500, z8-15`

**Learnings:**
- `addEvent` delays are useless for preventing disconnects when the operation itself (flood-fill) blocks the main thread for 1.5-5 seconds per call. The gaps help the server breathe but a single long flood-fill can still drop the client
- The correct solution for blocking-operation UX is to detach from the player entirely and use file-based output — not to fight the blocking with delays
- `cluster.monsters` from `Game.discoverSpawnClusters` is already sorted by count descending (confirmed in C++ source) — `[1]` is always the dominant monster
- "Broken pipe: Write error" on the network thread happens a few seconds before `Player(id)` returns nil on the game thread — there's a brief window where the player object still exists after the TCP connection is gone

**Decisions:**
- Headless batch over keepalive workarounds — any approach that requires the client to stay alive during blocking operations is inherently fragile on TFS architecture
- `batchLog` as single helper for both file and player output — keeps the logic in one place, degrades gracefully

**Next Session Should:**
- Run the actual batch save: `/hunt batch, exp2000, 20/500` (without `dry`)
- Review generated files for correctness, especially the ~15 "no exit" cases (have `-- TODO: verify exit position`)
- Decide on `requireexit` flag to skip no-exit caves, or fix exit detection
- Flag "Cursed Prospector - Krailos" (19858 tiles, 14767 spawns) for manual review — suspiciously large merge

---

## 2026-04-01 — Hunt Discovery Overhaul: Catalog, Targeted Batch, Expansion Optimizations

**Summary:** Redesigned the hunt registration workflow to decouple cheap data collection from expensive flood-filling. Added `/hunt catalog` (no flood-fill, writes CSV+TXT), `ids=` targeted batch, `requireexit` filter, and optimized `expandZoneConnections` with numeric keys and incremental bbox.

**Completed:**
- `posKey(p)` helper: `p.z*4294967296 + p.y*65536 + p.x` — eliminates string concat allocation per position per iteration in expansion loop
- `expandZoneConnections` bbox now computed ONCE before loop from initial positions, then updated incrementally from `newDestinations` (eliminates O(N×10) bbox rescans for large zones)
- `/hunt catalog [z] [exp] [min]` — calls `discoverSpawnClusters` + MonsterType exp lookup + cached town query. Writes `data/hunt_catalog.txt` (sorted by exp, with tier S/A/B/C) and `data/hunt_catalog.csv`. Takes seconds regardless of cave count. Stores results in `session.discoveries`.
- `/hunt batch, ids=10 18 63 68` — flood-fills ONLY specified cluster IDs. If catalog was run first, reuses cached discoveries (skips discoverSpawnClusters). Skipped IDs use 10ms addEvent (negligible overhead).
- `/hunt batch, requireexit` — skips clusters where exit detection returned a best-guess (exitIsBestGuess=true). Reports as "no exit" in summary. Lets user batch-save only the clean caves.

**Learnings:**
- `zone.positions` is `std::unordered_set<Position>` (no insertion order). Can't do index-based "new positions" tracking from Lua without C++ changes. The `checkedPositions` guard is still needed for floor-change detection.
- `getPositions()` copies from unordered_set into a vector each call — O(N) allocation. For large zones (10k+ tiles) over 10 iterations, this is ~100k Position→Lua table conversions. Not the primary bottleneck (that's the BFS itself) but meaningful for large zones.
- The main speedup is architectural (catalog-first, targeted batch), not micro-optimization. Avoid the mistake of optimizing the engine when the real win is eliminating work entirely.
- Town cache: `getNearestTownName()` was calling `Game.getTowns()` on every cluster (O(N×towns) per catalog). Fixed with local cache built once per command invocation.

**Decisions:**
- Numeric posKey over string key: `z*4294967296 + y*65536 + x` is safe for OT coords (x/y ≤ 65535, z ≤ 15), avoids string GC
- `requireexit` as a filter flag rather than trying to fix exit detection — cleaner boundary between "auto-detected clean caves" and "manual review cases"
- Catalog sorts by dominant exp descending — highest-value caves appear first for quick scanning

**Next Session Should:**
- Test `/hunt catalog, z8-15, exp2000, 20` in-game (after `/reload scripts`)
- Review `data/hunt_catalog.txt` output, pick IDs for batch
- Run `/hunt batch, dry, ids=<picked>, 20/500` to verify
- Run `/hunt batch, ids=<picked>, requireexit, 20/500` for actual save
- Handle the ~15 "no exit" clusters manually (accept + set exit + save)

---

## 2026-04-05 — Session wrap-up

**Summary:** Session closed; handoff and roadmap refreshed after hunt discovery workflow changes (`/hunt catalog`, targeted batch, `requireexit`, expansion loop tweaks).

**Completed:**
- `docs/HANDOFF.md` updated for next-session start (2026-04-05)
- `docs/INSTANCE_SYSTEM_ROADMAP.md` — Phase 0.5 checkbox for bulk triage tooling; last-updated date

**Learnings:**
- No new runtime findings this wrap-up; follow prior 2026-04-01 log entry for technical notes.

**Next Session Should:**
- `/reload scripts`, smoke-test `/hunt catalog`, then targeted batch as in 2026-04-01 entry above.

---

## 2026-04-06 — Wiki Hunt Import Pipeline + Management UI

**Summary:** Built a complete pipeline for importing hunting place data from TibiaWiki BR into the server. Includes a Python scraper, local web management UI with auto-classification and server monster validation, and direct Lua export. Also fixed `/hunt catalog` disconnect by making it headless.

**Completed:**
- Fixed `/hunt catalog` — made headless with `addEvent` + `playerId` capture, survives client disconnect during C++ `discoverSpawnClusters` blocking phase
- Built `tools/scrape_wiki_hunts.py` — scrapes 514 hunt pages from tibiawiki.com.br MediaWiki API, parses `Infobox_Hunts` template (name, city, coords, level, difficulty, exp/loot ratings, creatures, rare items, facilities). Creature lists fetched via `Category:Criaturas_de_{name}`.
- Built `tools/hunt_manager.py` — local HTTP server (port 8099) that auto-loads wiki JSON + scans 1693 server monster names from `data-crystal/monster/` and `data-global/monster/` Lua files + restores saved curation state
- Built `tools/hunt_manager.html` — management UI with: auto-classification (skip reasons: surface/low_level/tutorial/no_coords/no_creatures/no_monsters_on_server), monster match % bars, smart recommendation panel, filters, bulk actions, keyboard shortcuts, direct server-side save/export
- Built `tools/HUNT_MANAGER_USAGE.md` — full documentation

**Learnings:**
- tibiawiki.com.br `Infobox_Hunts` template has a `mapa` field with direct game coordinates (`33872,31709,14:1` = x,y,z:zoom). 99.4% of hunt pages have this. These map directly to `Position(x,y,z)` — perfect flood-fill seeds.
- BR wiki has 994 pages in `Category:Locais de Caça` (514 after dedup/pagination), EN wiki (tibia.fandom.com) has 450. BR wiki is richer for our needs.
- `tibiawiki.dev` REST API exists (parses EN wiki into JSON) but has less data than BR wiki's native MediaWiki API.
- MediaWiki batch API (`action=query&prop=revisions&titles=Page1|Page2|...`) fetches up to 50 pages per call — much faster than individual `action=parse` calls.
- Monster names in server Lua files use `Game.createMonsterType("Name")` — simple regex extraction works for building the validation set.
- The mega-merge problem in `discoverSpawnClusters` (Yalahar underground, Rookgaard, etc.) is completely bypassed by the wiki-first approach — each hunt has its own seed coordinate, no cluster merging needed.
- `addEvent` after a blocking C++ call gives the game loop one tick to process pending network I/O, but can't prevent disconnect during the C++ call itself. True fix would require async/chunked C++ processing.

**Decisions:**
- Wiki-first over spawn-clustering: wiki provides curated, human-verified hunt boundaries with all metadata. Spawn clustering kept as fallback for custom content only.
- BR wiki as primary source: has `mapa` field with direct game coords, more pages, richer metadata (difficulty, facility flags). EN wiki / tibiawiki.dev as secondary reference only.
- Local HTTP server over static HTML: enables auto-loading data, server-side file writes (no download dialogs), and monster scanning from project files.
- Auto-classify with tagged reasons: transparent skip decisions (surface, low_level, etc.) that can be overridden manually. Manual overrides preserved across re-classification.
- Surface hunts (z<=7) auto-skipped: most are entrances not caves, but tagged with reason so user can override if needed.

**Next Session Should:**
- Launch `python3 tools/hunt_manager.py`, curate hunts (review auto-classifications, adjust as needed)
- Export Lua table of approved hunts
- Build `/hunt wikimport` Lua command that reads `WIKI_HUNTS`, flood-fills from `seedPos`, validates creatures, registers hunts
- Test end-to-end: wiki import → flood-fill → instance creation → walk through

---

## 2026-04-07 — Wiki Import Command + Monster Matching Fixes

**Summary:** Fixed creature name matching in Hunt Manager (disambiguation suffixes + case sensitivity), built `/hunt wikimport` command for batch registration from wiki data, validated with dry run (83/89 hunts pass).

**Completed:**
- Fixed Hunt Manager monster matching: strip wiki disambiguation suffixes like `"Slime (Criatura)"` → `"Slime"` (21 patterns, 99 occurrences)
- Fixed case-insensitive matching: `"Priestess Of The Wild Sun"` → matches `"Priestess of the Wild Sun"`
- Lua export resolves to server's exact monster name casing
- Built `/hunt wikimport[, dry]` command: reads WIKI_HUNTS, merges duplicate seeds, finds walkable tiles (radius 30), flood-fills, detects exits, generates hunt_*.lua files
- Added quality gates: skip < 50 tiles, skip 0 spawns, warn mega-merges (>= 15k), warn duplicate flood-fills
- Fixed z-level display bug: `ipairs` vs `pairs` on already-sorted list (was showing indices 1,2,3 instead of actual z values)
- Added `wiki_hunts_import.lua` to `data/libs/functions/load.lua` (was missing, WIKI_HUNTS wasn't loading)
- Curated 92 hunts in Hunt Manager UI and exported Lua table

**Learnings:**
- `computeZoneStats` returns `zLevels` as a sorted list `{8,9,10}`, not a set. Using `pairs()` on it yields indices (1,2,3) not values. Always check return type before iterating.
- Wiki disambiguation suffixes are common in BR wiki: `(Criatura)`, `(Anti-Botter)`, `(Nostalgia)`, color variants like `(Amarelo)`. 20 of 21 base names exist on server.
- Wiki title-cases prepositions (`"Of"`, `"The"`) while server uses lowercase (`"of"`, `"the"`). Case-insensitive matching is essential.
- `findNearestWalkable` with small radius can find dead 2-tile pockets in rocks (Putrefactory). Radius 30 needed for Secret Library where seed is deep in unwalkable area.
- `data/libs/functions/load.lua` must explicitly list every file — new Lua libs don't auto-load.
- Podzilla area (level 600) has monster type definitions but zero spawns in world-monster.xml — very new content not yet placed on map.

**Decisions:**
- Normalize at matching time, keep wiki raw data unmodified — downstream consumers can apply their own normalization
- Radius 30 for walkable search — handles worst case (Secret Library) without being too slow (30x30 = 3600 tiles max)
- Skip thresholds: < 50 tiles (dead pockets), 0 spawns (unpopulated areas). Warn but don't skip mega-merges since some large hunts are legitimate.
- Duplicate detection via tile+spawn signature — simple heuristic that caught Deep Hub overlap

**Next Session Should:**
- Run `/hunt wikimport` (without dry) to generate all 83 hunt files
- Review mega-merge hunts manually (Castle Catacombs, Drefia, Netherworld)
- Test 5+ hunts in-game: `/reload scripts`, enter, verify instance + monsters + exit
- Begin Phase 1 if hunts are stable (entry cost, hunt selection UI, instance stamina)
