-- Physics tests: runs the real KartPhysics model in a headless rigid-body world.
-- Run from the project root:  luau tests/physics_test.luau
local Config = require("../src/shared/Config")
local KartPhysics = require("../src/shared/KartPhysics")
local TrackMath = require("../src/shared/TrackMath")
local TrackData = require("../src/shared/TrackData")
local World = require("./lib/world")
local Sim = require("./lib/sim")

local cfg = Config.Kart
local KMH = Config.KmhPerStudPerSecond
local pass, total = 0, 0
local function check(ok: boolean, label: string)
	total += 1
	if ok then
		pass += 1
	end
	print(string.format("%-4s %s", if ok then "PASS" else "FAIL", label))
	return ok
end

local EAST = vector.create(1, 0, 0)
local function flat(grip: number?, roll: number?)
	return World.newGround(0, grip or 1, roll or 1)
end

----------------------------------------------------------------------------
print("== Standing still ==")
do
	local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight + 0.3, 0), EAST)
	sim:run(3)
	local b = sim.body
	local res = sim.last
	local front = res.wheels[1].load + res.wheels[2].load
	local rear = res.wheels[3].load + res.wheels[4].load
	local frontPct = front / (front + rear) * 100
	check(math.abs(b.pos.y - cfg.RideHeight) < 0.05, string.format("settles at ride height (%.3f, want %.2f)", b.pos.y, cfg.RideHeight))
	check(vector.magnitude(b.vel) < 0.02, string.format("comes to rest (speed %.4f)", vector.magnitude(b.vel)))
	check(math.abs(frontPct - 42) < 2, string.format("weight split front %.1f%% (want ~42)", frontPct))
	check(res.grounded == 4, "all four wheels on the ground")
	-- no creep over 5 more seconds
	local p0 = b.pos
	sim:run(5)
	check(vector.magnitude(b.pos - p0) < 0.05, string.format("no creep while parked (%.4f studs in 5 s)", vector.magnitude(b.pos - p0)))
end

----------------------------------------------------------------------------
print("== Straight line ==")
do
	local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight, 0), EAST)
	sim.ctrl.throttle = 1
	local t50, t80, spun = nil, nil, 0
	sim:run(40, function(res)
		local v = sim:speed() * KMH
		if not t50 and v >= 50 then
			t50 = sim.t
		end
		if not t80 and v >= 80 then
			t80 = sim.t
		end
		for _, w in res.wheels do
			if w.spinning then
				spun += 1
			end
		end
		return nil
	end)
	local top = sim:speed() * KMH
	-- an outdoor rental kart (~15 hp 4-stroke, one gear, ~250 kg with driver)
	check(t50 ~= nil and t50 > 5 and t50 < 8, string.format("0-50 km/h in %.2f s (rental kart: about 6-7 s)", t50 or -1))
	check(t80 ~= nil and t80 > 10 and t80 < 17, string.format("0-80 km/h in %.2f s", t80 or -1))
	check(top > 92 and top < 104, string.format("top speed %.1f km/h", top))
	check(spun == 0, string.format("no wheelspin on asphalt (%d frames)", spun))
	check(math.abs(sim.body.pos.z) < 0.5, string.format("runs straight (drift %.3f studs)", sim.body.pos.z))
	check(sim.maxPitch < 3, string.format("squat under power %.2f deg", sim.maxPitch))

	-- braking from top speed
	sim.ctrl.throttle, sim.ctrl.brake = 0, 1
	local x0 = sim.body.pos.x
	local v0 = sim:speed()
	local locked, maxYaw = 0, 0
	local t0 = sim.t
	sim:run(10, function(res)
		maxYaw = math.max(maxYaw, math.abs(sim:yawRate()))
		for _, w in res.wheels do
			if w.locked then
				locked += 1
			end
		end
		return sim:speed() < 0.5
	end)
	local dist = sim.body.pos.x - x0
	local decel = v0 * v0 / (2 * dist) / cfg.Gravity
	check(decel > 1.2 and decel < 1.9, string.format("brakes %.0f km/h->0 in %.1f studs (%.2f g, %.2f s)", v0 * KMH, dist, decel, sim.t - t0))
	check(maxYaw < 5, string.format("stays straight under full braking (max yaw %.2f deg/s, locked frames %d)", maxYaw, locked))
	check(sim.maxPitch < 4, string.format("dive under braking %.2f deg", sim.maxPitch))
end

----------------------------------------------------------------------------
print("== Reverse ==")
do
	local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight, 0), EAST)
	sim.ctrl.brake = 1
	sim:run(5)
	local v = sim:speed()
	check(v < -cfg.ReverseSpeed + 2 and v > -cfg.ReverseSpeed - 1, string.format("holding brake reverses (%.1f studs/s)", v))
	sim.ctrl.brake, sim.ctrl.throttle = 0, 1
	sim:run(3)
	check(sim:speed() > 5, string.format("throttle drives forward again (%.1f)", sim:speed()))
end

----------------------------------------------------------------------------
print("== Cornering ==")
do
	-- steady state at several speeds with full steering input
	for _, kmh in { 30, 60, 90 } do
		local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight, 0), EAST)
		local target = kmh / KMH
		sim.body.vel = EAST * target
		local maxLat, maxRoll = 0, 0
		local spun = false
		sim:run(6, function()
			-- hold speed
			local v = sim:speed()
			sim.ctrl.throttle = if v < target then 1 else 0
			sim.ctrl.steer = 1
			if sim.t > 2 then
				local lat = vector.magnitude(sim.body.vel) * math.abs(math.rad(sim:yawRate())) / cfg.Gravity
				maxLat = math.max(maxLat, lat)
			end
			-- spun = heading is more than 30 degrees off the travel direction
			local vh = sim.body.vel
			if vector.magnitude(vh) > 3 then
				local slip = math.deg(math.acos(math.clamp(vector.dot(vector.normalize(vh), sim.body.look), -1, 1)))
				if slip > 30 then
					spun = true
				end
			end
			return nil
		end)
		check(not spun, string.format("%d km/h full lock: no spin (lateral %.2f g, roll %.2f deg)", kmh, maxLat, sim.maxRoll))
		check(sim.maxRoll < 6, string.format("%d km/h full lock: roll %.2f deg", kmh, sim.maxRoll))
		if kmh >= 60 then
			check(maxLat > 1.6, string.format("%d km/h uses the grip (%.2f g)", kmh, maxLat))
		end
	end
end

----------------------------------------------------------------------------
print("== Grass ==")
do
	local sim = Sim.new(flat(Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll), vector.create(0, cfg.RideHeight, 0), EAST)
	sim.ctrl.throttle = 1
	local spun = 0
	sim:run(25, function(res)
		for _, w in res.wheels do
			if w.spinning then
				spun += 1
			end
		end
		return nil
	end)
	local top = sim:speed() * KMH
	check(top < 82, string.format("grass top speed %.1f km/h", top))
	-- a ~15 hp rental kart hardly spins its wheels even on grass; it just
	-- crawls (the old 23 hp setting did spin them)
	check(top > 10, string.format("still pulls away on grass (wheelspin frames %d)", spun))
	-- coasting off: slows quickly
	sim.ctrl.throttle = 0
	local v0 = sim:speed()
	sim:run(2)
	check(sim:speed() < v0 * 0.75, string.format("grass scrubs speed when coasting (%.0f -> %.0f)", v0, sim:speed()))
end

----------------------------------------------------------------------------
print("== Slopes ==")
do
	-- a 6 degree ramp made of two triangles
	local g = World.newGround(-50, 1, 1)
	local ang = math.rad(6)
	local function P(x, z)
		return vector.create(x, -x * math.tan(ang), z)
	end
	g:addTri(P(-200, -50), P(200, -50), P(200, 50), 1, 1)
	g:addTri(P(-200, -50), P(200, 50), P(-200, 50), 1, 1)
	local sim = Sim.spawnOn(g, 0, 0, vector.create(0, 0, 1)) -- facing across the slope
	sim.ctrl.brake = 1
	sim:run(0.2)
	sim.ctrl.brake = 0
	sim:run(2)
	local p0 = sim.body.pos
	sim:run(5)
	check(vector.magnitude(sim.body.pos - p0) < 0.2, string.format("parked across a 6 deg slope (moved %.3f)", vector.magnitude(sim.body.pos - p0)))
	local sim2 = Sim.spawnOn(g, 0, 0, EAST) -- facing downhill, stop with the brake then let go
	sim2.ctrl.brake = 1
	sim2:run(0.2)
	sim2.ctrl.brake = 0
	sim2:run(2)
	local q0 = sim2.body.pos
	sim2:run(5)
	check(vector.magnitude(sim2.body.pos - q0) < 0.5, string.format("parked facing downhill (moved %.3f)", vector.magnitude(sim2.body.pos - q0)))
end

----------------------------------------------------------------------------
print("== Stability ==")
local function headingSlip(sim): number
	local v = sim.body.vel
	if vector.magnitude(v) < 3 then
		return 0
	end
	return math.deg(math.acos(math.clamp(vector.dot(vector.normalize(v), sim.body.look), -1, 1)))
end
do
	-- kicked into a slide (yaw rate) at 60 km/h, hands off: should straighten up
	local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight, 0), EAST)
	sim.body.vel = EAST * (60 / KMH)
	sim.body.angVel = vector.create(0, math.rad(70), 0)
	local maxSlip = 0
	sim:run(3, function()
		maxSlip = math.max(maxSlip, headingSlip(sim))
		return nil
	end)
	check(headingSlip(sim) < 5 and math.abs(sim:yawRate()) < 5, string.format("recovers from a 70 deg/s yaw kick (max slip %.1f, final %.1f deg)", maxSlip, headingSlip(sim)))

	-- at the limit in a corner, then stamp on the brakes / lift off / floor it
	for _, case in { { "full brake", 0, 1 }, { "lift off", 0, 0 }, { "full throttle", 1, 0 } } do
		local s2 = Sim.new(flat(), vector.create(0, cfg.RideHeight, 0), EAST)
		s2.body.vel = EAST * (55 / KMH)
		s2:run(2.5, function()
			s2.ctrl.steer = 0.9
			s2.ctrl.throttle = if s2:speed() < 55 / KMH then 1 else 0
			return nil
		end)
		local maxSlip = 0
		s2.ctrl.throttle, s2.ctrl.brake = case[2], case[3]
		s2:run(2.5, function()
			maxSlip = math.max(maxSlip, headingSlip(s2))
			return s2:speed() < 5 -- stop before it can start reversing
		end)
		check(maxSlip < 25, string.format("mid-corner %s: no spin (max slip %.1f deg)", case[1], maxSlip))
	end
end

----------------------------------------------------------------------------
print("== Kerb strike ==")
do
	-- a 0.35 stud raised strip under the left wheels only, hit at 90 km/h
	local g = World.newGround(0, 1, 1)
	local h = 0.35
	local function P(x, z)
		return vector.create(x, h, z)
	end
	-- left wheels run at z = -4.1 and -4.4, right wheels at about 0
	g:addTri(P(100, -6), P(104, -6), P(104, -2.5), 1, 1)
	g:addTri(P(100, -6), P(104, -2.5), P(100, -2.5), 1, 1)
	local sim = Sim.new(g, vector.create(0, cfg.RideHeight, -2), EAST)
	sim.body.vel = EAST * (90 / KMH)
	sim.ctrl.throttle = 1
	sim:run(4)
	check(sim.maxRoll < 8 and headingSlip(sim) < 3, string.format("kerb at 90 km/h: roll %.1f deg, slip %.1f deg", sim.maxRoll, headingSlip(sim)))
end

----------------------------------------------------------------------------
print("== Frame rates ==")
for _, fps in { 30, 120 } do
	local sim = Sim.new(flat(), vector.create(0, cfg.RideHeight + 0.2, 0), EAST, nil, fps)
	sim:run(2)
	local still = vector.magnitude(sim.body.vel)
	sim.ctrl.throttle = 1
	sim:run(6)
	sim.ctrl.steer = 1
	local spun = false
	sim:run(4, function()
		if headingSlip(sim) > 30 then
			spun = true
		end
		return nil
	end)
	check(still < 0.02 and not spun and sim.maxRoll < 6, string.format("%d fps: rests (%.3f), corners without spin, roll %.1f deg", fps, still, sim.maxRoll))
end

----------------------------------------------------------------------------
print("== Banked hairpin ==")
do
	-- an oval with 12.6 m hairpins: the fastest steady speed the autopilot
	-- carries through one, flat and banked 12 degrees (Hillside's Karussell)
	local function oval(bank: number)
		return TrackMath.build({
			Spacing = 6,
			Smoothing = 10,
			BankSmoothing = 40,
			StartY = 8,
			Segments = {
				{ kind = "S", length = "free", width = 32 },
				{ kind = "A", radius = 45, angle = 180, bank = bank },
				{ kind = "S", length = 300 },
				{ kind = "A", radius = 45, angle = 90, bank = bank },
				{ kind = "S", length = "free" },
				{ kind = "A", radius = 45, angle = 90, bank = bank },
			},
		} :: any)
	end
	local function carries(track, v: number): number?
		local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
		g:addTrack(track, nil, nil, 20)
		local pos, fwd = TrackMath.slot(track, 30, 0, 0)
		local sim = Sim.spawnOn(g, pos.x, pos.z, fwd)
		sim.body.vel = fwd * v
		local plan = table.create(track.n, v)
		local hint = 30
		local inCorner, slowest, result = false, math.huge, nil
		sim:run(15, function()
			local idx, lateral = sim:autopilot(track, plan, hint)
			hint = idx
			local smp = track.samples[idx]
			if math.abs(lateral) > 9 or vector.dot(sim.body.look, smp.fwd) < 0.8 then
				return true
			end
			if smp.segment == 2 then
				inCorner = true
				slowest = math.min(slowest, sim:speed())
			elseif inCorner and smp.segment == 3 then
				result = slowest
				return true
			end
			return nil
		end)
		return result
	end
	local function best(bank: number): number
		local track = oval(bank)
		local lo, hi, got = 20, 110, 0
		for _ = 1, 10 do
			local mid = (lo + hi) / 2
			local r = carries(track, mid)
			if r then
				lo, got = mid, r
			else
				hi = mid
			end
		end
		return got * KMH
	end
	local flatV, bankV = best(0), best(12)
	check(bankV > flatV * 1.1, string.format("banking lets the kart through faster: %.0f km/h flat, %.0f km/h banked 12 deg", flatV, bankV))
end

----------------------------------------------------------------------------
for _, run in { { "Tampines", 60 }, { "Tampines", 30 }, { "Tampines", 20 }, { "Silverstone", 60 }, { "Silverstone", 20 }, { "Lakeside", 60 }, { "Hillside", 60 }, { "Hillside", 20 }, { "Harbour", 60 }, { "Suzuka", 60 }, { "Suzuka", 20 }, { "Catalunya", 60 }, { "Catalunya", 20 }, { "Zandvoort", 60 }, { "Zandvoort", 20 }, { "YasMarina", 60 }, { "YasMarina", 20 } } do
local spec, fps = TrackData.get(run[1]), run[2]
print(string.format("== Autopilot lap of %s (%d fps) ==", spec.Name, fps))
do
	local track = TrackMath.build(spec)
	local g = World.newGround(-0.1, Config.Surfaces.Grass.grip, Config.Surfaces.Grass.roll)
	g:addTrack(track, nil, nil, 20)
	local start = track.samples[1]
	local pos, fwd = TrackMath.slot(track, 1, 0, 20)
	local sim = Sim.spawnOn(g, pos.x, pos.z, fwd, nil, fps)
	local plan = Sim.speedPlan(track, cfg, 0.85)
	local hint = 1
	local lapStart: number? = nil
	local laps = {}
	local maxLateral = 0
	local passedHalf = false
	local fell = false
	local pitchRates: { number } = {}
	sim:run(400, function(res)
		local idx, lateral = sim:autopilot(track, plan, hint)
		if lapStart then
			pitchRates[#pitchRates + 1] = math.deg(vector.dot(sim.body.angVel, sim.body.right))
		end
		hint = idx
		maxLateral = math.max(maxLateral, math.abs(lateral))
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
		if sim.body.pos.y < start.pos.y - 20 then
			fell = true
			return true
		end
		return #laps >= 2
	end)
	check(not fell, "never falls off the world")
	check(#laps >= 2, string.format("completes laps (%d)", #laps))
	if laps[2] then
		local avg = track.length / laps[2]
		check(avg * KMH > 50 and avg * KMH < 95, string.format("flying lap %.2f s (avg %.0f km/h, length %.0f studs)", laps[2], avg * KMH, track.length))
	end
	check(maxLateral < track.samples[2].width / 2, string.format("stays on the road (max offset %.1f studs)", maxLateral))
	-- roll against the world: the banking adds its own lean
	local maxBank = 0
	for _, smp in track.samples do
		maxBank = math.max(maxBank, math.abs(smp.bank))
	end
	check(sim.maxRoll < 12 + maxBank, string.format("max roll %.1f deg (road banked up to %.1f)", sim.maxRoll, maxBank))
	-- a crest or a bank winding off can lift a wheel for a frame now and then
	check(sim.lowContactFrames < sim.frames * 0.005, string.format("wheels stay down (%d of %d frames on fewer than 3)", sim.lowContactFrames, sim.frames))
	check(sim.airborneFrames < 10, string.format("airborne frames %d (crest)", sim.airborneFrames))
	check(sim.body.bottomHits < 30, string.format("chassis scrapes %d substeps", sim.body.bottomHits))
	-- ride: pitch rate minus its 0.15 s average (the rattle over road folds
	-- and facets; the hills used to be 7x the flat circuits)
	local half = math.max(1, math.floor(0.075 * fps + 0.5))
	local sum2 = 0
	for i = 1, #pitchRates do
		local avg, cnt = 0, 0
		for j = math.max(1, i - half), math.min(#pitchRates, i + half) do
			avg += pitchRates[j]
			cnt += 1
		end
		sum2 += (pitchRates[i] - avg / cnt) ^ 2
	end
	local jitter = math.sqrt(sum2 / math.max(#pitchRates, 1))
	local limit = if fps >= 60 then 1.0 elseif fps >= 30 then 1.3 else 1.6
	check(jitter < limit, string.format("smooth ride: pitch jitter %.2f deg/s (limit %.1f)", jitter, limit))
end
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
