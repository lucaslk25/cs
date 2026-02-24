-- Instance Info ExtendedOpcode Handler
-- Opcode 210: client requests instance data, server responds with JSON

local instanceOpcode = CreatureEvent("InstanceOpcode")

function instanceOpcode.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= INSTANCE_OPCODE then
		return
	end

	-- Parse the action from the buffer (simple JSON parse for action field)
	local action = buffer:match('"action"%s*:%s*"([^"]+)"')
	if not action then
		return
	end

	if action == "fetch" then
		local instanceId = player:getInstanceId()
		if instanceId > 1 and InstanceRegistry[instanceId] then
			InstanceRegistry.sendUpdate(player)
		else
			InstanceRegistry.sendClear(player)
		end
	end
end

instanceOpcode:register()
