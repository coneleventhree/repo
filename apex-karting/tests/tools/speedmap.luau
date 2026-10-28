-- Autopilot lap of one circuit, printed per track sample (for designing
-- corners: where it is flat out, how fast each corner goes, how long the
-- steering is held). Plot with tests/tools/speedmap.py.
--   luau tests/tools/speedmap.luau -a Hillside > hillside_speed.csv
-- Columns: i,x,y,z,kmh,throttle,brake,steer,lateral_g,segment,name
local Config = require("../../src/shared/Config")
local TrackData = require("../../src/shared/TrackData")
local TrackMath = require("../../src/shared/TrackMath")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local KMH = Config.KmhPerStudPerSecond

local spec = TrackData.get(...)
local track = TrackMath.build(spec)
local cfg = table.clone(Config.Kart)
local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
g:addTrack(track)
local pos, fwd = TrackMath.slot(track, 1, 0, 20)
local sim = Sim.spawnOn(g, pos.x, pos.z, fwd, cfg, 60)
local plan = Sim.speedPlan(track, cfg, 0.85)
local hint = 1
local lap = 0
local passedHalf = false
local rows: { [number]: string } = {}
local lapStart = 0
local lapTime = 0
sim:run(400, function()
	local idx = sim:autopilot(track, plan, hint)
	hint = idx
	if idx > track.n / 2 and idx < track.n * 0.6 then
		passedHalf = true
	end
	if idx >= 1 and idx < 5 and (lap == 0 or passedHalf) then
		lap += 1
		passedHalf = false
		if lap == 3 then
			lapTime = sim.t - lapStart
		end
		lapStart = sim.t
	end
	if lap == 2 then
		local b = sim.body
		local v = sim:speed()
		local yaw = sim:yawRate()
		local smp = track.samples[idx]
		local seg = spec.Segments[smp.segment]
		rows[idx] = string.format("%d,%.2f,%.2f,%.2f,%.1f,%.2f,%.2f,%.3f,%.2f,%d,%s", idx, b.pos.x, b.pos.y, b.pos.z, v * KMH, sim.ctrl.throttle, sim.ctrl.brake or 0, sim.ctrl.steer, math.abs(v * yaw) / cfg.Gravity, smp.segment, (seg and seg.name) or "")
	end
	return lap >= 3
end)
print(string.format("# %s length %.0f studs (%.2f km), autopilot lap %.2f s", spec.Name, track.length, track.length * Config.StudMeters / 1000, lapTime))
for i = 1, track.n do
	if rows[i] then
		print(rows[i])
	end
end
