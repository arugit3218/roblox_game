--!strict
-- Per-rarity balance. Caviar returns ~3x its feed cost (valuePerUnit 6, units = cost / 2)
-- and takes productionSeconds, so feeding can't be looped instantly.

local Types = require(script.Parent.Parent.Types)

export type RarityDef = {
	order: number,
	color: Color3,
	hatchMin: number,
	hatchMax: number,
	visitorsPerHour: number,
	coinsPerVisitor: number,
	feedCost: number,
	caviarUnits: number,
	valuePerUnit: number,
	productionSeconds: number,
}

local Rarities: { [Types.Rarity]: RarityDef } = {
	Common = {
		order = 1,
		color = Color3.fromRGB(200, 200, 200),
		hatchMin = 30,
		hatchMax = 120,
		visitorsPerHour = 2,
		coinsPerVisitor = 15,
		feedCost = 100,
		caviarUnits = 50,
		valuePerUnit = 6,
		productionSeconds = 60,
	},
	Uncommon = {
		order = 2,
		color = Color3.fromRGB(90, 200, 110),
		hatchMin = 10 * 60,
		hatchMax = 20 * 60,
		visitorsPerHour = 3,
		coinsPerVisitor = 40,
		feedCost = 300,
		caviarUnits = 150,
		valuePerUnit = 6,
		productionSeconds = 3 * 60,
	},
	Rare = {
		order = 3,
		color = Color3.fromRGB(70, 140, 255),
		hatchMin = 30 * 60,
		hatchMax = 45 * 60,
		visitorsPerHour = 4,
		coinsPerVisitor = 100,
		feedCost = 800,
		caviarUnits = 400,
		valuePerUnit = 6,
		productionSeconds = 7 * 60,
	},
	Epic = {
		order = 4,
		color = Color3.fromRGB(170, 80, 240),
		hatchMin = 45 * 60,
		hatchMax = 60 * 60,
		visitorsPerHour = 5,
		coinsPerVisitor = 250,
		feedCost = 2000,
		caviarUnits = 1000,
		valuePerUnit = 6,
		productionSeconds = 15 * 60,
	},
	Legendary = {
		order = 5,
		color = Color3.fromRGB(255, 180, 40),
		hatchMin = 90 * 60,
		hatchMax = 90 * 60,
		visitorsPerHour = 6,
		coinsPerVisitor = 500,
		feedCost = 5000,
		caviarUnits = 2500,
		valuePerUnit = 6,
		productionSeconds = 20 * 60,
	},
	Mythic = {
		order = 6,
		color = Color3.fromRGB(255, 70, 110),
		hatchMin = 120 * 60,
		hatchMax = 120 * 60,
		visitorsPerHour = 8,
		coinsPerVisitor = 1000,
		feedCost = 12000,
		caviarUnits = 6000,
		valuePerUnit = 6,
		productionSeconds = 30 * 60,
	},
}

return table.freeze(Rarities)
