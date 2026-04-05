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

#include "game/zones/zone.hpp"

#include "game/game.hpp"
#include "creatures/monsters/monster.hpp"
#include "creatures/monsters/spawns/spawn_monster.hpp"
#include "creatures/npcs/npc.hpp"
#include "creatures/players/player.hpp"
#include "utils/pugicast.hpp"
#include "kv/kv.hpp"
#include "game/movement/teleport.hpp"

#include <queue>

phmap::parallel_flat_hash_map<std::string, std::shared_ptr<Zone>> Zone::zones = {};
phmap::parallel_flat_hash_map<uint32_t, std::shared_ptr<Zone>> Zone::zonesByID = {};
const static std::shared_ptr<Zone> nullZone = nullptr;

std::shared_ptr<Zone> Zone::addZone(const std::string &name, uint32_t zoneID /* = 0 */) {
	if (name == "default") {
		g_logger().error("Zone name {} is reserved", name);
		return nullZone;
	}
	if (zoneID != 0 && zonesByID.contains(zoneID)) {
		g_logger().trace("[Zone::addZone] Found with ID {} while adding {}, linking them together...", zoneID, name);
		auto zone = zonesByID[zoneID];
		zone->name = name;
		zones[name] = zone;
		return zone;
	}

	if (zones[name]) {
		g_logger().error("Zone {} already exists", name);
		return nullZone;
	}
	zones[name] = std::make_shared<Zone>(name, zoneID);
	if (zoneID != 0) {
		zonesByID[zoneID] = zones[name];
	}
	return zones[name];
}

void Zone::addArea(Area area) {
	for (const auto &pos : area) {
		addPosition(pos);
	}
	refresh();
}

void Zone::subtractArea(Area area) {
	for (const auto &pos : area) {
		removePosition(pos);
	}
	refresh();
}

Position computeFloorchangeDestination(const std::shared_ptr<Tile> &tile) {
	if (!tile) {
		return {};
	}
	auto pos = tile->getPosition();

	if (tile->hasFlag(TILESTATE_FLOORCHANGE_DOWN)) {
		Position dest(pos.x, pos.y, pos.z + 1);
		auto destTile = g_game().map.getTile(dest.x, dest.y, dest.z);
		if (destTile) {
			if (destTile->hasFlag(TILESTATE_FLOORCHANGE_NORTH)) {
				dest.y += 1;
			} else if (destTile->hasFlag(TILESTATE_FLOORCHANGE_SOUTH)) {
				dest.y -= 1;
			} else if (destTile->hasFlag(TILESTATE_FLOORCHANGE_EAST)) {
				dest.x -= 1;
			} else if (destTile->hasFlag(TILESTATE_FLOORCHANGE_WEST)) {
				dest.x += 1;
			} else if (destTile->hasFlag(TILESTATE_FLOORCHANGE_SOUTH_ALT)) {
				dest.y -= 2;
			} else if (destTile->hasFlag(TILESTATE_FLOORCHANGE_EAST_ALT)) {
				dest.x -= 2;
			}
		}
		return dest;
	}

	if (tile->hasFlag(TILESTATE_FLOORCHANGE)) {
		Position dest(pos.x, pos.y, pos.z - 1);
		if (tile->hasFlag(TILESTATE_FLOORCHANGE_NORTH)) {
			dest.y -= 1;
		} else if (tile->hasFlag(TILESTATE_FLOORCHANGE_SOUTH)) {
			dest.y += 1;
		} else if (tile->hasFlag(TILESTATE_FLOORCHANGE_EAST)) {
			dest.x += 1;
		} else if (tile->hasFlag(TILESTATE_FLOORCHANGE_WEST)) {
			dest.x -= 1;
		} else if (tile->hasFlag(TILESTATE_FLOORCHANGE_SOUTH_ALT)) {
			dest.y += 2;
		} else if (tile->hasFlag(TILESTATE_FLOORCHANGE_EAST_ALT)) {
			dest.x += 2;
		}
		return dest;
	}
	return {};
}

FloodFillResult Zone::buildFromFloodFill(const Position &startPos, uint32_t maxTiles, uint32_t maxDistance) {
	Benchmark bm;
	FloodFillResult result;
	result.bboxMin = Position(std::numeric_limits<uint16_t>::max(), std::numeric_limits<uint16_t>::max(), 15);
	result.bboxMax = Position(0, 0, 0);

	auto startTile = g_game().map.getTile(startPos.x, startPos.y, startPos.z);
	if (!startTile) {
		g_logger().warn("[Zone::buildFromFloodFill] No tile at start position {}", startPos.toString());
		return result;
	}

	// Clear any existing positions so repeated calls don't accumulate stale data
	positions.clear();

	std::unordered_set<Position> visited;
	std::queue<Position> queue;
	queue.push(startPos);
	visited.insert(startPos);

	// Chebyshev distance cap: prevents BFS from crossing connected-but-unrelated cave
	// systems at the same z-level (e.g. Port Hope z=8 connected to Venore z=8 ~1200 tiles away).
	const int distCap = static_cast<int>(maxDistance);
	const int sx = static_cast<int>(startPos.x);
	const int sy = static_cast<int>(startPos.y);

	while (!queue.empty() && visited.size() <= maxTiles) {
		auto current = queue.front();
		queue.pop();

		auto tile = g_game().map.getTile(current.x, current.y, current.z);
		if (!tile) {
			continue;
		}

		addPosition(current);
		result.tilesAdded++;
		result.zLevels.insert(current.z);

		result.bboxMin.x = std::min(result.bboxMin.x, current.x);
		result.bboxMin.y = std::min(result.bboxMin.y, current.y);
		result.bboxMin.z = std::min(result.bboxMin.z, current.z);
		result.bboxMax.x = std::max(result.bboxMax.x, current.x);
		result.bboxMax.y = std::max(result.bboxMax.y, current.y);
		result.bboxMax.z = std::max(result.bboxMax.z, current.z);

		// Floor changes are NOT followed. The z-level of the seed is the only z-level
		// this function maps. Cross-z connections (stairs, holes) are handled by the
		// Lua expansion loop via registered script teleports — those seeds are passed
		// explicitly to expandFromFloodFill for each connected section.
		// Following floor changes here caused the BFS to reach z=9, walk the entire
		// connected underground (which spans the whole map), and include Venore/Farmine.

		if (tile->hasFlag(TILESTATE_TELEPORT)) {
			auto teleport = tile->getTeleportItem();
			if (teleport) {
				const auto &tpDest = teleport->getDestPos();
				// Same z-level only + distance guard: native teleport items that send the
				// player to a different z-level or far away are not part of this cave section.
				if (tpDest.x != 0 && !visited.count(tpDest)
					&& tpDest.z == startPos.z
					&& std::abs(static_cast<int>(tpDest.x) - sx) <= distCap
					&& std::abs(static_cast<int>(tpDest.y) - sy) <= distCap) {
					auto tpDestTile = g_game().map.getTile(tpDest.x, tpDest.y, tpDest.z);
					if (tpDestTile && !tpDestTile->hasFlag(TILESTATE_PROTECTIONZONE)) {
						visited.insert(tpDest);
						queue.push(tpDest);
					}
				}
			}
		}

		// Cardinal + diagonal (8-neighbor). The game engine (Map::getPathMatching,
		// Game::internalMoveCreature) does not check adjacent cardinal tiles for
		// diagonal movement — only the destination tile matters. We match that
		// behavior here. Wall-crossing through void is prevented by the null-tile
		// check; BLOCKSOLID walls and PZ tiles stop expansion as before.
		static const int dx[] = { -1, 1, 0, 0, -1, -1, 1, 1 };
		static const int dy[] = { 0, 0, -1, 1, -1, 1, -1, 1 };
		for (int i = 0; i < 8; i++) {
			Position neighbor(current.x + dx[i], current.y + dy[i], current.z);
			if (visited.count(neighbor)) {
				continue;
			}
			if (std::abs(static_cast<int>(neighbor.x) - sx) > distCap
				|| std::abs(static_cast<int>(neighbor.y) - sy) > distCap) {
				continue;
			}
			auto neighborTile = g_game().map.getTile(neighbor.x, neighbor.y, neighbor.z);
			if (!neighborTile) {
				continue;
			}
			if (neighborTile->hasProperty(CONST_PROP_BLOCKSOLID) && !neighborTile->hasFlag(TILESTATE_FLOORCHANGE)) {
				continue;
			}
			if (neighborTile->hasFlag(TILESTATE_PROTECTIONZONE)) {
				continue;
			}
			visited.insert(neighbor);
			queue.push(neighbor);
		}
	}

	// Detect entry tiles: floor-change tiles whose destination is OUTSIDE the zone,
	// but only if the destination has a reverse path back into the zone (bidirectional entry).
	for (const auto &pos : positions) {
		auto tile = g_game().map.getTile(pos.x, pos.y, pos.z);
		if (!tile || !tile->hasFlag(TILESTATE_FLOORCHANGE)) {
			continue;
		}
		auto dest = computeFloorchangeDestination(tile);
		if (dest.x == 0 || positions.count(dest)) {
			continue;
		}
		auto destTile = g_game().map.getTile(dest.x, dest.y, dest.z);
		if (!destTile) {
			continue;
		}
		bool hasReverse = false;
		if (destTile->hasFlag(TILESTATE_FLOORCHANGE_DOWN) || destTile->hasFlag(TILESTATE_FLOORCHANGE)) {
			auto reverseDest = computeFloorchangeDestination(destTile);
			if (reverseDest.x != 0 && positions.count(reverseDest)) {
				hasReverse = true;
			}
		}
		if (!hasReverse) {
			static const int sdx[] = { -1, 1, 0, 0 };
			static const int sdy[] = { 0, 0, -1, 1 };
			for (int i = 0; i < 4 && !hasReverse; i++) {
				auto adjTile = g_game().map.getTile(dest.x + sdx[i], dest.y + sdy[i], dest.z);
				if (adjTile && (adjTile->hasFlag(TILESTATE_FLOORCHANGE_DOWN) || adjTile->hasFlag(TILESTATE_FLOORCHANGE))) {
					auto revDest = computeFloorchangeDestination(adjTile);
					if (revDest.x != 0 && positions.count(revDest)) {
						hasReverse = true;
					}
				}
			}
		}
		if (hasReverse) {
			result.entryTiles.push_back(dest);
		}
	}

	// Check tiles one z-level above/below zone tiles for vertical entries
	for (uint8_t z : result.zLevels) {
		if (z > 0) {
			uint8_t aboveZ = z - 1;
			if (!result.zLevels.count(aboveZ)) {
				for (const auto &pos : positions) {
					if (pos.z != z) {
						continue;
					}
					auto aboveTile = g_game().map.getTile(pos.x, pos.y, aboveZ);
					if (aboveTile && aboveTile->hasFlag(TILESTATE_FLOORCHANGE_DOWN)) {
						auto dest = computeFloorchangeDestination(aboveTile);
						if (dest.x != 0 && positions.count(dest)) {
							result.entryTiles.push_back(Position(pos.x, pos.y, aboveZ));
						}
					}
				}
			}
		}
		if (z < 15) {
			uint8_t belowZ = z + 1;
			if (!result.zLevels.count(belowZ)) {
				for (const auto &pos : positions) {
					if (pos.z != z) {
						continue;
					}
					auto belowTile = g_game().map.getTile(pos.x, pos.y, belowZ);
					if (belowTile && belowTile->hasFlag(TILESTATE_FLOORCHANGE) && !belowTile->hasFlag(TILESTATE_FLOORCHANGE_DOWN)) {
						auto dest = computeFloorchangeDestination(belowTile);
						if (dest.x != 0 && positions.count(dest)) {
							result.entryTiles.push_back(Position(pos.x, pos.y, belowZ));
						}
					}
				}
			}
		}
	}

	// Deduplicate entries: cluster entries within 2 tiles on the same z-level
	{
		std::vector<Position> deduped;
		for (const auto &entry : result.entryTiles) {
			bool tooClose = false;
			for (const auto &kept : deduped) {
				if (entry.z == kept.z
					&& std::abs(static_cast<int>(entry.x) - static_cast<int>(kept.x)) <= 2
					&& std::abs(static_cast<int>(entry.y) - static_cast<int>(kept.y)) <= 2) {
					tooClose = true;
					break;
				}
			}
			if (!tooClose) {
				deduped.push_back(entry);
			}
		}
		result.entryTiles = std::move(deduped);
	}

	// Classify teleports: scan zone tiles for teleport items
	for (const auto &pos : positions) {
		auto tile = g_game().map.getTile(pos.x, pos.y, pos.z);
		if (!tile || !tile->hasFlag(TILESTATE_TELEPORT)) {
			continue;
		}
		auto teleport = tile->getTeleportItem();
		if (!teleport) {
			continue;
		}
		const auto &tpDest = teleport->getDestPos();
		if (tpDest.x == 0) {
			continue;
		}
		if (positions.count(tpDest)) {
			result.internalTeleports.emplace_back(pos, tpDest);
		} else {
			result.exitTeleports.emplace_back(pos, tpDest);
		}
	}

	// Find external teleports leading INTO the zone (teleport entries)
	{
		uint16_t minX = std::numeric_limits<uint16_t>::max(), maxX = 0;
		uint16_t minY = std::numeric_limits<uint16_t>::max(), maxY = 0;
		uint8_t minZ = 15, maxZ = 0;
		for (const auto &pos : positions) {
			minX = std::min(minX, pos.x);
			maxX = std::max(maxX, pos.x);
			minY = std::min(minY, pos.y);
			maxY = std::max(maxY, pos.y);
			minZ = std::min(minZ, pos.z);
			maxZ = std::max(maxZ, pos.z);
		}
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
						auto t = floor->getTile(sectorBaseX + tx, sectorBaseY + ty);
						if (!t || !t->hasFlag(TILESTATE_TELEPORT)) {
							continue;
						}
						Position srcPos(static_cast<uint16_t>(sectorBaseX + tx), static_cast<uint16_t>(sectorBaseY + ty), z);
						if (positions.count(srcPos)) {
							continue;
						}
						auto tp = t->getTeleportItem();
						if (!tp) {
							continue;
						}
						const auto &dest = tp->getDestPos();
						if (dest.x >= minX && dest.x <= maxX
							&& dest.y >= minY && dest.y <= maxY
							&& dest.z >= minZ && dest.z <= maxZ
							&& positions.count(dest)) {
							result.teleportEntries.emplace_back(srcPos, dest);
						}
					}
				}
			}
		}
	}

	// Count spawns that overlap with the flood-filled zone (center OR any individual spawn position)
	auto countSpawnsInZone = [&](std::vector<std::shared_ptr<SpawnMonster>> &spawnList) {
		for (const auto &spawn : spawnList) {
			if (positions.count(spawn->getCenterPos())) {
				result.spawnCount++;
				continue;
			}
			for (const auto &[id, sb] : spawn->getSpawnMonsterMap()) {
				if (positions.count(sb.pos)) {
					result.spawnCount++;
					break;
				}
			}
		}
	};
	countSpawnsInZone(g_game().map.spawnsMonster.getspawnMonsterList());
	for (int i = 0; i < 50; i++) {
		countSpawnsInZone(g_game().map.spawnsMonsterCustomMaps[i].getspawnMonsterList());
	}

	refresh();

	auto duration = bm.duration();

	std::map<uint8_t, uint32_t> tilesPerZ;
	for (const auto &pos : positions) {
		tilesPerZ[pos.z]++;
	}
	for (const auto &[z, count] : tilesPerZ) {
		g_logger().info("[Zone::buildFromFloodFill] z={}: {} tiles", z, count);
	}

	g_logger().info("[Zone::buildFromFloodFill] Zone '{}' built from {} with {} tiles, {} z-levels, {} entries, {} spawns in {}ms",
		name, startPos.toString(), result.tilesAdded, result.zLevels.size(), result.entryTiles.size(), result.spawnCount, duration);

	return result;
}

uint32_t Zone::expandFromFloodFill(const std::vector<Position> &startPositions, uint32_t maxTiles) {
	if (startPositions.empty()) {
		return 0;
	}

	// Distance limiting is the caller's responsibility (Lua expansion loop filters
	// destinations to seedPos ± maxDistance before calling this function).
	// This function trusts the seeds it receives and simply flood-fills from them,
	// bounded only by maxTiles and the map's natural walls/PZ boundaries.

	std::unordered_set<Position> visited;
	for (const auto &pos : positions) {
		visited.insert(pos);
	}

	std::queue<Position> queue;
	for (const auto &pos : startPositions) {
		if (!visited.count(pos)) {
			queue.push(pos);
			visited.insert(pos);
		}
	}

	uint32_t tilesAdded = 0;

	while (!queue.empty() && tilesAdded < maxTiles) {
		Position current = queue.front();
		queue.pop();

		auto tile = g_game().map.getTile(current.x, current.y, current.z);
		if (!tile) {
			continue;
		}

		positions.emplace(current);
		tilesAdded++;

		// Cardinal + diagonal (8-neighbor), matching game engine behavior.
		static const int dx[] = { -1, 1, 0, 0, -1, -1, 1, 1 };
		static const int dy[] = { 0, 0, -1, 1, -1, 1, -1, 1 };
		for (int i = 0; i < 8; i++) {
			Position neighbor(current.x + dx[i], current.y + dy[i], current.z);
			if (visited.count(neighbor)) {
				continue;
			}
			auto neighborTile = g_game().map.getTile(neighbor.x, neighbor.y, neighbor.z);
			if (!neighborTile) {
				continue;
			}
			if (neighborTile->hasProperty(CONST_PROP_BLOCKSOLID) && !neighborTile->hasFlag(TILESTATE_FLOORCHANGE)) {
				continue;
			}
			if (neighborTile->hasFlag(TILESTATE_PROTECTIONZONE)) {
				continue;
			}
			visited.insert(neighbor);
			queue.push(neighbor);
		}
	}

	refresh();
	return tilesAdded;
}

bool Zone::contains(const Position &pos) const {
	return positions.contains(pos);
}

Position Zone::getRemoveDestination(const std::shared_ptr<Creature> &creature /* = nullptr */) const {
	if (!creature || !creature->getPlayer()) {
		return Position();
	}
	if (removeDestination != Position()) {
		return removeDestination;
	}
	if (creature->getPlayer()) {
		return creature->getPlayer()->getTown()->getTemplePosition();
	}
	return Position();
}

std::shared_ptr<Zone> Zone::getZone(const std::string &name) {
	return zones[name];
}

std::shared_ptr<Zone> Zone::getZone(uint32_t zoneID) {
	if (zoneID == 0) {
		return nullZone;
	}
	if (zonesByID.contains(zoneID)) {
		return zonesByID[zoneID];
	}
	auto zone = std::make_shared<Zone>(zoneID);
	zonesByID[zoneID] = zone;
	return zone;
}

std::vector<Position> Zone::getPositions() const {
	std::vector<Position> result;
	for (const auto &pos : positions) {
		result.push_back(pos);
	}
	return result;
}

std::vector<std::shared_ptr<Creature>> Zone::getCreatures() {
	return weak::lock(creaturesCache);
}

std::vector<std::shared_ptr<Player>> Zone::getPlayers() {
	return weak::lock(playersCache);
}

std::vector<std::shared_ptr<Monster>> Zone::getMonsters() {
	return weak::lock(monstersCache);
}

std::vector<std::shared_ptr<Npc>> Zone::getNpcs() {
	return weak::lock(npcsCache);
}

std::vector<std::shared_ptr<Item>> Zone::getItems() {
	return weak::lock(itemsCache);
}

void Zone::removePlayers() {
	for (const auto &player : getPlayers()) {
		g_game().internalTeleport(player, getRemoveDestination(player));
		// Remove icon from player (soul war quest)
		if (player->hasIcon("goshnars-hatred-damage")) {
			player->removeIcon("goshnars-hatred-damage");
		}
	}
}

void Zone::removeMonsters() {
	for (const auto &monster : getMonsters()) {
		g_game().removeCreature(monster->getCreature());
	}
}

void Zone::removeNpcs() {
	for (const auto &npc : getNpcs()) {
		g_game().removeCreature(npc->getCreature());
	}
}

void Zone::clearZones() {
	for (const auto &[_, zone] : zones) {
		// do not clear zones loaded from the map (id > 0)
		if (!zone || zone->isStatic()) {
			continue;
		}
		zone->refresh();
	}
	zones.clear();
	for (const auto &[_, zone] : zonesByID) {
		zones[zone->name] = zone;
	}
}

bool Zone::removeZone(const std::string &name) {
	auto it = zones.find(name);
	if (it == zones.end()) {
		return false;
	}
	auto zone = it->second;
	if (zone && zone->isStatic()) {
		return false;
	}
	if (zone) {
		zone->positions.clear();
		zone->refresh();
	}
	zones.erase(it);
	return true;
}

std::vector<std::shared_ptr<Zone>> Zone::getZones(const Position position) {
	Benchmark bm_getZones;
	std::vector<std::shared_ptr<Zone>> result;
	for (const auto &[_, zone] : zones) {
		if (zone && zone->contains(position)) {
			result.push_back(zone);
		}
	}
	auto duration = bm_getZones.duration();
	if (duration > 100) {
		g_logger().warn("Listed {} zones for position {} in {} milliseconds", result.size(), position.toString(), duration);
	}
	return result;
}

std::vector<std::shared_ptr<Zone>> Zone::getZones() {
	Benchmark bm_getZones;
	std::vector<std::shared_ptr<Zone>> result;
	for (const auto &[_, zone] : zones) {
		if (zone) {
			result.push_back(zone);
		}
	}
	auto duration = bm_getZones.duration();
	if (duration > 100) {
		g_logger().warn("Listed {} zones in {} milliseconds", result.size(), duration);
	}
	return result;
}

void Zone::creatureAdded(const std::shared_ptr<Creature> &creature) {
	if (!creature) {
		return;
	}

	if (const auto &player = creature->getPlayer()) {
		playersCache.insert(player);
	} else if (const auto &monster = creature->getMonster()) {
		monstersCache.insert(monster);
	} else if (const auto &npc = creature->getNpc()) {
		npcsCache.insert(npc);
	}

	creaturesCache.insert(creature);
}

void Zone::creatureRemoved(const std::shared_ptr<Creature> &creature) {
	if (!creature) {
		return;
	}
	creaturesCache.erase(creature);
	playersCache.erase(creature->getPlayer());
	monstersCache.erase(creature->getMonster());
	npcsCache.erase(creature->getNpc());
}

void Zone::thingAdded(const std::shared_ptr<Thing> &thing) {
	if (!thing) {
		return;
	}

	if (const auto &item = thing->getItem()) {
		itemAdded(item);
	} else if (const auto &creature = thing->getCreature()) {
		creatureAdded(creature);
	}
}

void Zone::itemAdded(const std::shared_ptr<Item> &item) {
	if (!item) {
		return;
	}
	itemsCache.insert(item);
}

void Zone::itemRemoved(const std::shared_ptr<Item> &item) {
	if (!item) {
		return;
	}
	itemsCache.erase(item);
}

void Zone::refresh() {
	Benchmark bm_refresh;
	creaturesCache.clear();
	monstersCache.clear();
	npcsCache.clear();
	playersCache.clear();
	itemsCache.clear();

	for (const auto &position : getPositions()) {
		g_game().map.refreshZones(position);
	}
	g_logger().trace("Refreshed zone '{}' in {} milliseconds", name, bm_refresh.duration());
}

void Zone::setMonsterVariant(const std::string &variant) {
	monsterVariant = variant;
	g_logger().debug("Zone {} monster variant set to {}", name, variant);
	for (const auto &spawnMonster : g_game().map.spawnsMonster.getspawnMonsterList()) {
		if (!contains(spawnMonster->getCenterPos())) {
			continue;
		}
		spawnMonster->setMonsterVariant(variant);
	}

	removeMonsters();
}

bool Zone::loadFromXML(const std::string &fileName, uint16_t shiftID /* = 0 */) {
	pugi::xml_document doc;
	g_logger().debug("Loading zones from {}", fileName);
	pugi::xml_parse_result result = doc.load_file(fileName.c_str());
	if (!result) {
		printXMLError(__FUNCTION__, fileName, result);
		return false;
	}

	for (auto zoneNode : doc.child("zones").children()) {
		auto name = zoneNode.attribute("name").value();
		auto zoneId = pugi::cast<uint32_t>(zoneNode.attribute("zoneid").value()) << shiftID;
		addZone(name, zoneId);
	}
	return true;
}
