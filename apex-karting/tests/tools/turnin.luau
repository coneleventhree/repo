-- Turn-in report: tap a steering key at speed and watch what the kart does.
-- Shows the steering angle ramp, front tyre grip use, slip and yaw response,
-- with and without the keyboard filter (SteerFilter).
-- Run from the project root:  luau tests/tools/turnin.luau
local Config = require("../../src/shared/Config")
local SteerFilter = require("../../src/shared/SteerFilter")
local World = require("../lib/world")
local Sim = require("../lib/sim")
local cfg = Config.Kart
local KMH = Config.KmhPerStudPerSecond
local EAST = vector.create(1, 0, 0)

local function run(kmh: number, filtered: boolean, hold: number)
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(0, cfg.RideHeight, 0), EAST)
	local v0 = kmh / KMH
	sim.body.vel = EAST * v0
	local fs = SteerFilter.new()
	local t90, peakFront, peakSlip, peakYaw = nil, 0, 0, 0
	local yawAt = {}
	local maxStep = 0
	local lastAngle = 0
	sim:run(hold, function(res)
		local key = 1
		local cmd = if filtered then SteerFilter.step(Config.Steering, fs, key, true, sim:speed(), sim.frame) else key
		sim.ctrl.steer = cmd
		sim.ctrl.throttle = if sim:speed() < v0 then 1 else 0
		local ang = math.deg(res.steerAngle)
		maxStep = math.max(maxStep, math.abs(ang - lastAngle))
		lastAngle = ang
		local front = math.max(res.wheels[1].usage, res.wheels[2].usage)
		peakFront = math.max(peakFront, front)
		local vel = sim.body.vel
		local slip = math.deg(math.acos(math.clamp(vector.dot(vector.normalize(vel), sim.body.look), -1, 1)))
		peakSlip = math.max(peakSlip, slip)
		local yaw = math.abs(sim:yawRate())
		peakYaw = math.max(peakYaw, yaw)
		if not t90 and cmd > 0.9 then
			t90 = sim.t
		end
		for _, t in { 0.1, 0.25, 0.5 } do
			if not yawAt[t] and sim.t >= t then
				yawAt[t] = yaw
			end
		end
		return nil
	end)
	local lat = vector.magnitude(sim.body.vel) * math.rad(math.abs(sim:yawRate())) / cfg.Gravity
	return {
		t90 = t90 or -1,
		maxStep = maxStep,
		peakFront = peakFront,
		peakSlip = peakSlip,
		peakYaw = peakYaw,
		y01 = yawAt[0.1] or 0,
		y025 = yawAt[0.25] or 0,
		y05 = yawAt[0.5] or 0,
		lat = lat,
		finalYaw = math.abs(sim:yawRate()),
	}
end

print("speed  filter  t90(s)  maxStep(deg/frame)  peakFrontUse  peakBodySlip  yaw@0.1/0.25/0.5  peakYaw/finalYaw  lat(g)")
for _, kmh in { 20, 45, 70, 90 } do
	for _, filtered in { false, true } do
		local r = run(kmh, filtered, 3)
		print(string.format("%4d   %-6s  %5.2f   %8.2f            %6.2f        %6.1f        %5.1f/%5.1f/%5.1f    %5.1f/%5.1f     %4.2f",
			kmh, if filtered then "on" else "off", r.t90, r.maxStep, r.peakFront, r.peakSlip, r.y01, r.y025, r.y05, r.peakYaw, r.finalYaw, r.lat))
	end
end
