--!strict
-- Latest server snapshot for the local player (read-only mirror; the server owns truth).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local State = {}
State.snapshot = nil :: Types.Snapshot?

local listeners: { (Types.Snapshot) -> () } = {}

function State.onChanged(cb: (Types.Snapshot) -> ())
	table.insert(listeners, cb)
	if State.snapshot then
		task.spawn(cb, State.snapshot)
	end
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
local requestRemote = remotes:WaitForChild("Request") :: RemoteEvent

stateRemote.OnClientEvent:Connect(function(snapshot: Types.Snapshot)
	State.snapshot = snapshot
	for _, cb in listeners do
		task.spawn(cb, snapshot)
	end
end)

function State.request(action: string, ...: any)
	requestRemote:FireServer(action, ...)
end

-- Ask for a snapshot in case the first one arrived before we were listening.
task.defer(State.request, "Sync")

function State.now(): number
	return workspace:GetServerTimeNow()
end

return State
