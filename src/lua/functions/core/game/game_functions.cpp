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

#include "lua/functions/core/game/game_functions.hpp"

#include "core.hpp"
#include "creatures/monsters/monster.hpp"
#include "creatures/monsters/monsters.hpp"
#include "creatures/npcs/npc.hpp"
#include "creatures/players/achievement/player_achievement.hpp"
#include "creatures/players/player.hpp"
#include "game/functions/game_reload.hpp"
#include "game/game.hpp"
#include "game/instances/instance_manager.hpp"
#include "game/scheduling/dispatcher.hpp"
#include "game/zones/zone.hpp"
#include "io/io_bosstiary.hpp"
#include "io/iobestiary.hpp"
#include "items/item.hpp"
#include "lua/callbacks/event_callback.hpp"
#include "lua/callbacks/events_callbacks.hpp"
#include "lua/creature/events.hpp"
#include "lua/creature/talkaction.hpp"
#include "lua/functions/creatures/npc/npc_type_functions.hpp"
#include "lua/functions/events/event_callback_functions.hpp"
#include "lua/scripts/lua_environment.hpp"
#include "map/spectators.hpp"
#include "map/mapcache.hpp"
#include "items/tile.hpp"
#include "game/movement/teleport.hpp"
#include "lua/functions/lua_functions_loader.hpp"

void GameFunctions::init(lua_State* L) {
	Lua::registerTable(L, "Game");

	Lua::registerMethod(L, "Game", "createNpcType", GameFunctions::luaGameCreateNpcType);
	Lua::registerMethod(L, "Game", "createMonsterType", GameFunctions::luaGameCreateMonsterType);

	Lua::registerMethod(L, "Game", "getSpectators", GameFunctions::luaGameGetSpectators);

	Lua::registerMethod(L, "Game", "getBoostedCreature", GameFunctions::luaGameGetBoostedCreature);
	Lua::registerMethod(L, "Game", "getBestiaryList", GameFunctions::luaGameGetBestiaryList);

	Lua::registerMethod(L, "Game", "getPlayers", GameFunctions::luaGameGetPlayers);
	Lua::registerMethod(L, "Game", "loadMap", GameFunctions::luaGameLoadMap);
	Lua::registerMethod(L, "Game", "loadMapChunk", GameFunctions::luaGameloadMapChunk);

	Lua::registerMethod(L, "Game", "getExperienceForLevel", GameFunctions::luaGameGetExperienceForLevel);
	Lua::registerMethod(L, "Game", "getMonsterCount", GameFunctions::luaGameGetMonsterCount);
	Lua::registerMethod(L, "Game", "getPlayerCount", GameFunctions::luaGameGetPlayerCount);
	Lua::registerMethod(L, "Game", "getNpcCount", GameFunctions::luaGameGetNpcCount);
	Lua::registerMethod(L, "Game", "getMonsterTypes", GameFunctions::luaGameGetMonsterTypes);

	Lua::registerMethod(L, "Game", "getTowns", GameFunctions::luaGameGetTowns);
	Lua::registerMethod(L, "Game", "getHouses", GameFunctions::luaGameGetHouses);

	Lua::registerMethod(L, "Game", "getGameState", GameFunctions::luaGameGetGameState);
	Lua::registerMethod(L, "Game", "setGameState", GameFunctions::luaGameSetGameState);

	Lua::registerMethod(L, "Game", "getWorldType", GameFunctions::luaGameGetWorldType);
	Lua::registerMethod(L, "Game", "setWorldType", GameFunctions::luaGameSetWorldType);

	Lua::registerMethod(L, "Game", "getReturnMessage", GameFunctions::luaGameGetReturnMessage);

	Lua::registerMethod(L, "Game", "createItem", GameFunctions::luaGameCreateItem);
	Lua::registerMethod(L, "Game", "createContainer", GameFunctions::luaGameCreateContainer);
	Lua::registerMethod(L, "Game", "createMonster", GameFunctions::luaGameCreateMonster);
	Lua::registerMethod(L, "Game", "createSoulPitMonster", GameFunctions::luaGameCreateSoulPitMonster);
	Lua::registerMethod(L, "Game", "createNpc", GameFunctions::luaGameCreateNpc);
	Lua::registerMethod(L, "Game", "generateNpc", GameFunctions::luaGameGenerateNpc);
	Lua::registerMethod(L, "Game", "createTile", GameFunctions::luaGameCreateTile);
	Lua::registerMethod(L, "Game", "createBestiaryCharm", GameFunctions::luaGameCreateBestiaryCharm);

	Lua::registerMethod(L, "Game", "createItemClassification", GameFunctions::luaGameCreateItemClassification);

	Lua::registerMethod(L, "Game", "getBestiaryCharm", GameFunctions::luaGameGetBestiaryCharm);

	Lua::registerMethod(L, "Game", "startRaid", GameFunctions::luaGameStartRaid);

	Lua::registerMethod(L, "Game", "getClientVersion", GameFunctions::luaGameGetClientVersion);

	Lua::registerMethod(L, "Game", "reload", GameFunctions::luaGameReload);

	Lua::registerMethod(L, "Game", "hasDistanceEffect", GameFunctions::luaGameHasDistanceEffect);
	Lua::registerMethod(L, "Game", "hasEffect", GameFunctions::luaGameHasEffect);
	Lua::registerMethod(L, "Game", "getOfflinePlayer", GameFunctions::luaGameGetOfflinePlayer);
	Lua::registerMethod(L, "Game", "getNormalizedPlayerName", GameFunctions::luaGameGetNormalizedPlayerName);
	Lua::registerMethod(L, "Game", "getNormalizedGuildName", GameFunctions::luaGameGetNormalizedGuildName);

	Lua::registerMethod(L, "Game", "addInfluencedMonster", GameFunctions::luaGameAddInfluencedMonster);
	Lua::registerMethod(L, "Game", "removeInfluencedMonster", GameFunctions::luaGameRemoveInfluencedMonster);
	Lua::registerMethod(L, "Game", "getInfluencedMonsters", GameFunctions::luaGameGetInfluencedMonsters);
	Lua::registerMethod(L, "Game", "makeFiendishMonster", GameFunctions::luaGameMakeFiendishMonster);
	Lua::registerMethod(L, "Game", "removeFiendishMonster", GameFunctions::luaGameRemoveFiendishMonster);
	Lua::registerMethod(L, "Game", "getFiendishMonsters", GameFunctions::luaGameGetFiendishMonsters);
	Lua::registerMethod(L, "Game", "getBoostedBoss", GameFunctions::luaGameGetBoostedBoss);

	Lua::registerMethod(L, "Game", "getLadderIds", GameFunctions::luaGameGetLadderIds);
	Lua::registerMethod(L, "Game", "getDummies", GameFunctions::luaGameGetDummies);

	Lua::registerMethod(L, "Game", "getTalkActions", GameFunctions::luaGameGetTalkActions);
	Lua::registerMethod(L, "Game", "getEventCallbacks", GameFunctions::luaGameGetEventCallbacks);

	Lua::registerMethod(L, "Game", "registerAchievement", GameFunctions::luaGameRegisterAchievement);
	Lua::registerMethod(L, "Game", "getAchievementInfoById", GameFunctions::luaGameGetAchievementInfoById);
	Lua::registerMethod(L, "Game", "getAchievementInfoByName", GameFunctions::luaGameGetAchievementInfoByName);
	Lua::registerMethod(L, "Game", "getSecretAchievements", GameFunctions::luaGameGetSecretAchievements);
	Lua::registerMethod(L, "Game", "getPublicAchievements", GameFunctions::luaGameGetPublicAchievements);
	Lua::registerMethod(L, "Game", "getAchievements", GameFunctions::luaGameGetAchievements);

	Lua::registerMethod(L, "Game", "getSoulCoreItems", GameFunctions::luaGameGetSoulCoreItems);
	Lua::registerMethod(L, "Game", "getMonstersByRace", GameFunctions::luaGameGetMonstersByRace);
	Lua::registerMethod(L, "Game", "getMonstersByBestiaryStars", GameFunctions::luaGameGetMonstersByBestiaryStars);
	Lua::registerMethod(L, "Game", "getTitleByName", GameFunctions::luaGameGetTitleByName);

	Lua::registerMethod(L, "Game", "getHouseCountByAccount", GameFunctions::luaHouseGetHouseCountByAccount);

	Lua::registerMethod(L, "Game", "setGuildMotd", GameFunctions::luaGameSetGuildMotd);

	// Guild management functions
	Lua::registerMethod(L, "Game", "disbandGuild", GameFunctions::luaGameDisbandGuild);
	Lua::registerMethod(L, "Game", "invitePlayerToGuild", GameFunctions::luaGameInvitePlayerToGuild);
	Lua::registerMethod(L, "Game", "removePlayerFromGuild", GameFunctions::luaGameRemovePlayerFromGuild);
	Lua::registerMethod(L, "Game", "promotePlayer", GameFunctions::luaGamePromotePlayer);
	Lua::registerMethod(L, "Game", "demotePlayer", GameFunctions::luaGameDemotePlayer);
	Lua::registerMethod(L, "Game", "passLeadership", GameFunctions::luaGamePassLeadership);
	Lua::registerMethod(L, "Game", "setPlayerGuildNick", GameFunctions::luaGameSetPlayerGuildNick);
	Lua::registerMethod(L, "Game", "setRankName", GameFunctions::luaGameSetRankName);
	Lua::registerMethod(L, "Game", "createGuild", GameFunctions::luaGameCreateGuild);
	Lua::registerMethod(L, "Game", "joinGuild", GameFunctions::luaGameJoinGuild);

	// Instance System
	Lua::registerMethod(L, "Game", "createInstance", GameFunctions::luaGameCreateInstance);
	Lua::registerMethod(L, "Game", "destroyInstance", GameFunctions::luaGameDestroyInstance);
	Lua::registerMethod(L, "Game", "createInstanceMonster", GameFunctions::luaGameCreateInstanceMonster);
	Lua::registerMethod(L, "Game", "populateInstanceFromMap", GameFunctions::luaGamePopulateInstanceFromMap);
	Lua::registerMethod(L, "Game", "populateInstanceFromZone", GameFunctions::luaGamePopulateInstanceFromZone);
	Lua::registerMethod(L, "Game", "trackInstancePlayer", GameFunctions::luaGameTrackInstancePlayer);
	Lua::registerMethod(L, "Game", "untrackInstancePlayer", GameFunctions::luaGameUntrackInstancePlayer);
	Lua::registerMethod(L, "Game", "findInstanceByPlayerGuid", GameFunctions::luaGameFindInstanceByPlayerGuid);

	// Spawn Query System
	Lua::registerMethod(L, "Game", "getSpawnsInArea", GameFunctions::luaGameGetSpawnsInArea);
	Lua::registerMethod(L, "Game", "discoverSpawnClusters", GameFunctions::luaGameDiscoverSpawnClusters);

	// Teleport Query System
	Lua::registerMethod(L, "Game", "findTeleportsToArea", GameFunctions::luaGameFindTeleportsToArea);
}

// Game
int GameFunctions::luaGameCreateMonsterType(lua_State* L) {
	// Game.createMonsterType(name[, variant = ""[, alternateName = ""]])
	if (Lua::isString(L, 1)) {
		const auto name = Lua::getString(L, 1);
		std::string uniqueName = name;
		auto variant = Lua::getString(L, 2, "");
		const auto alternateName = Lua::getString(L, 3, "");
		std::set<std::string> names;

		// if variant starts with !, then it's the only variant for this monster, so we register it with both names
		if (variant.starts_with("!")) {
			names.insert(name);
			variant = variant.substr(1);
		}
		if (!variant.empty()) {
			uniqueName = variant + "|" + name;
		}
		names.insert(uniqueName);

		if (!alternateName.empty()) {
			names.insert(alternateName);
		}

		for (const auto &checkName : names) {
			if (g_monsters().getMonsterType(checkName, true)) {
				lua_pushnil(L);
				lua_pushstring(L, fmt::format("The monster with name {} already registered", checkName).c_str());
				return 2;
			}
		}

		const auto monsterType = std::make_shared<MonsterType>(name);
		if (!monsterType) {
			lua_pushnil(L);
			lua_pushstring(L, "MonsterType is nullptr");
			return 2;
		}

		monsterType->name = name;
		if (!alternateName.empty()) {
			monsterType->name = alternateName;
		}

		monsterType->variantName = variant;
		monsterType->nameDescription = "a " + name;

		for (const auto &registerName : names) {
			if (!g_monsters().tryAddMonsterType(registerName, monsterType)) {
				lua_pushnil(L);
				lua_pushstring(L, fmt::format("The monster with name {} already registered", registerName).c_str());
				return 2;
			}
		}

		Lua::pushUserdata<MonsterType>(L, monsterType);
		Lua::setMetatable(L, -1, "MonsterType");
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameCreateNpcType(lua_State* L) {
	return NpcTypeFunctions::luaNpcTypeCreate(L);
}

int GameFunctions::luaGameGetSpectators(lua_State* L) {
	// Game.getSpectators(position[, multifloor = false[, onlyPlayer = false[, minRangeX = 0[, maxRangeX = 0[, minRangeY = 0[, maxRangeY = 0]]]]]])
	const Position &position = Lua::getPosition(L, 1);
	const bool multifloor = Lua::getBoolean(L, 2, false);
	const bool onlyPlayers = Lua::getBoolean(L, 3, false);
	const auto minRangeX = Lua::getNumber<int32_t>(L, 4, 0);
	const auto maxRangeX = Lua::getNumber<int32_t>(L, 5, 0);
	const auto minRangeY = Lua::getNumber<int32_t>(L, 6, 0);
	const auto maxRangeY = Lua::getNumber<int32_t>(L, 7, 0);

	Spectators spectators;

	if (onlyPlayers) {
		spectators.find<Player>(position, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY);
	} else {
		spectators.find<Creature>(position, multifloor, minRangeX, maxRangeX, minRangeY, maxRangeY);
	}

	lua_createtable(L, spectators.size(), 0);

	int index = 0;
	for (const auto &creature : spectators) {
		Lua::pushUserdata<Creature>(L, creature);
		Lua::setCreatureMetatable(L, -1, creature);
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetBoostedCreature(lua_State* L) {
	// Game.getBoostedCreature()
	Lua::pushString(L, g_game().getBoostedMonsterName());
	return 1;
}

int GameFunctions::luaGameGetBestiaryList(lua_State* L) {
	// Game.getBestiaryList([bool[string or BestiaryType_t]])
	lua_newtable(L);
	int index = 0;
	const bool name = Lua::getBoolean(L, 2, false);

	if (lua_gettop(L) <= 2) {
		const std::map<uint16_t, std::string> &mtype_list = g_game().getBestiaryList();
		for (const auto &ita : mtype_list) {
			if (name) {
				Lua::pushString(L, ita.second);
			} else {
				lua_pushnumber(L, ita.first);
			}
			lua_rawseti(L, -2, ++index);
		}
	} else {
		if (Lua::isNumber(L, 2)) {
			const std::map<uint16_t, std::string> tmplist = g_iobestiary().findRaceByName("CRYSTAL", false, Lua::getNumber<BestiaryType_t>(L, 2));
			for (const auto &itb : tmplist) {
				if (name) {
					Lua::pushString(L, itb.second);
				} else {
					lua_pushnumber(L, itb.first);
				}
				lua_rawseti(L, -2, ++index);
			}
		} else {
			const std::map<uint16_t, std::string> tmplist = g_iobestiary().findRaceByName(Lua::getString(L, 2));
			for (const auto &itc : tmplist) {
				if (name) {
					Lua::pushString(L, itc.second);
				} else {
					lua_pushnumber(L, itc.first);
				}
				lua_rawseti(L, -2, ++index);
			}
		}
	}
	return 1;
}

int GameFunctions::luaGameCreateSoulPitMonster(lua_State* L) {
	// Game.createSoulPitMonster(monsterName, position, [stack = 1, [, extended = false[, force = false[, master = nil]]]])
	const auto &monster = Monster::createMonster(Lua::getString(L, 1));
	if (!monster) {
		lua_pushnil(L);
		return 1;
	}

	bool isSummon = false;
	if (lua_gettop(L) >= 6) {
		if (const auto &master = Lua::getCreature(L, 6)) {
			monster->setMaster(master, true);
			isSummon = true;
		}
	}

	const Position &position = Lua::getPosition(L, 2);
	const uint8_t stack = Lua::getNumber<uint8_t>(L, 3, 1);
	const bool extended = Lua::getBoolean(L, 4, false);
	const bool force = Lua::getBoolean(L, 5, false);
	if (g_game().placeCreature(monster, position, extended, force)) {
		monster->setSoulPitStack(stack);
		monster->onSpawn(position);

		Lua::pushUserdata<Monster>(L, monster);
		Lua::setMetatable(L, -1, "Monster");
	} else {
		if (isSummon) {
			monster->setMaster(nullptr);
		}
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameGetSoulCoreItems(lua_State* L) {
	// Game.getSoulCoreItems()
	std::vector<const ItemType*> soulCoreItems;
	for (const auto &itemType : Item::items.getItems()) {
		if (itemType.m_primaryType == "SoulCores" || itemType.type == ITEM_TYPE_SOULCORES) {
			soulCoreItems.emplace_back(&itemType);
		}
	}
	lua_createtable(L, soulCoreItems.size(), 0);
	int index = 0;
	for (const auto* itemType : soulCoreItems) {
		Lua::pushUserdata<const ItemType>(L, itemType);
		Lua::setMetatable(L, -1, "ItemType");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetMonstersByRace(lua_State* L) {
	// Game.getMonstersByRace(race)
	const BestiaryType_t race = Lua::getNumber<BestiaryType_t>(L, 1);
	const auto monstersByRace = g_monsters().getMonstersByRace(race);
	lua_createtable(L, monstersByRace.size(), 0);
	int index = 0;
	for (const auto &monsterType : monstersByRace) {
		Lua::pushUserdata<MonsterType>(L, monsterType);
		Lua::setMetatable(L, -1, "MonsterType");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetMonstersByBestiaryStars(lua_State* L) {
	// Game.getMonstersByBestiaryStars(stars)
	const uint8_t stars = Lua::getNumber<uint8_t>(L, 1);
	const auto monstersByStars = g_monsters().getMonstersByBestiaryStars(stars);
	lua_createtable(L, monstersByStars.size(), 0);
	int index = 0;
	for (const auto &monsterType : monstersByStars) {
		Lua::pushUserdata<MonsterType>(L, monsterType);
		Lua::setMetatable(L, -1, "MonsterType");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetPlayers(lua_State* L) {
	// Game.getPlayers()
	lua_createtable(L, g_game().getPlayersOnline(), 0);

	int index = 0;
	for (const auto &playerEntry : g_game().getPlayers()) {
		Lua::pushUserdata<Player>(L, playerEntry.second);
		Lua::setMetatable(L, -1, "Player");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameLoadMap(lua_State* L) {
	// Game.loadMap(path)
	const std::string &path = Lua::getString(L, 1);
	g_dispatcher().addEvent([path]() { g_game().loadMap(path); }, __FUNCTION__);
	return 0;
}

int GameFunctions::luaGameloadMapChunk(lua_State* L) {
	// Game.loadMapChunk(path, position, remove)
	const std::string &path = Lua::getString(L, 1);
	const Position &position = Lua::getPosition(L, 2);
	g_dispatcher().addEvent([path, position]() { g_game().loadMap(path, position); }, __FUNCTION__);
	return 0;
}

int GameFunctions::luaGameGetExperienceForLevel(lua_State* L) {
	// Game.getExperienceForLevel(level)
	const uint32_t level = Lua::getNumber<uint32_t>(L, 1);
	if (level == 0) {
		Lua::reportErrorFunc("Level must be greater than 0.");
	} else {
		lua_pushnumber(L, Player::getExpForLevel(level));
	}
	return 1;
}

int GameFunctions::luaGameGetMonsterCount(lua_State* L) {
	// Game.getMonsterCount()
	lua_pushnumber(L, g_game().getMonstersOnline());
	return 1;
}

int GameFunctions::luaGameGetPlayerCount(lua_State* L) {
	// Game.getPlayerCount()
	lua_pushnumber(L, g_game().getPlayersOnline());
	return 1;
}

int GameFunctions::luaGameGetNpcCount(lua_State* L) {
	// Game.getNpcCount()
	lua_pushnumber(L, g_game().getNpcsOnline());
	return 1;
}

int GameFunctions::luaGameGetMonsterTypes(lua_State* L) {
	// Game.getMonsterTypes()
	const auto type = g_monsters().monsters;
	lua_createtable(L, type.size(), 0);

	for (const auto &[typeName, mType] : type) {
		Lua::pushUserdata<MonsterType>(L, mType);
		Lua::setMetatable(L, -1, "MonsterType");
		lua_setfield(L, -2, typeName.c_str());
	}
	return 1;
}

int GameFunctions::luaGameGetTowns(lua_State* L) {
	// Game.getTowns()
	const auto towns = g_game().map.towns.getTowns();
	lua_createtable(L, towns.size(), 0);

	int index = 0;
	for (const auto &townEntry : towns) {
		Lua::pushUserdata<Town>(L, townEntry.second);
		Lua::setMetatable(L, -1, "Town");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetHouses(lua_State* L) {
	// Game.getHouses()
	const auto houses = g_game().map.houses.getHouses();
	lua_createtable(L, houses.size(), 0);

	int index = 0;
	for (const auto &houseEntry : houses) {
		Lua::pushUserdata<House>(L, houseEntry.second);
		Lua::setMetatable(L, -1, "House");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetGameState(lua_State* L) {
	// Game.getGameState()
	lua_pushnumber(L, g_game().getGameState());
	return 1;
}

int GameFunctions::luaGameSetGameState(lua_State* L) {
	// Game.setGameState(state)
	const GameState_t state = Lua::getNumber<GameState_t>(L, 1);
	g_game().setGameState(state);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameGetWorldType(lua_State* L) {
	// Game.getWorldType()
	lua_pushnumber(L, g_game().getWorldType());
	return 1;
}

int GameFunctions::luaGameSetWorldType(lua_State* L) {
	// Game.setWorldType(type)
	const WorldType_t type = Lua::getNumber<WorldType_t>(L, 1);
	if (type >= WORLDTYPE_FIRST && type <= WORLDTYPE_LAST) {
		g_game().setWorldType(type);
		Lua::pushBoolean(L, true);
	} else {
		Lua::pushBoolean(L, false);
	}

	return 1;
}

int GameFunctions::luaGameGetReturnMessage(lua_State* L) {
	// Game.getReturnMessage(value)
	const ReturnValue value = Lua::getNumber<ReturnValue>(L, 1);
	Lua::pushString(L, getReturnMessage(value));
	return 1;
}

int GameFunctions::luaGameCreateItem(lua_State* L) {
	// Game.createItem(itemId or name[, count[, position]])
	uint16_t itemId;
	if (Lua::isNumber(L, 1)) {
		itemId = Lua::getNumber<uint16_t>(L, 1);
	} else {
		itemId = Item::items.getItemIdByName(Lua::getString(L, 1));
		if (itemId == 0) {
			lua_pushnil(L);
			return 1;
		}
	}

	const auto count = Lua::getNumber<int32_t>(L, 2, 1);
	int32_t itemCount = 1;
	int32_t subType = 1;

	const ItemType &it = Item::items[itemId];
	if (it.hasSubType()) {
		if (it.stackable) {
			itemCount = std::ceil(count / static_cast<float_t>(it.stackSize));
		}

		subType = count;
	} else {
		itemCount = std::max<int32_t>(1, count);
	}

	Position position;
	if (lua_gettop(L) >= 3) {
		position = Lua::getPosition(L, 3);
	}

	const bool hasTable = itemCount > 1;
	if (hasTable) {
		lua_newtable(L);
	} else if (itemCount == 0) {
		lua_pushnil(L);
		return 1;
	}

	for (int32_t i = 1; i <= itemCount; ++i) {
		int32_t stackCount = subType;
		if (it.stackable) {
			stackCount = std::min<int32_t>(stackCount, it.stackSize);
			subType -= stackCount;
		}

		const auto &item = Item::CreateItem(itemId, stackCount);
		if (!item) {
			if (!hasTable) {
				lua_pushnil(L);
			}
			return 1;
		}

		if (position.x != 0) {
			const auto &tile = g_game().map.getTile(position);
			if (!tile) {
				if (!hasTable) {
					lua_pushnil(L);
				}
				return 1;
			}

			ReturnValue ret = g_game().internalAddItem(tile, item, INDEX_WHEREEVER, FLAG_NOLIMIT);
			if (ret != RETURNVALUE_NOERROR) {
				if (!hasTable) {
					lua_pushnil(L);
				}
				return 1;
			}
		} else {
			Lua::getScriptEnv()->addTempItem(item);
			item->setParent(VirtualCylinder::virtualCylinder);
		}

		if (hasTable) {
			lua_pushnumber(L, i);
			Lua::pushUserdata<Item>(L, item);
			Lua::setItemMetatable(L, -1, item);
			lua_settable(L, -3);
		} else {
			Lua::pushUserdata<Item>(L, item);
			Lua::setItemMetatable(L, -1, item);
		}
	}

	return 1;
}

int GameFunctions::luaGameCreateContainer(lua_State* L) {
	// Game.createContainer(itemId, size[, position])
	const uint16_t size = Lua::getNumber<uint16_t>(L, 2);
	uint16_t id;
	if (Lua::isNumber(L, 1)) {
		id = Lua::getNumber<uint16_t>(L, 1);
	} else {
		id = Item::items.getItemIdByName(Lua::getString(L, 1));
		if (id == 0) {
			lua_pushnil(L);
			return 1;
		}
	}

	const auto &container = Item::CreateItemAsContainer(id, size);
	if (!container) {
		lua_pushnil(L);
		return 1;
	}

	if (lua_gettop(L) >= 3) {
		const Position &position = Lua::getPosition(L, 3);
		const auto &tile = g_game().map.getTile(position);
		if (!tile) {
			lua_pushnil(L);
			return 1;
		}

		g_game().internalAddItem(tile, container, INDEX_WHEREEVER, FLAG_NOLIMIT);
	} else {
		Lua::getScriptEnv()->addTempItem(container);
		container->setParent(VirtualCylinder::virtualCylinder);
	}

	Lua::pushUserdata<Container>(L, container);
	Lua::setMetatable(L, -1, "Container");
	return 1;
}

int GameFunctions::luaGameCreateMonster(lua_State* L) {
	// Game.createMonster(monsterName, position[, extended = false[, force = false[, master = nil]]])
	const auto &monster = Monster::createMonster(Lua::getString(L, 1));
	if (!monster) {
		lua_pushnil(L);
		return 1;
	}

	bool isSummon = false;
	if (lua_gettop(L) >= 5) {
		if (const auto &master = Lua::getCreature(L, 5)) {
			monster->setMaster(master, true);
			isSummon = true;
		}
	}

	const Position &position = Lua::getPosition(L, 2);
	const bool extended = Lua::getBoolean(L, 3, false);
	const bool force = Lua::getBoolean(L, 4, false);
	if (g_game().placeCreature(monster, position, extended, force)) {
		monster->onSpawn(position);
		const auto &mtype = monster->getMonsterType();
		if (mtype && mtype->info.raceid > 0 && mtype->info.bosstiaryRace == BosstiaryRarity_t::RARITY_ARCHFOE) {
			for (const auto &spectator : Spectators().find<Player>(monster->getPosition(), true)) {
				if (const auto &tmpPlayer = spectator->getPlayer()) {
					tmpPlayer->sendBosstiaryCooldownTimer();
				}
			}
		}

		Lua::pushUserdata<Monster>(L, monster);
		Lua::setMetatable(L, -1, "Monster");
	} else {
		if (isSummon) {
			monster->setMaster(nullptr);
		} else {
		}
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameGenerateNpc(lua_State* L) {
	// Game.generateNpc(npcName)
	const auto &npc = Npc::createNpc(Lua::getString(L, 1));
	if (!npc) {
		lua_pushnil(L);
		return 1;
	} else {
		Lua::pushUserdata<Npc>(L, npc);
		Lua::setMetatable(L, -1, "Npc");
	}
	return 1;
}

int GameFunctions::luaGameCreateNpc(lua_State* L) {
	// Game.createNpc(npcName, position[, extended = false[, force = false]])
	const auto &npc = Npc::createNpc(Lua::getString(L, 1));
	if (!npc) {
		lua_pushnil(L);
		return 1;
	}

	const Position &position = Lua::getPosition(L, 2);
	const bool extended = Lua::getBoolean(L, 3, false);
	const bool force = Lua::getBoolean(L, 4, false);
	if (g_game().placeCreature(npc, position, extended, force)) {
		Lua::pushUserdata<Npc>(L, npc);
		Lua::setMetatable(L, -1, "Npc");
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameCreateTile(lua_State* L) {
	// Game.createTile(x, y, z[, isDynamic = false])
	// Game.createTile(position[, isDynamic = false])
	Position position;
	bool isDynamic;
	if (Lua::isTable(L, 1)) {
		position = Lua::getPosition(L, 1);
		isDynamic = Lua::getBoolean(L, 2, false);
	} else {
		position.x = Lua::getNumber<uint16_t>(L, 1);
		position.y = Lua::getNumber<uint16_t>(L, 2);
		position.z = Lua::getNumber<uint16_t>(L, 3);
		isDynamic = Lua::getBoolean(L, 4, false);
	}

	Lua::pushUserdata(L, g_game().map.getOrCreateTile(position, isDynamic));
	Lua::setMetatable(L, -1, "Tile");
	return 1;
}

int GameFunctions::luaGameGetBestiaryCharm(lua_State* L) {
	// Game.getBestiaryCharm()
	const auto c_list = g_game().getCharmList();
	lua_createtable(L, c_list.size(), 0);

	int index = 0;
	for (const auto &charmPtr : c_list) {
		Lua::pushUserdata<Charm>(L, charmPtr);
		Lua::setMetatable(L, -1, "Charm");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameCreateBestiaryCharm(lua_State* L) {
	// Game.createBestiaryCharm(id)
	if (const std::shared_ptr<Charm> &charm = g_iobestiary().getBestiaryCharm(static_cast<charmRune_t>(Lua::getNumber<int8_t>(L, 1, 0)), true)) {
		Lua::pushUserdata<Charm>(L, charm);
		Lua::setMetatable(L, -1, "Charm");
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameCreateItemClassification(lua_State* L) {
	// Game.createItemClassification(id)
	const ItemClassification* itemClassification = g_game().getItemsClassification(Lua::getNumber<uint8_t>(L, 1), true);
	if (itemClassification) {
		Lua::pushUserdata<const ItemClassification>(L, itemClassification);
		Lua::setMetatable(L, -1, "ItemClassification");
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameStartRaid(lua_State* L) {
	// Game.startRaid(raidName)
	const std::string &raidName = Lua::getString(L, 1);

	const auto &raid = g_game().raids.getRaidByName(raidName);
	if (!raid || !raid->isLoaded()) {
		lua_pushnumber(L, RETURNVALUE_NOSUCHRAIDEXISTS);
		return 1;
	}

	if (g_game().raids.getRunning() || raid->getState() == RAIDSTATE_EXECUTING) {
		lua_pushnumber(L, RETURNVALUE_ANOTHERRAIDISALREADYEXECUTING);
		return 1;
	}

	g_game().raids.setRunning(raid);
	raid->startRaid();
	lua_pushnumber(L, RETURNVALUE_NOERROR);
	return 1;
}

int GameFunctions::luaGameGetClientVersion(lua_State* L) {
	// Game.getClientVersion()
	lua_createtable(L, 0, 3);
	Lua::setField(L, "min", CLIENT_VERSION);
	Lua::setField(L, "max", CLIENT_VERSION);
	const std::string version = fmt::format("{}.{}", CLIENT_VERSION_UPPER, CLIENT_VERSION_LOWER);
	Lua::setField(L, "string", version);
	return 1;
}

int GameFunctions::luaGameReload(lua_State* L) {
	// Game.reload(reloadType)
	const Reload_t reloadType = Lua::getNumber<Reload_t>(L, 1);
	if (GameReload::getReloadNumber(reloadType) == GameReload::getReloadNumber(Reload_t::RELOAD_TYPE_NONE)) {
		Lua::reportErrorFunc("Reload type is none");
		Lua::pushBoolean(L, false);
		return 0;
	}

	if (GameReload::getReloadNumber(reloadType) >= GameReload::getReloadNumber(Reload_t::RELOAD_TYPE_LAST)) {
		Lua::reportErrorFunc("Reload type not exist");
		Lua::pushBoolean(L, false);
		return 0;
	}

	Lua::pushBoolean(L, GameReload::init(reloadType));
	lua_gc(g_luaEnvironment().getLuaState(), LUA_GCCOLLECT, 0);
	return 1;
}

int GameFunctions::luaGameHasEffect(lua_State* L) {
	// Game.hasEffect(effectId)
	const uint16_t effectId = Lua::getNumber<uint16_t>(L, 1);
	Lua::pushBoolean(L, g_game().hasEffect(effectId));
	return 1;
}

int GameFunctions::luaGameHasDistanceEffect(lua_State* L) {
	// Game.hasDistanceEffect(effectId)
	const uint16_t effectId = Lua::getNumber<uint16_t>(L, 1);
	Lua::pushBoolean(L, g_game().hasDistanceEffect(effectId));
	return 1;
}

int GameFunctions::luaGameGetOfflinePlayer(lua_State* L) {
	// Game.getOfflinePlayer(name or id)
	std::shared_ptr<Player> player = nullptr;
	if (Lua::isNumber(L, 1)) {
		const uint32_t id = Lua::getNumber<uint32_t>(L, 1);
		if (id >= Player::getFirstID() && id <= Player::getLastID()) {
			player = g_game().getPlayerByID(id, true);
		} else {
			player = g_game().getPlayerByGUID(id, true);
		}
	} else if (Lua::isString(L, 1)) {
		const auto name = Lua::getString(L, 1);
		player = g_game().getPlayerByName(name, true);
	}
	if (!player) {
		lua_pushnil(L);
	} else {
		Lua::pushUserdata<Player>(L, player);
		Lua::setMetatable(L, -1, "Player");
	}

	return 1;
}

int GameFunctions::luaGameGetNormalizedPlayerName(lua_State* L) {
	// Game.getNormalizedPlayerName(name[, isNewName = false])
	const auto name = Lua::getString(L, 1);
	const auto isNewName = Lua::getBoolean(L, 2, false);
	const auto &player = g_game().getPlayerByName(name, true, isNewName);
	if (player) {
		Lua::pushString(L, player->getName());
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameGetNormalizedGuildName(lua_State* L) {
	// Game.getNormalizedGuildName(name)
	const auto name = Lua::getString(L, 1);
	const auto &guild = g_game().getGuildByName(name, true);
	if (guild) {
		Lua::pushString(L, guild->getName());
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int GameFunctions::luaGameAddInfluencedMonster(lua_State* L) {
	// Game.addInfluencedMonster(monster)
	const auto &monster = Lua::getUserdataShared<Monster>(L, 1);
	if (!monster) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_MONSTER_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 0;
	}

	lua_pushboolean(L, g_game().addInfluencedMonster(monster));
	return 1;
}

int GameFunctions::luaGameRemoveInfluencedMonster(lua_State* L) {
	// Game.removeInfluencedMonster(monsterId)
	const uint32_t monsterId = Lua::getNumber<uint32_t>(L, 1);
	const auto create = Lua::getBoolean(L, 2, false);
	lua_pushnumber(L, g_game().removeInfluencedMonster(monsterId, create));
	return 1;
}

int GameFunctions::luaGameGetInfluencedMonsters(lua_State* L) {
	// Game.getInfluencedMonsters()
	const auto &monsters = g_game().getInfluencedMonsters();
	lua_createtable(L, static_cast<int>(monsters.size()), 0);
	int index = 0;
	for (const auto monsterId : monsters) {
		++index;
		lua_pushnumber(L, monsterId);
		lua_rawseti(L, -2, index);
	}

	return 1;
}

int GameFunctions::luaGameGetLadderIds(lua_State* L) {
	// Game.getLadderIds()
	const auto &ladders = Item::items.getLadders();
	lua_createtable(L, static_cast<int>(ladders.size()), 0);
	int index = 0;
	for (const auto &ladderId : ladders) {
		++index;
		lua_pushnumber(L, static_cast<lua_Number>(ladderId));
		lua_rawseti(L, -2, index);
	}

	return 1;
}

int GameFunctions::luaGameGetDummies(lua_State* L) {
	/**
	 * @brief Retrieve dummy IDs categorized by type.
	 * @details This function provides a table containing two sub-tables: one for free dummies and one for house (or premium) dummies.

	* @note usage on lua:
	    local dummies = Game.getDummies()
	    local rate = dummies[1] -- Retrieve dummy rate
	*/

	const auto &dummies = Item::items.getDummys();
	lua_createtable(L, dummies.size(), 0);
	for (const auto &[dummyId, rate] : dummies) {
		lua_pushnumber(L, static_cast<lua_Number>(rate));
		lua_rawseti(L, -2, dummyId);
	}
	return 1;
}

int GameFunctions::luaGameMakeFiendishMonster(lua_State* L) {
	// Game.makeFiendishMonster(monsterId[default= 0])
	const auto monsterId = Lua::getNumber<uint32_t>(L, 1, 0);
	const auto createForgeableMonsters = Lua::getBoolean(L, 2, false);
	lua_pushnumber(L, g_game().makeFiendishMonster(monsterId, createForgeableMonsters));
	return 1;
}

int GameFunctions::luaGameRemoveFiendishMonster(lua_State* L) {
	// Game.removeFiendishMonster(monsterId)
	const uint32_t monsterId = Lua::getNumber<uint32_t>(L, 1);
	const auto create = Lua::getBoolean(L, 2, false);
	lua_pushnumber(L, g_game().removeFiendishMonster(monsterId, create));
	return 1;
}

int GameFunctions::luaGameGetFiendishMonsters(lua_State* L) {
	// Game.getFiendishMonsters()
	const auto &monsters = g_game().getFiendishMonsters();

	lua_createtable(L, static_cast<int>(monsters.size()), 0);
	int index = 0;
	for (const auto monsterId : monsters) {
		++index;
		lua_pushnumber(L, monsterId);
		lua_rawseti(L, -2, index);
	}

	return 1;
}

int GameFunctions::luaGameGetBoostedBoss(lua_State* L) {
	// Game.getBoostedBoss()
	Lua::pushString(L, g_ioBosstiary().getBoostedBossName());
	return 1;
}

int GameFunctions::luaGameGetTalkActions(lua_State* L) {
	// Game.getTalkActions()
	const auto talkactionsMap = g_talkActions().getTalkActionsMap();
	lua_createtable(L, static_cast<int>(talkactionsMap.size()), 0);

	for (const auto &[talkName, talkactionSharedPtr] : talkactionsMap) {
		Lua::pushUserdata<TalkAction>(L, talkactionSharedPtr);
		Lua::setMetatable(L, -1, "TalkAction");
		lua_setfield(L, -2, talkName.c_str());
	}
	return 1;
}

int GameFunctions::luaGameGetEventCallbacks(lua_State* L) {
	lua_createtable(L, 0, 0);
	lua_pushcfunction(L, EventCallbackFunctions::luaEventCallbackLoad);
	for (const auto &[value, name] : magic_enum::enum_entries<EventCallback_t>()) {
		if (value != EventCallback_t::none) {
			std::string methodName = magic_enum::enum_name(value).data();
			lua_pushstring(L, methodName.c_str());
			// Copy the function reference to the top of the stack
			lua_pushvalue(L, -2);
			lua_settable(L, -4);
		}
	}
	// Pop the function
	lua_pop(L, 1);
	return 1;
}

int GameFunctions::luaGameRegisterAchievement(lua_State* L) {
	// Game.registerAchievement(id, name, description, secret, grade, points)
	if (lua_gettop(L) < 6) {
		Lua::reportErrorFunc("Achievement can only be registered with all params.");
		return 1;
	}

	const uint16_t id = Lua::getNumber<uint16_t>(L, 1);
	const std::string name = Lua::getString(L, 2);
	const std::string description = Lua::getString(L, 3);
	const bool secret = Lua::getBoolean(L, 4);
	const uint8_t grade = Lua::getNumber<uint8_t>(L, 5);
	const uint8_t points = Lua::getNumber<uint8_t>(L, 6);
	g_game().registerAchievement(id, name, description, secret, grade, points);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameGetAchievementInfoById(lua_State* L) {
	// Game.getAchievementInfoById(id)
	const uint16_t id = Lua::getNumber<uint16_t>(L, 1);
	const Achievement achievement = g_game().getAchievementById(id);
	if (achievement.id == 0) {
		Lua::reportErrorFunc("Achievement id is wrong");
		return 1;
	}

	lua_createtable(L, 0, 6);
	Lua::setField(L, "id", achievement.id);
	Lua::setField(L, "name", achievement.name);
	Lua::setField(L, "description", achievement.description);
	Lua::setField(L, "points", achievement.points);
	Lua::setField(L, "grade", achievement.grade);
	Lua::setField(L, "secret", achievement.secret);
	return 1;
}

int GameFunctions::luaGameGetAchievementInfoByName(lua_State* L) {
	// Game.getAchievementInfoByName(name)
	const std::string name = Lua::getString(L, 1);
	const Achievement achievement = g_game().getAchievementByName(name);
	if (achievement.id == 0) {
		Lua::reportErrorFunc("Achievement name is wrong");
		return 1;
	}

	lua_createtable(L, 0, 6);
	Lua::setField(L, "id", achievement.id);
	Lua::setField(L, "name", achievement.name);
	Lua::setField(L, "description", achievement.description);
	Lua::setField(L, "points", achievement.points);
	Lua::setField(L, "grade", achievement.grade);
	Lua::setField(L, "secret", achievement.secret);
	return 1;
}

int GameFunctions::luaGameGetSecretAchievements(lua_State* L) {
	// Game.getSecretAchievements()
	const std::vector<Achievement> &achievements = g_game().getSecretAchievements();
	int index = 0;
	lua_createtable(L, achievements.size(), 0);
	for (const auto &achievement : achievements) {
		lua_createtable(L, 0, 6);
		Lua::setField(L, "id", achievement.id);
		Lua::setField(L, "name", achievement.name);
		Lua::setField(L, "description", achievement.description);
		Lua::setField(L, "points", achievement.points);
		Lua::setField(L, "grade", achievement.grade);
		Lua::setField(L, "secret", achievement.secret);
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetPublicAchievements(lua_State* L) {
	// Game.getPublicAchievements()
	const std::vector<Achievement> &achievements = g_game().getPublicAchievements();
	int index = 0;
	lua_createtable(L, achievements.size(), 0);
	for (const auto &achievement : achievements) {
		lua_createtable(L, 0, 6);
		Lua::setField(L, "id", achievement.id);
		Lua::setField(L, "name", achievement.name);
		Lua::setField(L, "description", achievement.description);
		Lua::setField(L, "points", achievement.points);
		Lua::setField(L, "grade", achievement.grade);
		Lua::setField(L, "secret", achievement.secret);
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetAchievements(lua_State* L) {
	// Game.getAchievements()
	const std::map<uint16_t, Achievement> &achievements = g_game().getAchievements();
	int index = 0;
	lua_createtable(L, achievements.size(), 0);
	for (const auto &achievement_it : achievements) {
		lua_createtable(L, 0, 6);
		Lua::setField(L, "id", achievement_it.first);
		Lua::setField(L, "name", achievement_it.second.name);
		Lua::setField(L, "description", achievement_it.second.description);
		Lua::setField(L, "points", achievement_it.second.points);
		Lua::setField(L, "grade", achievement_it.second.grade);
		Lua::setField(L, "secret", achievement_it.second.secret);
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

int GameFunctions::luaGameGetTitleByName(lua_State* L) {
	// Game.getTitleByName(titleName)
	const std::string titleName = Lua::getString(L, 1);
	if (titleName.empty()) {
		lua_pushnil(L);
		return 1;
	}

	const Title &title = g_game().getTitleByName(titleName);
	if (title.m_maleName.empty() && title.m_femaleName.empty()) {
		lua_pushnil(L);
		return 1;
	}

	lua_createtable(L, 0, 4);
	Lua::pushString(L, title.m_maleName);
	lua_setfield(L, -2, "maleName");

	Lua::pushString(L, title.m_femaleName);
	lua_setfield(L, -2, "femaleName");

	Lua::pushNumber(L, title.m_id);
	lua_setfield(L, -2, "id");

	Lua::pushString(L, title.m_description);
	lua_setfield(L, -2, "description");
	return 1;
}

int GameFunctions::luaHouseGetHouseCountByAccount(lua_State* L) {
	// Game:getHouseCountByAccount(accountId)
	const auto &houses = g_game().map.houses.getHouses();
	if (houses.empty()) {
		Lua::reportErrorFunc("Houses not found");
		lua_pushnil(L);
		return 1;
	}

	uint32_t accountId = Lua::getNumber<uint32_t>(L, 2);
	uint16_t count = 0;
	for (const auto &[id, house] : houses) {
		if (house->getOwnerAccountId() == accountId) {
			++count;
		}
	}
	lua_pushnumber(L, count);
	return 1;
}

int GameFunctions::luaGameSetGuildMotd(lua_State* L) {
	// Game:setGuildMotd(guildId, newMotd)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string newMotd = Lua::getString(L, 2);

	g_game().setGuildMotd(guildId, newMotd);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameDisbandGuild(lua_State* L) {
	// Game:disbandGuild(guildId)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);

	g_game().disbandGuild(guildId);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameInvitePlayerToGuild(lua_State* L) {
	// Game:invitePlayerToGuild(guildId, playerName)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string playerName = Lua::getString(L, 2);

	g_game().invitePlayerToGuild(guildId, playerName);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameRemovePlayerFromGuild(lua_State* L) {
	// Game:removePlayerFromGuild(guildId, playerName)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string playerName = Lua::getString(L, 2);

	g_game().removePlayerFromGuild(guildId, playerName);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGamePromotePlayer(lua_State* L) {
	// Game:promotePlayer(guildId, playerName)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string playerName = Lua::getString(L, 2);

	g_game().promotePlayer(guildId, playerName);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameDemotePlayer(lua_State* L) {
	// Game:demotePlayer(guildId, playerName)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string playerName = Lua::getString(L, 2);

	g_game().demotePlayer(guildId, playerName);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGamePassLeadership(lua_State* L) {
	// Game:passLeadership(guildId, newLeaderName)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string newLeaderName = Lua::getString(L, 2);

	g_game().passLeadership(guildId, newLeaderName);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameSetPlayerGuildNick(lua_State* L) {
	// Game:setPlayerGuildNick(guildId, playerName, nick)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	const std::string playerName = Lua::getString(L, 2);
	const std::string nick = Lua::getString(L, 3);

	g_game().setPlayerGuildNick(guildId, playerName, nick);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameSetRankName(lua_State* L) {
	// Game:setRankName(guildId, rankLevel, newName)
	uint32_t guildId = Lua::getNumber<uint32_t>(L, 1);
	uint8_t rankLevel = Lua::getNumber<uint8_t>(L, 2);
	const std::string newName = Lua::getString(L, 3);

	g_game().setRankName(guildId, rankLevel, newName);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameCreateGuild(lua_State* L) {
	// Game:createGuild(guildName, leaderName)
	const std::string guildName = Lua::getString(L, 1);
	const std::string leaderName = Lua::getString(L, 2);

	uint32_t guildId = g_game().createGuild(guildName, leaderName);
	Lua::pushNumber(L, guildId);
	return 1;
}

int GameFunctions::luaGameJoinGuild(lua_State* L) {
	// Game:joinGuild(guildName, playerName)
	const std::string guildName = Lua::getString(L, 1);
	const std::string playerName = Lua::getString(L, 2);

	bool success = g_game().joinGuild(guildName, playerName);
	Lua::pushBoolean(L, success);
	return 1;
}

// === Instance System Lua Bindings ===

int GameFunctions::luaGameCreateInstance(lua_State* L) {
	// Game.createInstance([owner])
	// Creates a new instance and returns its ID.
	// Optional: pass a player as owner.
	std::shared_ptr<Player> owner = nullptr;
	if (lua_gettop(L) >= 1 && !lua_isnil(L, 1)) {
		owner = Lua::getUserdataShared<Player>(L, 1);
	}
	uint32_t instanceId = g_instanceManager().createInstance(owner);
	lua_pushnumber(L, instanceId);
	return 1;
}

int GameFunctions::luaGameDestroyInstance(lua_State* L) {
	// Game.destroyInstance(instanceId)
	// Destroys an existing instance.
	uint32_t instanceId = Lua::getNumber<uint32_t>(L, 1);
	bool success = g_instanceManager().destroyInstance(instanceId);
	Lua::pushBoolean(L, success);
	return 1;
}

int GameFunctions::luaGameCreateInstanceMonster(lua_State* L) {
	// Game.createInstanceMonster(monsterName, position, instanceId[, extended[, force]])
	// Creates a monster and assigns it to the specified instance.
	const std::string &monsterName = Lua::getString(L, 1);
	const Position &pos = Lua::getPosition(L, 2);
	uint32_t instanceId = Lua::getNumber<uint32_t>(L, 3);
	bool extended = Lua::getBoolean(L, 4, false);
	bool force = Lua::getBoolean(L, 5, false);

	auto monster = Monster::createMonster(monsterName);
	if (!monster) {
		lua_pushnil(L);
		return 1;
	}

	monster->setInstanceID(instanceId);

	if (!g_game().placeCreature(monster, pos, extended, force)) {
		lua_pushnil(L);
		return 1;
	}

	Lua::pushUserdata<Monster>(L, monster);
	Lua::setMetatable(L, -1, "Monster");
	return 1;
}

int GameFunctions::luaGamePopulateInstanceFromMap(lua_State* L) {
	// Game.populateInstanceFromMap(instanceId, position, width, height)
	uint32_t instanceId = Lua::getNumber<uint32_t>(L, 1);
	const Position &pos = Lua::getPosition(L, 2);
	uint16_t width = Lua::getNumber<uint16_t>(L, 3);
	uint16_t height = Lua::getNumber<uint16_t>(L, 4);

	uint32_t count = g_instanceManager().populateFromMap(instanceId, pos, width, height);
	lua_pushnumber(L, count);
	return 1;
}

int GameFunctions::luaGamePopulateInstanceFromZone(lua_State* L) {
	// Game.populateInstanceFromZone(instanceId, zone)
	uint32_t instanceId = Lua::getNumber<uint32_t>(L, 1);
	const auto &zone = Lua::getUserdataShared<Zone>(L, 2);
	if (!zone) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_ZONE_NOT_FOUND));
		lua_pushnumber(L, 0);
		return 1;
	}
	uint32_t count = g_instanceManager().populateFromZone(instanceId, zone);
	lua_pushnumber(L, count);
	return 1;
}

int GameFunctions::luaGameTrackInstancePlayer(lua_State* L) {
	// Game.trackInstancePlayer(playerGuid, instanceId)
	uint32_t playerGuid = Lua::getNumber<uint32_t>(L, 1);
	uint32_t instanceId = Lua::getNumber<uint32_t>(L, 2);
	g_instanceManager().trackPlayerInstance(playerGuid, instanceId);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameUntrackInstancePlayer(lua_State* L) {
	// Game.untrackInstancePlayer(playerGuid)
	uint32_t playerGuid = Lua::getNumber<uint32_t>(L, 1);
	g_instanceManager().untrackPlayerInstance(playerGuid);
	Lua::pushBoolean(L, true);
	return 1;
}

int GameFunctions::luaGameFindInstanceByPlayerGuid(lua_State* L) {
	// Game.findInstanceByPlayerGuid(playerGuid)
	// Returns instanceId or 0 if not found/instance no longer exists
	uint32_t playerGuid = Lua::getNumber<uint32_t>(L, 1);
	uint32_t instanceId = g_instanceManager().findInstanceByPlayerGuid(playerGuid);
	lua_pushnumber(L, instanceId);
	return 1;
}

// === Spawn Query System ===

int GameFunctions::luaGameGetSpawnsInArea(lua_State* L) {
	// Game.getSpawnsInArea(fromPos, toPos)
	// Returns table of {name, x, y, z, spawntime} for each individual spawn in the area
	const Position &fromPos = Lua::getPosition(L, 1);
	const Position &toPos = Lua::getPosition(L, 2);

	lua_newtable(L);
	int index = 1;

	auto processSpawnList = [&](std::vector<std::shared_ptr<SpawnMonster>> &spawnList) {
		for (const auto &spawn : spawnList) {
			const auto &center = spawn->getCenterPos();
			bool inArea = (center.x >= fromPos.x && center.x <= toPos.x
				&& center.y >= fromPos.y && center.y <= toPos.y
				&& center.z >= fromPos.z && center.z <= toPos.z);
			if (!inArea) {
				for (const auto &[id, block] : spawn->getSpawnMonsterMap()) {
					if (block.pos.x >= fromPos.x && block.pos.x <= toPos.x
						&& block.pos.y >= fromPos.y && block.pos.y <= toPos.y
						&& block.pos.z >= fromPos.z && block.pos.z <= toPos.z) {
						inArea = true;
						break;
					}
				}
			}
			if (!inArea) {
				continue;
			}
			for (const auto &[id, block] : spawn->getSpawnMonsterMap()) {
				for (const auto &[monsterType, weight] : block.monsterTypes) {
					lua_createtable(L, 0, 5);

					Lua::pushString(L, monsterType->name);
					lua_setfield(L, -2, "name");

					lua_pushnumber(L, block.pos.x);
					lua_setfield(L, -2, "x");
					lua_pushnumber(L, block.pos.y);
					lua_setfield(L, -2, "y");
					lua_pushnumber(L, block.pos.z);
					lua_setfield(L, -2, "z");

					lua_pushnumber(L, static_cast<lua_Number>(block.interval) / 1000);
					lua_setfield(L, -2, "spawntime");

					lua_rawseti(L, -2, index++);
				}
			}
		}
	};

	processSpawnList(g_game().map.spawnsMonster.getspawnMonsterList());
	for (int i = 0; i < 50; i++) {
		processSpawnList(g_game().map.spawnsMonsterCustomMaps[i].getspawnMonsterList());
	}

	return 1;
}

int GameFunctions::luaGameDiscoverSpawnClusters(lua_State* L) {
	// Game.discoverSpawnClusters(minZ, maxZ[, filterName])
	// Returns table of clusters: {fromPos, toPos, spawns, zLevels, monsters}
	uint8_t minZ = Lua::getNumber<uint8_t>(L, 1);
	uint8_t maxZ = Lua::getNumber<uint8_t>(L, 2);
	std::string filterName = Lua::getString(L, 3, "");

	bool hasFilter = !filterName.empty();
	std::string filterLower = filterName;
	if (hasFilter) {
		std::transform(filterLower.begin(), filterLower.end(), filterLower.begin(), ::tolower);
	}

	// Grid cell size for clustering
	constexpr int CELL_SIZE = 30;

	// Key: (cellX, cellY, z) -> list of spawn data
	struct SpawnEntry {
		Position pos;
		std::string name;
	};

	struct CellKey {
		int cellX;
		int cellY;
		uint8_t z;
		bool operator==(const CellKey &o) const {
			return cellX == o.cellX && cellY == o.cellY && z == o.z;
		}
	};

	struct CellKeyHash {
		size_t operator()(const CellKey &k) const {
			size_t h = std::hash<int>()(k.cellX);
			h ^= std::hash<int>()(k.cellY) + 0x9e3779b9 + (h << 6) + (h >> 2);
			h ^= std::hash<uint8_t>()(k.z) + 0x9e3779b9 + (h << 6) + (h >> 2);
			return h;
		}
	};

	std::unordered_map<CellKey, std::vector<SpawnEntry>, CellKeyHash> grid;

	auto processSpawnList = [&](std::vector<std::shared_ptr<SpawnMonster>> &spawnList) {
		for (const auto &spawn : spawnList) {
			const auto &center = spawn->getCenterPos();
			if (center.z < minZ || center.z > maxZ) {
				continue;
			}
			for (const auto &[id, block] : spawn->getSpawnMonsterMap()) {
				for (const auto &[monsterType, weight] : block.monsterTypes) {
					if (hasFilter) {
						std::string nameLower = monsterType->name;
						std::transform(nameLower.begin(), nameLower.end(), nameLower.begin(), ::tolower);
						if (nameLower.find(filterLower) == std::string::npos) {
							continue;
						}
					}
					CellKey key { static_cast<int>(block.pos.x) / CELL_SIZE,
						static_cast<int>(block.pos.y) / CELL_SIZE,
						block.pos.z };
					grid[key].push_back({ block.pos, monsterType->name });
				}
			}
		}
	};

	processSpawnList(g_game().map.spawnsMonster.getspawnMonsterList());
	for (int i = 0; i < 50; i++) {
		processSpawnList(g_game().map.spawnsMonsterCustomMaps[i].getspawnMonsterList());
	}

	// Flood-fill to merge adjacent cells into clusters
	std::unordered_set<CellKey, CellKeyHash> visited;

	struct Cluster {
		uint16_t minX = 65535, minY = 65535, maxX = 0, maxY = 0;
		uint8_t minClusterZ = 15, maxClusterZ = 0;
		std::unordered_map<std::string, uint32_t> monsterCounts;
		uint32_t totalSpawns = 0;
		std::set<uint8_t> zLevels;
		std::vector<Position> spawnPositions;
		Position centerSpawnPos;
	};

	std::vector<Cluster> clusters;

	for (auto &[cellKey, entries] : grid) {
		if (visited.count(cellKey)) {
			continue;
		}

		Cluster cluster;
		std::queue<CellKey> queue;
		queue.push(cellKey);
		visited.insert(cellKey);

		while (!queue.empty()) {
			auto current = queue.front();
			queue.pop();

			auto it = grid.find(current);
			if (it == grid.end()) {
				continue;
			}

			for (const auto &entry : it->second) {
				if (entry.pos.x < cluster.minX) {
					cluster.minX = entry.pos.x;
				}
				if (entry.pos.y < cluster.minY) {
					cluster.minY = entry.pos.y;
				}
				if (entry.pos.x > cluster.maxX) {
					cluster.maxX = entry.pos.x;
				}
				if (entry.pos.y > cluster.maxY) {
					cluster.maxY = entry.pos.y;
				}
				if (entry.pos.z < cluster.minClusterZ) {
					cluster.minClusterZ = entry.pos.z;
				}
				if (entry.pos.z > cluster.maxClusterZ) {
					cluster.maxClusterZ = entry.pos.z;
				}
				cluster.monsterCounts[entry.name]++;
				cluster.totalSpawns++;
				cluster.zLevels.insert(entry.pos.z);
				cluster.spawnPositions.push_back(entry.pos);
			}

			// Check 8 horizontal neighbors (same z-level only)
			for (int dx = -1; dx <= 1; dx++) {
				for (int dy = -1; dy <= 1; dy++) {
					if (dx == 0 && dy == 0) {
						continue;
					}
					CellKey neighbor { current.cellX + dx, current.cellY + dy, current.z };
					if (!visited.count(neighbor) && grid.count(neighbor)) {
						visited.insert(neighbor);
						queue.push(neighbor);
					}
				}
			}
		}

		if (cluster.totalSpawns >= 3) {
			double cx = (cluster.minX + cluster.maxX) / 2.0;
			double cy = (cluster.minY + cluster.maxY) / 2.0;
			double bestDist = std::numeric_limits<double>::max();
			for (const auto &pos : cluster.spawnPositions) {
				double dx = pos.x - cx;
				double dy = pos.y - cy;
				double dist = dx * dx + dy * dy;
				if (dist < bestDist) {
					bestDist = dist;
					cluster.centerSpawnPos = pos;
				}
			}
			cluster.spawnPositions.clear();
			cluster.spawnPositions.shrink_to_fit();
			clusters.push_back(std::move(cluster));
		}
	}

	// Phase 2: Auto-merge clusters connected by stairs/holes across Z-levels
	std::vector<size_t> ufParent(clusters.size());
	std::iota(ufParent.begin(), ufParent.end(), 0);
	auto findRoot = [&](size_t x) -> size_t {
		while (ufParent[x] != x) {
			ufParent[x] = ufParent[ufParent[x]];
			x = ufParent[x];
		}
		return x;
	};
	auto unite = [&](size_t a, size_t b) {
		ufParent[findRoot(b)] = findRoot(a);
	};

	for (size_t i = 0; i < clusters.size(); i++) {
		for (size_t j = i + 1; j < clusters.size(); j++) {
			if (findRoot(i) == findRoot(j)) {
				continue;
			}
			auto &ci = clusters[i];
			auto &cj = clusters[j];

			bool zAdj = false;
			uint8_t upperZ = 0, lowerZ = 0;
			for (uint8_t zi : ci.zLevels) {
				for (uint8_t zj : cj.zLevels) {
					if (zi + 1 == zj) {
						upperZ = zi;
						lowerZ = zj;
						zAdj = true;
					}
					if (zj + 1 == zi) {
						upperZ = zj;
						lowerZ = zi;
						zAdj = true;
					}
					if (zAdj) {
						break;
					}
				}
				if (zAdj) {
					break;
				}
			}
			if (!zAdj) {
				continue;
			}

			int oMinX = std::max(static_cast<int>(ci.minX), static_cast<int>(cj.minX));
			int oMaxX = std::min(static_cast<int>(ci.maxX), static_cast<int>(cj.maxX));
			int oMinY = std::max(static_cast<int>(ci.minY), static_cast<int>(cj.minY));
			int oMaxY = std::min(static_cast<int>(ci.maxY), static_cast<int>(cj.maxY));
			if (oMinX > oMaxX || oMinY > oMaxY) {
				continue;
			}

			bool connected = false;
			for (int x = oMinX; x <= oMaxX && !connected; x++) {
				for (int y = oMinY; y <= oMaxY && !connected; y++) {
					auto tileUp = g_game().map.getTile(x, y, upperZ);
					if (tileUp && tileUp->hasFlag(TILESTATE_FLOORCHANGE_DOWN)) {
						connected = true;
						break;
					}
					auto tileLow = g_game().map.getTile(x, y, lowerZ);
					if (tileLow && tileLow->hasFlag(TILESTATE_FLOORCHANGE) && !tileLow->hasFlag(TILESTATE_FLOORCHANGE_DOWN)) {
						connected = true;
						break;
					}
				}
			}
			if (connected) {
				unite(i, j);
			}
		}
	}

	// Rebuild merged clusters from union-find groups
	std::unordered_map<size_t, std::vector<size_t>> ufGroups;
	for (size_t i = 0; i < clusters.size(); i++) {
		ufGroups[findRoot(i)].push_back(i);
	}
	std::vector<Cluster> mergedClusters;
	for (auto &[root, members] : ufGroups) {
		if (members.size() == 1) {
			mergedClusters.push_back(std::move(clusters[members[0]]));
		} else {
			Cluster merged;
			size_t bestIdx = members[0];
			for (size_t idx : members) {
				auto &c = clusters[idx];
				merged.minX = std::min(merged.minX, c.minX);
				merged.minY = std::min(merged.minY, c.minY);
				merged.maxX = std::max(merged.maxX, c.maxX);
				merged.maxY = std::max(merged.maxY, c.maxY);
				merged.minClusterZ = std::min(merged.minClusterZ, c.minClusterZ);
				merged.maxClusterZ = std::max(merged.maxClusterZ, c.maxClusterZ);
				merged.totalSpawns += c.totalSpawns;
				for (auto &[name, count] : c.monsterCounts) {
					merged.monsterCounts[name] += count;
				}
				for (uint8_t z : c.zLevels) {
					merged.zLevels.insert(z);
				}
				if (c.totalSpawns > clusters[bestIdx].totalSpawns) {
					bestIdx = idx;
				}
			}
			merged.centerSpawnPos = clusters[bestIdx].centerSpawnPos;
			mergedClusters.push_back(std::move(merged));
		}
	}
	clusters = std::move(mergedClusters);

	// Sort by total spawns descending
	std::sort(clusters.begin(), clusters.end(), [](const Cluster &a, const Cluster &b) {
		return a.totalSpawns > b.totalSpawns;
	});

	// Build Lua result table
	lua_newtable(L);
	int clusterIdx = 1;
	for (const auto &cluster : clusters) {
		lua_createtable(L, 0, 6);

		// fromPos
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, cluster.minX);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, cluster.minY);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, cluster.minClusterZ);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "fromPos");

		// toPos
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, cluster.maxX);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, cluster.maxY);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, cluster.maxClusterZ);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "toPos");

		// centerSpawnPos: actual spawn position closest to geometric center
		lua_createtable(L, 0, 3);
		lua_pushnumber(L, cluster.centerSpawnPos.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, cluster.centerSpawnPos.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, cluster.centerSpawnPos.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "centerSpawnPos");

		// spawns count
		lua_pushnumber(L, cluster.totalSpawns);
		lua_setfield(L, -2, "spawns");

		// zLevels array
		lua_createtable(L, static_cast<int>(cluster.zLevels.size()), 0);
		int zIdx = 1;
		for (uint8_t z : cluster.zLevels) {
			lua_pushnumber(L, z);
			lua_rawseti(L, -2, zIdx++);
		}
		lua_setfield(L, -2, "zLevels");

		// monsters: sorted by count descending
		std::vector<std::pair<std::string, uint32_t>> sortedMonsters(
			cluster.monsterCounts.begin(), cluster.monsterCounts.end());
		std::sort(sortedMonsters.begin(), sortedMonsters.end(),
			[](const auto &a, const auto &b) { return a.second > b.second; });

		lua_createtable(L, static_cast<int>(sortedMonsters.size()), 0);
		int mIdx = 1;
		for (const auto &[name, count] : sortedMonsters) {
			lua_createtable(L, 0, 2);
			Lua::pushString(L, name);
			lua_setfield(L, -2, "name");
			lua_pushnumber(L, count);
			lua_setfield(L, -2, "count");
			lua_rawseti(L, -2, mIdx++);
		}
		lua_setfield(L, -2, "monsters");

		lua_rawseti(L, -2, clusterIdx++);
	}

	return 1;
}

int GameFunctions::luaGameFindTeleportsToArea(lua_State* L) {
	// Game.findTeleportsToArea(fromPos, toPos)
	const Position fromPos = Lua::getPosition(L, 1);
	const Position toPos = Lua::getPosition(L, 2);

	const uint16_t minX = std::min(fromPos.x, toPos.x);
	const uint16_t maxX = std::max(fromPos.x, toPos.x);
	const uint16_t minY = std::min(fromPos.y, toPos.y);
	const uint16_t maxY = std::max(fromPos.y, toPos.y);
	const uint8_t minZ = std::min(fromPos.z, toPos.z);
	const uint8_t maxZ = std::max(fromPos.z, toPos.z);

	struct TeleportEntry {
		Position source;
		Position destination;
	};
	std::vector<TeleportEntry> results;

	for (auto &[sectorKey, sector] : g_game().map.getMapSectors()) {
		const uint16_t sectorBaseX = static_cast<uint16_t>((sectorKey & 0xFFFF) * SECTOR_SIZE);
		const uint16_t sectorBaseY = static_cast<uint16_t>((sectorKey >> 16) * SECTOR_SIZE);

		for (uint8_t z = 0; z < MAP_MAX_LAYERS; ++z) {
			auto floor = sector.getFloor(z);
			if (!floor) {
				continue;
			}
			for (uint16_t tx = 0; tx < SECTOR_SIZE; ++tx) {
				for (uint16_t ty = 0; ty < SECTOR_SIZE; ++ty) {
					auto tile = floor->getTile(sectorBaseX + tx, sectorBaseY + ty);
					if (!tile || !tile->hasFlag(TILESTATE_TELEPORT)) {
						continue;
					}
					auto teleport = tile->getTeleportItem();
					if (!teleport) {
						continue;
					}
					const Position &destPos = teleport->getDestPos();
					if (destPos.x >= minX && destPos.x <= maxX
						&& destPos.y >= minY && destPos.y <= maxY
						&& destPos.z >= minZ && destPos.z <= maxZ) {
						results.push_back({
							Position(static_cast<uint16_t>(sectorBaseX + tx), static_cast<uint16_t>(sectorBaseY + ty), z),
							destPos });
					}
				}
			}
		}
	}

	lua_createtable(L, static_cast<int>(results.size()), 0);
	int idx = 1;
	for (const auto &entry : results) {
		lua_createtable(L, 0, 2);

		lua_createtable(L, 0, 3);
		lua_pushnumber(L, entry.source.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, entry.source.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, entry.source.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "source");

		lua_createtable(L, 0, 3);
		lua_pushnumber(L, entry.destination.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, entry.destination.y);
		lua_setfield(L, -2, "y");
		lua_pushnumber(L, entry.destination.z);
		lua_setfield(L, -2, "z");
		lua_setfield(L, -2, "destination");

		lua_rawseti(L, -2, idx++);
	}

	return 1;
}
