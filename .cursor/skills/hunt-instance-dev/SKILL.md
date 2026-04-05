---
name: hunt-instance-dev
description: >-
  Development workflow for Crystal Server's instanced hunt system. Covers hunt
  discovery (flood-fill, teleport expansion), instance lifecycle, zone management,
  GM commands, and testing procedures. Use when working on hunt instances, /hunt
  commands, zone building, teleport registry, or instance manager code.
---

# Hunt Instance Development

## Architecture Quick Reference

### Boot Sequence
```
load.lua → hunt_instance.lua (HuntInstance class loaded)
         → teleport.lua (ScriptTeleportRegistry initialized)
         → teleport_registry_extra.lua (manual registrations)
revscriptsys.lua → EventCallback metatables ready
data/scripts/movements/hunt_*.lua → HuntInstance:register() → _pendingZones
data/scripts/eventcallbacks/hunt_main_map_on_load.lua → mapOnLoad fires
  → HuntInstance.buildPendingZones() → doBuildZone() for each pending hunt
```

### GM Discovery Workflow (`/hunt`)
```
/hunt discover    → flood-fill from nearby entry, expand via teleports
/hunt name, X     → set custom name
/hunt exit        → set exit position
/hunt goto, X     → teleport to entries/exit/seed for validation
/hunt status      → show current session
/hunt test        → create a real instance and enter it
/hunt print       → show generated Lua config
/hunt save        → write to data/scripts/movements/hunt_<name>.lua
/hunt clear       → discard session (destroys temp zone)
/hunt scan        → grid-based cluster discovery
/hunt list        → show scan results
/hunt accept, N   → accept cluster N from scan
```

## Key Files

| File | Role | Lines |
|------|------|-------|
| `data/libs/functions/hunt_instance.lua` | Core HuntInstance class, zone building, instance lifecycle | ~476 |
| `data/scripts/talkactions/gm/hunt_zone_helper.lua` | `/hunt` GM command, discovery, testing, saving | ~1138 |
| `data/libs/functions/teleport.lua` | ScriptTeleportRegistry with spatial index | ~153 |
| `data/libs/functions/teleport_registry_extra.lua` | Manual registrations for scripts that skip registerScriptTeleport | ~26 |
| `src/game/zones/zone.cpp` | BFS flood-fill, expansion, floor-change logic | ~600 |
| `src/game/instances/instance_manager.cpp` | Instance creation, population, player movement | ~300 |

## Development Checklist

When modifying the hunt system:

- [ ] C++ changes: rebuild and verify no errors
- [ ] Lua changes: restart server or `/reload scripts`
- [ ] Test `/hunt discover` near a known cave entrance
- [ ] Verify tile count is reasonable (not 10k+ unless expected)
- [ ] Verify auto-name matches expected monster/town
- [ ] Check teleport entries make sense (not from unrelated quests)
- [ ] Test `/hunt test` — enter instance, verify monsters spawn
- [ ] Test `/hunt save` — verify generated file is correct
- [ ] Test server restart — verify hunt loads from saved file

## Critical Pitfalls

1. **BFS over-expansion:** Without `maxDistance` cap, BFS traverses entire underground networks. Always pass explicit distance.
2. **Bbox teleport leak:** Using rectangular bbox for teleport queries pulls in unrelated quests. Always filter with `zone:contains(tp.source)`.
3. **Session state persistence:** `session.name` and other fields persist between `/hunt discover` calls. Reset at start.
4. **Loading order:** EventCallbacks MUST be in `data/scripts/`, not `data/libs/`. Libs load before revscriptsys.
5. **Map not loaded:** `buildFromFloodFill` returns 0 tiles if called before map load. Use deferred build via `_pendingZones`.
6. **Stack indices:** In C++ Lua bindings, use `lua_gettop(L)` for absolute position indices, not relative `-1`.
7. **Floor-change pairs:** Always check both `TILESTATE_FLOORCHANGE` and `TILESTATE_FLOORCHANGE_DOWN`.
8. **PositionHasher:** C++ uses `PositionHasher`, not `PositionHash`.

## Adding a New Hunt

1. Stand next to the cave entrance in-game
2. `/hunt discover` — system finds entry, flood-fills, expands
3. `/hunt name, Monster Name - Location` — set proper name
4. `/hunt goto, entries` — verify entry positions make sense
5. `/hunt goto, exit` — verify exit position
6. `/hunt test` — enter instance, check monsters, use teleports
7. `/hunt save` — generates `data/scripts/movements/hunt_<name>.lua`
8. Restart server to verify it loads correctly
