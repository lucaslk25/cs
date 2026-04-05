# Crystal Server — C++ Conventions

## Build System

- CMake + vcpkg, preset `linux-debug`: `cmake --preset linux-debug && cmake --build build/linux-debug`
- Precompiled headers via `cmake_pch.hxx` — PCH warnings are normal, ignore them
- C++23 standard, GCC 14

## Naming

- Classes: `PascalCase` (`InstanceManager`, `WorldInstance`)
- Methods: `camelCase` (`buildFromFloodFill`, `getInstanceID`)
- Member vars: `camelCase` with no prefix, or `m_` for private in some classes
- Constants: `UPPER_SNAKE` (`INSTANCE_VISIBLE_TO_ALL`)
- Files: `snake_case.cpp/hpp`

## Lua Bindings

- Registration in `init()` via `Lua::registerMethod(L, "ClassName", "methodName", ...)`
- Use `Lua::getUserdataShared<T>(L, 1)` for userdata access
- Push results: `Lua::pushBoolean`, `Lua::pushPosition`, `Lua::pushString`, `lua_pushnumber`
- **Stack index pitfall:** Always use `lua_gettop(L)` for absolute indices when calling `Lua::getPosition` inside loops — relative indices (-1) shift as fields are pushed

## Zone/Instance Patterns

- `Zone::buildFromFloodFill` — 4-neighbor BFS, Chebyshev distance cap, same-Z only
- `Zone::expandFromFloodFill` — additive BFS from seed positions
- `computeFloorchangeDestination(tile)` — free function in `zone.hpp`
- `InstanceManager` — singleton via `g_instanceManager()`
- Instance ID 1 = global, 2+ = private, `UINT32_MAX` = visible to all

## Common Pitfalls

- `tile->getItems()` does NOT exist — use `tile->getItemList()` or iterate items
- `PositionHasher` not `PositionHash` for `std::unordered_set<Position>`
- Floor changes: always check both `TILESTATE_FLOORCHANGE` and `TILESTATE_FLOORCHANGE_DOWN`
