--!strict
-- What kind of server this is, and moving players between servers.
--
-- Every public server is a lobby. PRACTICE, RACE and PRIVATE ROOM reserve a
-- server of the same place (TeleportService:ReserveServerAsync), note what it
-- is for in a MemoryStore hash map under its PrivateServerId, and teleport the
-- players there with the same table as their teleport data. The reserved
-- server reads its role from that map when it starts (or from the first
-- player's teleport data if the map cannot be read). LOBBY sends a player to
-- any public server, which is a lobby.
--
-- Studio cannot teleport: there the one server switches to the new role in
-- place (Session.switchHere, set by init.server), with everyone in it.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackData = require(Shared:WaitForChild("TrackData"))

local Session = {}

export type Mode = "lobby" | "practice" | "race" | "room"
export type Role = { mode: Mode, track: string?, code: string?, host: number? }

local L = Config.Lobby
local MODES: { [string]: boolean } = { lobby = true, practice = true, race = true, room = true }

-- set by init.server
Session.switchHere = nil :: ((Role) -> ())? -- Studio: become `role` in place
Session.beforeLeave = nil :: ((Player) -> ())? -- save the player's data before a teleport
Session.notify = nil :: ((Player, string, { [string]: any }) -> ())? -- a RaceEvent to one client

local pending: { [Player]: boolean } = {} -- teleport under way

-- A role from teleport data or the map (nil if it is not one).
function Session.clean(t: unknown): Role?
	if type(t) ~= "table" then
		return nil
	end
	local d = t :: any
	if type(d.mode) ~= "string" or not MODES[d.mode] then
		return nil
	end
	local role: Role = { mode = d.mode :: Mode }
	if type(d.track) == "string" and TrackData.Tracks[d.track] then
		role.track = d.track
	end
	if type(d.code) == "string" and #d.code <= 12 and string.match(d.code, "^%d+$") then
		role.code = d.code
	end
	if type(d.host) == "number" then
		role.host = d.host
	end
	return role
end

function Session.studio(): boolean
	return RunService:IsStudio()
end

-- A server made by ReserveServerAsync (not a public one, not a VIP server).
function Session.reserved(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- Seconds on a clock every server agrees on (UTC wall time).
function Session.clock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local serversMap: MemoryStoreHashMap? = nil
local function servers(): MemoryStoreHashMap?
	if not serversMap then
		local ok, m = pcall(function()
			return MemoryStoreService:GetHashMap("A1Servers")
		end)
		if ok then
			serversMap = m
		end
	end
	return serversMap
end

-- This server's role. A reserved server reads it from the map, or waits for
-- the first player and reads their teleport data.
function Session.resolve(): Role
	if not Session.reserved() then
		return { mode = "lobby" }
	end
	local map = servers()
	if map then
		for _ = 1, 3 do
			local ok, v = pcall(function()
				return (map :: MemoryStoreHashMap):GetAsync(game.PrivateServerId)
			end)
			if ok then
				local role = Session.clean(v)
				if role then
					return role
				end
				break -- read fine, nothing there
			end
			task.wait(1)
		end
	end
	local first = Players:GetPlayers()[1]
	if not first then
		first = Players.PlayerAdded:Wait()
	end
	local ok, join = pcall(function()
		return first:GetJoinData()
	end)
	local role = if ok and join then Session.clean(join.TeleportData) else nil
	return role or { mode = "race" }
end

-- A new reserved server that will be `role`. Returns its access code (nil
-- if it could not be made). Studio has no reserved servers.
function Session.reserve(role: Role): string?
	if Session.studio() then
		return "studio"
	end
	local ok, code, id = pcall(function()
		return TeleportService:ReserveServerAsync(game.PlaceId)
	end)
	if not ok or type(code) ~= "string" then
		warn("[Session] could not reserve a server:", code)
		return nil
	end
	local map = servers()
	if map and type(id) == "string" then
		local saved, err = pcall(function()
			(map :: MemoryStoreHashMap):SetAsync(id, role, L.ServerTtl)
		end)
		if not saved then
			warn("[Session] could not note the server's role (teleport data will do):", err)
		end
	end
	return code
end

local function tell(p: Player, kind: string, data: { [string]: any })
	local f = Session.notify
	if f then
		f(p, kind, data)
	end
end

-- The loading screen's line for where the players are going.
function Session.label(role: Role): string
	if role.mode == "practice" then
		local spec = TrackData.Tracks[role.track or ""]
		return "Practice  -  " .. (if spec then spec.Name else "Loading")
	elseif role.mode == "race" then
		return "Quick race  -  joining the other drivers"
	elseif role.mode == "room" then
		return "Private room " .. (role.code or "")
	end
	return "Back to the lobby"
end

function Session.busy(p: Player): boolean
	return pending[p] == true
end

-- Sends players to the reserved server with access code `code` (or, with no
-- code, to a public server: the lobby). Their clients show the loading
-- screen first; `notice` is shown to them when they get there. Returns false
-- if nobody could be sent.
function Session.send(players: { Player }, role: Role, code: string?, notice: string?): boolean
	local list: { Player } = {}
	for _, p in players do
		if p.Parent and not pending[p] then
			table.insert(list, p)
		end
	end
	if #list == 0 then
		return false
	end
	local info = { mode = role.mode, track = role.track, code = role.code, label = Session.label(role) }
	if Session.studio() then
		-- one server: everyone in it goes along
		for _, p in Players:GetPlayers() do
			tell(p, "Teleport", info)
		end
		task.delay(L.TeleportDelay, function()
			local f = Session.switchHere
			if f then
				f(role)
			end
		end)
		return true
	end
	for _, p in list do
		pending[p] = true
		tell(p, "Teleport", info)
	end
	task.spawn(function()
		-- the next server loads the player's data: save it first
		local save = Session.beforeLeave
		if save then
			for _, p in list do
				pcall(save, p)
			end
		end
		task.wait(L.TeleportDelay)
		local still: { Player } = {}
		for _, p in list do
			if p.Parent then
				table.insert(still, p)
			end
		end
		if #still == 0 then
			return
		end
		local opts = Instance.new("TeleportOptions")
		if code then
			opts.ReservedServerAccessCode = code
		end
		opts:SetTeleportData({ mode = role.mode, track = role.track, code = role.code, host = role.host, label = info.label, notice = notice })
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, still, opts)
		end)
		if not ok then
			warn("[Session] teleport failed:", err)
			for _, p in still do
				pending[p] = nil
				tell(p, "TeleportFailed", { message = "Couldn't move you to the next server. Try again." })
			end
		end
	end)
	return true
end

-- Back to a lobby (any public server).
function Session.toLobby(player: Player)
	Session.send({ player }, { mode = "lobby" }, nil)
end

-- A private room's host removed this player: off to a lobby, where they see
-- `message`. Studio has only this server, so there it is Player:Kick.
function Session.kick(player: Player, message: string)
	if Session.studio() then
		player:Kick(message)
		return
	end
	pending[player] = nil -- (even mid-teleport: this one wins)
	Session.send({ player }, { mode = "lobby" }, nil, message)
end

function Session.init()
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result: any, message: string)
		if pending[player] then
			pending[player] = nil
			warn("[Session] teleport failed for", player.Name, message)
			tell(player, "TeleportFailed", { message = "Couldn't move you to the next server. Try again." })
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		pending[p] = nil
	end)
end

return Session
