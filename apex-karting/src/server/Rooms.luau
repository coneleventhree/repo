--!strict
-- Private rooms: CREATE ROOM reserves a server and gives it a short number
-- code (Config.Lobby.RoomDigits); friends type the code to join. The code
-- lives in a shared map (code -> the server's access code and the host);
-- the room's own server renews it while it is open and frees it when it
-- closes. In the room the host picks the track and length and starts the
-- race (RaceManager, mode "room").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SharedStore = require(script.Parent:WaitForChild("SharedStore"))
local Session = require(script.Parent:WaitForChild("Session"))

local Rooms = {}

export type Deps = {
	rooms: SharedStore.Map,
	reserve: (Session.Role) -> string?,
	send: ({ Player }, Session.Role, string?) -> boolean,
}

local L = Config.Lobby
local deps: Deps? = nil

function Rooms.init(d: Deps)
	deps = d
end

-- Digits only, exactly RoomDigits of them (nil otherwise).
function Rooms.cleanCode(code: unknown): string?
	if type(code) ~= "string" and type(code) ~= "number" then
		return nil
	end
	local digits = string.gsub(tostring(code), "%D", "")
	return if #digits == L.RoomDigits then digits else nil
end

-- A new room with `player` as host. Returns the code, or nil and a message.
function Rooms.create(player: Player): (string?, string?)
	local d = deps
	if not d then
		return nil, "Rooms are not ready yet"
	end
	for _ = 1, 12 do
		local code = string.format("%0" .. L.RoomDigits .. "d", math.random(0, 10 ^ L.RoomDigits - 1))
		-- claim the code before reserving, so two rooms never share one
		local claimed = d.rooms.update(code, function(old)
			if old ~= nil then
				return nil
			end
			return { host = player.UserId, claiming = true }
		end, 120)
		if claimed ~= nil then
			local role: Session.Role = { mode = "room", code = code, host = player.UserId }
			local access = d.reserve(role)
			if not access then
				d.rooms.remove(code)
				return nil, "Couldn't make a room. Try again."
			end
			d.rooms.set(code, { access = access, host = player.UserId, name = player.DisplayName }, L.RoomTtl)
			d.send({ player }, role, access)
			return code, nil
		end
	end
	return nil, "Couldn't make a room. Try again."
end

-- Into the room with this code. Returns nil, or a message to show.
function Rooms.join(player: Player, raw: unknown): string?
	local d = deps
	if not d then
		return "Rooms are not ready yet"
	end
	local code = Rooms.cleanCode(raw)
	if not code then
		return string.format("Enter the %d-digit room code", L.RoomDigits)
	end
	local v = d.rooms.get(code)
	if type(v) ~= "table" or type(v.access) ~= "string" then
		return "No room with that code"
	end
	if type(v.banned) == "table" and table.find(v.banned, player.UserId) then
		return "You were removed from this room"
	end
	d.send({ player }, { mode = "room", code = code, host = v.host }, v.access)
	return nil
end

-- In the room's own server: the host removed this player; the code no
-- longer lets them in (the room server also sends them away if they come).
function Rooms.ban(code: string, userId: number)
	local d = deps
	if not d then
		return
	end
	d.rooms.update(code, function(old)
		if type(old) ~= "table" then
			return nil
		end
		local list = if type(old.banned) == "table" then old.banned else {}
		if not table.find(list, userId) then
			table.insert(list, userId)
		end
		old.banned = list
		return old
	end, L.RoomTtl)
end

-- In the room's own server: keep the code while the room is open.
function Rooms.keep(code: string)
	local d = deps
	if not d then
		return
	end
	local function renew()
		d.rooms.update(code, function(old)
			return if type(old) == "table" then old else nil
		end, L.RoomTtl)
	end
	task.spawn(function()
		while true do
			task.wait(L.RoomRefresh)
			renew()
		end
	end)
	game:BindToClose(function()
		d.rooms.remove(code)
	end)
end

return Rooms
