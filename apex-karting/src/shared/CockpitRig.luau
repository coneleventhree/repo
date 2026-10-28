--!strict
-- The cockpit (first-person) camera, as pure maths so it can be tested.
--
-- A camera bolted rigidly to the chassis shows every twitch of the body, and
-- extra effects that react instantly (head sway, look-into-turn) add their
-- own jolt. Racing sims soften this, and so does this rig:
--
--   yaw     follows the kart exactly (you are sitting in it)
--   tilt    only a share of the kart's pitch and roll reaches the view
--           (horizon stabilisation), through a critically damped spring
--   head    sways a little with g-forces (outward in corners, forward under
--           braking); filtered acceleration drives a critically damped spring
--           so it eases in and out and never bounces back past centre
--   glance  the view turns a few degrees into the corner, eased the same way
--
-- Critically damped springs reach their target without overshoot, which is
-- what removes the "kick back" when the steering is released.

local CockpitRig = {}

export type Settings = {
	Eye: { number }, -- x, height above ground, forward (kart frame)
	Pitch: number, -- degrees
	HeadG: number, -- studs of sway per g, sideways
	HeadGForward: number, -- studs per g, fore/aft
	HeadMax: number, -- studs
	HeadResponse: number, -- 1/s, how quickly the sway follows
	AccelFilter: number, -- 1/s, low-pass on the measured acceleration
	TiltFollow: number, -- share of the kart's pitch/roll shown (0 = level horizon)
	TiltResponse: number, -- 1/s
	LookIntoTurn: number, -- degrees per degree/s of yaw rate
	MaxLookIntoTurn: number, -- degrees
	LookResponse: number, -- 1/s
}

export type Pose = {
	pos: vector,
	right: vector,
	up: vector,
	look: vector,
	vel: vector,
	angVel: vector,
}

export type State = {
	lastVel: vector?,
	accel: vector, -- filtered, kart frame (x right, y up, z forward)
	head: vector, -- sway offset, kart frame
	headVel: vector,
	tiltUp: vector, -- smoothed "up" of the view, world
	tiltVel: vector,
	glance: number, -- degrees
	glanceVel: number,
}

local WORLD_UP = vector.create(0, 1, 0)

function CockpitRig.new(): State
	return {
		lastVel = nil,
		accel = vector.zero,
		head = vector.zero,
		headVel = vector.zero,
		tiltUp = WORLD_UP,
		tiltVel = vector.zero,
		glance = 0,
		glanceVel = 0,
	}
end

-- Critically damped spring towards `target` (exact for constant target).
local function spring(x: number, v: number, target: number, omega: number, dt: number): (number, number)
	local e = math.exp(-omega * dt)
	local d = x - target
	local t = (v + omega * d) * dt
	return target + (d + t) * e, (v - omega * t) * e
end
CockpitRig.spring = spring

local function springV(x: vector, v: vector, target: vector, omega: number, dt: number): (vector, vector)
	local e = math.exp(-omega * dt)
	local d = x - target
	local t = (v + d * omega) * dt
	return target + (d + t) * e, (v - t * omega) * e
end

local function rotate(v: vector, axis: vector, angle: number): vector
	local c, s = math.cos(angle), math.sin(angle)
	return v * c + vector.cross(axis, v) * s + axis * (vector.dot(axis, v) * (1 - c))
end

-- Returns the eye position and the view's look and up vectors (world).
-- `lookYaw` / `lookPitch` (radians) are the player's free-look offsets.
function CockpitRig.step(s: Settings, st: State, pose: Pose, rideHeight: number, gravity: number, lookYaw: number, lookPitch: number, dt: number): (vector, vector, vector)
	dt = math.max(dt, 1e-4)
	local right, up, look = pose.right, pose.up, pose.look

	-- acceleration in the kart frame, low-pass filtered (raw per-frame
	-- velocity differences are noisy)
	local raw = vector.zero
	if st.lastVel then
		local a = (pose.vel - st.lastVel :: vector) / dt
		raw = vector.create(vector.dot(a, right), vector.dot(a, up), vector.dot(a, look))
	end
	st.lastVel = pose.vel
	local ka = 1 - math.exp(-s.AccelFilter * dt)
	st.accel += (raw - st.accel) * ka

	-- head sway: thrown outward in corners, forward under braking
	local want = vector.create(-st.accel.x / gravity * s.HeadG, 0, -st.accel.z / gravity * s.HeadGForward)
	local m = vector.magnitude(want)
	if m > s.HeadMax then
		want = want * (s.HeadMax / m)
	end
	st.head, st.headVel = springV(st.head, st.headVel, want, s.HeadResponse, dt)

	-- glance into the turn (yaw rate about the kart's up axis, degrees/s;
	-- positive = turning left, and a positive glance looks left)
	local yawRate = math.deg(vector.dot(pose.angVel, up))
	local wantGlance = math.clamp(yawRate * s.LookIntoTurn, -s.MaxLookIntoTurn, s.MaxLookIntoTurn)
	st.glance, st.glanceVel = spring(st.glance, st.glanceVel, wantGlance, s.LookResponse, dt)

	-- view "up": mostly level, a share of the kart's tilt, smoothed
	local wantUp = vector.normalize(WORLD_UP + (up - WORLD_UP) * s.TiltFollow)
	st.tiltUp, st.tiltVel = springV(st.tiltUp, st.tiltVel, wantUp, s.TiltResponse, dt)
	local viewUp = vector.normalize(st.tiltUp)

	-- heading straight from the kart, made perpendicular to the view up
	local fwd = look - viewUp * vector.dot(look, viewUp)
	if vector.magnitude(fwd) < 1e-4 then
		fwd = look
	end
	fwd = vector.normalize(fwd)
	local side = vector.normalize(vector.cross(fwd, viewUp))

	-- eye: fixed seat position plus the sway (in the kart frame)
	local e = s.Eye
	local localEye = vector.create(e[1], e[2] - rideHeight, e[3]) + st.head
	local eye = pose.pos + right * localEye.x + up * localEye.y + look * localEye.z

	-- turn the view: glance + free look about up, pitch about the side axis
	local yaw = math.rad(st.glance) + lookYaw
	local pitch = math.rad(s.Pitch) + lookPitch
	local viewLook = rotate(fwd, viewUp, yaw)
	local viewSide = rotate(side, viewUp, yaw)
	viewLook = rotate(viewLook, viewSide, pitch)
	local finalUp = rotate(viewUp, viewSide, pitch)
	return eye, viewLook, finalUp
end

return CockpitRig
