--!strict
-- Server-owned remotes. Clients only *request* actions through `Request`;
-- every handler receives raw (unknown) args and must validate them itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function makeEvent(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = folder
	return e
end

local Request = makeEvent("Request") -- client -> server: (action: string, ...args)
local State = makeEvent("State") -- server -> client: Snapshot
local Notify = makeEvent("Notify") -- server -> client: (text: string, kind: string)
local Hatched = makeEvent("Hatched") -- server -> client: (pet, isNewDex: boolean)
folder.Parent = ReplicatedStorage

type Handler = (player: Player, ...unknown) -> ()
type Route = { handler: Handler, rate: number, burst: number }

local routes: { [string]: Route } = {}
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

local function allow(player: Player, key: string, rate: number, burst: number): boolean
	local now = os.clock()
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[key]
	if not b then
		b = { tokens = burst, last = now }
		pb[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

Request.OnServerEvent:Connect(function(player: Player, action: unknown, ...: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local route = routes[action]
	if not route or not allow(player, action, route.rate, route.burst) then
		return
	end
	local ok, err = pcall(route.handler, player, ...)
	if not ok then
		warn(`[Net] {action} handler error for {player.Name}: {err}`)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

local Net = {}

function Net.handle(action: string, rate: number, burst: number, handler: Handler)
	assert(routes[action] == nil, `duplicate route {action}`)
	routes[action] = { handler = handler, rate = rate, burst = burst }
end

function Net.sendState(player: Player, snapshot: any)
	State:FireClient(player, snapshot)
end

function Net.notify(player: Player, text: string, kind: string?)
	Notify:FireClient(player, text, kind or "info")
end

function Net.hatched(player: Player, pet: any, isNew: boolean)
	Hatched:FireClient(player, pet, isNew)
end

function Net.notifyAll(text: string, kind: string?)
	Notify:FireAllClients(text, kind or "info")
end

-- Validators -----------------------------------------------------------------

function Net.isId(value: unknown): boolean
	return typeof(value) == "string" and #value > 0 and #value <= 40
end

return Net
