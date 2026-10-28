--!strict
-- Pure track maths shared by server, client and tests. No Roblox APIs, only the
-- built-in `vector` library, so the same code runs in the Luau CLI.
--
-- A track is described like a real circuit drawing: straights and constant-radius
-- arcs. Two straights are marked "free"; their lengths are solved so the lap
-- closes exactly. The dense path is lightly smoothed (gives clothoid-like corner
-- entries), then resampled at a fixed spacing. Each sample carries a banked
-- frame (fwd, right, up), the road width and signed curvature.
--
-- Headings: 0 = +X. Positive angles turn right (towards +Z), matching
-- right = cross(fwd, up). Bank in degrees: positive tilts the road down towards
-- its right edge (what a right-hand corner wants).

local TrackMath = {}

export type Sample = {
	i: number, -- 1-based index
	s: number, -- arc length from the start line
	pos: vector, -- centre of the road surface
	fwd: vector,
	right: vector,
	up: vector,
	width: number,
	bank: number, -- degrees
	curv: number, -- signed curvature in the ground plane (1/studs), + = turning right
	segment: number, -- index of the layout segment this sample came from
}

export type Track = {
	samples: { Sample },
	n: number,
	length: number,
	spacing: number,
	freeLengths: { number },
}

export type Segment = {
	kind: "S" | "A",
	length: (number | "free")?, -- straights
	radius: number?, -- arcs
	angle: number?, -- arcs, degrees, + = right
	bank: number?, -- arcs, degrees (sign is applied from the turn direction)
	width: number?, -- road width from this segment on
	y: number?, -- road height at the end of this segment
	name: string?,
}

export type Spec = {
	Segments: { Segment },
	Spacing: number,
	StartY: number?,
	Smoothing: number?, -- studs, half-window of the path smoothing
	BankSmoothing: number?,
}

local UP = vector.create(0, 1, 0)

local function wrap(i: number, n: number): number
	return ((i - 1) % n) + 1
end
TrackMath.wrap = wrap

local function dirOf(theta: number): vector
	return vector.create(math.cos(theta), 0, math.sin(theta))
end

-- Walks the layout with the given free lengths. Calls `emit(pos2d, segIndex,
-- localT)` every `step` studs when `emit` is given. Returns the end position
-- (x, z) and the heading.
local function walk(spec: Spec, free: { number }, step: number?, emit: ((number, number, number, number) -> ())?): (number, number, number)
	local x, z, theta = 0, 0, 0
	local f = 0
	for k, seg in spec.Segments do
		if seg.kind == "S" then
			local len: number
			if seg.length == "free" then
				f += 1
				len = free[f] or 0
			else
				len = seg.length :: number
			end
			local d = dirOf(theta)
			if emit and step then
				local count = math.max(1, math.floor(len / step + 0.5))
				for j = 0, count - 1 do
					local t = j / count
					emit(x + d.x * len * t, z + d.z * len * t, k, t)
				end
			end
			x += d.x * len
			z += d.z * len
		else
			local r = seg.radius :: number
			local ang = math.rad(seg.angle :: number)
			local sgn = if ang >= 0 then 1 else -1
			-- centre is to the right for right turns, to the left for left turns
			local rightDir = dirOf(theta + math.pi / 2)
			local cx, cz = x + rightDir.x * r * sgn, z + rightDir.z * r * sgn
			local a0 = math.atan2(z - cz, x - cx)
			if emit and step then
				local len = r * math.abs(ang)
				local count = math.max(1, math.floor(len / step + 0.5))
				for j = 0, count - 1 do
					local t = j / count
					local a = a0 + ang * t
					emit(cx + math.cos(a) * r, cz + math.sin(a) * r, k, t)
				end
			end
			local a1 = a0 + ang
			x, z = cx + math.cos(a1) * r, cz + math.sin(a1) * r
			theta += ang
		end
	end
	return x, z, theta
end

-- Solves the two free straight lengths so the lap closes.
local function solveFree(spec: Spec): { number }
	local dirs: { vector } = {}
	local theta = 0
	for _, seg in spec.Segments do
		if seg.kind == "S" then
			if seg.length == "free" then
				table.insert(dirs, dirOf(theta))
			end
		else
			theta += math.rad(seg.angle :: number)
		end
	end
	assert(#dirs == 2, "the layout needs exactly two free straights")
	-- clockwise +360, anticlockwise -360; a figure of eight (one road
	-- crossing the other on a bridge) turns 0 degrees
	assert(
		math.abs(math.abs(theta) - 2 * math.pi) < 1e-6 or math.abs(theta) < 1e-6,
		string.format("corners must add up to +-360 degrees, or 0 for a figure of eight (got %.2f)", math.deg(theta))
	)
	local ex, ez = walk(spec, { 0, 0 })
	-- L1*d1 + L2*d2 = -E
	local a, b, c, d = dirs[1].x, dirs[2].x, dirs[1].z, dirs[2].z
	local det = a * d - b * c
	assert(math.abs(det) > 1e-6, "free straights must not be parallel")
	local l1 = (-ex * d + b * ez) / det
	local l2 = (-a * ez + c * ex) / det
	return { l1, l2 }
end

local function smoothClosed(values: { number }, half: number): { number }
	local n = #values
	if half < 1 then
		return values
	end
	local out = table.create(n, 0)
	local sum = 0
	for j = -half, half do
		sum += values[wrap(1 + j, n)]
	end
	local w = 2 * half + 1
	for i = 1, n do
		out[i] = sum / w
		sum += values[wrap(i + half + 1, n)] - values[wrap(i - half, n)]
	end
	return out
end

function TrackMath.build(spec: Spec): Track
	local free = solveFree(spec)

	-- 1. Dense path, one point per stud
	local xs: { number }, zs: { number }, segs: { number }, ts: { number } = {}, {}, {}, {}
	walk(spec, free, 1, function(x, z, k, t)
		table.insert(xs, x)
		table.insert(zs, z)
		table.insert(segs, k)
		table.insert(ts, t)
	end)
	local dn = #xs

	-- per-point height, bank and width from the segment settings
	local ys, banks, widths = table.create(dn, 0), table.create(dn, 0), table.create(dn, 0)
	local segStartY: { number } = {}
	local segWidth: { number } = {}
	local y = spec.StartY or 0
	local width = spec.Segments[1].width or 34
	for k, seg in spec.Segments do
		segStartY[k] = y
		y = seg.y or y
		width = seg.width or width
		segWidth[k] = width
	end
	for j = 1, dn do
		local k = segs[j]
		local seg = spec.Segments[k]
		local y0 = segStartY[k]
		local y1 = seg.y or y0
		ys[j] = y0 + (y1 - y0) * ts[j]
		widths[j] = segWidth[k]
		if seg.kind == "A" then
			local sgn = if (seg.angle :: number) >= 0 then 1 else -1
			banks[j] = (seg.bank or 0) * sgn
		else
			banks[j] = 0
		end
	end

	-- 2. Smooth (closed loop). Small window for x/z, larger for the rest.
	local half = math.floor(spec.Smoothing or 12)
	xs = smoothClosed(smoothClosed(xs, half), half)
	zs = smoothClosed(smoothClosed(zs, half), half)
	ys = smoothClosed(smoothClosed(ys, 30), 30)
	banks = smoothClosed(smoothClosed(banks, math.floor(spec.BankSmoothing or 25)), math.floor(spec.BankSmoothing or 25))
	widths = smoothClosed(widths, 20)

	local cum = { 0 }
	for j = 2, dn + 1 do
		local a, b = j - 1, wrap(j, dn)
		cum[j] = cum[j - 1] + math.sqrt((xs[b] - xs[a]) ^ 2 + (ys[b] - ys[a]) ^ 2 + (zs[b] - zs[a]) ^ 2)
	end
	local total = cum[dn + 1]

	-- 3. Resample at a uniform spacing that divides the lap exactly
	local n = math.max(8, math.floor(total / spec.Spacing + 0.5))
	local ds = total / n
	local samples: { Sample } = {}
	local k = 1
	for i = 1, n do
		local s = (i - 1) * ds
		while cum[k + 1] < s do
			k += 1
		end
		local seg = cum[k + 1] - cum[k]
		local f = if seg > 0 then (s - cum[k]) / seg else 0
		local a, b = k, wrap(k + 1, dn)
		local function lerp(arr: { number }): number
			return arr[a] + (arr[b] - arr[a]) * f
		end
		samples[i] = {
			i = i,
			s = s,
			pos = vector.create(lerp(xs), lerp(ys), lerp(zs)),
			fwd = vector.zero,
			right = vector.zero,
			up = UP,
			width = lerp(widths),
			bank = lerp(banks),
			curv = 0,
			segment = segs[a],
		}
	end

	-- 4. Frames and curvature
	for i = 1, n do
		local prev = samples[wrap(i - 1, n)].pos
		local nxt = samples[wrap(i + 1, n)].pos
		samples[i].fwd = vector.normalize(nxt - prev)
	end
	for i = 1, n do
		local smp = samples[i]
		local flatRight = vector.normalize(vector.cross(smp.fwd, UP))
		local flatUp = vector.cross(flatRight, smp.fwd)
		local b = math.rad(smp.bank)
		smp.up = flatUp * math.cos(b) + flatRight * math.sin(b)
		smp.right = flatRight * math.cos(b) - flatUp * math.sin(b)
		local f0 = samples[wrap(i - 1, n)].fwd
		local f1 = samples[wrap(i + 1, n)].fwd
		local h0 = math.atan2(f0.z, f0.x)
		local h1 = math.atan2(f1.z, f1.x)
		local dh = (h1 - h0 + math.pi) % (2 * math.pi) - math.pi
		smp.curv = dh / (2 * ds)
	end

	return { samples = samples, n = n, length = total, spacing = ds, freeLengths = free }
end

-- Left and right road edges of a sample, optionally pushed outwards.
function TrackMath.edges(smp: Sample, extra: number?): (vector, vector)
	local h = smp.width / 2 + (extra or 0)
	return smp.pos - smp.right * h, smp.pos + smp.right * h
end

-- Nearest sample to `pos`, searching `back` samples behind and `ahead` samples in
-- front of `hint`. Without a hint the whole lap is searched.
-- Returns the sample index, lateral offset (studs, + = right) and arc position.
function TrackMath.nearest(track: Track, pos: vector, hint: number?, back: number?, ahead: number?): (number, number, number)
	local n = track.n
	local samples = track.samples
	local lo, hi = 1, n
	if hint ~= nil then
		lo, hi = hint - (back or n), hint + (ahead or n)
		if hi - lo + 1 > n then
			lo, hi = 1, n
		end
	end
	local best, bestD = 1, math.huge
	for j = lo, hi do
		local idx = wrap(j, n)
		local dv = pos - samples[idx].pos
		local d = vector.dot(dv, dv)
		if d < bestD then
			best, bestD = idx, d
		end
	end
	local smp = samples[best]
	local along = vector.dot(pos - smp.pos, smp.fwd)
	local lateral = vector.dot(pos - smp.pos, smp.right)
	local s = (smp.s + math.clamp(along, -track.spacing, track.spacing)) % track.length
	return best, lateral, s
end

-- Signed distance from b to a along the lap, in (-length/2, length/2].
function TrackMath.arcDelta(track: Track, a: number, b: number): number
	local d = (a - b) % track.length
	if d > track.length / 2 then
		d -= track.length
	end
	return d
end

-- Pose for a kart standing on sample i, shifted sideways (+ = right) and back
-- along the road. Returns position (centre of road surface) and frame vectors.
function TrackMath.slot(track: Track, i: number, lateral: number, back: number): (vector, vector, vector)
	local n = track.n
	local steps = back / track.spacing
	local i0 = math.floor(steps)
	local f = steps - i0
	local a = track.samples[wrap(i - i0, n)]
	local b = track.samples[wrap(i - i0 - 1, n)]
	local pos = a.pos + (b.pos - a.pos) * f
	local right = vector.normalize(a.right + (b.right - a.right) * f)
	local fwd = vector.normalize(a.fwd + (b.fwd - a.fwd) * f)
	local up = vector.cross(right, fwd)
	return pos + right * lateral, fwd, up
end

return TrackMath
