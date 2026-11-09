--!strict
-- Animated chevron arrows on the sea floor pointing at the current goal:
-- the next tier's nest, or the SAFE ZONE while carrying an egg. Client-only parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local State = require(script.Parent.Parent.Lib.State)

local Guide = {}

local CHEVRONS = 12
local SPACING = 5
local ARM = Vector3.new(0.6, 0.15, 2.6)
local TO_NEST = Color3.fromRGB(255, 80, 60)
local TO_SAFE = Color3.fromRGB(70, 255, 150)

type Chevron = { left: Part, right: Part }
local chevrons: { Chevron } = {}
local folder: Folder

local function makeArm(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = ARM
	p.Parent = folder
	return p
end

local function hideAll()
	for _, c in chevrons do
		c.left.Transparency = 1
		c.right.Transparency = 1
	end
end

local function goal(): Vector3?
	local snapshot = State.snapshot
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not snapshot or not root or not root:IsA("BasePart") then
		return nil
	end
	if snapshot.carrying then
		local x = math.clamp(root.Position.X, -110, 110)
		return Vector3.new(x, 0, Config.ESCAPE_Z - 10)
	end
	local profile = snapshot.profile
	if #profile.eggs >= Config.INCUBATOR_SLOTS then
		return nil
	end
	local tier = math.min(profile.highestTier + 1, Config.MAX_TIER)
	local world = workspace:FindFirstChild("World")
	local nest = world and world:FindFirstChild(`Nest_{tier}`)
	local egg = nest and nest:FindFirstChild("Egg")
	if egg and egg:IsA("BasePart") then
		return egg.Position
	end
	return nil
end

function Guide.init()
	folder = Instance.new("Folder")
	folder.Name = "GuideArrows"
	folder.Parent = workspace.CurrentCamera
	for _ = 1, CHEVRONS do
		table.insert(chevrons, { left = makeArm(), right = makeArm() })
	end
	hideAll()
end

function Guide.start()
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local target = goal()
		if not target or not root or not root:IsA("BasePart") then
			hideAll()
			return
		end
		local from = Vector3.new(root.Position.X, 0, root.Position.Z)
		local flat = Vector3.new(target.X, 0, target.Z) - from
		local distance = flat.Magnitude
		if distance < 9 then
			hideAll()
			return
		end
		local dir = flat.Unit
		local carrying = State.snapshot ~= nil and State.snapshot.carrying ~= nil
		local color = if carrying then TO_SAFE else TO_NEST
		local scroll = (os.clock() * 8) % SPACING
		for i, c in chevrons do
			local d = 4 + (i - 1) * SPACING + scroll
			if d > distance - 4 then
				c.left.Transparency = 1
				c.right.Transparency = 1
				continue
			end
			local pos = from + dir * d + Vector3.new(0, 0.35, 0)
			-- tip points along dir (lookAt's -Z); arms trail back at ±45°
			local base = CFrame.lookAt(pos, pos + dir)
			local fade = math.clamp((d - 4) / (CHEVRONS * SPACING), 0, 1)
			local transparency = 0.1 + fade * 0.7
			c.left.CFrame = base * CFrame.new(-0.85, 0, 0.85) * CFrame.Angles(0, math.rad(-45), 0)
			c.right.CFrame = base * CFrame.new(0.85, 0, 0.85) * CFrame.Angles(0, math.rad(45), 0)
			c.left.Color = color
			c.right.Color = color
			c.left.Transparency = transparency
			c.right.Transparency = transparency
		end
	end)
end

return Guide
