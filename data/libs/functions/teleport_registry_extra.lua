-- Centralized registry for MoveEvent-based teleports that don't call registerScriptTeleport()
-- These are teleports from upstream scripts that use player:teleportTo() but aren't registered
-- in ScriptTeleportRegistry, making them invisible to hunt discovery system.
--
-- This file is loaded after teleport.lua to ensure registerScriptTeleport() is available.

-- Feaster of Souls - actions_slab.lua
-- Floor teleports connecting different parts of the cave
registerScriptTeleport({ x = 33484, y = 31435, z = 8 }, { x = 33483, y = 31452, z = 9 })
registerScriptTeleport({ x = 33481, y = 31452, z = 9 }, { x = 33486, y = 31435, z = 8 })
registerScriptTeleport({ x = 33558, y = 31467, z = 9 }, { x = 33573, y = 31467, z = 9 })
registerScriptTeleport({ x = 33570, y = 31467, z = 9 }, { x = 33555, y = 31467, z = 9 })
registerScriptTeleport({ x = 33549, y = 31440, z = 9 }, { x = 33537, y = 31440, z = 9 })
registerScriptTeleport({ x = 33539, y = 31440, z = 9 }, { x = 33550, y = 31439, z = 9 })
registerScriptTeleport({ x = 33540, y = 31411, z = 9 }, { x = 33528, y = 31410, z = 9 })
registerScriptTeleport({ x = 33531, y = 31410, z = 9 }, { x = 33541, y = 31412, z = 9 })
registerScriptTeleport({ x = 33535, y = 31444, z = 8 }, { x = 33546, y = 31444, z = 8 })
registerScriptTeleport({ x = 33544, y = 31444, z = 8 }, { x = 33533, y = 31444, z = 8 })

-- NOTE: Boss teleports (actions_portal_*.lua) are intentionally NOT registered
-- as they should not be included in hunt zones.
-- Example: Unaz the Mean, Pale Worm, Brain Head, etc.

-- TODO: Add more teleports from other quest scripts as needed for hunt discovery.
-- To add a new teleport, use: registerScriptTeleport(source_pos, dest_pos)
-- where source_pos and dest_pos are tables with x, y, z fields.
