-- EventCallback for mapOnLoad to build hunt zones after map is loaded.
-- This must be in data/scripts/ (not data/libs/) because it needs revscriptsys to be loaded first.
--
-- NOTE: mapOnLoad fires for EVERY map-file load — including raid monster spawns (which reload
-- every few minutes). The _G guard ensures we only run once on actual server startup AND
-- survives /reload scripts (unlike a file-local variable which resets on reload).

local callback = EventCallback("HuntMapOnLoad")

function callback.mapOnLoad(path)
	if _G._huntZonesBuilt then
		return
	end
	_G._huntZonesBuilt = true
	logger.info("[HuntInstance] Building pending hunt zones after map load...")
	HuntInstance.buildPendingZones()
	logger.info("[HuntInstance] All pending hunt zones built.")
end

callback:register()
