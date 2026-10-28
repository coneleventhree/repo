-- Steering feel tests: the keyboard ramp (SteerFilter), what over-steering
-- the front wheels does (understeer), turn-in without a jerk, and a full lap
-- driven the way a person drives with a keyboard (tapping the arrow keys).
-- Run from the project root:  luau tests/steering_test.luau
local Config = require("../src/shared/Config")
local SteerFilter = require("../src/shared/SteerFilter")
local KartPhysics = require("../src/shared/KartPhysics")
local TrackMath = require("../src/shared/TrackMath")
local TrackData = require("../src/shared/TrackData")
local World = require("./lib/world")
local Sim = require("./lib/sim")

local cfg = Config.Kart
local S = Config.Steering
DEBUG_LAP = false
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

-- feeds `target` for `seconds`; returns the first time `reached(out)` is
-- true, plus the biggest change of the output in one frame
local function ramp(state, target: number, digital: boolean, speed: number, seconds: number, fps: number, reached: ((number) -> boolean)?)
	local dt = 1 / fps
	local t, hit, maxStep = 0, nil, 0
	local last = state.out
	while t < seconds - 1e-9 do
		t += dt
		local out = SteerFilter.step(S, state, target, digital, speed, dt)
		maxStep = math.max(maxStep, math.abs(out - last))
		last = out
		if reached and not hit and reached(out) then
			hit = t
		end
	end
	return hit or math.huge, maxStep
end
local function above(level: number)
	return function(x: number): boolean
		return x >= level
	end
end
local function below(level: number)
	return function(x: number): boolean
		return x <= level
	end
end

----------------------------------------------------------------------------
print("== Keyboard ramp ==")
do
	local tLow = ramp(SteerFilter.new(), 1, true, 0, 2, 60, above(0.9))
	local tHigh, stepHigh = ramp(SteerFilter.new(), 1, true, 75, 2, 60, above(0.9))
	check(tLow > 0.15 and tLow < 0.4, string.format("parking speed: 90%% lock after %.2f s", tLow))
	check(tHigh > 0.25 and tHigh < 0.6, string.format("racing speed: 90%% lock after %.2f s (gradual turn-in)", tHigh))
	check(stepHigh < 0.06, string.format("never jumps more than %.3f of lock in one frame", stepHigh))

	local st = SteerFilter.new()
	ramp(st, 1, true, 75, 2, 60)
	local tBack = ramp(st, 0, true, 75, 2, 60, below(0.05))
	check(tBack > 0.2 and tBack < 0.6, string.format("lets go back to centre in %.2f s", tBack))

	local sw = SteerFilter.new()
	ramp(sw, -1, true, 75, 2, 60)
	local tCross = ramp(sw, 1, true, 75, 2, 60, above(0))
	check(tCross < 0.25, string.format("left -> right goes through centre in %.2f s (quick counter-steer)", tCross))

	local t30 = ramp(SteerFilter.new(), 1, true, 75, 2, 30, above(0.9))
	local t120 = ramp(SteerFilter.new(), 1, true, 75, 2, 120, above(0.9))
	check(math.abs(t30 - t120) < 0.06, string.format("same feel at 30 fps (%.2f s) and 120 fps (%.2f s)", t30, t120))

	local stick = SteerFilter.new()
	ramp(stick, 0.3, false, 75, 1, 60)
	check(math.abs(stick.out - 0.3 ^ S.StickCurve) < 0.01, string.format("gamepad stick 0.3 -> %.3f (fine control near centre)", stick.out))
	local tStick = ramp(SteerFilter.new(), 1, false, 75, 1, 60, above(0.9))
	check(tStick < 0.25, string.format("gamepad stick reaches full in %.2f s (analog stays responsive)", tStick))
end

----------------------------------------------------------------------------
print("== Over-steering the front wheels pushes wide ==")
do
	local raw = table.clone(cfg)
	raw.SteerAssist = false
	local function steady(input: number)
		local sim = Sim.new(World.newGround(0, 1, 1), vector.create(0, cfg.RideHeight, 0), EAST, raw)
		local v0 = 50 / KMH
		sim.body.vel = EAST * v0
		local frontSlip = 0
		local n = 0
		sim:run(4, function(res)
			sim.ctrl.steer = input
			sim.ctrl.throttle = if sim:speed() < v0 then 1 else 0
			if sim.t > 3 then
				-- tyre slip angle at the front = wheel angle - direction the axle travels
				frontSlip += math.deg(res.steerAngle - KartPhysics.frontAxleSlip(raw, sim.body:snapshot()))
				n += 1
			end
			return nil
		end)
		local lat = vector.magnitude(sim.body.vel) * math.rad(math.abs(sim:yawRate())) / cfg.Gravity
		return lat, frontSlip / n
	end
	local best, bestInput = 0, 0
	for k = 1, 10 do
		local lat = steady(k / 10)
		if lat > best then
			best, bestInput = lat, k / 10
		end
	end
	local full, fullSlip = steady(1)
	local _, bestSlip = steady(bestInput)
	check(bestInput < 1, string.format("most cornering at %.0f%% lock (%.2f g, front slip %.1f deg), not full lock", bestInput * 100, best, bestSlip))
	check(full < best * 0.85 and fullSlip > 15, string.format("full lock at 50 km/h: front slip %.0f deg, only %.2f g = understeer", fullSlip, full))
end

----------------------------------------------------------------------------
print("== Turn-in ==")
local function turnIn(kmh: number, filtered: boolean)
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(0, cfg.RideHeight, 0), EAST)
	local v0 = kmh / KMH
	sim.body.vel = EAST * v0
	local fs = SteerFilter.new()
	local peak, last = 0, 0
	sim:run(3, function()
		sim.ctrl.steer = if filtered then SteerFilter.step(S, fs, 1, true, sim:speed(), sim.frame) else 1
		sim.ctrl.throttle = if sim:speed() < v0 then 1 else 0
		local yaw = math.abs(sim:yawRate())
		peak = math.max(peak, yaw)
		last = yaw
		return nil
	end)
	return peak / math.max(last, 1)
end
do
	for _, kmh in { 70, 90 } do
		local raw = turnIn(kmh, false)
		local smooth = turnIn(kmh, true)
		check(smooth < 1.15 and smooth < raw - 0.15, string.format("%d km/h: yaw overshoot %.0f%% with the ramp (was %.0f%% when the wheel snapped)", kmh, (smooth - 1) * 100, (raw - 1) * 100))
	end
end

----------------------------------------------------------------------------
print("== A lap on the keyboard ==")
do
	-- The driver taps the arrow keys like a person: press while the kart
	-- needs more lock than it has, let go when it has enough.
	local track = TrackMath.build(TrackData.get())
	local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
	g:addTrack(track)
	local pos, fwd = TrackMath.slot(track, 1, 0, 20)
	local sim = Sim.spawnOn(g, pos.x, pos.z, fwd)
	local plan = Sim.speedPlan(track, cfg, 0.8)
	local fs = SteerFilter.new()
	local key, presses = 0, 0
	local hint = 1
	local lapStart, lapTime, passedHalf = nil, nil, false
	local maxOff, maxSlip = 0, 0
	local gas, brk = 0, 0
	local done = sim:run(120, function()
		-- what a perfect analog driver would ask for
		local idx, lateral = sim:autopilot(track, plan, hint)
		hint = idx
		local want = sim.ctrl.steer
		local out = fs.out
		local newKey = key
		if want > out + 0.08 then
			newKey = if want > 0.05 then 1 else 0
		elseif want < out - 0.08 then
			newKey = if want < -0.05 then -1 else 0
		end
		if newKey ~= key and newKey ~= 0 then
			presses += 1
		end
		key = newKey
		sim.ctrl.steer = SteerFilter.step(S, fs, key, true, sim:speed(), sim.frame)
		-- keyboard pedals: on / off with the same ramp Input uses
		local wantGas, wantBrake = sim.ctrl.throttle > 0.5, sim.ctrl.brake > 0.15
		gas = if wantGas then math.min(gas + sim.frame * Config.Pedals.ThrottleRise, 1) else 0
		brk = if wantBrake then math.min(brk + sim.frame * Config.Pedals.BrakeRise, 1) else 0
		sim.ctrl.throttle, sim.ctrl.brake = gas, brk
		maxOff = math.max(maxOff, math.abs(lateral) - track.samples[idx].width / 2)
		local v = sim.body.vel
		if vector.magnitude(v) > 10 then
			local slipNow = math.deg(math.acos(math.clamp(vector.dot(vector.normalize(v), sim.body.look), -1, 1)))
			if slipNow > maxSlip and DEBUG_LAP then
				print(string.format("    t=%.2f idx=%d slip=%.1f v=%.1f key=%d out=%.2f gas=%.2f brk=%.2f", sim.t, idx, slipNow, sim:speed(), key, fs.out, gas, brk))
			end
			maxSlip = math.max(maxSlip, slipNow)
		end
		if idx > track.n / 2 and idx < track.n * 0.6 then
			passedHalf = true
		end
		if idx >= 1 and idx < 5 then
			if lapStart == nil then
				lapStart = sim.t
				passedHalf = false
			elseif passedHalf then
				lapTime = sim.t - lapStart
				return true
			end
		end
		return nil
	end)
	check(done and lapTime ~= nil, string.format("completes a lap on keys only (%.2f s, %d key presses)", lapTime or -1, presses))
	check(maxOff < 3.2, string.format("stays on the road and kerbs (at most %.1f studs past the edge)", math.max(maxOff, 0)))
	check(maxSlip < 15, string.format("no slides or spins (max body slip %.1f deg)", maxSlip))
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
