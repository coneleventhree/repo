-- Race logic tests (laps, positions, shortcuts, wrong way).
-- Run from the project root:  luau tests/race_test.luau
local TrackMath = require("../src/shared/TrackMath")
local TrackData = require("../src/shared/TrackData")
local RaceProgress = require("../src/shared/RaceProgress")
local Config = require("../src/shared/Config")

local pass, total = 0, 0
local function check(ok: boolean, label: string)
	total += 1
	if ok then
		pass += 1
	end
	print(string.format("%-4s %s", if ok then "PASS" else "FAIL", label))
	return ok
end

local track = TrackMath.build(TrackData.get())
local L = track.length
local LAPS = 3
local ALLOW = Config.Race.OffTrackAllowance

-- point on the centre line at unwrapped distance d (+ sideways offset)
local function at(d: number, side: number?): (vector, vector)
	local s = d % L
	local i = TrackMath.wrap(math.floor(s / track.spacing) + 1, track.n)
	local a = track.samples[i]
	local b = track.samples[TrackMath.wrap(i + 1, track.n)]
	local f = math.clamp((s - a.s) / track.spacing, 0, 1)
	local p = a.pos + (b.pos - a.pos) * f
	return p + a.right * (side or 0), a.fwd
end

----------------------------------------------------------------------------
print("== Two racers, three laps ==")
do
	local race = RaceProgress.new(TrackMath, track, LAPS, ALLOW, 0)
	local pA = at(-12)
	local pB = at(-26)
	local a = race:addRacer("A", pA, 0)
	local b = race:addRacer("B", pB, 0)
	check(math.abs(a.progress + 12) < 1 and math.abs(b.progress + 26) < 1, string.format("grid progress %.1f / %.1f", a.progress, b.progress))
	local events = { A = {}, B = {} }
	local dt = 1 / 60
	local t = 0
	local midChecked = false
	while not race:allDone() and t < 200 do
		t += dt
		for id, speed in { A = 60, B = 50 } do
			local r = race.racers[id]
			local start = if id == "A" then -12 else -26
			local p, f = at(start + speed * t, if id == "A" then 3 else -3)
			for _, e in race:update(id, p, f * speed, t) do
				table.insert(events[id], e)
			end
		end
		if not midChecked and t > 20 then
			midChecked = true
			local st = race:standings()
			check(st[1].id == "A", "faster racer leads mid-race")
		end
	end
	local function kinds(list)
		local out = {}
		for _, e in list do
			table.insert(out, e.kind .. (e.lap and tostring(e.lap) or ""))
		end
		return table.concat(out, ",")
	end
	check(kinds(events.A) == "start,lap1,lap2,finish3", "A events: " .. kinds(events.A))
	local st = race:standings()
	check(st[1].id == "A" and st[2].id == "B", "finish order A, B")
	local expectA = (LAPS * L + 12) / 60
	check(math.abs((a.finishTime :: number) - expectA) < 0.02, string.format("A finish time %.3f (expect %.3f)", a.finishTime :: number, expectA))
	check(#a.lapTimes == 3 and math.abs(a.lapTimes[2] - L / 60) < 0.02, string.format("A lap time %.3f (expect %.3f)", a.lapTimes[2] or -1, L / 60))
	check(math.abs((b.bestLap :: number) - L / 50) < 0.02, string.format("B best lap %.3f", b.bestLap :: number))
end

----------------------------------------------------------------------------
print("== Shortcut across the hairpin infield ==")
do
	local race = RaceProgress.new(TrackMath, track, LAPS, ALLOW, 0)
	local r = race:addRacer("C", at(-10), 0)
	local t = 0
	local dt = 1 / 30
	local speed = 50
	-- drive normally to sample 101 (hairpin approach)
	local entryS = track.samples[101].s
	local d = -10
	while d < entryS do
		t += dt
		d += speed * dt
		local p, f = at(d)
		race:update("C", p, f * speed, t)
	end
	local before = r.progress
	-- cut straight across to sample 141 (other side of the hairpin)
	local from = track.samples[101].pos
	local to = track.samples[141].pos
	local dist = vector.magnitude(to - from)
	local steps = math.floor(dist / (speed * dt))
	for k = 1, steps do
		t += dt
		local p = from + (to - from) * (k / steps)
		race:update("C", p, vector.normalize(to - from) * speed, t)
	end
	local cutGain = r.progress - before
	check(cutGain < dist * 1.5, string.format("cut gains %.0f studs of progress for %.0f studs driven (lap distance skipped %.0f)", cutGain, dist, track.samples[141].s - track.samples[101].s))
	-- keep driving forward from the exit: no progress while off the accepted line
	local exitS = track.samples[141].s
	for k = 1, 120 do
		t += dt
		local p, f = at(exitS + k * speed * dt)
		race:update("C", p, f * speed, t)
	end
	check(r.progress < track.samples[141].s - 40, string.format("stuck behind until they go back (progress %.0f)", r.progress))
	local rp = race:resetPose("C")
	check(rp ~= nil and vector.magnitude((rp :: vector) - track.samples[r.idx].pos) < 0.01, "reset pose is the last valid point")
	-- after a reset there, driving the real line works again
	local d2 = r.progress
	local p0 = r.progress
	for k = 1, 300 do
		t += dt
		d2 += speed * dt
		local p, f = at(d2)
		race:update("C", p, f * speed, t)
	end
	check(r.progress > p0 + 300 * speed * dt * 0.9, string.format("progress resumes after reset (+%.0f)", r.progress - p0))
end

----------------------------------------------------------------------------
print("== Inside line through the hairpin ==")
do
	-- hug the inside kerb (right side, hairpin is a right-hander) all the way round
	local race = RaceProgress.new(TrackMath, track, LAPS, ALLOW, 0)
	local r = race:addRacer("D", at(-10), 0)
	local t, dt, speed = 0, 1 / 60, 40
	local hs, he = track.samples[100].s, track.samples[145].s
	local d = -10
	local lastP = at(-10)
	while d < he + 50 do
		t += dt
		local side = if d > hs and d < he then track.samples[2].width * 0.45 * 0.9 else 0
		local p = at(d, side)
		-- advance the centre-line parameter so the real path speed is `speed`
		local nextP = at(d + 1, side)
		local stepLen = math.max(vector.magnitude(nextP - p), 0.2)
		d += speed * dt / stepLen
		race:update("D", p, (nextP - p) / stepLen * speed, t)
		lastP = p
	end
	check(r.progress > he, string.format("inside line is never treated as a shortcut (progress %.0f, want > %.0f)", r.progress, he))
end

----------------------------------------------------------------------------
print("== Wrong way and crossing the line backwards ==")
do
	local race = RaceProgress.new(TrackMath, track, LAPS, ALLOW, 0)
	local r = race:addRacer("E", at(-10), 0)
	local t, dt = 0, 1 / 60
	local d = -10
	local evs = {}
	local function drive(to: number, speed: number)
		local dir = if to > d then 1 else -1
		while (to - d) * dir > 0 do
			t += dt
			d += dir * speed * dt
			local p, f = at(d)
			for _, e in race:update("E", p, f * speed * dir, t) do
				table.insert(evs, e.kind)
			end
		end
	end
	drive(L + 30, 60) -- start + lap 1
	drive(L - 30, 20) -- reverse back over the line
	check(r.wrongWay, "wrong-way flag while driving backwards")
	drive(L + 60, 60) -- forwards again
	check(not r.wrongWay, "flag clears going forwards")
	check(table.concat(evs, ",") == "start,lap", "crossing the line again does not count a second lap: " .. table.concat(evs, ","))
	check(#r.lapTimes == 1, "one lap time recorded")
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
