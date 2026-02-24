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

#include "game/instances/instance_manager.hpp"

#include "creatures/creature.hpp"
#include "creatures/monsters/monster.hpp"
#include "creatures/monsters/spawns/spawn_monster.hpp"
#include "creatures/players/player.hpp"
#include "game/game.hpp"
#include "game/zones/zone.hpp"
#include "map/spectators.hpp"
#include "lib/logging/log_with_spd_log.hpp"

#include <algorithm>

// ============================================================================
// WorldInstance
// ============================================================================

WorldInstance::WorldInstance(uint32_t id, const std::shared_ptr<Player> &owner) :
	m_id(id),
	m_owner(owner),
	m_creationTime(OTSYS_TIME()) {
}

// ============================================================================
// InstanceManager
// ============================================================================

InstanceManager::InstanceManager() {
	g_logger().info("[InstanceManager] Initialized (max {} instances)", MAX_ACTIVE_INSTANCES);
}

uint32_t InstanceManager::createInstance(const std::shared_ptr<Player> &owner) {
	if (!m_enabled) {
		g_logger().debug("[InstanceManager] Disabled - returning global instance");
		return GLOBAL_INSTANCE_ID;
	}

	if (!canCreateMoreInstances()) {
		g_logger().warn("[InstanceManager] Limit reached ({}) - cannot create new instance", MAX_ACTIVE_INSTANCES);
		return GLOBAL_INSTANCE_ID;
	}

	uint32_t newId = m_nextInstanceId.fetch_add(1);
	auto newInstance = std::make_shared<WorldInstance>(newId, owner);

	{
		std::unique_lock<std::shared_mutex> lock(m_instancesMutex);
		m_instances[newId] = newInstance;
	}

	m_activeCount.fetch_add(1);

	std::string ownerName = owner ? owner->getName() : "none";
	g_logger().info("[InstanceManager] Created instance {} (owner: '{}', active: {})",
		newId, ownerName, m_activeCount.load());

	return newId;
}

bool InstanceManager::destroyInstance(uint32_t instanceId) {
	if (instanceId == GLOBAL_INSTANCE_ID) {
		g_logger().warn("[InstanceManager] Cannot destroy global instance");
		return false;
	}

	{
		std::unique_lock<std::shared_mutex> lock(m_instancesMutex);
		auto it = m_instances.find(instanceId);
		if (it == m_instances.end()) {
			g_logger().warn("[InstanceManager] Instance {} not found", instanceId);
			return false;
		}
		// Stop all spawn timers and remove monsters before erasing
		it->second->clearSpawns();
		m_instances.erase(it);

		// Clean up all player GUID mappings for this instance
		std::erase_if(m_playerGuidToInstance, [instanceId](const auto &pair) {
			return pair.second == instanceId;
		});
	}

	m_activeCount.fetch_sub(1);
	g_logger().info("[InstanceManager] Destroyed instance {} (active: {})", instanceId, m_activeCount.load());
	return true;
}

std::shared_ptr<WorldInstance> InstanceManager::getInstance(uint32_t instanceId) {
	if (instanceId == GLOBAL_INSTANCE_ID) {
		return nullptr;
	}

	std::shared_lock<std::shared_mutex> lock(m_instancesMutex);
	auto it = m_instances.find(instanceId);
	return (it != m_instances.end()) ? it->second : nullptr;
}

bool InstanceManager::instanceExists(uint32_t instanceId) const {
	if (instanceId == GLOBAL_INSTANCE_ID) {
		return true;
	}

	std::shared_lock<std::shared_mutex> lock(m_instancesMutex);
	return m_instances.find(instanceId) != m_instances.end();
}

void InstanceManager::movePlayerToInstance(const std::shared_ptr<Player> &player, uint32_t targetInstanceId) {
	if (!player) {
		return;
	}

	uint32_t currentInstanceId = player->getInstanceID();
	if (currentInstanceId == targetInstanceId) {
		return;
	}

	g_logger().info("[Instance] Player '{}': {} -> {}", player->getName(), currentInstanceId, targetInstanceId);

	// Block creature movement packets during transition to prevent race conditions
	// (creature moves queued before switch but sent after cause "no thing at pos" errors)
	// Reset happens on player's first movement in sendMoveCreature (protocolgame.cpp)
	player->setNeedsContextRefresh(true);

	Position originalPos = player->getPosition();
	auto playerTile = player->getTile();
	if (!playerTile) {
		return;
	}

	// ========================================================================
	// PHASE 1: Collect all information BEFORE any changes
	// ========================================================================

	// 1a. Find players in old context (they need to stop seeing the switching player)
	//     and players in new context (they need to start seeing the switching player)
	struct SpectatorRemoveInfo {
		std::shared_ptr<Player> spectator;
		int32_t stackpos;
	};
	std::vector<SpectatorRemoveInfo> oldInstancePlayerRemoves;
	std::vector<std::shared_ptr<Player>> newInstanceSpectators;

	auto allPlayerSpectators = Spectators().find<Player>(originalPos, true);
	for (const auto &spectator : allPlayerSpectators) {
		if (spectator == player) {
			continue;
		}
		auto specPlayer = spectator->getPlayer();
		if (!specPlayer) {
			continue;
		}

		if (specPlayer->getInstanceID() == currentInstanceId) {
			int32_t stackpos = playerTile->getStackposOfCreature(specPlayer, player);
			oldInstancePlayerRemoves.push_back({ specPlayer, stackpos });
		} else if (specPlayer->getInstanceID() == targetInstanceId) {
			newInstanceSpectators.push_back(specPlayer);
		}
	}

	// 1b. Find ALL creatures visible to the switching player in their current instance
	//     These need to be explicitly removed from the player's CLIENT before switching
	//     Without this, the client keeps old creature sprites cached (causing "clones")
	struct CreatureOnTile {
		Position pos;
		int32_t stackpos;
	};
	std::vector<CreatureOnTile> creaturesToRemoveFromPlayer;

	auto allCreatures = Spectators().find<Creature>(originalPos, true);
	for (const auto &creature : allCreatures) {
		if (creature == player) {
			continue;
		}
		if (!player->canSeeCreature(creature)) {
			continue;
		}

		// Skip creatures visible in ALL instances (e.g. NPCs) - they stay visible after switch
		if (creature->isVisibleToAllInstances()) {
			continue;
		}

		auto creatureTile = creature->getTile();
		if (!creatureTile) {
			continue;
		}

		int32_t stackpos = creatureTile->getStackposOfCreature(player, creature);
		if (stackpos >= 0) {
			creaturesToRemoveFromPlayer.push_back({ creature->getPosition(), stackpos });
		}
	}

	// Sort: same position -> remove highest stackpos first (so lower stackpos stays valid)
	std::sort(creaturesToRemoveFromPlayer.begin(), creaturesToRemoveFromPlayer.end(),
		[](const CreatureOnTile &a, const CreatureOnTile &b) {
			if (a.pos.x != b.pos.x) {
				return a.pos.x < b.pos.x;
			}
			if (a.pos.y != b.pos.y) {
				return a.pos.y < b.pos.y;
			}
			if (a.pos.z != b.pos.z) {
				return a.pos.z < b.pos.z;
			}
			return a.stackpos > b.stackpos; // Same pos: highest stackpos first
		});

	// ========================================================================
	// PHASE 2: Send REMOVE packets BEFORE instance change
	// ========================================================================

	// 2a. Remove all visible creatures from the SWITCHING PLAYER's client
	//     This is the key fix: prevents cached creature sprites ("clones" and "lingering names")
	for (const auto &info : creaturesToRemoveFromPlayer) {
		player->sendRemoveTileThing(info.pos, info.stackpos);
	}

	// 2b. Remove switching player from OLD instance spectators' clients
	for (const auto &info : oldInstancePlayerRemoves) {
		if (info.stackpos >= 0) {
			info.spectator->sendRemoveTileThing(originalPos, info.stackpos);
			info.spectator->sendMagicEffect(originalPos, CONST_ME_POFF);
		}
	}

	// 2c. Pre-calculate the switching player's OWN stackpos AFTER creature removes
	//     but BEFORE instance change
	int32_t playerOwnStackpos = playerTile->getStackposOfCreature(player, player);

	// ========================================================================
	// PHASE 3: Switch instance (server-side only, NO packet to client)
	// ========================================================================
	// KEY INSIGHT: The /ghost command works because it NEVER clears knownCreatureSet
	// or resets m_mapKnown. Creatures stay "known" -> opcode 0x62 (update) -> sprite renders.
	// We just update instance server-side, then use ghost-style remove/appear.
	player->setInstanceID(targetInstanceId);

	// ========================================================================
	// PHASE 4: Rebuild switching player's view (like a teleport, NOT an instance switch)
	// ========================================================================
	// Use the same pattern as a regular teleport in sendMoveCreature:
	// RemoveTileThing(self) -> sendMapDescription
	// The client stays in normal state (m_mapKnown=true), creatures render properly.
	if (playerOwnStackpos >= 0) {
		player->sendRemoveTileThing(originalPos, playerOwnStackpos);
	}
	player->sendMapDescription(originalPos);
	player->sendMagicEffect(originalPos, CONST_ME_TELEPORT);

	// ========================================================================
	// PHASE 5: Make switching player APPEAR for new instance spectators
	// ========================================================================
	// Use EXACTLY the same mechanism as /ghost un-ghost:
	// sendAddCreature(player, position, stackpos, false)
	// NO forgetCreature - creature stays "known" -> 0x62 update -> sprite renders immediately
	for (const auto &specPlayer : newInstanceSpectators) {
		specPlayer->sendCreatureAppear(player, originalPos, false);
		specPlayer->sendMagicEffect(originalPos, CONST_ME_TELEPORT);
	}

	// ========================================================================
	// PHASE 6: Update monster target lists in BOTH old and new instances
	// ========================================================================
	// Old instance: monsters must stop targeting the player (they can't see them anymore).
	// New instance: monsters must discover the player (they just "appeared").
	// Without this, old monsters chase across instances and new monsters ignore the player.
	for (const auto &creature : allCreatures) {
		if (creature == player) {
			continue;
		}
		if (const auto &monster = creature->getMonster()) {
			uint32_t monsterInstance = monster->getInstanceID();
			if (monsterInstance == currentInstanceId) {
				// OLD instance: clear direct references and rebuild target list
				if (monster->getAttackedCreature() == player) {
					monster->setAttackedCreature(nullptr);
				}
				if (monster->getFollowCreature() == player) {
					monster->setFollowCreature(nullptr);
				}
				monster->updateTargetList();
			} else if (monsterInstance == targetInstanceId) {
				// NEW instance: rebuild target list so the player is discovered
				monster->updateTargetList();
			}
		}
	}

	// Summons also change instance
	for (const auto &summon : player->getSummons()) {
		summon->setInstanceID(targetInstanceId);
	}

	// ========================================================================
	// PHASE 7: Clear the context refresh guard
	// ========================================================================
	// The needsContextRefresh flag blocks creature movement packets during transition.
	// Now that all phases are complete and the player's view is fully rebuilt,
	// we can safely clear it so creature movements render immediately.
	player->setNeedsContextRefresh(false);
}

// ============================================================================
// WorldInstance - Spawn Management
// ============================================================================

void WorldInstance::clearSpawns() {
	for (const auto &spawn : m_spawns) {
		spawn->stopEvent();
		spawn->removeMonsters();
	}
	m_spawns.clear();
}

// ============================================================================
// InstanceManager - Player GUID Tracking
// ============================================================================

void InstanceManager::trackPlayerInstance(uint32_t playerGuid, uint32_t instanceId) {
	std::unique_lock<std::shared_mutex> lock(m_instancesMutex);
	m_playerGuidToInstance[playerGuid] = instanceId;
}

void InstanceManager::untrackPlayerInstance(uint32_t playerGuid) {
	std::unique_lock<std::shared_mutex> lock(m_instancesMutex);
	m_playerGuidToInstance.erase(playerGuid);
}

uint32_t InstanceManager::findInstanceByPlayerGuid(uint32_t playerGuid) {
	std::unique_lock<std::shared_mutex> lock(m_instancesMutex);
	auto it = m_playerGuidToInstance.find(playerGuid);
	if (it == m_playerGuidToInstance.end()) {
		return 0;
	}
	uint32_t instanceId = it->second;
	if (m_instances.find(instanceId) == m_instances.end()) {
		m_playerGuidToInstance.erase(it);
		return 0;
	}
	return instanceId;
}

// ============================================================================
// InstanceManager - Populate from Map
// ============================================================================

uint32_t InstanceManager::populateFromMap(uint32_t instanceId, const Position &fromPos, uint16_t width, uint16_t height) {
	auto instance = getInstance(instanceId);
	if (!instance) {
		g_logger().warn("[InstanceManager::populateFromMap] Instance {} not found", instanceId);
		return 0;
	}

	// Define the area bounds (all Z levels)
	const uint16_t toX = fromPos.x + width;
	const uint16_t toY = fromPos.y + height;

	uint32_t spawnCount = 0;

	// Iterate all global spawn areas and clone those whose center is within the XY area (any Z)
	for (const auto &globalSpawn : g_game().map.spawnsMonster.getspawnMonsterList()) {
		const auto &center = globalSpawn->getCenterPos();
		if (center.x >= fromPos.x && center.x < toX
			&& center.y >= fromPos.y && center.y < toY) {
			auto clone = globalSpawn->cloneForInstance(instanceId);
			clone->startup();
			instance->addSpawn(clone);
			spawnCount++;
		}
	}

	// Also check custom map spawns
	for (int i = 0; i < 50; i++) {
		for (const auto &globalSpawn : g_game().map.spawnsMonsterCustomMaps[i].getspawnMonsterList()) {
			const auto &center = globalSpawn->getCenterPos();
			if (center.x >= fromPos.x && center.x < toX
				&& center.y >= fromPos.y && center.y < toY) {
				auto clone = globalSpawn->cloneForInstance(instanceId);
				clone->startup();
				instance->addSpawn(clone);
				spawnCount++;
			}
		}
	}

	g_logger().info("[InstanceManager::populateFromMap] Instance {} populated with {} spawn areas from ({},{},{}) {}x{}",
		instanceId, spawnCount, fromPos.x, fromPos.y, fromPos.z, width, height);

	return spawnCount;
}

// ============================================================================
// InstanceManager - Populate from Zone (flood-fill based)
// ============================================================================

uint32_t InstanceManager::populateFromZone(uint32_t instanceId, const std::shared_ptr<Zone> &zone) {
	auto instance = getInstance(instanceId);
	if (!instance) {
		g_logger().warn("[InstanceManager::populateFromZone] Instance {} not found", instanceId);
		return 0;
	}
	if (!zone) {
		g_logger().warn("[InstanceManager::populateFromZone] Zone is null for instance {}", instanceId);
		return 0;
	}

	uint32_t spawnCount = 0;

	auto cloneIfInZone = [&](std::vector<std::shared_ptr<SpawnMonster>> &spawnList) {
		for (const auto &globalSpawn : spawnList) {
			const auto &center = globalSpawn->getCenterPos();
			bool inZone = zone->contains(center);
			if (!inZone) {
				for (const auto &[id, sb] : globalSpawn->getSpawnMonsterMap()) {
					if (zone->contains(sb.pos)) {
						inZone = true;
						break;
					}
				}
			}
			if (inZone) {
				auto clone = globalSpawn->cloneForInstance(instanceId);
				clone->startup();
				instance->addSpawn(clone);
				spawnCount++;
			}
		}
	};

	cloneIfInZone(g_game().map.spawnsMonster.getspawnMonsterList());
	for (int i = 0; i < 50; i++) {
		cloneIfInZone(g_game().map.spawnsMonsterCustomMaps[i].getspawnMonsterList());
	}

	g_logger().info("[InstanceManager::populateFromZone] Instance {} populated with {} spawns from zone '{}'",
		instanceId, spawnCount, zone->getName());

	return spawnCount;
}
