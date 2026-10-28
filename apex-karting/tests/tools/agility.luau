-- Prints handling numbers for the current Config (not a pass/fail test).
-- Run from the project root:  luau tests/tools/agility.luau
local Config = require("../../src/shared/Config")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local cfg = Config.Kart
local KMH = Config.KmhPerStudPerSecond
local EAST = vector.create(1, 0, 0)

local function flat()
	return World.newGround(0, 1, 1)
end

local function steady(speed: number, steer: number)
	local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight, 0), EAST)
	sim.body.vel = EAST * speed
	local t90, peakYaw, yawSteady = nil, 0, 0
	local samples = {}
	sim:run(4, function()
		local v = sim:speed()
		sim.ctrl.throttle = if v < speed then 1 else 0
		sim.ctrl.steer = steer
		local yaw = math.abs(sim:yawRate())
		table.insert(samples, { t = sim.t, yaw = yaw })
		return nil
	end)
	-- steady yaw: average over the last second
	local sum, n = 0, 0
	for _, s in samples do
		if s.t > 3 then
			sum += s.yaw
			n += 1
		end
	end
	yawSteady = sum / n
	for _, s in samples do
		peakYaw = math.max(peakYaw, s.yaw)
		if not t90 and s.yaw >= 0.9 * yawSteady then
			t90 = s.t
		end
	end
	local v = vector.magnitude(sim.body.vel)
	local r = math.rad(yawSteady)
	local radius = if r > 1e-4 then v / r else math.huge
	local lat = v * r / cfg.Gravity
	return radius, lat, t90 or -1, yawSteady
end

print("speed(km/h)  radius(studs)  lateral(g)  t90(s)  yaw(deg/s)")
for _, kmh in { 15, 30, 45, 60, 80 } do
	local r, lat, t90, yaw = steady(kmh / KMH, 1)
	print(string.format("%8d %13.1f %11.2f %7.2f %10.1f", kmh, r, lat, t90, yaw))
end
