--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema) live here so both sides agree.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type EggKind = "Aquarium" | "Caviar"

export type Egg = {
	id: string,
	tier: number,
	kind: EggKind,
	rarity: Rarity,
	startedAt: number,
	hatchAt: number,
}

export type Pet = {
	id: string,
	tier: number,
	kind: EggKind,
	rarity: Rarity,
	name: string,
	placed: boolean,
	feedReadyAt: number, -- 0 = idle; otherwise caviar is ready at this time
	pendingUnits: number,
}

export type Order = {
	id: string,
	rarity: Rarity,
	units: number,
	reward: number,
}

export type PlayerProfile = {
	version: number,
	coins: number,
	gems: number,
	highestTier: number,
	heists: number,
	speedLevel: number,
	trails: { string },
	equippedTrail: string,
	eggs: { Egg },
	pets: { Pet },
	aquarium: { bank: number, lastSettle: number },
	caviar: { [string]: number },
	orders: { Order },
	dex: { [string]: boolean },
	nextId: number,
}

export type Carrying = { tier: number, kind: EggKind }

-- What the server sends the owning client.
export type Snapshot = {
	profile: PlayerProfile,
	carrying: Carrying?,
	saving: boolean, -- false when running on a temporary (unsaved) profile
}

return nil
