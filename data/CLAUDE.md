# Crystal Server — Lua Conventions

## Loading Order

1. `data/libs/` — loaded first (functions, tables, systems)
2. `revscriptsys.lua` — sets up EventCallback metatables
3. `data/scripts/` — loaded after libs + revscriptsys
4. `mapOnLoad` callback — fires after map is fully loaded

**Critical:** EventCallback registration MUST be in `data/scripts/`, never in `data/libs/`.

## File Patterns

- Libs: `data/libs/functions/<name>.lua` — global functions, registries
- Scripts: `data/scripts/<type>/<name>.lua` — event-driven game logic
- Hunt registrations: `data/scripts/movements/hunt_<name>.lua`

## Style

- Indent: tabs
- Local functions preferred over global when file-scoped
- Use `logger.info/warn/error` for server logging
- Player messages: `player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, ...)`
- Position format: `Position(x, y, z)` constructor

## Key APIs

- `Zone(name)` — create/get zone; `zone:buildFromFloodFill(seed, maxTiles, maxDistance)`
- `zone:expandFromFloodFill(posTable, maxTiles)` — additive expansion
- `zone:contains(pos)` — membership test; `zone:getPositions()` — all positions
- `Zone.removeByName(name)` — destroy a dynamic zone
- `Tile(pos):getFloorchangeDestination()` — C++ binding for stair/hole destination
- `Game.createInstance()`, `Game.destroyInstance(id)`, `Game.populateInstanceFromZone(id, zone)`
- `Game.getSpawnsInArea(from, to)` — returns `{name, x, y, z, spawntime}` entries

## Teleport System

- `registerScriptTeleport(src, dest)` — register for hunt discovery
- `getScriptTeleportDestination(pos)` — point lookup
- `getScriptTeleportsWithSourceInArea(from, to)` — spatial query (sector-indexed)
- `getScriptTeleportSourcesToArea(from, to)` — reverse spatial query
- `SimpleTeleport(from, dest)` — auto-registers + creates MoveEvent

## Common Pitfalls

- `HuntInstance:register()` only queues — zone build is deferred to `mapOnLoad`
- Expansion loop MUST filter with `zone:contains(tp.source)` — bbox alone includes unrelated teleports
- `session.name` persists between `/hunt discover` calls — always reset to `nil`
- `_G._huntZonesBuilt` guard (not local) for mapOnLoad — survives `/reload scripts`
