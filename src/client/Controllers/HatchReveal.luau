--!strict
-- Pet-reveal moment when an egg hatches: egg shakes, flashes, then a card shows
-- the pet's name, rarity, variant (Golden/Rainbow), income and a NEW! badge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local Rarities = require(Shared.GameData.Rarities)
local Types = require(Shared.Types)
local Variants = require(Shared.GameData.Variants)
local UI = require(script.Parent.Parent.Lib.UI)

local HatchReveal = {}

local gui: ScreenGui
local queue: { { pet: Types.Pet, isNew: boolean } } = {}
local showing = false

local function outlined(label: TextLabel, thickness: number?)
	UI.new(
		"UIStroke",
		{ Color = Color3.fromRGB(10, 30, 60), Thickness = thickness or 3, Parent = label }
	)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = 64
	end
end

local function show(pet: Types.Pet, isNew: boolean)
	local rarity = Rarities[pet.rarity]
	local variant = Variants.get(pet.variant)
	local accent = if variant.name ~= "Normal" then variant.color else rarity.color

	local overlay = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()

	-- 1) shaking egg
	local egg = UI.label(if pet.kind == "Aquarium" then "🥚" else "🥚", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(160, 160),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = overlay,
	})
	local eggConstraint = egg:FindFirstChildOfClass("UITextSizeConstraint")
	if eggConstraint then
		eggConstraint.MaxTextSize = 140
	end
	for i = 1, if #queue > 1 then 2 else 6 do
		local angle = if i % 2 == 0 then 14 else -14
		local t = TweenService:Create(egg, TweenInfo.new(0.09), { Rotation = angle * (i / 3) })
		t:Play()
		t.Completed:Wait()
	end
	egg:Destroy()

	-- 2) flash
	local flash = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.2,
		Parent = overlay,
	})
	TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()

	-- 3) card
	local card = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = UI.colors.panel,
		Parent = overlay,
	}, {
		UI.corner(18),
		UI.new("UIStroke", { Color = accent, Thickness = 4 }),
		UI.padding(14),
	})
	TweenService
		:Create(
			card,
			TweenInfo.new(0.35, Enum.EasingStyle.Back),
			{ Size = UDim2.fromOffset(420, 260) }
		)
		:Play()

	if variant.name ~= "Normal" then
		local v = UI.label(variant.label, {
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = variant.color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		outlined(v)
	end
	local name = UI.label(pet.name, {
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 52),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})
	outlined(name)
	UI.label(`<font color='#{rarity.color:ToHex()}'><b>{pet.rarity}</b></font> · {pet.kind} pet`, {
		Position = UDim2.new(0, 0, 0, 100),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})
	local perk = if pet.kind == "Aquarium"
		then `🐠 +{Format.number(Economy.petIncomePerHour(pet))} coins/hour`
		else `🍳 {Format.number(Economy.caviarUnits(pet))} caviar per feed`
	UI.label(perk, {
		Position = UDim2.new(0, 0, 0, 136),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UI.colors.good,
		Parent = card,
	})
	if isNew then
		local badge = UI.label("NEW! 📖", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 180),
			Size = UDim2.new(0, 150, 0, 36),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(255, 80, 120),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		UI.corner(10).Parent = badge
	end

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card, TweenInfo.new(0.2), { Size = UDim2.fromOffset(0, 0) }):Play()
		task.wait(0.25)
		overlay:Destroy()
	end
	local dismiss = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = overlay,
	})
	dismiss.Activated:Connect(close)
	-- Linger on rare pets; hurry through a backlog (e.g. returning after being offline).
	local hold = if variant.name ~= "Normal" then 3.5 elseif #queue > 1 then 1.2 else 2.6
	local untilTime = os.clock() + hold
	while not closed and os.clock() < untilTime do
		task.wait(0.1)
	end
	close()
end

local function pump()
	if showing then
		return
	end
	showing = true
	while #queue > 0 do
		local item = table.remove(queue, 1) :: { pet: Types.Pet, isNew: boolean }
		show(item.pet, item.isNew)
	end
	showing = false
end

function HatchReveal.init()
	gui = UI.new("ScreenGui", {
		Name = "HatchReveal",
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Hatched") :: RemoteEvent
	remote.OnClientEvent:Connect(function(pet: any, isNew: any)
		if typeof(pet) ~= "table" then
			return
		end
		table.insert(queue, { pet = pet, isNew = isNew == true })
		task.spawn(pump)
	end)
end

return HatchReveal
