-- Dumps the circuit layout for plotting (bands, barriers, stands, paddock).
-- luau tests/tools/dump_layout.luau [-a TrackId]
local TrackMath = require("../../src/shared/TrackMath")
local TrackData = require("../../src/shared/TrackData")
local TrackLayout = require("../../src/shared/TrackLayout")
local spec = TrackData.get(...)
local track = TrackMath.build(spec)
local grid = TrackLayout.grid(track)
local zones = TrackLayout.zones(track, grid)
local function P(tag, ...)
	local parts = { tag }
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		table.insert(parts, if type(v) == "number" then string.format("%.2f", v) else tostring(v))
	end
	print(table.concat(parts, ","))
end
for i, smp in track.samples do
	for _, side in { -1, 1 } do
		local b = if side < 0 then zones[i].left else zones[i].right
		local dir = TrackLayout.outward(smp, side)
		local e = smp.pos + dir * (smp.width / 2)
		-- tag, x, z, dirx, dirz, kerb, runoff, gravelFrom, gravelTo, turf
		P("Z", e.x, e.z, dir.x, dir.z, b.kerb, b.runoff, b.gravelFrom, b.gravelTo, b.turf)
	end
end
for k, bar in TrackLayout.barriers(track, grid, zones) do
	for _, p in bar.points do
		P("B", k, bar.kind, p.x, p.z)
	end
end
local pad = TrackLayout.paddock(track)
for _, p in pad.wall do
	P("W", p.x, p.z)
end
for name, r in { lane = pad.pitLane, garages = pad.garages, plaza = pad.plaza, facility = TrackLayout.facility(track) } do
	P("R", name, r.minX, r.maxX, r.minZ, r.maxZ)
end
for _, st in TrackLayout.stands(track, grid, zones, spec.Segments) do
	P("S", st.name, st.center.x, st.center.z, st.facing.x, st.facing.z, st.length, st.depth)
end
local bi = TrackLayout.bridge(track, spec.Segments, spec.Bridge)
if bi then
	local s = track.samples[bi]
	P("BR", s.pos.x, s.pos.z, s.right.x, s.right.z, s.width)
end
for _, m in TrackLayout.marshals(track, grid, zones, spec.Segments) do
	P("M", m.pos.x, m.pos.z)
end
