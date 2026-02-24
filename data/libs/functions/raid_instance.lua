---@class RaidInstance
---@field private name string
---@field private bossName string
---@field private bossPosition Position
---@field private createBoss function
---@field private entryPositions Position[]
---@field private teleportTo Position
---@field private area {from: Position, to: Position}
---@field private exit Position
---@field private maxInstances number
---@field private timeToDefeat number
---@field private timeAfterKill number
---@field private cooldownTime number
---@field private requiredLevel number
---@field private disabled boolean
---@field private alwaysAvailable boolean
---@field private monsters {name: string, pos: Position}[]
---@field private activeInstances table
---@field private groupToInstance table
RaidInstance = {}

--[[
local config = {
	bossName = "Gaz'Haragoth",
	bossPosition = Position(33538, 32381, 12),
	entryPositions = {                              -- stair/tile positions that trigger instance entry
		Position(33509, 32381, 11),
		Position(33510, 32381, 11),
		Position(33511, 32381, 11),
	},
	teleportTo = Position(33538, 32385, 12),        -- where player lands inside the boss room
	specPos = {                                      -- boss room zone area
		from = Position(33520, 32360, 12),
		to = Position(33560, 32400, 12),
	},
	exit = Position(33509, 32382, 11),              -- where players go after timeout/death
	maxInstances = 10,
	timeToDefeat = 20 * 60,                          -- 20 minutes
	timeAfterKill = 60,                              -- 60 seconds after boss dies
	cooldownTime = 20 * 60 * 60,                     -- 20 hours
	requiredLevel = 250,
	alwaysAvailable = false,                         -- if false, only works when raid boss exists globally
	monsters = {},                                   -- additional monsters to spawn
}

local raid = RaidInstance(config)
raid:register()
]]
setmetatable(RaidInstance, {
	---@param self RaidInstance
	---@param config table
	__call = function(self, config)
		if not config.bossName then
			error("RaidInstance: bossName is required")
		end
		return setmetatable({
			name = config.bossName:lower(),
			bossName = config.bossName,
			bossPosition = config.bossPosition,
			createBoss = config.createBoss,
			entryPositions = config.entryPositions or {},
			teleportTo = config.teleportTo,
			area = config.specPos,
			exit = config.exit,
			maxInstances = config.maxInstances or 10,
			timeToDefeat = config.timeToDefeat or (20 * 60),
			timeAfterKill = config.timeAfterKill or 60,
			cooldownTime = config.cooldownTime or (20 * 60 * 60),
			requiredLevel = config.requiredLevel or 0,
			disabled = config.disabled,
			alwaysAvailable = config.alwaysAvailable or false,
			monsters = config.monsters or {},
			activeInstances = {},   -- { [instanceId] = { timeoutEvent, groupKey, createdAt } }
			groupToInstance = {},   -- { [groupKey] = instanceId }
		}, { __index = RaidInstance })
	end,
})

-- ============================================================================
-- Group Key: determines which players share the same instance
-- Party members share instance via leader ID; solo players get their own
-- ============================================================================

---@param player Player
---@return number
function RaidInstance:getGroupKey(player)
	local party = player:getParty()
	if party then
		local leader = party:getLeader()
		if leader then
			return leader:getGuid()
		end
	end
	return player:getGuid()
end

-- ============================================================================
-- Raid active check: looks for the boss alive in the global instance
-- ============================================================================

---@return boolean
function RaidInstance:isRaidActive()
	if self.alwaysAvailable then
		return true
	end
	-- If there are already active instances, the raid is considered active
	-- (boss may have been killed globally but instances are still running)
	if self:countActiveInstances() > 0 then
		return true
	end
	-- Check if the boss exists at its spawn position in the global instance
	if self.bossPosition then
		local tile = Tile(self.bossPosition)
		if tile then
			local creatures = tile:getCreatures()
			if creatures then
				for _, creature in ipairs(creatures) do
					if creature:isMonster() and creature:getName():lower() == self.name and creature:getInstanceId() <= 1 then
						return true
					end
				end
			end
		end
		-- Also search the zone area in case boss moved from spawn position
		local zone = self:getZone()
		zone:refresh()
		for _, monster in ipairs(zone:getMonsters()) do
			if monster:getName():lower() == self.name and monster:getInstanceId() <= 1 then
				return true
			end
		end
	end
	return false
end

-- ============================================================================
-- Instance count
-- ============================================================================

---@return number
function RaidInstance:countActiveInstances()
	local count = 0
	for _ in pairs(self.activeInstances) do
		count = count + 1
	end
	return count
end

-- ============================================================================
-- Cleanup
-- ============================================================================

---@param instanceId number
function RaidInstance:cleanupInstance(instanceId)
	local zone = self:getZone()
	zone:refresh()
	-- 0. Broadcast clear to all players in this instance before cleanup
	InstanceRegistry.broadcastClear(instanceId, zone)
	InstanceRegistry.unregister(instanceId)
	-- 1. Move players back to exit and global instance
	for _, zonePlayer in ipairs(zone:getPlayers()) do
		if zonePlayer:getInstanceId() == instanceId then
			zonePlayer:teleportTo(self.exit)
			zonePlayer:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			if zonePlayer:getInstanceId() > 1 then
				zonePlayer:changeInstance(1)
			end
		end
	end
	-- 2. Remove monsters from this instance
	for _, monster in ipairs(zone:getMonsters()) do
		if monster:getInstanceId() == instanceId then
			monster:remove()
		end
	end
	-- 3. Destroy the instance
	Game.destroyInstance(instanceId)
	-- 4. Clean up tracking
	if self.activeInstances[instanceId] then
		-- Remove group->instance mapping
		local groupKey = self.activeInstances[instanceId].groupKey
		if groupKey and self.groupToInstance[groupKey] == instanceId then
			self.groupToInstance[groupKey] = nil
		end
		if self.activeInstances[instanceId].timeoutEvent then
			stopEvent(self.activeInstances[instanceId].timeoutEvent)
		end
		self.activeInstances[instanceId] = nil
	end
	logger.info("RaidInstance:cleanupInstance - cleaned up instance {} for boss {}", instanceId, self.name)
end

-- ============================================================================
-- Entry handler (called when player steps on entry tile)
-- ============================================================================

---@param player Player
---@return boolean
function RaidInstance:onStepIn(player)
	if not player or not player:isPlayer() then
		return true
	end

	-- If player is already in an active instance for this raid, let them pass normally
	-- This prevents re-triggering when walking over entry tiles while instanced
	local currentInstanceId = player:getInstanceId()
	if currentInstanceId > 1 and self.activeInstances[currentInstanceId] then
		return true
	end

	local monsterName = self.bossName

	-- Check disabled
	if self.disabled then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "This raid boss is temporarily disabled.")
		player:teleportTo(player:getPosition()) -- Cancel stair movement
		return false
	end

	-- Check if the raid is active (boss exists in global instance)
	if not self:isRaidActive() then
		return true -- No raid active: allow normal stair passage
	end

	-- Solo players (no party) pass through to fight the global boss
	local party = player:getParty()
	if not party then
		return true -- No party: normal passage, fight global boss
	end

	-- Check level
	local checkAccountType = player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER
	local isGameTester = player:hasFlag(PlayerFlag_IsGameTester)
	if checkAccountType and not isGameTester and player:getLevel() < self.requiredLevel then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You need to be level " .. self.requiredLevel .. " or higher to face " .. monsterName .. ".")
		player:teleportTo(player:getPosition())
		return false
	end

	-- Reconnection by persistent GUID (tracked in C++ InstanceManager, survives relog)
	local existingByGuid = Game.findInstanceByPlayerGuid(player:getGuid())
	if existingByGuid == 0 then
		existingByGuid = InstanceRegistry.findInstanceByParty(player)
	end
	if existingByGuid and existingByGuid > 0 and self.activeInstances[existingByGuid] then
		logger.info("RaidInstance:onStepIn - player {} reconnecting to instance {} via GUID for boss {}", player:getName(), existingByGuid, self.name)
		player:changeInstance(existingByGuid)
		Game.trackInstancePlayer(player:getGuid(), existingByGuid)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		addEvent(function(instId)
			InstanceRegistry.broadcastUpdate(instId)
		end, 500, existingByGuid)
		return true
	end

	-- Determine group key (party leader GUID)
	local groupKey = self:getGroupKey(player)

	-- Check if this group/party already has an active instance -> rejoin it
	local existingInstanceId = self.groupToInstance[groupKey]
	if existingInstanceId and self.activeInstances[existingInstanceId] then
		logger.info("RaidInstance:onStepIn - player {} rejoining existing instance {} for boss {}", player:getName(), existingInstanceId, self.name)
		player:changeInstance(existingInstanceId)
		Game.trackInstancePlayer(player:getGuid(), existingInstanceId)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		addEvent(function(instId)
			InstanceRegistry.broadcastUpdate(instId)
		end, 500, existingInstanceId)
		return true
	end

	-- No per-player cooldown for raid instances (the raid availability itself is the limiter)

	-- Check max instances
	if self:countActiveInstances() >= self.maxInstances then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Too many groups are fighting " .. monsterName .. " right now. Please try again later.")
		player:teleportTo(player:getPosition())
		return false
	end

	-- === CREATE NEW INSTANCE ===
	local instanceId = Game.createInstance(player)
	if not instanceId or instanceId <= 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Failed to create instance. Please try again later.")
		player:teleportTo(player:getPosition())
		return false
	end
	logger.info("RaidInstance:onStepIn - player {} created instance {} for boss {}", player:getName(), instanceId, self.name)

	-- Spawn boss in the instance
	local bossMonster = nil
	if self.createBoss then
		local result = self.createBoss(instanceId)
		if not result then
			Game.destroyInstance(instanceId)
			return false
		end
		if type(result) ~= "boolean" and result.registerEvent then
			bossMonster = result
		end
	elseif self.bossPosition then
		bossMonster = Game.createInstanceMonster(self.bossName, self.bossPosition, instanceId, true, true)
		if not bossMonster then
			Game.destroyInstance(instanceId)
			return false
		end
	end

	if bossMonster then
		bossMonster:registerEvent("RaidInstanceOnDeath")
	end

	-- Spawn additional monsters
	for _, monsterConfig in pairs(self.monsters) do
		Game.createInstanceMonster(monsterConfig.name, monsterConfig.pos, instanceId, true, true)
	end

	-- Switch player to the new instance (player stays on same tile, no teleport needed)
	player:changeInstance(instanceId)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)

	-- Track instance
	local timeoutEvt = addEvent(function(raidRef, instId)
		raidRef:cleanupInstance(instId)
	end, self.timeToDefeat * 1000, self, instanceId)

	self.activeInstances[instanceId] = {
		timeoutEvent = timeoutEvt,
		groupKey = groupKey,
		createdAt = os.time(),
	}
	self.groupToInstance[groupKey] = instanceId

	-- Track player GUID in C++ for reconnection after relog
	Game.trackInstancePlayer(player:getGuid(), instanceId)

	-- Register in global InstanceRegistry and send UI update to player
	InstanceRegistry.register(instanceId, "raid", self.bossName, self, os.time() + self.timeToDefeat)
	InstanceRegistry.sendUpdate(player)

	return false -- Prevent normal stair movement
end

-- ============================================================================
-- Zone
-- ============================================================================

function RaidInstance:getZone()
	return Zone("raid." .. toKey(self.name))
end

-- ============================================================================
-- Registration
-- ============================================================================

---@return boolean
function RaidInstance:register()
	-- Validate required params
	local missingParams = {}
	if not self.bossName then
		table.insert(missingParams, "bossName")
	end
	if not self.entryPositions or #self.entryPositions == 0 then
		table.insert(missingParams, "entryPositions")
	end
	if not self.teleportTo then
		table.insert(missingParams, "teleportTo")
	end
	if not self.area then
		table.insert(missingParams, "specPos")
	end
	if not self.exit then
		table.insert(missingParams, "exit")
	end
	if #missingParams > 0 then
		logger.error("RaidInstance:register() - boss {} missing parameters: {}", self.name or "unknown", table.concat(missingParams, ", "))
		return false
	end

	-- Setup zone
	local zone = self:getZone()
	zone:addArea(self.area.from, self.area.to)
	zone:blockFamiliars()
	zone:setRemoveDestination(self.exit)

	-- Zone leave event: return player to global when leaving boss area (skip on logout to avoid static clone)
	local raidRef = self
	local zoneEvent = ZoneEvent(zone)
	function zoneEvent.afterLeave(_zone, creature, isLogout)
		if not creature or not creature:isPlayer() then
			return
		end
		local zonePlayer = creature:getPlayer()
		if not zonePlayer or zonePlayer:isRemoved() then
			return
		end
		local instanceId = zonePlayer:getInstanceId()
		if instanceId > 1 and self.activeInstances[instanceId] then
			if not isLogout then
				logger.info("RaidInstance:zoneLeave - player {} left raid zone while in instance {}, returning to global", zonePlayer:getName(), instanceId)
				InstanceRegistry.sendClear(zonePlayer)
				zonePlayer:changeInstance(1)
			end
			-- Check if any players remain in this instance; if not, destroy it (run on both move and logout)
			addEvent(function(ref, instId, zn)
				if not ref.activeInstances[instId] then
					return
				end
				zn:refresh()
				local hasPlayers = false
				for _, p in ipairs(zn:getPlayers()) do
					if p:getInstanceId() == instId then
						hasPlayers = true
						break
					end
				end
				if not hasPlayers then
					logger.info("RaidInstance:zoneLeave - no players left in instance {}, cleaning up", instId)
					ref:cleanupInstance(instId)
				end
			end, 1000, raidRef, instanceId, _zone)
		end
	end
	zoneEvent:register()

	-- Register MoveEvent on each entry position
	local moveEvent = MoveEvent()
	moveEvent:type("stepin")
	function moveEvent.onStepIn(creature, item, position, fromPosition)
		local stepPlayer = creature:getPlayer()
		if not stepPlayer then
			return true -- Allow non-players (monsters) to pass
		end
		return raidRef:onStepIn(stepPlayer)
	end
	for _, pos in ipairs(self.entryPositions) do
		moveEvent:position(pos)
	end
	moveEvent:register()

	-- Store global reference for death handler
	RaidInstance[self.name] = self

	-- Register in AdminRegistry for Admin Helper UI
	AdminRegistry.raidInstances[self.bossName] = self

	logger.info("RaidInstance:register - registered raid instance '{}' with {} entry positions", self.bossName, #self.entryPositions)
	return true
end

-- ============================================================================
-- Data accessors (prepared for future client UI integration)
-- ============================================================================

---@return table
function RaidInstance:getInstanceInfo()
	local info = {}
	for instanceId, data in pairs(self.activeInstances) do
		local players = {}
		local zone = self:getZone()
		zone:refresh()
		for _, zonePlayer in ipairs(zone:getPlayers()) do
			if zonePlayer:getInstanceId() == instanceId then
				table.insert(players, {
					name = zonePlayer:getName(),
					level = zonePlayer:getLevel(),
					vocation = zonePlayer:getVocation():getName(),
				})
			end
		end
		table.insert(info, {
			instanceId = instanceId,
			createdAt = data.createdAt,
			elapsed = os.time() - data.createdAt,
			playerCount = #players,
			players = players,
		})
	end
	return info
end
