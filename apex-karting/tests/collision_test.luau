-- Kart-to-kart bumper contact: two karts on flat ground, each stepped by
-- KartPhysics with the other as an obstacle (the way two clients do it).
-- Checks that hits push, shove and spin karts believably and never launch
-- them, at 60 and 20 fps, and that the network lead cures most of a
-- 0.15 s delay. Run from the project root:  luau tests/collision_test.luau
local Config = require("../src/shared/Config")
local KartPhysics = require("../src/shared/KartPhysics")
local World = require("./lib/world")
local Sim = require("./lib/sim")

local cfg = Config.Kart
local bm = cfg.Bumper
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
local NORTH = vector.create(0, 0, -1)

local function newKart(x: number, z: number, look: vector, kmh: number, fps: number?)
	local ground = World.newGround(0, 1, 1)
	local sim = Sim.new(ground, vector.create(x, cfg.RideHeight, z), look, nil, fps)
	sim.body.vel = vector.normalize(look) * (kmh / KMH)
	return sim
end

-- true overlap of the two outlines right now (studs, > 0 = overlapping)
local function overlap(a, b): number
	local oa, ob = a:obstacle(), b:obstacle()
	local _, _, pen = KartPhysics.bumperContact(bm, a.body:snapshot(), ob, 0)
	local _, _, pen2 = KartPhysics.bumperContact(bm, b.body:snapshot(), oa, 0)
	return math.max(pen, pen2)
end

-- signed gap between the outlines (< 0 = overlapping), from a's outline points
local function separation(a, b): number
	local best = math.huge
	local fA = vector.normalize(vector.create(a.body.look.x, 0, a.body.look.z))
	local rA = vector.cross(fA, vector.create(0, 1, 0))
	local fB = vector.normalize(vector.create(b.body.look.x, 0, b.body.look.z))
	local rB = vector.cross(fB, vector.create(0, 1, 0))
	for _, q in KartPhysics.bumperOutline(bm) do
		local p = a.body.pos + rA * q.x + fA * q.f
		local rel = p - b.body.pos
		local d = KartPhysics.bumperSdf(bm, vector.dot(rel, rB), vector.dot(rel, fB))
		best = math.min(best, d)
	end
	return best
end

type Stats = { maxPen: number, maxVy: number, maxYaw: number, firstTouch: number?, touchOverlap: number? }

-- Steps both karts together for `seconds`. `delay` holds each kart's view of
-- the other back by that many seconds; `lead` extrapolates it forward again.
local function run(a, b, seconds: number, delay: number?, lead: number?, each: ((number) -> ())?): Stats
	local st: Stats = { maxPen = 0, maxVy = 0, maxYaw = 0, firstTouch = nil, touchOverlap = nil }
	local histA, histB = {}, {}
	local frames = math.floor(seconds / a.frame + 0.5)
	local lagFrames = math.floor((delay or 0) / a.frame + 0.5)
	for f = 1, frames do
		table.insert(histA, a:obstacle())
		table.insert(histB, b:obstacle())
		local function seen(hist)
			local o = hist[math.max(1, #hist - lagFrames)]
			local l = lead or 0
			return { pos = o.pos + o.vel * l, look = o.look, vel = o.vel, angVel = o.angVel }
		end
		local ra = a:step({ seen(histB) })
		b:step({ seen(histA) })
		if ra.contact > 0 and not st.firstTouch then
			st.firstTouch = f * a.frame
			st.touchOverlap = -separation(a, b)
		end
		st.maxPen = math.max(st.maxPen, overlap(a, b))
		for _, k in { a, b } do
			st.maxVy = math.max(st.maxVy, math.abs(k.body.vel.y))
			st.maxYaw = math.max(st.maxYaw, math.abs(k:yawRate()))
		end
		if each then
			each(f * a.frame)
		end
	end
	return st
end

local function speed(k): number
	return vector.magnitude(vector.create(k.body.vel.x, 0, k.body.vel.z)) * KMH
end

local function forward(k): number
	return k:speed() * KMH
end

----------------------------------------------------------------------------
print("== Outline ==")
do
	local d0 = KartPhysics.bumperSdf(bm, 0, 0)
	local dFront = KartPhysics.bumperSdf(bm, 0, bm.Front)
	local dSide = KartPhysics.bumperSdf(bm, bm.HalfWidth, 0)
	local dOut = KartPhysics.bumperSdf(bm, bm.HalfWidth + 1, bm.Front + 1)
	check(d0 < 0 and math.abs(dFront) < 1e-6 and math.abs(dSide) < 1e-6, string.format("signed distance: centre %.2f, front edge %.3f, side %.3f", d0, dFront, dSide))
	check(math.abs(dOut - (math.sqrt(2 * (1 + bm.Corner) ^ 2) - bm.Corner)) < 1e-6, string.format("outside a corner %.3f", dOut))
	local pts = KartPhysics.bumperOutline(bm)
	local worst = 0
	for _, p in pts do
		worst = math.max(worst, math.abs(KartPhysics.bumperSdf(bm, p.x, p.f)))
	end
	check(#pts > 20 and worst < 1e-6, string.format("%d outline points, all on the outline (%.1e)", #pts, worst))
end

----------------------------------------------------------------------------
for _, fps in { 60, 20 } do
	print(string.format("== Rear-end, 55 into 30 km/h, coasting (%d fps) ==", fps))
	local gap = 2
	local a = newKart(0, 0, EAST, 55, fps)
	local b = newKart(bm.Front + bm.Rear + gap, 0, EAST, 30, fps)
	local m = a.body.mass
	local p0 = m * (forward(a) + forward(b))
	local after: number? = nil
	local st = run(a, b, 1.5, nil, nil, function(t)
		if not after and t > 0.1 and overlap(a, b) <= 0 and forward(b) > 35 then
			after = t
		end
	end)
	local va, vb = forward(a), forward(b)
	print(string.format("    after: front %.1f km/h, rear %.1f km/h, deepest overlap %.2f studs", vb, va, st.maxPen))
	check(vb > 37 and va < 48, "the kart in front is shoved faster, the one behind slows")
	check(math.abs(m * (va + vb) - p0) / p0 < 0.12, string.format("momentum kept (%.0f -> %.0f)", p0, m * (va + vb)))
	local e = (vb - va) / (55 - 30)
	check(e > 0.1 and e < 0.45, string.format("restitution %.2f (bumpers give a little bounce)", e))
	check(st.maxPen > 0.1 and st.maxPen < 1.3, string.format("bumpers squash %.2f studs", st.maxPen))
	check(st.maxVy < 1.5 and a.maxRoll < 4 and b.maxPitch < 6, string.format("nobody launches (vertical %.2f studs/s, roll %.1f, pitch %.1f)", st.maxVy, a.maxRoll, b.maxPitch))
	check(st.maxYaw < 10, string.format("a straight hit does not spin anyone (%.1f deg/s)", st.maxYaw))
end

----------------------------------------------------------------------------
print("== Head-on, 30 km/h each ==")
do
	local a = newKart(0, 0, EAST, 30)
	local b = newKart(bm.Front * 2 + 2, 0, -EAST, 30)
	local va, vb = 0, 0
	local touched, parted = false, false
	local st = run(a, b, 1.5, nil, nil, function()
		local o = overlap(a, b)
		if o > 0 then
			touched = true
		elseif touched and not parted then
			parted = true
			va, vb = forward(a), forward(b)
		end
	end)
	check(parted and va < 0 and vb < 0, string.format("both bounce back (%.1f, %.1f km/h as they part)", va, vb))
	check(-va < 12 and -vb < 12, "but not far")
	check(st.maxPen < 2.4, string.format("deepest overlap %.2f studs", st.maxPen))
	check(st.maxVy < 2 and a.maxPitch < 8, string.format("no launch (vertical %.2f, pitch %.1f)", st.maxVy, a.maxPitch))
end

----------------------------------------------------------------------------
print("== Side by side at 60 km/h, one squeezes the other ==")
do
	local a = newKart(0, 0, EAST, 60)
	local b = newKart(0, bm.HalfWidth * 2 + 0.6, EAST, 60) -- on A's right (+z)
	local zB0 = b.body.pos.z
	local st = run(a, b, 2.0, nil, nil, function(t)
		a.ctrl.throttle, b.ctrl.throttle = 1, 1
		a.ctrl.steer = if t < 0.7 then 0.35 else 0
	end)
	local pushed = b.body.pos.z - zB0
	print(string.format("    pushed %.2f studs sideways, deepest overlap %.2f, yaw up to %.0f deg/s", pushed, st.maxPen, st.maxYaw))
	check(st.firstTouch ~= nil and pushed > 0.6, "the kart alongside gets shoved over")
	check(st.maxPen < 1.0, "bumpers rub, they do not pass through")
	check(st.maxYaw < 90 and a.maxRoll < 5 and b.maxRoll < 5, string.format("no spin, no tip (roll %.1f / %.1f deg)", a.maxRoll, b.maxRoll))
	check(st.maxVy < 1.5, string.format("wheels stay down (vertical %.2f)", st.maxVy))
end

----------------------------------------------------------------------------
print("== T-bone at 40 km/h into a parked kart ==")
do
	local b = newKart(0, 0, NORTH, 0)
	local a = newKart(-(bm.HalfWidth + bm.Front + 1.5), 0, EAST, 40)
	local x0 = b.body.pos.x
	local st = run(a, b, 1.5)
	local moved = b.body.pos.x - x0
	print(string.format("    struck kart moved %.2f studs, striker now %.1f km/h", moved, forward(a)))
	check(moved > 0.8, "the struck kart is shoved sideways")
	check(forward(a) < 20, "the striker loses most of its speed")
	check(st.maxPen < 1.8 and b.maxRoll < 8, string.format("no pass-through, no flip (overlap %.2f, roll %.1f)", st.maxPen, b.maxRoll))
end

----------------------------------------------------------------------------
print("== Clipping a rear corner at 50 km/h spins the other kart ==")
do
	local b = newKart(0, 0, EAST, 25)
	-- A behind and to the left, its right front corner hits B's left rear corner
	local a = newKart(-(bm.Front + bm.Rear + 1.5), -(bm.HalfWidth * 2 - 1.6), EAST, 50)
	local st = run(a, b, 1.5)
	print(string.format("    peak yaw %.0f deg/s", st.maxYaw))
	check(st.maxYaw > 25 and st.maxYaw < 400, "a corner hit turns the struck kart")
	check(st.maxVy < 1.5 and b.maxRoll < 6, string.format("still no launch (vertical %.2f)", st.maxVy))
end

----------------------------------------------------------------------------
print("== Network delay 0.15 s each way, rear-end 55 into 30 ==")
do
	-- start 12 studs apart so each kart's delayed view is full before the hit
	local function trial(delay: number?, lead: number?): Stats
		local a = newKart(0, 0, EAST, 55)
		local b = newKart(bm.Front + bm.Rear + 12, 0, EAST, 30)
		return run(a, b, 2.0, delay, lead)
	end
	local raw = trial(0.15, 0)
	local led = trial(0.15, 0.15)
	local fresh = trial()
	-- touchOverlap < 0: the push started while there was still a gap
	print(string.format("    first push at a true gap of %.2f studs without lead, %.2f with lead, %.2f with no delay", -(raw.touchOverlap or 0), -(led.touchOverlap or 0), -(fresh.touchOverlap or 0)))
	check(-(raw.touchOverlap or 0) > 2, "a stale view pushes the follower while there is still a gap (a phantom hit)")
	check(math.abs(led.touchOverlap or 99) < 0.5, "extrapolating by the delay makes the push start at the real touch")
	print(string.format("    deepest overlap: %.2f without lead, %.2f with, %.2f with no delay", raw.maxPen, led.maxPen, fresh.maxPen))
	check(math.abs(led.maxPen - fresh.maxPen) < math.abs(raw.maxPen - fresh.maxPen) + 0.05, "and the hit plays out closer to the no-delay one")
end

----------------------------------------------------------------------------
print("== Parked side by side, slightly overlapping ==")
do
	local a = newKart(0, 0, EAST, 0)
	local b = newKart(0, bm.HalfWidth * 2 - 0.4, EAST, 0)
	local st = run(a, b, 2)
	local sep = vector.magnitude(b.body.vel - a.body.vel)
	check(overlap(a, b) <= 0.1, string.format("eased apart (overlap now %.3f)", overlap(a, b)))
	check(sep < 1.5 and st.maxYaw < 15, string.format("gently (%.2f studs/s apart, yaw %.1f deg/s)", sep, st.maxYaw))
end

----------------------------------------------------------------------------
print("== Slipstream ==")
do
	-- two karts flat out down a long straight, the second 14 studs behind
	local a = newKart(0, 0, EAST, 95) -- leader
	local b = newKart(-14, 0, EAST, 95) -- follower
	a.ctrl.throttle, b.ctrl.throttle = 1, 1
	local gap0 = a.body.pos.x - b.body.pos.x
	local peakDraft, maxGain = 0, 0
	run(a, b, 3, nil, nil, function()
		a.ctrl.throttle, b.ctrl.throttle = 1, 1
		peakDraft = math.max(peakDraft, b.state.draft)
		maxGain = math.max(maxGain, forward(b) - forward(a))
	end)
	local gap1 = a.body.pos.x - b.body.pos.x
	print(string.format("    tow up to %.2f, follower up to %.1f km/h faster, gap %.1f -> %.1f studs", peakDraft, maxGain, gap0, gap1))
	check(peakDraft > 0.5 and a.state.draft < 0.01, "the follower gets a tow, the leader does not")
	check(maxGain > 2 and gap1 < gap0 - 3, "and closes in on the straight")
	-- alongside: no tow
	local c = newKart(0, 0, EAST, 95)
	local d = newKart(-2, 8, EAST, 95)
	run(c, d, 1.5, nil, nil, function()
		c.ctrl.throttle, d.ctrl.throttle = 1, 1
	end)
	check(d.state.draft < 0.05, string.format("side by side there is no tow (%.2f)", d.state.draft))
end

----------------------------------------------------------------------------
print("== A crossing: one kart on the bridge, one on the road under it ==")
do
	-- the same spot from above, 14 studs apart in height (Suzuka's bridge)
	local low = newKart(0, 0, EAST, 0)
	local high = newKart(0, 0.5, NORTH, 0)
	high.body.pos += vector.create(0, 14, 0)
	local f, _, pen = KartPhysics.bumperContact(bm, low.body:snapshot(), high:obstacle(), 0)
	check(pen == 0 and vector.magnitude(f) == 0, string.format("no bump between the two levels (overlap %.2f)", pen))
	-- flat out, the one under the bridge just behind the one on it: no tow
	local a = newKart(0, 0, EAST, 95)
	a.body.pos += vector.create(0, 14, 0)
	local b = newKart(-14, 0, EAST, 95)
	local tow = KartPhysics.draftTarget(cfg, b.body:snapshot(), { a:obstacle() })
	check(tow == 0, string.format("no tow from a kart on the other level (%.2f)", tow))
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
