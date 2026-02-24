local onBossDeath = CreatureEvent("BossLeverOnDeath")

function onBossDeath.onDeath(creature)
	if not creature then
		return true
	end

	local name = creature:getName()
	local key = "boss." .. toKey(name)
	local zone = Zone(key)

	if not zone then
		return true
	end

	local bossLever = BossLever[name:lower()]
	if not bossLever then
		return true
	end

	local instanceId = creature:getInstanceId()
	local isInstanced = bossLever.instanced and instanceId > 1

	if isInstanced then
		-- === INSTANCED BOSS DEATH ===
		-- Cancel the timeout event for this specific instance
		if bossLever.activeInstances[instanceId] and bossLever.activeInstances[instanceId].timeoutEvent then
			stopEvent(bossLever.activeInstances[instanceId].timeoutEvent)
			bossLever.activeInstances[instanceId].timeoutEvent = nil
		end

		if bossLever.timeAfterKill > 0 then
			-- Send message only to players in this instance
			zone:refresh()
			for _, zonePlayer in ipairs(zone:getPlayers()) do
				if zonePlayer:getInstanceId() == instanceId then
					zonePlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The " .. name .. " has been defeated. You have " .. bossLever.timeAfterKill .. " seconds to leave the room.")
				end
			end

			-- Schedule instance cleanup after timeAfterKill
			local cleanupEvt = addEvent(function(bossLeverRef, instId)
				bossLeverRef:cleanupInstance(instId)
			end, bossLever.timeAfterKill * 1000, bossLever, instanceId)

			-- Update the timeout event in tracking
			if bossLever.activeInstances[instanceId] then
				bossLever.activeInstances[instanceId].timeoutEvent = cleanupEvt
			end
		else
			-- Immediate cleanup
			bossLever:cleanupInstance(instanceId)
		end
	else
		-- === NORMAL BOSS DEATH (unchanged) ===
		if bossLever.timeoutEvent then
			stopEvent(bossLever.timeoutEvent)
			bossLever.timeoutEvent = nil
		end

		if bossLever.timeAfterKill > 0 then
			zone:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The " .. name .. " has been defeated. You have " .. bossLever.timeAfterKill .. " seconds to leave the room.")
			bossLever.timeoutEvent = addEvent(function(zn)
				zn:refresh()
				zn:removePlayers()
			end, bossLever.timeAfterKill * 1000, zone)
		end
	end

	onDeathForDamagingPlayers(creature, function(creature, player)
		player:takeScreenshot(SCREENSHOT_TYPE_BOSSDEFEATED)
	end)
	return true
end

onBossDeath:register()
