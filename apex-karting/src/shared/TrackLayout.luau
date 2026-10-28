--!strict
-- Where everything around the road goes: kerbs, the verge / run-off / gravel
-- bands beside the road, barriers, the pit lane, garages and paddock,
-- grandstands, the bridge, marshal posts and (on a circuit with hills) the
-- embankments the raised road stands on.
-- Pure Luau (no requires, no Roblox APIs) so it is tested and plotted
-- headlessly; the server's builders only turn these numbers into parts.

local TrackLayout = {}

type Sample = {
	i: number,
	s: number,
	pos: vector,
	fwd: vector,
	right: vector,
	up: vector,
	width: number,
	bank: number,
	curv: number,
	segment: number,
}
type Track = {
	samples: { Sample },
	n: number,
	length: number,
	spacing: number,
	freeLengths: { number },
}

local UP = vector.create(0, 1, 0)

TrackLayout.RoadThickness = 1.0
TrackLayout.KerbWidth = 3.2
TrackLayout.KerbHeight = 0.1
TrackLayout.Turf = 6 -- artificial-turf verge beside the white line
TrackLayout.RunOff = 28 -- painted asphalt run-off outside tight corners
TrackLayout.GravelFrom = 9 -- gravel trap outside the hairpin
TrackLayout.GravelTo = 34
TrackLayout.LawnY = -0.1 -- top of the lawn (everything else sits at 0)
TrackLayout.PitWallLateral = 7 -- beyond the main straight's left edge
TrackLayout.PitLaneWidth = 20
TrackLayout.GarageDepth = 22
TrackLayout.PaddockDepth = 80
TrackLayout.FacilityMargin = 120

local function wrap(i: number, n: number): number
	return ((i - 1) % n) + 1
end
TrackLayout.wrap = wrap

-- Sample counts in this file are tuned for 6-stud samples. Circuits with
-- hills use finer samples (a smoother road surface), so every window scales
-- to keep its length in studs.
local function steps(track: Track, n: number): number
	return math.max(1, math.floor(n * 6 / track.spacing + 0.5))
end
TrackLayout.steps = steps

local function flat(v: vector): vector
	return vector.create(v.x, 0, v.z)
end

-- unit vector pointing away from the road on one side (-1 left, 1 right)
local function outward(smp: Sample, side: number): vector
	return vector.normalize(flat(smp.right)) * side
end
TrackLayout.outward = outward

----------------------------------------------------------------------------
-- Spatial grid of samples (x/z buckets) for nearest-sample queries
----------------------------------------------------------------------------
local CELL = 32

export type Grid = { cells: { [number]: { number } }, track: Track }

local function cellKey(cx: number, cz: number): number
	return (cx + 2048) * 4096 + (cz + 2048)
end

function TrackLayout.grid(track: Track): Grid
	local cells: { [number]: { number } } = {}
	for i, smp in track.samples do
		local k = cellKey(math.floor(smp.pos.x / CELL), math.floor(smp.pos.z / CELL))
		local list = cells[k]
		if not list then
			list = {}
			cells[k] = list
		end
		table.insert(list, i)
	end
	return { cells = cells, track = track }
end

-- Nearest sample in the ground plane within `radius` (or nil), optionally
-- ignoring samples within `skip` indices of `around`.
function TrackLayout.nearest(grid: Grid, x: number, z: number, radius: number, around: number?, skip: number?): (number?, number)
	local track = grid.track
	local r = math.ceil(radius / CELL)
	local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
	local best, bestD = nil, radius * radius
	for dx = -r, r do
		for dz = -r, r do
			local list = grid.cells[cellKey(cx + dx, cz + dz)]
			if list then
				for _, i in list do
					local ok = true
					if around and skip then
						local sep = math.abs(i - around)
						sep = math.min(sep, track.n - sep)
						ok = sep > skip
					end
					if ok then
						local p = track.samples[i].pos
						local d = (p.x - x) ^ 2 + (p.z - z) ^ 2
						if d < bestD then
							best, bestD = i, d
						end
					end
				end
			end
		end
	end
	return best, math.sqrt(bestD)
end

-- Is p clear of every road (except samples near `around`) by `margin`?
local function clearOfRoads(grid: Grid, p: vector, margin: number, around: number?, skip: number?): boolean
	local i, d = TrackLayout.nearest(grid, p.x, p.z, 160, around, skip)
	if not i then
		return true
	end
	return d > grid.track.samples[i].width / 2 + margin
end
TrackLayout.clearOfRoads = clearOfRoads

-- Curvature smoothed over a few samples (sample noise would make kerbs flicker).
function TrackLayout.smoothCurv(track: Track, i: number, half: number): number
	local sum = 0
	for j = -half, half do
		sum += track.samples[wrap(i + j, track.n)].curv
	end
	return sum / (2 * half + 1)
end

----------------------------------------------------------------------------
-- Kerbs: inside of every corner tighter than 160, outside of those tighter
-- than 95, starting a little before and ending a little after the corner.
----------------------------------------------------------------------------
function TrackLayout.kerbs(track: Track): { { left: boolean, right: boolean } }
	local n = track.n
	local raw: { { left: boolean, right: boolean } } = table.create(n)
	for i = 1, n do
		local c = TrackLayout.smoothCurv(track, i, steps(track, 2))
		local inside = math.abs(c) > 1 / 160
		local outside = math.abs(c) > 1 / 95
		-- right-hander (c > 0): inside is the right edge
		local right = (c > 0 and inside) or (c < 0 and outside)
		local left = (c < 0 and inside) or (c > 0 and outside)
		raw[i] = { left = left, right = right }
	end
	local out: { { left: boolean, right: boolean } } = table.create(n)
	local reach = steps(track, 2)
	for i = 1, n do
		local l, r = false, false
		for j = -reach, reach do
			local k = raw[wrap(i + j, n)]
			l = l or k.left
			r = r or k.right
		end
		out[i] = { left = l, right = r }
	end
	return out
end

----------------------------------------------------------------------------
-- Bands beside the road, per sample and side (distances beyond the edge):
--   kerb    0 .. kerb        red/white kerb (where there is one)
--   runoff  kerb .. runoff   painted asphalt run-off (outside tight corners)
--   gravel  gravelFrom .. gravelTo (outside the hairpin)
--   turf    .. Turf          artificial turf verge everywhere else
-- Ends taper smoothly between samples and never reach another part of the
-- circuit.
----------------------------------------------------------------------------
export type Bands = { kerb: number, runoff: number, gravelFrom: number, gravelTo: number, turf: number, clear: number }
export type Zones = { { left: Bands, right: Bands } }

local function movingAverage(values: { number }, half: number): { number }
	local n = #values
	local out = table.create(n, 0)
	for i = 1, n do
		local sum = 0
		for j = -half, half do
			sum += values[wrap(i + j, n)]
		end
		out[i] = sum / (2 * half + 1)
	end
	return out
end

local function dilate(values: { boolean }, half: number): { number }
	local n = #values
	local out = table.create(n, 0)
	for i = 1, n do
		for j = -half, half do
			if values[wrap(i + j, n)] then
				out[i] = 1
				break
			end
		end
	end
	return out
end

-- How far out from the edge (up to `maxD`) the ground is clear of other roads.
local function clearance(grid: Grid, smp: Sample, side: number, maxD: number): number
	local half = smp.width / 2
	local dir = outward(smp, side)
	local base = flat(smp.pos) + dir * half
	local d = 2
	while d <= maxD do
		if not clearOfRoads(grid, base + dir * d, 6, smp.i, steps(grid.track, 25)) then
			return math.max(d - 6, 0)
		end
		d += 2
	end
	return maxD
end

-- Samples of a road that passes under another (a figure of eight), within
-- `reach` samples of the crossing: it runs between retaining walls there, so
-- it gets no run-off or gravel (TrackLayout.crossings has the details).
local function underCrossing(track: Track, grid: Grid, reach: number): { [number]: boolean }
	local n = track.n
	local out: { [number]: boolean } = {}
	for i = 1, n do
		local a = track.samples[i]
		local j, d = TrackLayout.nearest(grid, a.pos.x, a.pos.z, a.width, i, steps(track, 30))
		if j then
			local b = track.samples[j]
			if d < math.min(a.width, b.width) / 2 and a.pos.y > b.pos.y + 6 then
				for k = -reach, reach do
					out[wrap(j + k, n)] = true
				end
			end
		end
	end
	return out
end

function TrackLayout.zones(track: Track, grid: Grid): Zones
	local n = track.n
	local kerbs = TrackLayout.kerbs(track)
	local out: Zones = table.create(n)
	local perSide: { [number]: { runoff: { number }, gravel: { number } } } = {}
	local walled = underCrossing(track, grid, steps(track, 13))
	for _, side in { -1, 1 } do
		local tight, hairpin = table.create(n, false), table.create(n, false)
		for i = 1, n do
			local c = TrackLayout.smoothCurv(track, i, steps(track, 4))
			local isOutside = (c > 0 and side < 0) or (c < 0 and side > 0)
			tight[i] = isOutside and math.abs(c) > 1 / 110
			hairpin[i] = isOutside and math.abs(c) > 1 / 50
		end
		perSide[side] = {
			runoff = movingAverage(dilate(tight, steps(track, 5)), steps(track, 3)),
			gravel = movingAverage(dilate(hairpin, steps(track, 4)), steps(track, 3)),
		}
		for i in walled do
			perSide[side].runoff[i] = 0
			perSide[side].gravel[i] = 0
		end
	end
	for i = 1, n do
		local smp = track.samples[i]
		local entry = {} :: any
		for _, side in { -1, 1 } do
			local k = kerbs[i]
			local kw = if (side < 0 and k.left) or (side > 0 and k.right) then TrackLayout.KerbWidth else 0
			local maxD = TrackLayout.GravelTo + 2
			local clear = clearance(grid, smp, side, maxD)
			local runoff = math.max(kw, TrackLayout.RunOff * perSide[side].runoff[i])
			local g = perSide[side].gravel[i]
			local gravelFrom, gravelTo = 0, 0
			if g > 0.01 then
				gravelFrom = TrackLayout.GravelFrom
				gravelTo = TrackLayout.GravelFrom + (TrackLayout.GravelTo - TrackLayout.GravelFrom) * g
				runoff = math.min(runoff, gravelFrom)
			end
			runoff = math.min(runoff, clear)
			gravelTo = math.min(gravelTo, clear)
			if gravelTo <= gravelFrom + 1 then
				gravelFrom, gravelTo = 0, 0
			end
			local turf = math.min(TrackLayout.Turf, clear)
			local bands: Bands = { kerb = kw, runoff = runoff, gravelFrom = gravelFrom, gravelTo = gravelTo, turf = turf, clear = clear }
			if side < 0 then
				entry.left = bands
			else
				entry.right = bands
			end
		end
		out[i] = entry
	end
	return out
end

-- Outer end of the prepared surface on one side (where a barrier may stand).
function TrackLayout.bandEnd(b: Bands): number
	return math.max(b.kerb, b.runoff, b.gravelTo, b.turf)
end

----------------------------------------------------------------------------
-- Barriers: polylines of points on the ground.
----------------------------------------------------------------------------
export type Barrier = { kind: "tyres" | "wall", points: { vector } }

local function chainPoints(raw: { { i: number, p: vector } }, maxGap: number, minCount: number): { { vector } }
	table.sort(raw, function(a, b)
		return a.i < b.i
	end)
	local lines: { { vector } } = {}
	local cur: { vector } = {}
	local last: vector? = nil
	for _, e in raw do
		if last and vector.magnitude(e.p - last) > maxGap then
			if #cur >= minCount then
				table.insert(lines, cur)
			end
			cur = {}
		end
		table.insert(cur, e.p)
		last = e.p
	end
	if #cur >= minCount then
		table.insert(lines, cur)
	end
	return lines
end

function TrackLayout.barriers(track: Track, grid: Grid, zones: Zones): { Barrier }
	local n = track.n
	local out: { Barrier } = {}
	local ground = TrackLayout.ground(track, grid, zones)
	local function onGround(lines: { { vector } }): { { vector } }
		for _, line in lines do
			for k, p in line do
				line[k] = vector.create(p.x, TrackLayout.groundY(ground, p.x, p.z), p.z)
			end
		end
		return lines
	end

	-- (a) concrete walls down the middle of narrow gaps between two parts of the
	-- circuit (not where one crosses the other: the trench walls do that job)
	local gap: { { i: number, p: vector } } = {}
	for i = 1, n do
		local a = track.samples[i]
		local j, d = TrackLayout.nearest(grid, a.pos.x, a.pos.z, 140, i, steps(track, 30))
		if j and (TrackLayout.nearCrossing(ground, i, steps(track, 15)) or TrackLayout.nearCrossing(ground, j, steps(track, 15))) then
			j = nil
		end
		if j then
			local b = track.samples[j]
			local clear = d - a.width / 2 - b.width / 2
			if clear > 16 and clear < 80 and i < j then
				local m = (a.pos + b.pos) / 2
				table.insert(gap, { i = i, p = vector.create(m.x, 0, m.z) })
			end
		end
	end
	for _, line in onGround(chainPoints(gap, 14, 4)) do
		table.insert(out, { kind = "wall", points = line })
	end

	-- (b) tyre walls just beyond the run-off/gravel outside tight corners
	local tyres: { { i: number, p: vector } } = {}
	for i = 1, n do
		local smp = track.samples[i]
		for _, side in { -1, 1 } do
			local b = if side < 0 then zones[i].left else zones[i].right
			local ending = math.max(b.runoff, b.gravelTo)
			if ending > TrackLayout.RunOff * 0.6 and not TrackLayout.nearCrossing(ground, i, steps(track, 3)) then
				local p = flat(smp.pos) + outward(smp, side) * (smp.width / 2 + ending + 3)
				if clearOfRoads(grid, p, 12, i, steps(track, 20)) then
					table.insert(tyres, { i = i * 2 + (if side < 0 then 0 else 1), p = p })
				end
			end
		end
	end
	for _, line in onGround(chainPoints(tyres, 14, 4)) do
		table.insert(out, { kind = "tyres", points = line })
	end
	return out
end

----------------------------------------------------------------------------
-- Pit lane, garages and paddock along the main straight (its left side)
----------------------------------------------------------------------------
export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Paddock = {
	wall: { vector }, -- pit wall polyline
	pitLane: Rect,
	garages: Rect,
	plaza: Rect,
	straightZ: number,
	halfWidth: number,
}

function TrackLayout.paddock(track: Track): Paddock
	-- the main straight runs along +X at z = 0 through the start line
	local minX, maxX = math.huge, -math.huge
	local halfW = 0
	for _, smp in track.samples do
		if math.abs(smp.fwd.x) > 0.999 and math.abs(smp.pos.z) < 1 then
			minX = math.min(minX, smp.pos.x)
			maxX = math.max(maxX, smp.pos.x)
			halfW = math.max(halfW, smp.width / 2)
		end
	end
	local x0, x1 = minX + 12, maxX - 30
	local wallZ = -(halfW + TrackLayout.PitWallLateral)
	local wall: { vector } = {}
	local x = x0
	while x <= x1 do
		table.insert(wall, vector.create(x, 0, wallZ))
		x += 12
	end
	local laneTop = wallZ - 1
	local lane = { minX = x0, maxX = x1, minZ = laneTop - TrackLayout.PitLaneWidth, maxZ = laneTop }
	local garages = { minX = x0 + 10, maxX = x1 - 10, minZ = lane.minZ - TrackLayout.GarageDepth, maxZ = lane.minZ }
	local plaza = { minX = x0 - 10, maxX = x1 + 10, minZ = garages.minZ - TrackLayout.PaddockDepth, maxZ = garages.minZ }
	return { wall = wall, pitLane = lane, garages = garages, plaza = plaza, straightZ = 0, halfWidth = halfW }
end

----------------------------------------------------------------------------
-- Grandstands, bridge, marshal posts
----------------------------------------------------------------------------
export type Stand = { center: vector, facing: vector, length: number, depth: number, name: string }

local function segmentMiddle(track: Track, segment: number): number?
	local first, last = nil, nil
	for i, smp in track.samples do
		if smp.segment == segment then
			first = first or i
			last = i
		end
	end
	if not first or not last then
		return nil
	end
	return (first + last) // 2
end
TrackLayout.segmentMiddle = segmentMiddle

-- Corners: runs of consecutive arcs that share a name (a long corner drawn as
-- several arcs, like Luffield) count as one corner; unnamed arcs stand alone.
-- `mid` is the middle sample of the whole corner, `angle` its total turn.
export type Corner = { name: string?, angle: number, first: number, last: number, mid: number }

function TrackLayout.corners(track: Track, segments: { any }): { Corner }
	local out: { Corner } = {}
	local cur: Corner? = nil
	for k, seg in segments do
		if seg.kind == "A" then
			if cur and seg.name ~= nil and cur.name == seg.name and cur.last == k - 1 then
				cur.angle += seg.angle
				cur.last = k
			else
				cur = { name = seg.name, angle = seg.angle, first = k, last = k, mid = 0 }
				table.insert(out, cur :: Corner)
			end
		else
			cur = nil
		end
	end
	local kept: { Corner } = {}
	for _, c in out do
		local first, last = nil, nil
		for i, smp in track.samples do
			if smp.segment >= c.first and smp.segment <= c.last then
				first = first or i
				last = i
			end
		end
		if first and last then
			c.mid = (first + last) // 2
			table.insert(kept, c)
		end
	end
	return kept
end

-- Grandstand facing the road at sample i on `side`, set back past the bands.
local function standAt(track: Track, zones: Zones, i: number, side: number, setback: number, length: number, name: string): Stand
	local smp = track.samples[i]
	local b = if side < 0 then zones[i].left else zones[i].right
	local dir = outward(smp, side)
	local d = smp.width / 2 + TrackLayout.bandEnd(b) + setback
	return { center = flat(smp.pos) + dir * d, facing = -dir, length = length, depth = 28, name = name }
end

function TrackLayout.stands(track: Track, grid: Grid, zones: Zones, segments: { any }): { Stand }
	local P = TrackLayout.paddock(track)
	local ground = TrackLayout.ground(track, grid, zones)
	-- clear of every road? Then the highest ground under the footprint.
	local function fit(st: Stand): number?
		local along = vector.cross(st.facing, UP)
		local top = 0
		for _, u in { -0.5, 0, 0.5 } do
			for _, v in { 0, 1 } do
				local p = st.center + along * (u * st.length) - st.facing * (v * st.depth)
				if not clearOfRoads(grid, p, 10) then
					return nil
				end
				top = math.max(top, TrackLayout.groundY(ground, p.x, p.z))
			end
		end
		return top
	end
	local kept: { Stand } = {}
	-- main grandstand: infield side of the main straight, facing the pits, on
	-- the level; shorter (and slid along) where the infield is cramped
	local full = math.min(P.pitLane.maxX - P.pitLane.minX - 40, 280)
	local mainX = (P.pitLane.minX + P.pitLane.maxX) / 2
	local placed = false
	for _, len in { full, 200, 140 } do
		if placed or len > full then
			continue
		end
		local slack = (full - len) / 2
		for _, dx in { 0, -slack, slack, -slack / 2, slack / 2 } do
			local st: Stand = {
				center = vector.create(mainX + dx, 0, P.halfWidth + 14 + 14),
				facing = vector.create(0, 0, -1),
				length = len,
				depth = 28,
				name = "Main",
			}
			local top = fit(st)
			if top and top <= 0.3 then
				table.insert(kept, st)
				placed = true
				break
			end
		end
	end
	-- outside the slowest corners: on the level, or up on a concrete plinth
	-- where the ground there is an embankment (a circuit with hills)
	for _, c in TrackLayout.corners(track, segments) do
		if math.abs(c.angle) >= 90 then
			local side = if c.angle > 0 then -1 else 1
			local st = standAt(track, zones, c.mid, side, 22, 100, c.name or "Corner")
			local top = fit(st)
			if top then
				if top > 0.3 then
					st.center = vector.create(st.center.x, top, st.center.z)
				end
				table.insert(kept, st)
			end
		end
	end
	return kept
end

-- Sample index for the sponsor bridge: over the straight called `name` if
-- given, else over the longest fixed-length straight (not the first one).
function TrackLayout.bridge(track: Track, segments: { any }, name: string?): number?
	if name then
		for k, seg in segments do
			if seg.kind == "S" and seg.name == name then
				return segmentMiddle(track, k)
			end
		end
	end
	local best, bestLen = nil, 0
	for k, seg in segments do
		if seg.kind == "S" and type(seg.length) == "number" and seg.length > bestLen and k ~= 1 then
			best, bestLen = k, seg.length
		end
	end
	return if best then segmentMiddle(track, best) else nil
end

export type Post = { pos: vector, facing: vector }

-- A marshal post on the inside of every corner of 60 degrees or more.
function TrackLayout.marshals(track: Track, grid: Grid, zones: Zones, segments: { any }): { Post }
	local out: { Post } = {}
	for _, c in TrackLayout.corners(track, segments) do
		if math.abs(c.angle) >= 60 then
			local i = c.mid
			local smp = track.samples[i]
			local side = if c.angle > 0 then 1 else -1 -- inside of the corner
			local b = if side < 0 then zones[i].left else zones[i].right
			local dir = outward(smp, side)
			local p = flat(smp.pos) + dir * (smp.width / 2 + TrackLayout.bandEnd(b) + 8)
			if clearOfRoads(grid, p, 8, i, steps(track, 15)) then
				local y = TrackLayout.groundY(TrackLayout.ground(track, grid, zones), p.x, p.z)
				table.insert(out, { pos = vector.create(p.x, y, p.z), facing = -dir })
			end
		end
	end
	return out
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function lcg(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
TrackLayout.random = lcg

-- Bounding box of the circuit plus a margin.
function TrackLayout.bounds(track: Track, margin: number): Rect
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, smp in track.samples do
		minX = math.min(minX, smp.pos.x)
		maxX = math.max(maxX, smp.pos.x)
		minZ = math.min(minZ, smp.pos.z)
		maxZ = math.max(maxZ, smp.pos.z)
	end
	return { minX = minX - margin, maxX = maxX + margin, minZ = minZ - margin, maxZ = maxZ + margin }
end

-- The walled facility: circuit plus margin, stretched to include the paddock.
function TrackLayout.facility(track: Track): Rect
	-- room for the embankments of a raised circuit inside the fence
	local maxY = 0
	for _, smp in track.samples do
		maxY = math.max(maxY, smp.pos.y)
	end
	local margin = math.max(TrackLayout.FacilityMargin, maxY * TrackLayout.EmbankRun + TrackLayout.GravelTo + 24)
	local b = TrackLayout.bounds(track, margin)
	local P = TrackLayout.paddock(track)
	b.minZ = math.min(b.minZ, P.plaza.minZ - 10)
	-- round to 10 studs so the lawn stripes line up
	b.minX = math.floor(b.minX / 10) * 10
	b.minZ = math.floor(b.minZ / 10) * 10
	b.maxX = math.ceil(b.maxX / 10) * 10
	b.maxZ = math.ceil(b.maxZ / 10) * 10
	return b
end

-- Open ground inside the facility, away from everything that gets built:
-- points every `step` studs that are at least `minClear` studs from the
-- nearest road edge (well past kerbs, run-off, barriers and corner boards),
-- off the paddock and clear of the grandstands. Most open first; `clear` is
-- the distance to the nearest road edge (capped at 400), or to the fence or
-- a grandstand plus 26 if one of those is nearer. For lakes and trees.
export type Spot = { pos: vector, clear: number }
function TrackLayout.openGround(track: Track, grid: Grid, zones: Zones, segments: { any }, step: number, minClear: number): { Spot }
	local f = TrackLayout.facility(track)
	local P = TrackLayout.paddock(track)
	local stands = TrackLayout.stands(track, grid, zones, segments)
	local out: { Spot } = {}
	for x = f.minX + 30, f.maxX - 30, step do
		for z = f.minZ + 30, f.maxZ - 30, step do
			-- the pits and the paddock beside the main straight
			if z < P.pitLane.maxZ + 10 and x > P.plaza.minX - 30 and x < P.plaza.maxX + 30 then
				continue
			end
			local i, d = TrackLayout.nearest(grid, x, z, 400)
			local clear = if i then d - track.samples[i].width / 2 else 400
			-- the perimeter fence and the grandstands count as obstacles too,
			-- with a smaller margin than the road (EDGE_SLACK closer), so a
			-- lake sized by `clear` stays inside the fence and off the stands
			local EDGE_SLACK = 26
			local edge = math.min(x - f.minX, f.maxX - x, z - f.minZ, f.maxZ - z)
			clear = math.min(clear, edge + EDGE_SLACK)
			if clear < minClear then
				continue
			end
			local free = true
			for _, st in stands do
				local dx, dz = x - st.center.x, z - st.center.z
				local gap = math.sqrt(dx * dx + dz * dz) - (st.length / 2 + st.depth)
				if gap < 25 then
					free = false
					break
				end
				clear = math.min(clear, gap + EDGE_SLACK)
			end
			if free and clear >= minClear then
				table.insert(out, { pos = vector.create(x, 0, z), clear = clear })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.clear > b.clear
	end)
	return out
end

----------------------------------------------------------------------------
-- Ground under a circuit with hills (TrackData `y` values): grassy
-- embankments fall away from the outer edge of the bands at 1 in EmbankRun
-- down to the lawn, or until they meet another embankment (the higher one
-- wins, so two slopes meet in a valley) or another road. Flat circuits have
-- none and everything stays at y = 0.
----------------------------------------------------------------------------
TrackLayout.EmbankRun = 2.5 -- horizontal studs per stud of drop (about 22 degrees)

-- outer edge of the prepared surface (road + bands) on one side of a sample
export type Edge = { top: vector, dir: vector, foot: number }
export type Ground = {
	raised: boolean,
	track: Track,
	grid: Grid,
	zones: Zones,
	edges: { { left: Edge, right: Edge } },
	reach: number,
}
-- one strip of embankment: from the band edge (`top`) down to the `toe`;
-- `pocket` when it stopped above the lawn because its neighbours converge
-- (inside a tight corner): the ground beyond is filled by `pockets`
export type Skirt = { top: vector, toe: vector, pocket: boolean? }

local groundCache: { [any]: Ground } = setmetatable({}, { __mode = "k" }) :: any

function TrackLayout.ground(track: Track, grid: Grid, zones: Zones): Ground
	local cached = groundCache[track]
	if cached then
		return cached
	end
	local edges = table.create(track.n)
	local maxTop, maxFoot = 0, 0
	for i, smp in track.samples do
		local e = {} :: any
		for _, side in { -1, 1 } do
			local b = if side < 0 then zones[i].left else zones[i].right
			local dir = outward(smp, side)
			local top = smp.pos + smp.right * (side * smp.width / 2) + dir * TrackLayout.bandEnd(b)
			local foot = vector.magnitude(flat(top - smp.pos))
			maxTop = math.max(maxTop, top.y)
			maxFoot = math.max(maxFoot, foot)
			local edge: Edge = { top = top, dir = dir, foot = foot }
			if side < 0 then
				e.left = edge
			else
				e.right = edge
			end
		end
		edges[i] = e
	end
	local g: Ground = {
		raised = maxTop > 0.3,
		track = track,
		grid = grid,
		zones = zones,
		edges = edges,
		reach = maxTop * TrackLayout.EmbankRun + maxFoot + 4,
	}
	groundCache[track] = g
	return g
end

-- Height of the ground (road, bands or embankment) at x, z; 0 on the lawn.
-- Samples within `skip` of `around` are left out, and so are those within
-- `skip2` of `around2`.
local function rawGroundY(g: Ground, x: number, z: number, around: number?, skip: number?, around2: number?, skip2: number?): number
	if not g.raised then
		return 0
	end
	local track = g.track
	local n = track.n
	local run = TrackLayout.EmbankRun
	local r = math.ceil(g.reach / CELL)
	local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
	local best = 0
	for dx = -r, r do
		for dz = -r, r do
			local list = g.grid.cells[cellKey(cx + dx, cz + dz)]
			if list then
				for _, j in list do
					if around and skip then
						local sep = math.abs(j - around)
						if math.min(sep, n - sep) <= skip then
							continue
						end
					end
					if around2 and skip2 then
						local sep = math.abs(j - around2)
						if math.min(sep, n - sep) <= skip2 then
							continue
						end
					end
					local smp = track.samples[j]
					local ox, oz = x - smp.pos.x, z - smp.pos.z
					local e = if ox * smp.right.x + oz * smp.right.z >= 0 then g.edges[j].right else g.edges[j].left
					if e.top.y <= best then
						continue
					end
					local d = math.sqrt(ox * ox + oz * oz)
					local h = e.top.y - math.max(0, d - e.foot) / run
					if h > best then
						best = h
					end
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Crossings (a figure of eight): where one part of the circuit passes over
-- another on a bridge. The upper road's `deck` samples are the bridge span
-- (everything of theirs that would stand over the lower road's prepared
-- surface: no embankment under it, a girder and parapets instead); the lower
-- road runs through a trench of concrete retaining walls (`walls`, along its
-- band edges) for as long as the ground beside it is higher than its edge.
----------------------------------------------------------------------------
TrackLayout.CrossingClear = 6 -- a road this much lower where two overlap passes under
TrackLayout.TrenchWall = 2 -- retaining wall thickness
TrackLayout.TrenchKerb = 2.5 -- the walls stand this high above the ground behind them
TrackLayout.GirderDepth = 2.2 -- bridge girder under the deck road
TrackLayout.ParapetHeight = 2.6

-- p: foot of the wall's road-side face (on the band edge, at y 0); dir: out from the road
export type Wall = { i: number, side: number, p: vector, dir: vector, top: number, bottom: number }
export type Crossing = {
	over: number, -- upper-road sample at the crossing point
	under: number, -- lower-road sample under it
	deck: { number }, -- upper-road samples on the bridge, in lap order
	deckSet: { [number]: boolean },
	trenchSet: { [number]: boolean }, -- lower-road samples with a wall on either side
	walls: { Wall },
}

-- The lower-road sample (within `range` of `centre`) whose prepared surface,
-- widened by `extra` studs, q is on; also the lateral offset.
local function onRoadNear(g: Ground, q: vector, centre: number, range: number, extra: number): (number?, number)
	local track = g.track
	local n = track.n
	local best, bestD = nil, math.huge
	for k = centre - range, centre + range do
		local j = wrap(k, n)
		local p = track.samples[j].pos
		local d = (q.x - p.x) ^ 2 + (q.z - p.z) ^ 2
		if d < bestD then
			best, bestD = j, d
		end
	end
	if not best then
		return nil, 0
	end
	local smp = track.samples[best]
	local ox, oz = q.x - smp.pos.x, q.z - smp.pos.z
	local fl = math.sqrt(smp.fwd.x ^ 2 + smp.fwd.z ^ 2)
	local along = (ox * smp.fwd.x + oz * smp.fwd.z) / fl
	if math.abs(along) > track.spacing * 0.75 then
		return nil, 0
	end
	local rl = math.sqrt(smp.right.x ^ 2 + smp.right.z ^ 2)
	local lateral = (ox * smp.right.x + oz * smp.right.z) / rl
	local e = if lateral >= 0 then g.edges[best].right else g.edges[best].left
	if math.abs(lateral) <= e.foot + extra then
		return best, lateral
	end
	return nil, 0
end

local crossingCache: { [any]: { Crossing } } = setmetatable({}, { __mode = "k" }) :: any

function TrackLayout.crossings(g: Ground): { Crossing }
	local cached = crossingCache[g]
	if cached then
		return cached
	end
	local track = g.track
	local n = track.n
	local samples = track.samples
	-- upper-road samples standing over another road's centre line
	local hits: { { i: number, j: number, d: number } } = {}
	for i = 1, n do
		local a = samples[i]
		local j, d = TrackLayout.nearest(g.grid, a.pos.x, a.pos.z, a.width, i, steps(track, 30))
		if j then
			local b = samples[j]
			if d < math.min(a.width, b.width) / 2 and a.pos.y > b.pos.y + TrackLayout.CrossingClear then
				table.insert(hits, { i = i, j = j, d = d })
			end
		end
	end
	-- one crossing per run of such samples: the closest pair
	local out: { Crossing } = {}
	local k = 1
	while k <= #hits do
		local best = hits[k]
		local m = k + 1
		while m <= #hits and hits[m].i - hits[m - 1].i <= 2 do
			if hits[m].d < best.d then
				best = hits[m]
			end
			m += 1
		end
		k = m
		local over, under = best.i, best.j
		-- the bridge span: upper-road samples whose prepared surface reaches the
		-- lower road's (plus room for its walls)
		local function overlaps(s: number): boolean
			local smp = samples[s]
			local el, er = g.edges[s].left, g.edges[s].right
			local dir = outward(smp, 1)
			local t = -el.foot
			while true do
				local q = flat(smp.pos) + dir * t
				if onRoadNear(g, q, under, steps(track, 60), TrackLayout.TrenchWall + 1) then
					return true
				end
				if t >= er.foot then
					return false
				end
				t = math.min(t + 2, er.foot)
			end
		end
		local deck = { over }
		for _, step in { -1, 1 } do
			local s = over + step
			while math.abs(s - over) < steps(track, 40) and overlaps(wrap(s, n)) do
				if step < 0 then
					table.insert(deck, 1, wrap(s, n))
				else
					table.insert(deck, wrap(s, n))
				end
				s += step
			end
		end
		local deckSet: { [number]: boolean } = {}
		for _, s in deck do
			deckSet[s] = true
		end
		-- the deck road's underside over point q (or nil if q is not under it)
		local function deckUnder(q: vector): number?
			local low: number? = nil
			for _, s in deck do
				local smp = samples[s]
				local ox, oz = q.x - smp.pos.x, q.z - smp.pos.z
				local fl = math.sqrt(smp.fwd.x ^ 2 + smp.fwd.z ^ 2)
				local along = (ox * smp.fwd.x + oz * smp.fwd.z) / fl
				local rl = math.sqrt(smp.right.x ^ 2 + smp.right.z ^ 2)
				local lateral = (ox * smp.right.x + oz * smp.right.z) / rl
				local e = if lateral >= 0 then g.edges[s].right else g.edges[s].left
				if math.abs(along) <= track.spacing * 0.75 and math.abs(lateral) <= e.foot + 1.5 then
					local y = smp.pos.y - TrackLayout.RoadThickness - TrackLayout.GirderDepth
					low = if low then math.min(low, y) else y
				end
			end
			return low
		end
		-- retaining walls: out along the lower road while the ground beside it
		-- (the upper road's embankment, everything but the lower road itself)
		-- stands above its edge
		local walls: { Wall } = {}
		local trenchSet: { [number]: boolean } = {}
		for _, step in { -1, 1 } do
			local quiet = 0
			local s = if step < 0 then under else under + 1
			while math.abs(s - under) < steps(track, 50) and quiet < steps(track, 3) do
				local idx = wrap(s, n)
				local smp = samples[idx]
				local any = false
				for _, side in { -1, 1 } do
					local e = if side < 0 then g.edges[idx].left else g.edges[idx].right
					local p = flat(smp.pos) + e.dir * e.foot
					local mid = p + e.dir * (TrackLayout.TrenchWall / 2)
					local beside = rawGroundY(g, mid.x, mid.z, idx, steps(track, 60))
					if beside > e.top.y + 0.5 then
						local top = beside + TrackLayout.TrenchKerb
						local cap = deckUnder(mid)
						if cap then
							top = math.min(top, cap)
						end
						table.insert(walls, { i = idx, side = side, p = p, dir = e.dir, top = top, bottom = e.top.y - 1 })
						any = true
					end
				end
				if any then
					trenchSet[idx] = true
					quiet = 0
				else
					quiet += 1
				end
				s += step
			end
		end
		table.insert(out, { over = over, under = under, deck = deck, deckSet = deckSet, trenchSet = trenchSet, walls = walls })
	end
	crossingCache[g] = out
	return out
end

-- Is sample i on (or within `margin` samples of) a bridge span or a trench?
function TrackLayout.nearCrossing(g: Ground, i: number, margin: number): boolean
	local n = g.track.n
	for _, c in TrackLayout.crossings(g) do
		for k = -margin, margin do
			local j = wrap(i + k, n)
			if c.deckSet[j] or c.trenchSet[j] then
				return true
			end
		end
	end
	return false
end

-- Height of the ground (road, bands or embankment) at x, z; 0 on the lawn.
-- Samples within `skip` of `around` are left out. Inside a trench (on the
-- lower road's prepared surface at a crossing) the upper road and its
-- embankment are left out: there the ground is the lower road.
function TrackLayout.groundY(g: Ground, x: number, z: number, around: number?, skip: number?): number
	if not g.raised then
		return 0
	end
	local q = vector.create(x, 0, z)
	for _, c in TrackLayout.crossings(g) do
		if onRoadNear(g, q, c.under, steps(g.track, 50), 0.5) then
			return rawGroundY(g, x, z, around, skip, c.over, steps(g.track, 45))
		end
	end
	return rawGroundY(g, x, z, around, skip)
end

-- Embankment strips per sample and side (nil where the edge is at ground
-- level). Each runs straight out from the band edge and stops at the lawn,
-- where it meets a neighbouring strip (inside a corner), or at another road's
-- bands (ramping down to their edge height if it is still above it). Strips
-- of two parts of the circuit simply cross where their slopes meet: the
-- higher one is what shows, and no gap is left between them.
function TrackLayout.skirts(g: Ground): { { left: Skirt?, right: Skirt? } }
	local track = g.track
	local n = track.n
	local run = TrackLayout.EmbankRun
	local out = table.create(n)
	for i = 1, n do
		local entry = {} :: any
		if g.raised then
			for _, side in { -1, 1 } do
				local e = if side < 0 then g.edges[i].left else g.edges[i].right
				local h0 = e.top.y
				if h0 < 0.3 then
					continue
				end
				local maxT = h0 * run
				local base = flat(e.top)
				-- on the inside of a corner the strips converge: stop where this
				-- one meets a neighbour's, so they never cross
				local near = steps(track, 3)
				for k = -near, near do
					if k ~= 0 then
						local j = wrap(i + k, n)
						local ej = if side < 0 then g.edges[j].left else g.edges[j].right
						local bj = flat(ej.top)
						local det = e.dir.x * (-ej.dir.z) - e.dir.z * (-ej.dir.x)
						if math.abs(det) > 1e-6 then
							local rx, rz = bj.x - base.x, bj.z - base.z
							local tt = (rx * (-ej.dir.z) - rz * (-ej.dir.x)) / det
							local ss = (e.dir.x * rz - e.dir.z * rx) / det
							if tt > 0 and ss > 0 then
								maxT = math.min(maxT, tt)
							end
						end
					end
				end
				local converged = maxT < h0 * run - 1e-6
				local byRoad = false
				local toeT, toeY = maxT, h0 - maxT / run
				-- the other road whose prepared surface q is on (or nil), and its edge height there
				local function otherRoad(q: vector): number?
					local j, d = TrackLayout.nearest(g.grid, q.x, q.z, 80, i, steps(track, 4))
					if not j then
						return nil
					end
					local smp = track.samples[j]
					local ox, oz = q.x - smp.pos.x, q.z - smp.pos.z
					-- on that sample's cross-section (not just near it: inside a
					-- corner the same road's earlier samples are near too)
					local fl = math.sqrt(smp.fwd.x ^ 2 + smp.fwd.z ^ 2)
					local along = (ox * smp.fwd.x + oz * smp.fwd.z) / fl
					if math.abs(along) > track.spacing * 0.75 then
						return nil
					end
					local ej = if ox * smp.right.x + oz * smp.right.z >= 0 then g.edges[j].right else g.edges[j].left
					return if d < ej.foot then ej.top.y else nil
				end
				-- on a bridge: no strip from an edge that stands over the road
				-- passing underneath (the walls there are TrackLayout.crossings')
				local below = otherRoad(base)
				if below and below < h0 - TrackLayout.CrossingClear then
					continue
				end
				local step = 2
				local t = 0
				while t < maxT do
					local tn = math.min(t + step, maxT)
					local q = base + e.dir * tn
					-- reached another road's bands: end the strip at their edge
					if otherRoad(q) then
						local lo, hi = t, tn
						for _ = 1, 8 do
							local mid = (lo + hi) / 2
							if otherRoad(base + e.dir * mid) then
								hi = mid
							else
								lo = mid
							end
						end
						-- ramp down to their edge if still above it; if already
						-- below, stop there (their own strip covers this one)
						toeT = hi
						toeY = math.min(otherRoad(base + e.dir * hi) or 0, h0 - hi / run)
						-- never steeper than 45 degrees: a very short strip to a
						-- lower road stays level and leaves a kerb-like step
						toeY = math.max(toeY, h0 - hi * 0.8)
						byRoad = true
						break
					end
					t = tn
				end
				-- even a strip that meets another road's bands at once is kept
				-- (down to zero length): its neighbours' strips need its top to
				-- close the thin gap between the two bands
				do
					local toe = base + e.dir * toeT
					local skirt: Skirt = {
						top = e.top,
						toe = vector.create(toe.x, toeY, toe.z),
						pocket = converged and not byRoad and toeY > 0.3,
					}
					if side < 0 then
						entry.left = skirt
					else
						entry.right = skirt
					end
				end
			end
		end
		out[i] = entry
	end
	return out
end

-- The ground inside a tight corner, where the strips from the inner band
-- edge converge and stop above the lawn (`pocket` strips). Left as they
-- are, the space beyond them, between the long strips either side of the
-- corner, would be a hole down to the lawn, and the stopped strips cross
-- each other at different heights. So each run of pocket strips is replaced
-- by a fan: triangles from every pair of band-edge points to one hub (where
-- the strips converge, at the height their slopes reach there on average),
-- two triangles from the hub along the long strips either side, and one
-- across the mouth between those strips' toes. `skip[i]` (per side) marks the
-- strip pairs (i, i + 1) the fan replaces. A run whose fan would fold over
-- itself has its strips carried on down to the lawn instead (they cross).
export type Pockets = { tris: { { vector } }, skipLeft: { [number]: boolean }, skipRight: { [number]: boolean } }
function TrackLayout.pockets(g: Ground, skirts: { { left: Skirt?, right: Skirt? } }): Pockets
	local n = g.track.n
	local run = TrackLayout.EmbankRun
	local result: Pockets = { tris = {}, skipLeft = {}, skipRight = {} }
	for _, side in { -1, 1 } do
		local skip = if side < 0 then result.skipLeft else result.skipRight
		local function get(i: number): Skirt?
			local e = skirts[wrap(i, n)]
			return if side < 0 then e.left else e.right
		end
		-- walk the lap from just after a sample that is not in a pocket, so
		-- no run is split by the wrap-around
		local start = nil
		for k = 1, n do
			local s = get(k)
			if not (s and s.pocket) then
				start = k
				break
			end
		end
		if not start then
			continue
		end
		local k = 0
		while k < n do
			local i = start + 1 + k
			local s = get(i)
			if not (s and s.pocket) then
				k += 1
				continue
			end
			local len = 1
			while k + len < n do
				local nb = get(i + len)
				if not (nb and nb.pocket) then
					break
				end
				len += 1
			end
			k += len
			local a, b = i, i + len - 1
			local first, last = get(a - 1), get(b + 1)
			if not (first and last) then
				continue
			end
			-- the outline, walked once round: band edge, out along the last long
			-- strip, across the mouth, back along the first
			local outline: { vector } = {}
			for j = a - 1, b + 1 do
				table.insert(outline, (get(j) :: Skirt).top)
			end
			-- the two long strips may cross before their toes: then the mouth
			-- closes at the crossing (at the higher strip's height there)
			local p1, d1 = first.top, first.toe - first.top
			local p2, d2 = last.top, last.toe - last.top
			local den = d1.x * d2.z - d1.z * d2.x
			local crossAt: vector? = nil
			if math.abs(den) > 1e-6 then
				local rx, rz = p2.x - p1.x, p2.z - p1.z
				local s1 = (rx * d2.z - rz * d2.x) / den
				local s2 = (rx * d1.z - rz * d1.x) / den
				if s1 > 0 and s1 < 1 and s2 > 0 and s2 < 1 then
					local q = p1 + d1 * s1
					crossAt = vector.create(q.x, math.max(q.y, p2.y + d2.y * s2), q.z)
				end
			end
			if crossAt then
				table.insert(outline, crossAt)
			else
				table.insert(outline, last.toe)
				table.insert(outline, first.toe)
			end
			-- hub: where the stopped strips end, on average; if the fan from
			-- there would fold (the outline is not star-shaped around it), try
			-- points between it and the middle of the outline / the band edge
			local tx, tz = 0, 0
			for j = a, b do
				local t = (get(j) :: Skirt).toe
				tx += t.x
				tz += t.z
			end
			tx /= len
			tz /= len
			local ox, oz, ex, ez = 0, 0, 0, 0
			for _, q in outline do
				ox += q.x / #outline
				oz += q.z / #outline
			end
			for j = a, b do
				local top = (get(j) :: Skirt).top
				ex += top.x / len
				ez += top.z / len
			end
			local candidates = { { tx, tz }, { ox, oz } }
			for _, f in { 0.25, 0.5, 0.75 } do
				table.insert(candidates, { tx + (ox - tx) * f, tz + (oz - tz) * f })
			end
			for _, f in { 0.25, 0.5 } do
				table.insert(candidates, { tx + (ex - tx) * f, tz + (ez - tz) * f })
			end
			local tris: { { vector } } = {}
			local folds = true
			for _, cand in candidates do
				local hx, hz = cand[1], cand[2]
				local hy, cnt, lowest = 0, 0, math.huge
				for j = a - 1, b + 1 do
					local top = (get(j) :: Skirt).top
					hy += top.y - math.sqrt((top.x - hx) ^ 2 + (top.z - hz) ^ 2) / run
					cnt += 1
					lowest = math.min(lowest, top.y)
				end
				local hub = vector.create(hx, math.clamp(hy / cnt, 0, lowest), hz)
				tris = {}
				folds = false
				local sign = 0
				for j = 1, #outline do
					local p, q = outline[j], outline[j % #outline + 1]
					local cross = (q.x - p.x) * (hub.z - p.z) - (q.z - p.z) * (hub.x - p.x)
					if math.abs(cross) > 1e-3 then
						local sg = if cross > 0 then 1 else -1
						if sign == 0 then
							sign = sg
						elseif sg ~= sign then
							folds = true
							break
						end
						table.insert(tris, { p, q, hub })
					end
				end
				if not folds then
					break
				end
			end
			if folds then
				-- no hub works (an S-bend's strips fan out at the mouth): let
				-- the run's strips go on down to the lawn instead, crossing
				-- each other (a crease in the grass rather than a hole)
				for j = a, b do
					local k = get(j) :: Skirt
					local fl = vector.create(k.toe.x - k.top.x, 0, k.toe.z - k.top.z)
					if vector.magnitude(fl) > 1e-6 then
						local toe = k.top + vector.normalize(fl) * (k.top.y * run)
						k.toe = vector.create(toe.x, 0, toe.z)
						k.pocket = false
					end
				end
				continue
			end
			for _, t in tris do
				table.insert(result.tris, t)
			end
			for j = a - 1, b do
				skip[wrap(j, n)] = true
			end
		end
	end
	return result
end

----------------------------------------------------------------------------
-- Road surface pieces. Between two samples the road is a quad whose two
-- cross-sections are straight lines. Where the road climbs through a corner
-- (or the banking winds on) those lines are at different angles and heights,
-- so the quad is twisted, and built from two triangles it has a fold along
-- the diagonal (up to ~0.6 studs on Hillside): the karts rattled over one
-- every sample. A twisted quad is split into a grid of smaller pieces whose
-- corners lie on the smooth (bilinear) surface through its four corners,
-- until every fold is under RoadFold. Flat circuits keep two triangles per
-- quad. (The other half of the rattle was the facets of a sloped or banked
-- corner: circuits with hills use 5-stud samples instead of 6.)
----------------------------------------------------------------------------
TrackLayout.RoadFold = 0.05 -- studs
TrackLayout.RoadSplitAcross = 4 -- most strips across the road
TrackLayout.RoadSplitAlong = 6 -- most rows along it

local function quadCorners(track: Track, i: number): (vector, vector, vector, vector)
	local a = track.samples[i]
	local b = track.samples[wrap(i + 1, track.n)]
	local ha, hb = a.width / 2, b.width / 2
	return a.pos - a.right * ha, a.pos + a.right * ha, b.pos - b.right * hb, b.pos + b.right * hb
end

-- The triangles of road quad i..i+1 split `across` x `along` (neighbouring
-- quads share the straight cross-section between them, so no cracks).
function TrackLayout.roadTriangles(track: Track, i: number, across: number, along: number): { { vector } }
	local l0, r0, l1, r1 = quadCorners(track, i)
	local function at(u: number, v: number): vector
		local a = l0 + (r0 - l0) * u
		local b = l1 + (r1 - l1) * u
		return a + (b - a) * v
	end
	local out: { { vector } } = {}
	for p = 0, across - 1 do
		for q = 0, along - 1 do
			local p00, p10 = at(p / across, q / along), at((p + 1) / across, q / along)
			local p01, p11 = at(p / across, (q + 1) / along), at((p + 1) / across, (q + 1) / along)
			table.insert(out, { p00, p10, p11 })
			table.insert(out, { p00, p11, p01 })
		end
	end
	return out
end

-- The biggest fold among pieces from roadTriangles: how far each piece's
-- fourth corner is off the plane of its first triangle.
function TrackLayout.roadFold(tris: { { vector } }): number
	local worst = 0
	for k = 1, #tris, 2 do
		local a, b, c, d = tris[k][1], tris[k][2], tris[k][3], tris[k + 1][3]
		local nrm = vector.cross(b - a, c - a)
		if vector.magnitude(nrm) > 1e-9 then
			worst = math.max(worst, math.abs(vector.dot(d - a, vector.normalize(nrm))))
		end
	end
	return worst
end

-- How the road quad i..i+1 is split: strips across, rows along (the fewest
-- pieces that leave no fold over RoadFold, within the limits).
function TrackLayout.roadSplit(track: Track, i: number): (number, number)
	local fold = TrackLayout.roadFold(TrackLayout.roadTriangles(track, i, 1, 1))
	if fold <= TrackLayout.RoadFold then
		return 1, 1
	end
	local need = math.ceil(fold / TrackLayout.RoadFold - 1e-9)
	local across = math.min(need, TrackLayout.RoadSplitAcross)
	local along = math.min(math.ceil(need / across), TrackLayout.RoadSplitAlong)
	-- the estimate assumes one normal for the whole quad; check the pieces
	while TrackLayout.roadFold(TrackLayout.roadTriangles(track, i, across, along)) > TrackLayout.RoadFold do
		if along < TrackLayout.RoadSplitAlong then
			along += 1
		elseif across < TrackLayout.RoadSplitAcross then
			across += 1
		else
			break
		end
	end
	return across, along
end

-- Grid slot pose on the track (position on the road surface, forward, up).
function TrackLayout.gridSlot(track: Track, slotIndex: number, cfg: { GridFirstRowBack: number, GridRowSpacing: number, GridLateral: number, GridStagger: number }): (vector, vector, vector)
	local k = slotIndex - 1
	local row = k // 2
	local leftSide = k % 2 == 0
	local back = cfg.GridFirstRowBack + row * cfg.GridRowSpacing + (if leftSide then 0 else cfg.GridStagger)
	local lateral = if leftSide then -cfg.GridLateral else cfg.GridLateral
	local steps = back / track.spacing
	local i0 = math.floor(steps)
	local f = steps - i0
	local a = track.samples[wrap(1 - i0, track.n)]
	local b = track.samples[wrap(1 - i0 - 1, track.n)]
	local pos = a.pos + (b.pos - a.pos) * f
	local right = vector.normalize(a.right + (b.right - a.right) * f)
	local fwd = vector.normalize(a.fwd + (b.fwd - a.fwd) * f)
	local up = vector.cross(right, fwd)
	return pos + right * lateral, fwd, up
end

TrackLayout.UP = UP
return TrackLayout
