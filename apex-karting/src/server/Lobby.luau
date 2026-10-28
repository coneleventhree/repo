--!strict
-- The lobby's requests (the menu on every public server): PRACTICE on a
-- track, RACE (join / leave the quick-race queue), CREATE ROOM, JOIN ROOM;
-- and LOBBY from any other server. Problems go back to the player as a
-- "MenuError" RaceEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackData = require(Shared:WaitForChild("TrackData"))
local Session = require(script.Parent:WaitForChild("Session"))
local SharedStore = require(script.Parent:WaitForChild("SharedStore"))
local Matchmaker = require(script.Parent:WaitForChild("Matchmaker"))
local Rooms = require(script.Parent:WaitForChild("Rooms"))

local Lobby = {}

local L = Config.Lobby
local busy: { [Player]: boolean } = {}
local getMode: () -> string = function()
	return "lobby"
end
local raceEvent: RemoteEvent

local function say(p: Player, message: string)
	raceEvent:FireClient(p, "MenuError", { message = message })
end

-- one request at a time per player (double taps, impatient clicks)
local function once(p: Player, fn: () -> ())
	if busy[p] or Session.busy(p) then
		return
	end
	busy[p] = true
	task.spawn(function()
		local ok, err = pcall(fn :: any)
		if not ok then
			warn("[Lobby]", err)
			say(p, "Something went wrong. Try again.")
		end
		busy[p] = nil
	end)
end

local function onRequest(p: Player, kind: unknown, arg: unknown)
	local mode = getMode()
	if kind == "ToLobby" then
		if mode ~= "lobby" then
			once(p, function()
				Session.toLobby(p)
			end)
		end
		return
	end
	if mode ~= "lobby" then
		return
	end
	if kind == "Practice" then
		if type(arg) ~= "string" or not TrackData.Tracks[arg] then
			return
		end
		Matchmaker.leave(p)
		once(p, function()
			local role: Session.Role = { mode = "practice", track = arg }
			local code = Session.reserve(role)
			if not code then
				say(p, "Couldn't start practice. Try again.")
				return
			end
			Session.send({ p }, role, code)
		end)
	elseif kind == "Queue" then
		if arg == false then
			Matchmaker.leave(p)
		elseif not Session.busy(p) then
			Matchmaker.join(p)
		end
	elseif kind == "CreateRoom" then
		Matchmaker.leave(p)
		once(p, function()
			local code, err = Rooms.create(p)
			if not code then
				say(p, err or "Couldn't make a room. Try again.")
			end
		end)
	elseif kind == "JoinRoom" then
		Matchmaker.leave(p)
		once(p, function()
			local err = Rooms.join(p, arg)
			if err then
				say(p, err)
			end
		end)
	end
end

-- `mode` tells which kind of server this is right now (RaceManager.mode).
function Lobby.init(remotes: Folder, mode: () -> string)
	getMode = mode
	raceEvent = remotes:WaitForChild("RaceEvent") :: RemoteEvent
	local request = remotes:WaitForChild("Request") :: RemoteEvent
	request.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(p)
		busy[p] = nil
	end)

	-- shared maps: MemoryStore when published, tables in Studio
	local studio = Session.studio()
	local tickets, locks, rooms
	if studio then
		tickets = SharedStore.localMap(Session.clock)
		locks = SharedStore.localMap(Session.clock)
		rooms = SharedStore.localMap(Session.clock)
	else
		tickets = SharedStore.memory("A1Queue")
		locks = SharedStore.memory("A1Locks")
		rooms = SharedStore.memory("A1Rooms")
	end
	Matchmaker.init({
		tickets = tickets,
		locks = locks,
		reserve = function()
			return Session.reserve({ mode = "race" })
		end,
		send = function(list: { Player }, code: string)
			Session.send(list, { mode = "race" }, code)
		end,
		clock = Session.clock,
		minPlayers = if studio and L.StudioSolo then 1 else L.QueueMin,
	})
	Rooms.init({
		rooms = rooms,
		reserve = Session.reserve,
		send = Session.send,
	})
end

-- The server stopped being a lobby (Studio): nobody waits for a race here.
function Lobby.closed()
	for _, p in Players:GetPlayers() do
		Matchmaker.leave(p)
	end
end

return Lobby
