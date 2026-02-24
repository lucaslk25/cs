local onRaidBossDeath = CreatureEvent("RaidInstanceOnDeath")

function onRaidBossDeath.onDeath(creature)
	if not creature then
		return true
	end

	local name = creature:getName()
	local raidInstance = RaidInstance[name:lower()]
	if not raidInstance then
		return true
	end

	local instanceId = creature:getInstanceId()
	if instanceId <= 1 then
		-- Global instance death (from XML raid) - no instance cleanup needed
		return true
	end

	-- Cancel the timeout event for this instance
	if raidInstance.activeInstances[instanceId] and raidInstance.activeInstances[instanceId].timeoutEvent then
		stopEvent(raidInstance.activeInstances[instanceId].timeoutEvent)
		raidInstance.activeInstances[instanceId].timeoutEvent = nil
	end

	if raidInstance.timeAfterKill > 0 then
		-- Send message only to players in this instance
		local zone = raidInstance:getZone()
		zone:refresh()
		for _, zonePlayer in ipairs(zone:getPlayers()) do
			if zonePlayer:getInstanceId() == instanceId then
				zonePlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The " .. name .. " has been defeated. You have " .. raidInstance.timeAfterKill .. " seconds to leave the room.")
			end
		end

		-- Schedule instance cleanup after timeAfterKill
		local cleanupEvt = addEvent(function(raidRef, instId)
			raidRef:cleanupInstance(instId)
		end, raidInstance.timeAfterKill * 1000, raidInstance, instanceId)

		-- Update the timeout event in tracking
		if raidInstance.activeInstances[instanceId] then
			raidInstance.activeInstances[instanceId].timeoutEvent = cleanupEvt
		end
	else
		-- Immediate cleanup
		raidInstance:cleanupInstance(instanceId)
	end

	onDeathForDamagingPlayers(creature, function(creature, player)
		player:takeScreenshot(SCREENSHOT_TYPE_BOSSDEFEATED)
	end)
	return true
end

onRaidBossDeath:register()
