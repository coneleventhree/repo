--!strict
-- Builds every drivable surface of the circuit: the asphalt, kerbs,
-- painted run-off, gravel, turf verges, the lawn, painted lines, the start/
-- finish line and grid boxes. Each surface part carries a "Surface"
-- attribute (see Config.Surfaces) that sets the tyre grip on it.
-- Straight stretches are merged into long quads to keep the part count low.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local TrackLayout = require(Shared:WaitForChild("TrackLayout"))
local Config = require(Shared:WaitForChild("Config"))
local Build = require(script.Parent:WaitForChild("Build"))

local TrackBuilder = {}

local v3 = Build.v3
local UPV = Vector3.new(0, 1, 0)

local COLORS = {
	road = Color3.fromRGB(56, 56, 60),
	kerbRed = Color3.fromRGB(200, 30, 34),
	kerbWhite = Color3.fromRGB(238, 238, 238),
	runRed = Color3.fromRGB(178, 40, 44),
	runBlue = Color3.fromRGB(34, 74, 160),
	gravel = Color3.fromRGB(214, 196, 150),
	turf = Color3.fromRGB(46, 128, 60),
	lawnA = Color3.fromRGB(84, 150, 70),
	lawnB = Color3.fromRGB(74, 138, 62),
	slope = Color3.fromRGB(80, 142, 66),
	line = Color3.fromRGB(242, 242, 242),
	pitLane = Color3.fromRGB(66, 66, 72),
}

local function surface(p: Instance, name: string)
	p:SetAttribute("Surface", name)
end

-- Quads between consecutive samples along a band. `inner(i)`/`outer(i)` give
-- the band's two edge points at sample i (or nil to skip), `style(i)` returns
-- the props for the quad i..i+1 plus a merge key. Collinear quads with the
-- same key are merged into one. `tol`: how far (studs) a merged run's edges
-- may stray from the samples' edge points (default 0.03).
type Style = { key: string, props: { [string]: any }, surface: string?, height: number? }
local function ribbon(parent: Instance, n: number, inner: (number) -> Vector3?, outer: (number) -> Vector3?, style: (number) -> Style?, thickness: number, tol: number?)
	local straight = tol or 0.03
	local i = 1
	local done = 0
	local wrapI = function(k: number): number
		return TrackMath.wrap(k, n)
	end
	while done < n do
		local st = style(wrapI(i))
		local a0, b0 = inner(wrapI(i)), outer(wrapI(i))
		if not (st and a0 and b0) then
			i += 1
			done += 1
			continue
		end
		-- extend the run while the points stay on one straight line
		local j = i + 1
		local count = 1
		while done + count < n do
			local nxt = style(wrapI(j))
			local a2, b2 = inner(wrapI(j + 1)), outer(wrapI(j + 1))
			if not (nxt and nxt.key == st.key and a2 and b2) then
				break
			end
			local ok = true
			local la, lb = a2 - a0, b2 - b0
			local a1n, b1n = a2, b2
			for k = i + 1, j do
				local ak, bk = inner(wrapI(k)), outer(wrapI(k))
				if not (ak and bk) then
					ok = false
					break
				end
				local da = (ak - a0) - la * math.clamp((ak - a0):Dot(la) / math.max(la:Dot(la), 1e-9), 0, 1)
				local db = (bk - b0) - lb * math.clamp((bk - b0):Dot(lb) / math.max(lb:Dot(lb), 1e-9), 0, 1)
				if da.Magnitude > straight or db.Magnitude > straight then
					ok = false
					break
				end
				-- and flat: both edges straight is not enough where the road
				-- twists (banking winding on), the strip must not warp
				local mid = (ak + bk) / 2
				local normal = (b1n - a0):Cross(a1n - a0)
				if normal.Magnitude > 1e-6 and math.abs((mid - a0):Dot(normal.Unit)) > 0.002 then
					ok = false
					break
				end
			end
			if not ok then
				break
			end
			j += 1
			count += 1
		end
		local a1, b1 = inner(wrapI(j)), outer(wrapI(j))
		if a1 and b1 then
			local lift = Vector3.new(0, st.height or 0, 0)
			local w1, w2 = Build.triangle(parent, a0 + lift, b0 + lift, b1 + lift, thickness, UPV, st.props)
			local w3, w4 = Build.triangle(parent, a0 + lift, b1 + lift, a1 + lift, thickness, UPV, st.props)
			if st.surface then
				for _, w in { w1, w2, w3, w4 } do
					if w then
						surface(w, st.surface)
					end
				end
			end
		end
		done += count
		i = j
	end
end
TrackBuilder.ribbon = ribbon

function TrackBuilder.build(track: TrackMath.Track, zones: TrackLayout.Zones, parent: Instance): Folder
	local root = Build.folder(parent, "Track")
	local n = track.n
	local samples = track.samples

	local function edge(i: number, side: number, beyond: number): Vector3
		local smp = samples[i]
		local base = smp.pos + smp.right * (side * smp.width / 2)
		return v3(base + TrackLayout.outward(smp, side) * beyond)
	end

	-- on a raised road a crack between two neighbouring surfaces is a hole
	-- down to the lawn: merged runs keep to the sample edges much more tightly
	local raised = false
	for _, smp in samples do
		raised = raised or smp.pos.y > 0.3
	end
	local tol = if raised then 0.002 else nil

	-- Asphalt
	local road = Build.folder(root, "Road")
	local roadStyle: Style = {
		key = "road",
		props = { Material = Enum.Material.Asphalt, Color = COLORS.road, CastShadow = false },
		surface = "Asphalt",
	}
	-- twisted quads (a corner that climbs, banking winding on) are split into
	-- smaller pieces so the surface has no folds to rattle over; the rest go
	-- through the ribbon (straight runs merged)
	local split: { [number]: boolean } = {}
	for i = 1, n do
		local across, along = TrackLayout.roadSplit(track, i)
		if across * along > 1 then
			split[i] = true
			for _, t in TrackLayout.roadTriangles(track, i, across, along) do
				local w1, w2 = Build.triangle(road, v3(t[1]), v3(t[2]), v3(t[3]), TrackLayout.RoadThickness, UPV, roadStyle.props)
				for _, w in { w1, w2 } do
					if w then
						surface(w, "Asphalt")
					end
				end
			end
		end
	end
	ribbon(road, n, function(i)
		return edge(i, -1, 0)
	end, function(i)
		return edge(i, 1, 0)
	end, function(i)
		return if split[i] then nil else roadStyle
	end, TrackLayout.RoadThickness, tol)

	-- Bands beside the road on both sides
	local bands = Build.folder(root, "Bands")
	for _, side in { -1, 1 } do
		local function b(i: number): TrackLayout.Bands
			return if side < 0 then zones[i].left else zones[i].right
		end
		-- on a raised road, a turf base under all the bands, from the road edge
		-- out to the band end (where the embankment starts): the kerbs, run-off
		-- and gravel taper in and out between samples and leave thin slivers
		-- uncovered, harmless on the flat (the lawn is 0.1 below) but holes
		-- when the road is up on a hill
		-- (only where something tapers: a plain turf verge on both samples
		-- already covers the whole band, and the base would double the parts)
		local function plainTurf(i: number): boolean
			local bi = b(i)
			return bi.kerb <= 0 and bi.runoff <= bi.kerb + 0.5 and bi.gravelTo <= bi.gravelFrom and bi.turf > 0.3
		end
		if raised then
			ribbon(bands, n, function(i)
				return edge(i, side, 0)
			end, function(i)
				return edge(i, side, TrackLayout.bandEnd(b(i)))
			end, function(i)
				if plainTurf(i) and plainTurf(TrackMath.wrap(i + 1, n)) then
					return nil
				end
				return {
					key = "base",
					props = { Name = "TurfBase", Material = Enum.Material.Fabric, Color = COLORS.turf, CastShadow = false },
					surface = "Turf",
					-- well under the bands (no z-fighting from afar)
					height = -0.12,
				}
			end, 0.5, tol)
		end
		-- kerbs: a low crown, red/white per sample
		local kerbFolder = Build.folder(bands, if side < 0 then "KerbsLeft" else "KerbsRight")
		local kw, kh = TrackLayout.KerbWidth, TrackLayout.KerbHeight
		for i = 1, n do
			local j = TrackMath.wrap(i + 1, n)
			if b(i).kerb > 0 and b(j).kerb > 0 then
				local color = if i % 2 == 0 then COLORS.kerbRed else COLORS.kerbWhite
				local props = { Material = Enum.Material.SmoothPlastic, Color = color, CastShadow = false }
				local e0, e1 = edge(i, side, 0), edge(j, side, 0)
				local c0, c1 = edge(i, side, kw * 0.55) + Vector3.new(0, kh, 0), edge(j, side, kw * 0.55) + Vector3.new(0, kh, 0)
				local o0, o1 = edge(i, side, kw), edge(j, side, kw)
				for _, tri in { { e0, c0, c1 }, { e0, c1, e1 }, { c0, o0, o1 }, { c0, o1, c1 } } do
					local w1, w2 = Build.triangle(kerbFolder, tri[1], tri[2], tri[3], 0.5, UPV, props)
					for _, w in { w1, w2 } do
						if w then
							surface(w, "Kerb")
						end
					end
				end
			end
		end
		-- painted run-off: blue/red bands, alternating per sample
		ribbon(bands, n, function(i)
			local bi = b(i)
			return if bi.runoff > bi.kerb + 0.5 then edge(i, side, bi.kerb) else nil
		end, function(i)
			local bi = b(i)
			return if bi.runoff > bi.kerb + 0.5 then edge(i, side, bi.runoff) else nil
		end, function(i)
			return {
				key = "run" .. (i % 2),
				props = { Material = Enum.Material.Asphalt, Color = if i % 2 == 0 then COLORS.runRed else COLORS.runBlue, CastShadow = false },
				surface = "RunOff",
				height = -0.005,
			}
		end, 0.5, tol)
		-- gravel trap
		local gravelStyle: Style = {
			key = "gravel",
			props = { Material = Enum.Material.Sand, Color = COLORS.gravel, CastShadow = false },
			surface = "Gravel",
			height = -0.02,
		}
		ribbon(bands, n, function(i)
			local bi = b(i)
			return if bi.gravelTo > bi.gravelFrom then edge(i, side, bi.gravelFrom) else nil
		end, function(i)
			local bi = b(i)
			return if bi.gravelTo > bi.gravelFrom then edge(i, side, bi.gravelTo) else nil
		end, function()
			return gravelStyle
		end, 0.5, tol)
		-- turf verge where nothing else covers the first metres
		local turfStyle: Style = {
			key = "turf",
			props = { Material = Enum.Material.Fabric, Color = COLORS.turf, CastShadow = false },
			surface = "Turf",
			height = -0.01,
		}
		ribbon(bands, n, function(i)
			local bi = b(i)
			local from = math.max(bi.kerb, bi.runoff, bi.gravelTo)
			return if bi.turf > from + 0.3 then edge(i, side, from) else nil
		end, function(i)
			local bi = b(i)
			local from = math.max(bi.kerb, bi.runoff, bi.gravelTo)
			return if bi.turf > from + 0.3 then edge(i, side, bi.turf) else nil
		end, function()
			return turfStyle
		end, 0.5, tol)
	end

	-- White edge lines, inset from the edge
	local paint = Build.folder(root, "Paint")
	for i = 1, n do
		local s0 = samples[i]
		local s1 = samples[TrackMath.wrap(i + 1, n)]
		for _, side in { -1, 1 } do
			local inset = 1.0
			local a = s0.pos + s0.right * (side * (s0.width / 2 - inset))
			local c = s1.pos + s1.right * (side * (s1.width / 2 - inset))
			-- lie in the (possibly banked) road surface
			Build.strip(paint, v3(a), v3(c), v3(s0.up), 0.7, { Color = COLORS.line, Material = Enum.Material.SmoothPlastic })
		end
	end

	-- Start/finish: two rows of chequered squares across the road at sample 1
	do
		local s = samples[1]
		local cells = math.floor(s.width / 2)
		local size = s.width / cells
		local finish = Build.folder(root, "StartFinish")
		for row = 0, 1 do
			for c = 0, cells - 1 do
				local lateral = -s.width / 2 + (c + 0.5) * size
				local along = (row - 0.5) * size
				local pos = s.pos + s.right * lateral + s.fwd * along + s.up * 0.035
				local p = Build.decor(finish, {
					Size = Vector3.new(size, 0.05, size),
					CFrame = CFrame.fromMatrix(v3(pos), v3(s.right), v3(s.up), v3(-s.fwd)),
					Color = if (row + c) % 2 == 0 then Color3.new(0.05, 0.05, 0.05) else COLORS.line,
					Material = Enum.Material.SmoothPlastic,
					CastShadow = false,
				})
				p.Name = "Check"
			end
		end
	end

	-- Grid boxes: a white bar in front of each slot and short side ticks
	do
		local gridFolder = Build.folder(root, "Grid")
		for slot = 1, Config.Race.MaxRacers do
			local pos, fwd, up = TrackLayout.gridSlot(track, slot, Config.Race)
			local right = vector.cross(fwd, up)
			local front = pos + fwd * 3.8
			Build.strip(gridFolder, v3(front - right * 3.2), v3(front + right * 3.2), UPV, 0.5, { Color = COLORS.line, Material = Enum.Material.SmoothPlastic })
			for _, side in { -1, 1 } do
				local a = front + right * (side * 3.2)
				Build.strip(gridFolder, v3(a), v3(a - fwd * 2.5), UPV, 0.5, { Color = COLORS.line, Material = Enum.Material.SmoothPlastic })
			end
		end
	end

	return root
end

-- Grassy embankments under the raised parts of a circuit with hills
-- (TrackLayout.skirts): from the outer edge of the bands down to the lawn.
-- Drivable (grass grip), so they live in the Track folder.
function TrackBuilder.embankments(track: TrackMath.Track, ground: TrackLayout.Ground, root: Instance): Folder?
	if not ground.raised then
		return nil
	end
	local folder = Build.folder(root, "Embankments")
	local skirts = TrackLayout.skirts(ground)
	local style: Style = {
		key = "bank",
		props = { Material = Enum.Material.Grass, Color = COLORS.slope, CastShadow = false },
		surface = "Grass",
		height = -0.04,
	}
	-- inside tight corners a fan to one hub replaces the converging strips
	local pockets = TrackLayout.pockets(ground, skirts)
	for _, side in { -1, 1 } do
		local function get(i: number): TrackLayout.Skirt?
			return if side < 0 then skirts[i].left else skirts[i].right
		end
		local skip = if side < 0 then pockets.skipLeft else pockets.skipRight
		ribbon(folder, track.n, function(i)
			local k = get(i)
			return if k then v3(k.top) else nil
		end, function(i)
			local k = get(i)
			return if k then v3(k.toe) else nil
		end, function(i)
			return if get(i) and get(TrackMath.wrap(i + 1, track.n)) and not skip[i] then style else nil
		end, 1)
	end
	local lift = Vector3.new(0, style.height or 0, 0)
	for _, tri in pockets.tris do
		local w1, w2 = Build.triangle(folder, v3(tri[1]) + lift, v3(tri[2]) + lift, v3(tri[3]) + lift, 1, UPV, style.props)
		for _, w in { w1, w2 } do
			if w then
				surface(w, "Grass")
			end
		end
	end
	return folder
end

-- Where the circuit crosses itself (TrackLayout.crossings): a concrete girder
-- under the bridge span with parapets along both sides, and retaining walls
-- along the road that passes underneath. Solid, so they live in the Track
-- folder with the rest of what the karts touch.
function TrackBuilder.crossings(track: TrackMath.Track, ground: TrackLayout.Ground, root: Instance): Folder?
	local list = TrackLayout.crossings(ground)
	if #list == 0 then
		return nil
	end
	local folder = Build.folder(root, "Crossings")
	local samples = track.samples
	local n = track.n
	local concrete = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(176, 172, 164) }
	local girderColor = Color3.fromRGB(70, 92, 128)
	for _, c in list do
		local bridge = Build.folder(folder, "Bridge")
		-- the span plus a few samples either side for the parapets
		local first, last = c.deck[1], c.deck[#c.deck]
		local PAD = 3
		for k = -PAD, (last - first) % n + PAD - 1 do
			local i = TrackMath.wrap(first + k, n)
			local j = TrackMath.wrap(i + 1, n)
			local a, b = samples[i], samples[j]
			local onDeck = c.deckSet[i] or c.deckSet[j]
			local dir = v3(b.pos - a.pos)
			local look = Vector3.new(dir.X, 0, dir.Z).Unit
			local right = look:Cross(UPV)
			local len = dir.Magnitude + 0.3
			local el = math.max(ground.edges[i].left.foot, ground.edges[j].left.foot)
			local er = math.max(ground.edges[i].right.foot, ground.edges[j].right.foot)
			local mid = v3((a.pos + b.pos) / 2)
			local roadY = math.min(a.pos.y, b.pos.y)
			local under = roadY - TrackLayout.RoadThickness - TrackLayout.GirderDepth
			local cf = CFrame.fromMatrix(Vector3.new(mid.X, 0, mid.Z), right, UPV, -look)
			if onDeck then
				local w = el + er + 2.4
				Build.part(bridge, {
					Name = "Girder",
					Size = Vector3.new(w, TrackLayout.GirderDepth, len),
					CFrame = cf * CFrame.new((er - el) / 2, under + TrackLayout.GirderDepth / 2, 0),
					Color = girderColor,
					Material = Enum.Material.Concrete,
					CastShadow = true,
				})
			end
			-- parapets: over the span they run down the girder's side too
			local top = math.max(a.pos.y, b.pos.y) + TrackLayout.ParapetHeight
			local bottom = if onDeck then under else roadY - 1
			for _, side in { -1, 1 } do
				local off = if side < 0 then -(el + 0.6) else er + 0.6
				local p = Build.part(bridge, {
					Name = "Parapet",
					Size = Vector3.new(1.2, top - bottom, len),
					CFrame = cf * CFrame.new(off, (top + bottom) / 2, 0),
					Color = concrete.Color,
					Material = concrete.Material,
				})
				p:SetAttribute("Surface", "Concrete")
			end
		end
		-- retaining walls: one sloped-top panel between each pair of neighbours
		local trench = Build.folder(folder, "Trench")
		local at: { [number]: { [number]: TrackLayout.Wall } } = { [-1] = {}, [1] = {} }
		for _, w in c.walls do
			at[w.side][w.i] = w
		end
		for _, side in { -1, 1 } do
			for i, w in at[side] do
				local nx = at[side][TrackMath.wrap(i + 1, n)]
				if not nx then
					continue
				end
				local a0 = Vector3.new(w.p.x, w.bottom, w.p.z)
				local a1 = Vector3.new(w.p.x, w.top, w.p.z)
				local b0 = Vector3.new(nx.p.x, nx.bottom, nx.p.z)
				local b1 = Vector3.new(nx.p.x, nx.top, nx.p.z)
				local toRoad = -v3(w.dir)
				Build.triangle(trench, a0, a1, b1, TrackLayout.TrenchWall, toRoad, { Name = "Wall", Material = concrete.Material, Color = concrete.Color })
				Build.triangle(trench, a0, b1, b0, TrackLayout.TrenchWall, toRoad, { Name = "Wall", Material = concrete.Material, Color = concrete.Color })
			end
		end
	end
	return folder
end

-- Striped lawn over the whole facility, the pit lane and the paddock floor.
-- Lives in the Track folder so the wheels find grip on it too.
function TrackBuilder.ground(track: TrackMath.Track, root: Instance)
	local folder = Build.folder(root, "Ground")
	local f = TrackLayout.facility(track)
	local stripe = 40
	local z = f.minZ
	local k = 0
	while z < f.maxZ do
		local w = math.min(stripe, f.maxZ - z)
		local p = Build.part(folder, {
			Name = "Lawn",
			Size = Vector3.new(f.maxX - f.minX, 1, w),
			CFrame = CFrame.new((f.minX + f.maxX) / 2, TrackLayout.LawnY - 0.5, z + w / 2),
			Color = if k % 2 == 0 then COLORS.lawnA else COLORS.lawnB,
			Material = Enum.Material.Grass,
			CastShadow = false,
		})
		surface(p, "Grass")
		z += w
		k += 1
	end
	local P = TrackLayout.paddock(track)
	local lane = P.pitLane
	local pl = Build.part(folder, {
		Name = "PitLane",
		Size = Vector3.new(lane.maxX - lane.minX, 1, lane.maxZ - lane.minZ),
		CFrame = CFrame.new((lane.minX + lane.maxX) / 2, -0.5, (lane.minZ + lane.maxZ) / 2),
		Color = COLORS.pitLane,
		Material = Enum.Material.Asphalt,
		CastShadow = false,
	})
	surface(pl, "PitLane")
	local plaza = P.plaza
	local pz = Build.part(folder, {
		Name = "Paddock",
		Size = Vector3.new(plaza.maxX - plaza.minX, 1, plaza.maxZ - plaza.minZ),
		CFrame = CFrame.new((plaza.minX + plaza.maxX) / 2, -0.5, (plaza.minZ + plaza.maxZ) / 2),
		Color = Color3.fromRGB(150, 150, 152),
		Material = Enum.Material.Concrete,
		CastShadow = false,
	})
	surface(pz, "Concrete")
	-- pit lane markings: speed-limit line along the wall side and a box per garage
	local paint = folder
	local lineProps = { Color = COLORS.line, Material = Enum.Material.SmoothPlastic }
	-- (the garage side of the lane: its far edge from the main straight)
	local back = if P.side < 0 then lane.minZ else lane.maxZ
	local inward = -P.side
	local zLine = back + inward * 1.2
	Build.strip(paint, Vector3.new(lane.minX + 2, 0, zLine), Vector3.new(lane.maxX - 2, 0, zLine), UPV, 0.5, lineProps)
	local g = P.garages
	local bays = math.max(1, math.floor((g.maxX - g.minX) / 28))
	local bayW = (g.maxX - g.minX) / bays
	for b = 0, bays do
		local x = g.minX + b * bayW
		Build.strip(paint, Vector3.new(x, 0, back + inward * 1.5), Vector3.new(x, 0, back + inward * 9), UPV, 0.4, lineProps)
	end
	return folder
end

return TrackBuilder
