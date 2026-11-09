--!strict
-- Builds the map at runtime from code: bright reef lighting, sea floor, the hub
-- with player plots, the walled reef canyon (heist field) with creature nests, and
-- the painted SAFE ZONE. Also assigns plots, renders pets, and shows nest state
-- (egg type, sleeping guardians).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.GameData.Creatures)
local Rarities = require(Shared.GameData.Rarities)
local Types = require(Shared.Types)
local Variants = require(Shared.GameData.Variants)
local PlayerData = require(script.Parent.PlayerData)

export type Nest = {
	tier: number,
	def: Creatures.CreatureDef,
	egg: BasePart,
	prompt: ProximityPrompt,
	label: BillboardGui,
	creature: Model,
	creaturePivot: CFrame,
	sleepGui: BillboardGui,
	kind: Types.EggKind,
	asleep: boolean,
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

-- Palette
local SAND = Color3.fromRGB(246, 226, 176)
local CANYON_SAND = Color3.fromRGB(236, 208, 150)
local PATH = Color3.fromRGB(255, 240, 205)
local ROCK =
	{ Color3.fromRGB(96, 132, 156), Color3.fromRGB(82, 116, 142), Color3.fromRGB(112, 146, 166) }
local CORAL = {
	Color3.fromRGB(255, 105, 140),
	Color3.fromRGB(255, 150, 70),
	Color3.fromRGB(175, 95, 245),
	Color3.fromRGB(255, 215, 70),
	Color3.fromRGB(80, 225, 200),
}
local AQUARIUM_COLOR = Color3.fromRGB(80, 220, 255)
local CAVIAR_COLOR = Color3.fromRGB(255, 120, 60)
local SAFE_COLOR = Color3.fromRGB(70, 255, 170)

local CANYON_HALF_WIDTH = 135
local CANYON_END_Z = 330

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
			else Color3.fromRGB(225, 245, 255)
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(10, 40, 70)
		label.RichText = true
		label.Size = UDim2.fromScale(1, 0.4)
		label.Position = if name == "Title" then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 0.6)
		label.Parent = gui
	end
	gui.Parent = parent
	World.setBillboard(gui, text)
	return gui
end

-- Big text painted on the top face of a part (floor decals, signs).
local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.2
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(10, 50, 60)
	label.Parent = gui
	gui.Parent = target
end

local function bubbles(parent: BasePart, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Rate = rate
	e.Lifetime = NumberRange.new(4, 7)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(15, 15)
	e.Size = NumberSequence.new(0.3, 0.6)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255))
	e.LightEmission = 0.4
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
end

local function sparkles(parent: BasePart, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 6
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.25, 0)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Parent = parent
end

export type CreatureOptions = { color: Color3?, variant: string?, size: number? }

-- Creature model: elongated body (front = -Z), tail, eyes, optional variant look.
function World.makeCreature(def: Creatures.CreatureDef, opts: CreatureOptions?): Model
	local options: CreatureOptions = opts or {}
	local model = Instance.new("Model")
	model.Name = def.name
	local s = options.size or def.size
	local variant = options.variant or "Normal"
	local color = options.color or def.color
	if variant == "Golden" then
		color = Variants.get("Golden").color
	end

	local body = part({
		Name = "Body",
		Size = Vector3.new(s, s * 0.8, s * 1.6),
		Color = color,
		Material = if variant == "Golden" then Enum.Material.Foil else Enum.Material.SmoothPlastic,
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
	tail.Color = if variant == "Rainbow" then Color3.fromRGB(110, 220, 255) else color
	tail.CFrame = body.CFrame * CFrame.new(0, 0, s * 0.95)
	tail.Parent = model

	local fin = Instance.new("WedgePart")
	fin.Name = "Fin"
	fin.Anchored = true
	fin.CanCollide = false
	fin.CanQuery = false
	fin.Size = Vector3.new(0.25, s * 0.45, s * 0.6)
	fin.Color = if variant == "Rainbow"
		then Color3.fromRGB(255, 230, 90)
		else color:Lerp(Color3.new(1, 1, 1), 0.25)
	fin.CFrame = body.CFrame * CFrame.new(0, s * 0.5, s * 0.1)
	fin.Parent = model

	for _, side in { -1, 1 } do
		local white = part({
			Name = "EyeWhite",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * math.max(0.4, s * 0.26),
			Color = Color3.new(1, 1, 1),
			CanCollide = false,
			CanQuery = false,
		})
		white.CFrame = body.CFrame * CFrame.new(side * s * 0.3, s * 0.15, -s * 0.58)
		white.Parent = model
		local pupil = part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * math.max(0.25, s * 0.14),
			Color = Color3.new(0.05, 0.05, 0.08),
			CanCollide = false,
			CanQuery = false,
		})
		pupil.CFrame = body.CFrame * CFrame.new(side * s * 0.33, s * 0.16, -s * 0.68)
		pupil.Parent = model
	end

	if variant == "Rainbow" then
		local gradientColors = { CORAL[1], CORAL[2], CORAL[4], CORAL[5], CORAL[3] }
		body.Color = gradientColors[1]
		body.Material = Enum.Material.Neon
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.6
		highlight.FillColor = Color3.fromRGB(255, 120, 230)
		highlight.OutlineColor = Color3.fromRGB(120, 230, 255)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		sparkles(body, Color3.fromRGB(255, 160, 240))
	elseif variant == "Golden" then
		sparkles(body, Color3.fromRGB(255, 225, 120))
	end

	model.PrimaryPart = body
	return model
end

-- Build ----------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 12.5
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(120, 165, 190)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 195, 215)
	Lighting.EnvironmentDiffuseScale = 0.5
	for _, name in { "UnderwaterAtmosphere", "UnderwaterTint", "UnderwaterBloom", "UnderwaterRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "UnderwaterAtmosphere"
	atmosphere.Density = 0.33
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(110, 205, 235)
	atmosphere.Decay = Color3.fromRGB(50, 140, 190)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "UnderwaterTint"
	tint.TintColor = Color3.fromRGB(225, 248, 255)
	tint.Saturation = 0.3
	tint.Contrast = 0.08
	tint.Brightness = 0.03
	tint.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "UnderwaterBloom"
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "UnderwaterRays"
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

local function coralCluster(parent: Instance, pos: Vector3, rng: Random, scale: number)
	for _ = 1, rng:NextInteger(2, 4) do
		local color = CORAL[rng:NextInteger(1, #CORAL)]
		local offset = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)) * scale
		if rng:NextNumber() < 0.5 then
			local h = rng:NextNumber(2, 5) * scale
			part({
				Name = "CoralStalk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(h, 0.8 * scale, 0.8 * scale),
				CFrame = CFrame.new(pos + offset + Vector3.new(0, h / 2, 0)) * CFrame.Angles(
					0,
					rng:NextNumber(0, 6.28),
					math.rad(90 + rng:NextNumber(-20, 20))
				),
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				Parent = parent,
			})
			part({
				Name = "CoralTip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.3 * scale,
				Position = pos + offset + Vector3.new(0, h, 0),
				Color = color:Lerp(Color3.new(1, 1, 1), 0.2),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				Parent = parent,
			})
		else
			local d = rng:NextNumber(2, 4) * scale
			part({
				Name = "CoralBrain",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * d,
				Position = pos + offset + Vector3.new(0, d * 0.3, 0),
				Color = color,
				Material = Enum.Material.Pebble,
				CanCollide = false,
				CanQuery = false,
				Parent = parent,
			})
		end
	end
end

local function kelp(parent: Instance, pos: Vector3, rng: Random)
	local h = rng:NextNumber(8, 20)
	local k = part({
		Name = "Kelp",
		Size = Vector3.new(0.9, h, 0.3),
		Color = Color3.fromRGB(60, rng:NextInteger(170, 210), 90),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
	k.CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0))
		* CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 6.28), 0)
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
		Size = Vector3.new(700, 4, 700),
		Position = Vector3.new(0, -2, 90),
		Color = SAND,
		Material = Enum.Material.Sand,
		Parent = root,
	})
	-- Slightly different sand inside the canyon so the heist field reads as its own space.
	part({
		Name = "CanyonFloor",
		Size = Vector3.new(CANYON_HALF_WIDTH * 2, 0.1, CANYON_END_Z - Config.ESCAPE_Z),
		Position = Vector3.new(0, 0.05, (CANYON_END_Z + Config.ESCAPE_Z) / 2),
		Color = CANYON_SAND,
		Material = Enum.Material.Sand,
		CanQuery = false,
		Parent = root,
	})
	-- Main path from spawn to the safe zone.
	part({
		Name = "HubPath",
		Size = Vector3.new(14, 0.12, 60),
		Position = Vector3.new(0, 0.06, 12),
		Color = PATH,
		Material = Enum.Material.Pavement,
		CanQuery = false,
		Parent = root,
	})

	part({
		Name = "WaterSurface",
		Size = Vector3.new(2000, 1, 2000),
		Position = Vector3.new(0, 90, 90),
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
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
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = Vector3.new(0.3, 12, 12)
	spawn.CFrame = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	spawn.Color = Color3.fromRGB(150, 215, 230)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
	World.spawnCFrame = CFrame.lookAt(Vector3.new(0, 4, 0), Vector3.new(0, 4, 50))
end

local function buildCanyon()
	local rng = Random.new(7)
	local folder = Instance.new("Folder")
	folder.Name = "Canyon"
	folder.Parent = root

	-- Side walls: chunky layered rocks topped with coral.
	for _, side in { -1, 1 } do
		local z = Config.ESCAPE_Z
		while z < CANYON_END_Z + 10 do
			local w = rng:NextNumber(16, 24)
			local h = rng:NextNumber(26, 40)
			local x = side * (CANYON_HALF_WIDTH + rng:NextNumber(4, 9))
			part({
				Name = "Wall",
				Size = Vector3.new(18, h, w),
				CFrame = CFrame.new(x, h / 2 - 1, z + w / 2)
					* CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0),
				Color = ROCK[rng:NextInteger(1, #ROCK)],
				Material = Enum.Material.Slate,
				Parent = folder,
			})
			coralCluster(folder, Vector3.new(x - side * 7, 0, z + w / 2), rng, 1)
			if rng:NextNumber() < 0.5 then
				coralCluster(folder, Vector3.new(x, h - 1, z + w / 2), rng, 1.5)
			end
			z += w * 0.8
		end
	end
	-- Back wall.
	part({
		Name = "BackWall",
		Size = Vector3.new(CANYON_HALF_WIDTH * 2 + 40, 40, 20),
		Position = Vector3.new(0, 19, CANYON_END_Z + 12),
		Color = ROCK[2],
		Material = Enum.Material.Slate,
		Parent = folder,
	})

	-- Canyon floor decoration (non-colliding — the design says "no obstacles").
	for _ = 1, 55 do
		local p = Vector3.new(
			rng:NextNumber(-CANYON_HALF_WIDTH + 10, CANYON_HALF_WIDTH - 10),
			0,
			rng:NextNumber(Config.ESCAPE_Z + 15, CANYON_END_Z - 5)
		)
		if rng:NextNumber() < 0.55 then
			kelp(folder, p, rng)
		else
			coralCluster(folder, p, rng, rng:NextNumber(0.6, 1.1))
		end
	end
	for _ = 1, 10 do
		local vent = part({
			Name = "BubbleVent",
			Size = Vector3.new(2, 0.4, 2),
			Position = Vector3.new(
				rng:NextNumber(-120, 120),
				0.2,
				rng:NextNumber(Config.ESCAPE_Z + 20, CANYON_END_Z - 10)
			),
			Color = Color3.fromRGB(140, 125, 110),
			CanCollide = false,
			CanQuery = false,
			Parent = folder,
		})
		bubbles(vent, 5)
	end

	-- Fake light shafts from the surface.
	for _ = 1, 14 do
		local shaft = part({
			Name = "LightShaft",
			Size = Vector3.new(rng:NextNumber(6, 12), 90, 0.2),
			Color = Color3.fromRGB(255, 250, 210),
			Material = Enum.Material.Neon,
			Transparency = 0.96,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = folder,
		})
		shaft.CFrame = CFrame.new(rng:NextNumber(-200, 200), 45, rng:NextNumber(-120, 300))
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(8, 18)))
	end
end

local function buildHubDecor()
	local rng = Random.new(42)
	local folder = Instance.new("Folder")
	folder.Name = "HubDecor"
	folder.Parent = root
	for _ = 1, 45 do
		local x = rng:NextNumber(-300, 300)
		local z = rng:NextNumber(-200, 40)
		-- keep plots, spawn and the path clear
		if (z < -30 and z > -90 and math.abs(x) < 160) or (math.abs(x) < 25 and z > -20) then
			continue
		end
		local p = Vector3.new(x, 0, z)
		if rng:NextNumber() < 0.5 then
			kelp(folder, p, rng)
		else
			coralCluster(folder, p, rng, rng:NextNumber(0.8, 1.4))
		end
	end
	for _ = 1, 6 do
		local vent = part({
			Name = "BubbleVent",
			Size = Vector3.new(2, 0.4, 2),
			Position = Vector3.new(rng:NextNumber(-250, 250), 0.2, rng:NextNumber(-180, 30)),
			Color = Color3.fromRGB(140, 125, 110),
			CanCollide = false,
			CanQuery = false,
			Parent = folder,
		})
		bubbles(vent, 4)
	end

	-- Archway sign over the path into the canyon.
	for _, side in { -1, 1 } do
		part({
			Name = "ArchPillar",
			Size = Vector3.new(3, 30, 3),
			Position = Vector3.new(side * 16, 15, Config.ESCAPE_Z - 8),
			Color = ROCK[1],
			Material = Enum.Material.Slate,
			Parent = folder,
		})
	end
	local beam = part({
		Name = "ArchSign",
		Size = Vector3.new(36, 5, 1),
		Position = Vector3.new(0, 28, Config.ESCAPE_Z - 8),
		Color = Color3.fromRGB(255, 190, 70),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	-- Front faces -Z (toward the hub), Back faces the canyon.
	surfaceText(beam, Enum.NormalId.Front, "🥚 HEIST CANYON", Color3.new(1, 1, 1))
	surfaceText(beam, Enum.NormalId.Back, "🏠 HOME", Color3.new(1, 1, 1))
end

local function buildSafeZone()
	local line = part({
		Name = "EscapeLine",
		Size = Vector3.new(CANYON_HALF_WIDTH * 2, 0.3, 3),
		Position = Vector3.new(0, 0.15, Config.ESCAPE_Z),
		Color = SAFE_COLOR,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
		Parent = root,
	})
	line:SetAttribute("SafeLine", true)
	-- Painted lettering on the sea floor (reads correctly when walking into the canyon).
	for _, x in { -80, 0, 80 } do
		local plate = part({
			Name = "SafeZoneText",
			Size = Vector3.new(44, 0.12, 9),
			Position = Vector3.new(x, 0.12, Config.ESCAPE_Z - 7),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = root,
		})
		surfaceText(plate, Enum.NormalId.Top, "SAFE ZONE", SAFE_COLOR)
	end
end

-- Nest positions for each tier (later tiers further down the canyon).
function World.nestPosition(tier: number): Vector3
	local row = (tier - 1) // 5
	local col = (tier - 1) % 5
	return Vector3.new(-100 + col * 50, 0, 110 + row * 45 + (if col % 2 == 1 then 15 else 0))
end

function World.setEggKind(nest: Nest, kind: Types.EggKind)
	nest.kind = kind
	nest.egg.Color = if kind == "Aquarium" then AQUARIUM_COLOR else CAVIAR_COLOR
	local light = nest.egg:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = nest.egg.Color
	end
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

function World.setAsleep(nest: Nest, asleep: boolean)
	if nest.asleep == asleep then
		return
	end
	nest.asleep = asleep
	World.setBillboard(
		nest.sleepGui,
		if asleep
			then `<b>💤 {nest.def.name}</b>\nasleep — sneak in!`
			else `<b>{nest.def.name}</b>\n{string.rep("⭐", nest.def.stars)}`
	)
	-- Sleeping creatures sink and roll onto their side.
	nest.creature:PivotTo(
		if asleep
			then nest.creaturePivot * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(70))
			else nest.creaturePivot
	)
end

local function buildNest(def: Creatures.CreatureDef)
	local pos = World.nestPosition(def.tier)
	local folder = Instance.new("Model")
	folder.Name = `Nest_{def.tier}`
	folder.Parent = root

	part({
		Name = "NestBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 11, 11),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	-- Ring of rocks around the nest.
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		part({
			Name = "NestRock",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.2,
			Position = pos + Vector3.new(math.cos(a) * 5.4, 0.9, math.sin(a) * 5.4),
			Color = ROCK[(i % #ROCK) + 1],
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = folder,
		})
	end
	-- Tier sign post.
	local post = part({
		Name = "TierSign",
		Size = Vector3.new(6, 3, 0.6),
		Position = pos + Vector3.new(0, 6, 7),
		Color = Color3.fromRGB(255, 190, 70),
		Parent = folder,
	})
	surfaceText(post, Enum.NormalId.Front, `TIER {def.tier}`, Color3.new(1, 1, 1))

	local egg = part({
		Name = "Egg",
		Size = Vector3.new(2.6, 3.3, 2.6),
		Position = pos + Vector3.new(0, 2.8, 0),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = folder,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 2
	light.Parent = egg
	sparkles(egg, Color3.fromRGB(255, 255, 220))

	local label = billboard(egg, "", Vector3.new(0, 6, 0), UDim2.fromScale(13, 3.8), 110)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal egg"
	prompt.ObjectText = `Tier {def.tier} · {def.name}`
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = egg

	local creature = World.makeCreature(def)
	local pivot =
		CFrame.lookAt(pos + Vector3.new(9, def.size * 0.5 + 1, 2), pos + Vector3.new(0, 2, -10))
	creature:PivotTo(pivot)
	creature.Parent = folder
	local sleepGui = billboard(
		creature.PrimaryPart :: BasePart,
		`<b>{def.name}</b>\n{string.rep("⭐", def.stars)}`,
		Vector3.new(0, def.size * 0.6 + 2.2, 0),
		UDim2.fromScale(7, 2.2),
		70
	)
	sleepGui.Name = "NameGui"

	local nest: Nest = {
		tier = def.tier,
		def = def,
		egg = egg,
		prompt = prompt,
		label = label,
		creature = creature,
		creaturePivot = pivot,
		sleepGui = sleepGui,
		kind = "Aquarium",
		asleep = false,
	}
	World.setEggKind(nest, if math.random() < 0.5 then "Aquarium" else "Caviar")
	World.nests[def.tier] = nest
end

local PLOT_COUNT = 8
local PLOT_COLORS = {
	Color3.fromRGB(110, 200, 230),
	Color3.fromRGB(150, 220, 160),
	Color3.fromRGB(240, 180, 210),
	Color3.fromRGB(250, 210, 140),
	Color3.fromRGB(190, 170, 240),
	Color3.fromRGB(140, 220, 210),
	Color3.fromRGB(250, 170, 150),
	Color3.fromRGB(180, 210, 250),
}

local function buildPlot(index: number)
	local x = -126 + (index - 1) * 36
	local z = -60
	local model = Instance.new("Model")
	model.Name = `Plot{index}`
	model.Parent = root

	part({
		Name = "Base",
		Size = Vector3.new(32, 0.6, 28),
		Position = Vector3.new(x, 0.3, z),
		Color = PLOT_COLORS[index],
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	part({
		Name = "Border",
		Size = Vector3.new(33, 0.4, 29),
		Position = Vector3.new(x, 0.15, z),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local tank = part({
		Name = "Tank",
		Size = Vector3.new(24, 10, 6),
		Position = Vector3.new(x, 5.8, z - 9),
		Color = Color3.fromRGB(170, 235, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.7,
		Parent = model,
	})
	part({
		Name = "TankSand",
		Size = Vector3.new(23.6, 0.6, 5.6),
		Position = Vector3.new(x, 1.3, z - 9),
		Color = SAND,
		Material = Enum.Material.Sand,
		CanCollide = false,
		Parent = model,
	})
	part({
		Name = "TankBase",
		Size = Vector3.new(25, 0.8, 7),
		Position = Vector3.new(x, 0.8, z - 9),
		Color = Color3.fromRGB(60, 70, 90),
		Parent = model,
	})
	local rng = Random.new(index)
	for i = 1, 3 do
		coralCluster(model, Vector3.new(x - 10 + i * 5, 1.6, z - 9), rng, 0.45)
	end
	local sign = billboard(tank, "Empty plot", Vector3.new(0, 8, 0), UDim2.fromScale(18, 3.2), 160)

	part({
		Name = "Counter",
		Size = Vector3.new(14, 3, 4),
		Position = Vector3.new(x + 7, 2.1, z + 6),
		Color = Color3.fromRGB(245, 245, 250),
		Material = Enum.Material.Marble,
		Parent = model,
	})
	local kitchenSign = part({
		Name = "KitchenSign",
		Size = Vector3.new(8, 2, 0.4),
		Position = Vector3.new(x + 7, 6, z + 3.9),
		Color = Color3.fromRGB(255, 120, 80),
		Parent = model,
	})
	surfaceText(kitchenSign, Enum.NormalId.Back, "🍽 KITCHEN", Color3.new(1, 1, 1))

	local pad = part({
		Name = "CollectPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 6, 6),
		CFrame = CFrame.new(x - 9, 0.75, z + 6) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 210, 60),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	sparkles(pad, Color3.fromRGB(255, 230, 120))
	billboard(pad, "💰 COLLECT", Vector3.new(0, 3, 0), UDim2.fromScale(7, 1.6), 60)
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
		counterTop = Vector3.new(x + 7, 3.6, z + 6),
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
		local model = World.makeCreature(def, {
			variant = pet.variant,
			size = math.min(def.size, 2.6) * 0.8,
		})
		model.Name = pet.name
		local cf: CFrame
		if pet.kind == "Aquarium" then
			local col = aquariumIndex % 5
			local row = aquariumIndex // 5
			aquariumIndex += 1
			local p = plot.tankCenter + Vector3.new(-8 + col * 4, -1.5 + row * 3.5, 0)
			cf = CFrame.lookAt(p, p + Vector3.new(if row % 2 == 0 then 1 else -1, 0, 0))
		else
			local p = plot.counterTop + Vector3.new(-5.5 + kitchenIndex * 2.2, 1, 0)
			kitchenIndex += 1
			cf = CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
		end
		model:PivotTo(cf)
		local rarityColor = Rarities[pet.rarity].color:ToHex()
		local variant = Variants.get(pet.variant)
		billboard(
			model.PrimaryPart :: BasePart,
			string.format(
				"<font color='#%s'>%s</font>%s",
				if variant.name ~= "Normal" then variant.color:ToHex() else rarityColor,
				pet.name,
				if pet.feedReadyAt > 0 then "\n🍳 cooking" else ""
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
			plot.model:SetAttribute("OwnerUserId", player.UserId)
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
		plot.model:SetAttribute("OwnerUserId", nil)
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
	buildCanyon()
	buildHubDecor()
	buildSafeZone()
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

	-- Spawn facing the canyon so new players see where to go.
	local function faceCanyon(character: Model)
		character:WaitForChild("HumanoidRootPart", 5)
		task.wait()
		character:PivotTo(World.spawnCFrame)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(faceCanyon)
		if player.Character then
			task.spawn(faceCanyon, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return World
