-- How much faster a banked hairpin can be taken: the fastest steady speed the
-- autopilot holds round a 12.6 m (45 stud) hairpin, flat vs banked. Not
-- pass/fail. Run from the project root:  luau tests/tools/bank.luau
local Config = require("../../src/shared/Config")
local TrackMath = require("../../src/shared/TrackMath")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local KMH = Config.KmhPerStudPerSecond

local function oval(bank: number, radius: number)
	return TrackMath.build({
		Spacing = 6,
		Smoothing = 10,
		BankSmoothing = 40,
		StartY = 8,
		Segments = {
			{ kind = "S", length = "free", width = 32 },
			{ kind = "A", radius = radius, angle = 180, bank = bank },
			{ kind = "S", length = 300 },
			{ kind = "A", radius = radius, angle = 90, bank = bank },
			{ kind = "S", length = "free" },
			{ kind = "A", radius = radius, angle = 90, bank = bank },
		},
	} :: any)
end

-- holds `v` (studs/s) from the straight through the first hairpin; returns
-- whether it made it and the slowest speed in the corner
local function holds(track, v: number): (boolean, number)
	local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
	g:addTrack(track, nil, nil, 20)
	local pos, fwd = TrackMath.slot(track, 30, 0, 0)
	local sim = Sim.spawnOn(g, pos.x, pos.z, fwd)
	sim.body.vel = fwd * v
	local plan = table.create(track.n, v)
	local hint = 30
	local ok, inCorner, through = true, false, false
	local slowest = math.huge
	sim:run(15, function()
		local idx, lateral = sim:autopilot(track, plan, hint)
		hint = idx
		local smp = track.samples[idx]
		if math.abs(lateral) > 9 or vector.dot(sim.body.look, smp.fwd) < 0.8 then
			ok = false
			return true
		end
		if smp.segment == 2 then
			inCorner = true
			slowest = math.min(slowest, sim:speed())
		elseif inCorner and smp.segment == 3 then
			through = true
			return true
		end
		return nil
	end)
	return ok and through, slowest
end

local radius = 45
for _, bank in { 0, 8, 12, 15 } do
	local track = oval(bank, radius)
	local lo, hi = 20, 110
	local best = 0
	for _ = 1, 12 do
		local mid = (lo + hi) / 2
		local ok, slowest = holds(track, mid)
		if ok then
			lo = mid
			best = slowest
		else
			hi = mid
		end
	end
	print(string.format("hairpin r=%.1f m banked %2d deg: holds %.0f km/h through it", radius * Config.StudMeters, bank, best * KMH))
end
