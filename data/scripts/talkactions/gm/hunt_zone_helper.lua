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
--   /hunt scan[, filter]        → grid-based cluster discovery (for browsing)
--   /hunt list[, page]          → browse clusters
--   /hunt nearby                → 10 nearest clusters
--   /hunt goto, <N>             → teleport to cluster center
--   /hunt accept, <N>           → flood-fill from cluster center spawn, load into session
--
-- Batch registration:
--   /hunt batch[, dry][, N/T][, zN-M] → auto-register all caves matching criteria

-- ============================================================================
-- Utility: compute stair/hole destination — delegates to C++ Tile:getFloorchangeDestination()
-- ============================================================================

local function computeFloorchangeDestination(tile)
	if not tile then return nil end
	return tile:getFloorchangeDestination()
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

-- Returns sorted list of {name, count} for spawns within an area.
-- If `zone` is provided, only counts spawns whose position is inside the zone
-- (precise irregular-shape filter). Otherwise uses the rectangular bbox only.
local function getMonsterBreakdown(fromPos, toPos, zone)
	local spawns = Game.getSpawnsInArea(fromPos, toPos)
	if not spawns or #spawns == 0 then return {} end
	local counts = {}
	for _, s in ipairs(spawns) do
		if not zone or zone:contains(Position(s.x, s.y, s.z)) then
			counts[s.name] = (counts[s.name] or 0) + 1
		end
	end
	local list = {}
	for name, count in pairs(counts) do
		table.insert(list, { name = name, count = count })
	end
	table.sort(list, function(a, b) return a.count > b.count end)
	return list
end

local function getDominantMonsterInArea(fromPos, toPos)
	local list = getMonsterBreakdown(fromPos, toPos)
	return list[1] and list[1].name or nil
end

-- huntNameRegistry is only used by autoNameClusters (batch scan/list flow).
-- For individual /hunt discover we don't use a counter suffix.
local huntNameRegistry = {}

local function autoNameFromBBox(fromPos, toPos, centerX, centerY)
	local dominant = getDominantMonsterInArea(fromPos, toPos)
	local townName = getNearestTownName(centerX, centerY)
	if not dominant then
		return string.format("Cave - %s", townName)
	end
	return string.format("%s - %s", dominant, townName)
end

local function sanitizeFilename(name)
	return name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local function huntFileExists(name)
	local filepath = "data/scripts/movements/hunt_" .. sanitizeFilename(name) .. ".lua"
	local f = io.open(filepath, "r")
	if f then
		f:close()
		return true
	end
	return false
end

local function autoNameClusters(clusters, skipExistingFiles)
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
			local candidateName
			if idx == 1 then
				candidateName = string.format("%s - %s", dominant, townName)
			else
				candidateName = string.format("%s - %s #%d", dominant, townName, idx)
			end
			if skipExistingFiles then
				while huntFileExists(candidateName) do
					batchIndex[baseKey] = batchIndex[baseKey] + 1
					idx = batchIndex[baseKey]
					candidateName = string.format("%s - %s #%d", dominant, townName, idx)
				end
			end
			cluster.autoName = candidateName
		else
			cluster.autoName = "Empty Cluster"
		end
	end
end

-- ============================================================================
-- Shared helpers: expansion, classification, processing
-- ============================================================================

-- Numeric position key: avoids string concatenation + GC pressure for large zones.
-- Safe for OT map coords (x/y <= 65535, z <= 15).
local function posKey(p)
	return p.z * 4294967296 + p.y * 65536 + p.x
end

local function expandZoneConnections(zone, maxTiles)
	local followedSources = {}
	local checkedPositions = {}

	-- Compute initial bbox ONCE from the initial zone (before the loop).
	-- Maintained incrementally from newDestinations after each expansion,
	-- which avoids rescanning all N positions for bbox every iteration.
	local minX, minY, maxX, maxY = 65535, 65535, 0, 0
	for _, p in ipairs(zone:getPositions()) do
		if p.x < minX then minX = p.x end
		if p.y < minY then minY = p.y end
		if p.x > maxX then maxX = p.x end
		if p.y > maxY then maxY = p.y end
	end

	for _ = 1, 10 do
		local newDestinations = {}
		local seenDests = {}

		-- Floor-change detection. zone:getPositions() is O(N) each call (C++ copy),
		-- but checkedPositions ensures Tile() is only called for NEW tiles.
		-- The bbox is NOT recomputed here — it's maintained incrementally below.
		for _, p in ipairs(zone:getPositions()) do
			local pk = posKey(p)
			if not checkedPositions[pk] then
				checkedPositions[pk] = true
				local tile = Tile(Position(p.x, p.y, p.z))
				if tile then
					if tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_FLOORCHANGE_DOWN) then
						local dest = tile:getFloorchangeDestination()
						if dest and dest.x ~= 0 and not zone:contains(dest) then
							local dk = posKey(dest)
							if not seenDests[dk] then
								seenDests[dk] = true
								table.insert(newDestinations, dest)
							end
						end
					end
				end
			end
		end

		-- Script teleport lookup uses the maintained bbox (not recomputed from scratch).
		local searchFrom = Position(math.max(minX - 1, 0), math.max(minY - 1, 0), 0)
		local searchTo = Position(maxX + 1, maxY + 1, 15)
		for _, tp in ipairs(getScriptTeleportsWithSourceInArea(searchFrom, searchTo)) do
			local sk = posKey(tp.source)
			if not followedSources[sk]
				and zone:contains(tp.source)
				and not zone:contains(tp.dest) then
				followedSources[sk] = true
				local dk = posKey(tp.dest)
				if not seenDests[dk] then
					seenDests[dk] = true
					table.insert(newDestinations, tp.dest)
				end
			end
		end

		if #newDestinations == 0 then break end
		if zone:expandFromFloodFill(newDestinations, maxTiles) == 0 then break end

		-- Update bbox from the destination seeds of this expansion.
		-- The BFS from these seeds may add tiles beyond them, but bbox only grows,
		-- so the next iteration's teleport search will be conservative (safe).
		for _, d in ipairs(newDestinations) do
			if d.x < minX then minX = d.x end
			if d.y < minY then minY = d.y end
			if d.x > maxX then maxX = d.x end
			if d.y > maxY then maxY = d.y end
		end
	end
end

local function computeZoneStats(zone)
	local positions = zone:getPositions()
	if not positions or #positions == 0 then
		return nil
	end
	local minX, minY, minZ = 65535, 65535, 255
	local maxX, maxY, maxZ = 0, 0, 0
	local zSet = {}
	for _, p in ipairs(positions) do
		if p.x < minX then minX = p.x end
		if p.y < minY then minY = p.y end
		if p.z < minZ then minZ = p.z end
		if p.x > maxX then maxX = p.x end
		if p.y > maxY then maxY = p.y end
		if p.z > maxZ then maxZ = p.z end
		zSet[p.z] = true
	end
	local zList = {}
	for z, _ in pairs(zSet) do table.insert(zList, z) end
	table.sort(zList)
	local spawns = Game.getSpawnsInArea(
		Position(minX, minY, minZ),
		Position(maxX, maxY, maxZ))
	return {
		tiles = #positions,
		bboxMin = { x = minX, y = minY, z = minZ },
		bboxMax = { x = maxX, y = maxY, z = maxZ },
		zLevels = zList,
		spawns = spawns and #spawns or 0,
	}
end

local function classifyZoneTeleports(zone, bboxFrom, bboxTo)
	local teleportEntries = {}
	local exitTeleports = {}
	local internalTeleports = {}
	local seen = {}
	local allTeleports = {}

	for _, tp in ipairs(getScriptTeleportSourcesToArea(bboxFrom, bboxTo)) do
		local key = tp.source.x .. ":" .. tp.source.y .. ":" .. tp.source.z
		if not seen[key] then
			seen[key] = true
			allTeleports[#allTeleports + 1] = tp
		end
	end
	for _, tp in ipairs(getScriptTeleportsWithSourceInArea(bboxFrom, bboxTo)) do
		local key = tp.source.x .. ":" .. tp.source.y .. ":" .. tp.source.z
		if not seen[key] then
			seen[key] = true
			allTeleports[#allTeleports + 1] = tp
		end
	end

	for _, tp in ipairs(allTeleports) do
		local sourceInside = zone:contains(tp.source)
		local destInside = zone:contains(tp.dest)
		if sourceInside and destInside then
			internalTeleports[#internalTeleports + 1] = { source = tp.source, dest = tp.dest }
		elseif not sourceInside and destInside then
			teleportEntries[#teleportEntries + 1] = { source = tp.source, dest = tp.dest }
		elseif sourceInside and not destInside then
			exitTeleports[#exitTeleports + 1] = { source = tp.source, dest = tp.dest }
		end
	end
	return teleportEntries, exitTeleports, internalTeleports
end

local function processCluster(cluster, tempZoneName, maxTiles, maxDistance)
	maxTiles = maxTiles or 5000
	maxDistance = maxDistance or 300

	local seedPos
	if cluster.centerSpawnPos then
		seedPos = Position(cluster.centerSpawnPos.x, cluster.centerSpawnPos.y, cluster.centerSpawnPos.z)
	else
		seedPos = Position(
			math.floor((cluster.fromPos.x + cluster.toPos.x) / 2),
			math.floor((cluster.fromPos.y + cluster.toPos.y) / 2),
			cluster.zLevels and cluster.zLevels[1] or cluster.fromPos.z)
	end

	local zone = Zone(tempZoneName)
	local result = zone:buildFromFloodFill(seedPos, maxTiles, maxDistance)
	if not result or result.tiles == 0 then
		return nil, "flood-fill found 0 tiles"
	end

	expandZoneConnections(zone, maxTiles)

	local stats = computeZoneStats(zone)
	if not stats then
		return nil, "zone empty after expansion"
	end

	local bboxFrom = Position(stats.bboxMin.x, stats.bboxMin.y, stats.bboxMin.z)
	local bboxTo = Position(stats.bboxMax.x, stats.bboxMax.y, stats.bboxMax.z)
	local teleportEntries, exitTeleports, internalTeleports = classifyZoneTeleports(zone, bboxFrom, bboxTo)

	local allEntryPositions = {}
	local function posInList(list, x, y, z)
		for _, p in ipairs(list) do
			if p.x == x and p.y == y and p.z == z then return true end
		end
		return false
	end
	if result.entries then
		for _, ep in ipairs(result.entries) do
			allEntryPositions[#allEntryPositions + 1] = Position(ep.x, ep.y, ep.z)
		end
	end
	for _, tp in ipairs(teleportEntries) do
		local sx, sy, sz = tp.source.x, tp.source.y, tp.source.z
		if not posInList(allEntryPositions, sx, sy, sz) then
			allEntryPositions[#allEntryPositions + 1] = Position(sx, sy, sz)
		end
	end

	local exitPos = nil
	local exitIsBestGuess = false
	if #exitTeleports > 0 then
		local tp = exitTeleports[1]
		exitPos = Position(tp.dest.x, tp.dest.y, tp.dest.z)
	elseif result.entries and #result.entries > 0 then
		local bestEntry = result.entries[1]
		for _, ep in ipairs(result.entries) do
			if ep.z < bestEntry.z then bestEntry = ep end
		end
		exitPos = Position(bestEntry.x, bestEntry.y, bestEntry.z)
	elseif #teleportEntries > 0 then
		exitPos = Position(teleportEntries[1].source.x, teleportEntries[1].source.y, teleportEntries[1].source.z)
	else
		exitPos = seedPos
		exitIsBestGuess = true
	end

	return {
		caveSeed = seedPos,
		exitPos = exitPos,
		exitIsBestGuess = exitIsBestGuess,
		tiles = stats.tiles,
		bboxMin = stats.bboxMin,
		bboxMax = stats.bboxMax,
		zLevels = stats.zLevels,
		spawns = stats.spawns,
		teleportEntries = teleportEntries,
		exitTeleports = exitTeleports,
		internalTeleports = internalTeleports,
		allEntryPositions = allEntryPositions,
		floodFillResult = result,
		maxCaveTiles = maxTiles,
		maxDistance = maxDistance,
	}
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
	local guid = player:getGuid()
	Zone.removeByName("hunt._discover_" .. guid)
	sessions[guid] = nil
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

	if session.exitPos then
		if session.exitIsBestGuess then
			table.insert(lines, string.format('    exit = %s, -- TODO: verify exit position', fmtPos(session.exitPos)))
		else
			table.insert(lines, string.format('    exit = %s,', fmtPos(session.exitPos)))
		end
	else
		table.insert(lines, '    exit = Position(0, 0, 7), -- TODO: set exit')
	end

	if session.maxCaveTiles and session.maxCaveTiles ~= 5000 then
		table.insert(lines, string.format('    maxCaveTiles = %d,', session.maxCaveTiles))
	end
	if session.maxDistance and session.maxDistance ~= 300 then
		table.insert(lines, string.format('    maxDistance = %d,', session.maxDistance))
	end

	table.insert(lines, '    requiredLevel = 0,')
	table.insert(lines, '    cooldownTime = 0,')
	table.insert(lines, '    maxInstances = 20,')
	table.insert(lines, '})')
	table.insert(lines, 'hunt:register()')

	-- Append discovered entries/exits as comments for documentation
	table.insert(lines, '')
	if session.teleportEntries and #session.teleportEntries > 0 then
		table.insert(lines, '-- Discovered teleport entries:')
		for _, tp in ipairs(session.teleportEntries) do
			table.insert(lines, string.format('--   (%d,%d,%d) -> (%d,%d,%d)',
				tp.source.x, tp.source.y, tp.source.z,
				tp.dest.x, tp.dest.y, tp.dest.z))
		end
	end
	if session.exitTeleports and #session.exitTeleports > 0 then
		table.insert(lines, '-- Discovered exit teleports:')
		for _, tp in ipairs(session.exitTeleports) do
			local src = tp.source or tp[1]
			local dest = tp.dest or tp[2]
			if src and dest then
				table.insert(lines, string.format('--   (%d,%d,%d) -> (%d,%d,%d)',
					src.x, src.y, src.z, dest.x, dest.y, dest.z))
			end
		end
	end
	if session.internalTeleports and #session.internalTeleports > 0 then
		table.insert(lines, string.format('-- Internal teleports: %d', #session.internalTeleports))
	end

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

		-- /hunt discover[, maxTiles[, maxDistance]]
		-- maxTiles: hard cap on total zone tiles (default 5000)
		-- maxDistance: Chebyshev distance cap from seed for the initial BFS (default 300)
		--   300 tiles is enough for any normal cave while stopping BFS from crossing to
		--   other cave systems at the same z-level (Port Hope z=8 <-> Venore z=8 is ~1200 tiles).
		local params = arg:split("/")
		local maxTiles = tonumber(params[1] and params[1]:trim()) or tonumber(arg) or 5000
		local maxDistance = tonumber(params[2] and params[2]:trim()) or 300

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Flood-filling from %s (max %d tiles, radius %d)...", fmtPos(seedPos), maxTiles, maxDistance))

		-- Create a temporary zone for the flood-fill
		local tempZoneName = "hunt._discover_" .. player:getGuid()
		local tempZone = Zone(tempZoneName)
		local result = tempZone:buildFromFloodFill(seedPos, maxTiles, maxDistance)

		if not result or result.tiles == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Flood-fill found 0 tiles. Position may be blocked or invalid.")
			return true
		end

		local initialTiles = result.tilesAdded or result.tiles or 0

		session.caveSeed = seedPos
		session.floodFillResult = result
		session.maxCaveTiles = maxTiles
		session.maxDistance = maxDistance
		-- Reset name so it's recalculated from the current discover result, not a stale prior run
		session.name = nil
		-- Save the original bbox from buildFromFloodFill (before the expansion loop potentially
		-- inflates it) — used for naming so the dominant monster comes from the real cave z-level.
		local namingBboxMin = result.bboxMin
		local namingBboxMax = result.bboxMax

		expandZoneConnections(tempZone, maxTiles)

		-- Recalculate result after expansion
		local stats = computeZoneStats(tempZone)
		if stats then
			result.tiles = stats.tiles
			result.bboxMin = stats.bboxMin
			result.bboxMax = stats.bboxMax
			result.zLevels = stats.zLevels
			result.spawns = stats.spawns
		end

	-- Classify script teleports
	session.teleportEntries = {}
	session.internalTeleports = {}
	session.exitTeleports = {}

	if result.bboxMin and result.bboxMax then
		local bboxFrom = Position(result.bboxMin.x, result.bboxMin.y, result.bboxMin.z)
		local bboxTo = Position(result.bboxMax.x, result.bboxMax.y, result.bboxMax.z)
		session.teleportEntries, session.exitTeleports, session.internalTeleports =
			classifyZoneTeleports(tempZone, bboxFrom, bboxTo)
	end

	-- Unified entry positions for /hunt goto entries
	session.allEntryPositions = {}
	local function posAlreadyInList(list, x, y, z)
		for _, p in ipairs(list) do
			if p.x == x and p.y == y and p.z == z then return true end
		end
		return false
	end
	if result.entries then
		for _, ep in ipairs(result.entries) do
			session.allEntryPositions[#session.allEntryPositions + 1] = Position(ep.x, ep.y, ep.z)
		end
	end
	for _, tp in ipairs(session.teleportEntries) do
		local sx, sy, sz = tp.source.x, tp.source.y, tp.source.z
		if not posAlreadyInList(session.allEntryPositions, sx, sy, sz) then
			session.allEntryPositions[#session.allEntryPositions + 1] = Position(sx, sy, sz)
		end
	end

	-- Auto-detect exit
	if #session.exitTeleports > 0 then
		local tp = session.exitTeleports[1]
		session.exitPos = Position(tp.dest.x, tp.dest.y, tp.dest.z)
	elseif result.entries and #result.entries > 0 then
		local bestEntry = result.entries[1]
		for _, ep in ipairs(result.entries) do
			if ep.z < bestEntry.z then bestEntry = ep end
		end
		session.exitPos = Position(bestEntry.x, bestEntry.y, bestEntry.z)
	elseif #session.teleportEntries > 0 then
		local tp = session.teleportEntries[1]
		session.exitPos = Position(tp.source.x, tp.source.y, tp.source.z)
	end

	-- Auto-name using the original buildFromFloodFill bbox (before expansion inflates it).
	if not session.name then
		if namingBboxMin and namingBboxMax then
			local cx = math.floor((namingBboxMin.x + namingBboxMax.x) / 2)
			local cy = math.floor((namingBboxMin.y + namingBboxMax.y) / 2)
			session.name = autoNameFromBBox(
				Position(namingBboxMin.x, namingBboxMin.y, namingBboxMin.z),
				Position(namingBboxMax.x, namingBboxMax.y, namingBboxMax.z),
				cx, cy)
		else
			local townName = getNearestTownName(seedPos.x, seedPos.y)
			session.name = string.format("Cave - %s", townName)
		end
	end

	-- Monster breakdown: use original bbox for the query rectangle but filter by
	-- actual zone membership so L-shaped caves don't include unrelated spawns.
	local monsterBreakdown = {}
	if namingBboxMin and namingBboxMax then
		monsterBreakdown = getMonsterBreakdown(
			Position(namingBboxMin.x, namingBboxMin.y, namingBboxMin.z),
			Position(namingBboxMax.x, namingBboxMax.y, namingBboxMax.z),
			tempZone)
	end

	-- ── Output ────────────────────────────────────────────────────────────────
	local zStr = "?"
	if result.zLevels then
		local parts = {}
		for _, z in ipairs(result.zLevels) do table.insert(parts, tostring(z)) end
		zStr = table.concat(parts, ",")
	end

	local expandedTiles = result.tiles - initialTiles
	local tileStr
	if expandedTiles > 0 then
		tileStr = string.format("%d tiles (%d initial + %d via script teleports)", result.tiles, initialTiles, expandedTiles)
	else
		tileStr = string.format("%d tiles", result.tiles)
	end

	local bboxW = (result.bboxMax and result.bboxMin) and (result.bboxMax.x - result.bboxMin.x + 1) or 0
	local bboxH = (result.bboxMax and result.bboxMin) and (result.bboxMax.y - result.bboxMin.y + 1) or 0
	local totalEntries = (result.entries and #result.entries or 0) + #session.teleportEntries

	player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
		'[Hunt] Discovered: %s, z=[%s], bbox %dx%d',
		tileStr, zStr, bboxW, bboxH))
	player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
		'[Hunt] Spawns: %d total | Entries: %d (%d stair, %d teleport) | Internal tp: %d',
		result.spawns, totalEntries,
		result.entries and #result.entries or 0,
		#session.teleportEntries,
		#session.internalTeleports))
	player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
		'[Hunt] Name: "%s". Use /hunt name, <name> to change.', session.name))

	if #monsterBreakdown > 0 then
		local parts = {}
		for i, m in ipairs(monsterBreakdown) do
			if i > 6 then
				table.insert(parts, string.format("...+%d more types", #monsterBreakdown - 6))
				break
			end
			table.insert(parts, string.format("%s x%d", m.name, m.count))
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Monsters: " .. table.concat(parts, ", "))
	end

	if result.entries and #result.entries > 0 then
		local entryList = {}
		for i, ep in ipairs(result.entries) do
			if i > 5 then table.insert(entryList, "...") break end
			table.insert(entryList, string.format("(%d,%d,%d)", ep.x, ep.y, ep.z))
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Stair entries: " .. table.concat(entryList, ", "))
	end

	if #session.teleportEntries > 0 then
		local tpList = {}
		for i, tp in ipairs(session.teleportEntries) do
			if i > 5 then table.insert(tpList, "...") break end
			table.insert(tpList, string.format("(%d,%d,%d)->(%d,%d,%d)",
				tp.source.x, tp.source.y, tp.source.z,
				tp.dest.x, tp.dest.y, tp.dest.z))
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Teleport entries: " .. table.concat(tpList, ", "))
	end

	if #session.exitTeleports > 0 then
		local tpList = {}
		for i, tp in ipairs(session.exitTeleports) do
			if i > 5 then table.insert(tpList, "...") break end
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

	if initialTiles >= maxTiles then
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] WARNING: Initial fill hit tile limit (%d). Cave may be larger than shown. " ..
			"Use /hunt discover, %d to increase, or /hunt discover, %d/%d to also expand radius.",
			maxTiles, maxTiles * 2, maxTiles * 2, maxDistance))
	end

	player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
		"[Hunt] Validate: /hunt goto entries | /hunt goto exit | /hunt goto seed")
	player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
		"[Hunt] Confirm: /hunt name, <name> | /hunt save")

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
		local testSeed = session.caveSeed
		local testMaxTiles = session.maxCaveTiles or 5000
		local testRadius = session.maxDistance or 300
		local result = tempZone:buildFromFloodFill(testSeed, testMaxTiles, testRadius)

		expandZoneConnections(tempZone, testMaxTiles)

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
			local entries = session.allEntryPositions
			if not entries or #entries == 0 then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No entries detected.")
				return true
			end
			local n = #entries
			session.gotoEntryIdx = (session.gotoEntryIdx % n) + 1
			local entryPos = entries[session.gotoEntryIdx]
			local ok, actualPos = safeTeleport(player, entryPos)
			if ok then
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
					"[Hunt] Entry %d/%d: %s", session.gotoEntryIdx, n, fmtPos(actualPos)))
			else
				player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
					"[Hunt] Entry %d/%d: teleport failed at %s", session.gotoEntryIdx, n, fmtPos(entryPos)))
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
		local filepath = "data/scripts/movements/hunt_" .. sanitizeFilename(raw) .. ".lua"

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

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Flood-filling from cluster #%d...", n))

		local tempZoneName = "hunt._discover_" .. player:getGuid()
		local result, reason = processCluster(c, tempZoneName)
		if not result then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format("[Hunt] Failed: %s", reason))
			return true
		end

		session.caveSeed = result.caveSeed
		session.floodFillResult = result.floodFillResult
		session.maxCaveTiles = result.maxCaveTiles
		session.maxDistance = result.maxDistance
		session.gotoEntryIdx = 0
		session.teleportEntries = result.teleportEntries
		session.exitTeleports = result.exitTeleports
		session.internalTeleports = result.internalTeleports
		session.allEntryPositions = result.allEntryPositions
		session.name = c.autoName or string.format("Cave #%d", n)
		session.exitPos = result.exitPos

		local zStr = "?"
		if result.zLevels then
			local parts = {}
			for _, z in ipairs(result.zLevels) do table.insert(parts, tostring(z)) end
			zStr = table.concat(parts, ",")
		end

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			'[Hunt] Accepted #%d "%s": %d tiles, z=[%s], %d spawns, %d entries.',
			n, session.name, result.tiles, zStr, result.spawns,
			result.floodFillResult.entries and #result.floodFillResult.entries or 0))
		if session.exitPos then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Exit (auto): " .. fmtPos(session.exitPos))
		end
		if result.exitIsBestGuess then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] WARNING: No exit detected, using seed as fallback. Use /hunt exit to set manually.")
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Use /hunt goto entries/exit/seed to validate. /hunt save to write config.")

	-- =========================================================================
	-- CATALOG: collect cluster data with NO flood-fill and write a catalog file.
	-- Fast (seconds). Lets the user pick which caves to actually register,
	-- then use /hunt batch ids=<list> for targeted flood-fill.
	--
	-- Usage: /hunt catalog[, zN-M][, expN][, minS]
	-- Example: /hunt catalog, z8-15, exp2000, 20
	-- =========================================================================
	elseif action == "catalog" then
		local minZ = 8
		local maxZ = 15
		local minSpawns = 0
		local minExp = 0

		local catArgs = param:split(",")
		for i = 2, #catArgs do
			local a = catArgs[i]:trim():lower()
			local expVal = a:match("^exp(%d+)$")
			if expVal then
				minExp = tonumber(expVal)
			else
				local zMin, zMax = a:match("^z(%d+)-(%d+)$")
				if zMin then
					minZ = tonumber(zMin)
					maxZ = tonumber(zMax)
				else
					local zMatch = a:match("^z(%d+)$")
					if zMatch then
						minZ = tonumber(zMatch)
						maxZ = tonumber(zMatch)
					elseif tonumber(a) then
						minSpawns = tonumber(a)
					end
				end
			end
		end

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Building catalog (z%d-%d, minSpawns=%d, minExp=%d)...",
			minZ, maxZ, minSpawns, minExp))

		local clusters = Game.discoverSpawnClusters(minZ, maxZ, "")
		if not clusters or #clusters == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No clusters found.")
			return true
		end

		-- Cache towns once — getNearestTownName calls Game.getTowns() every invocation.
		local towns = Game.getTowns()
		local townCache = {}
		for _, town in ipairs(towns) do
			local tp = town:getTemplePosition()
			townCache[#townCache + 1] = { name = town:getName(), x = tp.x, y = tp.y }
		end
		local function nearestTownCached(cx, cy)
			local best, bestDist = "Unknown", math.huge
			for _, t in ipairs(townCache) do
				local d = (t.x - cx) * (t.x - cx) + (t.y - cy) * (t.y - cy)
				if d < bestDist then bestDist = d; best = t.name end
			end
			return best
		end

		-- Quality tier based on dominant monster exp
		local function qualityTier(exp)
			if exp >= 5000 then return "S"
			elseif exp >= 2000 then return "A"
			elseif exp >= 1000 then return "B"
			else return "C" end
		end

		-- Process each cluster (no flood-fill — pure data from discoverSpawnClusters)
		local rows = {}
		local skippedCount = 0
		for i, cluster in ipairs(clusters) do
			local dominant = cluster.monsters and cluster.monsters[1] and cluster.monsters[1].name or nil
			local domExp = 0
			if dominant then
				local mt = MonsterType(dominant)
				domExp = mt and mt:experience() or 0
			end

			if (cluster.spawns or 0) < minSpawns or domExp < minExp then
				skippedCount = skippedCount + 1
			else
				local cx = math.floor((cluster.fromPos.x + cluster.toPos.x) / 2)
				local cy = math.floor((cluster.fromPos.y + cluster.toPos.y) / 2)
				local cz = cluster.zLevels and cluster.zLevels[1] or cluster.fromPos.z
				local bboxW = cluster.toPos.x - cluster.fromPos.x + 1
				local bboxH = cluster.toPos.y - cluster.fromPos.y + 1
				local town = nearestTownCached(cx, cy)
				local autoName = dominant
					and string.format("%s - %s", dominant, town)
					or string.format("Cave - %s", town)

				local zStr = ""
				if cluster.zLevels then
					local parts = {}
					for _, z in ipairs(cluster.zLevels) do parts[#parts + 1] = tostring(z) end
					zStr = table.concat(parts, ",")
				end

				-- Top-3 monsters for detail line
				local monParts = {}
				for j, m in ipairs(cluster.monsters or {}) do
					if j > 3 then monParts[#monParts + 1] = "..."; break end
					monParts[#monParts + 1] = string.format("%s(%d)", m.name, m.count)
				end
				local monStr = table.concat(monParts, "; ")

				rows[#rows + 1] = {
					id = i,
					name = autoName,
					spawns = cluster.spawns or 0,
					domExp = domExp,
					tier = qualityTier(domExp),
					zStr = zStr,
					bboxW = bboxW,
					bboxH = bboxH,
					cx = cx, cy = cy, cz = cz,
					monStr = monStr,
					numZLevels = cluster.zLevels and #cluster.zLevels or 1,
				}
			end
		end

		-- Sort by dominant exp descending (highest value first)
		table.sort(rows, function(a, b) return a.domExp > b.domExp end)

		-- ── Write formatted text catalog ──────────────────────────────────────
		local TXT_PATH = "data/hunt_catalog.txt"
		local CSV_PATH = "data/hunt_catalog.csv"

		local txtLines = {}
		txtLines[#txtLines + 1] = string.format(
			"=== Hunt Catalog | z%d-%d | %d clusters → %d listed (sorted by exp) ===",
			minZ, maxZ, #clusters, #rows)
		txtLines[#txtLines + 1] = string.format(
			"%-5s %-4s %-7s %-6s %-16s %-11s %s",
			"ID", "Tier", "Spawns", "DomExp", "Z-Levels", "BboxWxH", "Name")
		txtLines[#txtLines + 1] = string.rep("-", 100)

		local csvLines = {}
		csvLines[#csvLines + 1] = "id,name,spawns,dominant_exp,tier,z_levels,bbox_w,bbox_h,center_x,center_y,center_z,z_count,monsters"

		for _, row in ipairs(rows) do
			-- Text: summary line + monster detail line
			txtLines[#txtLines + 1] = string.format(
				"%-5d %-4s %-7d %-6d %-16s %-11s %s",
				row.id, row.tier, row.spawns, row.domExp, row.zStr,
				row.bboxW .. "x" .. row.bboxH, row.name)
			txtLines[#txtLines + 1] = string.format(
				"      center=(%d,%d,%d)  monsters: %s",
				row.cx, row.cy, row.cz, row.monStr)

			-- CSV row
			local csvName = '"' .. row.name:gsub('"', '""') .. '"'
			local csvMons = '"' .. row.monStr:gsub('"', '""') .. '"'
			csvLines[#csvLines + 1] = string.format(
				"%d,%s,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%s",
				row.id, csvName, row.spawns, row.domExp, row.tier, row.zStr,
				row.bboxW, row.bboxH, row.cx, row.cy, row.cz, row.numZLevels, csvMons)
		end

		txtLines[#txtLines + 1] = ""
		txtLines[#txtLines + 1] = string.format(
			"Skipped: %d (below filters). Total scanned: %d.", skippedCount, #clusters)
		txtLines[#txtLines + 1] = ""
		txtLines[#txtLines + 1] = "To flood-fill and save specific clusters:"
		txtLines[#txtLines + 1] = "  /hunt batch, ids=10 18 63 68, 20/500"

		local f = io.open(TXT_PATH, "w")
		if f then f:write(table.concat(txtLines, "\n") .. "\n"); f:close() end

		local g = io.open(CSV_PATH, "w")
		if g then g:write(table.concat(csvLines, "\n") .. "\n"); g:close() end

		-- Store in session so /hunt goto <N> works immediately
		autoNameClusters(clusters)
		session.discoveries = clusters

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Catalog ready: %d clusters listed (%d skipped). Written to:",
			#rows, skippedCount))
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  data/hunt_catalog.txt  (sorted by exp, human-readable)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  data/hunt_catalog.csv  (importable into spreadsheet)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
			"[Hunt] Pick IDs, then: /hunt batch, ids=3 10 18 63, 20/500")

	-- =========================================================================
	-- BATCH: automated scan + accept + save for all qualifying clusters
	-- Uses addEvent to process one cluster per tick so the server stays responsive.
	-- =========================================================================
	elseif action == "batch" then
		local dryRun = false
		local requireExit = false
		local minSpawns = 5
		local minTiles = 50
		local minZ = 8
		local maxZ = 15
		local minExp = 0
		local selectedIds = nil  -- if set, only process these cluster IDs

		local batchArgs = param:split(",")
		for i = 2, #batchArgs do
			local a = batchArgs[i]:trim()
			local aLower = a:lower()
			if aLower == "dry" then
				dryRun = true
			elseif aLower == "requireexit" then
				requireExit = true
			else
				-- ids=3 10 18 63  OR  ids=3,10,18,63 (already split by comma so each a is one id)
				-- ids= can appear as a single arg "ids=3 10 18" (space-separated in one token)
				local idsStr = a:match("^[Ii][Dd][Ss]=(.+)$")
				if idsStr then
					selectedIds = {}
					for idStr in idsStr:gmatch("%d+") do
						selectedIds[tonumber(idStr)] = true
					end
				elseif aLower:match("^exp(%d+)$") then
					minExp = tonumber(aLower:match("^exp(%d+)$"))
				else
					local zMin, zMax = aLower:match("^z(%d+)-(%d+)$")
					if zMin then
						minZ = tonumber(zMin)
						maxZ = tonumber(zMax)
					else
						local zMatch = aLower:match("^z(%d+)$")
						if zMatch then
							minZ = tonumber(zMatch)
							maxZ = tonumber(zMatch)
						else
							local sMin, sTiles = aLower:match("^(%d+)/(%d+)$")
							if sMin then
								minSpawns = tonumber(sMin)
								minTiles = tonumber(sTiles)
							elseif tonumber(aLower) then
								minSpawns = tonumber(aLower)
							end
						end
					end
				end
			end
		end

		local filterStr = string.format("z%d-%d, min %d spawns, min %d tiles", minZ, maxZ, minSpawns, minTiles)
		if minExp > 0 then filterStr = filterStr .. string.format(", min %d exp", minExp) end
		if requireExit then filterStr = filterStr .. ", requireexit" end
		if selectedIds then
			local idList = {}
			for id, _ in pairs(selectedIds) do idList[#idList + 1] = tostring(id) end
			table.sort(idList, function(a, b) return tonumber(a) < tonumber(b) end)
			filterStr = filterStr .. " | targeted IDs: " .. table.concat(idList, ",")
		end

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Batch %s: scanning clusters (%s)...",
			dryRun and "DRY RUN" or "SAVE", filterStr))

		local clusters
		-- If we have a prior scan in session and ids= is specified, reuse it to skip discoverSpawnClusters
		if selectedIds and session.discoveries and #session.discoveries > 0 then
			clusters = session.discoveries
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
				"[Hunt] Reusing cached scan (%d clusters). Filtering to selected IDs.", #clusters))
		else
			clusters = Game.discoverSpawnClusters(minZ, maxZ, "")
		end

		if not clusters or #clusters == 0 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] No clusters found.")
			return true
		end
		autoNameClusters(clusters, not dryRun)

		local BATCH_LOG_PATH = "data/hunt_batch_results.txt"

		-- Truncate/init the log file for this run
		local initLog = io.open(BATCH_LOG_PATH, "w")
		if initLog then
			initLog:write(string.format("=== /hunt batch %s started: %d clusters, %s ===\n",
				dryRun and "DRY RUN" or "SAVE", #clusters, filterStr))
			initLog:close()
		end

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, string.format(
			"[Hunt] Found %d clusters. Running headlessly — results in data/hunt_batch_results.txt. You can disconnect.", #clusters))

		local state = {
			clusters = clusters,
			idx = 1,
			saved = 0,
			skipped = 0,
			skipReasons = { small = 0, exists = 0, overlap = 0, tiles = 0, failed = 0, lowExp = 0, noexit = 0 },
			batchZones = {},
			dryRun = dryRun,
			requireExit = requireExit,
			selectedIds = selectedIds,
			minSpawns = minSpawns,
			minTiles = minTiles,
			minExp = minExp,
			playerId = player:getId(),
		}

		local function batchLog(s, line)
			local f = io.open(BATCH_LOG_PATH, "a")
			if f then f:write(line .. "\n"); f:close() end
			local p = Player(s.playerId)
			if p then p:sendTextMessage(MESSAGE_HOTKEY_PRESSED, line) end
		end

		local function batchFinish(s)
			for _, zoneName in ipairs(s.batchZones) do
				Zone.removeByName(zoneName)
			end
			local skipParts = {}
			if s.skipReasons.small > 0 then table.insert(skipParts, s.skipReasons.small .. " too few spawns") end
			if s.skipReasons.lowExp > 0 then table.insert(skipParts, s.skipReasons.lowExp .. " low exp") end
			if s.skipReasons.tiles > 0 then table.insert(skipParts, s.skipReasons.tiles .. " too few tiles") end
			if s.skipReasons.exists > 0 then table.insert(skipParts, s.skipReasons.exists .. " already exist") end
			if s.skipReasons.overlap > 0 then table.insert(skipParts, s.skipReasons.overlap .. " overlap") end
			if s.skipReasons.noexit > 0 then table.insert(skipParts, s.skipReasons.noexit .. " no exit") end
			if s.skipReasons.failed > 0 then table.insert(skipParts, s.skipReasons.failed .. " failed") end
			local skipStr = #skipParts > 0 and (" (" .. table.concat(skipParts, ", ") .. ")") or ""
			local summary
			if s.dryRun then
				summary = string.format(
					"[Hunt] Dry run complete: %d would be saved, %d skipped%s.",
					s.saved, s.skipped, skipStr)
			else
				summary = string.format(
					"[Hunt] Batch complete: %d saved, %d skipped%s. Use /reload scripts to activate.",
					s.saved, s.skipped, skipStr)
			end
			batchLog(s, summary)
			print("[Hunt] Batch finished: " .. summary)
		end

		local function batchProcessNext(s)
			if s.idx > #s.clusters then
				batchFinish(s)
				return
			end

			-- Continue headlessly even if player disconnected
			local p = Player(s.playerId)

			local i = s.idx
			s.idx = s.idx + 1
			local cluster = s.clusters[i]
			local name = cluster.autoName or "Unknown"

			-- If ids= was specified, skip any cluster not in the selected set
			if s.selectedIds and not s.selectedIds[i] then
				addEvent(batchProcessNext, 10, s)
				return
			end

			if i % 10 == 1 then
				local msg = string.format("[Hunt] Processing %d/%d...", i, #s.clusters)
				if p then p:sendTextMessage(MESSAGE_HOTKEY_PRESSED, msg) end
				print(msg)
			end

			-- Quality gate: min spawns
			if (cluster.spawns or 0) < s.minSpawns then
				s.skipped = s.skipped + 1
				s.skipReasons.small = s.skipReasons.small + 1
				addEvent(batchProcessNext, 50, s)
				return
			end

			-- Quality gate: dominant monster experience
			if s.minExp > 0 and cluster.monsters and #cluster.monsters > 0 then
				local dominant = cluster.monsters[1].name
				local mt = MonsterType(dominant)
				local exp = mt and mt:experience() or 0
				if exp < s.minExp then
					s.skipped = s.skipped + 1
					s.skipReasons.lowExp = s.skipReasons.lowExp + 1
					addEvent(batchProcessNext, 50, s)
					return
				end
			end

			-- Quality gate: file already exists
			if not s.dryRun and huntFileExists(name) then
				s.skipped = s.skipped + 1
				s.skipReasons.exists = s.skipReasons.exists + 1
				addEvent(batchProcessNext, 50, s)
				return
			end

			-- Overlap detection
			local seedPos
			if cluster.centerSpawnPos then
				seedPos = Position(cluster.centerSpawnPos.x, cluster.centerSpawnPos.y, cluster.centerSpawnPos.z)
			else
				seedPos = Position(
					math.floor((cluster.fromPos.x + cluster.toPos.x) / 2),
					math.floor((cluster.fromPos.y + cluster.toPos.y) / 2),
					cluster.zLevels and cluster.zLevels[1] or cluster.fromPos.z)
			end
			for _, prevZoneName in ipairs(s.batchZones) do
				local prevZone = Zone(prevZoneName)
				if prevZone:contains(seedPos) then
					s.skipped = s.skipped + 1
					s.skipReasons.overlap = s.skipReasons.overlap + 1
					addEvent(batchProcessNext, 50, s)
					return
				end
			end

			-- Heavy work: flood-fill + expansion (blocks thread ~1.5-2s)
			local tempZoneName = string.format("hunt._batch_%d", i)
			local result, reason = processCluster(cluster, tempZoneName)
			if not result then
				Zone.removeByName(tempZoneName)
				s.skipped = s.skipped + 1
				s.skipReasons.failed = s.skipReasons.failed + 1
				addEvent(batchProcessNext, 2000, s)
				return
			end

			if result.tiles < s.minTiles then
				Zone.removeByName(tempZoneName)
				s.skipped = s.skipped + 1
				s.skipReasons.tiles = s.skipReasons.tiles + 1
				addEvent(batchProcessNext, 2000, s)
				return
			end

			-- Quality gate: requireexit — skip caves where exit detection failed
			if s.requireExit and result.exitIsBestGuess then
				Zone.removeByName(tempZoneName)
				s.skipped = s.skipped + 1
				s.skipReasons.noexit = s.skipReasons.noexit + 1
				batchLog(s, string.format("[Batch] #%d %s: SKIP (no exit detected)", i, name))
				addEvent(batchProcessNext, 2000, s)
				return
			end

			table.insert(s.batchZones, tempZoneName)

			local zStr = "?"
			if result.zLevels then
				local parts = {}
				for _, z in ipairs(result.zLevels) do table.insert(parts, tostring(z)) end
				zStr = table.concat(parts, ",")
			end

			local batchSession = {
				name = name,
				caveSeed = result.caveSeed,
				exitPos = result.exitPos,
				exitIsBestGuess = result.exitIsBestGuess,
				teleportEntries = result.teleportEntries,
				exitTeleports = result.exitTeleports,
				internalTeleports = result.internalTeleports,
				maxCaveTiles = result.maxCaveTiles,
				maxDistance = result.maxDistance,
			}

			if s.dryRun then
				local tag = result.exitIsBestGuess and "DRY (no exit)" or "DRY OK"
				batchLog(s, string.format(
					"[Batch] #%d %s: %d tiles, z=[%s], %d spawns -> %s",
					i, name, result.tiles, zStr, result.spawns, tag))
				s.saved = s.saved + 1
			else
				local config = generateConfig(batchSession)
				local header = string.format(
					"-- Hunt: %s\n-- Generated by /hunt batch (flood-fill from %s)\n\n",
					name, fmtPos(result.caveSeed))
				local filepath = "data/scripts/movements/hunt_" .. sanitizeFilename(name) .. ".lua"
				local file = io.open(filepath, "w")
				if file then
					file:write(header .. config .. "\n")
					file:close()
					batchLog(s, string.format(
						"[Batch] #%d %s: %d tiles, z=[%s] -> SAVED",
						i, name, result.tiles, zStr))
					s.saved = s.saved + 1
				else
					batchLog(s, string.format(
						"[Batch] #%d %s: WRITE FAILED (%s)", i, name, filepath))
					s.skipped = s.skipped + 1
					s.skipReasons.failed = s.skipReasons.failed + 1
				end
			end

			addEvent(batchProcessNext, 2000, s)
		end

		addEvent(batchProcessNext, 3000, state)

	-- =========================================================================
	-- HELP
	-- =========================================================================
	else
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Commands: (discovery)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt discover[, maxTiles[/maxDistance]]  flood-fill from stair/hole")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt scan[, filter]        global grid scan (browse clusters)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt list[, page]          browse scanned clusters")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt nearby                10 nearest clusters")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt goto, <N>             teleport to cluster N")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt accept, <N>           flood-fill from cluster N center")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Hunt] Commands: (bulk - recommended workflow)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt catalog[, zN-M][, expN][, minS]   fast catalog, no flood-fill")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /hunt batch[, dry][, ids=3 10 18][, N/T][, zN-M][, expN][, requireexit]")
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
