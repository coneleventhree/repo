-- Autopilot lap of every circuit: lap time, top speed and how much of the
-- lap is spent on full throttle. Not pass/fail. Run from the project root:
--   luau tests/tools/laps.luau                 (Config values)
--   luau tests/tools/laps.luau -a "8.5 510"    (DriveAccel PowerPerMass to compare)
local Config = require("../../src/shared/Config")
local TrackData = require("../../src/shared/TrackData")
local TrackMath = require("../../src/shared/TrackMath")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local KMH = Config.KmhPerStudPerSecond

local cfg = table.clone(Config.Kart)
local arg = ...
if arg then
	local v = {}
	for x in string.gmatch(arg, "[^%s]+") do
		table.insert(v, tonumber(x))
	end
	cfg.DriveAccel, cfg.PowerPerMass = v[1] or cfg.DriveAccel, v[2] or cfg.PowerPerMass
end
print(string.format("DriveAccel %g, PowerPerMass %g", cfg.DriveAccel, cfg.PowerPerMass))

for _, id in TrackData.Order do
	local spec = TrackData.get(id)
	local track = TrackMath.build(spec)
	local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
	g:addTrack(track)
	local pos, fwd = TrackMath.slot(track, 1, 0, 20)
	local sim = Sim.spawnOn(g, pos.x, pos.z, fwd, cfg, 60)
	local plan = Sim.speedPlan(track, cfg, 0.85)
	local hint = 1
	local lapStart: number? = nil
	local laps = {}
	local passedHalf = false
	local top, full, frames = 0, 0, 0
	sim:run(400, function()
		local idx = sim:autopilot(track, plan, hint)
		hint = idx
		if idx > track.n / 2 and idx < track.n * 0.6 then
			passedHalf = true
		end
		if lapStart == nil and idx >= 1 and idx < 5 then
			lapStart = sim.t
			passedHalf = false
		elseif lapStart and passedHalf and idx >= 1 and idx < 5 then
			table.insert(laps, sim.t - lapStart)
			lapStart = sim.t
			passedHalf = false
		end
		if #laps == 1 then
			top = math.max(top, sim:speed())
			frames += 1
			if sim.ctrl.throttle >= 1 then
				full += 1
			end
		end
		return #laps >= 2
	end)
	print(string.format("  %-14s flying lap %6.2f s, top %5.1f km/h, full throttle %2.0f%% of the lap", spec.Name, laps[2] or -1, top * KMH, 100 * full / math.max(frames, 1)))
end
