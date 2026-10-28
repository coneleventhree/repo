--!strict
-- Wins and personal best laps (leaderstats + DataStore), and the track record.
-- Best laps and records are kept per circuit; the leaderboard and the HUD
-- show the ones for the circuit in use (Stats.setTrack).
-- DataStores fail in Studio unless "Enable Studio Access to API Services" is
-- on; everything still works for the session, it just is not saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Stats = {}

type Data = { wins: number, bests: { [string]: number }, settings: { [string]: any }, dirty: boolean }
type Record = { time: number?, name: string?, loaded: boolean }

local store: DataStore? = nil
local available = true
local data: { [Player]: Data } = {}
local records: { [string]: Record } = {}
local trackId = "Tampines"
local onRecord: ((name: string, time: number) -> ())? = nil

local STORE_NAME = "ApexKarting_v1" -- the game's first name; kept so saved bests survive the rename to A1 Kart Racing
-- the first circuit keeps the keys it had before there were several
local LEGACY_TRACK = "Tampines"

local function recordKey(id: string): string
	return if id == LEGACY_TRACK then "track_record" else "track_record_" .. id
end

local function tryStore(): DataStore?
	if not available then
		return nil
	end
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return result
	end
	available = false
	warn("[Stats] DataStore unavailable, progress will not be saved:", result)
	return nil
end

function Stats.formatTime(t: number?): string
	if not t then
		return "--"
	end
	local m = math.floor(t / 60)
	local s = t - m * 60
	if m > 0 then
		return string.format("%d:%06.3f", m, s)
	end
	return string.format("%.3f", s)
end

local function recordOf(id: string): Record
	local r = records[id]
	if not r then
		r = { time = nil, name = nil, loaded = false }
		records[id] = r
	end
	return r
end

-- every circuit's record (Record_<id>, RecordBy_<id>: the lobby's cards
-- and RECORDS) and the one in use (TrackRecord, TrackRecordHolder: the HUD)
local function publishRecordOf(id: string)
	local r = recordOf(id)
	workspace:SetAttribute("Record_" .. id, r.time)
	workspace:SetAttribute("RecordBy_" .. id, r.name)
	if id == trackId then
		workspace:SetAttribute("TrackRecord", r.time)
		workspace:SetAttribute("TrackRecordHolder", r.name)
	end
end

local function publishRecord()
	publishRecordOf(trackId)
end

local function loadRecord(id: string)
	local r = recordOf(id)
	if r.loaded then
		return
	end
	r.loaded = true
	task.spawn(function()
		local ds = tryStore()
		if not ds then
			return
		end
		local ok, rec = pcall(function()
			return ds:GetAsync(recordKey(id))
		end)
		if ok and type(rec) == "table" then
			local t = tonumber(rec.time)
			-- a faster lap may already have been set this session
			if t and (not r.time or t < r.time) then
				r.time = t
				r.name = rec.name
			end
			publishRecordOf(id)
		end
	end)
end

local function showBest(player: Player)
	local d = data[player]
	local best = d and d.bests[trackId] or nil
	player:SetAttribute("PersonalBest", best)
	-- every circuit's best for the lobby (Best_<id>)
	if d then
		for id, t in d.bests do
			player:SetAttribute("Best_" .. id, t)
		end
	end
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Best Lap")
	if v and v:IsA("StringValue") then
		v.Value = Stats.formatTime(best)
	end
end

local function makeLeaderstats(player: Player, d: Data)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = d.wins
	wins.Parent = ls
	local best = Instance.new("StringValue")
	best.Name = "Best Lap"
	best.Value = Stats.formatTime(d.bests[trackId])
	best.Parent = ls
	ls.Parent = player
end

-- A setting value checked against Config.Settings (nil if not allowed).
local function cleanSetting(key: unknown, value: unknown): any
	if type(key) ~= "string" then
		return nil
	end
	local item = Config.Settings.Items[key]
	if not item then
		return nil
	end
	if type(item.default) == "boolean" then
		return if type(value) == "boolean" then value else nil
	elseif item.options then
		return if type(value) == "string" and table.find(item.options, value) then value else nil
	elseif type(value) == "number" and value == value then
		local v = math.clamp(value, item.min, item.max)
		return math.floor((v - item.min) / item.step + 0.5) * item.step + item.min
	end
	return nil
end

-- Player attributes S_<key> carry the settings to the client.
local function publishSettings(player: Player, d: Data)
	for key, item in Config.Settings.Items do
		local v = d.settings[key]
		if v == nil then
			v = item.default
		end
		player:SetAttribute("S_" .. key, v)
	end
end

local function load(player: Player)
	local d: Data = { wins = 0, bests = {}, settings = {}, dirty = false }
	local ds = tryStore()
	if ds then
		local ok, saved = pcall(function()
			return ds:GetAsync("p_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			d.wins = tonumber(saved.wins) or 0
			if type(saved.bests) == "table" then
				for id, t in saved.bests do
					if type(id) == "string" and tonumber(t) then
						d.bests[id] = tonumber(t) :: number
					end
				end
			end
			-- saves from before there were several circuits
			if not d.bests[LEGACY_TRACK] and tonumber(saved.best) then
				d.bests[LEGACY_TRACK] = tonumber(saved.best) :: number
			end
			if type(saved.settings) == "table" then
				for key, value in saved.settings do
					local v = cleanSetting(key, value)
					if v ~= nil then
						d.settings[key :: string] = v
					end
				end
			end
		elseif not ok then
			warn("[Stats] load failed for", player.Name, saved)
		end
	end
	data[player] = d
	makeLeaderstats(player, d)
	showBest(player)
	publishSettings(player, d)
end

local function save(player: Player)
	local d = data[player]
	local ds = tryStore()
	if not (d and ds) then
		return
	end
	local ok, err = pcall(function()
		ds:SetAsync("p_" .. player.UserId, { wins = d.wins, best = d.bests[LEGACY_TRACK], bests = d.bests, settings = d.settings })
	end)
	if not ok then
		warn("[Stats] save failed for", player.Name, err)
	end
end

function Stats.init(recordCallback: (name: string, time: number) -> (), firstTrack: string?)
	onRecord = recordCallback
	trackId = firstTrack or trackId
	loadRecord(trackId)
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		data[player] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)
end

-- Saves now (before a teleport: the next server loads what was saved). Yields.
function Stats.saveNow(player: Player)
	save(player)
end

-- Loads the records of these circuits too (the lobby shows them all).
function Stats.loadRecords(ids: { string })
	for _, id in ids do
		loadRecord(id)
		publishRecordOf(id)
	end
end

-- The circuit in use changed: show its record and everyone's best lap on it.
function Stats.setTrack(id: string)
	trackId = id
	loadRecord(id)
	publishRecord()
	for p in data do
		showBest(p)
	end
end

-- A player changed a setting (from the SETTINGS menu). Saved a little later
-- (several clicks in a row become one write) and when they leave.
function Stats.setSetting(player: Player, key: unknown, value: unknown)
	local d = data[player]
	local v = cleanSetting(key, value)
	if not d or v == nil then
		return
	end
	d.settings[key :: string] = v
	player:SetAttribute("S_" .. (key :: string), v)
	if not d.dirty then
		d.dirty = true
		task.delay(8, function()
			if data[player] == d and d.dirty then
				d.dirty = false
				save(player)
			end
		end)
	end
end

function Stats.addWin(player: Player)
	local d = data[player]
	if not d then
		return
	end
	d.wins += 1
	local ls = player:FindFirstChild("leaderstats")
	local wins = ls and ls:FindFirstChild("Wins")
	if wins and wins:IsA("IntValue") then
		wins.Value = d.wins
	end
	task.spawn(save, player)
end

-- Records a completed lap on the circuit in use. Returns true if it was a
-- personal best there.
function Stats.recordLap(player: Player, t: number): boolean
	local d = data[player]
	if not d or t < 10 then -- a lap under 10 s cannot be real
		return false
	end
	local id = trackId
	local pb = false
	local best = d.bests[id]
	if not best or t < best then
		d.bests[id] = t
		pb = true
		showBest(player)
		task.spawn(save, player)
	end
	local r = recordOf(id)
	if not r.time or t < r.time then
		r.time = t
		r.name = player.DisplayName
		publishRecordOf(id)
		if onRecord then
			onRecord(player.DisplayName, t)
		end
		local ds = tryStore()
		if ds then
			task.spawn(function()
				pcall(function()
					ds:UpdateAsync(recordKey(id), function(old)
						if type(old) == "table" and tonumber(old.time) and old.time <= t then
							return nil -- someone on another server was faster
						end
						return { time = t, name = player.DisplayName, userId = player.UserId }
					end)
				end)
			end)
		end
	end
	return pb
end

return Stats
