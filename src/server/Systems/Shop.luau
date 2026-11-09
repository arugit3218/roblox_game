--!strict
-- Speed upgrades and trail cosmetics; applies WalkSpeed + equipped trail to characters.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Shop = require(Shared.GameData.Shop)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Lib.Net)
local PlayerData = require(script.Parent.PlayerData)

local ShopSystem = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local function applyCharacter(player: Player, profile: Types.PlayerProfile)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.WalkSpeed = Economy.walkSpeed(profile.speedLevel)
	end
	if not root then
		return
	end
	local existing = root:FindFirstChild("CosmeticTrail")
	local trailDef = Shop.trailById[profile.equippedTrail]
	if existing and existing:GetAttribute("TrailId") == profile.equippedTrail then
		return
	end
	if existing then
		existing:Destroy()
	end
	for _, name in { "TrailTop", "TrailBottom" } do
		local a = root:FindFirstChild(name)
		if a then
			a:Destroy()
		end
	end
	if not trailDef then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail:SetAttribute("TrailId", trailDef.id)
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.7
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(trailDef.colors[1], trailDef.colors[2] or trailDef.colors[1])
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Parent = root
end

local function buySpeed(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local nextLevel = Shop.speedLevels[profile.speedLevel + 1]
	if not nextLevel then
		Net.notify(player, "Speed is maxed for now — more levels coming soon!", "info")
		return
	end
	if profile.coins < nextLevel.cost then
		Net.notify(player, `Need {nextLevel.cost} coins`, "error")
		return
	end
	profile.coins -= nextLevel.cost
	profile.speedLevel += 1
	applyCharacter(player, profile)
	Net.notify(player, `⚡ Swim speed upgraded to {nextLevel.speed}!`, "success")
	PlayerData.changed(player)
end

local function buyTrail(player: Player, trailId: unknown)
	if not Net.isId(trailId) then
		return
	end
	local profile = PlayerData.get(player)
	local trail = Shop.trailById[trailId :: string]
	if not profile or not trail or trail.phase > Config.PHASE then
		return
	end
	if table.find(profile.trails, trail.id) then
		return
	end
	if not Economy.trailUnlocked(profile, trail) then
		Net.notify(player, `🔒 {trail.name} is still locked`, "error")
		return
	end
	if trail.currency == "Coins" then
		if profile.coins < trail.cost then
			Net.notify(player, `Need {trail.cost} coins`, "error")
			return
		end
		profile.coins -= trail.cost
	else
		if profile.gems < trail.cost then
			Net.notify(player, `Need {trail.cost} gems`, "error")
			return
		end
		profile.gems -= trail.cost
	end
	table.insert(profile.trails, trail.id)
	profile.equippedTrail = trail.id
	applyCharacter(player, profile)
	Net.notify(player, `✨ Unlocked {trail.name}!`, "success")
	PlayerData.changed(player)
end

local function equipTrail(player: Player, trailId: unknown)
	if typeof(trailId) ~= "string" or #trailId > 40 then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if trailId ~= "" and not table.find(profile.trails, trailId) then
		return
	end
	profile.equippedTrail = trailId
	applyCharacter(player, profile)
	PlayerData.changed(player)
end

function ShopSystem.init()
	Net.handle("BuySpeed", 3, 5, buySpeed)
	Net.handle("BuyTrail", 3, 5, buyTrail)
	Net.handle("EquipTrail", 3, 5, equipTrail)
	Players.PlayerRemoving:Connect(function(player)
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
			characterConnections[player] = nil
		end
	end)

	PlayerData.onLoaded(function(player, profile)
		applyCharacter(player, profile)
		characterConnections[player] = player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			local current = PlayerData.get(player)
			if current then
				applyCharacter(player, current)
			end
		end)
	end)
end

return ShopSystem
