--!strict
-- Kart vehicle model. Pure Luau (only the `vector` library) so the exact same
-- code drives the kart in Roblox and in the headless tests.
--
-- Once per frame it takes the chassis pose and velocity, casts one ray per
-- wheel (through a callback) and returns one world force and one world torque
-- about the centre of mass. The caller applies them (VectorForce + Torque in
-- Roblox, a rigid-body integrator in the tests). Gravity is not included.
--
--   suspension  raycast spring-damper per corner + anti-roll + bump stop
--   tyres       slip angle -> lateral force (Pacejka magic formula), combined
--               with drive/brake force inside a friction circle; load-sensitive
--   drivetrain  rear-wheel drive, traction-limited, constant power at speed,
--               engine braking, front/rear brake split, reverse after a pause
--   steering    rate-limited, Ackermann geometry, optional counter-steer assist
--   slipstream  close behind another kart the air drag drops and the top
--               speed creeps up a little (a tow down the straights)
--   bumpers     soft contact with other karts: each kart is a rounded
--               rectangle (its wraparound bumper); overlap pushes back with a
--               spring-damper plus some rubbing friction, horizontal only, so
--               karts shove and spin each other but never launch
--
-- Sub-stepping: tyres and springs are stiff, and Roblox only lets us set a
-- force once per frame (30-60 Hz on phones). Holding a stiff force for a whole
-- frame overshoots and can explode. So each frame the model predicts the
-- chassis motion internally at 240 Hz against the ground planes found by the
-- rays, sums the impulse, and hands back the average force and torque. The
-- engine then integrates that smooth average. Same physics, stable at any fps.

local KartPhysics = {}

export type Body = {
	pos: vector, -- chassis box centre (= centre of mass)
	right: vector,
	up: vector,
	look: vector,
	vel: vector,
	angVel: vector,
	mass: number,
}

export type Hit = {
	dist: number, -- distance along the ray (from the mount point)
	normal: vector,
	grip: number, -- surface multiplier on Mu
	roll: number, -- surface multiplier on rolling resistance
}

export type RaycastFn = (origin: vector, dir: vector) -> Hit?

export type Controls = {
	throttle: number, -- 0..1
	brake: number, -- 0..1
	steer: number, -- -1 (left) .. 1 (right)
}

export type State = {
	steerAngle: number, -- radians, + = right
	reverse: boolean,
	reverseTimer: number,
	-- static-friction anchors: where each tyre is "stuck" while parked (nil = free)
	anchors: { [number]: vector },
	draft: number, -- slipstream 0..1 (smoothed)
}

export type WheelOut = {
	contact: boolean,
	hitDist: number, -- ray length to the ground (or full length in the air)
	compression: number,
	steer: number, -- radians, + = right
	load: number, -- normal force
	usage: number, -- grip demand / grip available (> 1 means sliding)
	spinning: boolean, -- driven wheel overpowering its grip
	locked: boolean, -- braked wheel overpowering its grip
	longSpeed: number, -- contact patch speed along the wheel
}

export type Result = {
	force: vector,
	torque: vector,
	wheels: { WheelOut },
	forwardSpeed: number,
	speed: number,
	grounded: number,
	reverse: boolean,
	steerAngle: number,
	contact: number, -- deepest bumper overlap with another kart this frame (studs, 0 = none)
	contactSpeed: number, -- closing speed at the first touch this frame (studs/s)
	draft: number, -- slipstream 0..1
}

-- Slipstream: a kart between Gap and Length studs ahead (centre to centre)
-- and within Width studs sideways gives a tow that grows as you close in.
-- At full tow drag drops by DragCut and the governor allows TopGain more
-- studs/s. Rise/Fall: how fast the tow builds and fades (1/s).
export type SlipstreamConfig = {
	Gap: number,
	Length: number,
	Width: number,
	MinSpeed: number,
	DragCut: number,
	TopGain: number,
	Rise: number,
	Fall: number,
}

-- Another kart as seen by this one: its centre of mass, heading and motion
-- (the caller extrapolates network-delayed karts to "now").
export type Obstacle = {
	pos: vector,
	look: vector,
	vel: vector,
	angVel: vector,
}

-- Bumper outline (relative to the centre of mass) and contact response.
-- Stiffness: push per stud of overlap, capped at SpringMax (so karts that
-- end up deep inside each other, after a lag spike or a reset, ease apart
-- instead of exploding). Damping: push per stud/s of closing speed (and less
-- push while parting), faded in over the first quarter stud of overlap (no
-- jolt at the first touch); it is what stops a hard hit. MaxAccel caps the
-- total. All in studs/s^2.
export type BumperConfig = {
	HalfWidth: number,
	Front: number,
	Rear: number,
	Corner: number,
	Stiffness: number,
	SpringMax: number,
	Damping: number,
	Friction: number,
	MaxAccel: number,
}

export type WheelSpec = { name: string, x: number, f: number, radius: number, width: number, front: boolean, grip: number, stiffness: number? }

-- The fields of Config.Kart this module reads.
export type KartConfig = {
	Gravity: number,
	CoreSize: { number },
	RideHeight: number,
	Wheels: { WheelSpec },
	SpringHz: number,
	DampingRatio: number,
	Travel: number,
	BumpStopRate: number,
	AntiRollFront: number,
	AntiRollRear: number,
	Mu: number,
	LoadSensitivity: number,
	PacejkaB: number,
	PacejkaC: number,
	RollingResistance: number,
	LowSpeedBlend: number,
	DriveAccel: number,
	PowerPerMass: number,
	EngineBraking: number,
	TopSpeed: number,
	DragCoef: number,
	BrakeAccel: number,
	BrakeRearBias: number,
	ReverseAccel: number,
	ReverseSpeed: number,
	ReverseDelay: number,
	SteerLock: number,
	SteerRate: number,
	SteerReturnRate: number,
	Ackermann: number,
	SteerAssist: boolean,
	SteerAssistSlip: number,
	AssistCatch: number?,
	Bumper: BumperConfig?,
	Slipstream: SlipstreamConfig?,
}

local TWO_PI = 2 * math.pi
local SUBSTEP_HZ = 240
local ANCHOR_OMEGA = 2 * math.pi * 6 -- static-friction spring
local UP = vector.create(0, 1, 0)

local function tanh(x: number): number
	if x > 10 then
		return 1
	elseif x < -10 then
		return -1
	end
	local e = math.exp(2 * x)
	return (e - 1) / (e + 1)
end

local function rotate(v: vector, axis: vector, angle: number): vector
	local c, s = math.cos(angle), math.sin(angle)
	return v * c + vector.cross(axis, v) * s + axis * (vector.dot(axis, v) * (1 - c))
end

function KartPhysics.newState(cfg: KartConfig): State
	return { steerAngle = 0, reverse = false, reverseTimer = 0, anchors = {}, draft = 0 }
end

export type Geometry = {
	wheelbase: number,
	frontF: number,
	rearF: number,
	frontTrack: number,
	rearTrack: number,
	frontShare: number,
	rearShare: number,
	omega: number,
	staticCompression: number,
	rayLength: number,
	-- inertia of the chassis box per unit mass, local axes
	ix: number, -- pitch (about right)
	iy: number, -- yaw (about up)
	iz: number, -- roll (about look)
}

local geometryCache: { [any]: Geometry } = setmetatable({}, { __mode = "k" }) :: any

-- Derived constants that only depend on the config.
function KartPhysics.geometry(cfg: KartConfig): Geometry
	local cached = geometryCache[cfg]
	if cached then
		return cached
	end
	local frontF, rearF = -math.huge, math.huge
	local frontTrack, rearTrack = 0, 0
	for _, w in cfg.Wheels do
		if w.front then
			frontF = math.max(frontF, w.f)
			frontTrack = math.max(frontTrack, math.abs(w.x) * 2)
		else
			rearF = math.min(rearF, w.f)
			rearTrack = math.max(rearTrack, math.abs(w.x) * 2)
		end
	end
	local wheelbase = frontF - rearF
	local omega = TWO_PI * cfg.SpringHz
	local staticComp = cfg.Gravity / (omega * omega)
	local bw, bh, bl = cfg.CoreSize[1], cfg.CoreSize[2], cfg.CoreSize[3]
	local g: Geometry = {
		wheelbase = wheelbase,
		frontF = frontF,
		rearF = rearF,
		frontTrack = frontTrack,
		rearTrack = rearTrack,
		-- static share of the weight carried by one front / one rear wheel
		frontShare = (-rearF / wheelbase) / 2,
		rearShare = (frontF / wheelbase) / 2,
		omega = omega,
		staticCompression = staticComp,
		rayLength = cfg.RideHeight + staticComp, -- mount to ground at full droop
		ix = (bh * bh + bl * bl) / 12,
		iy = (bw * bw + bl * bl) / 12,
		iz = (bw * bw + bh * bh) / 12,
	}
	geometryCache[cfg] = g
	return g
end

-- How much the steering assist blends in at a given speed (0 = raw lock).
function KartPhysics.assistWeight(cfg: KartConfig, speed: number): number
	if not cfg.SteerAssist then
		return 0
	end
	return math.clamp((speed - 8) / 14, 0, 1)
end

-- Slip angle of the front axle's velocity relative to the chassis (radians,
-- + = moving to the right of where the nose points).
function KartPhysics.frontAxleSlip(cfg: KartConfig, body: Body): number
	local g = KartPhysics.geometry(cfg)
	local vf = body.vel + vector.cross(body.angVel, body.look * g.frontF)
	local vlong = vector.dot(vf, body.look)
	if vlong < 2 then
		return 0
	end
	return math.atan2(vector.dot(vf, body.right), vlong)
end

-- Front slip angle (radians) the assist asks for at input u in [0, 1].
-- The tyre's grip rises steeply at small slip angles and flattens towards the
-- peak, so mapping the input straight to a slip angle made the first half of
-- the key press do almost all the turning (and the last part of letting go
-- snap the kart straight). This inverts the grip curve instead: the input
-- asks for a share of the front grip, so the kart's turn builds and fades in
-- step with the input. Full input reaches SteerAssistSlip (just past peak).
function KartPhysics.assistSlip(cfg: KartConfig, u: number): number
	u = math.clamp(u, 0, 1)
	local B, C = cfg.PacejkaB, cfg.PacejkaC
	local peak = math.tan(math.pi / (2 * C)) / B
	local slip = math.tan(math.asin(u) / C) / B
	return slip * (math.rad(cfg.SteerAssistSlip) / peak)
end

-- Steering angle at the wheels for a given input (-1..1).
-- Without assist: input * lock. With assist (blended in with speed) the input
-- sets the front tyres' slip angle relative to where the front axle is going,
-- so full input means "use all the front grip" and letting go of the keys
-- points the wheels where the kart is travelling (natural counter-steer when
-- the rear steps out). The physics stays the same; only the steering column
-- is helped, which is what keyboard players need.
-- Rear axle slip angle (radians, + = rear axle moving to the right of the nose).
function KartPhysics.rearAxleSlip(cfg: KartConfig, body: Body): number
	local g = KartPhysics.geometry(cfg)
	local vr = body.vel + vector.cross(body.angVel, body.look * g.rearF)
	local vlong = vector.dot(vr, body.look)
	if math.abs(vlong) < 2 then
		return 0
	end
	return math.atan2(vector.dot(vr, body.right), math.abs(vlong))
end

-- Slip angle where the rear tyres peak (radians).
local function rearPeak(cfg: KartConfig): number
	local stiff = 1
	for _, w in cfg.Wheels do
		if not w.front then
			stiff = w.stiffness or 1
		end
	end
	return math.tan(math.pi / (2 * cfg.PacejkaC)) / (cfg.PacejkaB * stiff)
end

-- `beta` overrides the front axle direction (the lagged value from State).
-- Besides aiming the front tyres, the assist catches slides: once the rear
-- tyres slip past their peak (oversteer), the front slip it asks for is
-- pulled back towards counter-steer, even if the steering key is still held,
-- as a keyboard player cannot react as fast as a hand on a wheel.
function KartPhysics.steerTarget(cfg: KartConfig, input: number, body: Body, beta: number?): number
	local lock = math.rad(cfg.SteerLock)
	local w = KartPhysics.assistWeight(cfg, math.abs(vector.dot(body.vel, body.look)))
	local raw = input * lock
	if w <= 0 then
		return raw
	end
	local slip = math.sign(input) * KartPhysics.assistSlip(cfg, math.abs(input))
	local gain = cfg.AssistCatch or 0
	if gain > 0 then
		-- rear force direction: r > 0 means the rear is pushing the kart's tail
		-- out to the left (rotating right)
		local r = -KartPhysics.rearAxleSlip(cfg, body)
		local limit = rearPeak(cfg) * 1.15
		local excess = math.sign(r) * math.max(math.abs(r) - limit, 0)
		slip -= gain * excess
		local cap = math.rad(cfg.SteerAssistSlip)
		slip = math.clamp(slip, -cap, cap)
	end
	local assisted = (beta or KartPhysics.frontAxleSlip(cfg, body)) + slip
	return math.clamp(raw * (1 - w) + assisted * w, -lock, lock)
end

-- Inverse of steerTarget for a desired wheel angle (used by the test autopilot).
function KartPhysics.inputFor(cfg: KartConfig, delta: number, body: Body, beta: number?): number
	local lo, hi = -1, 1
	local function at(u: number): number
		return KartPhysics.steerTarget(cfg, u, body, beta)
	end
	if at(hi) <= delta then
		return 1
	elseif at(lo) >= delta then
		return -1
	end
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if at(mid) < delta then
			lo = mid
		else
			hi = mid
		end
	end
	return (lo + hi) / 2
end

local function approach(current: number, target: number, rate: number): number
	if current < target then
		return math.min(current + rate, target)
	end
	return math.max(current - rate, target)
end

type Plane = { point: vector, normal: vector, grip: number, roll: number }

type Demands = {
	drive: number,
	brake: number,
	reverse: number,
	steerL: number,
	steerR: number,
}

-- Forces for one substep. `b` is the predicted body. Returns force (no
-- gravity), torque about the centre of mass, and fills `outs`.
local function wheelForces(
	cfg: KartConfig,
	g: Geometry,
	state: State,
	b: Body,
	planes: { [number]: Plane },
	d: Demands,
	h: number,
	outs: { WheelOut }
): (vector, vector, number)
	local m = b.mass
	local up, right, look = b.up, b.right, b.look
	local vel, angVel = b.vel, b.angVel
	local forwardSpeed = vector.dot(vel, look)
	local wheels = cfg.Wheels
	local nW = #wheels
	local omega2 = g.omega * g.omega

	-- suspension geometry against each wheel's ground plane
	local comp = table.create(nW, 0)
	local dist = table.create(nW, g.rayLength)
	local mounts: { vector } = table.create(nW)
	local grounded = 0
	for i, w in wheels do
		local mount = b.pos + right * w.x + look * w.f
		mounts[i] = mount
		local pl = planes[i]
		if pl then
			-- distance along the ray (-up) to the plane
			local denom = vector.dot(up, pl.normal)
			if denom > 0.2 then
				local dd = vector.dot(mount - pl.point, pl.normal) / denom
				if dd >= -0.5 and dd <= g.rayLength then
					dist[i] = math.max(dd, 0)
					comp[i] = g.rayLength - dist[i]
					grounded += 1
				end
			end
		end
		if comp[i] <= 0 then
			state.anchors[i] = nil
		end
	end

	-- anti-roll: wheels 1,2 are the front pair and 3,4 the rear pair
	local arb = table.create(nW, 0)
	for _, pair in { { 1, 2 }, { 3, 4 } } do
		local a, c = pair[1], pair[2]
		if wheels[a] and wheels[c] then
			local front = wheels[a].front
			local share = if front then g.frontShare else g.rearShare
			local k = m * share * omega2 * (if front then cfg.AntiRollFront else cfg.AntiRollRear)
			local diff = comp[a] - comp[c]
			arb[a] = k * diff
			arb[c] = -k * diff
		end
	end

	local force = vector.zero
	local torque = vector.zero
	for i, w in wheels do
		local share = if w.front then g.frontShare else g.rearShare
		local mi = m * share
		local k = mi * omega2
		local c = 2 * cfg.DampingRatio * mi * g.omega
		local wheelSteer = if w.front then (if w.x < 0 then d.steerL else d.steerR) else 0
		local out = outs[i]
		out.contact = comp[i] > 0
		out.hitDist = dist[i]
		out.compression = comp[i]
		out.steer = wheelSteer
		out.load, out.usage, out.spinning, out.locked, out.longSpeed = 0, 0, false, false, 0
		local pl = planes[i]
		if comp[i] > 0 and pl then
			local p = mounts[i] - up * dist[i] -- contact point
			local r = p - b.pos
			local vp = vel + vector.cross(angVel, r)
			local compRate = -vector.dot(vp, up)
			local x = comp[i]
			local fs = k * x + c * compRate + arb[i]
			local bump = g.staticCompression + cfg.Travel
			if x > bump then
				fs += k * cfg.BumpStopRate * (x - bump)
			end
			fs = math.max(fs, 0)
			local n = pl.normal
			local load = fs * math.max(vector.dot(up, n), 0.2)
			out.load = load

			-- contact frame
			local wfwd = look * math.cos(wheelSteer) + right * math.sin(wheelSteer)
			local lv = wfwd - n * vector.dot(wfwd, n)
			local lmag = vector.magnitude(lv)
			local tireF = vector.zero
			if lmag > 1e-4 and load > 0 then
				local l = lv / lmag
				local t = vector.cross(l, n)
				local vx = vector.dot(vp, l)
				local vy = vector.dot(vp, t)
				out.longSpeed = vx

				local staticLoad = m * share * cfg.Gravity
				local mu = cfg.Mu * w.grip * pl.grip * math.clamp(1 - cfg.LoadSensitivity * (load / staticLoad - 1), 0.6, 1.25)
				local fmax = mu * load

				-- lateral: magic formula on slip angle, stick model at low speed
				local alpha = math.atan2(vy, math.max(math.abs(vx), 0.5))
				local dyn = -math.sin(cfg.PacejkaC * math.atan(cfg.PacejkaB * (w.stiffness or 1) * alpha)) * fmax
				local stick = -vy * mi / h * 0.25
				local blend = math.clamp(math.abs(vx) / cfg.LowSpeedBlend, 0, 1)
				local fy = dyn * blend + stick * (1 - blend)
				local noOvershoot = 0.5 * mi * math.abs(vy) / h
				fy = math.clamp(fy, -noOvershoot, noOvershoot)

				-- longitudinal demand
				local fx = 0
				local driven = not w.front
				local sgn = tanh(vx / 0.6)
				if driven then
					local nDriven = 2
					if d.drive > 0 then
						local a = math.min(cfg.DriveAccel, cfg.PowerPerMass / math.max(math.abs(forwardSpeed), 1))
						local top = cfg.TopSpeed + (if cfg.Slipstream then cfg.Slipstream.TopGain * state.draft else 0)
						local governor = math.clamp((top + 4 - forwardSpeed) / 4, 0, 1)
						fx += m * a * d.drive * governor / nDriven
					elseif d.reverse > 0 then
						local governor = math.clamp((cfg.ReverseSpeed + forwardSpeed) / 2 + 0.2, 0, 1)
						fx -= m * cfg.ReverseAccel * d.reverse * governor / nDriven
					elseif d.brake <= 0 then
						fx -= m * cfg.EngineBraking * sgn / nDriven
					end
				end
				local bias = if w.front then (1 - cfg.BrakeRearBias) / 2 else cfg.BrakeRearBias / 2
				local brakeF = m * cfg.BrakeAccel * d.brake * bias
				if brakeF > 0 then
					if math.abs(vx) < 1.5 then
						-- hold still instead of jittering around zero
						fx += math.clamp(-vx * mi * 0.5 / h, -brakeF, brakeF)
					else
						fx -= brakeF * sgn
					end
				end
				fx -= cfg.RollingResistance * pl.roll * load * sgn

				-- friction circle
				local ux, uy = 0, 0
				if fmax > 1e-6 then
					ux, uy = fx / fmax, fy / fmax
				end
				local usage = math.sqrt(ux * ux + uy * uy)
				out.usage = usage
				if usage > 1 then
					ux /= usage
					uy /= usage
					if driven and d.drive > 0 and math.abs(ux) > 0.6 then
						out.spinning = true
					end
					if brakeF > 0 and math.abs(ux) > 0.6 then
						out.locked = true
					end
				end
				tireF = l * (ux * fmax) + t * (uy * fmax)

				-- Static friction while parked: pin the contact patch to an anchor
				-- with a stiff spring-damper. Velocity-based friction alone always
				-- creeps on slopes and banking.
				local holding = d.drive <= 0 and d.reverse <= 0
				local anchor: vector? = state.anchors[i]
				if not holding then
					state.anchors[i] = nil
					anchor = nil
				elseif not anchor and math.sqrt(vx * vx + vy * vy) < 0.25 and math.abs(forwardSpeed) < 0.5 then
					anchor = p
					state.anchors[i] = p
				end
				if anchor then
					local ka = mi * ANCHOR_OMEGA * ANCHOR_OMEGA
					local ca = 2 * 1.0 * mi * ANCHOR_OMEGA
					local dp = p - anchor
					dp -= n * vector.dot(dp, n)
					local vpl = vp - n * vector.dot(vp, n)
					local fa = dp * -ka - vpl * ca
					if vector.magnitude(fa) > fmax * 0.95 then
						state.anchors[i] = nil -- breaks loose: slide on the normal model
					else
						tireF = fa
						out.usage = vector.magnitude(fa) / math.max(fmax, 1e-6)
					end
				end
			else
				state.anchors[i] = nil
			end

			local f = up * fs + tireF
			force += f
			torque += vector.cross(r, f)
		end
	end

	-- aerodynamic drag at the centre of mass (less in another kart's wake)
	local dragCut = if cfg.Slipstream then cfg.Slipstream.DragCut * state.draft else 0
	force -= vel * (cfg.DragCoef * (1 - dragCut) * m * vector.magnitude(vel))
	return force, torque, grounded
end

----------------------------------------------------------------------------
-- Bumpers: kart-to-kart contact
----------------------------------------------------------------------------
-- Signed distance from a point (x right, f forward, relative to the centre of
-- mass) to the bumper outline, and the outward direction there.
local function bumperSdf(bm: BumperConfig, x: number, f: number): (number, number, number)
	local c = bm.Corner
	local fc = (bm.Front - bm.Rear) / 2
	local hl = (bm.Front + bm.Rear) / 2
	local lf = f - fc
	local sx = if x >= 0 then 1 else -1
	local sf = if lf >= 0 then 1 else -1
	local qx = math.abs(x) - (bm.HalfWidth - c)
	local qf = math.abs(lf) - (hl - c)
	if qx > 0 or qf > 0 then
		local ox, of = math.max(qx, 0), math.max(qf, 0)
		local len = math.sqrt(ox * ox + of * of)
		local inside = math.min(math.max(qx, qf), 0)
		if len < 1e-9 then
			return inside - c, sx, 0
		end
		return len + inside - c, sx * ox / len, sf * of / len
	end
	-- inside the straight-edged core: nearest edge
	if qx > qf then
		return qx - c, sx, 0
	end
	return qf - c, 0, sf
end
KartPhysics.bumperSdf = bumperSdf

-- Points around the outline (local x, f), every metre or so plus the corners.
type OutlinePoint = { x: number, f: number }
local outlineCache: { [any]: { OutlinePoint } } = setmetatable({}, { __mode = "k" }) :: any
local function outline(bm: BumperConfig): { OutlinePoint }
	local cached = outlineCache[bm]
	if cached then
		return cached
	end
	local pts: { OutlinePoint } = {}
	local c, W, F, R = bm.Corner, bm.HalfWidth, bm.Front, bm.Rear
	local function edge(x0: number, f0: number, x1: number, f1: number)
		local len = math.sqrt((x1 - x0) ^ 2 + (f1 - f0) ^ 2)
		local n = math.max(1, math.ceil(len / 1.0))
		for i = 0, n - 1 do
			local t = i / n
			table.insert(pts, { x = x0 + (x1 - x0) * t, f = f0 + (f1 - f0) * t })
		end
	end
	local function arc(cx: number, cf: number, a0: number)
		for k = 0, 3 do
			local a = a0 + (k / 4) * math.pi / 2
			table.insert(pts, { x = cx + math.cos(a) * c, f = cf + math.sin(a) * c })
		end
	end
	-- anticlockwise from the front right, as seen from above with x right, f up
	edge(W - c, F, -(W - c), F)
	arc(-(W - c), F - c, math.pi / 2)
	edge(-W, F - c, -W, -R + c)
	arc(-(W - c), -R + c, math.pi)
	edge(-(W - c), -R, W - c, -R)
	arc(W - c, -R + c, 3 * math.pi / 2)
	edge(W, -R + c, W, F - c)
	arc(W - c, F - c, 0)
	outlineCache[bm] = pts
	return pts
end
KartPhysics.bumperOutline = outline

local function flat(v: vector): vector
	return vector.create(v.x, 0, v.z)
end

-- Push on body `b` from obstacle `o` (advanced `t` seconds), applied at the
-- height of the centre of mass so it never rolls or pitches the kart.
-- Returns the force, the torque about the centre of mass, the overlap and
-- the closing speed.
-- Karts further apart in height than this are on the two levels of a
-- crossing (one on the bridge, one under it): they neither touch nor tow.
local OTHER_LEVEL = 5

local function bumperContact(bm: BumperConfig, b: Body, o: Obstacle, t: number): (vector, vector, number, number)
	local reach = math.sqrt(bm.HalfWidth ^ 2 + math.max(bm.Front, bm.Rear) ^ 2)
	local cA = b.pos
	local cB = o.pos + o.vel * t
	-- on the other level of a crossing (the bridge over the road): no contact
	if math.abs(cB.y - cA.y) > OTHER_LEVEL then
		return vector.zero, vector.zero, 0, 0
	end
	cB = vector.create(cB.x, cA.y, cB.z)
	local d = cB - cA
	if d.x * d.x + d.z * d.z > (2 * reach) ^ 2 then
		return vector.zero, vector.zero, 0, 0
	end
	local fA = vector.normalize(flat(b.look))
	local rA = vector.cross(fA, UP)
	local spin = o.angVel.y * t
	local fB = vector.normalize(flat(o.look))
	if math.abs(spin) > 1e-6 then
		fB = vector.normalize(flat(rotate(fB, UP, spin)))
	end
	local rB = vector.cross(fB, UP)
	local pts = outline(bm)
	local sumW, maxPen = 0, 0
	local sumN, sumP = vector.zero, vector.zero
	-- my outline inside theirs: push out along their surface normal
	for _, q in pts do
		local p = cA + rA * q.x + fA * q.f
		local rel = p - cB
		local dist, gx, gf = bumperSdf(bm, vector.dot(rel, rB), vector.dot(rel, fB))
		if dist < 0 then
			local w = -dist
			sumW += w
			sumN += (rB * gx + fB * gf) * w
			sumP += p * w
			maxPen = math.max(maxPen, w)
		end
	end
	-- their outline inside mine: push away from that point
	for _, q in pts do
		local p = cB + rB * q.x + fB * q.f
		local rel = p - cA
		local dist, gx, gf = bumperSdf(bm, vector.dot(rel, rA), vector.dot(rel, fA))
		if dist < 0 then
			local w = -dist
			sumW += w
			sumN -= (rA * gx + fA * gf) * w
			sumP += p * w
			maxPen = math.max(maxPen, w)
		end
	end
	if sumW <= 0 or vector.magnitude(sumN) < 1e-9 then
		return vector.zero, vector.zero, 0, 0
	end
	local n = vector.normalize(flat(sumN))
	local point = sumP / sumW
	-- relative velocity of the two surfaces at the contact
	local vA = b.vel + vector.cross(b.angVel, point - b.pos)
	local vB = o.vel + vector.cross(o.angVel, point - cB)
	local vrel = flat(vA - vB)
	local vn = vector.dot(vrel, n) -- < 0 while closing
	local closing = math.max(0, -vn)
	local spring = math.min(bm.Stiffness * maxPen, bm.SpringMax)
	-- damping resists both closing and parting (less bounce), but never pulls
	local damp = -bm.Damping * vn * math.min(maxPen / 0.25, 1)
	local accel = math.clamp(spring + damp, 0, bm.MaxAccel)
	local fn = b.mass * accel
	local vt = vrel - n * vn
	local vtMag = vector.magnitude(vt)
	local force = n * fn
	if vtMag > 1e-6 then
		-- rubbing bumpers: friction that fades in smoothly from standstill
		force -= vt * (bm.Friction * fn / (vtMag + 0.5))
	end
	local torque = vector.cross(point - b.pos, force)
	return force, torque, maxPen, closing
end
KartPhysics.bumperContact = bumperContact

-- Rigid-body substep for the internal prediction (chassis box inertia).
local function integrate(b: Body, g: Geometry, force: vector, torque: vector, gravity: number, h: number)
	b.vel += (force / b.mass - UP * gravity) * h
	local back = -b.look
	local w = b.angVel
	local wl = vector.create(vector.dot(w, b.right), vector.dot(w, b.up), vector.dot(w, back))
	local tl = vector.create(vector.dot(torque, b.right), vector.dot(torque, b.up), vector.dot(torque, back))
	local m = b.mass
	local ix, iy, iz = g.ix * m, g.iy * m, g.iz * m
	local Iw = vector.create(ix * wl.x, iy * wl.y, iz * wl.z)
	local gyro = vector.cross(wl, Iw)
	wl += vector.create((tl.x - gyro.x) / ix, (tl.y - gyro.y) / iy, (tl.z - gyro.z) / iz) * h
	b.angVel = b.right * wl.x + b.up * wl.y + back * wl.z
	b.pos += b.vel * h
	local wmag = vector.magnitude(b.angVel)
	if wmag > 1e-9 then
		local axis = b.angVel / wmag
		local ang = wmag * h
		b.right = rotate(b.right, axis, ang)
		b.up = rotate(b.up, axis, ang)
		b.look = rotate(b.look, axis, ang)
	end
	b.look = vector.normalize(b.look)
	b.right = vector.normalize(vector.cross(b.look, b.up))
	b.up = vector.cross(b.right, b.look)
end

-- How much tow the karts ahead give right now (0..1, unsmoothed).
function KartPhysics.draftTarget(cfg: KartConfig, body: Body, others: { Obstacle }?): number
	local sl = cfg.Slipstream
	if not sl or not others then
		return 0
	end
	local f = flat(body.look)
	if vector.magnitude(f) < 1e-6 then
		return 0
	end
	f = vector.normalize(f)
	local r = vector.cross(f, UP)
	if vector.dot(body.vel, f) < sl.MinSpeed then
		return 0
	end
	local best = 0
	for _, o in others do
		if math.abs(o.pos.y - body.pos.y) > OTHER_LEVEL then
			continue
		end
		local rel = flat(o.pos - body.pos)
		local ahead = vector.dot(rel, f)
		local lat = math.abs(vector.dot(rel, r))
		if ahead > sl.Gap and ahead < sl.Length and lat < sl.Width and vector.dot(o.vel, f) > sl.MinSpeed * 0.7 then
			local near = 1 - (ahead - sl.Gap) / (sl.Length - sl.Gap)
			local centred = 1 - (lat / sl.Width) ^ 2
			best = math.max(best, near * centred)
		end
	end
	return math.clamp(best, 0, 1)
end

-- `others`: nearby karts to bump into and draft behind (optional).
function KartPhysics.step(cfg: KartConfig, state: State, body: Body, ctrl: Controls, dt: number, raycast: RaycastFn, others: { Obstacle }?): Result
	dt = math.clamp(dt, 1 / 480, 1 / 10)
	local g = KartPhysics.geometry(cfg)
	local up, right, look = body.up, body.right, body.look
	local vel = body.vel
	local forwardSpeed = vector.dot(vel, look)

	----------------------------------------------------------------------
	-- Controls: reverse logic and steering (once per frame)
	----------------------------------------------------------------------
	local throttle = math.clamp(ctrl.throttle, 0, 1)
	local brake = math.clamp(ctrl.brake, 0, 1)
	if state.reverse then
		if (throttle > 0.1 and forwardSpeed > -1) or forwardSpeed > 3 then
			state.reverse = false
			state.reverseTimer = 0
		end
	elseif brake > 0.1 and throttle < 0.1 and math.abs(forwardSpeed) < 1 then
		state.reverseTimer += dt
		if state.reverseTimer >= cfg.ReverseDelay then
			state.reverse = true
		end
	else
		state.reverseTimer = 0
	end
	local d: Demands = { drive = throttle, brake = brake, reverse = 0, steerL = 0, steerR = 0 }
	if state.reverse then
		d.drive, d.brake, d.reverse = 0, throttle, brake
	end

	local input = math.clamp(ctrl.steer, -1, 1)
	local target = KartPhysics.steerTarget(cfg, input, body)
	local returning = math.abs(input) < 0.05
	local rate = math.rad(if returning then cfg.SteerReturnRate else cfg.SteerRate) * dt
	state.steerAngle = approach(state.steerAngle, target, rate)
	local delta = state.steerAngle

	-- Ackermann: inner wheel turns tighter
	d.steerL, d.steerR = delta, delta
	if math.abs(delta) > 1e-4 then
		local R = g.wheelbase / math.tan(math.abs(delta))
		local half = g.frontTrack / 2
		local inner = math.atan(g.wheelbase / math.max(R - half, 0.1))
		local outer = math.atan(g.wheelbase / (R + half))
		local a = cfg.Ackermann
		inner = math.abs(delta) + (inner - math.abs(delta)) * a
		outer = math.abs(delta) + (outer - math.abs(delta)) * a
		if delta > 0 then -- turning right: right wheel is inner
			d.steerL, d.steerR = outer, inner
		else
			d.steerL, d.steerR = -inner, -outer
		end
	end

	----------------------------------------------------------------------
	-- Ground planes under each wheel (one ray each, a little longer than the
	-- suspension so a landing during this frame is seen)
	----------------------------------------------------------------------
	local wheels = cfg.Wheels
	local nW = #wheels
	local planes: { [number]: Plane } = {}
	-- and where each wheel will be at the end of the frame: the prediction
	-- blends from one plane to the other, so a wheel that crosses an edge
	-- between two road pieces during a long frame (20-30 fps) rolls over it
	-- instead of meeting it all at once at the next frame
	local planesEnd: { [number]: Plane } = {}
	local reach = g.rayLength + 0.6 + math.max(0, -vector.dot(vel, up)) * dt * 2
	for i, w in wheels do
		local mount = body.pos + right * w.x + look * w.f
		local hit = raycast(mount, -up * reach)
		if hit then
			planes[i] = { point = mount - up * hit.dist, normal = hit.normal, grip = hit.grip, roll = hit.roll }
			local ahead = mount + vel * dt
			local hit2 = raycast(ahead, -up * reach)
			if hit2 then
				planesEnd[i] = { point = ahead - up * hit2.dist, normal = hit2.normal, grip = hit2.grip, roll = hit2.roll }
			end
		else
			state.anchors[i] = nil
		end
	end
	-- the ground under each wheel part way (t) through the frame: heights
	-- along the suspension ray and normals blended between the two planes
	local function planesAt(bb: Body, t: number): { [number]: Plane }
		local out: { [number]: Plane } = {}
		for i, w in wheels do
			local a, e = planes[i], planesEnd[i]
			if a and e then
				local mount = bb.pos + bb.right * w.x + bb.look * w.f
				local da, de = vector.dot(bb.up, a.normal), vector.dot(bb.up, e.normal)
				if da > 0.2 and de > 0.2 then
					local hA = vector.dot(mount - a.point, a.normal) / da
					local hE = vector.dot(mount - e.point, e.normal) / de
					local n = vector.normalize(a.normal * (1 - t) + e.normal * t)
					local src = if t < 0.5 then a else e
					out[i] = { point = mount - bb.up * (hA + (hE - hA) * t), normal = n, grip = src.grip, roll = src.roll }
					continue
				end
			end
			out[i] = a
		end
		return out
	end

	-- slipstream from the karts ahead, eased in and out
	do
		local tow = KartPhysics.draftTarget(cfg, body, others)
		local sl = cfg.Slipstream
		if sl then
			local towRate = if tow > state.draft then sl.Rise else sl.Fall
			state.draft += (tow - state.draft) * math.min(towRate * dt, 1)
		else
			state.draft = 0
		end
	end

	----------------------------------------------------------------------
	-- Predict the frame at 240 Hz and average the impulse
	----------------------------------------------------------------------
	local outs: { WheelOut } = table.create(nW)
	for i = 1, nW do
		outs[i] = {
			contact = false,
			hitDist = g.rayLength,
			compression = 0,
			steer = 0,
			load = 0,
			usage = 0,
			spinning = false,
			locked = false,
			longSpeed = 0,
		}
	end
	local sub = math.max(1, math.ceil(dt * SUBSTEP_HZ - 1e-6))
	local h = dt / sub
	local b: Body = {
		pos = body.pos,
		right = right,
		up = up,
		look = look,
		vel = vel,
		angVel = body.angVel,
		mass = body.mass,
	}
	local impulse, angImpulse = vector.zero, vector.zero
	local grounded = 0
	local bm = cfg.Bumper
	local contact, contactSpeed = 0, 0
	for k = 1, sub do
		local f, t, gnd = wheelForces(cfg, g, state, b, planesAt(b, (k - 0.5) / sub), d, h, outs)
		grounded = gnd
		if bm and others then
			local at = (k - 0.5) * h
			for _, o in others do
				local cf, ct, pen, closing = bumperContact(bm, b, o, at)
				if pen > 0 then
					f += cf
					t += ct
					if contact == 0 then
						contactSpeed = closing
					end
					contact = math.max(contact, pen)
				end
			end
		end
		impulse += f * h
		angImpulse += t * h
		integrate(b, g, f, t, cfg.Gravity, h)
	end

	return {
		force = impulse / dt,
		torque = angImpulse / dt,
		wheels = outs,
		forwardSpeed = forwardSpeed,
		speed = vector.magnitude(vel),
		grounded = grounded,
		reverse = state.reverse,
		steerAngle = delta,
		contact = contact,
		contactSpeed = contactSpeed,
		draft = state.draft,
	}
end

return KartPhysics
