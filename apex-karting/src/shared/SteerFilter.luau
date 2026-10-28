--!strict
-- Turns raw steering input into a smooth steering command, the way racing
-- games treat a keyboard (Forza calls it input smoothing):
--
--   digital keys / touch buttons  the command rises towards full lock at a
--       limited rate that gets slower with speed (a quick flick at parking
--       speed, a gradual turn-in at racing speed), comes back to centre a
--       little quicker, and goes through centre fast when you switch
--       direction (a counter-steer should not be sluggish)
--   analog stick  passes through with a gentle response curve and only a
--       light rate limit, so fine corrections stay precise
--
-- A real driver cannot snap the wheel to full lock either, and if they did
-- the front tyres would go past their peak slip angle and the kart would push
-- wide (understeer). The ramp gives the weight time to transfer onto the
-- outside front tyre. Pure Luau, no Roblox APIs.

local SteerFilter = {}

export type Settings = {
	RiseLow: number, -- input units per second towards lock at low speed
	RiseHigh: number, -- ... at RiseSpeed and above
	ReturnLow: number, -- towards centre when released, low speed
	ReturnHigh: number,
	Counter: number, -- through centre when switching direction
	RiseSpeed: number, -- studs/s where the high-speed rates are reached
	Smoothing: number, -- 1/s, removes the corners of the ramp
	StickRate: number, -- rate limit for the analog stick
	StickCurve: number, -- exponent: >1 = finer control around centre
}

export type State = {
	ramp: number, -- rate-limited command
	out: number, -- smoothed command (what the kart gets)
}

function SteerFilter.new(): State
	return { ramp = 0, out = 0 }
end

local function approach(x: number, target: number, step: number): number
	if x < target then
		return math.min(x + step, target)
	end
	return math.max(x - step, target)
end

-- `target` in [-1, 1]; `digital` = it came from keys or touch buttons.
-- `speed` is the kart's forward speed (studs/s). Returns the command.
function SteerFilter.step(s: Settings, state: State, target: number, digital: boolean, speed: number, dt: number): number
	target = math.clamp(target, -1, 1)
	local x = state.ramp
	if digital then
		local f = math.clamp(math.abs(speed) / s.RiseSpeed, 0, 1)
		local rise = s.RiseLow + (s.RiseHigh - s.RiseLow) * f
		local back = s.ReturnLow + (s.ReturnHigh - s.ReturnLow) * f
		if target ~= 0 and x * target < 0 then
			-- switching direction: hurry back through centre first
			x = approach(x, 0, s.Counter * dt)
		elseif math.abs(target) > math.abs(x) then
			x = approach(x, target, rise * dt)
		else
			x = approach(x, target, back * dt)
		end
	else
		local shaped = math.sign(target) * math.abs(target) ^ s.StickCurve
		x = approach(x, shaped, s.StickRate * dt)
	end
	state.ramp = x
	-- light low-pass on top, so the wheel never jerks at the ends of the ramp
	local k = 1 - math.exp(-s.Smoothing * dt)
	state.out += (x - state.out) * k
	if math.abs(state.out) < 1e-4 and x == 0 then
		state.out = 0
	end
	return state.out
end

return SteerFilter
