-- /instanceui — Force send instance UI data to the player (debug/test command)
-- If in an instance: sends real data
-- If not in an instance: sends fake test data

local talk = TalkAction("/instanceui")

function talk.onSay(player, words, param)
	local instanceId = player:getInstanceId()

	if instanceId > 1 and InstanceRegistry[instanceId] then
		-- Real instance: send actual data
		InstanceRegistry.sendUpdate(player)
		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[InstanceUI] Sent real data for instance #" .. instanceId)
	else
		-- Not in instance: send fake test data
		local esc = InstanceRegistry.jsonEscape
		local outfitJson = InstanceRegistry.getOutfitJson("Gaz'Haragoth")
		local totalTime = 45 * 60
		local jsonStr = string.format(
			'{"action":"update","data":{"instanceId":%d,"type":"%s","name":"%s","outfit":%s,"players":[%s],"timeRemaining":%d,"totalTime":%d,"createdAt":%d}}',
			999,
			"raid",
			esc("Gaz'Haragoth (Test)"),
			outfitJson,
			string.format('{"name":"%s","level":%d,"vocation":"%s"}', esc(player:getName()), player:getLevel(), esc(player:getVocation():getName())),
			totalTime,
			totalTime,
			os.time()
		)

		-- Diagnostic logging
		local isOtc = player:isUsingOtClient()
		logger.info("[InstanceUI] isUsingOtClient={}, INSTANCE_OPCODE={}, jsonLen={}", tostring(isOtc), INSTANCE_OPCODE, #jsonStr)
		logger.info("[InstanceUI] JSON: {}", jsonStr)

		local sent = player:sendExtendedOpcode(INSTANCE_OPCODE, jsonStr)
		logger.info("[InstanceUI] sendExtendedOpcode returned: {}", tostring(sent))

		player:sendTextMessage(MESSAGE_HOTKEY_PRESSED, "[InstanceUI] Sent test data (otc=" .. tostring(isOtc) .. ", sent=" .. tostring(sent) .. ")")
	end
	return true
end

talk:separator(" ")
talk:groupType("god")
talk:register()
