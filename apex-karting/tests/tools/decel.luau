-- Deceleration report: coasting (off the throttle), braking with the keyboard
-- (the same ramp Input uses), and how much speed a corner scrubs off.
-- Not pass/fail. Run from the project root:  luau tests/tools/decel.luau
local Config = require("../../src/shared/Config")
local SteerFilter = require("../../src/shared/SteerFilter")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local cfg = Config.Kart
local KMH = Config.KmhPerStudPerSecond
local G = cfg.Gravity
local EAST = vector.create(1, 0, 0)

local function newSim(kmh: number)
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(0, cfg.RideHeight, 0), EAST)
	sim.body.vel = EAST * (kmh / KMH)
	return sim
end

-- coasting: decel at a few speeds and the time to lose speed
do
	local sim = newSim(95)
	local marks = { 90, 70, 50, 30 }
	local seen, times = {}, {}
	local lastV = sim:speed()
	sim:run(30, function()
		local v = sim:speed() * KMH
		local a = (lastV - sim:speed()) / sim.frame / G
		lastV = sim:speed()
		for _, m in marks do
			if not seen[m] and v <= m then
				seen[m] = a
				times[m] = sim.t
			end
		end
		return v < 25
	end)
	print("coasting (lift off, no brake)")
	for _, m in marks do
		print(string.format("  at %d km/h: %.3f g", m, seen[m] or -1))
	end
	print(string.format("  90 -> 50 km/h takes %.1f s, 90 -> 30 km/h %.1f s", (times[50] or 0) - (times[90] or 0), (times[30] or 0) - (times[90] or 0)))
end

-- keyboard braking: S held from 90 km/h with Input's brake ramp
do
	local sim = newSim(90)
	local x0 = sim.body.pos.x
	local brk, peak = 0, 0
	local lastV = sim:speed()
	local t0 = sim.t
	local rampRate = Config.Pedals and Config.Pedals.BrakeRise or 9
	sim:run(10, function()
		brk = math.min(brk + sim.frame * rampRate, 1)
		sim.ctrl.throttle, sim.ctrl.brake = 0, brk
		local a = (lastV - sim:speed()) / sim.frame / G
		lastV = sim:speed()
		peak = math.max(peak, a)
		return sim:speed() < 0.5
	end)
	print(string.format("keyboard brake 90 -> 0 km/h: %.2f s, %.0f studs, peak %.2f g", sim.t - t0, sim.body.pos.x - x0, peak))
end

-- a tap of the brake (0.3 s) from 80 km/h
do
	local sim = newSim(80)
	local brk = 0
	local rampRate = Config.Pedals and Config.Pedals.BrakeRise or 9
	sim:run(0.3, function()
		brk = math.min(brk + sim.frame * rampRate, 1)
		sim.ctrl.throttle, sim.ctrl.brake = 0, brk
		return nil
	end)
	print(string.format("0.3 s brake tap from 80 km/h leaves %.0f km/h", sim:speed() * KMH))
end

-- corner: hold the steering key at 70 km/h, (a) on full throttle (b) coasting
for _, gas in { 1, 0 } do
	local sim = newSim(70)
	local fs = SteerFilter.new()
	local v1 = 0
	sim:run(2.5, function()
		sim.ctrl.steer = SteerFilter.step(Config.Steering, fs, 1, true, sim:speed(), sim.frame)
		sim.ctrl.throttle = gas
		if sim.t <= 2.0 then
			v1 = sim:speed()
		end
		return nil
	end)
	print(string.format("2 s of full steering at 70 km/h, %s: ends at %.0f km/h", if gas == 1 then "full throttle" else "coasting", v1 * KMH))
end
