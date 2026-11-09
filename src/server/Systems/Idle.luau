--!strict
-- Idle economy: incubation, aquarium visitor income, caviar feeding and orders.
-- All timers are absolute os.time() stamps, so progress continues while offline.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.GameData.Creatures)
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local Rarities = require(Shared.GameData.Rarities)
local Variants = require(Shared.GameData.Variants)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Lib.Net)
local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)

type Profile = Types.PlayerProfile

local Idle = {}
local rng = Random.new()

local PET_NAMES = {
	"Splash",
	"Bubbles",
	"Neptune",
	"Coral",
	"Finn",
	"Pearl",
	"Marina",
	"Ripple",
	"Drift",
	"Tide",
	"Kelpie",
	"Sunny",
	"Misty",
	"Echo",
	"Wave",
	"Pebble",
	"Breeze",
	"Sandy",
}

function Idle.incubatorFull(profile: Profile): boolean
	return #profile.eggs >= Config.INCUBATOR_SLOTS
end

function Idle.addEgg(profile: Profile, tier: number, kind: Types.EggKind, luck: number?)
	local def = Creatures.get(tier)
	assert(def, "bad tier")
	local r = Rarities[def.rarity]
	local now = os.time()
	table.insert(profile.eggs, {
		id = PlayerData.newId(profile),
		tier = tier,
		kind = kind,
		rarity = def.rarity,
		startedAt = now,
		hatchAt = now + rng:NextInteger(r.hatchMin, r.hatchMax),
		luck = luck or 1,
	})
end

local function rollOrder(profile: Profile): Types.Order
	-- Ask for caviar the player can actually produce (falls back to Common).
	local rarities: { Types.Rarity } = {}
	for _, pet in profile.pets do
		if pet.kind == "Caviar" and pet.placed and not table.find(rarities, pet.rarity) then
			table.insert(rarities, pet.rarity)
		end
	end
	local rarity: Types.Rarity = if #rarities > 0
		then rarities[rng:NextInteger(1, #rarities)]
		else "Common"
	local r = Rarities[rarity]
	local units = math.max(5, math.floor(r.caviarUnits * rng:NextNumber(0.3, 1) / 5) * 5)
	return {
		id = PlayerData.newId(profile),
		rarity = rarity,
		units = units,
		reward = units * r.valuePerUnit,
	}
end

-- Advance timers for one player. Returns true if anything changed.
local function tickProfile(player: Player, profile: Profile, now: number): boolean
	local changed = false

	-- Hatch eggs (iterate backwards so removal is safe).
	for i = #profile.eggs, 1, -1 do
		local egg = profile.eggs[i]
		if egg.hatchAt <= now then
			table.remove(profile.eggs, i)
			local def = Creatures.get(egg.tier)
			local slots = if egg.kind == "Aquarium"
				then Config.AQUARIUM_SLOTS
				else Config.KITCHEN_SLOTS
			local placed = Economy.countPlaced(profile, egg.kind) < slots
			if placed and egg.kind == "Aquarium" then
				Economy.settleAquarium(profile, now) -- lock in income at the old rate
			end
			local name =
				`{PET_NAMES[rng:NextInteger(1, #PET_NAMES)]} the {if def then def.name else "Fish"}`
			local pet: Types.Pet = {
				id = PlayerData.newId(profile),
				tier = egg.tier,
				kind = egg.kind,
				rarity = egg.rarity,
				name = name,
				variant = egg.variant or Variants.roll(rng, egg.luck or 1),
				placed = placed,
				feedReadyAt = 0,
				pendingUnits = 0,
			}
			table.insert(profile.pets, pet)
			local dexKey = `{egg.tier}:{egg.kind}`
			local isNew = not profile.dex[dexKey]
			profile.dex[dexKey] = true
			Net.hatched(player, pet, isNew)
			if not placed then
				Net.notify(player, `{name} is stored — your {egg.kind} slots are full`, "warn")
			end
			changed = true
		end
	end

	-- Finish caviar production.
	for _, pet in profile.pets do
		if pet.feedReadyAt > 0 and pet.feedReadyAt <= now then
			profile.caviar[pet.rarity] = (profile.caviar[pet.rarity] or 0) + pet.pendingUnits
			Net.notify(
				player,
				`🍳 {pet.name} made {pet.pendingUnits} {pet.rarity} caviar`,
				"success"
			)
			pet.feedReadyAt = 0
			pet.pendingUnits = 0
			changed = true
		end
	end

	-- Keep the order queue full.
	while #profile.orders < Config.ORDER_SLOTS do
		table.insert(profile.orders, rollOrder(profile))
		changed = true
	end

	return changed
end

local function findPet(profile: Profile, id: string): Types.Pet?
	for _, pet in profile.pets do
		if pet.id == id then
			return pet
		end
	end
	return nil
end

function Idle.collectAquarium(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local now = os.time()
	Economy.settleAquarium(profile, now)
	local amount = math.floor(profile.aquarium.bank)
	if amount <= 0 then
		Net.notify(player, "No visitor coins yet — place aquarium pets to earn.", "info")
		return
	end
	profile.aquarium.bank -= amount
	profile.coins += amount
	Net.notify(player, `💰 Collected {Format.number(amount)} coins from visitors`, "success")
	PlayerData.changed(player)
end

local function feedPet(player: Player, petId: unknown)
	if not Net.isId(petId) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local pet = findPet(profile, petId :: string)
	if not pet or pet.kind ~= "Caviar" or not pet.placed or pet.feedReadyAt > 0 then
		return
	end
	local r = Rarities[pet.rarity]
	if profile.coins < r.feedCost then
		Net.notify(player, `Need {Format.number(r.feedCost)} coins to feed {pet.name}`, "error")
		return
	end
	profile.coins -= r.feedCost
	pet.feedReadyAt = os.time() + r.productionSeconds
	pet.pendingUnits = Economy.caviarUnits(pet)
	PlayerData.changed(player)
end

local function fulfillOrder(player: Player, orderId: unknown)
	if not Net.isId(orderId) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for i, order in profile.orders do
		if order.id == orderId then
			local have = profile.caviar[order.rarity] or 0
			if have < order.units then
				Net.notify(
					player,
					`Need {order.units} {order.rarity} caviar (you have {have})`,
					"error"
				)
				return
			end
			profile.caviar[order.rarity] = have - order.units
			profile.coins += order.reward
			table.remove(profile.orders, i)
			table.insert(profile.orders, rollOrder(profile))
			Net.notify(player, `🧾 Order served! +{Format.number(order.reward)} coins`, "success")
			PlayerData.changed(player)
			return
		end
	end
end

function Idle.init()
	Net.handle("CollectAquarium", 2, 3, Idle.collectAquarium)
	Net.handle("FeedPet", 5, 8, feedPet)
	Net.handle("FulfillOrder", 5, 8, fulfillOrder)

	PlayerData.onLoaded(function(player, profile)
		tickProfile(player, profile, os.time())
		PlayerData.changed(player)
	end)
end

function Idle.start()
	for _, plot in World.plots do
		local prompt = plot.pad:FindFirstChild("CollectPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player)
				if plot.owner == player then
					Idle.collectAquarium(player)
				else
					Net.notify(player, "That's not your aquarium!", "error")
				end
			end)
		end
	end

	while true do
		task.wait(1)
		local now = os.time()
		for _, player in PlayerData.players() do
			local profile = PlayerData.get(player)
			if profile and tickProfile(player, profile, now) then
				PlayerData.changed(player)
			end
		end
	end
end

return Idle
