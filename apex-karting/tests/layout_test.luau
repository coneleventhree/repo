-- Layout tests for every circuit: run-off bands never reach another part
-- of the track, barriers/stands/posts keep clear of the racing surface, the
-- pits sit beside the main straight, grid slots are on the road.
-- Run from the project root:  luau tests/layout_test.luau
local TrackMath = require("../src/shared/TrackMath")
local TrackData = require("../src/shared/TrackData")
local TrackLayout = require("../src/shared/TrackLayout")
local Config = require("../src/shared/Config")

local pass, total = 0, 0
local function check(ok: boolean, label: string)
	total += 1
	if ok then
		pass += 1
	end
	print(string.format("%-4s %s", if ok then "PASS" else "FAIL", label))
	return ok
end

for _, trackId in TrackData.Order do
	local spec = TrackData.get(trackId)
	print(string.format("== %s ==", spec.Name))
	local track = TrackMath.build(spec)
	local grid = TrackLayout.grid(track)
	local zones = TrackLayout.zones(track, grid)

	-- flat unless the circuit asks for hills (y) or banking
	local hilly, banked = false, false
	for _, seg in spec.Segments do
		hilly = hilly or seg.y ~= nil or seg.bank ~= nil
		banked = banked or seg.bank ~= nil
	end
	local maxY, minY, maxBank, maxGrade = 0, 0, 0, 0
	for i, smp in track.samples do
		maxY = math.max(maxY, smp.pos.y)
		minY = math.min(minY, smp.pos.y)
		maxBank = math.max(maxBank, math.abs(smp.bank))
		local nxt = track.samples[TrackMath.wrap(i + 1, track.n)].pos
		local run = math.sqrt((nxt.x - smp.pos.x) ^ 2 + (nxt.z - smp.pos.z) ^ 2)
		maxGrade = math.max(maxGrade, math.abs(nxt.y - smp.pos.y) / run)
	end
	if not hilly then
		check(maxY < 1e-6 and minY > -1e-6 and maxBank < 1e-6, string.format("track is flat (max height %.6f, max bank %.6f)", maxY, maxBank))
	else
		check(maxY > 20 and minY > -0.01, string.format("hills: road from %.2f up to %.1f studs (%.1f m), never below the lawn", minY, maxY, maxY * Config.StudMeters))
		check(maxGrade < 0.12, string.format("steepest grade %.1f %%", maxGrade * 100))
		if banked then
			check(maxBank > 10 and maxBank <= 16, string.format("banked corners up to %.1f deg", maxBank))
		end
		-- the grid, the start line and the pits stay level
		local level = true
		for slot = 1, Config.Race.MaxRacers do
			local pos, _, up = TrackLayout.gridSlot(track, slot, Config.Race)
			level = level and math.abs(pos.y) < 0.01 and up.y > 0.9999
		end
		local s1 = track.samples[1]
		check(level and math.abs(s1.pos.y) < 0.01, "grid and start line are level")
		-- embankments: a strip under every raised edge, all running downhill,
		-- none reaching the fence or another road
		local ground = TrackLayout.ground(track, grid, zones)
		local skirts = TrackLayout.skirts(ground)
		local f = TrackLayout.facility(track)
		local raisedEdges, open, steepest, outside, strips = 0, 0, 0, 0, 0
		for i = 1, track.n do
			for _, side in { -1, 1 } do
				local e = if side < 0 then ground.edges[i].left else ground.edges[i].right
				local k = if side < 0 then skirts[i].left else skirts[i].right
				-- (a bridge span stands on its girder, not on an embankment)
				if e.top.y > 1 and not TrackLayout.nearCrossing(ground, i, 0) then
					raisedEdges += 1
					-- a strip down from the edge, or another road's bands right
					-- there at about the same height
					local p = e.top + e.dir * 2
					if not k and TrackLayout.groundY(ground, p.x, p.z, i, 15) < e.top.y - 2 then
						open += 1
					end
				end
				if k then
					strips += 1
					local run = math.sqrt((k.toe.x - k.top.x) ^ 2 + (k.toe.z - k.top.z) ^ 2)
					steepest = math.max(steepest, math.abs(k.toe.y - k.top.y) / math.max(run, 1e-3))
					if k.toe.x < f.minX + 4 or k.toe.x > f.maxX - 4 or k.toe.z < f.minZ + 4 or k.toe.z > f.maxZ - 4 then
						outside += 1
					end
				end
			end
		end
		check(raisedEdges > 200 and open == 0, string.format("ground under every raised edge (%d edges, %d strips, %d open)", raisedEdges, strips, open))
		check(steepest < 1, string.format("embankments no steeper than 45 deg (steepest 1 in %.1f)", 1 / math.max(steepest, 1e-6)))
		check(outside == 0, string.format("embankments stay inside the fence (%d outside)", outside))
		-- banking lowers the inside edge: it must stay above the lawn
		local lowest = math.huge
		for i = 1, track.n do
			lowest = math.min(lowest, ground.edges[i].left.top.y, ground.edges[i].right.top.y)
		end
		check(lowest > -0.05, string.format("every road and band edge above the lawn (lowest %.2f)", lowest))
	end

	-- distance from a point to the nearest road edge, ignoring samples near `around`
	local function clearance(x: number, z: number, around: number?, skip: number?): number
		local i, d = TrackLayout.nearest(grid, x, z, 400, around, skip)
		if not i then
			return math.huge
		end
		return d - track.samples[i].width / 2
	end

	-- bands never reach another part of the circuit (where one crosses
	-- over the other the two overlap by design)
	local layoutGround = TrackLayout.ground(track, grid, zones)
	local worstBand = math.huge
	local runoffs, gravels = 0, 0
	for i, smp in track.samples do
		for _, side in { -1, 1 } do
			if TrackLayout.nearCrossing(layoutGround, i, 2) then
				continue
			end
			local b = if side < 0 then zones[i].left else zones[i].right
			local e = TrackLayout.bandEnd(b)
			if b.runoff > b.kerb + 1 then
				runoffs += 1
			end
			if b.gravelTo > b.gravelFrom then
				gravels += 1
			end
			local p = smp.pos + smp.right * (side * smp.width / 2) + TrackLayout.outward(smp, side) * e
			worstBand = math.min(worstBand, clearance(p.x, p.z, i, 25))
		end
	end
	check(worstBand > 3, string.format("run-off/gravel/turf stay %.1f studs clear of other track", worstBand))
	check(runoffs > 40, string.format("painted run-off outside tight corners (%d sample sides)", runoffs))
	check(gravels > 10, string.format("gravel trap at the hairpin (%d sample sides)", gravels))

	-- a figure of eight: the bridge and the road under it
	local crossings = TrackLayout.crossings(layoutGround)
	if spec.Id == "Suzuka" then
		check(#crossings == 1, string.format("one crossing (%d)", #crossings))
	end
	for _, c in crossings do
		local o, u = track.samples[c.over], track.samples[c.under]
		local headroom = o.pos.y - TrackLayout.RoadThickness - TrackLayout.GirderDepth - u.pos.y
		check(headroom >= 10, string.format("crossing: %.1f studs from the lower road up to the girder", headroom))
		-- the lowest point of the girder over the whole lower road under it
		local lowest = math.huge
		for _, k in c.deck do
			local smp = track.samples[k]
			for t = -smp.width / 2, smp.width / 2, 2 do
				local q = smp.pos + smp.right * t
				local idx = TrackMath.nearest(track, q - vector.create(0, 12, 0))
				local under = track.samples[idx]
				if not c.deckSet[idx] and math.abs(vector.dot(q - under.pos, under.right)) < under.width / 2 then
					lowest = math.min(lowest, q.y - TrackLayout.RoadThickness - TrackLayout.GirderDepth - under.pos.y)
				end
			end
		end
		check(lowest >= 9.5, string.format("crossing: at least %.1f studs of headroom anywhere under the bridge", lowest))
		local span = #c.deck * track.spacing
		check(span >= 30 and span <= 90, string.format("crossing: bridge span %.0f studs (%d samples)", span, #c.deck))
		-- walls on both sides of the lower road right under the bridge, never
		-- poking up through the deck
		local sides, through = { [-1] = 0, [1] = 0 }, 0
		for _, w in c.walls do
			local sep = math.abs(w.i - c.under)
			if math.min(sep, track.n - sep) <= 2 then
				sides[w.side] += 1
			end
			for _, k in c.deck do
				local smp = track.samples[k]
				local rel = w.p - smp.pos
				local along = math.abs(rel.x * smp.fwd.x + rel.z * smp.fwd.z)
				local lat = math.abs(rel.x * smp.right.x + rel.z * smp.right.z)
				if along < track.spacing * 0.5 and lat < smp.width / 2 and w.top > smp.pos.y - TrackLayout.RoadThickness then
					through += 1
				end
			end
		end
		check(sides[-1] >= 3 and sides[1] >= 3, string.format("crossing: retaining walls both sides under the bridge (%d / %d)", sides[-1], sides[1]))
		check(through == 0, string.format("crossing: no wall pokes through the deck (%d)", through))
		-- no embankment strip starts from the bridge over the lower road
		local skirts = TrackLayout.skirts(layoutGround)
		local overRoad = 0
		for _, k in c.deck do
			for _, side in { -1, 1 } do
				local sk = if side < 0 then skirts[k].left else skirts[k].right
				if sk then
					local idx = TrackMath.nearest(track, sk.top - vector.create(0, 12, 0))
					local under = track.samples[idx]
					local lat = math.abs(vector.dot(sk.top - under.pos, under.right))
					if not c.deckSet[idx] and lat < under.width / 2 then
						overRoad += 1
					end
				end
			end
		end
		check(overRoad == 0, string.format("crossing: no embankment hangs over the lower road (%d)", overRoad))
		-- each level finds its own road (3D nearest sample)
		local onLow = TrackMath.nearest(track, u.pos + vector.create(0, 1, 0))
		local onHigh = TrackMath.nearest(track, o.pos + vector.create(0, 1, 0))
		check(onLow == c.under and onHigh == c.over, string.format("crossing: a kart under the bridge is on sample %d (lower road %d), on it %d (%d)", onLow, c.under, onHigh, c.over))
	end

	-- the road surface: no fold left along a piece's diagonal (they rattled
	-- the karts on the hills); measured on the pieces the game builds
	local worstFold, pieces = 0, 0
	for i = 1, track.n do
		local across, along = TrackLayout.roadSplit(track, i)
		local tris = TrackLayout.roadTriangles(track, i, across, along)
		pieces += #tris / 2
		worstFold = math.max(worstFold, TrackLayout.roadFold(tris))
	end
	check(worstFold <= TrackLayout.RoadFold + 1e-6, string.format("road surface: largest fold %.3f studs (%d pieces for %d samples)", worstFold, pieces, track.n))

	-- barriers clear of every road
	local barriers = TrackLayout.barriers(track, grid, zones)
	local minClear = math.huge
	local tyreLines, walls = 0, 0
	for _, bar in barriers do
		if bar.kind == "tyres" then
			tyreLines += 1
		else
			walls += 1
		end
		for k = 1, #bar.points - 1 do
			local a, b = bar.points[k], bar.points[k + 1]
			for t = 0, 1, 0.25 do
				local p = a + (b - a) * t
				minClear = math.min(minClear, clearance(p.x, p.z))
			end
		end
	end
	check(tyreLines >= 4, string.format("tyre walls placed (%d lines, %d concrete walls)", tyreLines, walls))
	check(minClear > 10, string.format("barriers keep %.1f studs from the road edge", minClear))

	-- pits: pit wall between the main straight and the pit lane; buildings clear
	local P = TrackLayout.paddock(track)
	local wallZ = P.wall[1].z
	check(#P.wall > 20 and wallZ < -P.halfWidth and P.pitLane.maxZ <= wallZ, string.format("pit wall at z=%.0f between straight (edge %.0f) and pit lane (%.0f..%.0f)", wallZ, -P.halfWidth, P.pitLane.minZ, P.pitLane.maxZ))
	local function rectClear(r: TrackLayout.Rect): number
		local worst = math.huge
		for x = r.minX, r.maxX, 8 do
			for z = r.minZ, r.maxZ, 8 do
				worst = math.min(worst, clearance(x, z))
			end
		end
		return worst
	end
	check(rectClear(P.pitLane) > 6, string.format("pit lane clear of the track (%.1f)", rectClear(P.pitLane)))
	check(rectClear(P.garages) > 20 and rectClear(P.plaza) > 40, "garages and paddock clear of the track")

	-- grandstands and marshal posts
	local stands = TrackLayout.stands(track, grid, zones, spec.Segments)
	local standClear = math.huge
	for _, st in stands do
		local along = vector.cross(st.facing, vector.create(0, 1, 0))
		for u = -0.5, 0.5, 0.125 do
			for v = 0, 1, 0.25 do
				local p = st.center + along * (u * st.length) - st.facing * (v * st.depth)
				standClear = math.min(standClear, clearance(p.x, p.z))
			end
		end
	end
	check(#stands >= 3, string.format("%d grandstands", #stands))
	check(standClear > 10, string.format("grandstands %.1f studs from the road", standClear))
	local posts = TrackLayout.marshals(track, grid, zones, spec.Segments)
	local postClear = math.huge
	for _, m in posts do
		postClear = math.min(postClear, clearance(m.pos.x, m.pos.z))
	end
	check(#posts >= 4 and postClear > 7, string.format("%d marshal posts, %.1f studs from the road", #posts, postClear))

	-- everything inside the facility walls
	local f = TrackLayout.facility(track)
	local inside = true
	for _, smp in track.samples do
		for _, side in { -1, 1 } do
			local p = smp.pos + smp.right * (side * (smp.width / 2 + 40))
			if p.x < f.minX or p.x > f.maxX or p.z < f.minZ or p.z > f.maxZ then
				inside = false
			end
		end
	end
	check(inside and P.plaza.minZ > f.minZ, "circuit, run-off and paddock are inside the perimeter")

	-- grid slots on the road, behind the line, facing forward
	local okSlots = true
	for slot = 1, Config.Race.MaxRacers do
		local pos, fwd = TrackLayout.gridSlot(track, slot, Config.Race)
		local idx, lateral, s = TrackMath.nearest(track, pos)
		local smp = track.samples[idx]
		local behind = TrackMath.arcDelta(track, s, 0)
		if math.abs(lateral) > smp.width / 2 - 3 or behind > -5 or vector.dot(fwd, smp.fwd) < 0.99 then
			okSlots = false
			print(string.format("    slot %d lateral %.1f behind %.1f", slot, lateral, behind))
		end
	end
	check(okSlots, string.format("%d grid slots on the road behind the line", Config.Race.MaxRacers))

	-- kerbs exist in corners and not around the start line
	local kerbs = TrackLayout.kerbs(track)
	local count, onStraight = 0, 0
	for i, k in kerbs do
		if k.left or k.right then
			count += 1
			if i <= 20 or i >= track.n - 20 then
				onStraight += 1
			end
		end
	end
	check(count > 60 and onStraight == 0, string.format("kerbs on %d samples, %d around the start line", count, onStraight))
end

print(string.format("\n%d/%d passed", pass, total))
if pass ~= total then
	error("some checks failed", 0)
end
