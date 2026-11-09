--!strict
-- Studio-only QA hooks. Creates ServerStorage.DevCommand (BindableFunction) so
-- testers / tooling can grant coins or skip timers. Never exists in live servers,
-- and is server-only (BindableFunctions are not reachable from clients).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Idle = require(script.Parent.Idle)
local PlayerData = require(script.Parent.PlayerData)

local DevTools = {}

local function firstPlayer(name: unknown): Player?
	if typeof(name) == "string" then
		local p = Players:FindFirstChild(name)
		return if p and p:IsA("Player") then p else nil
	end
	return Players:GetPlayers()[1]
end

local commands: { [string]: (Player, any) -> any } = {
	coins = function(player, amount)
		local profile = assert(PlayerData.get(player))
		profile.coins += tonumber(amount) or 10000
		PlayerData.changed(player)
		return profile.coins
	end,
	skip = function(player)
		-- Finish all incubation + caviar timers now.
		local profile = assert(PlayerData.get(player))
		local now = os.time()
		for _, egg in profile.eggs do
			egg.hatchAt = now
		end
		for _, pet in profile.pets do
			if pet.feedReadyAt > 0 then
				pet.feedReadyAt = now
			end
		end
		PlayerData.changed(player)
		return true
	end,
	elapse = function(player, seconds)
		-- Pretend `seconds` passed for aquarium income.
		local profile = assert(PlayerData.get(player))
		profile.aquarium.lastSettle -= tonumber(seconds) or 3600
		PlayerData.changed(player)
		return true
	end,
	egg = function(player, spec)
		-- spec = "tier:Kind", e.g. "2:Aquarium"
		local profile = assert(PlayerData.get(player))
		local tierText, kind = string.match(tostring(spec), "^(%d+):(%a+)$")
		local tier = tonumber(tierText)
		if not tier or (kind ~= "Aquarium" and kind ~= "Caviar") then
			return "usage: egg <tier>:<Aquarium|Caviar>"
		end
		Idle.addEgg(profile, tier, kind :: any)
		PlayerData.changed(player)
		return true
	end,
	tier = function(player, tier)
		local profile = assert(PlayerData.get(player))
		profile.highestTier = tonumber(tier) or 5
		PlayerData.changed(player)
		return profile.highestTier
	end,
	profile = function(player)
		return PlayerData.get(player)
	end,
}

function DevTools.init()
	if not RunService:IsStudio() then
		return
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "DevCommand"
	fn.OnInvoke = function(cmd: string, playerName: string?, arg: any)
		local player = firstPlayer(playerName)
		local handler = commands[cmd]
		if not player or not handler then
			return "no player or unknown command"
		end
		return handler(player, arg)
	end
	fn.Parent = ServerStorage
end

return DevTools
