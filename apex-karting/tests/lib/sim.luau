-- Runs the real KartPhysics model on the headless world.
local Config = require("../../src/shared/Config")
local KartPhysics = require("../../src/shared/KartPhysics")
local TrackMath = require("../../src/shared/TrackMath")
local World = require("./world")

local Sim = {}
Sim.__index = Sim

-- Roblox steps physics at 240 Hz; the client updates forces once per frame.
local PHYSICS_HZ = 240

function Sim.new(ground, pos: vector, look: vector, cfg: any?, fps: number?)
	cfg = cfg or Config.Kart
	local frame = 1 / (fps or 60)
	local body = World.newBody(cfg.CoreSize, cfg.Density, pos, look, cfg.BoxSize, cfg.BoxOffsetY, cfg.BoxOffsetZ)
	return setmetatable({
		cfg = cfg,
		ground = ground,
		body = body,
		state = KartPhysics.newState(cfg),
		ctrl = { throttle = 0, brake = 0, steer = 0 },
		frame = frame,
		sub = math.max(1, math.floor(PHYSICS_HZ * frame + 0.5)),
		t = 0,
		last = nil :: any,
		maxRoll = 0,
		maxPitch = 0,
		airborneFrames = 0,
		lowContactFrames = 0,
		frames = 0,
	}, Sim)
end

-- Places the kart standing on the ground at its ride height.
function Sim.spawnOn(ground, x: number, z: number, look: vector, cfg: any?, fps: number?)
	cfg = cfg or Config.Kart
	local gy = ground:heightAt(x, z, 200)
	return Sim.new(ground, vector.create(x, gy + cfg.RideHeight, z), look, cfg, fps)
end

-- `others`: obstacles (other karts) for the bumpers, see Sim:obstacle().
function Sim:step(others: { any }?)
	local b = self.body
	local frame, sub = self.frame, self.sub
	local res = KartPhysics.step(self.cfg, self.state, b:snapshot(), self.ctrl, frame, function(o, d)
		return self.ground:raycast(o, d)
	end, others)
	self.last = res
	for _ = 1, sub do
		b:integrate(res.force, res.torque, self.cfg.Gravity, frame / sub)
		b:collideGround(self.ground, frame / sub)
	end
	self.t += frame
	self.frames += 1
	local roll, pitch = b:attitude()
	self.maxRoll = math.max(self.maxRoll, math.abs(roll))
	self.maxPitch = math.max(self.maxPitch, math.abs(pitch))
	if res.grounded == 0 then
		self.airborneFrames += 1
	elseif res.grounded < 3 then
		self.lowContactFrames += 1
	end
	return res
end

function Sim:run(seconds: number, each: ((any) -> boolean?)?)
	local frames = math.floor(seconds / self.frame + 0.5)
	for _ = 1, frames do
		local res = self:step()
		if each and each(res) then
			return true
		end
	end
	return false
end

-- This kart as another kart sees it (an Obstacle for KartPhysics.step).
function Sim:obstacle(): any
	local b = self.body
	return { pos = b.pos, look = b.look, vel = b.vel, angVel = b.angVel }
end

function Sim:speed(): number
	return vector.dot(self.body.vel, self.body.look)
end

function Sim:yawRate(): number
	return math.deg(vector.dot(self.body.angVel, self.body.up))
end

----------------------------------------------------------------------------
-- Autopilot: pure pursuit on the centre line with a curvature speed plan.
----------------------------------------------------------------------------
function Sim.speedPlan(track, cfg, margin: number)
	local n = track.n
	local mu = cfg.Mu * margin
	local v = table.create(n, 0)
	for i = 1, n do
		-- average curvature over a short window to ignore sample noise
		local k = 0
		for j = -2, 2 do
			k += math.abs(track.samples[TrackMath.wrap(i + j, n)].curv)
		end
		k /= 5
		v[i] = math.min(cfg.TopSpeed, math.sqrt(mu * cfg.Gravity / math.max(k, 1e-5)))
	end
	-- braking pass (backwards, twice round the loop)
	local aBrake = cfg.Mu * cfg.Gravity * 0.55 * margin
	for _ = 1, 2 do
		for i = n, 1, -1 do
			local nxt = v[TrackMath.wrap(i + 1, n)]
			v[i] = math.min(v[i], math.sqrt(nxt * nxt + 2 * aBrake * track.spacing))
		end
	end
	return v
end

function Sim:autopilot(track, plan, hint: number)
	local b = self.body
	local idx, lateral = TrackMath.nearest(track, b.pos, hint, 10, 30)
	local speed = self:speed()
	local lookAhead = 7 + 0.3 * math.abs(speed)
	local steps = math.max(1, math.floor(lookAhead / track.spacing + 0.5))
	local target = track.samples[TrackMath.wrap(idx + steps, track.n)].pos
	-- angle to target in the kart's horizontal plane
	local to = target - b.pos
	local x = vector.dot(to, b.right)
	local f = vector.dot(to, b.look)
	local alpha = math.atan2(x, f)
	local g = KartPhysics.geometry(self.cfg)
	local delta = math.atan(2 * g.wheelbase * math.sin(alpha) / lookAhead)
	self.ctrl.steer = KartPhysics.inputFor(self.cfg, delta, b:snapshot())
	-- speed: the slowest planned speed between here and the look-ahead point
	-- (so it does not floor it while still in the corner)
	local vt = math.huge
	for j = 0, steps do
		vt = math.min(vt, plan[TrackMath.wrap(idx + j, track.n)])
	end
	if speed < vt - 1 then
		self.ctrl.throttle, self.ctrl.brake = 1, 0
	elseif speed > vt + 2 then
		self.ctrl.throttle, self.ctrl.brake = 0, math.clamp((speed - vt) / 10, 0.2, 1)
	else
		self.ctrl.throttle, self.ctrl.brake = 0.3, 0
	end
	return idx, lateral
end

return Sim
