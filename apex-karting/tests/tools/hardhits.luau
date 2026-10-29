-- Hard hits: do two karts come apart, or end up locked inside each other?
-- Prints, per hit: deepest overlap, how long they stay overlapping and the
-- overlap left at the end. Each client sees the other `delay` late (with
-- the contact echo). Not pass/fail. Run from the project root:
--   luau tests/tools/hardhits.luau     (-a "HardDepth HardStiffness HardMax" to try others)
local Config = require("../../src/shared/Config")
local KartPhysics = require("../../src/shared/KartPhysics")
local World = require("../lib/world")
local Sim = require("../lib/sim")

local cfg = Config.Kart
local bm = cfg.Bumper
local KMH = Config.KmhPerStudPerSecond

local function kart(x: number, z: number, look: vector, kmh: number)
	local sim = Sim.new(World.newGround(0, 1, 1), vector.create(x, cfg.RideHeight, z), vector.normalize(look), nil, 60)
	sim.body.vel = vector.normalize(look) * (kmh / KMH)
	return sim
end

local function overlap(a, b): number
	local _, _, p1 = KartPhysics.bumperContact(bm, a.body:snapshot(), b:obstacle(), 0)
	local _, _, p2 = KartPhysics.bumperContact(bm, b.body:snapshot(), a:obstacle(), 0)
	return math.max(p1, p2)
end

local function run(a, b, delay: number, throttleA: number, throttleB: number)
	local lag = math.floor(delay * 60 + 0.5)
	local hA, hB = {}, {}
	local eA, eB = KartPhysics.newEcho(), KartPhysics.newEcho()
	local maxPen, stuck = 0, 0
	for _ = 1, 180 do
		table.insert(hA, a:obstacle())
		table.insert(hB, b:obstacle())
		local function seen(h)
			local o = h[math.max(1, #h - lag)]
			return { pos = o.pos + o.vel * delay, look = o.look, vel = o.vel, angVel = o.angVel }
		end
		local now = a.t
		local sb = KartPhysics.echoApply(eA, "b", seen(hB), now, delay + a.frame)
		local sa = KartPhysics.echoApply(eB, "a", seen(hA), now, delay + a.frame)
		a.ctrl.throttle, b.ctrl.throttle = throttleA, throttleB
		local ra, rb = a:step({ sb }), b:step({ sa })
		KartPhysics.echoAdd(eA, "b", ra.bumps[1], now)
		KartPhysics.echoAdd(eB, "a", rb.bumps[1], now)
		local o = overlap(a, b)
		maxPen = math.max(maxPen, o)
		if o > 0.5 then
			stuck += a.frame
		end
	end
	return maxPen, stuck, overlap(a, b)
end

local arg = ...
if arg then
	local v = {}
	for x in string.gmatch(arg, "[^%s]+") do
		table.insert(v, tonumber(x))
	end
	bm.HardDepth, bm.HardStiffness, bm.HardMax = v[1], v[2], v[3]
end
print(string.format("HardDepth %s, HardStiffness %s, HardMax %s", tostring(bm.HardDepth), tostring(bm.HardStiffness), tostring(bm.HardMax)))
local E, W, N = vector.create(1, 0, 0), vector.create(-1, 0, 0), vector.create(0, 0, -1)
local cases = {
	{ "head-on 90 + 90", function() return kart(0, 0, E, 90), kart(bm.Front * 2 + 25, 0, W, 90), 1, 1 end },
	{ "head-on 60 + 60, both on the gas", function() return kart(0, 0, E, 60), kart(bm.Front * 2 + 20, 0, W, 60), 1, 1 end },
	{ "rear-end 95 into a stopped kart", function() return kart(0, 0, E, 95), kart(bm.Front + bm.Rear + 25, 0, E, 0), 1, 0 end },
	{ "T-bone 90", function() return kart(-(bm.HalfWidth + bm.Front + 25), 0, E, 90), kart(0, 0, N, 0), 1, 0 end },
	{ "corner into side 80, angled", function() return kart(-20, 14, vector.create(1, 0, -0.7), 80), kart(0, 0, E, 30), 1, 1 end },
}
for _, delay in { 0, 0.1 } do
	for _, c in cases do
		local a, b, ta, tb = c[2]()
		local pen, stuck, left = run(a, b, delay, ta, tb)
		print(string.format("delay %.1f  %-36s deepest %.2f studs, overlapping > 0.5 for %.2f s, at the end %.2f", delay, c[1], pen, stuck, left))
	end
end
