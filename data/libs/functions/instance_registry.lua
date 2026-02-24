-- ============================================================================
-- Instance Registry: global table mapping instanceId -> metadata
-- Used by the ExtendedOpcode handler to resolve instance info for any player.
-- Shared by all instance systems (RaidInstance, BossLever, future hunts).
-- ============================================================================
InstanceRegistry = InstanceRegistry or {}
INSTANCE_OPCODE = 210
ADMIN_OPCODE = 211

-- Registry for Admin Helper: maps boss/raid/hunt name → self reference
-- Populated by RaidInstance:register(), BossLever:register(), HuntInstance:register()
AdminRegistry = AdminRegistry or { raidInstances = {}, bossLevers = {}, hunts = {} }

--- Escape a string for safe JSON embedding.
--- Handles backslashes, double quotes, and control characters.
---@param str string|nil
---@return string
function InstanceRegistry.jsonEscape(str)
	if not str then
		return ""
	end
	str = str:gsub('\\', '\\\\')
	str = str:gsub('"', '\\"')
	str = str:gsub('\n', '\\n')
	str = str:gsub('\r', '\\r')
	str = str:gsub('\t', '\\t')
	return str
end

--- Build outfit JSON string from a monster name.
--- Returns a JSON object string like {"type":248,"head":0,"body":0,"legs":0,"feet":0,"addons":0}
---@param monsterName string
---@return string
function InstanceRegistry.getOutfitJson(monsterName)
	local mt = MonsterType(monsterName)
	if mt then
		local o = mt:getOutfit()
		return string.format(
			'{"type":%d,"head":%d,"body":%d,"legs":%d,"feet":%d,"addons":%d}',
			o.lookType or 0, o.lookHead or 0, o.lookBody or 0,
			o.lookLegs or 0, o.lookFeet or 0, o.lookAddons or 0
		)
	end
	return '{"type":0,"head":0,"body":0,"legs":0,"feet":0,"addons":0}'
end

--- Register an active instance in the global registry
---@param instanceId number
---@param instanceType string "raid" | "boss" | "hunt"
---@param name string Display name (e.g. "Gaz'Haragoth")
---@param sourceRef table Reference to RaidInstance or BossLever object
---@param timeoutAt number os.time() when instance expires
function InstanceRegistry.register(instanceId, instanceType, name, sourceRef, timeoutAt)
	InstanceRegistry[instanceId] = {
		type = instanceType,
		name = name,
		sourceRef = sourceRef,
		timeoutAt = timeoutAt,
		createdAt = os.time(),
	}
end

--- Remove an instance from the Lua registry.
--- Player GUID cleanup is handled automatically by C++ InstanceManager::destroyInstance.
---@param instanceId number
function InstanceRegistry.unregister(instanceId)
	InstanceRegistry[instanceId] = nil
end

--- Find an active instance by checking all party members' GUIDs via C++ tracking.
---@param player Player
---@return number|nil
function InstanceRegistry.findInstanceByParty(player)
	local party = player:getParty()
	if not party then
		return nil
	end
	local leader = party:getLeader()
	if leader then
		local leaderInst = Game.findInstanceByPlayerGuid(leader:getGuid())
		if leaderInst > 0 then
			return leaderInst
		end
	end
	for _, member in ipairs(party:getMembers()) do
		local instId = Game.findInstanceByPlayerGuid(member:getGuid())
		if instId > 0 then
			return instId
		end
	end
	return nil
end

--- Build JSON string for instance data and send to a player
---@param player Player
function InstanceRegistry.sendUpdate(player)
	local instanceId = player:getInstanceId()
	if instanceId <= 1 then
		InstanceRegistry.sendClear(player)
		return
	end

	local entry = InstanceRegistry[instanceId]
	if not entry then
		InstanceRegistry.sendClear(player)
		return
	end

	-- Collect players in this instance from the source's zone
	local esc = InstanceRegistry.jsonEscape
	local playersJson = {}
	local ref = entry.sourceRef
	if ref and ref.getZone then
		local zone = ref:getZone()
		zone:refresh()
		for _, zonePlayer in ipairs(zone:getPlayers()) do
			if zonePlayer:getInstanceId() == instanceId then
				local voc = zonePlayer:getVocation()
				local vocName = voc and voc:getName() or "Unknown"
				table.insert(playersJson, string.format(
					'{"name":"%s","level":%d,"vocation":"%s"}',
					esc(zonePlayer:getName()), zonePlayer:getLevel(), esc(vocName)
				))
			end
		end
	end

	local timeRemaining = 0
	if entry.timeoutAt then
		timeRemaining = math.max(0, entry.timeoutAt - os.time())
	end

	local outfitJson = '{"type":0,"head":0,"body":0,"legs":0,"feet":0,"addons":0}'
	if entry.type ~= "hunt" then
		outfitJson = InstanceRegistry.getOutfitJson(entry.name)
	end
	local totalTime = (entry.sourceRef and entry.sourceRef.timeToDefeat) or timeRemaining
	local jsonStr = string.format(
		'{"action":"update","data":{"instanceId":%d,"type":"%s","name":"%s","outfit":%s,"players":[%s],"timeRemaining":%d,"totalTime":%d,"createdAt":%d}}',
		instanceId,
		esc(entry.type or "unknown"),
		esc(entry.name or "Unknown"),
		outfitJson,
		table.concat(playersJson, ","),
		timeRemaining,
		totalTime,
		entry.createdAt or 0
	)

	player:sendExtendedOpcode(INSTANCE_OPCODE, jsonStr)
end

--- Send clear signal to close the instance panel on client
---@param player Player
function InstanceRegistry.sendClear(player)
	player:sendExtendedOpcode(INSTANCE_OPCODE, '{"action":"clear"}')
end

--- Broadcast update to all players in an instance
---@param instanceId number
function InstanceRegistry.broadcastUpdate(instanceId)
	local entry = InstanceRegistry[instanceId]
	if not entry or not entry.sourceRef then
		return
	end

	local ref = entry.sourceRef
	if ref.getZone then
		local zone = ref:getZone()
		zone:refresh()
		for _, zonePlayer in ipairs(zone:getPlayers()) do
			if zonePlayer:getInstanceId() == instanceId then
				InstanceRegistry.sendUpdate(zonePlayer)
			end
		end
	end
end

--- Broadcast clear to all players in an instance (before cleanup)
---@param instanceId number
---@param zone Zone
function InstanceRegistry.broadcastClear(instanceId, zone)
	if zone then
		zone:refresh()
		for _, zonePlayer in ipairs(zone:getPlayers()) do
			if zonePlayer:getInstanceId() == instanceId then
				InstanceRegistry.sendClear(zonePlayer)
			end
		end
	end
end
