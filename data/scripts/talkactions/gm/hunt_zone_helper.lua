-- Hunt Zone Helper — GM tool for defining HuntInstance zones via flood-fill.
--
-- Primary workflow (stand on a cave entrance):
--   /hunt discover              → flood-fill from stair/hole destination, show cave info
--   /hunt name, Dragon Lords    → set hunt name
--   /hunt exit                  → mark exit position (or auto-detected)
--   /hunt test                  → create test instance
--   /hunt save[, filename]      → write config to disk
--   /hunt clear                 → reset session
--
-- Global scan (browse all clusters):
--   /hunt scan[, filter]        → old grid-based cluster discovery (for browsing)
--   /hunt list[, page]          → browse clusters
--   /hunt nearby                → 10 nearest clusters
--   /hunt goto, <N>             → teleport to cluster center
--   /hunt accept, <N>           → flood-fill from cluster center spawn, load into session

-- ============================================================================
-- Utility: compute stair/hole destination using tile floor-change flags
-- ============================================================================

local function computeFloorchangeDestination(tile)
	if not tile then return nil end
	local pos = tile:getPosition()

	if tile:hasFlag(TILESTATE_FLOORCHANGE_DOWN) then
		local dest = Position(pos.x, pos.y, pos.z + 1)
		local destTile = Tile(dest)
		if destTile then
			if destTile:hasFlag(TILESTATE_FLOORCHANGE_NORTH) then
				dest.y = dest.y + 1
			elseif destTile:hasFlag(TILESTATE_FLOORCHANGE_SOUTH) then
				dest.y = dest.y - 1
			elseif destTile:hasFlag(TILESTATE_FLOORCHANGE_EAST) then
				dest.x = dest.x - 1
			elseif destTile:hasFlag(TILESTATE_FLOORCHANGE_WEST) then
				dest.x = dest.x + 1
			elseif destTile:hasFlag(TILESTATE_FLOORCHANGE_SOUTH_ALT) then
				dest.y = dest.y - 2
			elseif destTile:hasFlag(TILESTATE_FLOORCHANGE_EAST_ALT) then
				dest.x = dest.x - 2
			end
		end
		return dest
	elseif tile:hasFlag(TILESTATE_FLOORCHANGE) then
		local dest = Position(pos.x, pos.y, pos.z - 1)
		if tile:hasFlag(TILESTATE_FLOORCHANGE_NORTH) then
			dest.y = dest.y - 1
		elseif tile:hasFlag(TILESTATE_FLOORCHANGE_SOUTH) then
			dest.y = dest.y + 1
		elseif tile:hasFlag(TILESTATE_FLOORCHANGE_EAST) then
			dest.x = dest.x + 1
		elseif tile:hasFlag(TILESTATE_FLOORCHANGE_WEST) then
			dest.x = dest.x - 1
		elseif tile:hasFlag(TILESTATE_FLOORCHANGE_SOUTH_ALT) then
			dest.y = dest.y + 2
		elseif tile:hasFlag(TILESTATE_FLOORCHANGE_EAST_ALT) then
			dest.x = dest.x + 2
		end
		return dest
	end
	return nil
end

local function safeTeleport(player, targetPos)
	local p = Position(targetPos.x, targetPos.y, targetPos.z)
	if player:teleportTo(p) then
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		return true, p
	end
	for radius = 1, 5 do
		for dx = -radius, radius do
			for dy = -radius, radius do
				if math.abs(dx) == radius or math.abs(dy) == radius then
					local tryPos = Position(p.x + dx, p.y + dy, p.z)
					local tile = Tile(tryPos)
					if tile and not tile:hasProperty(CONST_PROP_BLOCKSOLID) then
						if player:teleportTo(tryPos) then
							player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
							return true, tryPos
						end
					end
				end
			end
		end
	end
	return false, nil
end

local function getNearestTownName(centerX, centerY)
	local towns = Game.getTowns()
	local bestName = "Unknown"
	local bestDist = math.huge
	for _, town in ipairs(towns) do
		local tpos = town:getTemplePosition()
		local dx = tpos.x - centerX
		local dy = tpos.y - centerY
		local dist = dx * dx + dy * dy
		if dist < bestDist then
			bestDist = dist
			bestName = town:getName()
		end
	end
	return bestName
end

local huntNameRegistry = {}

local function getDominantMonsterInArea(fromPos, toPos)
	local spawns = Game.getSpawnsInArea(fromPos, toPos)
	if not spawns or #spawns == 0 then
		return nil
	end
	local counts = {}
	for _, s in ipairs(spawns) do
		counts[s.name] = (counts[s.name] or 0) + 1
	end
	local bestName, bestCount = nil, 0
	for name, count in pairs(counts) do
		if count > bestCount then
			bestName = name
			bestCount = count
		end
	end
	return bestName
end

local function autoNameFromBBox(fromPos, toPos, centerX, centerY)
	local dominant = getDominantMonsterInArea(fromPos, toPos)
	local townName = getNearestTownName(centerX, centerY)
	if not dominant then
		return string.format("Cave - %s", townName)
	end
	local baseKey = dominant .. " - " .. townName
	huntNameRegistry[baseKey] = (huntNameRegistry[baseKey] or 0) + 1
	local idx = huntNameRegistry[baseKey]
	if idx == 1 then
		return string.format("%s - %s", dominant, townName)
	end
	return string.format("%s - %s #%d", dominant, townName, idx)
end

local function autoNameClusters(clusters)
	local batchIndex = {}
	for _, cluster in ipairs(clusters) do
		if cluster.monsters and #cluster.monsters > 0 then
			local dominant = cluster.monsters[1].name
			local cx = math.floor((cluster.fromPos.x + cluster.toPos.x) / 2)
			local cy = math.floor((cluster.fromPos.y + cluster.toPos.y) / 2)
			local townName = getNearestTownName(cx, cy)
			local baseKey = dominant .. " - " .. townName
			batchIndex[baseKey] = (batchIndex[baseKey] or 0) + 1
			local idx = batchIndex[baseKey]
			if idx == 1 then
				cluster.autoName = string.format("%s - %s", dominant, townName)
			else
				cluster.autoName = string.format("%s - %s #%d", dominant, townName, idx)
			end
		else
			cluster.autoName = "Empty Cluster"
		end
	end
end

-- ============================================================================
-- Per-player session state
-- ============================================================================

local sessions = {}

local function getSession(player)
	local guid = player:getGuid()
	if not sessions[guid] then
		sessions[guid] = {
			name = nil,
			caveSeed = nil,
			floodFillResult = nil,
			exitPos = nil,
			maxCaveTiles = 5000,
			testInstanceId = nil,
			discoveries = nil,
			gotoEntryIdx = 0,
		}
	end
	return sessions[guid]
end

local function clearSession(player)
	sessions[player:getGuid()] = nil
end

-- ============================================================================
-- Formatting helpers
-- ============================================================================

local function fmtPos(pos)
	return string.format("Position(%d, %d, %d)", pos.x, pos.y, pos.z)
end

local function generateConfig(session)
	local lines = {}
	table.insert(lines, 'local hunt = HuntInstance({')
	table.insert(lines, string.format('    name = "%s",', session.name))
	table.insert(lines, string.format('    caveSeed = %s,', fmtPos(session.caveSeed)))

	local exitStr = session.exitPos and fmtPos(session.exitPos) or 'Position(0, 0, 7) -- TODO: set exit'
	table.insert(lines, string.format('    exit = %s,', exitStr))

	if session.maxCaveTiles and session.maxCaveTiles ~= 5000 then
		table.insert(lines, string.format('    maxCaveTiles = %d,', session.maxCaveTiles))
	end

	table.insert(lines, '    requiredLevel = 0,')
	table.insert(lines, '    cooldownTime = 0,')
	table.insert(lines, '    maxInstances = 20,')
	table.insert(lines, '})')
	table.insert(lines, 'hunt:register()')

	return table.concat(lines, '\n')
end

-- ============================================================================
-- Talkaction
-- ============================================================================

local huntHelper = TalkAction("/hunt")

function huntHelper.onSay(player, words, param)
	logCommand(player, words, param)

	local split = param:split(",")
	local action = split[1] and split[1]:trim():lower() or ""
	local arg = split[2] and split[2]:trim() or ""

	local session = getSession(player)
	local pos = player:getPosition()

	-- =========================================================================
	-- DISCOVER: flood-fill from current position (stair/hole) or given position
	-- =========================================================================
	if action == "discover" then
		local seedPos = nil

		-- Scan current tile + 1 sqm radius for stairs/holes
		for dx = -1, 1 do
			for dy = -1, 1 do
				if seedPos then break end
				local checkPos = Position(pos.x + dx, pos.y + dy, pos.z)
				local checkTile = Tile(checkPos)
				if checkTile and (checkTile:hasFlag(TILESTATE_FLOORCHANGE) or checkTile:hasFlag(TILESTATE_FLOORCHANGE_DOWN)) then
					local dest = computeFloorchangeDestination(checkTile)
					if dest then
						seedPos = dest
						local label = (dx == 0 and dy == 0) and "Standing on" or "Nearby"
						player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
							"[Hunt] %s stair/hole at (%d,%d,%d) → destination: %s",
							label, checkPos.x, checkPos.y, checkPos.z, fmtPos(seedPos)))
					end
				end
			end
			if seedPos then break end
		end

		if not seedPos then
			for dx = -1, 1 do
				for dy = -1, 1 do
					if seedPos then break end
					local checkPos = Position(pos.x + dx, pos.y + dy, pos.z)
					local checkTile = Tile(checkPos)
					if checkTile and checkTile:hasFlag(TILESTATE_TELEPORT) then
						local tpItem = checkTile:getTeleportItem()
						if tpItem then
							local tpDest = tpItem:getDestination()
							if tpDest and tpDest.x ~= 0 then
								seedPos = tpDest
								local label = (dx == 0 and dy == 0) and "Standing on" or "Nearby"
								player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
									"[Hunt] %s teleport at (%d,%d,%d) -> destination: %s",
									label, checkPos.x, checkPos.y, checkPos.z, fmtPos(seedPos)))
							end
						end
					end
				end
				if seedPos then break end
			end
		end

		-- Check ScriptTeleportRegistry (script-based MoveEvent teleports)
		if not seedPos then
			for dx = -1, 1 do
				for dy = -1, 1 do
					if seedPos then break end
					local checkPos = Position(pos.x + dx, pos.y + dy, pos.z)
					local dest = getScriptTeleportDestination(checkPos)
					if dest then
						seedPos = dest
						local label = (dx == 0 and dy == 0) and "Standing on" or "Nearby"
						player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
							"[Hunt] %s script teleport at (%d,%d,%d) -> destination: %s",
							label, checkPos.x, checkPos.y, checkPos.z, fmtPos(seedPos)))
					end
				end
				if seedPos then break end
			end
		end

		-- Manual seed: /hunt discover, seed, x y z
		if not seedPos and arg ~= "" then
			local coords = arg:match("^seed%s*,%s*(.+)$") or arg:match("^seed%s+(.+)$")
			if coords then
				local sx, sy, sz = coords:match("(%d+)%s+(%d+)%s+(%d+)")
				if sx and sy and sz then
					seedPos = Position(tonumber(sx), tonumber(sy), tonumber(sz))
					player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
						"[Hunt] Manual seed position: %s", fmtPos(seedPos)))
				else
					player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Invalid seed format. Use: /hunt discover, seed, x y z")
					return true
				end
			end
		end

		if not seedPos then
			if pos.z >= 8 then
				seedPos = pos
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
					"[Hunt] Using current position as cave seed: %s", fmtPos(seedPos)))
			else
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No stair/hole/teleport found within 1 sqm. Stand near a cave entrance or inside the cave (z>=8). Or use: /hunt discover, seed, x y z")
				return true
			end
		end

		local maxTiles = tonumber(arg) or 5000
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Flood-filling from %s (max %d tiles)...", fmtPos(seedPos), maxTiles))

		-- Create a temporary zone for the flood-fill
		local tempZoneName = "hunt._discover_" .. player:getGuid()
		local tempZone = Zone(tempZoneName)
		local result = tempZone:buildFromFloodFill(seedPos, maxTiles)

		if not result or result.tiles == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Flood-fill found 0 tiles. Position may be blocked or invalid.")
			return true
		end

		session.caveSeed = seedPos
		session.floodFillResult = result
		session.maxCaveTiles = maxTiles

		-- Store teleport data in session
		session.teleportEntries = result.teleportEntries or {}
		session.internalTeleports = result.internalTeleports or {}
		session.exitTeleports = result.exitTeleports or {}

		-- Auto-detect exit: pick stair entry with lowest z, teleport entry source, or exit teleport dest
		if result.entries and #result.entries > 0 then
			local bestEntry = result.entries[1]
			for _, ep in ipairs(result.entries) do
				if ep.z < bestEntry.z then
					bestEntry = ep
				end
			end
			session.exitPos = Position(bestEntry.x, bestEntry.y, bestEntry.z)
		elseif #session.teleportEntries > 0 then
			local tp = session.teleportEntries[1]
			session.exitPos = Position(tp.source.x, tp.source.y, tp.source.z)
		elseif #session.exitTeleports > 0 then
			local tp = session.exitTeleports[1]
			session.exitPos = Position(tp.dest.x, tp.dest.y, tp.dest.z)
		end

		-- Auto-name from dominant monster + nearest town
		if not session.name then
			if result.bboxMin and result.bboxMax then
				local cx = math.floor((result.bboxMin.x + result.bboxMax.x) / 2)
				local cy = math.floor((result.bboxMin.y + result.bboxMax.y) / 2)
				session.name = autoNameFromBBox(
					Position(result.bboxMin.x, result.bboxMin.y, result.bboxMin.z),
					Position(result.bboxMax.x, result.bboxMax.y, result.bboxMax.z),
					cx, cy)
			else
				local townName = getNearestTownName(seedPos.x, seedPos.y)
				session.name = string.format("Cave - %s", townName)
			end
		end

		-- Show results
		local zStr = "?"
		if result.zLevels then
			local parts = {}
			for _, z in ipairs(result.zLevels) do
				table.insert(parts, tostring(z))
			end
			zStr = table.concat(parts, ",")
		end

		local totalEntries = (result.entries and #result.entries or 0) + #session.teleportEntries
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			'[Hunt] Discovered: %d tiles, z=[%s], %d spawns, %d entries (%d stair, %d teleport), %d internal tp',
			result.tiles, zStr, result.spawns, totalEntries,
			result.entries and #result.entries or 0,
			#session.teleportEntries,
			#session.internalTeleports))
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			'[Hunt] Name: "%s". Use /hunt name, <name> to change.', session.name))

		if result.entries and #result.entries > 0 then
			local entryList = {}
			for i, ep in ipairs(result.entries) do
				if i > 5 then
					table.insert(entryList, "...")
					break
				end
				table.insert(entryList, string.format("(%d,%d,%d)", ep.x, ep.y, ep.z))
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Stair entries: " .. table.concat(entryList, ", "))
		end

		if #session.teleportEntries > 0 then
			local tpList = {}
			for i, tp in ipairs(session.teleportEntries) do
				if i > 5 then
					table.insert(tpList, "...")
					break
				end
				table.insert(tpList, string.format("(%d,%d,%d)->(%d,%d,%d)",
					tp.source.x, tp.source.y, tp.source.z,
					tp.dest.x, tp.dest.y, tp.dest.z))
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Teleport entries: " .. table.concat(tpList, ", "))
		end

		if #session.exitTeleports > 0 then
			local tpList = {}
			for i, tp in ipairs(session.exitTeleports) do
				if i > 5 then
					table.insert(tpList, "...")
					break
				end
				table.insert(tpList, string.format("(%d,%d,%d)->(%d,%d,%d)",
					tp.source.x, tp.source.y, tp.source.z,
					tp.dest.x, tp.dest.y, tp.dest.z))
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit teleports: " .. table.concat(tpList, ", "))
		end

		if session.exitPos then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit (auto): " .. fmtPos(session.exitPos))
		else
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No exit detected. Use /hunt exit to set manually.")
		end

		if result.tiles >= maxTiles then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				"[Hunt] WARNING: Flood-fill hit tile limit (%d). Cave may be larger. Use /hunt discover, <higher limit> if needed.", maxTiles))
		end

	-- =========================================================================
	-- NAME
	-- =========================================================================
	elseif action == "name" then
		if arg == "" then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Usage: /hunt name, <name>")
			return true
		end
		session.name = arg
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Name set: " .. arg)

	-- =========================================================================
	-- EXIT
	-- =========================================================================
	elseif action == "exit" then
		session.exitPos = pos
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit set: " .. fmtPos(pos))

	-- =========================================================================
	-- STATUS
	-- =========================================================================
	elseif action == "status" then
		if not session.caveSeed then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No active session. Use /hunt discover on a cave entrance.")
			return true
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format('[Hunt] Name: "%s"', session.name or "(not set)"))
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] CaveSeed: " .. fmtPos(session.caveSeed))
		if session.floodFillResult then
			local r = session.floodFillResult
			local zStr = "?"
			if r.zLevels then
				local parts = {}
				for _, z in ipairs(r.zLevels) do
					table.insert(parts, tostring(z))
				end
				zStr = table.concat(parts, ",")
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				"[Hunt] Tiles: %d, z=[%s], Spawns: %d, Entries: %d",
				r.tiles, zStr, r.spawns, r.entries and #r.entries or 0))
		end
		if session.exitPos then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit: " .. fmtPos(session.exitPos))
		else
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit: not set")
		end

	-- =========================================================================
	-- TEST
	-- =========================================================================
	elseif action == "test" then
		if not session.caveSeed then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Run /hunt discover first.")
			return true
		end
		local exitPos = session.exitPos or player:getPosition()
		local instanceId = Game.createInstance(player)
		if not instanceId or instanceId <= 1 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Failed to create test instance.")
			return true
		end

		-- Build a temp zone and populate from it
		local tempZoneName = "hunt._test_" .. player:getGuid()
		local tempZone = Zone(tempZoneName)
		tempZone:buildFromFloodFill(session.caveSeed, session.maxCaveTiles or 5000)
		local spawnCount = Game.populateInstanceFromZone(instanceId, tempZone)

		player:changeInstance(instanceId)
		-- Teleport to caveSeed
		safeTeleport(player, session.caveSeed)
		session.testInstanceId = instanceId
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Test instance #%d created. Populated %d spawns. Use /instance leave when done.",
			instanceId, spawnCount))

	-- =========================================================================
	-- GOTO entries
	-- =========================================================================
	elseif action == "goto" then
		local target = arg:lower()

		if target == "entries" then
			if not session.floodFillResult or not session.floodFillResult.entries or #session.floodFillResult.entries == 0 then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No entries detected.")
				return true
			end
			local entries = session.floodFillResult.entries
			session.gotoEntryIdx = (session.gotoEntryIdx % #entries) + 1
			local ep = entries[session.gotoEntryIdx]
			local entryPos = Position(ep.x, ep.y, ep.z)
			local ok, actualPos = safeTeleport(player, entryPos)
			if ok then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
					"[Hunt] Entry %d/%d: %s", session.gotoEntryIdx, #entries, fmtPos(actualPos)))
			else
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
					"[Hunt] Entry %d/%d: teleport failed at %s", session.gotoEntryIdx, #entries, fmtPos(entryPos)))
			end

		elseif target == "exit" then
			if not session.exitPos then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No exit defined.")
				return true
			end
			local ok, actualPos = safeTeleport(player, session.exitPos)
			if ok then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit: " .. fmtPos(actualPos))
			end

		elseif target == "seed" or target == "cave" then
			if not session.caveSeed then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No caveSeed. Run /hunt discover first.")
				return true
			end
			local ok, actualPos = safeTeleport(player, session.caveSeed)
			if ok then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] CaveSeed: " .. fmtPos(actualPos))
			end

		else
			-- /hunt goto <N> → teleport to discovery cluster N
			local n = tonumber(target)
			if not n then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Usage: /hunt goto, <N|entries|exit|seed>")
				return true
			end
			if not session.discoveries or n < 1 or n > #session.discoveries then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
					"[Hunt] Invalid cluster #%d. Run /hunt scan first.", n))
				return true
			end
			local c = session.discoveries[n]
			local tp
			if c.centerSpawnPos then
				tp = Position(c.centerSpawnPos.x, c.centerSpawnPos.y, c.centerSpawnPos.z)
			else
				local cx = math.floor((c.fromPos.x + c.toPos.x) / 2)
				local cy = math.floor((c.fromPos.y + c.toPos.y) / 2)
				local cz = c.fromPos.z
				if c.zLevels and #c.zLevels > 0 then
					cz = c.zLevels[math.ceil(#c.zLevels / 2)]
				end
				tp = Position(cx, cy, cz)
			end
			if not player:teleportTo(tp) then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format("[Hunt] Teleport failed at %s.", fmtPos(tp)))
				return true
			end
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				'[Hunt] Teleported to #%d "%s" at %s', n, c.autoName or "?", fmtPos(tp)))
			local monsterParts = {}
			for j, m in ipairs(c.monsters or {}) do
				if j > 5 then
					table.insert(monsterParts, "...")
					break
				end
				table.insert(monsterParts, string.format("%s x%d", m.name, m.count))
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				"[Hunt] %d spawns | %s", c.spawns or 0, table.concat(monsterParts, ", ")))
		end

	-- =========================================================================
	-- PRINT
	-- =========================================================================
	elseif action == "print" then
		if not session.caveSeed then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No active session. Use /hunt discover.")
			return true
		end
		if not session.name then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Set a name first: /hunt name, <name>")
			return true
		end
		local config = generateConfig(session)
		for _, line in ipairs(config:split("\n")) do
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, line)
		end

	-- =========================================================================
	-- SAVE
	-- =========================================================================
	elseif action == "save" then
		if not session.caveSeed then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No active session. Use /hunt discover.")
			return true
		end
		if not session.name then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Set a name first: /hunt name, <name>")
			return true
		end
		local raw = arg ~= "" and arg or session.name
		local filename = raw:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
		local filepath = "data/scripts/movements/hunt_" .. filename .. ".lua"

		local config = generateConfig(session)
		local header = string.format("-- Hunt: %s\n-- Generated by /hunt save (flood-fill from %s)\n\n", session.name, fmtPos(session.caveSeed))
		local content = header .. config .. "\n"

		local file = io.open(filepath, "w")
		if file then
			file:write(content)
			file:close()
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format("[Hunt] Saved to %s", filepath))
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Reload scripts to activate.")
		else
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format("[Hunt] Failed to write: %s", filepath))
			for _, line in ipairs(config:split("\n")) do
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, line)
			end
		end

	-- =========================================================================
	-- CLEAR
	-- =========================================================================
	elseif action == "clear" then
		clearSession(player)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Session cleared.")

	-- =========================================================================
	-- SCAN: global grid-based cluster discovery (for browsing)
	-- =========================================================================
	elseif action == "scan" then
		local minZ = 8
		local maxZ = 15
		local filterName = ""
		if arg ~= "" then
			local zMin, zMax = arg:match("^z(%d+)-(%d+)$")
			if zMin then
				minZ = tonumber(zMin)
				maxZ = tonumber(zMax)
			else
				local zMatch = arg:match("^z(%d+)$")
				if zMatch then
					minZ = tonumber(zMatch)
					maxZ = tonumber(zMatch)
				else
					filterName = arg
				end
			end
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Scanning cave clusters... (this may take a moment)")
		local clusters = Game.discoverSpawnClusters(minZ, maxZ, filterName)
		if not clusters or #clusters == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No clusters found.")
			return true
		end
		autoNameClusters(clusters)
		session.discoveries = clusters
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Found %d clusters. Use /hunt list to browse, /hunt goto <N> to teleport, /hunt accept <N> to flood-fill.", #clusters))

	-- =========================================================================
	-- LIST
	-- =========================================================================
	elseif action == "list" then
		if not session.discoveries or #session.discoveries == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No discoveries. Run /hunt scan first.")
			return true
		end
		local page = tonumber(arg) or 1
		local perPage = 10
		local startIdx = (page - 1) * perPage + 1
		local endIdx = math.min(startIdx + perPage - 1, #session.discoveries)
		local totalPages = math.ceil(#session.discoveries / perPage)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Clusters (page %d/%d, %d total):", page, totalPages, #session.discoveries))
		for i = startIdx, endIdx do
			local c = session.discoveries[i]
			if not c then break end
			local zStr = "z=?"
			if c.zLevels and #c.zLevels == 1 then
				zStr = string.format("z=%d", c.zLevels[1])
			elseif c.zLevels and #c.zLevels > 1 then
				zStr = string.format("z=%d-%d", c.zLevels[1], c.zLevels[#c.zLevels])
			end
			local monsterParts = {}
			for j, m in ipairs(c.monsters or {}) do
				if j > 3 then
					table.insert(monsterParts, "...")
					break
				end
				table.insert(monsterParts, string.format("%s x%d", m.name, m.count))
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				"  #%d: %s (%s, %d spawns) | %s",
				i, c.autoName or "?", zStr, c.spawns or 0, table.concat(monsterParts, ", ")))
		end
		if page < totalPages then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format("  Use /hunt list, %d for next page.", page + 1))
		end

	-- =========================================================================
	-- NEARBY
	-- =========================================================================
	elseif action == "nearby" then
		if not session.discoveries or #session.discoveries == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No discoveries. Run /hunt scan first.")
			return true
		end
		local ranked = {}
		for i, c in ipairs(session.discoveries) do
			if c and c.fromPos and c.toPos then
				local cx = math.floor((c.fromPos.x + c.toPos.x) / 2)
				local cy = math.floor((c.fromPos.y + c.toPos.y) / 2)
				local dist = math.abs(cx - pos.x) + math.abs(cy - pos.y)
				table.insert(ranked, { idx = i, dist = dist, cluster = c })
			end
		end
		table.sort(ranked, function(a, b) return a.dist < b.dist end)
		local count = math.min(10, #ranked)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format("[Hunt] %d nearest clusters:", count))
		for k = 1, count do
			local r = ranked[k]
			local c = r.cluster
			local zStr = "z=?"
			if c.zLevels and #c.zLevels == 1 then
				zStr = string.format("z=%d", c.zLevels[1])
			elseif c.zLevels and #c.zLevels > 1 then
				zStr = string.format("z=%d-%d", c.zLevels[1], c.zLevels[#c.zLevels])
			end
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				"  #%d: %s (%s, %d spawns, ~%d tiles away)",
				r.idx, c.autoName or "?", zStr, c.spawns or 0, r.dist))
		end

	-- =========================================================================
	-- ACCEPT: flood-fill from a cluster's center spawn position
	-- =========================================================================
	elseif action == "accept" then
		local n = tonumber(arg)
		if not n then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Usage: /hunt accept, <N>")
			return true
		end
		if not session.discoveries or n < 1 or n > #session.discoveries then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Invalid cluster number. Run /hunt scan first.")
			return true
		end
		local c = session.discoveries[n]

		-- Use cluster center spawn as flood-fill seed
		local seedPos
		if c.centerSpawnPos then
			seedPos = Position(c.centerSpawnPos.x, c.centerSpawnPos.y, c.centerSpawnPos.z)
		else
			seedPos = Position(
				math.floor((c.fromPos.x + c.toPos.x) / 2),
				math.floor((c.fromPos.y + c.toPos.y) / 2),
				c.zLevels and c.zLevels[1] or c.fromPos.z)
		end

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Flood-filling from cluster #%d center: %s...", n, fmtPos(seedPos)))

		local tempZoneName = "hunt._discover_" .. player:getGuid()
		local tempZone = Zone(tempZoneName)
		local result = tempZone:buildFromFloodFill(seedPos, 5000)

		if not result or result.tiles == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Flood-fill found 0 tiles from cluster center.")
			return true
		end

		session.caveSeed = seedPos
		session.floodFillResult = result
		session.maxCaveTiles = 5000
		session.gotoEntryIdx = 0

		-- Auto-name
		session.name = c.autoName or string.format("Cave #%d", n)

		-- Auto-exit from entries
		if result.entries and #result.entries > 0 then
			local bestEntry = result.entries[1]
			for _, ep in ipairs(result.entries) do
				if ep.z < bestEntry.z then
					bestEntry = ep
				end
			end
			session.exitPos = Position(bestEntry.x, bestEntry.y, bestEntry.z)
		end

		local zStr = "?"
		if result.zLevels then
			local parts = {}
			for _, z in ipairs(result.zLevels) do
				table.insert(parts, tostring(z))
			end
			zStr = table.concat(parts, ",")
		end

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			'[Hunt] Accepted #%d "%s": %d tiles, z=[%s], %d spawns, %d entries.',
			n, session.name, result.tiles, zStr, result.spawns, result.entries and #result.entries or 0))
		if session.exitPos then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit (auto): " .. fmtPos(session.exitPos))
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Use /hunt goto entries/exit/seed to validate. /hunt save to write config.")

	-- =========================================================================
	-- HELP
	-- =========================================================================
	else
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Commands: (discovery)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt discover[, maxTiles]  flood-fill from stair/hole or current pos")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt scan[, filter]        global grid scan (browse clusters)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt list[, page]          browse scanned clusters")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt nearby                10 nearest clusters")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt goto, <N>             teleport to cluster N")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt accept, <N>           flood-fill from cluster N center")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Commands: (editing)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt name, <name>          set hunt name")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt exit                  set exit position")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Commands: (validation)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt status                show session info")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt goto, entries          cycle entries")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt goto, exit/seed       teleport to exit/seed")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt test                  create test instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Commands: (output)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt print                 show config")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt save[, filename]      save config to disk")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt clear                 reset session")
	end

	return true
end

huntHelper:separator(" ")
huntHelper:groupType("gamemaster")
huntHelper:register()
