---@class BossLever
---@field private name string
---@field private bossPosition Position
---@field private createBoss function
---@field private timeToFightAgain number
---@field private timeToDefeat number
---@field private minPlayers number
---@field private timeAfterKill number
---@field private requiredLevel number
---@field private disabled boolean
---@field private onUseExtra function
---@field private _position Position
---@field private _uid number
---@field private _aid number
---@field private playerPositions {pos: Position, teleport: Position}[]
---@field private area {from: Position, to: Position}
---@field private monsters {name: string, pos: Position}[]
---@field private exitTeleporter Position
---@field private exit Position
---@field private encounter Encounter
---@field private timeoutEvent Event
---@field private disableCooldown boolean
---@field private instanced boolean
---@field private maxInstances number
---@field private activeInstances table
BossLever = {}

--[[
local config = {
	boss = {
		name = "Faceless Bane",
		position = Position(33617, 32561, 13)
	}
	requiredLevel = 250,
	timeToFightAgain = 10 * 60 * 60, -- In seconds
	minPlayers = 4,
	instanced = false, -- Set to true for instanced boss fights (multiple groups simultaneously)
	maxInstances = 10, -- Max concurrent instances for this boss (only used when instanced = true)
	playerPositions = {
		{ pos = Position(33638, 32562, 13), teleport = Position(33617, 32567, 13) },
		{ pos = Position(33639, 32562, 13), teleport = Position(33617, 32567, 13) },
		{ pos = Position(33640, 32562, 13), teleport = Position(33617, 32567, 13) },
		{ pos = Position(33641, 32562, 13), teleport = Position(33617, 32567, 13) },
		{ pos = Position(33642, 32562, 13), teleport = Position(33617, 32567, 13) },
	},
	specPos = {
		from = Position(33607, 32553, 13),
		to = Position(33627, 32570, 13)
	},
	onUseExtra = function(player, infoPositions)
		player:teleportTo(Position(33618, 32523, 15))
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end,
	exit = Position(33618, 32523, 15),
}
]]
setmetatable(BossLever, {
	---@param self BossLever
	---@param config table
	__call = function(self, config)
		local boss = config.boss
		if not boss then
			error("BossLever: boss is required")
		end
		return setmetatable({
			name = boss.name:lower(),
			encounter = config.encounter,
			bossPosition = boss.position,
			timeToFightAgain = config.timeToFightAgain or configManager.getNumber(configKeys.BOSS_DEFAULT_TIME_TO_FIGHT_AGAIN),
			timeToDefeat = config.timeToDefeat or configManager.getNumber(configKeys.BOSS_DEFAULT_TIME_TO_DEFEAT),
			timeAfterKill = config.timeAfterKill or 60,
			requiredLevel = config.requiredLevel or 0,
			createBoss = boss.createFunction,
			disabled = config.disabled,
			minPlayers = config.minPlayers or 1,
			playerPositions = config.playerPositions,
			onUseExtra = config.onUseExtra or function() end,
			exitTeleporter = config.exitTeleporter,
			exit = config.exit,
			area = config.specPos,
			monsters = config.monsters or {},
			disableCooldown = config.disableCooldown,
			instanced = config.instanced or false,
			maxInstances = config.maxInstances or 10,
			activeInstances = {},
			_position = nil,
			_uid = nil,
			_aid = nil,
		}, { __index = BossLever })
	end,
})

---@param self BossLever
---@param position Position
---@return BossLever
function BossLever:position(position)
	self._position = position
	return self
end

---@param self BossLever
---@param uid number
---@return BossLever
function BossLever:uid(uid)
	self._uid = uid
	return self
end

---@param self BossLever
---@param aid number
---@return BossLever
function BossLever:aid(aid)
	self._aid = aid
	return self
end

function BossLever:kvScope()
	local mType = MonsterType(self.name)
	if not mType then
		error("BossLever: boss name is invalid")
	end
	return "boss.cooldown." .. toKey(tostring(mType:raceId()))
end

---@param self BossLever
---@param player Player
---@return number
function BossLever:lastEncounterTime(player)
	if not player or self.disableCooldown then
		return 0
	end
	return player:getBossCooldown(self.name)
end

---@param self BossLever
---@param time number
---@return boolean
function BossLever:setLastEncounterTime(time)
	local info = self.lever:getInfoPositions()
	if not info then
		logger.error("BossLever:setLastEncounterTime - lever:getInfoPositions() returned nil")
		return false
	end
	for _, v in pairs(info) do
		if v.creature then
			local player = v.creature:getPlayer()
			if player then
				player:setBossCooldown(self.name, time)
			end
		end
	end
	return true
end

---@return number
function BossLever:countActiveInstances()
	local count = 0
	for _ in pairs(self.activeInstances) do
		count = count + 1
	end
	return count
end

---@param instanceId number
function BossLever:cleanupInstance(instanceId)
	local zone = self:getZone()
	zone:refresh()
	-- 0. Broadcast clear to all players in this instance before cleanup
	InstanceRegistry.broadcastClear(instanceId, zone)
	InstanceRegistry.unregister(instanceId)
	-- 1. Move players back to global and teleport to exit
	-- Note: teleportTo triggers zone afterLeave which calls changeInstance(1) automatically.
	-- The explicit changeInstance(1) below is a safety fallback in case the zone event didn't fire.
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
		if self.activeInstances[instanceId].timeoutEvent then
			stopEvent(self.activeInstances[instanceId].timeoutEvent)
		end
		self.activeInstances[instanceId] = nil
	end
	logger.info("BossLever:cleanupInstance - cleaned up instance {} for boss {}", instanceId, self.name)
end

---@param player Player
---@return boolean
function BossLever:onUse(player)
	local monsterName = MonsterType(self.name):getName()
	local isParticipant = false
	for _, v in ipairs(self.playerPositions) do
		if Position(v.pos) == player:getPosition() then
			isParticipant = true
		end
	end
	if not isParticipant then
		return false
	end

	if self.disabled then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The boss is temporarily disabled.")
		return true
	end

	local zone = self:getZone()
	zone:refresh() -- Refresh the zone to ensure it is up-to-date
	if self.instanced then
		-- Instance mode: check concurrent instance limit instead of room occupancy
		if self:countActiveInstances() >= self.maxInstances then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Too many groups are fighting " .. monsterName .. " right now. Please try again later.")
			return true
		end
	else
		if zone:countPlayers(IgnoredByMonsters) > 0 then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "There's already someone fighting with " .. monsterName .. ".")
			return true
		end
	end

	self.lever = Lever()
	local lever = self.lever
	lever:setPositions(self.playerPositions)
	lever:setCondition(function(creature)
		if not creature or not creature:isPlayer() then
			return true
		end

		local checkAccountType = creature:getAccountType() < ACCOUNT_TYPE_GAMEMASTER
		local isGameTester = player:hasFlag(PlayerFlag_IsGameTester)
		if checkAccountType and not isGameTester and creature:getLevel() < self.requiredLevel then
			local message = "All players need to be level " .. self.requiredLevel .. " or higher."
			creature:sendTextMessage(MESSAGE_EVENT_ADVANCE, message)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, message)
			return false
		end

		local infoPositions = lever:getInfoPositions()
		if creature:getGroup():getId() < GROUP_TYPE_GOD and checkAccountType and not isGameTester and self:lastEncounterTime(creature) > os.time() then
			for _, posInfo in pairs(infoPositions) do
				local currentPlayer = posInfo.creature
				if currentPlayer then
					local lastEncounter = self:lastEncounterTime(currentPlayer)
					local currentTime = os.time()
					if lastEncounter and currentTime < lastEncounter then
						local timeLeft = lastEncounter - currentTime
						local timeMessage = Game.getTimeInWords(timeLeft) .. " to face " .. self.name .. " again!"
						local message = "You have to wait " .. timeMessage

						if currentPlayer ~= player then
							player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "A member in your team has to wait " .. timeMessage)
						end

						currentPlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, message)
						currentPlayer:getPosition():sendMagicEffect(CONST_ME_POFF)
					end
				end
			end
			return false
		end

		return self.onUseExtra(creature, infoPositions) ~= false
	end)

	lever:checkPositions()
	if #lever:getPlayers() < self.minPlayers then
		lever:executeOnPlayers(function(creature)
			local message = string.format("You need %d qualified players for this challenge.", self.minPlayers)
			creature:sendTextMessage(MESSAGE_EVENT_ADVANCE, message)
			creature:getPosition():sendMagicEffect(CONST_ME_POFF)
		end)
		return false
	end
	if lever:checkConditions() then
		if self.instanced then
			-- === INSTANCED FLOW ===
			local instanceId = Game.createInstance(player)
			if not instanceId or instanceId <= 1 then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Failed to create instance. Please try again later.")
				return true
			end
			logger.info("BossLever:onUse - created instance {} for boss {}", instanceId, self.name)

			-- Spawn boss in the instance
			local bossMonster = nil
			if self.createBoss then
				-- Custom creation function receives instanceId for instanced bosses
				local result = self.createBoss(instanceId)
				if not result then
					Game.destroyInstance(instanceId)
					return true
				end
				-- If createFunction returns a monster, register death event
				if type(result) ~= "boolean" and result.registerEvent then
					bossMonster = result
				end
			elseif self.bossPosition then
				logger.debug("BossLever:onUse - creating instanced boss: {} in instance {}", self.name, instanceId)
				bossMonster = Game.createInstanceMonster(self.name, self.bossPosition, instanceId, true, true)
				if not bossMonster then
					Game.destroyInstance(instanceId)
					return true
				end
			end

			if bossMonster then
				bossMonster:registerEvent("BossLeverOnDeath")
			end

			-- Spawn additional monsters in the instance
			for _, monsterConfig in pairs(self.monsters) do
				Game.createInstanceMonster(monsterConfig.name, monsterConfig.pos, instanceId, true, true)
			end

			-- Teleport players to boss room, then switch to instance
			lever:teleportPlayers()
			local info = lever:getInfoPositions()
			if info then
				for _, v in pairs(info) do
					if v.creature and v.creature:isPlayer() then
						v.creature:changeInstance(instanceId)
						Game.trackInstancePlayer(v.creature:getGuid(), instanceId)
					end
				end
			end

			-- Set cooldowns
			lever:setCooldownAllPlayers(self.name, os.time() + self.timeToFightAgain)
			self:setLastEncounterTime(os.time() + self.timeToFightAgain)

			-- Track this instance and set timeout
			local timeoutEvt = addEvent(function(bossLeverRef, instId)
				bossLeverRef:cleanupInstance(instId)
			end, self.timeToDefeat * 1000, self, instanceId)

			self.activeInstances[instanceId] = {
				timeoutEvent = timeoutEvt,
				createdAt = os.time(),
			}

			-- Register in global InstanceRegistry and send UI update to all players
			InstanceRegistry.register(instanceId, "boss", MonsterType(self.name):getName(), self, os.time() + self.timeToDefeat)
			if info then
				for _, v in pairs(info) do
					if v.creature and v.creature:isPlayer() then
						InstanceRegistry.sendUpdate(v.creature)
					end
				end
			end
		else
			-- === NORMAL FLOW (unchanged) ===
			zone:removeMonsters()
			for _, monster in pairs(self.monsters) do
				Game.createMonster(monster.name, monster.pos, true, true)
			end
			if self.createBoss then
				if not self.createBoss() then
					return true
				end
			elseif self.bossPosition then
				logger.debug("BossLever:onUse - creating boss: {}", self.name)
				local monster = Game.createMonster(self.name, self.bossPosition, true, true)
				if not monster then
					return true
				end
				monster:registerEvent("BossLeverOnDeath")
			end
			lever:teleportPlayers()
			lever:setCooldownAllPlayers(self.name, os.time() + self.timeToFightAgain)
			if self.encounter then
				local encounter = Encounter(self.encounter)
				encounter:reset()
				encounter:start()
			end
			self:setLastEncounterTime(os.time() + self.timeToFightAgain)
			if self.timeoutEvent then
				stopEvent(self.timeoutEvent)
				self.timeoutEvent = nil
			end
			self.timeoutEvent = addEvent(function(zn)
				zn:refresh()
				zn:removePlayers()
			end, self.timeToDefeat * 1000, zone)
		end
	end
	return true
end

---@param Zone
function BossLever:getZone()
	return Zone("boss." .. toKey(self.name))
end

---@param self BossLever
---@return boolean
function BossLever:register()
	local missingParams = {}
	if not self.name then
		table.insert(missingParams, "boss.name")
	end
	if not self.playerPositions then
		table.insert(missingParams, "playerPositions")
	end
	if not self.area then
		table.insert(missingParams, "specPos")
	end
	if not self.exit then
		table.insert(missingParams, "exit")
	end
	if not self._position and not self._uid and not self._aid then
		table.insert(missingParams, "position or uid or aid")
	end
	if #missingParams > 0 then
		local name = self.name or "unknown"
		logger.error("BossLever:register() - boss with name {} missing parameters: {}", name, table.concat(missingParams, ", "))
		return false
	end

	local zone = self:getZone()

	zone:addArea(self.area.from, self.area.to)
	zone:blockFamiliars()
	zone:setRemoveDestination(self.exit)

	-- Instance System: when a player leaves the boss zone, return them to global instance (skip on logout to avoid static clone)
	if self.instanced then
		local bossLeverRef = self
		local zoneEvent = ZoneEvent(zone)
		function zoneEvent.afterLeave(_zone, creature, isLogout)
			if not creature or not creature:isPlayer() then
				return
			end
			local player = creature:getPlayer()
			if not player or player:isRemoved() then
				return -- Guard: player might be logging out
			end
			local instanceId = player:getInstanceId()
			if instanceId > 1 and self.activeInstances[instanceId] then
				if not isLogout then
					logger.info("BossLever:zoneLeave - player {} left boss zone while in instance {}, returning to global", player:getName(), instanceId)
					InstanceRegistry.sendClear(player)
					player:changeInstance(1)
				end
				-- Check if any players remain in this instance; if not, destroy it (run on both move and logout)
				addEvent(function(bossRef, instId, zn)
					if not bossRef.activeInstances[instId] then
						return -- Already cleaned up
					end
					zn:refresh()
					local hasPlayers = false
					for _, zonePlayer in ipairs(zn:getPlayers()) do
						if zonePlayer:getInstanceId() == instId then
							hasPlayers = true
							break
						end
					end
					if not hasPlayers then
						logger.info("BossLever:zoneLeave - no players left in instance {}, cleaning up", instId)
						bossRef:cleanupInstance(instId)
					end
				end, 1000, bossLeverRef, instanceId, _zone)
			end
		end
		zoneEvent:register()
	end

	local action = Action()
	action.onUse = function(player)
		self:onUse(player)
	end
	if self._position then
		action:position(self._position)
	end
	if self._uid then
		action:uid(self._uid)
	end
	if self._aid then
		action:aid(self._aid)
	end
	action:register()
	BossLever[self.name] = self

	-- Register in AdminRegistry for Admin Helper UI (self.name is boss.name:lower() from constructor)
	AdminRegistry.bossLevers[self.name] = self

	if self.exitTeleporter then
		SimpleTeleport(self.exitTeleporter, self.exit)
	end
	return true
end
