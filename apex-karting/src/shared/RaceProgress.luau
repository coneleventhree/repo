--!strict
-- Lap counting, positions and lap times. Pure Luau so it is unit-tested
-- headlessly; the server feeds it kart positions every frame.
--
-- Progress is the distance driven along the centre line, unwrapped across
-- laps: negative on the grid, 0 at the first crossing of the line, and
-- Laps * length at the finish. It only advances when
--   * the kart is within the road width plus an allowance of the centre line,
--   * the nearest sample is inside a window ahead of the last accepted one, and
--   * the gain is plausible for the distance actually driven since the last
--     accepted update (so cutting across the infield does not count).
-- A racer who leaves the course stays at their last valid point until they
-- come back (or press reset, which puts them there).
--
-- Also: sector splits (setSectors), laps struck off for track limits
-- (invalidateLap: the lap still counts for distance but not as a time) and
-- the chequered flag of a timed session (closeSession: everyone finishes
-- the lap they are on).

-- TrackMath is passed in (RaceProgress.new) so this module has no requires
-- and runs unchanged in Roblox and in the Luau CLI tests.
type Sample = {
	i: number,
	s: number,
	pos: vector,
	fwd: vector,
	right: vector,
	up: vector,
	width: number,
	bank: number,
	curv: number,
	segment: number,
}
type Track = {
	samples: { Sample },
	n: number,
	length: number,
	spacing: number,
	freeLengths: { number },
}
type TrackMath = {
	nearest: (Track, vector, number?, number?, number?) -> (number, number, number),
	arcDelta: (Track, number, number) -> number,
}

local RaceProgress = {}
RaceProgress.__index = RaceProgress

local WINDOW_BACK = 10
local WINDOW_AHEAD = 45
local GAIN_FACTOR = 1.35 -- allowed track distance per stud actually driven
local GAIN_SLACK = 10 -- plus this much per update (inside lines are shorter)

export type Racer = {
	id: any,
	idx: number, -- last accepted nearest sample
	s: number, -- last accepted arc position on the lap
	progress: number, -- unwrapped
	lastPos: vector?,
	lastTime: number,
	budget: number, -- distance driven since the last accepted update
	onCourse: boolean,
	wrongWayTime: number,
	wrongWay: boolean,
	lap: number, -- 1-based lap being driven (0 = not started)
	crossed: number, -- highest line crossing counted (k * length), -1 = none
	lapStart: number?,
	lapTimes: { number },
	bestLap: number?,
	finished: boolean,
	finishTime: number?,
	dnf: boolean,
	lapInvalid: boolean, -- the lap being driven is struck off (track limits)
	sector: number, -- sector splits passed on the current lap
	finishAt: number?, -- line crossing that ends this racer's session (closeSession)
}

-- kind: "start" (first crossing), "sector" (split `index`, `time` since the
-- lap started), "lap" (`time` = lap time, `invalid` if struck off),
-- "finish" (race: `time` since the start; timed session: the last lap).
export type Event = { kind: "lap" | "finish" | "start" | "sector", racer: Racer, time: number?, lap: number?, index: number?, invalid: boolean?, lapTime: number? }

export type Race = typeof(setmetatable(
	{} :: {
		tm: TrackMath,
		track: Track,
		laps: number,
		allowance: number,
		racers: { [any]: Racer },
		order: { any },
		startTime: number,
		finishCount: number,
		sectors: { number },
		closed: boolean,
	},
	RaceProgress
))

function RaceProgress.new(tm: TrackMath, track: Track, laps: number, allowance: number, startTime: number): Race
	return setmetatable({
		tm = tm,
		track = track,
		laps = laps,
		allowance = allowance,
		racers = {},
		order = {},
		startTime = startTime,
		finishCount = 0,
		sectors = {},
		closed = false,
	}, RaceProgress)
end

-- Sector split points as fractions of the lap, e.g. { 1/3, 2/3 }.
function RaceProgress.setSectors(self: Race, fractions: { number })
	self.sectors = table.clone(fractions)
	table.sort(self.sectors)
end

-- Strikes off the lap the racer is on (it will not count as a time).
function RaceProgress.invalidateLap(self: Race, id: any)
	local r = self.racers[id]
	if r and r.lap >= 1 then
		r.lapInvalid = true
	end
end

-- Chequered flag for a timed session: everyone finishes the lap they are
-- on; racers who have not started a lap are done straight away.
function RaceProgress.closeSession(self: Race)
	self.closed = true
	for _, id in self.order do
		local r = self.racers[id]
		if not r.finished then
			if r.lap >= 1 then
				r.finishAt = r.lap
			else
				r.finished = true
				self.finishCount += 1
			end
		end
	end
end

-- Registers a racer standing at `pos` (normally a grid slot behind the line).
function RaceProgress.addRacer(self: Race, id: any, pos: vector, now: number): Racer
	local track, TrackMath = self.track, self.tm
	local idx, _, s = TrackMath.nearest(track, pos)
	local racer: Racer = {
		id = id,
		idx = idx,
		s = s,
		progress = TrackMath.arcDelta(track, s, 0), -- e.g. -20 for 20 studs behind the line
		lastPos = pos,
		lastTime = now,
		budget = 0,
		onCourse = true,
		wrongWayTime = 0,
		wrongWay = false,
		lap = 0,
		crossed = -1,
		lapStart = nil,
		lapTimes = {},
		bestLap = nil,
		finished = self.closed,
		finishTime = nil,
		dnf = false,
		lapInvalid = false,
		sector = 0,
		finishAt = nil,
	}
	self.racers[id] = racer
	table.insert(self.order, id)
	return racer
end

function RaceProgress.removeRacer(self: Race, id: any)
	self.racers[id] = nil
	local i = table.find(self.order, id)
	if i then
		table.remove(self.order, i)
	end
end

local function crossTime(p0: number, p1: number, t0: number, t1: number, target: number): number
	if p1 == p0 then
		return t1
	end
	return t0 + (t1 - t0) * math.clamp((target - p0) / (p1 - p0), 0, 1)
end

-- Feed one position sample. `vel` is used for the wrong-way warning.
-- Returns a list of events (lap completed, finished).
function RaceProgress.update(self: Race, id: any, pos: vector, vel: vector, now: number): { Event }
	local events: { Event } = {}
	local r = self.racers[id]
	if not r or r.finished or r.dnf then
		return events
	end
	local track, TrackMath = self.track, self.tm
	local L = track.length
	local dt = math.max(now - r.lastTime, 1e-3)

	if r.lastPos then
		local moved = vector.magnitude(pos - r.lastPos)
		-- ignore teleports (resets) when budgeting
		r.budget += math.min(moved, 200 * dt + 5)
	end
	r.lastPos = pos
	r.lastTime = now

	local idx, lateral, s = TrackMath.nearest(track, pos, r.idx, WINDOW_BACK, WINDOW_AHEAD)
	local smp = track.samples[idx]
	local rel = pos - smp.pos
	local vertical = math.abs(vector.dot(rel, smp.up))
	local along = math.abs(vector.dot(rel, smp.fwd))
	-- the nearest sample in the window must really be near (not just level
	-- with the kart sideways while the kart is far past the window's end)
	r.onCourse = math.abs(lateral) <= smp.width / 2 + self.allowance and along <= 3 * track.spacing and vertical < 40

	-- wrong way: moving against the track direction for a while
	local speed = vector.magnitude(vel)
	if speed > 8 and vector.dot(vel, smp.fwd) < -0.4 * speed then
		r.wrongWayTime += dt
	else
		r.wrongWayTime = math.max(r.wrongWayTime - dt * 2, 0)
	end
	r.wrongWay = r.wrongWayTime > 1.2

	if not r.onCourse then
		return events
	end
	local delta = TrackMath.arcDelta(track, s, r.s)
	if delta > r.budget * GAIN_FACTOR + GAIN_SLACK then
		return events -- too far for the distance driven: a shortcut
	end
	local p0 = r.progress
	local p1 = p0 + delta
	r.idx, r.s, r.progress = idx, s, p1
	r.budget = 0

	-- sector splits on the lap being driven (before its line crossing)
	if delta > 0 and r.lapStart and #self.sectors > 0 and r.lap >= 1 then
		local lapBase = (r.lap - 1) * L
		for j = r.sector + 1, #self.sectors do
			local at = lapBase + self.sectors[j] * L
			if p0 < at and p1 >= at then
				r.sector = j
				local t = crossTime(p0, p1, now - dt, now, at)
				table.insert(events, { kind = "sector", racer = r, index = j, time = t - (r.lapStart :: number), lap = r.lap })
			elseif p1 < at then
				break
			end
		end
	end

	-- crossing lap boundaries (k * L for k = 0 .. laps)
	if delta > 0 then
		local limit = math.min(r.finishAt or self.laps, self.laps)
		local kFirst = math.floor(p0 / L) + 1
		local kLast = math.floor(p1 / L)
		for k = math.max(kFirst, r.crossed + 1, 0), math.min(kLast, limit) do
			r.crossed = k
			local t = crossTime(p0, p1, now - dt, now, k * L)
			if k == 0 then
				r.lap = 1
				r.lapStart = t
				r.sector = 0
				r.lapInvalid = false
				table.insert(events, { kind = "start", racer = r, time = t })
			else
				local lt: number? = nil
				local invalid = r.lapInvalid
				if r.lapStart then
					lt = t - (r.lapStart :: number)
					if not invalid then
						table.insert(r.lapTimes, lt :: number)
						if not r.bestLap or (lt :: number) < (r.bestLap :: number) then
							r.bestLap = lt
						end
					end
				end
				r.lapInvalid = false
				r.sector = 0
				if k >= limit then
					r.finished = true
					r.finishTime = t - self.startTime
					self.finishCount += 1
					table.insert(events, { kind = "finish", racer = r, time = r.finishTime, lap = k, lapTime = lt, invalid = invalid })
					break
				end
				r.lap = k + 1
				r.lapStart = t
				table.insert(events, { kind = "lap", racer = r, time = lt, lap = k, invalid = invalid })
			end
		end
	end
	return events
end

-- Pose to reset a racer to: the last accepted point on the centre line.
function RaceProgress.resetPose(self: Race, id: any): (vector?, vector?, vector?)
	local r = self.racers[id]
	if not r then
		return nil
	end
	local smp = self.track.samples[r.idx]
	r.lastPos = nil -- the teleport must not eat or add budget
	return smp.pos, smp.fwd, smp.up
end

-- Racers in race order: finishers by time (plus `penalties[id]` seconds, if
-- given), then the rest by distance covered. DNFs last. Every list the
-- players see (standings, positions, the finish message, results, podium)
-- uses this, so they cannot disagree about who is where.
function RaceProgress.standings(self: Race, penalties: { [any]: number }?): { Racer }
	local list: { Racer } = {}
	for _, id in self.order do
		table.insert(list, self.racers[id])
	end
	local pen = penalties or {}
	local function total(x: Racer): number
		return (x.finishTime :: number) + (pen[x.id] or 0)
	end
	table.sort(list, function(a, b)
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished and b.finished then
			local ta, tb = total(a), total(b)
			if ta ~= tb then
				return ta < tb
			end
			return (a.finishTime :: number) < (b.finishTime :: number)
		end
		if a.dnf ~= b.dnf then
			return not a.dnf
		end
		return a.progress > b.progress
	end)
	return list
end

function RaceProgress.allDone(self: Race): boolean
	for _, id in self.order do
		local r = self.racers[id]
		if not r.finished and not r.dnf then
			return false
		end
	end
	return true
end

return RaceProgress
