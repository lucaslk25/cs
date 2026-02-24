-- Gaz'Haragoth Instanced Raid Boss
-- Entry: terracotta tiles at z=11 (intermediate room, after descending stairs)
-- Player stays on same tile, gets instanced, then walks down to z=12 boss room
-- Players in the same party share the same instance

local config = {
	bossName = "Gaz'Haragoth",
	bossPosition = Position(33538, 32381, 12),
	entryPositions = {
		Position(33509, 32382, 11),
		Position(33510, 32382, 11),
		Position(33511, 32382, 11),
	},
	teleportTo = Position(33510, 32382, 11), -- stay on same tile (intermediate room)
	specPos = {                               -- zone covers z=10 (exit/stairs), z=11 (intermediate) and z=12 (boss room)
		from = Position(33506, 32360, 10),
		to = Position(33560, 32400, 12),
	},
	exit = Position(33510, 32380, 10), -- z=10, safe spot above the stairs
	maxInstances = 10,
	timeToDefeat = 45 * 60,     -- 45 minutes to kill the boss
	timeAfterKill = 5 * 60,     -- 5 minutes after boss dies
	requiredLevel = 250,
}

local raid = RaidInstance(config)
raid:register()
