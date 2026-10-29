--!strict
-- The race weekend loop. What a server does depends on its mode (Session):
--   lobby     the menu; no karts (State "Lobby")
--   practice  one player's free practice; the track changes from the HUD
--   race      a quick race: the loop below, round after round
--   room      a private room: a waiting room (State "Lobby", no karts) with
--             the players, READY / NOT READY, the host's track and length;
--             the host starts once every guest is ready (and can kick);
--             then qualifying, grid, race, podium and back to the waiting
--             room (no vote)
--
--   Practice      fewer than MinPlayers: everyone free-drives with lap timing;
--                 the track can be changed straight away from the HUD
--   Intermission  enough players: countdown while still practising; votes on
--                 the next track and race length; when everyone presses
--                 READY the countdown drops to a few seconds
--   Qualifying    one timed lap each, with ghosts (karts pass through each
--                 other, no slipstream): everyone starts together a run-up
--                 before the line; a deleted lap means the back of the grid.
--                 Over when everyone is done, or at the flag (per track
--                 time: finish the lap you are on)
--   Grid          karts placed on the grid in qualifying order (anchored);
--                 five red lights
--   Racing        lights out; laps and positions from RaceProgress
--   Results       a short podium for the top three, then the next round
--
-- Track limits (TrackLimits): all four tyres beyond the kerb. In practice and
-- qualifying the lap is struck off; in the race the first few are warnings,
-- then each one adds a time penalty to the result. Every timed lap is split
-- into sectors, coloured against the session's and the driver's best.
--
-- Every circuit is built at start-up; the one in use is workspace.Circuit,
-- the others wait in ServerStorage.Circuits. Switching moves the folders.
--
-- Clients read workspace attributes (RaceState, StateEnd, LightsStart,
-- RaceStart, Laps, Track, TrackName, Tracks, Votes_<id>, LenVotes_<length>,
-- ReadyCount, QualiClosing, Podium) and player attributes (Lap, Position,
-- WrongWay, OffCourse, Finished, Vote, LengthVote, Ready, Warnings, Penalty)
-- and get one-off messages on the RaceEvent remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local TrackLayout = require(Shared:WaitForChild("TrackLayout"))
local TrackLimits = require(Shared:WaitForChild("TrackLimits"))
local RaceProgress = require(Shared:WaitForChild("RaceProgress"))
local KartFactory = require(script.Parent:WaitForChild("KartFactory"))
local Stats = require(script.Parent:WaitForChild("Stats"))
local Build = require(script.Parent:WaitForChild("Build"))
local v3, vec = Build.v3, Build.vec

local RaceManager = {}
-- called after a switch to another circuit (init.server sets the weather)
RaceManager.onTrackChanged = nil :: ((any) -> ())?
-- a private room's host removed this player (init.server sends them to the
-- lobby with the message and bars them from the room)
RaceManager.onKick = nil :: ((Player, string) -> ())?

type State = "Lobby" | "Practice" | "Intermission" | "Qualifying" | "Grid" | "Racing" | "Results"
type Mode = "practice" | "quali" | "race" -- the kind of timing session
export type ServerMode = "lobby" | "practice" | "race" | "room"
export type Role = { mode: ServerMode, track: string?, code: string?, host: number? }

-- One built circuit: its TrackData entry, the sampled track, the bands
-- beside the road (for track limits) and its folder.
export type Circuit = { id: string, spec: any, track: TrackMath.Track, zones: TrackLayout.Zones, folder: Folder }

local R = Config.Race
local LENGTHS = { "Short", "Normal", "Long" }
local DEFAULT_SECTORS = { 1 / 3, 2 / 3 }

-- circuits and votes
local circuits: { [string]: Circuit } = {}
local order: { string } = {}
local current: Circuit
local storage: Folder
local track: TrackMath.Track
local zones: TrackLayout.Zones
local LAPS = 3
local votes: { [Player]: string } = {}
local lengthVotes: { [Player]: string } = {}
local ready: { [Player]: boolean } = {}
local lastTrackChange = -math.huge

-- what this server is for (setMode)
local serverMode: ServerMode = "race"
local roomCode: string? = nil
local roomHost: number? = nil -- UserId
local roomLength = "Normal"
-- the waiting room's pick: only a note until START (switching circuits sends
-- thousands of parts to every client, so it happens once, then)
local roomPick: string? = nil
local wantTrack: string? = nil -- a switch asked for a circuit still being built
local kicked: { [number]: boolean } = {} -- UserIds the room's host removed

local kartFolder: Folder
local raceEvent: RemoteEvent

local state: State = "Practice"
local stateEnd = 0
local karts: { [Player]: Model } = {}
local numbers: { [Player]: number } = {}
local lastReset: { [Player]: number } = {}
local spawnHold: { [Player]: number } = {} -- onCharacter is about to give a kart
local ghostSince: { [Model]: number } = {} -- since when a reset kart has been a ghost

-- sessions
local practice: { [Player]: RaceProgress.Race } = {}
local quali: RaceProgress.Race? = nil
local qualiClosing = false
local race: RaceProgress.Race? = nil
local racers: { Player } = {}
local raceStart = 0
local finishDeadline: number? = nil
local lastStandings = 0
local lastAttr = 0
local lastTick = 0

-- timing extras for the session in progress
type Bests = { sectors: { [number]: number }, lap: number? }
local sessionBest: Bests = { sectors = {}, lap = nil }
local bests: { [Player]: Bests } = {}
local splits: { [Player]: number } = {} -- last split time on the current lap
local limits: { [Player]: TrackLimits.Tracker } = {}
local warnings: { [Player]: number } = {}
local penalties: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Lobby: characters stand still behind the menu.
local function freeze(p: Player, on: boolean)
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then
		h.WalkSpeed = if on then 0 else 16
		h.JumpHeight = if on then 0 else 7.2
	end
end

local function setState(s: State, duration: number?)
	local was = state
	state = s
	stateEnd = if duration then now() + duration else 0
	workspace:SetAttribute("RaceState", s)
	workspace:SetAttribute("StateEnd", stateEnd)
	-- qualifying is driven with ghosts (clients drop the bumpers and the tow)
	workspace:SetAttribute("Ghost", s == "Qualifying")
	if (was == "Lobby") ~= (s == "Lobby") then
		for _, p in Players:GetPlayers() do
			freeze(p, s == "Lobby")
		end
	end
end

-- Where a server rests between rounds: the menu (lobby), the waiting room
-- (private room), free practice (practice and quick-race servers).
local function idle(): State
	return if serverMode == "lobby" or serverMode == "room" then "Lobby" else "Practice"
end

-- a quick race needs MinPlayers; a private room races with whoever is there
local function minPlayers(): number
	return if serverMode == "room" then 1 else R.MinPlayers
end

local function isHost(p: Player): boolean
	return serverMode == "room" and p.UserId == roomHost
end

-- The room's host: whoever made it, or (if they left) the next player.
local function checkHost()
	if serverMode ~= "room" then
		workspace:SetAttribute("RoomHost", nil)
		workspace:SetAttribute("RoomHostName", nil)
		return
	end
	local host = if roomHost then Players:GetPlayerByUserId(roomHost) else nil
	if not host then
		host = Players:GetPlayers()[1]
		if host then
			roomHost = host.UserId
		end
	end
	workspace:SetAttribute("RoomHost", roomHost)
	workspace:SetAttribute("RoomHostName", if host then host.DisplayName else nil)
end

local function setStateEnd(t: number)
	stateEnd = t
	workspace:SetAttribute("StateEnd", stateEnd)
end

local function fire(player: Player?, kind: string, payload: { [string]: any }?)
	if player then
		raceEvent:FireClient(player, kind, payload or {})
	else
		raceEvent:FireAllClients(kind, payload or {})
	end
end

local function alive(player: Player): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

local function eligiblePlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if alive(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function numberFor(player: Player): number
	if numbers[player] then
		return numbers[player]
	end
	local used = {}
	for _, n in numbers do
		used[n] = true
	end
	local n = 1
	while used[n] do
		n += 1
	end
	numbers[player] = n
	return n
end

local function colorFor(player: Player): Color3
	local n = numberFor(player)
	return KartFactory.Colors[(n - 1) % #KartFactory.Colors + 1]
end

local function chassisOf(player: Player): BasePart?
	local k = karts[player]
	return k and k.PrimaryPart or nil
end

local function removeKart(player: Player)
	local k = karts[player]
	karts[player] = nil
	practice[player] = nil
	if k then
		KartFactory.release(player)
		k:Destroy()
	end
end

-- pose on the road for grid slot `slot`, lifted to ride height by KartFactory
local function slotPose(slot: number): (Vector3, Vector3, Vector3)
	local pos, fwd, up = TrackLayout.gridSlot(track, slot, R)
	return v3(pos), v3(fwd), v3(up)
end

local function spawnKart(player: Player, pos: Vector3, fwd: Vector3, up: Vector3, anchored: boolean): Model?
	removeKart(player)
	if not alive(player) then
		return nil
	end
	local center = pos + up * (Config.Kart.RideHeight + 0.15)
	local model = KartFactory.create(player, numberFor(player), CFrame.lookAt(center, center + fwd, up), colorFor(player), anchored, kartFolder)
	karts[player] = model
	if not KartFactory.seat(model, player) then
		model:Destroy()
		karts[player] = nil
		return nil
	end
	if not anchored then
		task.defer(KartFactory.handOver, model, player)
	end
	return model
end

-- first grid slot with no kart near it
local function freeSlot(): number
	for slot = 1, R.MaxRacers do
		local pos = slotPose(slot)
		local taken = false
		for _, k in karts do
			if k.PrimaryPart and (k.PrimaryPart.Position - pos).Magnitude < 8 then
				taken = true
				break
			end
		end
		if not taken then
			return slot
		end
	end
	return math.random(1, R.MaxRacers)
end

local function newSession(laps: number, startTime: number): RaceProgress.Race
	local s = RaceProgress.new(TrackMath, track, laps, R.OffTrackAllowance, startTime)
	s:setSectors(current.spec.Sectors or DEFAULT_SECTORS)
	return s
end

local function resetTiming()
	sessionBest = { sectors = {}, lap = nil }
	table.clear(bests)
	table.clear(splits)
	table.clear(limits)
	table.clear(warnings)
	table.clear(penalties)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Warnings", nil)
		p:SetAttribute("Penalty", nil)
	end
end

local function spawnPracticeKart(player: Player)
	local pos, fwd, up = slotPose(freeSlot())
	local model = spawnKart(player, pos, fwd, up, false)
	if model then
		practice[player] = newSession(1e9, now())
		practice[player]:addRacer(player, vec(pos), now())
		limits[player] = TrackLimits.newTracker()
		splits[player] = 0
	end
end

local function canPractice(): boolean
	return state == "Practice" or state == "Intermission"
end

----------------------------------------------------------------------------
-- Circuits, votes and ready
----------------------------------------------------------------------------
local function publishVotes(): { [string]: number }
	local counts: { [string]: number } = {}
	for p, id in votes do
		if p.Parent then
			counts[id] = (counts[id] or 0) + 1
		end
	end
	for _, id in order do
		workspace:SetAttribute("Votes_" .. id, counts[id] or 0)
	end
	local lens: { [string]: number } = {}
	for p, l in lengthVotes do
		if p.Parent then
			lens[l] = (lens[l] or 0) + 1
		end
	end
	for _, l in LENGTHS do
		workspace:SetAttribute("LenVotes_" .. l, lens[l] or 0)
	end
	local readyCount = 0
	for p, on in ready do
		if on and p.Parent then
			readyCount += 1
		end
	end
	workspace:SetAttribute("ReadyCount", readyCount)
	return counts
end

local function resetVotes()
	table.clear(votes)
	table.clear(lengthVotes)
	table.clear(ready)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Vote", nil)
		p:SetAttribute("LengthVote", nil)
		p:SetAttribute("Ready", nil)
	end
	publishVotes()
end

-- Most votes wins; a tie is drawn among the leaders; no votes keeps the track.
local function voteWinner(): string
	local counts = publishVotes()
	local best, leaders = 0, {}
	for _, id in order do
		local c = counts[id] or 0
		if c > best then
			best, leaders = c, { id }
		elseif c == best and c > 0 then
			table.insert(leaders, id)
		end
	end
	if best == 0 then
		return current.id
	end
	return leaders[math.random(1, #leaders)]
end

-- Race length: most votes; ties go to Normal if it is among them.
local function lengthWinner(): string
	local counts: { [string]: number } = {}
	for p, l in lengthVotes do
		if p.Parent then
			counts[l] = (counts[l] or 0) + 1
		end
	end
	local best, leaders = 0, {}
	for _, l in LENGTHS do
		local c = counts[l] or 0
		if c > best then
			best, leaders = c, { l }
		elseif c == best and c > 0 then
			table.insert(leaders, l)
		end
	end
	if best == 0 or table.find(leaders, "Normal") then
		return "Normal"
	end
	return leaders[math.random(1, #leaders)]
end

local function lapsFor(spec: any, length: string): number
	local opts = spec.Lengths or { spec.Laps or 3, spec.Laps or 3, spec.Laps or 3 }
	return opts[table.find(LENGTHS, length) or 2]
end

-- Everyone in the server pressed READY: start in a few seconds.
local function checkAllReady()
	if state ~= "Intermission" then
		return
	end
	local list = eligiblePlayers()
	if #list < minPlayers() then
		return
	end
	for _, p in list do
		if not ready[p] then
			return
		end
	end
	local soon = now() + R.ReadyCountdown
	if stateEnd > soon then
		setStateEnd(soon)
		fire(nil, "AllReady", {})
	end
end

-- The waiting room: every player but the host has pressed READY.
local function guestsReady(): boolean
	for _, p in Players:GetPlayers() do
		if not isHost(p) and not ready[p] then
			return false
		end
	end
	return true
end

local function lobbySpawn(c: Circuit): BasePart?
	local pits = c.folder:FindFirstChild("Pits")
	local sp = pits and pits:FindFirstChild("LobbySpawn")
	return if sp and sp:IsA("BasePart") then sp else nil
end

local function activate(c: Circuit)
	current = c
	track = c.track
	zones = c.zones
	LAPS = lapsFor(c.spec, if serverMode == "room" then roomLength else "Normal")
	c.folder.Name = "Circuit"
	c.folder.Parent = workspace
	workspace:SetAttribute("Track", c.id)
	workspace:SetAttribute("TrackName", c.spec.Name)
	roomPick = nil
	workspace:SetAttribute("RoomTrack", c.id)
	workspace:SetAttribute("Laps", LAPS)
	Stats.setTrack(c.id)
	resetTiming()
end

-- Puts circuit `id` in use. Karts are taken away (the caller decides what
-- comes next) and anyone walking around is moved to the new paddock.
local function switchTo(id: string): boolean
	local c = circuits[id]
	if not c or c == current then
		return false
	end
	for _, p in Players:GetPlayers() do
		removeKart(p)
	end
	local old = current
	old.folder.Parent = storage
	old.folder.Name = old.id
	activate(c)
	lastTrackChange = now()
	local sp = lobbySpawn(c)
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		if sp and ch and ch.PrimaryPart then
			local off = Vector3.new(math.random(-5, 5), 4, math.random(-5, 5))
			ch:PivotTo(CFrame.new(sp.Position + off))
		end
		-- practice karts come back on their own once the new circuit has
		-- reached everyone's client (thousands of parts to replicate)
		spawnHold[p] = os.clock() + R.TrackLoadTime
	end
	if RaceManager.onTrackChanged then
		RaceManager.onTrackChanged(c)
	end
	fire(nil, "Track", { id = c.id, name = c.spec.Name, laps = LAPS })
	print(string.format("[A1KartRacing] track is now %s", c.spec.Name))
	return true
end

local function publishTracks()
	workspace:SetAttribute("Tracks", table.concat(order, ","))
	publishVotes()
end

----------------------------------------------------------------------------
-- Timing: sectors, laps, track limits
----------------------------------------------------------------------------
local function bestsOf(p: Player): Bests
	local b = bests[p]
	if not b then
		b = { sectors = {}, lap = nil }
		bests[p] = b
	end
	return b
end

-- purple: fastest of the session, green: the driver's best, yellow: slower
local function rate(p: Player, index: number?, t: number, invalid: boolean): string
	if invalid then
		return "invalid"
	end
	local mine = bestsOf(p)
	local myBest = if index then mine.sectors[index] else mine.lap
	local overall = if index then sessionBest.sectors[index] else sessionBest.lap
	local colour = "yellow"
	if not myBest or t <= myBest then
		colour = "green"
		if index then
			mine.sectors[index] = t
		else
			mine.lap = t
		end
	end
	if not overall or t <= overall then
		colour = "purple"
		if index then
			sessionBest.sectors[index] = t
		else
			sessionBest.lap = t
		end
	end
	return colour
end

local function sectorEvent(p: Player, index: number, split: number, invalid: boolean)
	local sectorTime = split - (splits[p] or 0)
	splits[p] = split
	fire(p, "Sector", { index = index, split = split, time = sectorTime, colour = rate(p, index, sectorTime, invalid) })
end

-- a timed lap ended: last sector, the lap itself, personal best
local function lapDone(p: Player, racer: RaceProgress.Racer, lapNo: number, lapTime: number?, invalid: boolean, final: boolean)
	local sectorCount = #((current.spec.Sectors or DEFAULT_SECTORS) :: { number }) + 1
	if lapTime then
		sectorEvent(p, sectorCount, lapTime, invalid)
	end
	splits[p] = 0
	local pb = false
	local colour = "invalid"
	if lapTime and not invalid then
		pb = Stats.recordLap(p, lapTime)
		colour = rate(p, nil, lapTime, false)
	end
	fire(p, "Lap", { lap = lapNo, time = lapTime, pb = pb, best = racer.bestLap, invalid = invalid, colour = colour, final = final })
end

local function handleEvents(player: Player, events: { RaceProgress.Event }, mode: Mode)
	for _, e in events do
		if e.kind == "start" then
			splits[player] = 0
			fire(player, "LapStart", { time = e.time, lap = 1 })
		elseif e.kind == "sector" then
			sectorEvent(player, e.index :: number, e.time :: number, e.racer.lapInvalid)
		elseif e.kind == "lap" then
			lapDone(player, e.racer, e.lap :: number, e.time, e.invalid == true, false)
			fire(player, "LapStart", { time = (e.racer.lapStart :: number), lap = e.racer.lap })
		elseif e.kind == "finish" then
			lapDone(player, e.racer, e.lap :: number, e.lapTime, e.invalid == true, true)
			if mode == "race" then
				local r = race :: RaceProgress.Race
				player:SetAttribute("Finished", true)
				player:SetAttribute("FinishTime", e.time)
				fire(nil, "Finish", { userId = player.UserId, name = player.DisplayName, position = r.finishCount, time = e.time })
				if r.finishCount == 1 then
					finishDeadline = now() + R.FinishGrace
					workspace:SetAttribute("FinishDeadline", finishDeadline)
				end
			elseif mode == "quali" then
				-- the one timed lap is in: where it puts them so far
				player:SetAttribute("QualiDone", true)
				local best = e.racer.bestLap
				local place: number? = nil
				local q = quali
				if best and q then
					local ahead = 0
					for _, id in q.order do
						local other = q.racers[id]
						if other ~= e.racer and other.bestLap and other.bestLap < best then
							ahead += 1
						end
					end
					place = ahead + 1
				end
				fire(player, "QualiDone", { best = best, place = place })
			end
		end
	end
end

-- Track limits for one driver this frame. Practice and qualifying: the lap
-- is struck off. Race: warnings, then a time penalty per excursion.
local function checkLimits(p: Player, session: RaceProgress.Race, mode: Mode, dt: number)
	local c = chassisOf(p)
	local racer = session.racers[p]
	if not (c and racer) or racer.finished or c.Anchored then
		return
	end
	local tr = limits[p]
	if not tr then
		tr = TrackLimits.newTracker()
		limits[p] = tr
	end
	local cf = c.CFrame
	local wheels: { TrackLimits.Wheel } = {}
	for _, w in Config.Kart.Wheels do
		local pos = cf.Position + cf.RightVector * w.x + cf.LookVector * w.f
		table.insert(wheels, { pos = vec(pos), half = w.width / 2 })
	end
	local hint = TrackLimits.locate(TrackMath, track, tr, vec(cf.Position))
	local out = TrackLimits.allOut(TrackMath, track, zones, hint, wheels)
	if not TrackLimits.step(tr, out, c.AssemblyLinearVelocity.Magnitude, dt) then
		return
	end
	if mode == "race" then
		local n = (warnings[p] or 0) + 1
		warnings[p] = n
		p:SetAttribute("Warnings", n)
		local added = 0
		if n > R.TrackLimitWarnings then
			added = R.TrackLimitPenalty
			penalties[p] = (penalties[p] or 0) + added
			p:SetAttribute("Penalty", penalties[p])
		end
		fire(p, "TrackLimits", { warnings = n, max = R.TrackLimitWarnings, added = added, penalty = penalties[p] or 0 })
	else
		local wasValid = not racer.lapInvalid and racer.lap >= 1
		session:invalidateLap(p)
		if wasValid then
			fire(p, "TrackLimits", { deleted = true })
		end
	end
end

----------------------------------------------------------------------------
-- Qualifying
----------------------------------------------------------------------------
local startGrid: (gridOrder: { Player }) -> ()

-- where one-lap qualifying starts: QualiRunUp studs before the line, in the
-- middle of the road (ghosts, so everyone can start from the same spot)
local function runUpPose(): (Vector3, Vector3, Vector3)
	local pos, fwd, up = TrackLayout.gridSlot(track, 1, { GridFirstRowBack = R.QualiRunUp, GridRowSpacing = 0, GridLateral = 0, GridStagger = 0 })
	return v3(pos), v3(fwd), v3(up)
end

local function qualiSlot(player: Player)
	local q = quali
	if not q then
		return
	end
	local racer = q.racers[player]
	local pos: vector?, fwd: vector?, up: vector?
	if racer then
		pos, fwd, up = q:resetPose(player)
	end
	if not (pos and fwd and up) then
		local p3, f3, u3 = runUpPose()
		pos, fwd, up = vec(p3), vec(f3), vec(u3)
	end
	local model = spawnKart(player, v3(pos :: vector), v3(fwd :: vector), v3(up :: vector), false)
	if model and not racer then
		q:addRacer(player, pos :: vector, now())
		limits[player] = TrackLimits.newTracker()
		splits[player] = 0
	end
	player:SetAttribute("InRace", model ~= nil)
end

local function startQualifying()
	local list = eligiblePlayers()
	if #list < minPlayers() then
		setState(idle())
		return
	end
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	for _, p in Players:GetPlayers() do
		removeKart(p)
		p:SetAttribute("InRace", false)
		p:SetAttribute("Finished", nil)
		p:SetAttribute("FinishTime", nil)
		p:SetAttribute("Position", nil)
		p:SetAttribute("Lap", nil)
		p:SetAttribute("GridSlot", nil)
		p:SetAttribute("QualiDone", nil)
	end
	resetTiming()
	-- one timed lap: the session's "finish" is the end of lap 1
	quali = newSession(1, now())
	qualiClosing = false
	workspace:SetAttribute("QualiClosing", false)
	workspace:SetAttribute("Podium", false)
	local duration = current.spec.Qualifying or R.QualifyingTime
	setState("Qualifying", duration)
	local pos, fwd, up = runUpPose()
	for slot, p in list do
		if slot > R.MaxRacers then
			break
		end
		if spawnKart(p, pos, fwd, up, false) then
			(quali :: RaceProgress.Race):addRacer(p, vec(pos), now())
			limits[p] = TrackLimits.newTracker()
			splits[p] = 0
			p:SetAttribute("InRace", true)
		end
	end
	fire(nil, "Qualifying", { duration = duration })
end

-- qualifying order: clean best laps first, then everyone without one
local function qualiOrder(): { RaceProgress.Racer }
	local q = quali
	local list: { RaceProgress.Racer } = {}
	if not q then
		return list
	end
	for _, id in q.order do
		table.insert(list, q.racers[id])
	end
	table.sort(list, function(a, b)
		if (a.bestLap ~= nil) ~= (b.bestLap ~= nil) then
			return a.bestLap ~= nil
		end
		if a.bestLap and b.bestLap then
			return a.bestLap < b.bestLap
		end
		return false
	end)
	return list
end

local function qualiPayload(): { any }
	local out = {}
	local leader: number? = nil
	for i, r in qualiOrder() do
		local p = r.id :: Player
		if i == 1 then
			leader = r.bestLap
		end
		table.insert(out, {
			userId = p.UserId,
			name = p.DisplayName,
			number = numbers[p] or 0,
			color = colorFor(p),
			best = r.bestLap,
			gap = if r.bestLap and leader and i > 1 then r.bestLap - leader else nil,
			laps = #r.lapTimes,
			finished = r.finished,
		})
	end
	return out
end

local function finishQualifying()
	local gridOrder: { Player } = {}
	for _, r in qualiOrder() do
		local p = r.id :: Player
		if p.Parent then
			table.insert(gridOrder, p)
		end
	end
	fire(nil, "QualiResult", { list = qualiPayload() })
	quali = nil
	qualiClosing = false
	workspace:SetAttribute("QualiClosing", false)
	startGrid(gridOrder)
end

----------------------------------------------------------------------------
-- Grid, race, podium
----------------------------------------------------------------------------
startGrid = function(gridOrder: { Player })
	local list: { Player } = {}
	for _, p in gridOrder do
		if p.Parent and alive(p) then
			table.insert(list, p)
		end
	end
	-- anyone who missed qualifying starts at the back
	local late: { Player } = {}
	for _, p in eligiblePlayers() do
		if not table.find(list, p) then
			table.insert(late, p)
		end
	end
	for i = #late, 2, -1 do
		local j = math.random(1, i)
		late[i], late[j] = late[j], late[i]
	end
	for _, p in late do
		table.insert(list, p)
	end
	if #list < minPlayers() then
		setState(idle())
		return
	end
	for _, p in Players:GetPlayers() do
		removeKart(p)
		p:SetAttribute("InRace", false)
		p:SetAttribute("Finished", nil)
		p:SetAttribute("FinishTime", nil)
		p:SetAttribute("Position", nil)
		p:SetAttribute("Lap", nil)
	end
	resetTiming()
	racers = {}
	setState("Grid", 2 + R.CountdownTime)
	workspace:SetAttribute("Laps", LAPS)
	workspace:SetAttribute("RaceStart", nil)
	workspace:SetAttribute("LightsStart", now() + 2)
	for slot, p in list do
		if slot > R.MaxRacers then
			break
		end
		local pos, fwd, up = slotPose(slot)
		if spawnKart(p, pos, fwd, up, true) then
			table.insert(racers, p)
			p:SetAttribute("InRace", true)
			p:SetAttribute("GridSlot", slot)
			p:SetAttribute("Position", slot)
		end
	end
	if #racers < 1 then
		setState(idle())
	end
end

local function lightsOut()
	-- F1 style: a short random hold after the fifth light
	task.wait(0.3 + math.random() * 0.9)
	if state ~= "Grid" then
		return
	end
	raceStart = now()
	finishDeadline = nil
	local r = newSession(LAPS, raceStart)
	race = r
	for _, p in racers do
		local k = karts[p]
		if k and k.PrimaryPart then
			r:addRacer(p, vec(k.PrimaryPart.Position), raceStart)
			limits[p] = TrackLimits.newTracker()
			k.PrimaryPart.Anchored = false
			KartFactory.handOver(k, p)
		end
	end
	setState("Racing", R.MaxRaceTime)
	workspace:SetAttribute("RaceStart", raceStart)
	fire(nil, "Go", { time = raceStart })
end

-- Final classification: finishers by time plus penalties, then the rest by
-- distance covered, retirements last.
local function classification(): { RaceProgress.Racer }
	local r = race
	if not r then
		return {}
	end
	local list = r:standings()
	local function total(x: RaceProgress.Racer): number
		return (x.finishTime :: number) + (penalties[x.id :: Player] or 0)
	end
	table.sort(list, function(a, b)
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished and b.finished then
			return total(a) < total(b)
		end
		if a.dnf ~= b.dnf then
			return not a.dnf
		end
		return a.progress > b.progress
	end)
	return list
end

local function standingsPayload(final: boolean): { any }
	local list = {}
	local r = race
	if not r then
		return list
	end
	local ordered: { RaceProgress.Racer } = if final then classification() else r:standings()
	local leader: RaceProgress.Racer? = nil
	for pos, racer in ordered do
		local p = racer.id :: Player
		if pos == 1 then
			leader = racer
		end
		local gap: number? = nil
		if leader and racer ~= leader and not racer.finished then
			gap = (leader.progress - racer.progress) -- studs behind the leader
		end
		table.insert(list, {
			userId = p.UserId,
			name = p.DisplayName,
			number = numbers[p] or 0,
			color = colorFor(p),
			lap = math.clamp(racer.lap, 1, LAPS),
			finished = racer.finished,
			dnf = racer.dnf,
			time = if racer.finishTime then racer.finishTime + (penalties[p] or 0) else nil,
			penalty = penalties[p],
			best = racer.bestLap,
			gap = gap,
		})
	end
	return list
end

-- The podium in the paddock (built by Scenery): its three steps.
local function podiumSteps(): { BasePart }
	local pits = current.folder:FindFirstChild("Pits")
	local podium = pits and pits:FindFirstChild("Podium")
	local steps: { BasePart } = {}
	if podium then
		for i = 1, 3 do
			local s = podium:FindFirstChild("Step" .. i)
			if s and s:IsA("BasePart") then
				steps[i] = s
			end
		end
	end
	return steps
end

-- confetti over the podium while the results are up
local function setConfetti(on: boolean)
	local pits = current.folder:FindFirstChild("Pits")
	local podium = pits and pits:FindFirstChild("Podium")
	local cannon = podium and podium:FindFirstChild("Confetti")
	if cannon then
		for _, e in cannon:GetChildren() do
			if e:IsA("ParticleEmitter") then
				e.Enabled = on
			end
		end
	end
end

local function endRace()
	local r = race
	if not r then
		setState(idle())
		return
	end
	for _, id in r.order do
		local racer = r.racers[id]
		if not racer.finished then
			racer.dnf = true
		end
	end
	local results = standingsPayload(true)
	local ordered = classification()
	local winner = ordered[1]
	if winner and winner.finished then
		Stats.addWin(winner.id :: Player)
	end
	fire(nil, "Results", { list = results })
	race = nil
	racers = {}
	-- podium: the top three finishers' karts on the steps, everyone else's away
	local steps = podiumSteps()
	local onPodium: { [Player]: boolean } = {}
	for place = 1, 3 do
		local racer = ordered[place]
		local step = steps[place]
		if racer and racer.finished and step then
			local p = racer.id :: Player
			local k = karts[p]
			if k then
				local top = step.Position + Vector3.new(0, step.Size.Y / 2, 0)
				KartFactory.place(k, nil, top, step.CFrame.LookVector, Vector3.new(0, 1, 0), true)
				onPodium[p] = true
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if not onPodium[p] then
			removeKart(p)
		end
		p:SetAttribute("InRace", false)
		p:SetAttribute("WrongWay", false)
		p:SetAttribute("OffCourse", false)
	end
	workspace:SetAttribute("Podium", #steps == 3)
	setConfetti(next(onPodium) ~= nil)
	setState("Results", R.ResultsTime)
	workspace:SetAttribute("RaceStart", nil)
	workspace:SetAttribute("FinishDeadline", nil)
end

local function startIntermission()
	resetVotes()
	workspace:SetAttribute("Podium", false)
	setState("Intermission", R.IntermissionTime)
end

----------------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------------
-- Another kart (centre) closer than ResetClear to `pos`, ignoring `own`
-- and karts on the other level of a crossing.
local function kartNear(pos: Vector3, own: Model?): boolean
	local clear = R.ResetClear
	for _, k in karts do
		local c = k.PrimaryPart
		if k ~= own and c then
			local d = c.Position - pos
			if math.abs(d.Y) < 5 and d.X * d.X + d.Z * d.Z < clear * clear then
				return true
			end
		end
	end
	return false
end

-- A reset pose near (pos, fwd, up) that no other kart is sitting on: the
-- point itself, then beside it, then a few samples further back.
local function clearPose(own: Model, pos: vector, fwd: vector, up: vector): (vector, vector, vector)
	local idx = TrackMath.nearest(track, pos)
	local back = math.max(1, math.floor(R.ResetClear / track.spacing + 0.5))
	for step = 0, 3 do
		local smp = track.samples[TrackMath.wrap(idx - step * back, track.n)]
		local p0, f0, u0 = pos, fwd, up
		if step > 0 then
			p0, f0, u0 = smp.pos, smp.fwd, smp.up
		end
		local right = vector.normalize(vector.cross(f0, u0))
		local side = math.clamp(smp.width / 2 - 4, 0, R.ResetClear)
		for _, s in { 0, 1, -1 } do
			local p = p0 + right * (side * s)
			if (s == 0 or side > 0) and not kartNear(v3(p), own) then
				return p, f0, u0
			end
		end
	end
	return pos, fwd, up
end

-- Reset karts (Ghost attribute) stay ghosts until no kart is near them.
local function updateGhosts(t: number)
	for k in ghostSince do
		if not k.Parent then
			ghostSince[k] = nil
		end
	end
	for _, k in karts do
		local c = k.PrimaryPart
		if c and k:GetAttribute("Ghost") then
			local since = ghostSince[k] or t
			ghostSince[k] = since
			if t - since >= R.ResetGhostTime and not kartNear(c.Position, k) then
				ghostSince[k] = nil
				k:SetAttribute("Ghost", nil)
			end
		end
	end
end

local function tick()
	local t = now()
	updateGhosts(t)
	local dt = math.clamp(t - lastTick, 0, 0.2)
	lastTick = t
	local attrDue = t - lastAttr > 0.2
	if attrDue then
		lastAttr = t
	end
	if state == "Racing" and race then
		local r = race :: RaceProgress.Race
		for _, p in racers do
			local c = chassisOf(p)
			if c and r.racers[p] then
				handleEvents(p, r:update(p, vec(c.Position), vec(c.AssemblyLinearVelocity), t), "race")
				checkLimits(p, r, "race", dt)
			end
		end
		if attrDue then
			for pos, racer in r:standings() do
				local p = racer.id :: Player
				p:SetAttribute("Position", pos)
				p:SetAttribute("Lap", math.clamp(racer.lap, 1, LAPS))
				p:SetAttribute("WrongWay", racer.wrongWay and not racer.finished)
				p:SetAttribute("OffCourse", not racer.onCourse and not racer.finished)
			end
		end
		if t - lastStandings > 0.5 then
			lastStandings = t
			fire(nil, "Standings", { mode = "race", list = standingsPayload(false) })
		end
		if r:allDone() or (finishDeadline and t > finishDeadline) or t > stateEnd or #r.order == 0 then
			endRace()
		end
	elseif state == "Qualifying" and quali then
		local q = quali :: RaceProgress.Race
		for _, id in table.clone(q.order) do
			local p = id :: Player
			local c = chassisOf(p)
			if c then
				handleEvents(p, q:update(p, vec(c.Position), vec(c.AssemblyLinearVelocity), t), "quali")
				checkLimits(p, q, "quali", dt)
				if attrDue then
					local racer = q.racers[p]
					p:SetAttribute("WrongWay", racer.wrongWay)
					p:SetAttribute("OffCourse", not racer.onCourse)
				end
			end
		end
		if t - lastStandings > 0.5 then
			lastStandings = t
			local payload = qualiPayload()
			for pos, e in payload do
				local p = Players:GetPlayerByUserId(e.userId)
				if p then
					p:SetAttribute("Position", pos)
				end
			end
			fire(nil, "Standings", { mode = "quali", list = payload })
		end
	elseif canPractice() then
		for p, pr in practice do
			local c = chassisOf(p)
			if c then
				handleEvents(p, pr:update(p, vec(c.Position), vec(c.AssemblyLinearVelocity), t), "practice")
				checkLimits(p, pr, "practice", dt)
				local racer = pr.racers[p]
				if racer and attrDue then
					p:SetAttribute("WrongWay", racer.wrongWay)
					p:SetAttribute("OffCourse", not racer.onCourse)
				end
			end
		end
	end
end

local function stateLoop()
	while true do
		local t = now()
		local count = #eligiblePlayers()
		workspace:SetAttribute("PlayerCount", count)
		checkHost()
		if state == "Lobby" then
			-- the menu: nothing runs here
		elseif state == "Practice" then
			-- only a quick race goes to the vote on its own; a room waits for
			-- its host's START, a practice server never races
			if serverMode == "race" and count >= R.MinPlayers then
				startIntermission()
			end
		elseif state == "Intermission" then
			if count < minPlayers() then
				setState(idle())
			elseif t >= stateEnd then
				switchTo(voteWinner())
				LAPS = lapsFor(current.spec, lengthWinner())
				resetVotes()
				startQualifying()
			end
		elseif state == "Qualifying" then
			local q = quali
			if count < minPlayers() or not q then
				quali = nil
				setState(idle())
			elseif not qualiClosing and #q.order > 0 and q:allDone() then
				-- everyone has done their lap
				finishQualifying()
			elseif not qualiClosing and t >= stateEnd then
				-- chequered flag: finish the lap you are on
				qualiClosing = true
				q:closeSession()
				workspace:SetAttribute("QualiClosing", true)
				setStateEnd(t + math.min(R.QualiOvertime, track.length / 40))
				fire(nil, "Chequered", {})
			elseif qualiClosing and (q:allDone() or t >= stateEnd) then
				finishQualifying()
			end
		elseif state == "Grid" then
			if #racers == 0 then
				setState(idle())
			elseif t >= stateEnd then
				lightsOut()
			end
		elseif state == "Results" then
			if t >= stateEnd then
				setConfetti(false)
				for _, p in Players:GetPlayers() do
					removeKart(p)
				end
				if serverMode == "race" and count >= R.MinPlayers then
					startIntermission()
				else
					-- a room goes back to its waiting room (everyone NOT READY
					-- again); a lone racer practises
					resetVotes()
					workspace:SetAttribute("Podium", false)
					setState(idle())
				end
				resetTiming()
				if canPractice() then
					for _, p in Players:GetPlayers() do
						if alive(p) then
							spawnPracticeKart(p)
						end
					end
				end
			end
		end
		-- practice: everyone who is alive and not driving gets a kart
		if canPractice() then
			for _, p in Players:GetPlayers() do
				local held = spawnHold[p] and os.clock() < spawnHold[p]
				if not held and not karts[p] and alive(p) and p:GetAttribute("WantsKart") ~= false then
					spawnPracticeKart(p)
				end
			end
		elseif state == "Qualifying" and not qualiClosing then
			-- late arrivals and respawned drivers join the session
			for _, p in Players:GetPlayers() do
				local held = spawnHold[p] and os.clock() < spawnHold[p]
				if not held and not karts[p] and alive(p) then
					qualiSlot(p)
				end
			end
		end
		task.wait(0.25)
	end
end

----------------------------------------------------------------------------
-- Requests from clients
----------------------------------------------------------------------------
local function onRequest(player: Player, kind: unknown, arg: unknown)
	if kind == "Vote" then
		-- practice: change the track now; intermission: a vote for the next race
		if type(arg) ~= "string" or not circuits[arg] then
			return
		end
		if state == "Practice" then
			if arg ~= current.id and now() - lastTrackChange > R.TrackChangeCooldown then
				switchTo(arg)
			end
		elseif state == "Lobby" and serverMode == "room" then
			-- the waiting room: only the host picks; the circuit itself is
			-- swapped in when they press START
			if isHost(player) then
				roomPick = arg
				workspace:SetAttribute("RoomTrack", arg)
				LAPS = lapsFor(circuits[arg].spec, roomLength)
				workspace:SetAttribute("Laps", LAPS)
			end
		elseif state == "Intermission" then
			votes[player] = arg
			player:SetAttribute("Vote", arg)
			publishVotes()
		end
	elseif kind == "Length" then
		if type(arg) ~= "string" or not table.find(LENGTHS, arg) then
			return
		end
		if state == "Intermission" then
			lengthVotes[player] = arg
			player:SetAttribute("LengthVote", arg)
			publishVotes()
		elseif state == "Lobby" and isHost(player) then
			roomLength = arg
			LAPS = lapsFor(circuits[roomPick or current.id].spec, arg)
			workspace:SetAttribute("RoomLength", arg)
			workspace:SetAttribute("Laps", LAPS)
		end
	elseif kind == "Start" then
		-- the room's host starts the race on the track and length they
		-- picked, once every guest is ready
		if state == "Lobby" and isHost(player) and guestsReady() then
			local pick = roomPick
			if pick and pick ~= current.id then
				switchTo(pick)
			end
			LAPS = lapsFor(current.spec, roomLength)
			workspace:SetAttribute("Laps", LAPS)
			resetVotes()
			startQualifying()
		end
	elseif kind == "Ready" then
		if state == "Intermission" then
			ready[player] = arg == true
			player:SetAttribute("Ready", arg == true)
			publishVotes()
			checkAllReady()
		elseif state == "Lobby" and serverMode == "room" and not isHost(player) then
			ready[player] = arg == true
			player:SetAttribute("Ready", arg == true)
			publishVotes()
		end
	elseif kind == "Kick" then
		-- the room's host removes a player (who cannot come back to this room)
		local target = if type(arg) == "number" then Players:GetPlayerByUserId(arg) else nil
		if serverMode == "room" and isHost(player) and target and target ~= player then
			kicked[target.UserId] = true
			ready[target] = nil
			target:SetAttribute("Ready", nil)
			publishVotes()
			local f = RaceManager.onKick
			if f then
				f(target, "The host removed you from the room")
			end
		end
	elseif kind == "Setting" then
		if type(arg) == "table" then
			local a = arg :: any
			Stats.setSetting(player, a.key, a.value)
		end
	elseif kind == "Reset" then
		local t = now()
		if lastReset[player] and t - lastReset[player] < R.ResetCooldown then
			return
		end
		local k = karts[player]
		if not k or state == "Grid" or state == "Results" then
			return
		end
		lastReset[player] = t
		local pos: vector?, fwd: vector?, up: vector?
		if state == "Racing" and race and race.racers[player] and not race.racers[player].finished then
			pos, fwd, up = race:resetPose(player)
		elseif state == "Qualifying" and quali and quali.racers[player] then
			pos, fwd, up = quali:resetPose(player)
		elseif practice[player] then
			pos, fwd, up = practice[player]:resetPose(player)
		end
		if not (pos and fwd and up) then
			local c = k.PrimaryPart
			if not c then
				return
			end
			local idx = TrackMath.nearest(track, vec(c.Position))
			local smp = track.samples[idx]
			pos, fwd, up = smp.pos, smp.fwd, smp.up
		end
		if pos and fwd and up then
			pos, fwd, up = clearPose(k, pos, fwd, up)
			KartFactory.place(k, player, v3(pos), v3(fwd), v3(up), false)
			if kartNear(v3(pos), k) then
				k:SetAttribute("Ghost", true)
				ghostSince[k] = nil
			end
		end
		fire(player, "Reset", {})
	elseif kind == "Kart" then
		-- toggle: leave the kart to walk around, or ask for one again (practice only)
		if not canPractice() then
			return
		end
		if karts[player] then
			player:SetAttribute("WantsKart", false)
			removeKart(player)
		else
			player:SetAttribute("WantsKart", true)
			if alive(player) then
				spawnPracticeKart(player)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Players and characters
----------------------------------------------------------------------------
local function onCharacter(player: Player, character: Model)
	spawnHold[player] = os.clock() + 1.5
	KartFactory.setCharacterParts(character, "Players", false)
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			local seated = karts[player] and true or false
			d.CollisionGroup = if seated then "Drivers" else "Players"
			d.Massless = seated
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		removeKart(player)
	end)
	freeze(player, state == "Lobby")
	task.wait(0.5)
	if player.Parent == nil or player.Character ~= character then
		return
	end
	-- back into the session after a respawn
	if state == "Racing" and race and race.racers[player] and not race.racers[player].finished then
		local pos, fwd, up = race:resetPose(player)
		if pos and fwd and up then
			spawnKart(player, v3(pos), v3(fwd), v3(up), false)
		end
	elseif state == "Qualifying" and not qualiClosing then
		qualiSlot(player)
	elseif canPractice() and player:GetAttribute("WantsKart") ~= false then
		spawnPracticeKart(player)
	end
end

local function onPlayer(player: Player)
	if serverMode == "room" and kicked[player.UserId] then
		local f = RaceManager.onKick
		if f then
			task.defer(f, player, "You were removed from this room")
		end
	end
	numberFor(player)
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local function onLeave(player: Player)
	removeKart(player)
	if race then
		race:removeRacer(player)
	end
	if quali then
		quali:removeRacer(player)
	end
	local i = table.find(racers, player)
	if i then
		table.remove(racers, i)
	end
	numbers[player] = nil
	lastReset[player] = nil
	spawnHold[player] = nil
	votes[player] = nil
	lengthVotes[player] = nil
	ready[player] = nil
	limits[player] = nil
	bests[player] = nil
	splits[player] = nil
	publishVotes()
	task.defer(checkAllReady)
end

-- A circuit built after start-up (it waits in ServerStorage until voted in).
function RaceManager.addCircuit(c: Circuit)
	if circuits[c.id] then
		return
	end
	circuits[c.id] = c
	table.insert(order, c.id)
	if c ~= current then
		c.folder.Name = c.id
		c.folder.Parent = storage
	end
	publishTracks()
	if wantTrack == c.id then
		wantTrack = nil
		if state == "Practice" or state == "Lobby" then
			switchTo(c.id)
		end
	end
end

-- What this server is for now. Called once at start-up; in Studio (no
-- teleports) again whenever the menu sends everyone somewhere else.
function RaceManager.setMode(role: Role)
	local m: ServerMode = role.mode
	serverMode = m :: ServerMode
	quali, race = nil, nil
	racers = {}
	qualiClosing = false
	finishDeadline = nil
	table.clear(practice)
	for _, p in Players:GetPlayers() do
		removeKart(p)
		for _, a in { "InRace", "Finished", "FinishTime", "Position", "Lap", "GridSlot", "WrongWay", "OffCourse", "QualiDone", "WantsKart" } do
			p:SetAttribute(a, nil)
		end
		spawnHold[p] = os.clock() + 1
		freeze(p, m == "lobby" or m == "room")
	end
	resetVotes()
	resetTiming()
	setConfetti(false)
	for _, a in { "QualiClosing", "FinishDeadline", "RaceStart", "LightsStart" } do
		workspace:SetAttribute(a, nil)
	end
	workspace:SetAttribute("Podium", false)
	if roomCode ~= (if m == "room" then role.code else nil) then
		table.clear(kicked)
	end
	roomCode = if m == "room" then role.code else nil
	roomHost = if m == "room" then role.host else nil
	roomLength = "Normal"
	workspace:SetAttribute("ServerMode", m)
	workspace:SetAttribute("RoomCode", roomCode)
	workspace:SetAttribute("RoomLength", if m == "room" then roomLength else nil)
	checkHost()
	workspace:SetAttribute("MinPlayers", minPlayers())
	wantTrack = nil
	local want = role.track
	if want and want ~= current.id then
		if circuits[want] then
			switchTo(want)
		else
			wantTrack = want
		end
	end
	LAPS = lapsFor(current.spec, roomLength)
	workspace:SetAttribute("Laps", LAPS)
	setState(idle())
	print(string.format("[A1KartRacing] server mode: %s%s", m, if roomCode then " " .. roomCode else ""))
end

function RaceManager.mode(): ServerMode
	return serverMode
end

-- `first` is the circuit already in workspace; `role` what this server is for.
function RaceManager.start(first: Circuit, remotes: Folder, role: Role?)
	local existing = ServerStorage:FindFirstChild("Circuits")
	if existing and existing:IsA("Folder") then
		storage = existing
	else
		local f = Instance.new("Folder")
		f.Name = "Circuits"
		f.Parent = ServerStorage
		storage = f
	end
	circuits[first.id] = first
	table.insert(order, first.id)
	activate(first)
	publishTracks()
	kartFolder = Instance.new("Folder")
	kartFolder.Name = "Karts"
	kartFolder.Parent = workspace
	raceEvent = remotes:WaitForChild("RaceEvent") :: RemoteEvent
	local request = remotes:WaitForChild("Request") :: RemoteEvent
	request.OnServerEvent:Connect(onRequest)

	RaceManager.setMode(role or { mode = "race" })

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(onLeave)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	lastTick = now()
	RunService.Heartbeat:Connect(tick)
	task.spawn(stateLoop)
end

return RaceManager
