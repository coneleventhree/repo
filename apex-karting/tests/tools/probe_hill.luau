-- Boots a practice server on a hilly circuit and probes the ground beside the
-- raised road like the e2e test, printing every big step (holes, cliffs).
-- Run from the project root:  luau tests/tools/probe_hill.luau [-a Suzuka]
local Game = require("../lib/game")
-- a practice server on the circuit asked for (public servers are lobbies)
local want = (...) or "Hillside"
local G = Game.boot({ reserved = { mode = "practice", track = want } })
local A = G.addPlayer("Alice", 101)
G.startClient(A, Game.ClientSpec)
G.run(3)
assert(G.workspace:GetAttribute("Track") == want, "not on " .. want)
local ctx = { name = "probe" }
local TrackMath = Game.sharedModule(G, ctx, "TrackMath")
local TrackData = Game.sharedModule(G, ctx, "TrackData")
local track = TrackMath.build(TrackData.get(want))
local D = require("../mock/datatypes")
local Vector3 = D.Vector3
local params = D.RaycastParams.new()
params.FilterType = G.Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { G.workspace.Circuit.Track }
local down = Vector3.new(0, -200, 0)
local found = 0
for i = 1, track.n, 2 do
	local smp = track.samples[i]
	if smp.pos.y > 3 then
		for _, side in { -1, 1 } do
			local lastY, lastName = nil, nil
			for d = 0.6, smp.width / 2 + 50, 1.7 do
				local r = Vector3.new(smp.right.x, 0, smp.right.z).Unit
				local p = Vector3.new(smp.pos.x, smp.pos.y, smp.pos.z) + r * (side * d) + Vector3.new(smp.fwd.x, smp.fwd.y, smp.fwd.z) * 0.9
				local hit = G.workspace:Raycast(Vector3.new(p.X, smp.pos.y + 60, p.Z), down, params)
				if hit then
					local name = hit.Instance:GetFullName()
					if lastY and math.abs(hit.Position.Y - lastY) > 2.5 then
						found += 1
						if found <= 400 then
							print(string.format("i=%d side=%d d=%.1f at (%.0f, %.0f): %.1f -> %.1f  %s -> %s", i, side, d, p.X, p.Z, lastY, hit.Position.Y, lastName, name))
						end
					end
					lastY, lastName = hit.Position.Y, name
				end
			end
		end
	end
end
print("big steps", found)
