-- Boots the game in the mock runtime with one driver and prints every part
-- (for the preview renderer in tests/tools/render.py).
-- Run from the project root:  luau tests/tools/dump_world.luau [-a TrackId] > world.txt
local Game = require("../lib/game")
-- a practice server on the circuit asked for (public servers are lobbies)
local want = ...
local G = Game.boot({ reserved = { mode = "practice", track = want } })
local A = G.addPlayer("Alice", 101)
G.startClient(A, Game.ClientSpec)
G.run(3)
-- zoom all the way into the cockpit so the preview can show the driver's view
for _ = 1, 12 do
	G.wheel(1)
	G.run(0.05)
end
G.run(1)
assert(#G.errors == 0, G.errors[1])
local cam = G.workspace.CurrentCamera
local ccf = cam.CFrame
local look = ccf.LookVector
local up = ccf.UpVector
print(string.format("CAMERA|%.4f,%.4f,%.4f|%.5f,%.5f,%.5f|%.5f,%.5f,%.5f|%.2f", ccf.X, ccf.Y, ccf.Z, look.X, look.Y, look.Z, up.X, up.Y, up.Z, cam.FieldOfView))
for p in G.partRegistry do
	if (p._props.Transparency or 0) >= 1 or (p._props.LocalTransparencyModifier or 0) >= 1 then
		continue
	end
	local cf = G.partCF(p)
	local s = p._props.Size or { X = 4, Y = 1, Z = 2 }
	local c = p._props.Color or { R = 0.64, G = 0.64, B = 0.64 }
	local shape = p._props.Shape and p._props.Shape.Name or "Block"
	-- a sphere SpecialMesh turns the part into an ellipsoid filling its size
	for _, ch in p._children do
		if ch._class == "SpecialMesh" and ch._props.MeshType and ch._props.MeshType.Name == "Sphere" then
			shape = "Ellipsoid"
			local sc = ch._props.Scale
			if sc then
				s = { X = s.X * sc.X, Y = s.Y * sc.Y, Z = s.Z * sc.Z }
			end
		end
	end
	local m = cf.m
	print(table.concat({
		p:GetFullName(),
		p._class,
		shape,
		string.format("%.4f,%.4f,%.4f", s.X, s.Y, s.Z),
		string.format("%.4f,%.4f,%.4f", cf.px, cf.py, cf.pz),
		string.format("%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f", m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]),
		string.format("%.3f,%.3f,%.3f", c.R, c.G, c.B),
		string.format("%.2f", p._props.Transparency or 0),
		p._props.Material and p._props.Material.Name or "Plastic",
	}, "|"))
end
