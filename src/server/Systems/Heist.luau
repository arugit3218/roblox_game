--!strict
-- Heist: steal one egg (type shown up-front), get chased by the nest's creature,
-- cross the safe line to keep it. Caught = egg returns, you respawn at the hub.
-- Fully server-authoritative: the server validates the steal, moves the chaser,
-- and decides success from the character's server-side position.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creatures = require(Shared.GameData.Creatures)
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Lib.Net)
local Events = require(script.Parent.Events)
local Idle = require(script.Parent.Idle)
local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)

type Chase = {
	player: Player,
	nest: World.Nest,
	kind: Types.EggKind,
	chaser: Model,
	carried: BasePart,
	started: number,
	connection: RBXScriptConnection?,
	reactionDelay: number,
	luck: number,
	rewardMult: number,
	lastSamplePos: Vector3,
	lastSampleTime: number,
}

local Heist = {}
local chases: { [Player]: Chase } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return root
		end
	end
	return nil
end

local function endChase(chase: Chase, success: boolean, reason: string?)
	if chases[chase.player] ~= chase then
		return
	end
	chases[chase.player] = nil
	if chase.connection then
		chase.connection:Disconnect()
	end
	chase.chaser:Destroy()
	chase.carried:Destroy()
	PlayerData.setCarrying(chase.player, nil)

	local player = chase.player
	local profile = PlayerData.get(player)
	if not player.Parent or not profile then
		return
	end

	if success then
		local def = chase.nest.def
		local reward = def.reward * chase.rewardMult
		Idle.addEgg(profile, def.tier, chase.kind, chase.luck)
		profile.coins += reward
		profile.heists += 1
		profile.highestTier = math.max(profile.highestTier, def.tier)
		Net.notify(
			player,
			`🥚 Egg secured! {chase.kind} Egg from the {def.name} is incubating. +{Format.number(
				reward
			)} coins`,
			"success"
		)
		PlayerData.changed(player)
	else
		Net.notify(player, reason or "😱 Caught! The egg went back to the nest.", "error")
		local root = rootOf(player)
		if root then
			(player.Character :: Model):PivotTo(World.spawnCFrame)
		end
	end
end

local function attachCarriedEgg(player: Player, kind: Types.EggKind, root: BasePart): BasePart
	local egg = Instance.new("Part")
	egg.Name = "CarriedEgg"
	egg.Size = Vector3.new(1.6, 2, 1.6)
	egg.CanCollide = false
	egg.CanQuery = false
	egg.Massless = true
	egg.Color = if kind == "Aquarium"
		then Color3.fromRGB(80, 220, 255)
		else Color3.fromRGB(255, 120, 60)
	egg.Material = Enum.Material.Neon
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	egg.CFrame = root.CFrame * CFrame.new(0, 3.6, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = egg
	weld.Parent = egg
	egg.Parent = player.Character
	return egg
end

local function onStealTriggered(player: Player, nest: World.Nest)
	local profile = PlayerData.get(player)
	local root = rootOf(player)
	if not profile or not root then
		return
	end
	local def = nest.def
	if chases[player] then
		return
	end
	if def.tier > Config.MAX_TIER then
		return
	end
	if def.tier > profile.highestTier + 1 then
		Net.notify(player, `🔒 Steal a Tier {def.tier - 1} egg first!`, "error")
		return
	end
	if Idle.incubatorFull(profile) then
		Net.notify(
			player,
			`Your incubator is full ({Config.INCUBATOR_SLOTS} eggs). Wait for some to hatch!`,
			"error"
		)
		return
	end
	if (root.Position - nest.egg.Position).Magnitude > Config.STEAL_REACH then
		return
	end

	local kind = nest.kind
	local chaser = World.makeCreature(def)
	chaser:PivotTo((nest.creature :: Model):GetPivot())
	chaser.Parent = workspace

	local now = os.clock()
	local wasAsleep = nest.asleep
	World.setAsleep(nest, false) -- the thief wakes it up
	local chase: Chase = {
		player = player,
		nest = nest,
		kind = kind,
		chaser = chaser,
		carried = attachCarriedEgg(player, kind, root),
		started = now,
		connection = nil,
		reactionDelay = Config.CHASE_REACTION_DELAY
			+ (if wasAsleep then Config.SLEEP_BONUS_DELAY else 0),
		luck = Events.luck(),
		rewardMult = Events.rewardMultiplier(),
		lastSamplePos = root.Position,
		lastSampleTime = now,
	}
	chases[player] = chase
	PlayerData.setCarrying(player, { tier = def.tier, kind = kind })
	Net.notify(
		player,
		if wasAsleep
			then `😴 Sneaky! The {def.name} was asleep — head start! RUN!`
			else `🏃 You grabbed the {kind} Egg! Get back to the SAFE ZONE!`,
		"warn"
	)

	local speed = Creatures.speedOf(def)
	local catchDistance = Config.CATCH_DISTANCE + def.size * 0.5
	chase.connection = RunService.Heartbeat:Connect(function(dt)
		local r = rootOf(player)
		if not r then
			endChase(chase, false, "😵 You lost the egg!")
			return
		end
		local t = os.clock()
		local target = r.Position

		-- Movement sanity check EVERY frame, before the escape check, so a teleport
		-- across the safe line can never count. Full 3D distance (no flying over the chaser),
		-- generous margin for lag/jumps; the sample window advances every 0.5s.
		local moved = (target - chase.lastSamplePos).Magnitude
		local allowed = Economy.walkSpeed(profile.speedLevel) * (t - chase.lastSampleTime) * 1.75
			+ 12
		if moved > allowed or target.Y > Config.HEIST_MAX_Y then
			endChase(chase, false, "⚠️ Heist failed (moved too fast).")
			return
		end
		if t - chase.lastSampleTime >= 0.5 then
			chase.lastSamplePos = target
			chase.lastSampleTime = t
		end

		-- Escaped?
		if target.Z <= Config.ESCAPE_Z then
			endChase(chase, true)
			return
		end

		if t - chase.started > Config.CHASE_TIMEOUT then
			endChase(chase, false, "⏱ The creature reclaimed its egg!")
			return
		end
		if t - chase.started < chase.reactionDelay or speed <= 0 then
			return
		end

		local current = chaser:GetPivot().Position
		local goal = Vector3.new(target.X, math.max(target.Y, def.size * 0.5 + 1), target.Z)
		local delta = goal - current
		local step = math.min(speed * dt, delta.Magnitude)
		local nextPos = if delta.Magnitude > 0.01 then current + delta.Unit * step else current
		chaser:PivotTo(CFrame.lookAt(nextPos, goal))
		if (goal - nextPos).Magnitude <= catchDistance then
			endChase(chase, false)
		end
	end)
end

local function rerollEggs()
	for _, nest in World.nests do
		World.setEggKind(nest, if math.random() < 0.5 then "Aquarium" else "Caviar")
	end
end

-- Each nest's guardian naps on its own random rhythm.
local function sleepCycle(nest: World.Nest)
	local rng = Random.new()
	task.wait(rng:NextNumber(0, 8))
	while true do
		World.setAsleep(nest, true)
		task.wait(rng:NextNumber(Config.SLEEP_SECONDS[1], Config.SLEEP_SECONDS[2]))
		World.setAsleep(nest, false)
		task.wait(rng:NextNumber(Config.AWAKE_SECONDS[1], Config.AWAKE_SECONDS[2]))
	end
end

function Heist.start()
	for _, nest in World.nests do
		task.spawn(sleepCycle, nest)
	end
	for _, nest in World.nests do
		nest.prompt.Triggered:Connect(function(player)
			onStealTriggered(player, nest)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		local chase = chases[player]
		if chase then
			endChase(chase, false)
		end
	end)
	while true do
		task.wait(Config.EGG_REROLL_SECONDS)
		rerollEggs()
	end
end

return Heist
