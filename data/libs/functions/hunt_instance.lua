---@class HuntInstance
---@field private name string
---@field private caveSeed Position
---@field private exit Position
---@field private maxCaveTiles number
---@field private maxInstances number
---@field private timeLimit number|nil
---@field private cooldownTime number
---@field private requiredLevel number
---@field private disabled boolean
---@field private activeInstances table
---@field private groupToInstance table
---@field private partyCooldowns table
---@field private leaveGracePeriod number
---@field private _floodFillResult table|nil
HuntInstance = {}

--[[
local hunt = HuntInstance({
    name = "Dragon Lords #3 - Darashia",
    caveSeed = Position(32847, 32165, 8),   -- first walkable tile inside the cave (flood-fill origin)
    exit = Position(32847, 32163, 7),       -- where players go when they leave or time out
    maxCaveTiles = 5000,                    -- flood-fill tile limit (default 5000)
    maxInstances = 20,
    timeLimit = 4 * 60 * 60,               -- optional: 4h session limit (nil = no limit)
    cooldownTime = 0,                       -- seconds between runs per party (0 = no cooldown)
    requiredLevel = 0,
    disabled = false,
})
hunt:register()
]]

-- ============================================================================
-- Constructor
-- ============================================================================

setmetatable(HuntInstance, {
	---@param self HuntInstance
	---@param config table
	__call = function(self, config)
		if not config.name then
			error("HuntInstance: name is required")
		end
		if not config.caveSeed then
			error("HuntInstance: caveSeed is required (first walkable position inside the cave)")
		end
		return setmetatable({
			name = config.name,
			caveSeed = config.caveSeed,
			exit = config.exit,
			maxCaveTiles = config.maxCaveTiles or 5000,
			maxInstances = config.maxInstances or 20,
			timeLimit = config.timeLimit,
			cooldownTime = config.cooldownTime or 0,
			requiredLevel = config.requiredLevel or 0,
			disabled = config.disabled or false,
			activeInstances = {},
			groupToInstance = {},
			partyCooldowns = {},
			leaveGracePeriod = config.leaveGracePeriod or 300,
			_floodFillResult = nil,
		}, { __index = HuntInstance })
	end,
})

-- ============================================================================
-- Group key: party leader GUID, solo player gets own instance
-- ============================================================================

---@param player Player
---@return number
function HuntInstance:getGroupKey(player)
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
-- Instance count
-- ============================================================================

---@return number
function HuntInstance:countActiveInstances()
	local count = 0
	for _ in pairs(self.activeInstances) do
		count = count + 1
	end
	return count
end

-- ============================================================================
-- Zone
-- ============================================================================

function HuntInstance:getZone()
	return Zone("hunt." .. toKey(self.name))
end

-- ============================================================================
-- Populate monsters from zone spawns into the instance
-- ============================================================================

---@param instanceId number
---@return number total spawns added
function HuntInstance:populateInstance(instanceId)
	return Game.populateInstanceFromZone(instanceId, self:getZone())
end

-- ============================================================================
-- Cleanup
-- ============================================================================

---@param instanceId number
function HuntInstance:cleanupInstance(instanceId)
	local zone = self:getZone()
	zone:refresh()
	InstanceRegistry.broadcastClear(instanceId, zone)
	InstanceRegistry.unregister(instanceId)
	for _, zonePlayer in ipairs(zone:getPlayers()) do
		if zonePlayer:getInstanceId() == instanceId then
			zonePlayer:teleportTo(self.exit)
			zonePlayer:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			if zonePlayer:getInstanceId() > 1 then
				zonePlayer:changeInstance(1)
			end
		end
	end
	for _, monster in ipairs(zone:getMonsters()) do
		if monster:getInstanceId() == instanceId then
			monster:remove()
		end
	end
	Game.destroyInstance(instanceId)
	if self.activeInstances[instanceId] then
		local groupKey = self.activeInstances[instanceId].groupKey
		if groupKey and self.groupToInstance[groupKey] == instanceId then
			self.groupToInstance[groupKey] = nil
		end
		if self.activeInstances[instanceId].timeoutEvent then
			stopEvent(self.activeInstances[instanceId].timeoutEvent)
		end
		self.activeInstances[instanceId] = nil
	end
	logger.info("HuntInstance:cleanupInstance - cleaned up instance {} for hunt '{}'", instanceId, self.name)
end

-- ============================================================================
-- Entry handler (called from zone afterEnter)
-- ============================================================================

---@param player Player
function HuntInstance:onStepIn(player)
	if not player or not player:isPlayer() then
		return
	end

	local currentInstanceId = player:getInstanceId()
	if currentInstanceId > 1 and self.activeInstances[currentInstanceId] then
		return
	end

	if self.disabled then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "This hunting area is temporarily unavailable.")
		player:teleportTo(self.exit)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		return
	end

	local checkAccountType = player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER
	local isGameTester = player:hasFlag(PlayerFlag_IsGameTester)
	if checkAccountType and not isGameTester and self.requiredLevel > 0 and player:getLevel() < self.requiredLevel then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You need to be level %d or higher to enter %s.", self.requiredLevel, self.name))
		player:teleportTo(self.exit)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		return
	end

	-- Reconnect via persistent C++ GUID tracking (survives relog)
	local existingByGuid = Game.findInstanceByPlayerGuid(player:getGuid())
	if existingByGuid == 0 then
		existingByGuid = InstanceRegistry.findInstanceByParty(player)
	end
	if existingByGuid and existingByGuid > 0 and self.activeInstances[existingByGuid] then
		logger.info("HuntInstance:onStepIn - player {} reconnecting to instance {} for hunt '{}'", player:getName(), existingByGuid, self.name)
		player:changeInstance(existingByGuid)
		Game.trackInstancePlayer(player:getGuid(), existingByGuid)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		addEvent(function(instId)
			InstanceRegistry.broadcastUpdate(instId)
		end, 500, existingByGuid)
		return
	end

	local groupKey = self:getGroupKey(player)

	-- Rejoin existing group instance
	local existingInstanceId = self.groupToInstance[groupKey]
	if existingInstanceId and self.activeInstances[existingInstanceId] then
		logger.info("HuntInstance:onStepIn - player {} rejoining instance {} for hunt '{}'", player:getName(), existingInstanceId, self.name)
		player:changeInstance(existingInstanceId)
		Game.trackInstancePlayer(player:getGuid(), existingInstanceId)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		addEvent(function(instId)
			InstanceRegistry.broadcastUpdate(instId)
		end, 500, existingInstanceId)
		return
	end

	-- Cooldown check
	if self.cooldownTime and self.cooldownTime > 0 then
		local lastStart = self.partyCooldowns[groupKey]
		if lastStart then
			local elapsed = os.time() - lastStart
			if elapsed < self.cooldownTime then
				local remaining = self.cooldownTime - elapsed
				local mins = math.floor(remaining / 60)
				local secs = remaining % 60
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
					"Your party must wait %d:%02d before starting another hunt in %s.", mins, secs, self.name))
				player:teleportTo(self.exit)
				player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
				return
			end
		end
	end

	-- Max instances
	if self:countActiveInstances() >= self.maxInstances then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("All instances of %s are currently occupied. Please try again later.", self.name))
		player:teleportTo(self.exit)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		return
	end

	-- === CREATE NEW INSTANCE ===
	local instanceId = Game.createInstance(player)
	if not instanceId or instanceId <= 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Failed to create instance. Please try again later.")
		player:teleportTo(self.exit)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		return
	end

	self.activeInstances[instanceId] = {
		groupKey = groupKey,
		timeoutEvent = nil,
		createdAt = os.time(),
	}
	self.groupToInstance[groupKey] = instanceId

	local spawnCount = self:populateInstance(instanceId)
	logger.info("HuntInstance:onStepIn - player {} created instance {} for hunt '{}', populated {} spawns", player:getName(), instanceId, self.name, spawnCount)

	player:changeInstance(instanceId)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)

	if self.cooldownTime and self.cooldownTime > 0 then
		self.partyCooldowns[groupKey] = os.time()
	end

	local timeoutEvt = nil
	if self.timeLimit and self.timeLimit > 0 then
		timeoutEvt = addEvent(function(huntRef, instId)
			huntRef:cleanupInstance(instId)
		end, self.timeLimit * 1000, self, instanceId)
	end
	self.activeInstances[instanceId].timeoutEvent = timeoutEvt

	Game.trackInstancePlayer(player:getGuid(), instanceId)

	local timeoutAt = self.timeLimit and (os.time() + self.timeLimit) or nil
	InstanceRegistry.register(instanceId, "hunt", self.name, self, timeoutAt)
	InstanceRegistry.sendUpdate(player)
end

-- ============================================================================
-- Registration — flood-fill from caveSeed builds exact zone
-- ============================================================================

---@return boolean
function HuntInstance:register()
	if not self.name or self.name == "" then
		logger.error("HuntInstance:register() - hunt missing name")
		return false
	end
	if not self.caveSeed then
		logger.error("HuntInstance:register() - hunt '{}' missing caveSeed", self.name)
		return false
	end
	if not self.exit then
		logger.error("HuntInstance:register() - hunt '{}' missing exit", self.name)
		return false
	end

	local zone = self:getZone()

	-- Build zone via flood-fill from caveSeed
	local result = zone:buildFromFloodFill(self.caveSeed, self.maxCaveTiles)
	self._floodFillResult = result

	if result.tiles == 0 then
		logger.error("HuntInstance:register - hunt '{}' flood-fill from {} found 0 tiles!", self.name, self.caveSeed:toString())
		return false
	end

	if result.spawns == 0 then
		logger.warn("HuntInstance:register - hunt '{}' has NO spawns in flood-filled area!", self.name)
	end

	zone:blockFamiliars()
	zone:setRemoveDestination(self.exit)

	local huntRef = self

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
		if instanceId > 1 and huntRef.activeInstances[instanceId] then
			if not isLogout then
				logger.info("HuntInstance:zoneLeave - player {} left hunt zone '{}' while in instance {}", zonePlayer:getName(), huntRef.name, instanceId)
				InstanceRegistry.sendClear(zonePlayer)
				zonePlayer:changeInstance(1)
			end
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
					logger.info("HuntInstance:zoneLeave - no players in instance {} for '{}', cleaning up", instId, ref.name)
					ref:cleanupInstance(instId)
				end
			end, (huntRef.leaveGracePeriod or 300) * 1000, huntRef, instanceId, _zone)
		end
	end

	function zoneEvent.afterEnter(_zone, creature)
		if not creature or not creature:isPlayer() then
			return
		end
		local zonePlayer = creature:getPlayer()
		if not zonePlayer or zonePlayer:isRemoved() then
			return
		end
		if zonePlayer:getInstanceId() ~= 1 then
			return
		end
		huntRef:onStepIn(zonePlayer)
	end

	zoneEvent:register()

	HuntInstance[self.name] = self
	AdminRegistry.hunts[self.name] = self

	local zStr = ""
	if result.zLevels then
		local parts = {}
		for _, z in ipairs(result.zLevels) do
			table.insert(parts, tostring(z))
		end
		zStr = table.concat(parts, ",")
	end

	logger.info("HuntInstance:register - registered hunt '{}': {} tiles, z=[{}], {} spawns, {} entries (flood-fill from {})",
		self.name, result.tiles, zStr, result.spawns,
		result.entries and #result.entries or 0, self.caveSeed:toString())
	return true
end

-- ============================================================================
-- Info (for admin UI / debugging)
-- ============================================================================

---@return table
function HuntInstance:getInstanceInfo()
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
