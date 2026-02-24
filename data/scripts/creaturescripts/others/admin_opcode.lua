-- Admin Helper ExtendedOpcode Handler
-- Opcode 211 (ADMIN_OPCODE): client requests data lists; server responds with JSON.
-- Only responds to players with GM/God access.
-- Actions: "players", "raids", "teleports"
-- AdminRegistry sources: raidInstances, bossLevers, hunts

local adminOpcode = CreatureEvent("AdminOpcode")

-- Attempt to find a matching raid command name for a given boss name.
-- Iterates Raid.registry (key = raid command string) looking for a case-insensitive
-- substring match against the boss name. Returns nil if no match found.
local function findRaidCommand(bossName)
	if not Raid or not Raid.registry then
		return nil
	end
	local lower = bossName:lower()
	for key, _ in pairs(Raid.registry) do
		if lower:find(key:lower(), 1, true) or key:lower():find(lower, 1, true) then
			return key
		end
	end
	return nil
end

local function posJson(pos)
	if not pos then return "null" end
	return string.format('{"x":%d,"y":%d,"z":%d}', pos.x, pos.y, pos.z)
end

-- Action: return all online players
local function handlePlayers(player)
	local esc = InstanceRegistry.jsonEscape
	local entries = {}
	for _, p in ipairs(Game.getPlayers()) do
		local voc = p:getVocation()
		local vocName = voc and voc:getName() or "None"
		table.insert(entries, string.format(
			'{"name":"%s","level":%d,"vocation":"%s"}',
			esc(p:getName()), p:getLevel(), esc(vocName)
		))
	end
	local json = string.format('{"action":"players","data":[%s]}', table.concat(entries, ","))
	player:sendExtendedOpcode(ADMIN_OPCODE, json)
end

-- Action: return all registered raid instances and boss levers with outfit, entryPos, raidCommand
local function handleRaids(player)
	local esc = InstanceRegistry.jsonEscape
	local entries = {}

	for bossName, ref in pairs(AdminRegistry.raidInstances) do
		local outfitJson = InstanceRegistry.getOutfitJson(bossName)
		local entryPos = ref.entryPositions and ref.entryPositions[1] or nil
		local raidCommand = findRaidCommand(bossName)
		local cmdJson = raidCommand and ('"' .. esc(raidCommand) .. '"') or "null"
		table.insert(entries, string.format(
			'{"name":"%s","boss":"%s","type":"raidInstance","outfit":%s,"entryPos":%s,"requiredLevel":%d,"raidCommand":%s}',
			esc(bossName), esc(bossName), outfitJson, posJson(entryPos),
			ref.requiredLevel or 0, cmdJson
		))
	end

	for bossName, ref in pairs(AdminRegistry.bossLevers) do
		local outfitJson = InstanceRegistry.getOutfitJson(bossName)
		local entryPos = ref.playerPositions and ref.playerPositions[1] and ref.playerPositions[1].pos or nil
		local raidCommand = findRaidCommand(bossName)
		local cmdJson = raidCommand and ('"' .. esc(raidCommand) .. '"') or "null"
		table.insert(entries, string.format(
			'{"name":"%s","boss":"%s","type":"bossLever","outfit":%s,"entryPos":%s,"requiredLevel":%d,"raidCommand":%s}',
			esc(bossName), esc(bossName), outfitJson, posJson(entryPos),
			ref.requiredLevel or 0, cmdJson
		))
	end

	-- Hunt instances (no boss outfit; use empty outfit)
	for huntName, ref in pairs(AdminRegistry.hunts or {}) do
		local entryPos = ref.entryPositions and ref.entryPositions[1] or nil
		table.insert(entries, string.format(
			'{"name":"%s","boss":null,"type":"hunt","outfit":{"type":0,"head":0,"body":0,"legs":0,"feet":0,"addons":0},"entryPos":%s,"requiredLevel":%d,"raidCommand":null}',
			esc(huntName), posJson(entryPos), ref.requiredLevel or 0
		))
	end

	local json = string.format('{"action":"raids","data":[%s]}', table.concat(entries, ","))
	player:sendExtendedOpcode(ADMIN_OPCODE, json)
end

-- Action: return towns + hunt entry positions for the Teleports tab
local function handleTeleports(player)
	local esc = InstanceRegistry.jsonEscape
	local townEntries = {}
	local huntEntries = {}

	-- Towns from the map
	for _, town in ipairs(Game.getTowns()) do
		table.insert(townEntries, string.format(
			'{"id":%d,"name":"%s"}',
			town:getId(), esc(town:getName())
		))
	end

	-- Raid instances
	for bossName, ref in pairs(AdminRegistry.raidInstances) do
		local entryPos = ref.entryPositions and ref.entryPositions[1] or nil
		table.insert(huntEntries, string.format(
			'{"name":"%s","type":"raidInstance","entryPos":%s}',
			esc(bossName), posJson(entryPos)
		))
	end

	-- Boss levers
	for bossName, ref in pairs(AdminRegistry.bossLevers) do
		local entryPos = ref.playerPositions and ref.playerPositions[1] and ref.playerPositions[1].pos or nil
		table.insert(huntEntries, string.format(
			'{"name":"%s","type":"bossLever","entryPos":%s}',
			esc(bossName), posJson(entryPos)
		))
	end

	-- Hunt instances
	for huntName, ref in pairs(AdminRegistry.hunts or {}) do
		local entryPos = ref.entryPositions and ref.entryPositions[1] or nil
		table.insert(huntEntries, string.format(
			'{"name":"%s","type":"hunt","entryPos":%s}',
			esc(huntName), posJson(entryPos)
		))
	end

	local json = string.format(
		'{"action":"teleports","data":{"towns":[%s],"hunts":[%s]}}',
		table.concat(townEntries, ","),
		table.concat(huntEntries, ",")
	)
	player:sendExtendedOpcode(ADMIN_OPCODE, json)
end

function adminOpcode.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= ADMIN_OPCODE then
		return
	end

	-- Security: only GM/God players
	local group = player:getGroup()
	if not group or not group:getAccess() then
		return
	end

	local action = buffer:match('"action"%s*:%s*"([^"]+)"')
	if not action then
		return
	end

	if action == "players" then
		handlePlayers(player)
	elseif action == "raids" then
		handleRaids(player)
	elseif action == "teleports" then
		handleTeleports(player)
	end
end

adminOpcode:register()
