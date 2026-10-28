-- Ride smoothness: an autopilot lap of a circuit, measuring how much the
-- chassis shakes (pitch / roll rate and vertical acceleration minus their
-- 0.15 s moving average, i.e. the jitter a driver feels as "rattling").
--   luau tests/tools/ride.luau -a "Hillside [fps] [plain | fold]"
--   luau tests/tools/ride.luau -a "Hillside 60 plain"   (two triangles per quad, as before)
--   luau tests/tools/ride.luau -a "Hillside 60 0.05"    (another TrackLayout.RoadFold)
local Config = require("../../src/shared/Config")
local TrackData = require("../../src/shared/TrackData")
local TrackMath = require("../../src/shared/TrackMath")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local TrackLayout = require("../../src/shared/TrackLayout")

local args = {}
for w in string.gmatch((...) or "", "[^%s]+") do
	table.insert(args, w)
end
local spec = TrackData.get(args[1])
local fps = tonumber(args[2]) or 60

-- SPACING env-style 5th word: build with another sample spacing (experiments)
if args[4] and tonumber(args[4]) then
	spec = table.clone(spec)
	spec.Spacing = tonumber(args[4])
end
local track = TrackMath.build(spec)
local cfg = Config.Kart
-- lat "plain": the old two triangles per quad; a number: RoadFold for the
-- game's adaptive split (default: the game's own value)
local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
if args[3] == "plain" then
	g.plainRoad = true
elseif tonumber(args[3]) then
	TrackLayout.RoadFold = tonumber(args[3]) :: number
end
g:addTrack(track, nil, nil, 20)

local pos, fwd = TrackMath.slot(track, 1, 0, 20)
local sim = Sim.spawnOn(g, pos.x, pos.z, fwd, nil, fps)
local plan = Sim.speedPlan(track, cfg, 0.85)
local hint = 1
local lap, passedHalf = 0, false
local rec: { { idx: number, pitch: number, roll: number, vy: number } } = {}
sim:run(400, function()
	local idx = sim:autopilot(track, plan, hint)
	hint = idx
	if idx > track.n / 2 and idx < track.n * 0.6 then
		passedHalf = true
	end
	if idx >= 1 and idx < 5 and (lap == 0 or passedHalf) then
		lap += 1
		passedHalf = false
	end
	if lap == 2 then
		local b = sim.body
		table.insert(rec, {
			idx = idx,
			pitch = math.deg(vector.dot(b.angVel, b.right)),
			roll = math.deg(vector.dot(b.angVel, b.look)),
			vy = vector.dot(b.vel, b.up),
		})
	end
	return lap >= 3
end)

-- jitter = value minus its centred moving average over ~0.15 s
local half = math.max(1, math.floor(0.075 * fps + 0.5))
local function jitter(key: string): ({ number })
	local out = table.create(#rec, 0)
	for i = 1, #rec do
		local sum, cnt = 0, 0
		for j = math.max(1, i - half), math.min(#rec, i + half) do
			sum += (rec[j] :: any)[key]
			cnt += 1
		end
		out[i] = (rec[i] :: any)[key] - sum / cnt
	end
	return out
end
local function rms(xs: { number }): number
	local s = 0
	for _, x in xs do
		s += x * x
	end
	return math.sqrt(s / math.max(#xs, 1))
end
local jp, jr, jv = jitter("pitch"), jitter("roll"), jitter("vy")
local worst = {}
for i, r in rec do
	local seg = track.samples[r.idx].segment
	local e = worst[seg] or { pitch = 0, roll = 0, vy = 0, seg = seg }
	e.pitch = math.max(e.pitch, math.abs(jp[i]))
	e.roll = math.max(e.roll, math.abs(jr[i]))
	e.vy = math.max(e.vy, math.abs(jv[i]))
	worst[seg] = e
end
local splits = 0
for i = 1, track.n do
	local a, b = TrackLayout.roadSplit(track, i)
	splits += a * b
end
print(string.format("%s %d fps, road %s (%d pieces / %d quads): jitter rms pitch %.2f deg/s, roll %.2f deg/s, heave %.3f studs/s (%d frames)", spec.Name, fps, if g.plainRoad then "plain" else string.format("fold < %.3f", TrackLayout.RoadFold), if g.plainRoad then track.n else splits, track.n, rms(jp), rms(jr), rms(jv), #rec))
local list = {}
for _, e in worst do
	table.insert(list, e)
end
table.sort(list, function(a, b)
	return a.pitch + a.roll > b.pitch + b.roll
end)
for k = 1, math.min(6, #list) do
	local e = list[k]
	local seg = spec.Segments[e.seg]
	print(string.format("  segment %2d %-16s max pitch %.1f roll %.1f heave %.2f", e.seg, seg.name or seg.kind, e.pitch, e.roll, e.vy))
end
