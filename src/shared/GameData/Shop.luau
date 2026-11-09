--!strict
-- Speed upgrades and trail cosmetics. Prices here are the server's source of truth too.

export type SpeedLevel = { cost: number, speed: number }

export type Unlock = { kind: "Tier" | "Heists" | "Event" | "Prestige", value: number }

export type TrailDef = {
	id: string,
	name: string,
	currency: "Coins" | "Gems",
	cost: number,
	unlock: Unlock,
	phase: number,
	colors: { Color3 },
}

local rgb = Color3.fromRGB

-- Phase 1 ships 5 of the 20 planned levels (25 -> 40 speed, +0.75 per level).
local speedLevels: { SpeedLevel } = {
	{ cost = 500, speed = 25.75 },
	{ cost = 900, speed = 26.5 },
	{ cost = 1400, speed = 27.25 },
	{ cost = 2000, speed = 28 },
	{ cost = 2700, speed = 28.75 },
}

local function t(
	id: string,
	name: string,
	currency: "Coins" | "Gems",
	cost: number,
	unlock: Unlock,
	phase: number,
	colors: { Color3 }
): TrailDef
	return {
		id = id,
		name = name,
		currency = currency,
		cost = cost,
		unlock = unlock,
		phase = phase,
		colors = colors,
	}
end

local function tier(n: number): Unlock
	return { kind = "Tier", value = n }
end

local trails: { TrailDef } = {
	t(
		"StarBubbles",
		"Star Bubbles",
		"Coins",
		1000,
		tier(2),
		1,
		{ rgb(255, 255, 200), rgb(150, 220, 255) }
	),
	t(
		"PlanktonGlow",
		"Plankton Glow",
		"Coins",
		2000,
		tier(5),
		1,
		{ rgb(120, 255, 180), rgb(40, 160, 120) }
	),
	t(
		"EggBubbles",
		"Egg Bubbles",
		"Coins",
		2500,
		tier(4),
		1,
		{ rgb(255, 245, 220), rgb(255, 200, 150) }
	),
	t(
		"CoralDust",
		"Coral Dust",
		"Coins",
		3000,
		tier(8),
		1,
		{ rgb(255, 130, 120), rgb(255, 200, 160) }
	),
	t(
		"KelpRibbon",
		"Kelp Ribbon",
		"Coins",
		3500,
		tier(9),
		1,
		{ rgb(60, 160, 60), rgb(150, 220, 90) }
	),
	t(
		"PearlMist",
		"Pearl Mist",
		"Coins",
		4000,
		tier(11),
		2,
		{ rgb(240, 240, 255), rgb(200, 210, 240) }
	),
	t(
		"RainbowShimmer",
		"Rainbow Shimmer",
		"Coins",
		5000,
		tier(7),
		2,
		{ rgb(255, 80, 80), rgb(80, 120, 255) }
	),
	t(
		"GoldenSparkle",
		"Golden Sparkle",
		"Gems",
		500,
		tier(10),
		2,
		{ rgb(255, 210, 60), rgb(255, 255, 180) }
	),
	t(
		"Bioluminescent",
		"Bioluminescent",
		"Gems",
		750,
		tier(12),
		2,
		{ rgb(60, 255, 255), rgb(30, 80, 255) }
	),
	t(
		"FireTrail",
		"Fire Trail",
		"Gems",
		300,
		{ kind = "Heists", value = 50 },
		2,
		{ rgb(255, 90, 20), rgb(255, 220, 60) }
	),
	t(
		"IceCrystals",
		"Ice Crystals",
		"Gems",
		400,
		tier(14),
		3,
		{ rgb(200, 240, 255), rgb(120, 200, 255) }
	),
	t(
		"GhostTrail",
		"Ghost Trail",
		"Gems",
		250,
		{ kind = "Event", value = 0 },
		3,
		{ rgb(230, 230, 255), rgb(150, 150, 200) }
	),
	t(
		"StarlightTrail",
		"Starlight Trail",
		"Gems",
		600,
		tier(15),
		3,
		{ rgb(255, 255, 255), rgb(180, 180, 255) }
	),
	t(
		"StardustPath",
		"Stardust Path",
		"Gems",
		450,
		tier(16),
		3,
		{ rgb(255, 230, 180), rgb(200, 150, 255) }
	),
	t(
		"AuroraWaves",
		"Aurora Waves",
		"Gems",
		700,
		tier(18),
		3,
		{ rgb(80, 255, 160), rgb(160, 80, 255) }
	),
	t(
		"CrystalCascade",
		"Crystal Cascade",
		"Gems",
		550,
		tier(19),
		4,
		{ rgb(180, 255, 255), rgb(255, 180, 255) }
	),
	t(
		"MeteorStreak",
		"Meteor Streak",
		"Gems",
		800,
		tier(20),
		4,
		{ rgb(255, 150, 60), rgb(120, 60, 40) }
	),
	t(
		"SonicBoom",
		"Sonic Boom",
		"Gems",
		500,
		{ kind = "Heists", value = 100 },
		4,
		{ rgb(220, 240, 255), rgb(80, 160, 255) }
	),
	t("MysticVoid", "Mystic Void", "Gems", 900, tier(25), 4, { rgb(60, 0, 90), rgb(10, 0, 20) }),
	t(
		"DiamondRain",
		"Diamond Rain",
		"Gems",
		1000,
		{ kind = "Prestige", value = 1 },
		4,
		{ rgb(200, 255, 255), rgb(255, 255, 255) }
	),
}

local byId: { [string]: TrailDef } = {}
for _, trail in trails do
	byId[trail.id] = trail
end

return {
	speedLevels = speedLevels,
	trails = trails,
	trailById = byId,
}
