function Teleport.isTeleport(self)
	return true
end

ScriptTeleportRegistry = {}
local _teleportUniquePopulated = false

function registerScriptTeleport(source, destination)
	local key = source.x .. ":" .. source.y .. ":" .. source.z
	ScriptTeleportRegistry[key] = {
		source = Position(source.x, source.y, source.z),
		destination = Position(destination.x, destination.y, destination.z),
	}
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
