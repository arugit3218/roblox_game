--!strict
-- Top bar (coins, gems, dex, uncollected aquarium coins), heist banner, toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local State = require(script.Parent.Parent.Lib.State)
local UI = require(script.Parent.Parent.Lib.UI)

local Hud = {}

local gui: ScreenGui
local coinsLabel: TextLabel
local gemsLabel: TextLabel
local dexLabel: TextLabel
local pendingLabel: TextLabel
local banner: TextLabel
local warning: TextLabel
local toastHolder: Frame

local function pill(text: string, color: Color3, order: number): TextLabel
	local frame = UI.new("Frame", {
		Size = UDim2.new(0.22, 0, 1, 0),
		BackgroundColor3 = UI.colors.panel,
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
	}, { UI.corner(12), UI.padding(6), UI.new("UIStroke", { Color = color, Thickness = 2 }) })
	local label = UI.label(
		text,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	label.Parent = frame
	frame.Parent = gui:FindFirstChild("TopBar")
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
		LayoutOrder = -math.floor(os.clock() * 100),
	}, { UI.corner(10), UI.padding(6), UI.new("UIStroke", { Color = color, Thickness = 2 }) })
	local label = UI.label(
		text,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }
	)
	label.Parent = frame
	frame.Parent = toastHolder

	-- keep at most 4 toasts
	local toasts = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
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

local function render()
	local snapshot = State.snapshot
	if not snapshot then
		return
	end
	local profile = snapshot.profile
	coinsLabel.Text = `💰 {Format.number(profile.coins)}`
	gemsLabel.Text = `💎 {Format.number(profile.gems)}`
	local dexCount = 0
	for _ in profile.dex do
		dexCount += 1
	end
	dexLabel.Text = `📖 {dexCount}/50`
	local pending = Economy.aquariumPending(profile, State.now())
	pendingLabel.Text = `🐠 {Format.number(pending)} ready`

	local carrying = snapshot.carrying
	banner.Visible = carrying ~= nil
	if carrying then
		banner.Text =
			`{if carrying.kind == "Aquarium" then "🏠" else "🍽"} Carrying a {carrying.kind} Egg — swim back to the <b>SAFE ZONE</b>!`
	end
	warning.Visible = not snapshot.saving
end

function Hud.init()
	local player = Players.LocalPlayer
	gui = UI.new("ScreenGui", {
		Name = "Hud",
		DisplayOrder = 10, -- toasts above menus
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	UI.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.6, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(720, 44) }),
	})
	coinsLabel = pill("💰 0", UI.colors.warn, 1)
	gemsLabel = pill("💎 0", UI.colors.accent, 2)
	pendingLabel = pill("🐠 0 ready", UI.colors.good, 3)
	dexLabel = pill("📖 0/50", UI.colors.muted, 4)

	banner = UI.label("", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0.7, 0, 0, 40),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = UI.colors.bad,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = gui,
	})
	UI.corner(10).Parent = banner
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(640, 40), Parent = banner })

	warning = UI.label("⚠ Studio temporary profile — progress will NOT save", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(0.4, 0, 0, 20),
		TextColor3 = UI.colors.warn,
		Visible = false,
		Parent = gui,
	})

	toastHolder = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(0.5, 0, 0, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(560, 200) }),
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
