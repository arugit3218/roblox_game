--!strict
-- Pure economy rules shared by server (authoritative) and client (display only).

local Config = require(script.Parent.Config)
local Rarities = require(script.Parent.GameData.Rarities)
local Shop = require(script.Parent.GameData.Shop)
local Types = require(script.Parent.Types)
local Variants = require(script.Parent.GameData.Variants)

local Economy = {}

function Economy.petIncomePerHour(pet: Types.Pet): number
	local r = Rarities[pet.rarity]
	return r.visitorsPerHour * r.coinsPerVisitor * Variants.get(pet.variant).multiplier
end

function Economy.caviarUnits(pet: Types.Pet): number
	return Rarities[pet.rarity].caviarUnits * Variants.get(pet.variant).multiplier
end

function Economy.aquariumRatePerSecond(profile: Types.PlayerProfile): number
	local perHour = 0
	for _, pet in profile.pets do
		if pet.kind == "Aquarium" and pet.placed then
			perHour += Economy.petIncomePerHour(pet)
		end
	end
	return perHour / 3600
end

-- Coins waiting in the aquarium at `now` (bank + accrual since last settle, capped).
function Economy.aquariumPending(profile: Types.PlayerProfile, now: number): number
	local elapsed = math.clamp(now - profile.aquarium.lastSettle, 0, Config.OFFLINE_CAP_SECONDS)
	return profile.aquarium.bank + elapsed * Economy.aquariumRatePerSecond(profile)
end

-- Fold accrued income into the bank. Call before anything changes the rate.
function Economy.settleAquarium(profile: Types.PlayerProfile, now: number)
	profile.aquarium.bank = Economy.aquariumPending(profile, now)
	profile.aquarium.lastSettle = now
end

function Economy.walkSpeed(speedLevel: number): number
	local level = Shop.speedLevels[speedLevel]
	return if level then level.speed else Config.BASE_SPEED
end

function Economy.countPlaced(profile: Types.PlayerProfile, kind: Types.EggKind): number
	local n = 0
	for _, pet in profile.pets do
		if pet.kind == kind and pet.placed then
			n += 1
		end
	end
	return n
end

function Economy.trailUnlocked(profile: Types.PlayerProfile, trail: Shop.TrailDef): boolean
	local u = trail.unlock
	if u.kind == "Tier" then
		return profile.highestTier >= u.value
	elseif u.kind == "Heists" then
		return profile.heists >= u.value
	end
	return false -- events / prestige not live yet
end

return Economy
