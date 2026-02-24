-- Instance System - Test Commands
-- Usage:
--   /instance create          -> Creates a new instance, prints the ID
--   /instance join <id>       -> Moves player to instance <id> (ghost-style 5-phase switch)
--   /instance leave           -> Returns player to global instance (id=1)
--   /instance info            -> Shows current instance ID and active count
--   /instance destroy <id>    -> Destroys an instance
--   /instance monster <name>  -> Spawns a monster in the player's current instance at player's position
--   /instance item <id>       -> Creates an item tagged with current instance (visible only in this instance)

local instance = TalkAction("/instance")

function instance.onSay(player, words, param)
	logCommand(player, words, param)

	local split = param:split(",")
	local action = split[1] and split[1]:trim():lower() or ""
	local arg = split[2] and split[2]:trim() or ""

	if action == "create" then
		local instanceId = Game.createInstance(player)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Created instance #" .. instanceId)
		return true

	elseif action == "join" then
		local targetId = tonumber(arg)
		if not targetId then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Usage: /instance join, <id>")
			return true
		end
		local currentId = player:getInstanceId()
		player:changeInstance(targetId)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Switched from #" .. currentId .. " to #" .. targetId)
		return true

	elseif action == "leave" then
		local currentId = player:getInstanceId()
		player:changeInstance(1)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Left instance #" .. currentId .. ", back to global (#1)")
		return true

	elseif action == "info" then
		local instanceId = player:getInstanceId()
		local status = "global"
		if instanceId > 1 then
			status = "private"
		end
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
			"[Instance] Current: #" .. instanceId .. " (" .. status .. ")")
		return true

	elseif action == "destroy" then
		local targetId = tonumber(arg)
		if not targetId then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Usage: /instance destroy, <id>")
			return true
		end
		if targetId == 1 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Cannot destroy global instance")
			return true
		end
		local success = Game.destroyInstance(targetId)
		if success then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Destroyed instance #" .. targetId)
		else
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Failed to destroy instance #" .. targetId)
		end
		return true

	elseif action == "monster" then
		if arg == "" then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Usage: /instance monster, <name>")
			return true
		end
		local pos = player:getPosition()
		local instanceId = player:getInstanceId()
		local monster = Game.createInstanceMonster(arg, pos, instanceId, true, true)
		if monster then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
				"[Instance] Spawned '" .. arg .. "' in instance #" .. instanceId .. " at " .. pos:toString())
		else
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
				"[Instance] Failed to spawn '" .. arg .. "' - check monster name")
		end
		return true

	elseif action == "populate" then
		-- Usage: /instance populate, <width>, <height>
		-- Clones all global spawns within the area around the player into their current instance
		local instanceId = player:getInstanceId()
		if instanceId <= 1 then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Must be in a private instance to populate")
			return true
		end
		local w = tonumber(arg) or 100
		local h = tonumber(split[3] and split[3]:trim() or "") or w
		local pos = player:getPosition()
		-- Center the area around the player
		local fromPos = Position(pos.x - math.floor(w / 2), pos.y - math.floor(h / 2), pos.z)
		local count = Game.populateInstanceFromMap(instanceId, fromPos, w, h)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
			"[Instance] Populated instance #" .. instanceId .. " with " .. count .. " spawn areas (" .. w .. "x" .. h .. " from " .. fromPos:toString() .. ")")
		return true

	elseif action == "item" then
		local itemId = tonumber(arg)
		if not itemId then
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Usage: /instance item, <itemId>")
			return true
		end
		local instanceId = player:getInstanceId()
		local item = Game.createItem(itemId, 1, player:getPosition())
		if item then
			item:setCustomAttribute("instanceid", instanceId)
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
				"[Instance] Created item " .. itemId .. " in instance #" .. instanceId)
		else
			player:sendTextMessage(MESSAGE_HOTKEY_PRESSED,
				"[Instance] Failed to create item " .. itemId)
		end
		return true

	else
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[Instance] Commands:")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance create              - Create new instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance join, <id>          - Join instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance leave               - Return to global (#1)")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance info                - Show current instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance destroy, <id>       - Destroy instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance monster, <name>     - Spawn monster in instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance populate, <w>, <h>  - Clone map spawns into instance")
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "  /instance item, <itemId>      - Create instanced item")
		return true
	end
end

instance:separator(" ")
instance:groupType("normal")
instance:register()
