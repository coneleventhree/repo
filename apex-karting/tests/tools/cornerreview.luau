-- Corner review: how much each corner of a circuit asks of the driver.
-- A racing line is found across the whole road (minimum curvature: each
-- point moved towards where its neighbours' curve wants it, kept on the
-- road), the kart's grip turns its curvature into a speed limit, and a
-- point-mass lap (full throttle with the real engine curve, braking back
-- from every limit) gives the speed everywhere. Per named corner: the speed
-- coming in, the slowest point, how much is lost, and "FLAT" when it is
-- taken without lifting. A corner that a driver can straight-line or take
-- flat is no corner. Not pass/fail.
--   luau tests/tools/cornerreview.luau            (every circuit)
--   luau tests/tools/cornerreview.luau -a Hillside
--   luau tests/tools/cornerreview.luau -a "Hillside Sling=45,55"   (try other arcs)
local Config = require("../../src/shared/Config")
local TrackData = require("../../src/shared/TrackData")
local TrackMath = require("../../src/shared/TrackMath")
local TrackLayout = require("../../src/shared/TrackLayout")

local cfg = Config.Kart
local KMH = Config.KmhPerStudPerSecond
local LAT = 70 -- studs/s^2: the kart's cornering grip (tests/tools/agility.luau)
local BRAKE = 38 -- studs/s^2: firm braking, a little under the peak
local MARGIN = 3 -- studs from the kart's centre to the road edge (half a kart, kerbs allowed)

local function flat(v: vector): vector
	return vector.create(v.x, 0, v.z)
end

local function review(id: string)
	local spec = TrackData.get(id)
	local track = TrackMath.build(spec)
	local n = track.n
	local ds = track.spacing
	local C, R, W = {}, {}, {}
	for i, s in track.samples do
		C[i] = flat(s.pos)
		R[i] = vector.normalize(flat(s.right))
		W[i] = s.width / 2 - MARGIN
	end
	local off = table.create(n, 0)
	local P = table.create(n, vector.zero)
	for i = 1, n do
		P[i] = C[i]
	end
	local function w(i: number): number
		return TrackMath.wrap(i, n)
	end
	-- minimum curvature: P_i towards (-P_i-2 + 4 P_i-1 + 4 P_i+1 - P_i+2) / 6
	-- (30000 sweeps: fewer left the line short of the road edges and the
	-- corners looking harder than they are)
	for _ = 1, 30000 do
		for i = 1, n do
			local t = (-P[w(i - 2)] + P[w(i - 1)] * 4 + P[w(i + 1)] * 4 - P[w(i + 2)]) / 6
			local o = math.clamp(vector.dot(t - C[i], R[i]), -W[i], W[i])
			off[i] = o
			P[i] = C[i] + R[i] * o
		end
	end
	-- curvature of the line (circle through i-2, i, i+2) -> speed limit
	local vlim = table.create(n, 0)
	local top = cfg.TopSpeed
	for i = 1, n do
		local a, b, c = P[w(i - 2)], P[i], P[w(i + 2)]
		local ab, bc, ca = vector.magnitude(b - a), vector.magnitude(c - b), vector.magnitude(a - c)
		local cross = math.abs((b - a).x * (c - a).z - (b - a).z * (c - a).x)
		local k = if ab * bc * ca > 1e-9 then 2 * cross / (ab * bc * ca) else 0
		local bank = math.rad(math.abs(track.samples[i].bank))
		vlim[i] = math.min(top, math.sqrt((LAT + cfg.Gravity * math.sin(bank)) / math.max(k, 1e-6)))
	end
	-- point-mass lap: forward (engine) and backward (brakes), twice round
	local function accel(v: number): number
		return math.min(cfg.DriveAccel, cfg.PowerPerMass / math.max(v, 1)) - cfg.DragCoef * v * v
	end
	local v = table.create(n, 0)
	local acc = table.create(n, 0) -- full throttle only (where braking would start)
	local start = 1
	for i = 1, n do
		if vlim[i] < vlim[start] then
			start = i
		end
	end
	v[start] = vlim[start]
	for k = 1, 2 * n do
		local i = w(start + k)
		local p = w(i - 1)
		local up = math.sqrt(math.max(v[p] ^ 2 + 2 * accel(v[p]) * ds, 0))
		acc[i] = up
		v[i] = math.min(vlim[i], up)
	end
	for k = 1, 2 * n do
		local i = w(start - k)
		v[i] = math.min(v[i], math.sqrt(v[w(i + 1)] ^ 2 + 2 * BRAKE * ds))
	end
	local lap = 0
	for i = 1, n do
		lap += ds / math.max(v[i], 1)
	end
	print(string.format("== %s  (%.0f studs, ideal lap %.1f s)", spec.Name, track.length, lap))
	print(string.format("   %-18s %8s %8s %8s %8s  %s", "corner", "angle", "in km/h", "min km/h", "lost", "line uses"))
	local before = math.floor(90 / ds)
	for _, c in TrackLayout.corners(track, spec.Segments) do
		-- (an S counts by how much it turns either way: Sling's +28 -28 sums to 0)
		local turn = 0
		for k = c.first, c.last do
			turn += math.abs(spec.Segments[k].angle)
		end
		c.angle = if math.abs(c.angle) < 1 then turn else c.angle
		if c.name and turn >= 10 then
			local first, last = nil, nil
			for i, s in track.samples do
				if s.segment >= c.first and s.segment <= c.last then
					first = first or i
					last = i
				end
			end
			if first and last then
				local vin, vmin, used = 0, math.huge, 0
				for k = -before, 0 do
					vin = math.max(vin, v[w(first + k)])
				end
				for i = first, last do
					vmin = math.min(vmin, v[i])
					used = math.max(used, math.abs(off[i]) / math.max(W[i], 1))
				end
				local lost = (vin - vmin) * KMH
				local verdict = if lost < 2 then "FLAT" elseif lost < 8 then "lift" else "brake"
				print(string.format("   %-18s %7.0f° %8.0f %8.0f %8.0f  %3.0f%%  %s", c.name, c.angle, vin * KMH, vmin * KMH, lost, used * 100, verdict))
			end
		end
	end
end

local arg = ...
if arg then
	-- "Id Name=radius,angle ...": try other numbers for the arcs called Name
	-- (an S keeps its signs)
	local words = string.split(arg, " ")
	local id = words[1]
	for k = 2, #words do
		local name, r, a = string.match(words[k], "^(.-)=([%d%.]+),([%d%.]+)$")
		if name then
			for _, seg in TrackData.get(id).Segments do
				if seg.kind == "A" and seg.name == name then
					seg.radius = tonumber(r)
					seg.angle = if seg.angle > 0 then tonumber(a) else -(tonumber(a) :: number)
				end
			end
		end
	end
	review(id)
else
	for _, id in TrackData.Order do
		review(id)
	end
end
