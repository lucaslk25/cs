# Crystal Server — Current Handoff

> Last updated: 2026-04-07 | Session: Wiki import command + monster matching fixes

## What Was Done This Session

### Hunt Manager monster matching fixes
- Fixed wiki disambiguation suffixes (`"Slime (Criatura)"` → matches `"Slime"`) — 21 unique patterns, 99 total occurrences
- Fixed case-insensitive matching (`"Priestess Of The Wild Sun"` → matches `"Priestess of the Wild Sun"`)
- Both fixes applied to: `computeMonsterMatch`, detail panel creature tags, match summary count
- Lua export now resolves to server's exact casing via case-insensitive lookup

### `/hunt wikimport` command (Lua)
- New command reads `WIKI_HUNTS` global table, flood-fills from seed positions, detects exits, generates hunt registration files
- **Seed walkability fix:** spiral search (radius 30) for nearest walkable tile before flood-fill
- **Duplicate seed merging:** hunts sharing same `seedPos` (e.g., Secret Library 4 sections) auto-merged into one
- **Quality gates:** skips hunts with < 50 tiles or 0 spawns
- **Warnings:** flags mega-merges (>= 15k tiles) and duplicate flood-fills (same tile+spawn counts)
- **Headless:** runs via `addEvent`, results written to `data/hunt_wikimport_results.txt`
- Supports dry run: `/hunt wikimport, dry`

### Dry run results (v2 with all fixes)
- 89 hunts processed (92 originals, 3 merged from duplicates)
- 83 would save, 6 skipped (4 too small, 2 no spawns)
- 5 warnings: 3 mega-merges (Castle Catacombs, Drefia, Netherworld), 2 duplicate overlap (Deep Hub dungeons)
- Z-levels now display correctly (was showing indices instead of actual z values)
- Secret Library found with radius 30 (7096 tiles, z=[12,13])

### `wiki_hunts_import.lua` registered in load.lua
- Was missing from `data/libs/functions/load.lua` — `WIKI_HUNTS` table wasn't loading

## Current State

- **Build:** No C++ changes — last known: compiles cleanly.
- **Server:** `/hunt wikimport, dry` tested successfully. 83 hunts ready to save.
- **Wiki data:** 92 hunts curated and exported via Hunt Manager UI.
- **Registered hunts:** 1 (Flimsy Lost Soul - Blue Valley). 83 more ready after running wikimport without dry flag.

## Work In Progress

- **Actual wikimport run** — dry run validated, needs `/hunt wikimport` (without dry) to generate all hunt_*.lua files
- **Manual review needed:** 3 mega-merge hunts (Castle Catacombs, Drefia Grim Reaper Halls, Netherworld) and Deep Hub overlap

## Next Steps (Priority Order)

1. **Run `/hunt wikimport`** (without dry) — generate 83 hunt registration files
2. **Review mega-merge hunts** — Castle Catacombs (19.8k tiles), Drefia (22.7k tiles, 10 z-levels), Netherworld (19.8k tiles, 14.7k spawns). May need manual seed adjustment or maxTiles tuning.
3. **Review Deep Hub overlap** — Crystal/Fungus/Magma all produce 7991 tiles/192 spawns. Verify they're actually distinct areas.
4. **Test 5+ hunts in-game** — `/reload scripts`, enter caves, verify instance creation, monsters, exit
5. **Gold coin entry cost** — `entryCost` + `onStepIn` validation (Phase 1)
6. **Hunt selection UI (client)** + **Instance Stamina (C++/DB)** — Phase 1 roadmap

## Known Issues / Blockers

- **Putrefactory** — seed lands in 2-tile rock pocket, real cave missed. Needs manual seed override.
- **Podzilla Stalk** — area exists (4030 tiles) but 0 spawns in world-monster.xml. New content not yet placed on map.
- **Podzilla Bottom** — 16 tiles, 0 spawns. Same issue.
- **C++ `discoverSpawnClusters` blocks main thread** — not a blocker for wiki approach
- **Pre-existing C++ warning** — `ioguild.cpp:261` unused variable

## Key Decisions Made

- **Wiki creature name normalization** — strip `" (Criatura)"` etc. at matching time in JS, and resolve to server's exact casing in Lua export. Wiki raw data kept unmodified.
- **Case-insensitive matching** — lowercase Set built alongside exact Set for lookups. Covers `"Of"` vs `"of"` wiki/server divergence.
- **Walkable radius 30** — increased from 10 to handle Secret Library and similar deep-in-rock seeds
- **Skip < 50 tiles and 0 spawns** — avoids registering dead pockets and unpopulated areas
- **Mega-merge warning threshold 15k** — flags but doesn't skip, since some large hunts are legitimate

## Files Modified This Session

- `data/scripts/talkactions/gm/hunt_zone_helper.lua` — added `/hunt wikimport` command
- `data/libs/functions/load.lua` — added `wiki_hunts_import.lua` to load list
- `tools/hunt_manager.html` — creature name normalization + case-insensitive matching
- `tools/hunt_manager.py` — creature name normalization in Lua export + case-insensitive resolution
- `docs/HANDOFF.md`, `docs/SESSION_LOG.md`, `docs/INSTANCE_SYSTEM_ROADMAP.md` — session updates
