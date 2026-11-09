--!strict
-- Side menu + panels: Eggs, Aquarium, Kitchen (caviar + orders), Shop.
-- Panels only render state and send requests; the server validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.GameData.Creatures)
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local Rarities = require(Shared.GameData.Rarities)
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

local function rarityText(rarity: string): string
	local def = (Rarities :: any)[rarity]
	return if def then `<font color='#{def.color:ToHex()}'>{rarity}</font>` else rarity
end

local function clear()
	for _, child in content:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	rowCount = 0
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
local function row(text: string, buttonText: string?, buttonColor: Color3?, onClick: (() -> ())?)
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
	end
end

-- Panels ---------------------------------------------------------------------

local function renderEggs(profile: Profile, now: number)
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
		local remaining = egg.hatchAt - now
		row(
			`{icon} {if def then def.name else "?"} {egg.kind} Egg · {rarityText(egg.rarity)}`,
			if remaining > 0 then `⏳ {Format.duration(remaining)}` else "🐣 Hatching…",
			UI.colors.disabled,
			nil
		)
	end
	heading("Pokedex")
	local dexCount = 0
	for _ in profile.dex do
		dexCount += 1
	end
	note(`Discovered {dexCount} of 50 pets (25 creatures × Aquarium/Caviar)`)
end

local function renderAquarium(profile: Profile, now: number)
	local rate = Economy.aquariumRatePerSecond(profile) * 3600
	local pending = Economy.aquariumPending(profile, now)
	heading("Visitor income")
	row(
		`🐠 {Format.number(rate)} coins/hour · <b>{Format.number(pending)}</b> ready`,
		"Collect",
		UI.colors.good,
		function()
			State.request("CollectAquarium")
		end
	)
	note("Income keeps building while you're offline (up to 12 hours).")
	heading(`Display pets ({Economy.countPlaced(profile, "Aquarium")}/{Config.AQUARIUM_SLOTS})`)
	local any = false
	for _, pet in profile.pets do
		if pet.kind == "Aquarium" then
			any = true
			local r = Rarities[pet.rarity]
			row(
				`{pet.name} · {rarityText(pet.rarity)}`,
				if pet.placed then `{r.visitorsPerHour * r.coinsPerVisitor}/hr` else "Stored",
				UI.colors.disabled,
				nil
			)
		end
	end
	if not any then
		note("Steal an 🏠 Aquarium Egg to get display pets.")
	end
end

local function renderKitchen(profile: Profile, now: number)
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
				row(
					`{pet.name} · making {pet.pendingUnits} caviar`,
					`🍳 {Format.duration(pet.feedReadyAt - now)}`,
					UI.colors.disabled,
					nil
				)
			else
				local affordable = profile.coins >= r.feedCost
				row(
					`{pet.name} · {rarityText(pet.rarity)} → {r.caviarUnits} caviar`,
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

local RENDERERS: { [string]: (Profile, number) -> () } = {
	Eggs = renderEggs,
	Aquarium = renderAquarium,
	Kitchen = renderKitchen,
	Shop = function(profile)
		renderShop(profile)
	end,
}

local function render()
	if not current or not State.snapshot then
		return
	end
	local scroll = content.CanvasPosition
	clear()
	RENDERERS[current](State.snapshot.profile, State.now())
	content.CanvasPosition = scroll
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

	local side = UI.new("Frame", {
		Name = "Side",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 4 * 54),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.new(
			"UIListLayout",
			{ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})
	for i, entry in
		{
			{ "Eggs", "🥚 Eggs" },
			{ "Aquarium", "🐠 Aquarium" },
			{ "Kitchen", "🍽 Kitchen" },
			{ "Shop", "🛒 Shop" },
		}
	do
		local b = UI.button(entry[2], UI.colors.panel, function()
			open(entry[1])
		end, { Name = entry[1] .. "Button", Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i })
		UI.new("UIStroke", {
			Color = UI.colors.accent,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = b,
		})
		b.Parent = side
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
		task.wait(1)
		render() -- refresh countdowns
	end
end

return Menus
