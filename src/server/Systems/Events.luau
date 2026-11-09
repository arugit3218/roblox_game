--!strict
-- Server-wide timed event ("Golden Current"): every EVENT_INTERVAL seconds it runs
-- for EVENT_DURATION. While active, stolen eggs get boosted Golden/Rainbow luck and
-- heists pay double coins. State replicates to clients via workspace attributes.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Parent.Lib.Net)

local Events = {}

function Events.isActive(): boolean
	local endsAt = workspace:GetAttribute("EventEndsAt")
	return typeof(endsAt) == "number" and workspace:GetServerTimeNow() < endsAt
end

function Events.luck(): number
	return if Events.isActive() then Config.EVENT_LUCK else 1
end

function Events.rewardMultiplier(): number
	return if Events.isActive() then Config.EVENT_REWARD_MULT else 1
end

function Events.init()
	workspace:SetAttribute("EventName", "Golden Current")
	workspace:SetAttribute("EventEndsAt", 0)
	workspace:SetAttribute("NextEventAt", workspace:GetServerTimeNow() + Config.EVENT_INTERVAL)
end

function Events.start()
	while true do
		task.wait(1)
		local now = workspace:GetServerTimeNow()
		local nextAt = workspace:GetAttribute("NextEventAt")
		if typeof(nextAt) ~= "number" or now < nextAt then
			continue
		end
		workspace:SetAttribute("EventEndsAt", now + Config.EVENT_DURATION)
		workspace:SetAttribute("NextEventAt", now + Config.EVENT_DURATION + Config.EVENT_INTERVAL)
		Net.notifyAll(
			"🌟 GOLDEN CURRENT! 3x Golden/Rainbow luck + 2x heist coins for 3 minutes!",
			"warn"
		)
	end
end

return Events
