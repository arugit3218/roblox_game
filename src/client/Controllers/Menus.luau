--!strict
-- Right-side icon buttons + panels: Eggs, Aquarium, Kitchen (caviar + orders), Shop, Index.
-- Panels only render state and send requests; the server validates everything.
-- Panels rebuild only when state changes; countdown labels tick in place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.GameData.Creatures)
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local Rarities = require(Shared.GameData.Rarities)
local Variants = require(Shared.GameData.Variants)
local Shop = require(Shared.GameData.Shop)
local Types = require(Shared.Types)
local State = require(script.Parent.Parent.Lib.State)
local UI = require(script.Parent.Parent.Lib.UI)

type Profile = Types.PlayerProfile

local Menus = {}

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local content: ScrollingFrame
local current: string? = nil
local rowCount = 0
local aquariumBadge: TextLabel

-- Countdown labels updated in place every 0.5s (no panel rebuild).
type Timer = { label: TextLabel, endsAt: number, format: (number) -> string }
local timers: { Timer } = {}

local function rarityText(rarity: string): string
	local def = (Rarities :: any)[rarity]
	return if def then `<font color='#{def.color:ToHex()}'>{rarity}</font>` else rarity
end

local function variantText(pet: Types.Pet): string
	local v = Variants.get(pet.variant)
	return if v.name == "Normal" then "" else `<font color='#{v.color:ToHex()}'>{v.label}</font> `
end

local function clear()
	for _, child in content:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	rowCount = 0
	table.clear(timers)
end

local function heading(text: string)
	rowCount += 1
	UI.label(`<b>{text}</b>`, {
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = UI.colors.accent,
		LayoutOrder = rowCount,
		Parent = content,
	})
end

local function note(text: string)
	rowCount += 1
	UI.label(text, {
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = UI.colors.muted,
		LayoutOrder = rowCount,
		Parent = content,
	})
end

-- A row with descriptive text and an optional action button.
local function row(
	text: string,
	buttonText: string?,
	buttonColor: Color3?,
	onClick: (() -> ())?
): TextButton?
	rowCount += 1
	local frame = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = UI.colors.panelLight,
		LayoutOrder = rowCount,
		Parent = content,
	}, { UI.corner(8), UI.padding(6) })
	UI.label(text, {
		Size = UDim2.new(if buttonText then 0.66 else 1, 0, 1, 0),
		Parent = frame,
	})
	if buttonText then
		local b = UI.button(buttonText, buttonColor or UI.colors.accent, onClick, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0.32, 0, 1, 0),
		})
		b.Parent = frame
		return b
	end
	return nil
end

local function countdown(button: TextButton?, endsAt: number, format: (number) -> string)
	if button then
		table.insert(timers, { label = button :: any, endsAt = endsAt, format = format })
	end
end

-- Panels ---------------------------------------------------------------------

local function renderEggs(profile: Profile, _now: number)
	heading(`Incubator ({#profile.eggs}/{Config.INCUBATOR_SLOTS})`)
	if #profile.eggs == 0 then
		note("No eggs yet. Head to the Heist Field and steal one!")
	end
	local eggs = table.clone(profile.eggs)
	table.sort(eggs, function(a, b)
		return a.hatchAt < b.hatchAt
	end)
	for _, egg in eggs do
		local def = Creatures.get(egg.tier)
		local icon = if egg.kind == "Aquarium" then "🏠" else "🍽"
		local b = row(
			`{icon} {if def then def.name else "?"} {egg.kind} Egg · {rarityText(egg.rarity)}`,
			"",
			UI.colors.disabled,
			nil
		)
		countdown(b, egg.hatchAt, function(remaining)
			return if remaining > 0 then `⏳ {Format.duration(remaining)}` else "🐣 Hatching…"
		end)
	end
	heading("Pokedex")
	local dexCount = 0
	for _ in profile.dex do
		dexCount += 1
	end
	note(`Discovered {dexCount} of 50 pets (25 creatures × Aquarium/Caviar)`)
end

local function renderAquarium(profile: Profile, _now: number)
	local rate = Economy.aquariumRatePerSecond(profile) * 3600
	heading("Visitor income")
	local b = row(`🐠 {Format.number(rate)} coins/hour`, "Collect", UI.colors.good, function()
		State.request("CollectAquarium")
	end)
	countdown(b, 0, function()
		local snap = State.snapshot
		local amount = if snap then Economy.aquariumPending(snap.profile, State.now()) else 0
		return `Collect 💰{Format.number(amount)}`
	end)
	note("Income keeps building while you're offline (up to 12 hours).")
	heading(`Display pets ({Economy.countPlaced(profile, "Aquarium")}/{Config.AQUARIUM_SLOTS})`)
	local any = false
	for _, pet in profile.pets do
		if pet.kind == "Aquarium" then
			any = true
			row(
				`{variantText(pet)}{pet.name} · {rarityText(pet.rarity)}`,
				if pet.placed then `{Format.number(Economy.petIncomePerHour(pet))}/hr` else "Stored",
				UI.colors.disabled,
				nil
			)
		end
	end
	if not any then
		note("Steal an 🏠 Aquarium Egg to get display pets.")
	end
end

local function renderKitchen(profile: Profile, _now: number)
	heading("Caviar stock")
	local stock = {}
	for _, rarity in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
		local n = profile.caviar[rarity] or 0
		if n > 0 then
			table.insert(stock, `{rarityText(rarity)}: {Format.number(n)}`)
		end
	end
	note(
		if #stock > 0 then table.concat(stock, "  ·  ") else "No caviar yet — feed a caviar pet."
	)

	heading(`Caviar pets ({Economy.countPlaced(profile, "Caviar")}/{Config.KITCHEN_SLOTS})`)
	local any = false
	for _, pet in profile.pets do
		if pet.kind == "Caviar" then
			any = true
			local r = Rarities[pet.rarity]
			if not pet.placed then
				row(`{pet.name} · {rarityText(pet.rarity)}`, "Stored", UI.colors.disabled, nil)
			elseif pet.feedReadyAt > 0 then
				local b = row(
					`{pet.name} · making {pet.pendingUnits} caviar`,
					"",
					UI.colors.disabled,
					nil
				)
				countdown(b, pet.feedReadyAt, function(remaining)
					return `🍳 {Format.duration(remaining)}`
				end)
			else
				local affordable = profile.coins >= r.feedCost
				row(
					`{variantText(pet)}{pet.name} · {rarityText(pet.rarity)} → {Economy.caviarUnits(
						pet
					)} caviar`,
					`Feed 💰{Format.number(r.feedCost)}`,
					if affordable then UI.colors.warn else UI.colors.disabled,
					function()
						State.request("FeedPet", pet.id)
					end
				)
			end
		end
	end
	if not any then
		note("Steal a 🍽 Caviar Egg to get caviar pets.")
	end

	heading("Customer orders")
	for _, order in profile.orders do
		local have = profile.caviar[order.rarity] or 0
		local ready = have >= order.units
		row(
			`🧾 {order.units} {rarityText(order.rarity)} caviar → 💰{Format.number(
				order.reward
			)}`,
			if ready then "Serve" else `{have}/{order.units}`,
			if ready then UI.colors.good else UI.colors.disabled,
			function()
				State.request("FulfillOrder", order.id)
			end
		)
	end
	note("Orders never expire — serve them whenever you're ready.")
end

local function renderShop(profile: Profile)
	heading("Swim speed")
	local nextLevel = Shop.speedLevels[profile.speedLevel + 1]
	local speed = Economy.walkSpeed(profile.speedLevel)
	if nextLevel then
		row(
			`⚡ Speed {speed} → {nextLevel.speed} (Lv {profile.speedLevel}/{#Shop.speedLevels})`,
			`💰 {Format.number(nextLevel.cost)}`,
			if profile.coins >= nextLevel.cost then UI.colors.warn else UI.colors.disabled,
			function()
				State.request("BuySpeed")
			end
		)
	else
		row(`⚡ Speed {speed} (max for now)`, nil, nil, nil)
	end

	heading("Trails")
	row(
		"No trail",
		if profile.equippedTrail == "" then "Equipped" else "Equip",
		if profile.equippedTrail == "" then UI.colors.disabled else UI.colors.accent,
		function()
			State.request("EquipTrail", "")
		end
	)
	for _, trail in Shop.trails do
		if trail.phase > Config.PHASE then
			continue
		end
		local owned = table.find(profile.trails, trail.id) ~= nil
		local unlocked = Economy.trailUnlocked(profile, trail)
		local price =
			`{if trail.currency == "Coins" then "💰" else "💎"} {Format.number(trail.cost)}`
		if owned then
			local equipped = profile.equippedTrail == trail.id
			row(
				`✨ {trail.name}`,
				if equipped then "Equipped" else "Equip",
				if equipped then UI.colors.disabled else UI.colors.accent,
				function()
					State.request("EquipTrail", trail.id)
				end
			)
		elseif not unlocked then
			row(
				`🔒 {trail.name} · steal a Tier {trail.unlock.value} egg`,
				price,
				UI.colors.disabled,
				nil
			)
		else
			row(`✨ {trail.name}`, price, UI.colors.warn, function()
				State.request("BuyTrail", trail.id)
			end)
		end
	end
end

local function renderIndex(profile: Profile)
	local found = 0
	for _ in profile.dex do
		found += 1
	end
	heading(`Index · {found}/50 discovered`)
	note("Steal both an 🏠 Aquarium and a 🍽 Caviar egg from every creature!")
	rowCount += 1
	local grid = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = rowCount,
		Parent = content,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.new(0.2, -6, 0, 74),
			CellPadding = UDim2.new(0, 6, 0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for _, def in Creatures.list do
		local aq = profile.dex[`{def.tier}:Aquarium`] == true
		local cv = profile.dex[`{def.tier}:Caviar`] == true
		local live = def.tier <= Config.MAX_TIER
		local seen = aq or cv
		local card = UI.new("Frame", {
			BackgroundColor3 = if seen then UI.colors.panelLight else UI.colors.disabled,
			LayoutOrder = def.tier,
			Parent = grid,
		}, {
			UI.corner(8),
			UI.padding(4),
			UI.new(
				"UIStroke",
				{ Color = Rarities[def.rarity].color, Thickness = if seen then 2 else 0 }
			),
		})
		UI.label(if seen then def.name else (if live then "???" else "🔒 Soon"), {
			Size = UDim2.new(1, 0, 0.45, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		UI.label(`T{def.tier} · {rarityText(def.rarity)}`, {
			Position = UDim2.new(0, 0, 0.42, 0),
			Size = UDim2.new(1, 0, 0.28, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.colors.muted,
			Parent = card,
		})
		UI.label(`{if aq then "🏠" else "▫️"} {if cv then "🍽" else "▫️"}`, {
			Position = UDim2.new(0, 0, 0.7, 0),
			Size = UDim2.new(1, 0, 0.3, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
	end
end

local RENDERERS: { [string]: (Profile, number) -> () } = {
	Eggs = renderEggs,
	Aquarium = renderAquarium,
	Kitchen = renderKitchen,
	Shop = function(profile)
		renderShop(profile)
	end,
	Index = function(profile)
		renderIndex(profile)
	end,
}

local function tickTimers()
	local now = State.now()
	for _, t in timers do
		if t.label.Parent then
			t.label.Text = t.format(t.endsAt - now)
		end
	end
	local snap = State.snapshot
	if snap and aquariumBadge then
		local pending = math.floor(Economy.aquariumPending(snap.profile, now))
		aquariumBadge.Visible = pending > 0
		aquariumBadge.Text = `+{Format.number(pending)}`
	end
end

local function render()
	if not current or not State.snapshot then
		return
	end
	local scroll = content.CanvasPosition
	clear()
	RENDERERS[current](State.snapshot.profile, State.now())
	content.CanvasPosition = scroll
	tickTimers()
end

local function open(name: string)
	if current == name then
		current = nil
		panel.Visible = false
		return
	end
	current = name
	title.Text = name
	panel.Visible = true
	content.CanvasPosition = Vector2.zero
	render()
end

function Menus.init()
	gui = UI.new("ScreenGui", {
		Name = "Menus",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	UI.autoScale(gui)

	local side = UI.new("Frame", {
		Name = "Side",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 84, 0, 5 * 92),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})
	local entries = {
		{ "Eggs", "🥚", "Eggs", Color3.fromRGB(240, 90, 90) },
		{ "Aquarium", "🐠", "Aquarium", Color3.fromRGB(60, 170, 240) },
		{ "Kitchen", "🍽", "Kitchen", Color3.fromRGB(250, 150, 50) },
		{ "Shop", "🛒", "Shop", Color3.fromRGB(80, 200, 110) },
		{ "Index", "📖", "Index", Color3.fromRGB(160, 100, 240) },
	}
	for i, entry in entries do
		local b = UI.new("TextButton", {
			Name = entry[1] .. "Button",
			Size = UDim2.new(1, 0, 0, 84),
			BackgroundColor3 = entry[4],
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = i,
			Parent = side,
		}, {
			UI.corner(14),
			UI.new("UIStroke", {
				Color = Color3.new(1, 1, 1),
				Thickness = 3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
		UI.label(entry[2], {
			Size = UDim2.new(1, 0, 0.66, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = b,
		})
			:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize =
			44
		local caption = UI.label(entry[3], {
			Position = UDim2.new(0, 0, 0.62, 0),
			Size = UDim2.new(1, 0, 0.34, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = b,
		})
		UI.new("UIStroke", { Color = Color3.fromRGB(10, 30, 60), Thickness = 2, Parent = caption })
		b.Activated:Connect(function()
			open(entry[1])
		end)
		if entry[1] == "Aquarium" then
			aquariumBadge = UI.label("", {
				Name = "Badge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(0, 4, 0, -6),
				Size = UDim2.new(0, 70, 0, 22),
				BackgroundTransparency = 0,
				BackgroundColor3 = UI.colors.good,
				TextXAlignment = Enum.TextXAlignment.Center,
				Visible = false,
				Parent = b,
			})
			UI.corner(8).Parent = aquariumBadge
		end
	end

	panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.66),
		BackgroundColor3 = UI.colors.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, {
		UI.corner(14),
		UI.padding(12),
		UI.new("UIStroke", { Color = UI.colors.accent, Thickness = 2 }),
		UI.new(
			"UISizeConstraint",
			{ MaxSize = Vector2.new(620, 520), MinSize = Vector2.new(300, 260) }
		),
	})
	title = UI.label("", { Size = UDim2.new(1, -50, 0, 34), Parent = panel })
	UI.button("<b>X</b>", UI.colors.bad, function()
		current = nil
		panel.Visible = false
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 34, 0, 34),
	}).Parent =
		panel

	content = UI.new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, {
		UI.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }
		),
		UI.new("UIPadding", { PaddingRight = UDim.new(0, 10) }),
	})

	State.onChanged(function()
		render()
	end)
end

function Menus.start()
	while true do
		task.wait(0.5)
		tickTimers()
	end
end

return Menus
