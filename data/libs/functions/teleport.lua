function Teleport.isTeleport(self)
	return true
end

ScriptTeleportRegistry = {}
local _teleportUniquePopulated = false

-- Spatial index: bucket teleports by 32×32 sector for fast area queries.
-- _srcSectors[sectorKey] = { entry1, entry2, ... }  (indexed by source sector)
-- _dstSectors[sectorKey] = { entry1, entry2, ... }  (indexed by destination sector)
local SECTOR_SIZE = 32
local _srcSectors = {}
local _dstSectors = {}

local function sectorKey(x, y)
	local sx = math.floor(x / SECTOR_SIZE)
	local sy = math.floor(y / SECTOR_SIZE)
	return sx + sy * 65536
end

function registerScriptTeleport(source, destination)
	local key = source.x .. ":" .. source.y .. ":" .. source.z
	local entry = {
		source = Position(source.x, source.y, source.z),
		destination = Position(destination.x, destination.y, destination.z),
	}
	ScriptTeleportRegistry[key] = entry

	local srcKey = sectorKey(source.x, source.y)
	if not _srcSectors[srcKey] then _srcSectors[srcKey] = {} end
	_srcSectors[srcKey][#_srcSectors[srcKey] + 1] = entry

	local dstKey = sectorKey(destination.x, destination.y)
	if not _dstSectors[dstKey] then _dstSectors[dstKey] = {} end
	_dstSectors[dstKey][#_dstSectors[dstKey] + 1] = entry
end

local function populateFromTeleportUnique()
	if _teleportUniquePopulated then
		return
	end
	_teleportUniquePopulated = true
	if not TeleportUnique then
		return
	end
	for _, entry in pairs(TeleportUnique) do
		if entry.destination and entry.itemPos and entry.itemPos.x then
			registerScriptTeleport(entry.itemPos, entry.destination)
		end
	end
end

function getScriptTeleportDestination(pos)
	populateFromTeleportUnique()
	local key = pos.x .. ":" .. pos.y .. ":" .. pos.z
	local entry = ScriptTeleportRegistry[key]
	return entry and entry.destination or nil
end

--- Returns script teleports whose destination is inside the given area.
--- Uses spatial index: only checks sectors that overlap the query rectangle.
--- @param fromPos Position
--- @param toPos Position
--- @return table list of { source = Position, dest = Position }
function getScriptTeleportSourcesToArea(fromPos, toPos)
	populateFromTeleportUnique()
	local list = {}
	local seen = {}
	local sxMin = math.floor(fromPos.x / SECTOR_SIZE)
	local sxMax = math.floor(toPos.x / SECTOR_SIZE)
	local syMin = math.floor(fromPos.y / SECTOR_SIZE)
	local syMax = math.floor(toPos.y / SECTOR_SIZE)
	for sx = sxMin, sxMax do
		for sy = syMin, syMax do
			local bucket = _dstSectors[sx + sy * 65536]
			if bucket then
				for _, entry in ipairs(bucket) do
					local dest = entry.destination
					local entryKey = entry.source.x .. ":" .. entry.source.y .. ":" .. entry.source.z
					if not seen[entryKey]
						and dest.x >= fromPos.x and dest.x <= toPos.x
						and dest.y >= fromPos.y and dest.y <= toPos.y
						and dest.z >= fromPos.z and dest.z <= toPos.z then
						seen[entryKey] = true
						list[#list + 1] = { source = entry.source, dest = dest }
					end
				end
			end
		end
	end
	return list
end

--- Returns script teleports whose source is inside the given area.
--- Uses spatial index: only checks sectors that overlap the query rectangle.
--- @param fromPos Position
--- @param toPos Position
--- @return table list of { source = Position, dest = Position }
function getScriptTeleportsWithSourceInArea(fromPos, toPos)
	populateFromTeleportUnique()
	local list = {}
	local seen = {}
	local sxMin = math.floor(fromPos.x / SECTOR_SIZE)
	local sxMax = math.floor(toPos.x / SECTOR_SIZE)
	local syMin = math.floor(fromPos.y / SECTOR_SIZE)
	local syMax = math.floor(toPos.y / SECTOR_SIZE)
	for sx = sxMin, sxMax do
		for sy = syMin, syMax do
			local bucket = _srcSectors[sx + sy * 65536]
			if bucket then
				for _, entry in ipairs(bucket) do
					local src = entry.source
					local entryKey = src.x .. ":" .. src.y .. ":" .. src.z
					if not seen[entryKey]
						and src.x >= fromPos.x and src.x <= toPos.x
						and src.y >= fromPos.y and src.y <= toPos.y
						and src.z >= fromPos.z and src.z <= toPos.z then
						seen[entryKey] = true
						list[#list + 1] = { source = src, dest = entry.destination }
					end
				end
			end
		end
	end
	return list
end

function SimpleTeleport(from, destination, condition, disableEffect)
	registerScriptTeleport(from, destination)

	local teleport = MoveEvent()

	function teleport.onStepIn(creature, item, position, fromPosition)
		local player = creature:getPlayer()
		if not player then
			return false
		end

		if condition and not condition(player, item, position, fromPosition) then
			return false
		end

		player:teleportTo(destination)
		if not disableEffect then
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		return true
	end

	teleport:position(from)
	teleport:register()
	return teleport
end
