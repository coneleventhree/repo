-- Prints the sampled track as CSV for plotting: i,s,x,y,z,rx,ry,rz,width,bank,curv
-- luau tests/tools/dump_track.luau [-a TrackId]
local TrackMath = require("../../src/shared/TrackMath")
local TrackData = require("../../src/shared/TrackData")
local spec = TrackData.get(...)
local t = TrackMath.build(spec)
print(string.format("# n=%d length=%.1f spacing=%.3f free=%.1f,%.1f", t.n, t.length, t.spacing, t.freeLengths[1], t.freeLengths[2]))
for _, s in t.samples do
	print(string.format("%d,%.2f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.2f,%.2f,%.5f", s.i, s.s, s.pos.x, s.pos.y, s.pos.z, s.right.x, s.right.y, s.right.z, s.width, s.bank, s.curv))
end
