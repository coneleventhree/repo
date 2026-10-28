-- Bumper contact report: how deep the bumpers squash, how much they bounce
-- and how fast overlapping karts are eased apart, for a few typical hits.
-- Not pass/fail. Run from the project root:  luau tests/tools/bumps.luau
-- (with -a "Stiffness SpringMax Damping MaxAccel" to try other numbers)
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

-- runs until the bumpers part (or `seconds`); returns deepest overlap and the
-- velocities at the moment they part
local function hit(a, b, seconds: number): (number, vector, vector, number)
	local deepest, touched = 0, false
	local peakAccel = 0
	for _ = 1, math.floor(seconds * 60) do
		local va0 = a.body.vel
		local oa, ob = a:obstacle(), b:obstacle()
		a:step({ ob })
		b:step({ oa })
		peakAccel = math.max(peakAccel, vector.magnitude(a.body.vel - va0) * 60)
		local o = overlap(a, b)
		deepest = math.max(deepest, o)
		if o > 0 then
			touched = true
		elseif touched then
			break
		end
	end
	return deepest, a.body.vel, b.body.vel, peakAccel
end

local function report()
	-- rear-end, closing 25
	local a, b = kart(0, 0, EAST, 55), kart(bm.Front + bm.Rear + 1, 0, EAST, 30)
	local pen1, va, vb, g1 = hit(a, b, 2)
	local e1 = (vector.dot(vb, EAST) - vector.dot(va, EAST)) / (25 / KMH)
	-- head-on, closing 60
	a, b = kart(0, 0, EAST, 30), kart(bm.Front * 2 + 1, 0, -EAST, 30)
	local pen2, va2, vb2, g2 = hit(a, b, 2)
	local e2 = (vector.dot(vb2, EAST) - vector.dot(va2, EAST)) / (60 / KMH)
	-- T-bone at 40 into a parked kart
	b = kart(0, 0, NORTH, 0)
	a = kart(-(bm.HalfWidth + bm.Front + 1), 0, EAST, 40)
	local pen3, _, vb3, g3 = hit(a, b, 2)
	-- parked, 2 studs deep side by side (after a lag spike or a reset)
	a, b = kart(0, 0, EAST, 0), kart(0, bm.HalfWidth * 2 - 2, EAST, 0)
	local _, va4, vb4 = hit(a, b, 3)
	local apart = vector.magnitude(vb4 - va4) * KMH
	print(string.format("rear-end 55>30: squash %.2f bounce %.2f peak %.1f g | head-on 30+30: squash %.2f bounce %.2f peak %.1f g | T-bone 40: squash %.2f shove %.0f km/h peak %.1f g | 2-stud overlap at rest: apart at %.1f km/h",
		pen1, e1, g1 / cfg.Gravity, pen2, e2, g2 / cfg.Gravity, pen3, vector.magnitude(vb3) * KMH, g3 / cfg.Gravity, apart))
end

local arg = ...
if arg then
	local v = {}
	for x in string.gmatch(arg, "[^%s]+") do
		table.insert(v, tonumber(x))
	end
	bm.Stiffness, bm.SpringMax, bm.Damping, bm.MaxAccel = v[1], v[2], v[3], v[4]
end
print(string.format("Stiffness %g, SpringMax %g, Damping %g, MaxAccel %g", bm.Stiffness, bm.SpringMax, bm.Damping, bm.MaxAccel))
report()
