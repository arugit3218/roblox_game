--!strict
-- Builds the map at runtime from code (placeholder art): underwater lighting,
-- sea floor, the hub with player plots, the heist field with creature nests,
-- and the escape line. Also assigns plots and renders each player's pets.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.GameData.Creatures)
local Rarities = require(Shared.GameData.Rarities)
local Types = require(Shared.Types)
local PlayerData = require(script.Parent.PlayerData)

export type Nest = {
	tier: number,
	def: Creatures.CreatureDef,
	egg: BasePart,
	prompt: ProximityPrompt,
	label: BillboardGui,
	creature: Model,
	kind: Types.EggKind,
}

export type Plot = {
	index: number,
	model: Model,
	owner: Player?,
	sign: BillboardGui,
	pad: BasePart,
	tankCenter: Vector3,
	counterTop: Vector3,
	petsFolder: Folder,
}

local World = {}
World.nests = {} :: { [number]: Nest }
World.plots = {} :: { Plot }
World.spawnCFrame = CFrame.new(0, 4, 0)

local root: Folder

local SAND = Color3.fromRGB(214, 196, 150)
local AQUARIUM_COLOR = Color3.fromRGB(80, 220, 255)
local CAVIAR_COLOR = Color3.fromRGB(255, 120, 60)

-- Helpers --------------------------------------------------------------------

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- Sets a billboard's text: first line = title, remaining lines = smaller subtitle.
function World.setBillboard(gui: BillboardGui, text: string)
	local lines = string.split(text, "\n")
	local title = gui:FindFirstChild("Title") :: TextLabel
	local sub = gui:FindFirstChild("Sub") :: TextLabel
	title.Text = lines[1]
	local rest = table.concat(lines, "\n", 2)
	sub.Text = rest
	sub.Visible = rest ~= ""
	title.Size = if rest ~= "" then UDim2.fromScale(1, 0.6) else UDim2.fromScale(1, 1)
end

local function billboard(
	parent: Instance,
	text: string,
	offset: Vector3,
	size: UDim2,
	maxDistance: number
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	for _, name in { "Title", "Sub" } do
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = if name == "Title"
			then Color3.new(1, 1, 1)
			else Color3.fromRGB(210, 235, 255)
		label.TextStrokeTransparency = 0.3
		label.RichText = true
		label.Size = UDim2.fromScale(1, 0.4)
		label.Position = if name == "Title" then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 0.6)
		label.Parent = gui
	end
	gui.Parent = parent
	World.setBillboard(gui, text)
	return gui
end

local function bubbles(parent: BasePart, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Rate = rate
	e.Lifetime = NumberRange.new(4, 7)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(15, 15)
	e.Size = NumberSequence.new(0.3, 0.6)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
	e.LightEmission = 0.3
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
end

-- Creature model: elongated body (front = -Z), tail, eyes.
function World.makeCreature(def: Creatures.CreatureDef): Model
	local model = Instance.new("Model")
	model.Name = def.name
	local s = def.size
	local body = part({
		Name = "Body",
		Size = Vector3.new(s, s * 0.8, s * 1.6),
		Color = def.color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.Parent = model

	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Anchored = true
	tail.CanCollide = false
	tail.CanQuery = false
	tail.Size = Vector3.new(0.3, s * 0.9, s * 0.7)
	tail.Color = def.color
	tail.CFrame = body.CFrame * CFrame.new(0, 0, s * 0.95)
	tail.Parent = model

	for _, side in { -1, 1 } do
		local eye = part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * math.max(0.3, s * 0.18),
			Color = Color3.new(0.05, 0.05, 0.05),
			CanCollide = false,
			CanQuery = false,
		})
		eye.CFrame = body.CFrame * CFrame.new(side * s * 0.32, s * 0.15, -s * 0.62)
		eye.Parent = model
	end
	model.PrimaryPart = body
	return model
end

-- Build ----------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 1.4
	Lighting.Ambient = Color3.fromRGB(50, 100, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 130, 170)
	for _, name in { "UnderwaterAtmosphere", "UnderwaterTint" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "UnderwaterAtmosphere"
	atmosphere.Density = 0.6
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(30, 105, 150)
	atmosphere.Decay = Color3.fromRGB(5, 35, 70)
	atmosphere.Glare = 0
	atmosphere.Haze = 2.2
	atmosphere.Parent = Lighting
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "UnderwaterTint"
	tint.TintColor = Color3.fromRGB(170, 215, 255)
	tint.Saturation = 0.1
	tint.Parent = Lighting
end

local function buildFloor()
	-- Replace the template's default floor / spawns with ours.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and not d:IsDescendantOf(root) then
			d:Destroy()
		end
	end

	part({
		Name = "SeaFloor",
		Size = Vector3.new(640, 4, 560),
		Position = Vector3.new(0, -2, 70),
		Color = SAND,
		Material = Enum.Material.Sand,
		Parent = root,
	})

	part({
		Name = "WaterSurface",
		Size = Vector3.new(2000, 1, 2000),
		Position = Vector3.new(0, 70, 70),
		Color = Color3.fromRGB(40, 140, 200),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = root,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Color = Color3.fromRGB(60, 150, 190)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
	World.spawnCFrame = CFrame.new(0, 4, 0)

	local hint = part({
		Name = "HubSign",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 9, 20),
		Transparency = 1,
		CanCollide = false,
		Parent = root,
	})
	billboard(
		hint,
		"🥚 <b>HEIST FIELD</b> ↑\nSteal an egg, then swim back across the glowing line!",
		Vector3.zero,
		UDim2.fromScale(36, 9),
		200
	)
end

local function buildEscapeLine()
	local line = part({
		Name = "EscapeLine",
		Size = Vector3.new(620, 0.4, 6),
		Position = Vector3.new(0, 0.2, Config.ESCAPE_Z - 3),
		Color = Color3.fromRGB(80, 255, 220),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Parent = root,
	})
	for x = -300, 300, 60 do
		local post = part({
			Name = "SafePost",
			Size = Vector3.new(1, 10, 1),
			Position = Vector3.new(x, 5, Config.ESCAPE_Z - 3),
			Color = Color3.fromRGB(80, 255, 220),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = root,
		})
		if x == 0 then
			billboard(post, "<b>SAFE ZONE</b>", Vector3.new(0, 7, 0), UDim2.fromScale(20, 5), 220)
		end
	end
	return line
end

local function buildDecor()
	local rng = Random.new(42)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root
	for _ = 1, 90 do
		local x = rng:NextNumber(-300, 300)
		local z = rng:NextNumber(-180, 330)
		local h = rng:NextNumber(6, 18)
		-- keep paths / plots / nests clear-ish
		if math.abs(x) < 20 and z > -10 and z < 220 then
			continue
		end
		if z < -35 and z > -85 and math.abs(x) < 150 then
			continue
		end
		local kelp = part({
			Name = "Kelp",
			Size = Vector3.new(0.8, h, 0.4),
			Color = Color3.fromRGB(40, rng:NextInteger(120, 170), 60),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			Parent = decor,
		})
		kelp.CFrame = CFrame.new(x, h / 2, z)
			* CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6.28), 0)
	end
	for _ = 1, 40 do
		local x = rng:NextNumber(-300, 300)
		local z = rng:NextNumber(60, 330)
		local s = rng:NextNumber(2, 7)
		part({
			Name = "Rock",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * s,
			Position = Vector3.new(x, s * 0.25, z),
			Color = Color3.fromRGB(110, 115, 120),
			Material = Enum.Material.Slate,
			CanCollide = false,
			CanQuery = false,
			Parent = decor,
		})
	end
	for _ = 1, 12 do
		local emitter = part({
			Name = "BubbleVent",
			Size = Vector3.new(2, 0.4, 2),
			Position = Vector3.new(rng:NextNumber(-250, 250), 0.2, rng:NextNumber(-150, 300)),
			Color = Color3.fromRGB(120, 110, 100),
			CanCollide = false,
			CanQuery = false,
			Parent = decor,
		})
		bubbles(emitter, 4)
	end
end

-- Nest positions for each tier (later tiers further from the safe line).
local function nestPosition(tier: number): Vector3
	local row = (tier - 1) // 5
	local col = (tier - 1) % 5
	return Vector3.new(-100 + col * 50, 0, 110 + row * 45 + (if col % 2 == 1 then 15 else 0))
end

function World.setEggKind(nest: Nest, kind: Types.EggKind)
	nest.kind = kind
	nest.egg.Color = if kind == "Aquarium" then AQUARIUM_COLOR else CAVIAR_COLOR
	local def = nest.def
	World.setBillboard(
		nest.label,
		string.format(
			"<b>%s</b>\nTier %d · %s · %s",
			if kind == "Aquarium" then "🏠 Aquarium Egg" else "🍽 Caviar Egg",
			def.tier,
			def.name,
			def.rarity
		)
	)
end

local function buildNest(def: Creatures.CreatureDef)
	local pos = nestPosition(def.tier)
	local folder = Instance.new("Model")
	folder.Name = `Nest_{def.tier}`
	folder.Parent = root

	part({
		Name = "NestBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 9, 9),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 90, 60),
		Material = Enum.Material.Wood,
		Parent = folder,
	})

	local egg = part({
		Name = "Egg",
		Size = Vector3.new(2.4, 3, 2.4),
		Position = pos + Vector3.new(0, 2.5, 0),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = folder,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = egg

	local label = billboard(egg, "", Vector3.new(0, 4, 0), UDim2.fromScale(12, 3.5), 90)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal egg"
	prompt.ObjectText = `Tier {def.tier} · {def.name}`
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = egg

	local creature = World.makeCreature(def)
	creature:PivotTo(
		CFrame.lookAt(pos + Vector3.new(6, def.size * 0.5 + 1, 2), pos + Vector3.new(0, 2, -10))
	)
	creature.Parent = folder
	billboard(
		creature.PrimaryPart :: BasePart,
		`<b>{def.name}</b>\n{string.rep("⭐", def.stars)}`,
		Vector3.new(0, def.size * 0.6 + 2, 0),
		UDim2.fromScale(8, 2.5),
		80
	)

	local nest: Nest = {
		tier = def.tier,
		def = def,
		egg = egg,
		prompt = prompt,
		label = label,
		creature = creature,
		kind = "Aquarium",
	}
	World.setEggKind(nest, if math.random() < 0.5 then "Aquarium" else "Caviar")
	World.nests[def.tier] = nest
end

local PLOT_COUNT = 8
local function buildPlot(index: number)
	local x = -126 + (index - 1) * 36
	local z = -60
	local model = Instance.new("Model")
	model.Name = `Plot{index}`
	model.Parent = root

	part({
		Name = "Base",
		Size = Vector3.new(32, 0.4, 28),
		Position = Vector3.new(x, 0.2, z),
		Color = Color3.fromRGB(70, 150, 170),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local tank = part({
		Name = "Tank",
		Size = Vector3.new(24, 10, 6),
		Position = Vector3.new(x, 5.4, z - 9),
		Color = Color3.fromRGB(150, 220, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.65,
		Parent = model,
	})
	part({
		Name = "TankBase",
		Size = Vector3.new(25, 0.6, 7),
		Position = Vector3.new(x, 0.5, z - 9),
		Color = Color3.fromRGB(60, 60, 70),
		Parent = model,
	})
	local sign = billboard(tank, "Empty plot", Vector3.new(0, 7.5, 0), UDim2.fromScale(16, 3), 150)

	part({
		Name = "Counter",
		Size = Vector3.new(14, 3, 4),
		Position = Vector3.new(x + 7, 1.9, z + 6),
		Color = Color3.fromRGB(230, 230, 235),
		Material = Enum.Material.Marble,
		Parent = model,
	})
	local kitchenSign = part({
		Name = "KitchenSign",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(x + 7, 7, z + 6),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	billboard(kitchenSign, "🍽 Kitchen", Vector3.zero, UDim2.fromScale(8, 2), 80)

	local pad = part({
		Name = "CollectPad",
		Size = Vector3.new(5, 0.3, 5),
		Position = Vector3.new(x - 9, 0.55, z + 6),
		Color = Color3.fromRGB(255, 210, 60),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Collect coins"
	prompt.ObjectText = "Aquarium visitors"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	local petsFolder = Instance.new("Folder")
	petsFolder.Name = "Pets"
	petsFolder.Parent = model

	table.insert(World.plots, {
		index = index,
		model = model,
		owner = nil,
		sign = sign,
		pad = pad,
		tankCenter = tank.Position,
		counterTop = Vector3.new(x + 7, 3.4, z + 6),
		petsFolder = petsFolder,
	})
end

-- Plots & pets ---------------------------------------------------------------

function World.getPlot(player: Player): Plot?
	for _, plot in World.plots do
		if plot.owner == player then
			return plot
		end
	end
	return nil
end

local renderedVersion: { [Player]: string } = {}

local function petSignature(profile: Types.PlayerProfile): string
	local parts = {}
	for _, pet in profile.pets do
		if pet.placed then
			table.insert(parts, pet.id .. (if pet.feedReadyAt > 0 then "f" else ""))
		end
	end
	return table.concat(parts, ",")
end

function World.renderPets(player: Player, profile: Types.PlayerProfile)
	local plot = World.getPlot(player)
	if not plot then
		return
	end
	local sig = petSignature(profile)
	if renderedVersion[player] == sig then
		return
	end
	renderedVersion[player] = sig
	plot.petsFolder:ClearAllChildren()

	local aquariumIndex, kitchenIndex = 0, 0
	for _, pet in profile.pets do
		if not pet.placed then
			continue
		end
		local def = Creatures.get(pet.tier)
		if not def then
			continue
		end
		local model = World.makeCreature({
			tier = def.tier,
			name = pet.name,
			stars = def.stars,
			rarity = def.rarity,
			speedClass = def.speedClass,
			reward = def.reward,
			color = def.color,
			size = math.min(def.size, 2.6) * 0.8,
		})
		local cf: CFrame
		if pet.kind == "Aquarium" then
			local col = aquariumIndex % 5
			local row = aquariumIndex // 5
			aquariumIndex += 1
			local p = plot.tankCenter + Vector3.new(-8 + col * 4, -2 + row * 3.5, 0)
			cf = CFrame.lookAt(p, p + Vector3.new(if row % 2 == 0 then 1 else -1, 0, 0))
		else
			local p = plot.counterTop + Vector3.new(-5.5 + kitchenIndex * 2.2, 1, 0)
			kitchenIndex += 1
			cf = CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
		end
		model:PivotTo(cf)
		local rarityColor = Rarities[pet.rarity].color:ToHex()
		billboard(
			model.PrimaryPart :: BasePart,
			string.format(
				"<font color='#%s'>%s</font>%s",
				rarityColor,
				pet.name,
				if pet.feedReadyAt > 0 then "\n🍳" else ""
			),
			Vector3.new(0, 1.6, 0),
			UDim2.fromScale(4, 1.1),
			18
		)
		model.Parent = plot.petsFolder
	end
end

local function assignPlot(player: Player)
	for _, plot in World.plots do
		if plot.owner == nil then
			plot.owner = player
			World.setBillboard(plot.sign, `<b>{player.DisplayName}'s Aquarium</b>`)
			return
		end
	end
	warn(`[World] no free plot for {player.Name}`)
end

local function releasePlot(player: Player)
	local plot = World.getPlot(player)
	if plot then
		plot.owner = nil
		World.setBillboard(plot.sign, "Empty plot")
		plot.petsFolder:ClearAllChildren()
	end
	renderedVersion[player] = nil
end

function World.init()
	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = workspace

	buildLighting()
	buildFloor()
	buildEscapeLine()
	buildDecor()
	for tier = 1, Config.MAX_TIER do
		local def = Creatures.get(tier)
		if def then
			buildNest(def)
		end
	end
	for i = 1, PLOT_COUNT do
		buildPlot(i)
	end

	PlayerData.onLoaded(function(player, profile)
		assignPlot(player)
		World.renderPets(player, profile)
	end)
	PlayerData.onChanged(World.renderPets)
	Players.PlayerRemoving:Connect(releasePlot)
end

return World
