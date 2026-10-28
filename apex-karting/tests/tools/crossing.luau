-- Prints a circuit's crossings (TrackLayout.crossings): the bridge span,
-- headroom under it and the retaining walls along the road underneath.
--   luau tests/tools/crossing.luau -a Suzuka
local TrackMath = require("../../src/shared/TrackMath")
local TrackLayout = require("../../src/shared/TrackLayout")
local TrackData = require("../../src/shared/TrackData")
local spec = TrackData.get(...)
local track = TrackMath.build(spec)
local grid = TrackLayout.grid(track)
local zones = TrackLayout.zones(track, grid)
local g = TrackLayout.ground(track, grid, zones)
local list = TrackLayout.crossings(g)
print(string.format("# %s: %d crossing(s)", spec.Name, #list))
for _, c in list do
	local o, u = track.samples[c.over], track.samples[c.under]
	print(string.format("over %d (y %.1f) under %d (y %.1f): road-to-road %.1f, under the girder %.1f", c.over, o.pos.y, c.under, u.pos.y, o.pos.y - u.pos.y, o.pos.y - TrackLayout.RoadThickness - TrackLayout.GirderDepth - u.pos.y))
	print("deck", table.concat(c.deck, " "))
	local t = {}
	for i in c.trenchSet do
		table.insert(t, i)
	end
	table.sort(t)
	print("trench", table.concat(t, " "))
	for _, w in c.walls do
		print(string.format("wall %d side %d at %.1f,%.1f bottom %.1f top %.1f", w.i, w.side, w.p.x, w.p.z, w.bottom, w.top))
	end
end
