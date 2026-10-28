-- Cockpit camera smoothness: drives the kart through a steering press and
-- release and a quick left-right slalom on the keyboard, and checks the view
-- (CockpitRig) for jolts: bounce-back after letting go, horizon wobble, head
-- sway that overshoots. Compares with a camera bolted to the chassis.
-- Run from the project root:  luau tests/camera_test.luau
local Config = require("../src/shared/Config")
local SteerFilter = require("../src/shared/SteerFilter")
local CockpitRig = require("../src/shared/CockpitRig")
local World = require("./lib/world")
local Sim = require("./lib/sim")

local cfg = Config.Kart
local CP = Config.Camera.Cockpit
local KMH = Config.KmhPerStudPerSecond
local EAST = vector.create(1, 0, 0)

local pass, total = 0, 0
local function check(ok: boolean, label: string)
	total += 1
	if ok then
		pass += 1
	end
	print(string.format("%-4s %s", if ok then "PASS" else "FAIL", label))
	return ok
end

local function heading(v: vector): number
	return math.deg(math.atan2(-v.z, v.x))
end

-- `keys(t)` returns -1 / 0 / 1. Records per frame: view heading, roll, head sway.
local function drive(kmh: number, seconds: number, keys: (number) -> number, rigid: boolean)
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(0, cfg.RideHeight, 0), EAST)
	local v0 = kmh / KMH
	sim.body.vel = EAST * v0
	local fs = SteerFilter.new()
	local rig = CockpitRig.new()
	local frames = {}
	sim:run(seconds, function()
		sim.ctrl.steer = SteerFilter.step(Config.Steering, fs, keys(sim.t), true, sim:speed(), sim.frame)
		sim.ctrl.throttle = if sim:speed() < v0 then 1 else 0
		local b = sim.body
		local look, up, sway
		if rigid then
			-- a camera bolted to the chassis
			look, up, sway = b.look, b.up, 0
		else
			local pose = { pos = b.pos, right = b.right, up = b.up, look = b.look, vel = b.vel, angVel = b.angVel }
			local _, l, u = CockpitRig.step(CP :: any, rig, pose, cfg.RideHeight, cfg.Gravity, 0, 0, sim.frame)
			look, up, sway = l, u, rig.head.x
		end
		local side = vector.normalize(vector.cross(look, vector.create(0, 1, 0)))
		local roll = math.deg(math.asin(math.clamp(vector.dot(up, side), -1, 1)))
		table.insert(frames, { t = sim.t, h = heading(look), roll = roll, sway = sway, yawKart = sim:yawRate() })
		return nil
	end)
	return frames, sim.frame
end

local function rates(frames, dt: number)
	local out = {}
	for i = 2, #frames do
		local d = (frames[i].h - frames[i - 1].h + 180) % 360 - 180
		out[i] = d / dt
	end
	out[1] = out[2] or 0
	return out
end

----------------------------------------------------------------------------
print("== Press and let go at 70 km/h ==")
do
	local press = function(t: number): number
		return if t < 1.0 then 1 else 0
	end
	local smooth, dt = drive(70, 2.5, press, false)
	local rigid = drive(70, 2.5, press, true)
	local rs, rr = rates(smooth, dt), rates(rigid, dt)
	-- after letting go the view should settle without swinging back the other way
	local function backSwing(r)
		local worst = 0
		for i, f in smooth do
			if f.t > 1.0 then
				worst = math.max(worst, r[i]) -- turning was negative yaw (right); positive = swing back
			end
		end
		return worst
	end
	local function maxRoll(frames)
		local m = 0
		for _, f in frames do
			m = math.max(m, math.abs(f.roll))
		end
		return m
	end
	local function maxJerk(r)
		local m = 0
		for i = 3, #r do
			m = math.max(m, math.abs((r[i] - r[i - 1]) / dt))
		end
		return m
	end
	local swayOver = 0
	local peakSway = 0
	for _, f in smooth do
		peakSway = math.max(peakSway, math.abs(f.sway))
	end
	for _, f in smooth do
		if f.t > 1.35 then
			swayOver = math.max(swayOver, -f.sway * (if smooth[1] then 1 else 1))
		end
	end
	-- right turn throws the head left (negative x); after release it must not cross to the right
	local crossed = 0
	for _, f in smooth do
		if f.t > 1.0 then
			crossed = math.max(crossed, f.sway)
		end
	end
	check(backSwing(rs) < 2.5, string.format("no swing back after letting go (%.1f deg/s; bolted-on camera %.1f)", backSwing(rs), backSwing(rr)))
	check(maxRoll(smooth) < 0.45 and maxRoll(smooth) < maxRoll(rigid) * 0.5, string.format("horizon tilt %.2f deg (bolted-on camera %.2f)", maxRoll(smooth), maxRoll(rigid)))
	check(maxJerk(rs) < 2200, string.format("view turns without jolts: max change of turn rate %.0f deg/s^2 (bolted-on %.0f)", maxJerk(rs), maxJerk(rr)))
	check(peakSway > 0.01 and peakSway <= CP.HeadMax + 1e-6, string.format("head sways %.3f studs in the corner", peakSway))
	check(crossed < 0.004, string.format("head eases back without bouncing past centre (%.4f)", crossed))
	local _ = swayOver
end

----------------------------------------------------------------------------
print("== Quick left-right slalom at 60 km/h ==")
do
	local slalom = function(t: number): number
		local k = math.floor(t / 0.45)
		if t > 3.6 then
			return 0
		end
		return if k % 2 == 0 then 1 else -1
	end
	local smooth, dt = drive(60, 4.5, slalom, false)
	local rigid = drive(60, 4.5, slalom, true)
	local function maxRoll(frames)
		local m = 0
		for _, f in frames do
			m = math.max(m, math.abs(f.roll))
		end
		return m
	end
	local function rollRate(frames)
		local m = 0
		for i = 2, #frames do
			m = math.max(m, math.abs(frames[i].roll - frames[i - 1].roll) / dt)
		end
		return m
	end
	check(maxRoll(smooth) < maxRoll(rigid) * 0.5, string.format("horizon rocks %.2f deg (bolted-on camera %.2f)", maxRoll(smooth), maxRoll(rigid)))
	check(rollRate(smooth) < rollRate(rigid) * 0.4, string.format("roll speed %.1f deg/s (bolted-on %.1f)", rollRate(smooth), rollRate(rigid)))
	local maxSway = 0
	for _, f in smooth do
		maxSway = math.max(maxSway, math.abs(f.sway))
	end
	check(maxSway <= CP.HeadMax + 1e-6, string.format("head sway stays within %.2f studs (%.3f)", CP.HeadMax, maxSway))
end

----------------------------------------------------------------------------
print("== The kart answers the keys in proportion ==")
do
	-- with the grip-curve-aware assist the kart's turn builds and fades in
	-- step with the steering, instead of snapping at the start or the end
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(0, cfg.RideHeight, 0), EAST)
	local v0 = 70 / KMH
	sim.body.vel = EAST * v0
	local fs = SteerFilter.new()
	local atHalf, settled, decay90, decay10 = nil, 0, nil, nil
	sim:run(2.5, function()
		local key = if sim.t < 1.0 then 1 else 0
		local cmd = SteerFilter.step(Config.Steering, fs, key, true, sim:speed(), sim.frame)
		sim.ctrl.steer = cmd
		sim.ctrl.throttle = if sim:speed() < v0 then 1 else 0
		local yaw = math.abs(sim:yawRate())
		if sim.t < 1.0 then
			if not atHalf and cmd >= 0.5 then
				atHalf = yaw
			end
			if sim.t > 0.8 then
				settled = yaw
			end
		else
			if not decay90 and yaw < settled * 0.9 then
				decay90 = sim.t
			end
			if not decay10 and yaw < settled * 0.1 then
				decay10 = sim.t
			end
		end
		return nil
	end)
	local share = (atHalf or 0) / math.max(settled, 1)
	check(share > 0.35 and share < 0.75, string.format("half the steering gives %.0f%% of the turn", share * 100))
	local fade = (decay10 or 99) - (decay90 or 0)
	check(fade > 0.15, string.format("letting go: the turn fades over %.2f s (no snap straight)", fade))
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
