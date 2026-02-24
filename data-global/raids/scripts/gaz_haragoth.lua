function onRaid()
	-- Gaz'Haragoth raid script: kicks all players from the boss zone, then spawns the boss

	local raidInstance = RaidInstance["gaz'haragoth"]
	if raidInstance then
		local zone = raidInstance:getZone()
		zone:refresh()

		-- Kick all players from z=11 (intermediate room) and z=12 (boss room) back to exit
		local exitPos = raidInstance.exit
		local kickedPlayers = {}
		for _, player in ipairs(zone:getPlayers()) do
			if player:getInstanceId() <= 1 then -- Only kick global-instance players
				player:teleportTo(exitPos)
				player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "A powerful force pushes you out as Gaz'Haragoth invades!")
				table.insert(kickedPlayers, player:getName())
			end
		end

		if #kickedPlayers > 0 then
			logger.info("Gaz'Haragoth raid: kicked {} players from zone: {}", #kickedPlayers, table.concat(kickedPlayers, ", "))
		end
	end

	-- Spawn the boss globally (original raid behavior)
	Game.createMonster("Gaz'Haragoth", Position(33538, 32381, 12), true, true)
	logger.info("Gaz'Haragoth raid: boss spawned at global instance")
end
