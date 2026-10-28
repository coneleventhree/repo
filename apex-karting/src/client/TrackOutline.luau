--!strict
-- Circuit outlines drawn with thin frames (the minimap, the track cards in
-- the HUD and in the lobby menu), and each circuit's sampled track, built
-- once per client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local TrackData = require(Shared:WaitForChild("TrackData"))

local TrackOutline = {}

local ACCENT = Color3.fromRGB(255, 196, 0)
local built: { [string]: TrackMath.Track } = {}

-- The sampled track for a circuit id.
function TrackOutline.track(id: string): TrackMath.Track
	local t = built[id]
	if not t then
		t = TrackMath.build(TrackData.get(id))
		built[id] = t
	end
	return t
end

-- Draws a track outline into `frame` (size x size pixels): a dark edge, a
-- light line, and the start/finish in yellow. Every piece is named
-- "Outline" so it can be cleared. Returns the scale and corner used to map
-- world x/z onto it.
function TrackOutline.draw(frame: GuiObject, t: TrackMath.Track, size: number, pad: number, every: number, thick: number): (number, Vector2)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, s in t.samples do
		minX, maxX = math.min(minX, s.pos.x), math.max(maxX, s.pos.x)
		minZ, maxZ = math.min(minZ, s.pos.z), math.max(maxZ, s.pos.z)
	end
	local span = math.max(maxX - minX, maxZ - minZ)
	local scale = (size - 2 * pad) / span
	-- centre the shorter axis
	local origin = Vector2.new(minX - ((span - (maxX - minX)) / 2), minZ - ((span - (maxZ - minZ)) / 2))
	local function pt(x: number, z: number): Vector2
		return Vector2.new((x - origin.X) * scale + pad, (z - origin.Y) * scale + pad)
	end
	local n = t.n
	for pass = 1, 2 do
		for i = 1, n, every do
			local a = t.samples[i].pos
			local b = t.samples[TrackMath.wrap(i + every, n)].pos
			local pa, pb = pt(a.x, a.z), pt(b.x, b.z)
			local d = pb - pa
			local seg = Instance.new("Frame")
			seg.Name = "Outline"
			seg.BorderSizePixel = 0
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
			seg.Size = UDim2.fromOffset(d.Magnitude + 2, if pass == 1 then thick * 2 else thick)
			seg.Rotation = math.deg(math.atan2(d.Y, d.X))
			seg.BackgroundColor3 = if pass == 1 then Color3.fromRGB(0, 0, 0) else Color3.fromRGB(215, 218, 226)
			seg.BackgroundTransparency = if pass == 1 then 0.5 else 0.05
			seg.ZIndex = pass
			seg.Parent = frame
		end
	end
	-- start/finish marker
	local s1 = t.samples[1]
	local p = pt(s1.pos.x, s1.pos.z)
	local mark = Instance.new("Frame")
	mark.Name = "Outline"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromOffset(p.X, p.Y)
	mark.Size = UDim2.fromOffset(3, thick * 3)
	mark.BackgroundColor3 = ACCENT
	mark.BorderSizePixel = 0
	mark.Rotation = math.deg(math.atan2(s1.fwd.z, s1.fwd.x))
	mark.ZIndex = 3
	mark.Parent = frame
	return scale, origin
end

return TrackOutline
