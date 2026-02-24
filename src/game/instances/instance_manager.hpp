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

#pragma once

#include <memory>
#include <unordered_map>
#include <shared_mutex>
#include <atomic>

class Player;
class Creature;
class SpawnMonster;
class Zone;
struct Position;

/**
 * @brief Represents an isolated world instance for instanced hunts.
 *
 * Instance ID 1 = global shared world (default for all creatures)
 * Instance ID 2+ = private instances
 */
class WorldInstance {
public:
	explicit WorldInstance(uint32_t id, const std::shared_ptr<Player> &owner = nullptr);
	~WorldInstance() = default;

	uint32_t getId() const {
		return m_id;
	}
	std::shared_ptr<Player> getOwner() const {
		return m_owner.lock();
	}

	void addSpawn(const std::shared_ptr<SpawnMonster> &spawn) {
		m_spawns.push_back(spawn);
	}
	const std::vector<std::shared_ptr<SpawnMonster>> &getSpawns() const {
		return m_spawns;
	}
	void clearSpawns();

private:
	uint32_t m_id;
	std::weak_ptr<Player> m_owner;
	int64_t m_creationTime;
	std::vector<std::shared_ptr<SpawnMonster>> m_spawns;
};

/**
 * @brief Manages all world instances (Singleton).
 *
 * Handles creation, destruction, and player transitions between instances.
 * Uses ghost-style context switching (proven in Canary POC) to avoid
 * custom packets and keep the client in normal operating state.
 */
class InstanceManager {
public:
	InstanceManager();
	~InstanceManager() = default;

	// Core operations
	uint32_t createInstance(const std::shared_ptr<Player> &owner = nullptr);
	bool destroyInstance(uint32_t instanceId);
	std::shared_ptr<WorldInstance> getInstance(uint32_t instanceId);
	bool instanceExists(uint32_t instanceId) const;

	// Player management - Ghost-style 5-phase switching
	void movePlayerToInstance(const std::shared_ptr<Player> &player, uint32_t targetInstanceId);

	// Spawn management - clone global map spawns into an instance
	uint32_t populateFromMap(uint32_t instanceId, const Position &fromPos, uint16_t width, uint16_t height);
	uint32_t populateFromZone(uint32_t instanceId, const std::shared_ptr<Zone> &zone);

	// Player GUID tracking for reconnection after relog
	void trackPlayerInstance(uint32_t playerGuid, uint32_t instanceId);
	void untrackPlayerInstance(uint32_t playerGuid);
	uint32_t findInstanceByPlayerGuid(uint32_t playerGuid);

	// System info
	bool isEnabled() const {
		return m_enabled;
	}
	void setEnabled(bool enabled) {
		m_enabled = enabled;
	}
	size_t getActiveInstanceCount() const {
		return m_activeCount.load();
	}
	bool canCreateMoreInstances() const {
		return m_activeCount.load() < MAX_ACTIVE_INSTANCES;
	}

private:
	static constexpr size_t MAX_ACTIVE_INSTANCES = 2200;
	static constexpr uint32_t GLOBAL_INSTANCE_ID = 1;

	bool m_enabled = true;
	std::atomic<uint32_t> m_nextInstanceId { 2 }; // Start at 2, 1 is global
	std::atomic<size_t> m_activeCount { 0 };

	mutable std::shared_mutex m_instancesMutex;
	std::unordered_map<uint32_t, std::shared_ptr<WorldInstance>> m_instances;
	std::unordered_map<uint32_t, uint32_t> m_playerGuidToInstance;
};

// Global singleton accessor
inline InstanceManager &g_instanceManager() {
	static InstanceManager instance;
	return instance;
}
