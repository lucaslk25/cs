# Instanced Hunt: Handoff & Implementation Tracking

## Visao geral

O sistema de **Instanced Hunt** permite que caves sejam instanciadas para grupos de jogadores. Um GM usa `/hunt discover` perto da entrada de uma cave, o sistema faz flood-fill para mapear todos os tiles, e depois o GM salva com `/hunt save`. No boot do servidor, o script carrega e registra a zone.

O sistema funciona para caves com **escadas/buracos** (floorchange). O trabalho atual e estender para caves acessiveis via **teleports** (item teleports do mapa e MoveEvent teleports de scripts Lua).

---

## Estado atual dos arquivos

### Preservado (uncommitted, funcional)

| Arquivo | O que tem |
|---------|-----------|
| `data/libs/functions/teleport.lua` | `getScriptTeleportSourcesToArea(fromPos, toPos)` - retorna teleports cujo **destino** esta na area (+18 linhas) |
| `data/scripts/talkactions/gm/hunt_zone_helper.lua` | Deteccao de script teleport entries no discover e accept; unified entry positions (`allEntryPositions`); auto-exit prefere exit-teleport; dedup por posicao (+101 linhas) |
| `data/scripts/movements/hunt_flimsy_lost_soul_blue_valley.lua` | Script de hunt salvo (untracked, funcional como template) |

### Revertido pelo "undo all" (precisa reimplementar)

| Arquivo | O que foi perdido |
|---------|-------------------|
| `src/game/zones/zone.cpp` | (1) BFS com **8 vizinhos** (diagonais) em vez de 4; (2) metodo `expandFromFloodFill(startPositions, maxTiles)`; (3) excecao `TILESTATE_TELEPORT` no check blocksolid |
| `src/game/zones/zone.hpp` | Declaracao de `expandFromFloodFill` |
| `src/lua/functions/core/game/zone_functions.cpp` | Binding Lua `Zone:expandFromFloodFill(positionsTable, maxTiles)` |
| `src/lua/functions/core/game/zone_functions.hpp` | Declaracao de `luaZoneExpandFromFloodFill` |
| `data/libs/functions/hunt_instance.lua` | Sistema de deferred build: `_pendingZones`, `buildPendingZones()`, `doBuildZone()` com expansion loop |
| `data/scripts/eventcallbacks/hunt_main_map_on_load.lua` | Arquivo novo - callback `mainMapOnLoad` que chama `HuntInstance.buildPendingZones()` |
| `data/libs/functions/teleport.lua` | `getScriptTeleportsWithSourceInArea(fromPos, toPos)` - retorna teleports cujo **source** esta na area |

### Nunca implementado

| Item | Descricao |
|------|-----------|
| `data/libs/functions/teleport_registry_extra.lua` | Registro centralizado de ~19 scripts upstream que nao chamam `registerScriptTeleport()` |
| Expansion loop no discover/test/accept | Loop que segue script teleports cujo source esta na zone e expande via `expandFromFloodFill` |
| Dedup de entries por destino | Um source por destino unico (evita entries duplicados como 32883 e 32884 pro mesmo dest) |
| Classificacao internal vs entry | Teleport com source dentro da zone = internal (extensao da cave), nao entry |

---

## Mudancas necessarias (em ordem de implementacao)

### 1. C++: BFS com 8 vizinhos + excecao blocksolid teleport

**Arquivo:** `src/game/zones/zone.cpp`, metodo `buildFromFloodFill`

**Estado atual (linha 182-202):**
```cpp
// Expand to 4 cardinal neighbors on same z-level
static const int dx[] = { -1, 1, 0, 0 };
static const int dy[] = { 0, 0, -1, 1 };
for (int i = 0; i < 4; i++) {
    // ...
    if (neighborTile->hasProperty(CONST_PROP_BLOCKSOLID) && !neighborTile->hasFlag(TILESTATE_FLOORCHANGE)) {
        continue;
    }
```

**Mudanca:**
```cpp
// Expand to 8 neighbors (4 cardinal + 4 diagonal) so diagonal-only tiles are included
static const int dx[] = { -1, 1, 0, 0, -1, -1, 1, 1 };
static const int dy[] = { 0, 0, -1, 1, -1, 1, -1, 1 };
for (int i = 0; i < 8; i++) {
    // ...
    if (neighborTile->hasProperty(CONST_PROP_BLOCKSOLID)
        && !neighborTile->hasFlag(TILESTATE_FLOORCHANGE)
        && !neighborTile->hasFlag(TILESTATE_TELEPORT)) {
        continue;
    }
```

**Por que:** Tiles acessiveis apenas por diagonal (dead spots) nao eram detectados com 4 vizinhos. Teleport items blocksolid (magic forcefields) precisam ser visitados pelo BFS.

### 2. C++: Metodo `expandFromFloodFill`

**Arquivo:** `src/game/zones/zone.hpp` (declaracao) + `src/game/zones/zone.cpp` (implementacao)

**Declaracao em zone.hpp:**
```cpp
uint32_t expandFromFloodFill(const std::vector<Position> &startPositions, uint32_t maxTiles);
```
(Adicionar `#include <vector>` se necessario)

**Implementacao em zone.cpp:**
- Inicializa `visited` com as `positions` existentes da zone
- Para cada startPosition: se nao esta em visited e tem tile, adiciona a queue
- BFS identico ao buildFromFloodFill (8 vizinhos, floorchange, item teleport, blocksolid+teleport exception)
- Guarda `refPos` do primeiro start position valido para o check de distancia (<200)
- Chama `refresh()` no final
- Retorna numero de tiles adicionados

### 3. C++: Binding Lua para `expandFromFloodFill`

**Arquivos:** `zone_functions.hpp` (declaracao) + `zone_functions.cpp` (implementacao + registro)

**Registro:**
```cpp
Lua::registerMethod(L, "Zone", "expandFromFloodFill", ZoneFunctions::luaZoneExpandFromFloodFill);
```

**Implementacao:**
- Recebe tabela de positions (index 2) e maxTiles (index 3)
- Itera a tabela com `lua_rawgeti` + `Lua::getPosition(L, lua_gettop(L))` (usar indice ABSOLUTO, nao relativo!)
- Chama `zone->expandFromFloodFill(positions, maxTiles)`
- Retorna `lua_pushnumber(L, added)`

**LICAO APRENDIDA - Bug critico do indice de stack:**
`Lua::getPosition(L, arg)` internamente chama `getField(L, arg, "x")` que faz push na stack. Se `arg` for relativo (-1), apos o primeiro `getField` o -1 aponta para o valor de x em vez da position table. **Sempre usar `lua_gettop(L)` para obter o indice absoluto.**

### 4. Lua: `getScriptTeleportsWithSourceInArea` em teleport.lua

**Arquivo:** `data/libs/functions/teleport.lua`

Adicionar (alem do ja existente `getScriptTeleportSourcesToArea` que filtra por dest):
```lua
function getScriptTeleportsWithSourceInArea(fromPos, toPos)
    populateFromTeleportUnique()
    local list = {}
    for _, entry in pairs(ScriptTeleportRegistry) do
        local src = entry.source
        local dest = entry.destination
        if src and dest and src.x >= fromPos.x and src.x <= toPos.x
            and src.y >= fromPos.y and src.y <= toPos.y
            and src.z >= fromPos.z and src.z <= toPos.z then
            list[#list + 1] = { source = src, dest = dest }
        end
    end
    return list
end
```

### 5. Lua: Deferred zone building em hunt_instance.lua

**Arquivo:** `data/libs/functions/hunt_instance.lua`

**Problema:** Scripts carregam ANTES do mapa. `zone:buildFromFloodFill()` no `register()` retorna 0 tiles porque `g_game().map.getTile()` retorna nullptr.

**Solucao:** `register()` apenas guarda config numa lista `_pendingZones`. Depois do mapa carregar, `buildPendingZones()` executa o flood-fill.

**Mudancas em `register()`:**
- NAO chamar `buildFromFloodFill`
- Guardar self em `HuntInstance._pendingZones`
- Retornar true

**Nova funcao `HuntInstance.buildPendingZones()`:**
- Itera `_pendingZones`
- Para cada: chama `doBuildZone(self)`
- Limpa `_pendingZones`

**Nova funcao `HuntInstance:doBuildZone()`:**
- `zone:buildFromFloodFill(caveSeed, maxCaveTiles)`
- Expansion loop (ver secao 7)
- `zone:blockFamiliars()`, `zone:setRemoveDestination(exit)`
- Registar `ZoneEvent` (afterLeave, afterEnter)
- Log de resultado

**LICAO APRENDIDA:** NAO registar o EventCallback `mainMapOnLoad` neste arquivo! O `revscriptsys.lua` que define o `__newindex` do EventCallback carrega DEPOIS de `hunt_instance.lua`. Tentar `cb.mainMapOnLoad = function()` antes do revscriptsys causa: `attempt to index local 'cb' (a userdata value)`.

### 6. Lua: EventCallback mainMapOnLoad (arquivo separado)

**Arquivo NOVO:** `data/scripts/eventcallbacks/hunt_main_map_on_load.lua`

```lua
local cb = EventCallback("HuntInstanceMainMapOnLoad", true)

function cb.mainMapOnLoad()
    HuntInstance.buildPendingZones()
end

cb:register()
```

**Por que arquivo separado:** Scripts em `data/scripts/` carregam DEPOIS dos libs E DEPOIS do revscriptsys. O EventCallback metatable ja tem o `__newindex` configurado.

### 7. Lua: Expansion loop (discover, test, accept, doBuildZone)

**Padrao do loop (aplicar em 4 locais):**
```lua
local function bboxFromPositions(positions)
    if #positions == 0 then return nil, nil end
    local minx, miny, minz = positions[1].x, positions[1].y, positions[1].z
    local maxx, maxy, maxz = minx, miny, minz
    for i = 2, #positions do
        local p = positions[i]
        if p.x < minx then minx = p.x end
        if p.y < miny then miny = p.y end
        if p.z < minz then minz = p.z end
        if p.x > maxx then maxx = p.x end
        if p.y > maxy then maxy = p.y end
        if p.z > maxz then maxz = p.z end
    end
    return Position(minx, miny, minz), Position(maxx, maxy, maxz)
end

local bboxMin, bboxMax = result.bboxMin, result.bboxMax
while bboxMin and bboxMax do
    local tps = getScriptTeleportsWithSourceInArea(bboxMin, bboxMax)
    local destsToAdd = {}
    local seen = {}
    for _, tp in ipairs(tps) do
        local d = tp.dest
        if d and zone:contains(tp.source) and not zone:contains(d) then
            local key = d.x .. ":" .. d.y .. ":" .. d.z
            if not seen[key] then
                seen[key] = true
                destsToAdd[#destsToAdd + 1] = d
            end
        end
    end
    if #destsToAdd == 0 then break end
    local added = zone:expandFromFloodFill(destsToAdd, maxTiles)
    if added == 0 then break end
    local positions = zone:getPositions()
    if type(positions) ~= "table" or #positions == 0 then break end
    bboxMin, bboxMax = bboxFromPositions(positions)
end
```

**LICAO APRENDIDA - `zone:contains(tp.source)` e CRITICO:**
Sem este check, o loop usa o bbox RETANGULAR para buscar teleports. O bbox pode cobrir areas enormes do mapa (2000x1000 tiles) contendo teleports de quests totalmente diferentes. Isso causou expansao para 20k tiles e 146 entries aleatorios. O check `zone:contains(tp.source)` garante que so teleports cujo source e efetivamente um tile da cave sao seguidos.

**Locais de aplicacao:**
1. `hunt_zone_helper.lua` - discover (apos `buildFromFloodFill`)
2. `hunt_zone_helper.lua` - test (apos `buildFromFloodFill`)
3. `hunt_zone_helper.lua` - accept (apos `buildFromFloodFill`)
4. `hunt_instance.lua` - `doBuildZone()` (apos `buildFromFloodFill`)

### 8. Lua: Dedup de entries por destino + classificacao internal

**No discover (hunt_zone_helper.lua), ao processar `getScriptTeleportSourcesToArea`:**

```lua
local destSeen = {}
for _, tp in ipairs(session.teleportEntries) do
    local dk = tp.dest.x .. ":" .. tp.dest.y .. ":" .. tp.dest.z
    destSeen[dk] = true
end
for _, tp in ipairs(scriptEntries) do
    if tempZone:contains(tp.source) then
        -- Source inside zone = internal (extensao da cave, nao entry)
        session.internalTeleports[#session.internalTeleports + 1] = {
            source = tp.source, dest = tp.dest
        }
    elseif not tempZone:contains(tp.dest) then
        -- Source outside, dest outside = skip
    else
        -- Source outside, dest inside = real entry (dedup por dest)
        local dk = tp.dest.x .. ":" .. tp.dest.y .. ":" .. tp.dest.z
        if not destSeen[dk] then
            destSeen[dk] = true
            session.teleportEntries[#session.teleportEntries + 1] = {
                source = tp.source, dest = tp.dest
            }
        end
    end
end
```

### 9. Lua: Registro centralizado de teleports (`teleport_registry_extra.lua`)

**Arquivo NOVO:** `data/libs/functions/teleport_registry_extra.lua`

Registra teleports de ~19 scripts upstream que usam MoveEvent `:position()` + `teleportTo()` mas NAO chamam `registerScriptTeleport()`. Boss teleports sao intencionalmente excluidos.

**Scripts a cobrir:**

```lua
local extraTeleports = {
    -- Feaster of Souls: slab transitions (actions_slab.lua)
    { pos = {33484, 31435, 8}, dest = {33483, 31452, 9} },
    { pos = {33481, 31452, 9}, dest = {33486, 31435, 8} },
    { pos = {33558, 31467, 9}, dest = {33573, 31467, 9} },
    { pos = {33570, 31467, 9}, dest = {33555, 31467, 9} },
    { pos = {33549, 31440, 9}, dest = {33537, 31440, 9} },
    { pos = {33539, 31440, 9}, dest = {33550, 31439, 9} },
    { pos = {33540, 31411, 9}, dest = {33528, 31410, 9} },
    { pos = {33531, 31410, 9}, dest = {33541, 31412, 9} },
    { pos = {33535, 31444, 8}, dest = {33546, 31444, 8} },
    { pos = {33544, 31444, 8}, dest = {33533, 31444, 8} },

    -- Dragolisk teleport
    { pos = {33216, 31126, 14}, dest = {33186, 31190, 7} },
    { pos = {33187, 31190, 7}, dest = {33217, 31123, 14} },

    -- ... (restantes 17 scripts - extrair coordenadas de cada)
}
```

**Carregar em `load.lua`** DEPOIS de `teleport.lua`:
```lua
dofile(CORE_DIRECTORY .. "/libs/functions/teleport.lua")
dofile(CORE_DIRECTORY .. "/libs/functions/teleport_registry_extra.lua")
```

**Boss teleports EXCLUIDOS (intencional):**
- `actions_portal_minis_feaster.lua` (Unaz, Irgix, Vok)
- `actions_portal_minis_grimvale.lua` (Bloodback, etc.)
- `actions_portal_minis_ancient_feud.lua`
- `actions_portal_minis_kilmaresh.lua`
- `movements_boss_timer.lua` (Cults of Tibia)
- `movements_boss.lua` (Killing in the Name Of)
- E outros boss scripts

**Por que bosses ficam excluidos:** Boss teleports sao MoveEvents com `:position()` que NAO criam item Teleport (sem `TILESTATE_TELEPORT`) e NAO chamam `registerScriptTeleport()`. O C++ BFS nao os ve, e a expansao Lua tambem nao. Isso e correto: salas de boss nao devem fazer parte da hunt zone.

### 10. Checks defensivos

Em todos os expansion loops, antes de chamar `bboxFromPositions(positions)`:
```lua
local positions = zone:getPositions()
if type(positions) ~= "table" or #positions == 0 then break end
```

---

## Taxonomia de teleports no Crystal Server

```
Tipo 1: Item Teleport (OTBM map)
  - Item do tipo ITEM_TYPE_TELEPORT colocado no editor de mapa
  - Tile tem TILESTATE_TELEPORT
  - C++ BFS segue automaticamente (buildFromFloodFill + expandFromFloodFill)
  - Exemplo: magic forcefields invisiveis, teleport pads

Tipo 2: Script Teleport com registerScriptTeleport
  - MoveEvent Lua que chama registerScriptTeleport()
  - Inclui SimpleTeleport() e TeleportUnique
  - Lua expansion loop segue via ScriptTeleportRegistry
  - Exemplo: actions_entrances.lua (Feaster of Souls)

Tipo 3: Script Teleport SEM registerScriptTeleport
  - MoveEvent Lua com :position() + teleportTo() mas sem registro
  - Invisivel ao sistema de hunts (C++ e Lua)
  - Fix: teleport_registry_extra.lua registra manualmente
  - Exemplo: actions_slab.lua (Feaster of Souls)

Tipo 4: Boss Teleport (EXCLUIDO intencionalmente)
  - MoveEvent Lua com :position() + teleportTo()
  - NAO registado, NAO seguido
  - Boss rooms ficam fora da hunt zone
  - Exemplo: actions_portal_minis_feaster.lua (Unaz the Mean)
```

---

## Licoes aprendidas (bugs encontrados e corrigidos)

1. **Lua stack index relativo vs absoluto:** `Lua::getPosition(L, -1)` falha porque `getField` faz push na stack. Usar `lua_gettop(L)` para indice absoluto.

2. **Ordem de carregamento libs vs revscriptsys:** EventCallback `__newindex` so esta disponivel DEPOIS de revscriptsys.lua. Registros de callback devem ir em `data/scripts/eventcallbacks/`, nao em libs.

3. **Scripts carregam antes do mapa:** `buildFromFloodFill()` em `register()` retorna 0 tiles no boot. Solucao: deferred build via `mainMapOnLoad` callback.

4. **Bbox retangular vs zone:contains():** Usar bbox para buscar teleports inclui teleports de quests distantes que por acaso caem no retangulo. Sempre filtrar com `zone:contains(tp.source)`.

5. **4 vizinhos vs 8 vizinhos:** Tiles acessiveis apenas por diagonal (dead spots, corners) nao eram incluidos na zone com BFS de 4 vizinhos.

6. **Blocksolid + Teleport:** Tiles com item teleport que sao blocksolid (magic forcefields) eram ignorados pelo BFS. Adicionar excecao como ja existe para floorchange.

7. **Overwrite de hunt salva:** Dar discover novamente e salvar com o mesmo nome sobrescreve o arquivo .lua anterior. Funciona corretamente.

---

## Ordem de implementacao recomendada

1. **C++ (requer recompile):** items 1, 2, 3 (8-neighbor BFS, expandFromFloodFill, Lua binding)
2. **Lua teleport.lua:** item 4 (getScriptTeleportsWithSourceInArea)
3. **Lua hunt_instance.lua:** item 5 (deferred build)
4. **Lua eventcallback:** item 6 (hunt_main_map_on_load.lua)
5. **Lua hunt_zone_helper.lua:** items 7, 8 (expansion loop + dedup/classification)
6. **Lua teleport_registry_extra.lua:** item 9 (registro centralizado)
7. **Lua load.lua:** adicionar dofile para teleport_registry_extra.lua
8. **Verificacao:** item 10 (checks defensivos)

---

## Checklist de teste

- [ ] Compilar C++ sem warnings
- [ ] Servidor inicia sem erros (mainMapOnLoad registra corretamente)
- [ ] Hunt registrada carrega tiles no boot (nao 0 tiles)
- [ ] `/hunt discover` perto de teleport de cave: encontra seed, tiles, entries
- [ ] Tiles diagonais incluidos (sem dead spots)
- [ ] Slab teleports (Feaster) detectados pela expansao
- [ ] Item teleports blocksolid detectados
- [ ] Boss teleports (Unaz) NAO incluidos na zone
- [ ] Entries deduplicados por destino
- [ ] Internal teleports classificados corretamente
- [ ] `/hunt test` cria instancia funcional
- [ ] Player permanece na instancia ao usar slab teleports
- [ ] Player sai da instancia ao sair da zone
- [ ] `/hunt save` gera script correto
- [ ] Servidor reinicia e hunt funciona com tiles carregados
