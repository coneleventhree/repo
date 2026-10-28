-- Bumper hits as two clients play them: each kart sees the other `delay`
-- seconds late and extrapolates it forward by that much (a perfect lead).
-- Prints bounce (restitution), momentum gained and the speeds after the hit
-- for each delay. Not pass/fail. Run from the project root:
--   luau tests/tools/lagbumps.luau        (-a off: without the contact echo)
local Config = require("../../src/shared/Config")
local KartPhysics = require("../../src/shared/KartPhysics")
local World = require("../lib/world")
local Sim = require("../lib/sim")

local cfg = Config.Kart
local bm = cfg.Bumper
local KMH = Config.KmhPerStudPerSecond
local EAST = vector.create(1, 0, 0)
local NORTH = vector.create(0, 0, -1)

local function kart(x: number, z: number, look: vector, kmh: number)
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(x, cfg.RideHeight, z), look, nil, 60)
	sim.body.vel = look * (kmh / KMH)
	return sim
end

local function overlap(a, b): number
	local _, _, p1 = KartPhysics.bumperContact(bm, a.body:snapshot(), b:obstacle(), 0)
	local _, _, p2 = KartPhysics.bumperContact(bm, b.body:snapshot(), a:obstacle(), 0)
	return math.max(p1, p2)
end

local USE_ECHO = (...) ~= "off"

local function run(a, b, seconds: number, delay: number)
	local eA, eB = KartPhysics.newEcho(), KartPhysics.newEcho()
	local lead = delay
	local lag = math.floor(delay * 60 + 0.5)
	local hA, hB = {}, {}
	local touched, parted = false, false
	local maxPen = 0
	for _ = 1, math.floor(seconds * 60) do
		table.insert(hA, a:obstacle())
		table.insert(hB, b:obstacle())
		local function seen(h)
			local o = h[math.max(1, #h - lag)]
			return { pos = o.pos + o.vel * lead, look = o.look, vel = o.vel, angVel = o.angVel }
		end
		local now = a.t
		local sb, sa = seen(hB), seen(hA)
		if USE_ECHO then
			sb = KartPhysics.echoApply(eA, "b", sb, now, lead + a.frame)
			sa = KartPhysics.echoApply(eB, "a", sa, now, lead + a.frame)
		end
		local ra = a:step({ sb })
		local rb = b:step({ sa })
		KartPhysics.echoAdd(eA, "b", ra.bumps[1], now)
		KartPhysics.echoAdd(eB, "a", rb.bumps[1], now)
		local o = overlap(a, b)
		maxPen = math.max(maxPen, o)
		if o > 0 then
			touched = true
		elseif touched and not parted then
			parted = true
		end
	end
	return maxPen
end

local function along(k, dir: vector): number
	return vector.dot(k.body.vel, dir) * KMH
end

for _, delay in { 0, 0.05, 0.1, 0.15, 0.25 } do
	-- rear-end 55 into 30 (closing 25 km/h), coasting
	local a, b = kart(0, 0, EAST, 55), kart(bm.Front + bm.Rear + 14, 0, EAST, 30)
	local pen = run(a, b, 1.2, delay)
	local va, vb = along(a, EAST), along(b, EAST)
	local e = (vb - va) / 25
	-- head-on 30 + 30
	local c, d = kart(0, 0, EAST, 30), kart(bm.Front * 2 + 16, 0, -EAST, 30)
	local pen2 = run(c, d, 1.2, delay)
	local e2 = (along(d, EAST) - along(c, EAST)) / 60
	-- side by side at 50, B steers into A for 0.3 s
	local s, t = kart(0, 0, EAST, 50), kart(0, -(bm.HalfWidth * 2 + 0.6), EAST, 50)
	local lead = delay
	local lag = math.floor(delay * 60 + 0.5)
	local hS, hT = {}, {}
	local eS, eT = KartPhysics.newEcho(), KartPhysics.newEcho()
	local maxLat = 0
	for f = 1, 90 do
		table.insert(hS, s:obstacle())
		table.insert(hT, t:obstacle())
		local function seen(h)
			local o = h[math.max(1, #h - lag)]
			return { pos = o.pos + o.vel * lead, look = o.look, vel = o.vel, angVel = o.angVel }
		end
		t.ctrl.steer = if f < 18 then 0.5 else 0
		s.ctrl.throttle, t.ctrl.throttle = 0.6, 0.6
		local now = s.t
		local st, ss = seen(hT), seen(hS)
		if USE_ECHO then
			st = KartPhysics.echoApply(eS, "t", st, now, lead + s.frame)
			ss = KartPhysics.echoApply(eT, "s", ss, now, lead + s.frame)
		end
		local rs = s:step({ st })
		local rt = t:step({ ss })
		KartPhysics.echoAdd(eS, "t", rs.bumps[1], now)
		KartPhysics.echoAdd(eT, "s", rt.bumps[1], now)
		maxLat = math.max(maxLat, math.abs(vector.dot(s.body.vel, NORTH)) * KMH, math.abs(vector.dot(t.body.vel, NORTH)) * KMH)
	end
	print(string.format("delay %.2f s | rear-end: after %4.1f / %4.1f km/h, bounce %.2f, squash %.2f | head-on: bounce %.2f, squash %.2f | side swipe: peak sideways %4.1f km/h",
		delay, va, vb, e, pen, e2, pen2, maxLat))
end
