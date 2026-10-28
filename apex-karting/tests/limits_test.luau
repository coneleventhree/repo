-- Track limits and sector splits: which wheel positions count as off track,
-- how excursions become violations, struck-off laps, sector events and the
-- chequered flag of a timed session.
-- Run from the project root:  luau tests/limits_test.luau
local TrackMath = require("../src/shared/TrackMath")
local TrackData = require("../src/shared/TrackData")
local TrackLayout = require("../src/shared/TrackLayout")
local TrackLimits = require("../src/shared/TrackLimits")
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
local grid = TrackLayout.grid(track)
local zones = TrackLayout.zones(track, grid)
local wheelsCfg = Config.Kart.Wheels

-- the four tyre contact points of a kart standing at sample i, `lateral`
-- studs right of the centre line
local function wheelsAt(i: number, lateral: number): { TrackLimits.Wheel }
	local smp = track.samples[i]
	local centre = smp.pos + smp.right * lateral
	local out = {}
	for _, w in wheelsCfg do
		table.insert(out, { pos = centre + smp.right * w.x + smp.fwd * w.f, half = w.width / 2 })
	end
	return out
end

-- a sample on a straight and one in a corner with a kerb on the outside
local straight = 10
local cornerI, cornerSide = nil, 0
for i = 1, track.n do
	if zones[i].left.kerb > 0 and zones[i].right.kerb == 0 then
		cornerI, cornerSide = i, -1
		break
	end
end
assert(cornerI, "no kerbed corner found")
local half = track.samples[straight].width / 2
local widest = 0
for _, w in wheelsCfg do
	widest = math.max(widest, math.abs(w.x) + w.width / 2)
end

print("== Which positions are off track ==")
check(not TrackLimits.allOut(TrackMath, track, zones, straight, wheelsAt(straight, 0)), "centre of the road: on track")
check(not TrackLimits.allOut(TrackMath, track, zones, straight, wheelsAt(straight, half)), "straddling the edge: on track")
check(not TrackLimits.allOut(TrackMath, track, zones, straight, wheelsAt(straight, half + widest - 0.2)), "one tyre edge still on the line: on track")
check(TrackLimits.allOut(TrackMath, track, zones, straight, wheelsAt(straight, half + widest + 0.5)), "all four tyres past the edge (no kerb): off")
check(TrackLimits.allOut(TrackMath, track, zones, straight, wheelsAt(straight, -(half + widest + 0.5))), "same on the other side")
local cw = track.samples[cornerI].width / 2
local kerb = TrackLayout.KerbWidth
check(not TrackLimits.allOut(TrackMath, track, zones, cornerI, wheelsAt(cornerI, cornerSide * (cw + widest + 0.5))), "beyond the white line but on the kerb: on track")
check(TrackLimits.allOut(TrackMath, track, zones, cornerI, wheelsAt(cornerI, cornerSide * (cw + kerb + widest + 0.6))), "beyond the kerb: off")

print("== Following the kart round the lap ==")
do
	local tr = TrackLimits.newTracker()
	local n = track.n
	local ok = true
	for i = 1, n, 3 do
		local smp = track.samples[i]
		if TrackLimits.locate(TrackMath, track, tr, smp.pos + smp.right * 2) ~= i then
			ok = false
		end
	end
	check(ok, "locate follows a kart driving a whole lap")
	-- a jump far ahead (reset, respawn, a teleport): found again at once
	local far = (tr.idx :: number + math.floor(n / 2) - 1) % n + 1
	local smp = track.samples[far]
	check(TrackLimits.locate(TrackMath, track, tr, smp.pos) == far, "a jump half a lap away is found straight away")
	-- the race's own position held still (a rejected cut) must not matter:
	-- on the road, ten samples past a stale race index, the kart is on track
	local stale = 40
	local here = stale + 30
	local tr2 = TrackLimits.newTracker()
	tr2.idx = stale
	local hint = TrackLimits.locate(TrackMath, track, tr2, track.samples[here].pos)
	check(hint == here and not TrackLimits.allOut(TrackMath, track, zones, hint, wheelsAt(here, 0)), "on the road thirty samples past a stale hint: on track")
	check(TrackLimits.allOut(TrackMath, track, zones, stale, wheelsAt(here, 0)), "(using the stale hint directly would have called it off track)")
end

print("== Excursions ==")
do
	local tr = TrackLimits.newTracker()
	local hits = 0
	local function feed(out: boolean, speed: number, seconds: number)
		for _ = 1, math.floor(seconds * 60) do
			if TrackLimits.step(tr, out, speed, 1 / 60) then
				hits += 1
			end
		end
	end
	feed(true, 60, 0.1)
	check(hits == 0, "a brush under 0.2 s does not count")
	feed(true, 60, 1.0)
	check(hits == 1, "a real excursion counts once")
	feed(false, 60, 0.2)
	feed(true, 60, 0.5)
	check(hits == 1, "flickering back in for a moment is the same excursion")
	feed(false, 60, 0.6)
	feed(true, 60, 0.5)
	check(hits == 2, "after 0.4 s back on track the next one counts")
	feed(false, 60, 1)
	feed(true, 3, 2)
	check(hits == 2, "crawling about in the grass after a spin does not count")
end

print("== Sectors, struck-off laps, chequered flag ==")
do
	local race = RaceProgress.new(TrackMath, track, 1e9, 60, 0)
	race:setSectors({ 1 / 3, 2 / 3 })
	local pos = TrackMath.slot(track, 1, 0, 10)
	race:addRacer("a", pos, 0)
	local t = 0
	local events = {}
	local function driveTo(i: number, dt: number)
		t += dt
		for _, e in race:update("a", track.samples[i].pos, track.samples[i].fwd * 60, t) do
			table.insert(events, e)
		end
	end
	local function lap(invalidAt: number?)
		for i = 1, track.n, 2 do
			driveTo(i, 0.1)
			if invalidAt and i == invalidAt then
				race:invalidateLap("a")
			end
		end
	end
	lap() -- first crossing starts the timer partway into this
	lap(101)
	lap()
	local kinds, sectors, laps = {}, 0, {}
	for _, e in events do
		kinds[e.kind] = (kinds[e.kind] or 0) + 1
		if e.kind == "sector" then
			sectors += 1
		elseif e.kind == "lap" then
			table.insert(laps, e)
		end
	end
	check(kinds.start == 1, "timer starts at the first crossing")
	check(sectors >= 4 and sectors % 2 == 0, string.format("two splits per timed lap (%d)", sectors))
	local flagged = 0
	for _, e in laps do
		if e.invalid then
			flagged += 1
		end
	end
	check(#laps >= 2 and flagged == 1, string.format("the struck-off lap is flagged, the others are clean (%d of %d)", flagged, #laps))
	local r = race.racers.a
	check(r.bestLap ~= nil and #r.lapTimes == #laps - 1, string.format("only clean laps are kept (%d of %d)", #r.lapTimes, #laps))
	-- chequered flag halfway round: the lap in progress still counts
	for i = 1, math.floor(track.n / 2), 2 do
		driveTo(i, 0.1)
	end
	local before = #r.lapTimes
	race:closeSession()
	race:addRacer("late", pos, t)
	local finished = false
	for i = math.floor(track.n / 2) + 1, track.n, 2 do
		driveTo(i, 0.1)
	end
	driveTo(1, 0.1)
	driveTo(3, 0.1)
	finished = r.finished
	check(finished and #r.lapTimes == before + 1, string.format("after the flag the lap in progress is finished and counted (%d -> %d laps)", before, #r.lapTimes))
	check(race.racers.late.finished and race:allDone(), "a driver who joins after the flag is done at once")
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
