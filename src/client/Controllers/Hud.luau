--!strict
-- HUD: big objective text (top), wallet + speed quick-upgrade (bottom-left),
-- Golden Current event timer (bottom-right), toasts, and "+coins" pops.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local Shop = require(Shared.GameData.Shop)
local Types = require(Shared.Types)
local State = require(script.Parent.Parent.Lib.State)
local UI = require(script.Parent.Parent.Lib.UI)

local Hud = {}

local gui: ScreenGui
local objective: TextLabel
local objectiveSub: TextLabel
local coinsLabel: TextLabel
local gemsLabel: TextLabel
local speedLabel: TextLabel
local speedButton: TextButton
local eventLabel: TextLabel
local warning: TextLabel
local toastHolder: Frame

local lastCoins: number? = nil
local lastCarrying: Types.Carrying? = nil
local securedUntil = 0
local lastHeists = 0

local OUTLINE = Color3.fromRGB(10, 30, 60)

local function stroke(parent: Instance, thickness: number?)
	UI.new("UIStroke", {
		Color = OUTLINE,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

local function bigText(text: string, props: { [string]: any }): TextLabel
	local label = UI.label(text, props)
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MaxTextSize = 60
	end
	stroke(label)
	return label
end

function Hud.toast(text: string, kind: string)
	local color = if kind == "success"
		then UI.colors.good
		elseif kind == "error" then UI.colors.bad
		elseif kind == "warn" then UI.colors.warn
		else UI.colors.accent
	local frame = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = UI.colors.panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = math.floor(os.clock() * 100),
	}, { UI.corner(10), UI.padding(6), UI.new("UIStroke", { Color = color, Thickness = 2 }) })
	local label = UI.label(
		text,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	label.Parent = frame
	frame.Parent = toastHolder

	local toasts = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 3 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end

	task.delay(3.5, function()
		if frame.Parent then
			local info = TweenInfo.new(0.4)
			TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			task.wait(0.45)
			frame:Destroy()
		end
	end)
end

local function coinPop(amount: number)
	local pop = bigText(`+{Format.number(amount)}`, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 70, 1, -96),
		Size = UDim2.new(0, 220, 0, 34),
		TextColor3 = Color3.fromRGB(255, 230, 90),
		Parent = gui,
	})
	local tween = TweenService:Create(
		pop,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 70, 1, -150), TextTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Once(function()
		pop:Destroy()
	end)
end

local function setObjective(title: string, sub: string, color: Color3)
	if objective.Text ~= title then
		objective.Text = title
		objective.TextColor3 = color
		-- little pop when the goal changes
		objective.Size = UDim2.new(0.8, 0, 0, 70)
		TweenService:Create(objective, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
			Size = UDim2.new(0.7, 0, 0, 60),
		}):Play()
	end
	objectiveSub.Text = sub
end

local function render()
	local snapshot = State.snapshot
	if not snapshot then
		return
	end
	local profile = snapshot.profile
	local now = State.now()

	-- Wallet
	coinsLabel.Text = `💰 {Format.number(profile.coins)}`
	gemsLabel.Text = `💎 {Format.number(profile.gems)}`
	if lastCoins and profile.coins > lastCoins then
		coinPop(profile.coins - lastCoins)
	end
	lastCoins = profile.coins

	-- Speed + quick upgrade
	speedLabel.Text = `⚡ {Economy.walkSpeed(profile.speedLevel)}`
	local nextLevel = Shop.speedLevels[profile.speedLevel + 1]
	if nextLevel then
		speedButton.Text = `+ 💰{Format.number(nextLevel.cost)}`
		speedButton.BackgroundColor3 = if profile.coins >= nextLevel.cost
			then UI.colors.good
			else UI.colors.disabled
	else
		speedButton.Text = "MAX"
		speedButton.BackgroundColor3 = UI.colors.disabled
	end

	-- Objective
	local carrying = snapshot.carrying
	if lastCarrying and not carrying and profile.heists > lastHeists then
		securedUntil = os.clock() + 2.5 -- escaped (not caught)
	end
	lastCarrying = carrying
	lastHeists = profile.heists
	if carrying then
		setObjective(
			"Escape to the SAFE ZONE!",
			"Follow the green arrows — don't get caught!",
			UI.colors.good
		)
	elseif os.clock() < securedUntil then
		setObjective("Egg Secured! 🥚", "It's hatching in your incubator", UI.colors.warn)
	elseif #profile.eggs >= Config.INCUBATOR_SLOTS then
		setObjective("Incubator full!", "Wait for an egg to hatch", UI.colors.muted)
	else
		local nextTier = math.min(profile.highestTier + 1, Config.MAX_TIER)
		setObjective(
			"Steal an Egg!",
			`Follow the arrows to the Tier {nextTier} nest`,
			Color3.new(1, 1, 1)
		)
	end

	warning.Visible = not snapshot.saving

	-- Event timer
	local endsAt = workspace:GetAttribute("EventEndsAt")
	local nextAt = workspace:GetAttribute("NextEventAt")
	local tint = Lighting:FindFirstChild("UnderwaterTint")
	if typeof(endsAt) == "number" and now < endsAt then
		eventLabel.Text = `🌟 GOLDEN CURRENT · {Format.duration(endsAt - now)}`
		eventLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
		if tint and tint:IsA("ColorCorrectionEffect") then
			tint.TintColor = Color3.fromRGB(255, 240, 200)
		end
	else
		if typeof(nextAt) == "number" then
			eventLabel.Text = `🌟 Golden Current in {Format.duration(nextAt - now)}`
		end
		eventLabel.TextColor3 = Color3.new(1, 1, 1)
		if tint and tint:IsA("ColorCorrectionEffect") then
			tint.TintColor = Color3.fromRGB(225, 248, 255)
		end
	end
end

function Hud.init()
	local player = Players.LocalPlayer
	gui = UI.new("ScreenGui", {
		Name = "Hud",
		DisplayOrder = 10,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UI.autoScale(gui)

	objective = bigText("Steal an Egg!", {
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0.7, 0, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	objectiveSub = UI.label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(0.6, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	stroke(objectiveSub, 2)

	-- Bottom-left wallet
	local wallet = UI.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(0, 260, 0, 130),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
	})
	local speedRow = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = wallet,
	})
	speedLabel = bigText("⚡ 25", { Size = UDim2.new(0, 110, 1, 0), Parent = speedRow })
	speedButton = UI.button("+", UI.colors.good, function()
		State.request("BuySpeed")
	end, {
		Name = "SpeedUpgrade",
		Position = UDim2.new(0, 116, 0, 2),
		Size = UDim2.new(0, 110, 1, -4),
	})
	speedButton.Parent = speedRow
	gemsLabel = bigText("💎 0", {
		Size = UDim2.new(1, 0, 0, 34),
		TextColor3 = Color3.fromRGB(130, 230, 255),
		LayoutOrder = 2,
		Parent = wallet,
	})
	coinsLabel = bigText("💰 0", {
		Size = UDim2.new(1, 0, 0, 50),
		TextColor3 = Color3.fromRGB(120, 255, 120),
		LayoutOrder = 3,
		Parent = wallet,
	})

	-- Bottom-right event timer
	eventLabel = bigText("", {
		Name = "EventTimer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.new(0, 360, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = gui,
	})

	warning = UI.label("⚠ Studio temporary profile — progress will NOT save", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(0.4, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.colors.warn,
		Visible = false,
		Parent = gui,
	})

	toastHolder = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0.42, 0, 0, 180),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(560, 180) }),
	})

	local notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent
	notify.OnClientEvent:Connect(function(text: unknown, kind: unknown)
		if typeof(text) == "string" then
			Hud.toast(text, if typeof(kind) == "string" then kind else "info")
		end
	end)
	State.onChanged(render)
end

function Hud.start()
	while true do
		render()
		task.wait(0.5)
	end
end

return Hud
