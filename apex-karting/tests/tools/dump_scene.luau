-- A practice server on one circuit with several karts placed where asked,
-- printed like dump_world.luau (for promo shots: thumbnails and the icon).
--   luau tests/tools/dump_scene.luau -a "Hillside 120:-6:0 116:5:3" > scene.txt
-- Each kart: sample index : studs left(-)/right(+) of the centre line : yaw
-- in degrees (+ = nose to the right), or "grid" to leave it on the grid.
local Game = require("../lib/game")

local args = ...
local words = {}
for w in string.gmatch(args or "", "[^%s]+") do
	table.insert(words, w)
end
local trackId = words[1] or "Tampines"
local G = Game.boot({ reserved = { mode = "practice", track = trackId } })
local players = {}
for k = 2, #words do
	table.insert(players, G.addPlayer("Driver" .. (k - 1), 100 + k))
end
if #players == 0 then
	table.insert(players, G.addPlayer("Driver1", 101))
end
-- one client draws every kart's wheels, steering wheel and so on
G.startClient(players[1], Game.ClientSpec)
G.run(5)

local ctx = { name = "scene" }
local TrackMath = Game.sharedModule(G, ctx, "TrackMath")
local TrackData = Game.sharedModule(G, ctx, "TrackData")
local Config = Game.sharedModule(G, ctx, "Config")
local D = require("../mock/datatypes")
local track = TrackMath.build(TrackData.get(trackId))
for k, p in players do
	local spec = words[k + 1]
	local kart = G.workspace.Karts:FindFirstChild("Kart_" .. p.UserId)
	-- "grid": leave the kart in the grid slot practice gave it
	if spec and spec ~= "grid" and kart then
		local idx, lat, yaw = string.match(spec, "^([%d.]+):([-%d.]+):([-%d.]+)$")
		local i = tonumber(idx) :: number
		local smp = track.samples[TrackMath.wrap(math.floor(i), track.n)]
		local nxt = track.samples[TrackMath.wrap(math.floor(i) + 1, track.n)]
		local f = i - math.floor(i)
		local pos = smp.pos + (nxt.pos - smp.pos) * f + smp.right * (tonumber(lat) :: number)
		local a = math.rad(tonumber(yaw) :: number)
		local fwd = smp.fwd * math.cos(a) + smp.right * math.sin(a)
		local up = smp.up
		local base = D.Vector3.new(pos.x, pos.y, pos.z) + D.Vector3.new(up.x, up.y, up.z) * (Config.Kart.RideHeight + 0.05)
		kart.PrimaryPart.Anchored = true
		kart:PivotTo(D.CFrame.lookAt(base, base + D.Vector3.new(fwd.x, fwd.y, fwd.z), D.Vector3.new(up.x, up.y, up.z)))
	end
end
G.run(0.3)
for part in G.partRegistry do
	local p = part :: any
	if (p._props.Transparency or 0) >= 1 then
		continue
	end
	local cf = G.partCF(p)
	local s = p._props.Size or { X = 4, Y = 1, Z = 2 }
	local c = p._props.Color or { R = 0.64, G = 0.64, B = 0.64 }
	local shape = p._props.Shape and p._props.Shape.Name or "Block"
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
