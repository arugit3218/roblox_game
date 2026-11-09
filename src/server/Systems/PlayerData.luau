--!strict
-- Owns player profiles: session-locked load, autosave, release on leave/shutdown,
-- and pushing state snapshots to the owning client. Gameplay code mutates the
-- in-memory profile from PlayerData.get() and then calls PlayerData.changed().

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Lib.Net)

type Profile = Types.PlayerProfile
type Session = {
	profile: Profile,
	saving: boolean, -- false = temporary profile (Studio without API access)
	carrying: Types.Carrying?,
	dirty: boolean,
	busy: boolean, -- a DataStore write is in flight (saves are serialized)
	releasing: boolean, -- final save started; autosaves must not run
	released: boolean, -- final save finished (lock cleared or abandoned)
}
type Stored = { data: any, lock: { jobId: string, time: number }? }

local CURRENT_VERSION = 1
local STORE_NAME = "PlayerData_v1"

local PlayerData = {}

local sessions: { [Player]: Session } = {}
local releasingUsers: { [number]: boolean } = {} -- UserIds whose final save is in flight
local loadingCount = 0
local shuttingDown = false
local loadedCallbacks: { (Player, Profile) -> () } = {}
local changedCallbacks: { (Player, Profile) -> () } = {}

local function defaultProfile(): Profile
	return {
		version = CURRENT_VERSION,
		coins = 0,
		gems = 0,
		highestTier = 0,
		heists = 0,
		speedLevel = 0,
		trails = {},
		equippedTrail = "",
		eggs = {},
		pets = {},
		aquarium = { bank = 0, lastSettle = os.time() },
		caviar = {},
		orders = {},
		dex = {},
		nextId = 1,
	}
end

local MIGRATIONS: { [number]: (any) -> any } = {}

local function migrate(data: any): Profile
	-- Fill any missing top-level fields from defaults (forward-compatible).
	local defaults = defaultProfile() :: any
	for k, v in defaults do
		if data[k] == nil then
			data[k] = v
		end
	end
	while data.version < CURRENT_VERSION do
		local step = MIGRATIONS[data.version]
		if not step then
			error(`missing migration from v{data.version}`)
		end
		data = step(data)
		data.version += 1
	end
	return data :: Profile
end

local store: DataStore? = nil
local function getStore(): DataStore
	if not store then
		store = DataStoreService:GetDataStore(STORE_NAME)
	end
	return store :: DataStore
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function isStudioAccessError(err: string): boolean
	return RunService:IsStudio()
		and (
			string.find(err, "StudioAccessToApisNotAllowed", 1, true) ~= nil
			or string.find(err, "publish", 1, true) ~= nil
			or string.find(err, "403", 1, true) ~= nil
		)
end

-- Returns: profile (or nil), status "ok" | "locked" | "studio" | "error"
local function tryLoad(player: Player): (Profile?, string)
	local jobId = game.JobId
	local claimed = false
	local result: Profile? = nil
	local ok, err = pcall(function()
		getStore():UpdateAsync(keyFor(player), function(old: Stored?): Stored?
			local now = os.time()
			claimed = false
			if
				old
				and old.lock
				and old.lock.jobId ~= jobId
				and now - old.lock.time < Config.LOCK_STALE_SECONDS
			then
				return nil -- another server owns this profile; abort the write
			end
			local data = migrate(if old and old.data then old.data else defaultProfile())
			result = data
			claimed = true
			return { data = data, lock = { jobId = jobId, time = now } }
		end)
	end)
	if not ok then
		local msg = tostring(err)
		if isStudioAccessError(msg) then
			return nil, "studio"
		end
		warn(`[PlayerData] load failed for {player.Name}: {msg}`)
		return nil, "error"
	end
	if not claimed then
		return nil, "locked"
	end
	return result, "ok"
end

local function save(player: Player, session: Session, release: boolean): boolean
	if not session.saving or session.released or (not release and session.releasing) then
		return true
	end
	-- Serialize writes so a slow autosave can never land after the release.
	while session.busy do
		task.wait(0.1)
	end
	if session.released or (not release and session.releasing) then
		return true
	end
	session.busy = true
	local jobId = game.JobId
	local profile = session.profile
	local result = false
	for attempt = 1, 4 do
		local lostLock = false
		local ok, err = pcall(function()
			getStore():UpdateAsync(keyFor(player), function(old: Stored?): Stored?
				lostLock = false
				if not release and session.releasing then
					return nil -- release began while we waited; let it win
				end
				if old and old.lock and old.lock.jobId ~= jobId then
					lostLock = true
					return nil -- someone else owns it now; never overwrite their data
				end
				return {
					data = profile,
					lock = if release then nil else { jobId = jobId, time = os.time() },
				}
			end)
		end)
		if ok then
			if lostLock then
				-- Another server took over: stop this session so nothing is silently lost.
				warn(`[PlayerData] lost session lock for {player.Name}; ending session`)
				session.released = true
				if sessions[player] == session then
					sessions[player] = nil
					player:Kick("Your data was opened in another server. Please rejoin.")
				end
				result = false
			else
				if release then
					session.released = true
				end
				result = true
			end
			break
		end
		warn(`[PlayerData] save attempt {attempt} failed for {player.Name}: {err}`)
		if attempt < 4 then
			task.wait(math.min(2 ^ attempt, 8))
		end
	end
	session.busy = false
	return result
end

-- Final save + lock release. Safe to call from PlayerRemoving and BindToClose at once.
local function releaseSession(player: Player, session: Session)
	if session.releasing then
		while not session.released and session.busy do
			task.wait(0.1)
		end
		return
	end
	session.releasing = true
	local userId = player.UserId
	releasingUsers[userId] = true
	save(player, session, true)
	session.released = true
	releasingUsers[userId] = nil
end

local function buildSnapshot(session: Session): Types.Snapshot
	return { profile = session.profile, carrying = session.carrying, saving = session.saving }
end

local function flush(player: Player)
	local session = sessions[player]
	if not session or not session.dirty then
		return
	end
	session.dirty = false
	Net.sendState(player, buildSnapshot(session))
	for _, cb in changedCallbacks do
		task.spawn(cb, player, session.profile)
	end
end

local function loadPlayer(player: Player)
	-- If this player just left this server, wait for that final save first
	-- (otherwise we could load stale data and later overwrite the newer save).
	local waitUntil = os.clock() + 30
	while releasingUsers[player.UserId] and os.clock() < waitUntil do
		task.wait(0.2)
	end

	local profile: Profile? = nil
	local saving = true
	for attempt = 1, 6 do
		local loaded, status = tryLoad(player)
		if status == "ok" then
			profile = loaded
			break
		elseif status == "studio" then
			warn(
				"[PlayerData] DataStores unavailable in Studio (publish the place and enable "
					.. "'Studio Access to API Services'). Using a TEMPORARY profile that will not save."
			)
			profile = defaultProfile()
			saving = false
			break
		end
		if not player.Parent then
			return
		end
		task.wait(if status == "locked" then 3 else math.min(2 ^ attempt, 10))
	end

	if not profile then
		player:Kick("We couldn't load your data safely. Please rejoin in a minute.")
		return
	end

	local session: Session = {
		profile = profile,
		saving = saving,
		carrying = nil,
		dirty = true,
		busy = false,
		releasing = false,
		released = false,
	}

	if not player.Parent or shuttingDown then
		-- Left (or server closing) while loading: release the lock we just took.
		releaseSession(player, session)
		return
	end

	sessions[player] = session
	for _, cb in loadedCallbacks do
		task.spawn(cb, player, profile)
	end
	flush(player)

	-- Staggered autosave.
	task.spawn(function()
		task.wait(player.UserId % Config.AUTOSAVE_INTERVAL)
		while sessions[player] == session do
			save(player, session, false)
			task.wait(Config.AUTOSAVE_INTERVAL)
		end
	end)
end

local function onPlayerAdded(player: Player)
	loadingCount += 1
	local ok, err = pcall(loadPlayer, player)
	loadingCount -= 1
	if not ok then
		warn(`[PlayerData] load crashed for {player.Name}: {err}`)
		player:Kick("We couldn't load your data safely. Please rejoin in a minute.")
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	releaseSession(player, session)
	if sessions[player] == session then
		sessions[player] = nil
	end
end

-- Public API -----------------------------------------------------------------

function PlayerData.get(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function PlayerData.players(): { Player }
	local list = {}
	for player in sessions do
		table.insert(list, player)
	end
	return list
end

function PlayerData.changed(player: Player)
	local session = sessions[player]
	if not session or session.dirty then
		return
	end
	session.dirty = true
	task.defer(flush, player)
end

function PlayerData.setCarrying(player: Player, carrying: Types.Carrying?)
	local session = sessions[player]
	if session then
		session.carrying = carrying
		PlayerData.changed(player)
	end
end

function PlayerData.getCarrying(player: Player): Types.Carrying?
	local session = sessions[player]
	return if session then session.carrying else nil
end

function PlayerData.newId(profile: Profile): string
	local id = tostring(profile.nextId)
	profile.nextId += 1
	return id
end

function PlayerData.onLoaded(cb: (Player, Profile) -> ())
	table.insert(loadedCallbacks, cb)
end

function PlayerData.onChanged(cb: (Player, Profile) -> ())
	table.insert(changedCallbacks, cb)
end

function PlayerData.init()
	-- Client asks for a fresh snapshot once its UI is ready.
	Net.handle("Sync", 1, 2, function(player)
		local session = sessions[player]
		if session then
			Net.sendState(player, buildSnapshot(session))
		end
	end)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player, session in sessions do
			pending += 1
			task.spawn(function()
				releaseSession(player, session)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while (pending > 0 or loadingCount > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
