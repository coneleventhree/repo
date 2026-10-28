-- Acceleration report: standing start, pull at a few speeds, top speed, and
-- how much a better corner exit is still worth down a straight.
-- Not pass/fail. Run from the project root:
--   luau tests/tools/accel.luau                 (Config values)
--   luau tests/tools/accel.luau -a "8.5 510 0.2"  (DriveAccel PowerPerMass [Slipstream.DragCut])
local Config = require("../../src/shared/Config")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local KMH = Config.KmhPerStudPerSecond
local EAST = vector.create(1, 0, 0)

local cfg = table.clone(Config.Kart)
local arg = ...
if arg then
	local v = {}
	for x in string.gmatch(arg, "[^%s]+") do
		table.insert(v, tonumber(x))
	end
	cfg.DriveAccel, cfg.PowerPerMass = v[1] or cfg.DriveAccel, v[2] or cfg.PowerPerMass
	if v[3] then
		cfg.Slipstream = table.clone(cfg.Slipstream)
		cfg.Slipstream.DragCut = v[3]
	end
end
local G = cfg.Gravity
-- the real-world power this means for a 250 kg kart with driver
local watts = cfg.PowerPerMass * Config.StudMeters ^ 2 * 250
print(string.format("DriveAccel %g (%.2f g launch), PowerPerMass %g (~%.1f kW / %.0f hp at the wheels for 250 kg)", cfg.DriveAccel, cfg.DriveAccel / G, cfg.PowerPerMass, watts / 1000, watts / 745.7))

local ground = World.newGround(0, 1, 1)
local function newSim(kmh: number)
	local sim = Sim.new(ground, vector.create(0, cfg.RideHeight, 0), EAST, cfg)
	sim.body.vel = EAST * (kmh / KMH)
	sim.ctrl.throttle = 1
	return sim
end

-- standing start
do
	local sim = newSim(0)
	local marks = { 30, 50, 70, 80, 90, 95 }
	local at, dist = {}, {}
	local pull = {}
	local lastV = 0
	sim:run(60, function()
		local v = sim:speed() * KMH
		local a = (sim:speed() - lastV) / sim.frame / G
		lastV = sim:speed()
		for _, m in marks do
			if not at[m] and v >= m then
				at[m] = sim.t
				dist[m] = sim.body.pos.x
			end
		end
		for _, m in { 20, 50, 80, 90 } do
			if not pull[m] and v >= m then
				pull[m] = a
			end
		end
		return nil
	end)
	print("standing start, full throttle")
	for _, m in marks do
		if at[m] then
			print(string.format("  0-%d km/h  %5.2f s  %4.0f studs", m, at[m], dist[m]))
		else
			print(string.format("  0-%d km/h  not reached", m))
		end
	end
	print(string.format("  net pull: %.2f g at 20, %.2f g at 50, %.2f g at 80, %.2f g at 90 km/h", pull[20] or 0, pull[50] or 0, pull[80] or 0, pull[90] or 0))
	print(string.format("  speed after 60 s: %.1f km/h", sim:speed() * KMH))
end

-- corner exit: 5 km/h better out of a corner, how much of it is left later
do
	print("a 5 km/h better exit (50 vs 45 km/h), full throttle down the straight")
	local a, b = newSim(45), newSim(50)
	local checkpoints = { 100, 200, 400, 700 }
	local ta, tb, va, vb = {}, {}, {}, {}
	for _ = 1, 60 * 40 do
		a:step()
		b:step()
		for _, d in checkpoints do
			if not ta[d] and a.body.pos.x >= d then
				ta[d], va[d] = a.t, a:speed() * KMH
			end
			if not tb[d] and b.body.pos.x >= d then
				tb[d], vb[d] = b.t, b:speed() * KMH
			end
		end
		if ta[700] and tb[700] then
			break
		end
	end
	for _, d in checkpoints do
		print(string.format("  after %3d studs: %.1f vs %.1f km/h (still %.1f km/h faster), %.2f s gained", d, vb[d], va[d], vb[d] - va[d], ta[d] - tb[d]))
	end
end

-- slipstream: two karts flat out from 70 km/h, the second 12 studs behind
do
	local lead, follow = newSim(70), newSim(70)
	follow.body.pos -= EAST * 12
	local gap0 = lead.body.pos.x - follow.body.pos.x
	local gain, gaps = 0, {}
	for i = 1, 60 * 8 do
		local lo, fo = lead:obstacle(), follow:obstacle()
		lead:step({ fo })
		follow:step({ lo })
		gain = math.max(gain, (follow:speed() - lead:speed()) * KMH)
		if i % 120 == 0 then
			table.insert(gaps, string.format("%.1f", lead.body.pos.x - follow.body.pos.x))
		end
	end
	print(string.format("slipstream from 70 km/h, 12 studs behind (DragCut %.2f): follower up to %.1f km/h faster; gap %.1f -> %s studs (every 2 s); speeds at 8 s: %.1f / %.1f km/h", cfg.Slipstream.DragCut, gain, gap0, table.concat(gaps, " -> "), lead:speed() * KMH, follow:speed() * KMH))
end
