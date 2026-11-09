--!strict
-- All 25 heist creatures from the design doc. Config.MAX_TIER limits which are live.

local Types = require(script.Parent.Parent.Types)

export type SpeedClass =
	"Stationary"
	| "VerySlow"
	| "Slow"
	| "Medium"
	| "Fast"
	| "VeryFast"
	| "SpeedCheck"
	| "MaxSpeed"

export type CreatureDef = {
	tier: number,
	name: string,
	stars: number,
	rarity: Types.Rarity,
	speedClass: SpeedClass,
	reward: number,
	color: Color3,
	size: number,
}

-- Chase speed in studs/second (player starts at 25, max 40).
local SPEEDS: { [SpeedClass]: number } = {
	Stationary = 0,
	VerySlow = 12,
	Slow = 16,
	Medium = 21,
	Fast = 27,
	VeryFast = 31,
	SpeedCheck = 34,
	MaxSpeed = 38,
}

local function c(
	tier: number,
	name: string,
	stars: number,
	rarity: Types.Rarity,
	speedClass: SpeedClass,
	reward: number,
	color: Color3,
	size: number
): CreatureDef
	return {
		tier = tier,
		name = name,
		stars = stars,
		rarity = rarity,
		speedClass = speedClass,
		reward = reward,
		color = color,
		size = size,
	}
end

local rgb = Color3.fromRGB
local list: { CreatureDef } = {
	c(1, "Tadpole", 1, "Common", "Slow", 50, rgb(70, 60, 50), 2),
	c(2, "Goldfish", 1, "Common", "Slow", 75, rgb(255, 150, 30), 2.2),
	c(3, "Trout", 2, "Common", "Medium", 100, rgb(150, 160, 110), 3),
	c(4, "Guppy", 1, "Common", "Slow", 60, rgb(120, 200, 255), 2),
	c(5, "Angelfish", 2, "Common", "Medium", 90, rgb(240, 230, 120), 2.6),
	c(6, "Seahorse", 1, "Common", "VerySlow", 70, rgb(250, 170, 60), 2.4),
	c(7, "Dolphin", 2, "Uncommon", "Medium", 200, rgb(130, 150, 180), 5),
	c(8, "Sea Turtle", 2, "Uncommon", "Medium", 250, rgb(70, 140, 80), 4.5),
	c(9, "Starfish", 1, "Common", "Stationary", 55, rgb(255, 120, 90), 2.5),
	c(10, "Pufferfish", 2, "Uncommon", "Slow", 180, rgb(230, 210, 120), 3),
	c(11, "Clownfish", 2, "Uncommon", "Medium", 175, rgb(255, 120, 20), 2.4),
	c(12, "Octopus", 3, "Rare", "Fast", 400, rgb(200, 70, 90), 4),
	c(13, "Hammerhead", 3, "Rare", "Fast", 500, rgb(110, 120, 130), 6),
	c(14, "Manta Ray", 3, "Rare", "VeryFast", 600, rgb(40, 50, 70), 6),
	c(15, "Electric Eel", 2, "Uncommon", "Medium", 220, rgb(80, 110, 60), 4),
	c(16, "Lionfish", 3, "Rare", "Medium", 450, rgb(200, 80, 60), 3),
	c(17, "Seahawk", 3, "Rare", "VeryFast", 550, rgb(150, 120, 90), 3.5),
	c(18, "Giant Squid", 4, "Epic", "VeryFast", 800, rgb(220, 90, 110), 8),
	c(19, "Sperm Whale", 4, "Epic", "SpeedCheck", 1000, rgb(90, 90, 100), 12),
	c(20, "Blue Whale", 4, "Legendary", "SpeedCheck", 1200, rgb(70, 110, 170), 14),
	c(21, "Goblin Shark", 4, "Epic", "VeryFast", 900, rgb(220, 160, 160), 6),
	c(22, "Anglerfish", 3, "Rare", "Fast", 480, rgb(60, 50, 70), 4),
	c(23, "Jellyfish", 2, "Uncommon", "Slow", 160, rgb(220, 150, 255), 3),
	c(24, "Megalodon", 5, "Mythic", "MaxSpeed", 1400, rgb(100, 110, 120), 16),
	c(25, "Killer Whale", 5, "Mythic", "MaxSpeed", 1500, rgb(30, 30, 35), 12),
}

local Creatures = {
	list = list,
	speedOf = function(def: CreatureDef): number
		return SPEEDS[def.speedClass]
	end,
	get = function(tier: number): CreatureDef?
		return list[tier]
	end,
}

return Creatures
