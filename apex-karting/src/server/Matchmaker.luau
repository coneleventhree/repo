--!strict
-- Quick-race matchmaking across every lobby server.
--
-- Pressing RACE puts a ticket in a shared map (key: the player's UserId;
-- value: when they started waiting and which server they are on). Every
-- lobby server with someone waiting reads the map every QueuePoll seconds:
--   * once QueueMin drivers wait, the race goes QueueWait seconds after the
--     QueueMin-th of them joined (straight away when QueueMax wait);
--   * when it is time, one server takes a short lock, reserves a race
--     server and writes its access code into the tickets of the first
--     QueueMax drivers;
--   * each lobby server sends its own drivers whose ticket has a code.
-- Tickets are renewed by their server on every pass and expire on their own
-- if that server goes away.
--
-- Waiting players see: attributes Queued, QueueCount (drivers waiting) and
-- QueueGo (this server's time when the race goes, nil until there are
-- enough drivers).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SharedStore = require(script.Parent:WaitForChild("SharedStore"))

local Matchmaker = {}

export type Deps = {
	tickets: SharedStore.Map,
	locks: SharedStore.Map,
	reserve: () -> string?, -- a race server's access code
	send: ({ Player }, string) -> (), -- off to that server
	clock: () -> number, -- shared wall clock (seconds)
	minPlayers: number,
}

local L = Config.Lobby
local deps: Deps? = nil
local waiting: { [Player]: number } = {} -- when each started waiting (shared clock)
local polling = false
local again = false

local function key(p: Player): string
	return tostring(p.UserId)
end

local function clearAttrs(p: Player)
	p:SetAttribute("Queued", nil)
	p:SetAttribute("QueueCount", nil)
	p:SetAttribute("QueueGo", nil)
end

function Matchmaker.isWaiting(p: Player): boolean
	return waiting[p] ~= nil
end

-- One server forms the match: whoever gets the lock.
local function form(d: Deps, free: { { key: string, t: number } }, t: number): boolean
	local lock = d.locks.update("queue", function(old)
		if type(old) == "table" and old.job ~= game.JobId and type(old.at) == "number" and old.at > t - 10 then
			return nil -- another server is on it
		end
		return { job = game.JobId, at = t }
	end, 15)
	if lock == nil then
		return false
	end
	local code = d.reserve()
	local given = 0
	if code then
		local match = game.JobId .. ":" .. tostring(math.floor(t * 1000))
		for i = 1, math.min(#free, L.QueueMax) do
			local v = d.tickets.update(free[i].key, function(old)
				if type(old) == "table" and not old.code then
					old.code = code
					old.match = match
					return old
				end
				return nil
			end, L.TicketTtl)
			if v ~= nil then
				given += 1
			end
		end
	end
	d.locks.remove("queue")
	return given > 0
end

-- One pass: renew our tickets, send the matched ones, count down, form a match.
function Matchmaker.poll()
	local d = deps
	if not d or next(waiting) == nil then
		return
	end
	if polling then
		again = true
		return
	end
	polling = true
	local t = d.clock()
	for p, since in table.clone(waiting) do
		d.tickets.update(key(p), function(old)
			if type(old) == "table" and old.code then
				return nil -- already given a server: leave it be
			end
			return { job = game.JobId, t = since, name = p.DisplayName }
		end, L.TicketTtl)
	end
	local items = d.tickets.list()
	local formed = false
	if items then
		local free: { { key: string, t: number } } = {}
		local matched: { [string]: { Player } } = {}
		for _, it in items do
			local v = it.value
			if type(v) ~= "table" then
				continue
			end
			if type(v.code) == "string" then
				local p = Players:GetPlayerByUserId(tonumber(it.key) or 0)
				if p and waiting[p] then
					local list = matched[v.code] or {}
					matched[v.code] = list
					table.insert(list, p)
				end
			elseif type(v.t) == "number" then
				table.insert(free, { key = it.key, t = v.t })
			end
		end
		for code, list in matched do
			for _, p in list do
				waiting[p] = nil
				d.tickets.remove(key(p))
				clearAttrs(p)
			end
			d.send(list, code)
		end
		table.sort(free, function(a, b)
			if a.t ~= b.t then
				return a.t < b.t
			end
			return a.key < b.key
		end)
		local startAt: number? = nil
		if #free >= L.QueueMax then
			startAt = t
		elseif #free >= d.minPlayers then
			startAt = free[d.minPlayers].t + L.QueueWait
		end
		local serverNow = workspace:GetServerTimeNow()
		for p in waiting do
			p:SetAttribute("QueueCount", math.max(#free, 1))
			p:SetAttribute("QueueGo", if startAt then serverNow + math.max(startAt - t, 0) else nil)
		end
		if startAt and t >= startAt then
			formed = form(d, free, t)
		end
	end
	polling = false
	if formed or again then
		again = false
		-- our own drivers in the new match leave on this next pass
		task.defer(Matchmaker.poll)
	end
end

function Matchmaker.join(p: Player)
	local d = deps
	if not d or waiting[p] then
		return
	end
	waiting[p] = d.clock()
	p:SetAttribute("Queued", true)
	p:SetAttribute("QueueCount", 1)
	p:SetAttribute("QueueGo", nil)
	task.spawn(Matchmaker.poll)
end

function Matchmaker.leave(p: Player)
	local d = deps
	if not waiting[p] then
		return
	end
	waiting[p] = nil
	clearAttrs(p)
	if d then
		task.spawn(d.tickets.remove, key(p))
	end
end

function Matchmaker.init(d: Deps)
	deps = d
	Players.PlayerRemoving:Connect(Matchmaker.leave)
	task.spawn(function()
		while true do
			task.wait(L.QueuePoll)
			Matchmaker.poll()
		end
	end)
end

return Matchmaker
