////////////////////////////////////////////////////////////////////////
// Crystal Server - an opensource roleplaying game
////////////////////////////////////////////////////////////////////////
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
////////////////////////////////////////////////////////////////////////

#include "lua/functions/core/game/zone_functions.hpp"

#include "game/zones/zone.hpp"
#include "game/game.hpp"
#include "lua/functions/lua_functions_loader.hpp"

void ZoneFunctions::init(lua_State* L) {
	Lua::registerSharedClass(L, "Zone", "", ZoneFunctions::luaZoneCreate);
	Lua::registerMetaMethod(L, "Zone", "__eq", ZoneFunctions::luaZoneCompare);

	Lua::registerMethod(L, "Zone", "getName", ZoneFunctions::luaZoneGetName);
	Lua::registerMethod(L, "Zone", "addArea", ZoneFunctions::luaZoneAddArea);
	Lua::registerMethod(L, "Zone", "subtractArea", ZoneFunctions::luaZoneSubtractArea);
	Lua::registerMethod(L, "Zone", "buildFromFloodFill", ZoneFunctions::luaZoneBuildFromFloodFill);
	Lua::registerMethod(L, "Zone", "contains", ZoneFunctions::luaZoneContains);
	Lua::registerMethod(L, "Zone", "getRemoveDestination", ZoneFunctions::luaZoneGetRemoveDestination);
	Lua::registerMethod(L, "Zone", "setRemoveDestination", ZoneFunctions::luaZoneSetRemoveDestination);
	Lua::registerMethod(L, "Zone", "getPositions", ZoneFunctions::luaZoneGetPositions);
	Lua::registerMethod(L, "Zone", "getCreatures", ZoneFunctions::luaZoneGetCreatures);
	Lua::registerMethod(L, "Zone", "getPlayers", ZoneFunctions::luaZoneGetPlayers);
	Lua::registerMethod(L, "Zone", "getMonsters", ZoneFunctions::luaZoneGetMonsters);
	Lua::registerMethod(L, "Zone", "getNpcs", ZoneFunctions::luaZoneGetNpcs);
	Lua::registerMethod(L, "Zone", "getItems", ZoneFunctions::luaZoneGetItems);

	Lua::registerMethod(L, "Zone", "removePlayers", ZoneFunctions::luaZoneRemovePlayers);
	Lua::registerMethod(L, "Zone", "removeMonsters", ZoneFunctions::luaZoneRemoveMonsters);
	Lua::registerMethod(L, "Zone", "removeNpcs", ZoneFunctions::luaZoneRemoveNpcs);
	Lua::registerMethod(L, "Zone", "refresh", ZoneFunctions::luaZoneRefresh);

	Lua::registerMethod(L, "Zone", "setMonsterVariant", ZoneFunctions::luaZoneSetMonsterVariant);

	// static methods
	Lua::registerMethod(L, "Zone", "getByPosition", ZoneFunctions::luaZoneGetByPosition);
	Lua::registerMethod(L, "Zone", "getByName", ZoneFunctions::luaZoneGetByName);
	Lua::registerMethod(L, "Zone", "getAll", ZoneFunctions::luaZoneGetAll);
}

// Zone
int ZoneFunctions::luaZoneCreate(lua_State* L) {
	// Zone(name)
	const auto name = Lua::getString(L, 2);
	auto zone = Zone::getZone(name);
	if (!zone) {
		zone = Zone::addZone(name);
	}
	Lua::pushUserdata<Zone>(L, zone);
	Lua::setMetatable(L, -1, "Zone");
	return 1;
}

int ZoneFunctions::luaZoneCompare(lua_State* L) {
	const auto &zone1 = Lua::getUserdataShared<Zone>(L, 1);
	const auto &zone2 = Lua::getUserdataShared<Zone>(L, 2);
	if (!zone1) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	if (!zone2) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}

	Lua::pushBoolean(L, zone1->getName() == zone2->getName());
	return 1;
}

int ZoneFunctions::luaZoneGetName(lua_State* L) {
	// Zone:getName()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	Lua::pushString(L, zone->getName());
	return 1;
}

int ZoneFunctions::luaZoneAddArea(lua_State* L) {
	// Zone:addArea(fromPos, toPos)
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto fromPos = Lua::getPosition(L, 2);
	const auto toPos = Lua::getPosition(L, 3);
	const auto area = Area(fromPos, toPos);
	zone->addArea(area);
	Lua::pushBoolean(L, true);
	return 1;
}

int ZoneFunctions::luaZoneSubtractArea(lua_State* L) {
	// Zone:subtractArea(fromPos, toPos)
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto fromPos = Lua::getPosition(L, 2);
	const auto toPos = Lua::getPosition(L, 3);
	const auto area = Area(fromPos, toPos);
	zone->subtractArea(area);
	Lua::pushBoolean(L, true);
	return 1;
}

int ZoneFunctions::luaZoneBuildFromFloodFill(lua_State* L) {
	// Zone:buildFromFloodFill(startPos[, maxTiles])
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto startPos = Lua::getPosition(L, 2);
	uint32_t maxTiles = Lua::getNumber<uint32_t>(L, 3, 5000);

	auto result = zone->buildFromFloodFill(startPos, maxTiles);

	lua_createtable(L, 0, 8);

	lua_pushnumber(L, result.tilesAdded);
	lua_setfield(L, -2, "tiles");

	lua_pushnumber(L, result.spawnCount);
	lua_setfield(L, -2, "spawns");

	// bounding box
	lua_createtable(L, 0, 3);
	lua_pushnumber(L, result.bboxMin.x);
	lua_setfield(L, -2, "x");
	lua_pushnumber(L, result.bboxMin.y);
	lua_setfield(L, -2, "y");
	lua_pushnumber(L, result.bboxMin.z);
	lua_setfield(L, -2, "z");
	lua_setfield(L, -2, "bboxMin");

	lua_createtable(L, 0, 3);
	lua_pushnumber(L, result.bboxMax.x);
	lua_setfield(L, -2, "x");
	lua_pushnumber(L, result.bboxMax.y);
	lua_setfield(L, -2, "y");
	lua_pushnumber(L, result.bboxMax.z);
	lua_setfield(L, -2, "z");
	lua_setfield(L, -2, "bboxMax");

	// zLevels array
	lua_createtable(L, static_cast<int>(result.zLevels.size()), 0);
	int idx = 1;
	for (uint8_t z : result.zLevels) {
		lua_pushnumber(L, z);
		lua_rawseti(L, -2, idx++);
	}
	lua_setfield(L, -2, "zLevels");

	// entries array of positions
	lua_createtable(L, static_cast<int>(result.entryTiles.size()), 0);
	idx = 1;
	for (const auto &entry : result.entryTiles) {
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, entry.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, entry.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, entry.z);
		lua_setfield(L, -2, "z");
		lua_rawseti(L, -2, idx++);
	}
	lua_setfield(L, -2, "entries");

	// teleportEntries: external teleports leading into the zone [{source={x,y,z}, dest={x,y,z}}]
	lua_createtable(L, static_cast<int>(result.teleportEntries.size()), 0);
	idx = 1;
	for (const auto &[src, dst] : result.teleportEntries) {
		lua_createtable(L, 0, 2);
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, src.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, src.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, src.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "source");
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, dst.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, dst.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, dst.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "dest");
		lua_rawseti(L, -2, idx++);
	}
	lua_setfield(L, -2, "teleportEntries");

	// internalTeleports: teleports within the zone [{source={x,y,z}, dest={x,y,z}}]
	lua_createtable(L, static_cast<int>(result.internalTeleports.size()), 0);
	idx = 1;
	for (const auto &[src, dst] : result.internalTeleports) {
		lua_createtable(L, 0, 2);
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, src.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, src.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, src.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "source");
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, dst.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, dst.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, dst.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "dest");
		lua_rawseti(L, -2, idx++);
	}
	lua_setfield(L, -2, "internalTeleports");

	// exitTeleports: teleports inside the zone leading outside [{source={x,y,z}, dest={x,y,z}}]
	lua_createtable(L, static_cast<int>(result.exitTeleports.size()), 0);
	idx = 1;
	for (const auto &[src, dst] : result.exitTeleports) {
		lua_createtable(L, 0, 2);
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, src.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, src.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, src.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "source");
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, dst.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, dst.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, dst.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "dest");
		lua_rawseti(L, -2, idx++);
	}
	lua_setfield(L, -2, "exitTeleports");

	return 1;
}

int ZoneFunctions::luaZoneContains(lua_State* L) {
	// Zone:contains(position)
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto pos = Lua::getPosition(L, 2);
	Lua::pushBoolean(L, zone->contains(pos));
	return 1;
}

int ZoneFunctions::luaZoneGetRemoveDestination(lua_State* L) {
	// Zone:getRemoveDestination()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		return 1;
	}
	Lua::pushPosition(L, zone->getRemoveDestination());
	return 1;
}

int ZoneFunctions::luaZoneSetRemoveDestination(lua_State* L) {
	// Zone:setRemoveDestination(pos)
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		return 1;
	}
	const auto pos = Lua::getPosition(L, 2);
	zone->setRemoveDestination(pos);
	return 1;
}

int ZoneFunctions::luaZoneGetPositions(lua_State* L) {
	// Zone:getPositions()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto positions = zone->getPositions();
	lua_createtable(L, static_cast<int>(positions.size()), 0);

	int index = 0;
	for (auto pos : positions) {
		index++;
		Lua::pushPosition(L, pos);
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneGetCreatures(lua_State* L) {
	// Zone:getCreatures()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto &creatures = zone->getCreatures();
	lua_createtable(L, static_cast<int>(creatures.size()), 0);

	int index = 0;
	for (const auto &creature : creatures) {
		index++;
		Lua::pushUserdata<Creature>(L, creature);
		Lua::setCreatureMetatable(L, -1, creature);
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneGetPlayers(lua_State* L) {
	// Zone:getPlayers()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto &players = zone->getPlayers();
	lua_createtable(L, static_cast<int>(players.size()), 0);

	int index = 0;
	for (const auto &player : players) {
		index++;
		Lua::pushUserdata<Player>(L, player);
		Lua::setMetatable(L, -1, "Player");
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneGetMonsters(lua_State* L) {
	// Zone:getMonsters()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto &monsters = zone->getMonsters();
	lua_createtable(L, static_cast<int>(monsters.size()), 0);

	int index = 0;
	for (const auto &monster : monsters) {
		index++;
		Lua::pushUserdata<Monster>(L, monster);
		Lua::setMetatable(L, -1, "Monster");
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneGetNpcs(lua_State* L) {
	// Zone:getNpcs()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto &npcs = zone->getNpcs();
	lua_createtable(L, static_cast<int>(npcs.size()), 0);

	int index = 0;
	for (const auto &npc : npcs) {
		index++;
		Lua::pushUserdata<Npc>(L, npc);
		Lua::setMetatable(L, -1, "Npc");
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneGetItems(lua_State* L) {
	// Zone:getItems()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto &items = zone->getItems();
	lua_createtable(L, static_cast<int>(items.size()), 0);

	int index = 0;
	for (const auto &item : items) {
		index++;
		Lua::pushUserdata<Item>(L, item);
		Lua::setMetatable(L, -1, "Item");
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneRemovePlayers(lua_State* L) {
	// Zone:removePlayers()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}

	zone->removePlayers();
	return 1;
}

int ZoneFunctions::luaZoneRemoveMonsters(lua_State* L) {
	// Zone:removeMonsters()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	zone->removeMonsters();
	return 1;
}

int ZoneFunctions::luaZoneRemoveNpcs(lua_State* L) {
	// Zone:removeNpcs()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	zone->removeNpcs();
	return 1;
}

int ZoneFunctions::luaZoneSetMonsterVariant(lua_State* L) {
	// Zone:setMonsterVariant(variant)
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}
	const auto variant = Lua::getString(L, 2);
	if (variant.empty()) {
		Lua::pushBoolean(L, false);
		return 1;
	}
	zone->setMonsterVariant(variant);
	Lua::pushBoolean(L, true);
	return 1;
}

int ZoneFunctions::luaZoneGetByName(lua_State* L) {
	// Zone.getByName(name)
	const auto name = Lua::getString(L, 1);
	const auto &zone = Zone::getZone(name);
	if (!zone) {
		lua_pushnil(L);
		return 1;
	}
	Lua::pushUserdata<Zone>(L, zone);
	Lua::setMetatable(L, -1, "Zone");
	return 1;
}

int ZoneFunctions::luaZoneGetByPosition(lua_State* L) {
	// Zone.getByPosition(pos)
	const auto pos = Lua::getPosition(L, 1);
	const auto &tile = g_game().map.getTile(pos);
	if (!tile) {
		lua_pushnil(L);
		return 1;
	}
	int index = 0;
	const auto &zones = tile->getZones();
	lua_createtable(L, static_cast<int>(zones.size()), 0);
	for (const auto &zone : zones) {
		index++;
		Lua::pushUserdata<Zone>(L, zone);
		Lua::setMetatable(L, -1, "Zone");
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneGetAll(lua_State* L) {
	// Zone.getAll()
	const auto &zones = Zone::getZones();
	lua_createtable(L, static_cast<int>(zones.size()), 0);
	int index = 0;
	for (const auto &zone : zones) {
		index++;
		Lua::pushUserdata<Zone>(L, zone);
		Lua::setMetatable(L, -1, "Zone");
		lua_rawseti(L, -2, index);
	}
	return 1;
}

int ZoneFunctions::luaZoneRefresh(lua_State* L) {
	// Zone:refresh()
	const auto &zone = Lua::getUserdataShared<Zone>(L, 1);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		return 1;
	}
	zone->refresh();
	return 1;
}
