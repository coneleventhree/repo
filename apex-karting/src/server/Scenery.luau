--!strict
-- The circuit facility around the track: lighting, start gantry with start
-- lights, pit wall, garages and race control, paddock with spawn, grandstands,
-- the sponsor bridge, barriers with catch fences, marshal posts, floodlight
-- towers, the perimeter wall and the car park outside it.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local TrackLayout = require(Shared:WaitForChild("TrackLayout"))
local Config = require(Shared:WaitForChild("Config"))
local Build = require(script.Parent:WaitForChild("Build"))

local Scenery = {}
local v3 = Build.v3

local DARK = Color3.fromRGB(30, 32, 36)
local CONCRETE = Color3.fromRGB(198, 198, 194)
local WHITE = Color3.fromRGB(240, 240, 240)
local ACCENT = Color3.fromRGB(255, 196, 0)
local RED = Color3.fromRGB(200, 34, 38)
local BLUE = Color3.fromRGB(28, 70, 160)
local FENCE = Color3.fromRGB(70, 74, 80)
local FONT = Enum.Font.GothamBlack

-- fictional sponsors only (TRACK = the circuit's own name)
local SPONSORS = { "A1 KART RACING", "GRIPLINE TYRES", "VOLT ENERGY", "SUNSET FUELS", "TRACK", "NORTHPEAK", "KESTREL OIL", "ORBIT TELECOM" }
local sponsorIndex = 0
local trackName = "A1 KART RACING"
local function nextSponsor(): string
	sponsorIndex += 1
	local s = SPONSORS[(sponsorIndex - 1) % #SPONSORS + 1]
	return if s == "TRACK" then trackName else s
end

-- Call before building a circuit's scenery.
function Scenery.begin(spec: any)
	sponsorIndex = 0
	trackName = string.upper(spec.Name)
end

local function label(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3, ppm: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppm or 20
	gui.LightInfluence = 0.6
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg
	t.BackgroundTransparency = 0
	t.TextColor3 = color
	t.Font = FONT
	t.TextScaled = true
	t.Text = text
	t.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.PaddingLeft = UDim.new(0.02, 0)
	pad.PaddingRight = UDim.new(0.02, 0)
	pad.Parent = t
end

-- Which face of a part whose CFrame looks along a->b points towards `target`.
local function faceTowards(cf: CFrame, target: Vector3): Enum.NormalId
	return if cf.RightVector:Dot(target - cf.Position) > 0 then Enum.NormalId.Right else Enum.NormalId.Left
end

-- Weather per circuit (TrackData `Sky`): "Sunny" (default), "Cloudy",
-- "Sunset" (low warm sun) or "Night" (dark sky; the circuit's own lamps
-- light the track, see Scenery.trackLights).
type Sky = { clock: number, brightness: number, exposure: number, density: number, haze: number, glare: number, color: Color3, decay: Color3, saturation: number, contrast: number, clouds: number, ambient: Color3, outdoor: Color3, tint: Color3?, lift: number? }
local DAY_AMBIENT = Color3.new(0.25, 0.25, 0.28)
local DAY_OUTDOOR = Color3.new(0.55, 0.55, 0.6)
local SKIES: { [string]: Sky } = {
	Sunny = {
		clock = 14.6, brightness = 2.8, exposure = 0.1,
		density = 0.22, haze = 0.6, glare = 0.15,
		color = Color3.fromRGB(205, 218, 232), decay = Color3.fromRGB(120, 138, 160),
		saturation = 0.1, contrast = 0.06, clouds = 0,
		ambient = DAY_AMBIENT, outdoor = DAY_OUTDOOR,
	},
	-- a bright English summer afternoon under broken cloud (the user found
	-- the darker first version hard to read on a phone)
	Cloudy = {
		clock = 15.2, brightness = 2.6, exposure = 0.2,
		density = 0.26, haze = 0.9, glare = 0.05,
		color = Color3.fromRGB(210, 216, 226), decay = Color3.fromRGB(150, 158, 172),
		saturation = 0, contrast = 0.05, clouds = 0.5,
		ambient = Color3.new(0.3, 0.3, 0.33), outdoor = Color3.new(0.62, 0.62, 0.67),
	},
	-- late afternoon: low golden sun and long shadows through the trees
	Sunset = {
		clock = 17.7, brightness = 2.2, exposure = 0.15,
		density = 0.3, haze = 1.6, glare = 0.4,
		color = Color3.fromRGB(240, 196, 150), decay = Color3.fromRGB(180, 120, 90),
		saturation = 0.15, contrast = 0.08, clouds = 0.25,
		ambient = Color3.fromRGB(70, 58, 52), outdoor = Color3.fromRGB(150, 120, 100),
		tint = Color3.fromRGB(255, 240, 225),
	},
	-- after dark, but a floodlit circuit: a dark blue sky and a road that is
	-- easy to read even on a phone screen (the first, darker version was
	-- not: little ambient light and a thick dark haze hid the far road)
	Night = {
		clock = 21.3, brightness = 1, exposure = 0.6,
		density = 0.22, haze = 0.3, glare = 0,
		color = Color3.fromRGB(84, 96, 132), decay = Color3.fromRGB(52, 60, 92),
		saturation = 0.05, contrast = 0.06, clouds = 0,
		ambient = Color3.fromRGB(105, 110, 130), outdoor = Color3.fromRGB(125, 132, 160),
		lift = 0.04,
	},
}

function Scenery.lighting(spec: any?)
	local sk = SKIES[spec and spec.Sky or "Sunny"] or SKIES.Sunny
	Lighting.ClockTime = sk.clock
	Lighting.Brightness = sk.brightness
	Lighting.ExposureCompensation = sk.exposure
	Lighting.Ambient = sk.ambient
	Lighting.OutdoorAmbient = sk.outdoor
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local atmo = Instance.new("Atmosphere")
	atmo.Density = sk.density
	atmo.Offset = 0.15
	atmo.Color = sk.color
	atmo.Decay = sk.decay
	atmo.Glare = sk.glare
	atmo.Haze = sk.haze
	atmo.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 20
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = sk.saturation
	cc.Contrast = sk.contrast
	cc.TintColor = sk.tint or Color3.new(1, 1, 1)
	cc.Brightness = sk.lift or 0
	cc.Parent = Lighting
	local old = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if sk.clouds > 0 then
		local clouds = old or Instance.new("Clouds")
		clouds.Cover = sk.clouds
		clouds.Density = 0.5
		clouds.Color = Color3.fromRGB(236, 238, 242)
		clouds.Parent = workspace.Terrain
	elseif old then
		old:Destroy()
	end
end

-- A wall along a polyline with an optional catch fence and sponsor boards
-- on the side facing `trackSide(mid)`.
local function wallLine(folder: Instance, pts: { Vector3 }, height: number, thick: number, color: Color3, material: Enum.Material, fence: number, boardsToward: ((Vector3) -> Vector3?)?, stripes: boolean?)
	for k = 1, #pts - 1 do
		local a, c = pts[k], pts[k + 1]
		local mid = (a + c) / 2
		local len = (c - a).Magnitude + 0.4
		if len < 0.5 then
			continue
		end
		local cf = CFrame.lookAt(mid + Vector3.new(0, height / 2 + TrackLayout.LawnY, 0), mid + Vector3.new(0, height / 2 + TrackLayout.LawnY, 0) + (c - a))
		local w = Build.part(folder, {
			Name = "Wall",
			Size = Vector3.new(thick, height, len),
			CFrame = cf,
			Color = if stripes then (if k % 2 == 0 then RED else WHITE) else color,
			Material = material,
			CustomPhysicalProperties = PhysicalProperties.new(2, 0.15, if stripes then 0.4 else 0.25, 1, 1),
		})
		if boardsToward and k % 4 == 2 and len > 6 then
			local target = boardsToward(mid)
			if target then
				label(w, faceTowards(cf, target), nextSponsor(), WHITE, if k % 8 == 2 then BLUE else RED, 10)
			end
		end
		if fence > 0 then
			local top = height + TrackLayout.LawnY
			Build.decor(folder, {
				Name = "Fence",
				Size = Vector3.new(0.12, fence, len),
				CFrame = CFrame.lookAt(mid + Vector3.new(0, top + fence / 2, 0), mid + Vector3.new(0, top + fence / 2, 0) + (c - a)),
				Color = FENCE,
				Material = Enum.Material.DiamondPlate,
				Transparency = 0.6,
				CastShadow = false,
			})
			if k % 2 == 1 then
				Build.decor(folder, {
					Name = "Post",
					Size = Vector3.new(0.35, fence + 0.4, 0.35),
					CFrame = CFrame.new(a + Vector3.new(0, top + fence / 2, 0)),
					Color = DARK,
					Material = Enum.Material.Metal,
				})
			end
		end
	end
end

-- Start gantry over the line, with five red start lights facing the grid.
function Scenery.gantry(track: TrackMath.Track, spec: any, parent: Instance): Model
	local s = track.samples[1]
	local model = Instance.new("Model")
	model.Name = "Gantry"
	local half = s.width / 2 + 3
	local height = 15
	for _, side in { -1, 1 } do
		local base = s.pos + s.right * (side * half)
		Build.part(model, {
			Name = "Pillar",
			Size = Vector3.new(1.6, height + 1, 1.6),
			CFrame = CFrame.fromMatrix(v3(base + s.up * (height / 2)), v3(s.right), v3(s.up), v3(-s.fwd)),
			Color = DARK,
			Material = Enum.Material.Metal,
		})
	end
	local beamPos = s.pos + s.up * height
	local beam = Build.part(model, {
		Name = "Beam",
		Size = Vector3.new(half * 2 + 1.6, 2.4, 1.4),
		CFrame = CFrame.fromMatrix(v3(beamPos), v3(s.right), v3(s.up), v3(-s.fwd)),
		Color = DARK,
		Material = Enum.Material.Metal,
	})
	label(beam, Enum.NormalId.Back, string.upper(spec.Name), WHITE, DARK)
	label(beam, Enum.NormalId.Front, "A1 KART RACING", ACCENT, DARK)
	local lights = Build.folder(model, "Lights")
	for k = 1, 5 do
		local lateral = (k - 3) * 3
		local center = beamPos + s.right * lateral - s.up * 2.6 - s.fwd * 0.2
		Build.part(model, {
			Name = "Pod",
			Size = Vector3.new(2.4, 2.6, 1.2),
			CFrame = CFrame.fromMatrix(v3(center), v3(s.right), v3(s.up), v3(-s.fwd)),
			Color = Color3.fromRGB(12, 12, 14),
			Material = Enum.Material.SmoothPlastic,
		})
		local lamp = Build.decor(lights, {
			Name = "Light" .. k,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 1.7, 1.7),
			CFrame = CFrame.fromMatrix(v3(center - s.fwd * 0.65), v3(-s.fwd), v3(s.up), v3(-s.right)),
			Color = Color3.fromRGB(40, 8, 8),
			Material = Enum.Material.SmoothPlastic,
		})
		lamp:SetAttribute("Index", k)
	end
	model.Parent = parent
	return model
end

-- The podium in the paddock: three steps facing +Z (towards the garages),
-- a backdrop, a camera mark for the podium view and a confetti cannon.
-- RaceManager puts the top three karts on Step1..3 after a race and turns
-- the confetti on (the ParticleEmitters in Confetti) while the results are up.
function Scenery.podium(parent: Instance, x: number, z: number): Folder
	local folder = Build.folder(parent, "Podium")
	local base = 0.6
	Build.part(folder, {
		Name = "Plinth",
		Size = Vector3.new(36, base, 16),
		CFrame = CFrame.new(x, base / 2, z),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	-- second on the winner's right (left as you look at it), third on the left
	type StepSpec = { place: number, dx: number, h: number, color: Color3 }
	local specs: { StepSpec } = {
		{ place = 1, dx = 0, h = 3.2, color = ACCENT },
		{ place = 2, dx = -11, h = 2.2, color = Color3.fromRGB(200, 204, 212) },
		{ place = 3, dx = 11, h = 1.4, color = Color3.fromRGB(196, 120, 60) },
	}
	for _, sp in specs do
		local pos = Vector3.new(x + sp.dx, base + sp.h / 2, z)
		local step = Build.part(folder, {
			Name = "Step" .. sp.place,
			Size = Vector3.new(10.5, sp.h, 9.5),
			CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)),
			Color = sp.color,
			Material = Enum.Material.SmoothPlastic,
		})
		-- the front (LookVector) face carries the number
		label(step, Enum.NormalId.Front, tostring(sp.place), WHITE, sp.color, 6)
	end
	-- backdrop with the circuit name
	local back = Build.part(folder, {
		Name = "Backdrop",
		Size = Vector3.new(40, 15, 1),
		CFrame = CFrame.new(x, 7.5, z - 7),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	label(back, Enum.NormalId.Back, trackName .. "  -  A1 KART RACING", ACCENT, DARK, 6)
	-- chequered strip along the top of the backdrop
	for i = 0, 15 do
		for row = 0, 1 do
			Build.decor(folder, {
				Name = "Chequer",
				Size = Vector3.new(2.5, 1.2, 0.2),
				CFrame = CFrame.new(x - 18.75 + i * 2.5, 13.9 - row * 1.2, z - 6.4),
				Color = if (i + row) % 2 == 0 then WHITE else DARK,
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
	for _, dx in { -21, 21 } do
		Build.part(folder, {
			Name = "Pillar",
			Size = Vector3.new(2, 17, 2),
			CFrame = CFrame.new(x + dx, 8.5, z - 7),
			Color = RED,
			Material = Enum.Material.SmoothPlastic,
		})
	end
	-- where the podium camera sits, looking at the steps
	local camPos = Vector3.new(x, 9, z + 30)
	Build.decor(folder, {
		Name = "Camera",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.lookAt(camPos, Vector3.new(x, 4.5, z)),
		Transparency = 1,
		CastShadow = false,
	})
	-- confetti from above the steps
	local cannon = Build.decor(folder, {
		Name = "Confetti",
		Size = Vector3.new(30, 1, 6),
		CFrame = CFrame.new(x, 17, z - 2),
		Transparency = 1,
		CastShadow = false,
	})
	-- one emitter per colour (a colour sequence would fade every piece)
	for _, color in { ACCENT, RED, BLUE, WHITE } do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Emitter"
		emitter.Enabled = false
		emitter.Rate = 20
		emitter.Lifetime = NumberRange.new(3, 4.5)
		emitter.Speed = NumberRange.new(4, 9)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Acceleration = Vector3.new(0, -6, 0)
		emitter.Drag = 1.2
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-200, 200)
		emitter.Size = NumberSequence.new(0.25)
		emitter.Color = ColorSequence.new(color)
		emitter.LightInfluence = 0.3
		emitter.Parent = cannon
	end
	return folder
end

-- Pit wall, garages with race control, and the paddock with the spawn.
function Scenery.pits(track: TrackMath.Track, spec: any, parent: Instance): SpawnLocation
	local P = TrackLayout.paddock(track)
	local folder = Build.folder(parent, "Pits")

	-- pit wall (concrete, fence on top, boards facing the main straight)
	local wallPts: { Vector3 } = {}
	for _, p in P.wall do
		table.insert(wallPts, v3(p))
	end
	wallLine(folder, wallPts, 3.4, 1.6, CONCRETE, Enum.Material.Concrete, 6, function(mid)
		return mid + Vector3.new(0, 0, 10)
	end)

	-- garages: a long low building, one open bay per team
	local g = P.garages
	local h1 = 12
	local depth = g.maxZ - g.minZ
	local cx = (g.minX + g.maxX) / 2
	local frontZ = g.maxZ
	Build.part(folder, { -- back wall
		Name = "GarageBack",
		Size = Vector3.new(g.maxX - g.minX, h1, 1),
		CFrame = CFrame.new(cx, h1 / 2, g.minZ + 0.5),
		Color = CONCRETE,
		Material = Enum.Material.Concrete,
	})
	Build.part(folder, { -- ground-floor ceiling / first floor
		Name = "GarageRoof",
		Size = Vector3.new(g.maxX - g.minX + 2, 1, depth + 2),
		CFrame = CFrame.new(cx, h1 + 0.5, (g.minZ + g.maxZ) / 2),
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	})
	local bays = math.max(1, math.floor((g.maxX - g.minX) / 28))
	local bayW = (g.maxX - g.minX) / bays
	local teamColors = { RED, BLUE, ACCENT, Color3.fromRGB(30, 160, 80), Color3.fromRGB(240, 110, 20), Color3.fromRGB(130, 60, 190), Color3.fromRGB(20, 180, 190), Color3.fromRGB(230, 70, 150) }
	for b = 0, bays do
		local x = g.minX + b * bayW
		Build.part(folder, {
			Name = "Pier",
			Size = Vector3.new(2, h1, depth),
			CFrame = CFrame.new(x, h1 / 2, (g.minZ + g.maxZ) / 2),
			Color = WHITE,
			Material = Enum.Material.SmoothPlastic,
		})
		if b < bays then
			local bx = x + bayW / 2
			Build.decor(folder, { -- dark interior
				Name = "Interior",
				Size = Vector3.new(bayW - 2, h1 - 2, 0.4),
				CFrame = CFrame.new(bx, (h1 - 2) / 2, g.minZ + 1.4),
				Color = Color3.fromRGB(46, 48, 54),
				Material = Enum.Material.SmoothPlastic,
			})
			local header = Build.decor(folder, {
				Name = "Header",
				Size = Vector3.new(bayW - 2, 2.2, 0.4),
				CFrame = CFrame.new(bx, h1 - 1.2, frontZ - 0.2),
				Color = teamColors[b % #teamColors + 1],
				Material = Enum.Material.SmoothPlastic,
			})
			label(header :: BasePart, Enum.NormalId.Back, "TEAM " .. (b + 1), WHITE, teamColors[b % #teamColors + 1], 12)
		end
	end
	-- hospitality level: glass front, set back
	Build.part(folder, {
		Name = "Upper",
		Size = Vector3.new(g.maxX - g.minX - 6, 7, depth - 6),
		CFrame = CFrame.new(cx, h1 + 4.5, (g.minZ + g.maxZ) / 2 - 3),
		Color = CONCRETE,
		Material = Enum.Material.Concrete,
	})
	Build.decor(folder, {
		Name = "Glass",
		Size = Vector3.new(g.maxX - g.minX - 6, 5.5, 0.3),
		CFrame = CFrame.new(cx, h1 + 4.6, g.maxZ - 5.9),
		Color = Color3.fromRGB(120, 170, 210),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
	})
	local sign = Build.decor(folder, {
		Name = "Sign",
		Size = Vector3.new(math.min(140, g.maxX - g.minX - 20), 6, 0.6),
		CFrame = CFrame.new(cx, h1 + 11.5, g.maxZ - 6),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	label(sign :: BasePart, Enum.NormalId.Back, string.upper(spec.Name), ACCENT, DARK, 8)

	-- race control tower at the pit exit end
	local tx = g.maxX + 12
	Build.part(folder, {
		Name = "Tower",
		Size = Vector3.new(14, 26, 14),
		CFrame = CFrame.new(tx, 13, g.minZ + depth / 2),
		Color = WHITE,
		Material = Enum.Material.SmoothPlastic,
	})
	Build.part(folder, {
		Name = "ControlRoom",
		Size = Vector3.new(18, 7, 18),
		CFrame = CFrame.new(tx, 29.5, g.minZ + depth / 2),
		Color = Color3.fromRGB(110, 160, 205),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
	})
	Build.part(folder, {
		Name = "TowerRoof",
		Size = Vector3.new(20, 1, 20),
		CFrame = CFrame.new(tx, 33.5, g.minZ + depth / 2),
		Color = DARK,
		Material = Enum.Material.Metal,
	})
	local towerSign = Build.decor(folder, {
		Name = "TowerSign",
		Size = Vector3.new(14, 4, 0.4),
		CFrame = CFrame.new(tx, 22, g.minZ + depth / 2 + 7.2),
		Color = RED,
		Material = Enum.Material.SmoothPlastic,
	})
	label(towerSign :: BasePart, Enum.NormalId.Back, "RACE CONTROL", WHITE, RED, 12)

	-- a sweeping wing-shaped roof over the whole pit building, overhanging
	-- the pit lane (TrackData PitStyle = "Wing")
	if spec.PitStyle == "Wing" then
		local lane = P.pitLane
		-- section through the roof, back (paddock side) to front (over the lane)
		local section = {
			Vector2.new(g.minZ - 6, h1 + 9),
			Vector2.new(g.minZ + 4, h1 + 14.5),
			Vector2.new(g.minZ + 14, h1 + 17),
			Vector2.new(g.maxZ, h1 + 17.6),
			Vector2.new(lane.minZ + 8, h1 + 16.6),
			Vector2.new(lane.maxZ - 3, h1 + 13.2),
		}
		-- from just past the first bay to the race control tower
		local x0, x1 = g.minX - 6, g.maxX + 1
		local len = x1 - x0
		local rcx = (x0 + x1) / 2
		for k = 1, #section - 1 do
			local a, b = section[k], section[k + 1]
			local mid = (a + b) / 2
			local d = b - a
			local cf = CFrame.lookAt(Vector3.new(rcx, mid.Y, mid.X), Vector3.new(rcx, mid.Y + d.Y, mid.X + d.X))
			Build.part(folder, {
				Name = "WingRoof",
				Size = Vector3.new(len, 0.8, d.Magnitude + 0.3),
				CFrame = cf,
				Color = Color3.fromRGB(236, 238, 240),
				Material = Enum.Material.SmoothPlastic,
			})
		end
		-- a dark leading edge over the lane; the back rests on slim columns
		-- (the front is cantilevered off the garage piers)
		local front = section[#section]
		Build.decor(folder, {
			Name = "WingEdge",
			Size = Vector3.new(len, 1.2, 0.5),
			CFrame = CFrame.new(rcx, front.Y - 0.2, front.X + 0.2),
			Color = DARK,
			Material = Enum.Material.Metal,
		})
		local cols = math.max(2, math.floor(len / 36))
		for c = 0, cols do
			local x = x0 + 6 + (len - 12) * c / cols
			Build.part(folder, {
				Name = "WingColumn",
				Size = Vector3.new(0.9, h1 + 10, 0.9),
				CFrame = CFrame.new(x, (h1 + 10) / 2, g.minZ - 3),
				Color = Color3.fromRGB(200, 202, 206),
				Material = Enum.Material.Metal,
			})
		end
		local nameBoard = Build.decor(folder, {
			Name = "WingSign",
			Size = Vector3.new(math.min(160, len - 40), 3.4, 0.4),
			CFrame = CFrame.new(rcx, section[4].Y + 2.4, g.maxZ - 2),
			Color = DARK,
			Material = Enum.Material.SmoothPlastic,
		})
		label(nameBoard :: BasePart, Enum.NormalId.Back, string.upper(spec.Name) .. "  -  THE WING", WHITE, DARK, 8)
	end

	-- paddock: podium, spawn and how-to-play board
	local plaza = P.plaza
	Scenery.podium(folder, (plaza.minX + plaza.maxX) / 2 + 70, plaza.minZ + 24)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new((plaza.minX + plaza.maxX) / 2 - 20, 0.1, (plaza.minZ + plaza.maxZ) / 2)
	spawn.Color = ACCENT
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	local board = Build.part(folder, {
		Name = "InfoBoard",
		Size = Vector3.new(26, 14, 1),
		CFrame = CFrame.new((plaza.minX + plaza.maxX) / 2 + 12, 8, plaza.minZ + 14),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.3
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = DARK
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.RichText = true
	text.Text = table.concat({
		'<font color="#FFC400">HOW TO RACE</font>',
		"W / S   throttle and brake (hold S to reverse)",
		"A / D   steer",
		"R   back on track",
		"Mouse wheel / C   camera, zoom in for cockpit",
		"Right-drag   rotate camera     V   reset view",
		"Gamepad: RT / LT / left stick",
		"M   track, race length and READY before each race",
		"Practice until 2+ drivers are here, then qualifying sets the grid.",
		string.format("All 4 wheels past the kerb: %d warnings, then +%d s each.", Config.Race.TrackLimitWarnings, Config.Race.TrackLimitPenalty),
	}, "\n")
	text.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.PaddingBottom = UDim.new(0.06, 0)
	pad.Parent = text
	return spawn
end

-- Tiered grandstand. `center` is the middle of the front edge; it rises away
-- from the track (opposite `facing`).
local function grandstand(folder: Instance, st: TrackLayout.Stand)
	local facing = v3(st.facing)
	local along = facing:Cross(Vector3.new(0, 1, 0))
	local base = v3(st.center)
	local tiers = 7
	local rowDepth = st.depth / tiers
	local seatColors = { BLUE, WHITE, RED }
	-- right-handed frame whose LookVector is `facing` (towards the track)
	local function frame(offsetBack: number, y: number): CFrame
		local p = base - facing * offsetBack + Vector3.new(0, y, 0)
		return CFrame.fromMatrix(p, along, Vector3.new(0, 1, 0), -facing)
	end
	-- up on a hillside: a concrete plinth from the lawn to the stand's floor
	if base.Y > 0.3 then
		local h = base.Y + TrackLayout.LawnY + 1
		Build.part(folder, {
			Name = "Plinth",
			Size = Vector3.new(st.length + 2, h, st.depth + 3),
			CFrame = frame(st.depth / 2 + 1, TrackLayout.LawnY - h / 2),
			Color = CONCRETE,
			Material = Enum.Material.Concrete,
		})
	end
	Build.part(folder, {
		Name = "FrontWall",
		Size = Vector3.new(st.length, 2, 1),
		CFrame = frame(0.5, 1 + TrackLayout.LawnY),
		Color = CONCRETE,
		Material = Enum.Material.Concrete,
	})
	for t = 0, tiers - 1 do
		local h = 1.6 * (t + 1) + 1
		Build.part(folder, {
			Name = "Tier",
			Size = Vector3.new(st.length, h, rowDepth),
			CFrame = frame(1 + rowDepth * (t + 0.5), h / 2 + TrackLayout.LawnY),
			Color = CONCRETE,
			Material = Enum.Material.Concrete,
		})
		Build.decor(folder, {
			Name = "Seats",
			Size = Vector3.new(st.length - 1, 0.6, rowDepth * 0.35),
			CFrame = frame(1 + rowDepth * (t + 0.3), h + 0.3 + TrackLayout.LawnY),
			Color = seatColors[t % #seatColors + 1],
			Material = Enum.Material.SmoothPlastic,
		})
	end
	-- roof on columns at the back
	local backOff = 1 + st.depth
	local roofY = 1.6 * tiers + 12
	local cols = math.max(2, math.floor(st.length / 30) + 1)
	for c = 0, cols - 1 do
		local u = -st.length / 2 + st.length * c / (cols - 1)
		local p = base - facing * backOff + along * u
		Build.part(folder, {
			Name = "Column",
			Size = Vector3.new(1.2, roofY, 1.2),
			CFrame = CFrame.new(p + Vector3.new(0, roofY / 2, 0)),
			Color = DARK,
			Material = Enum.Material.Metal,
		})
	end
	Build.part(folder, {
		Name = "Roof",
		Size = Vector3.new(st.length + 4, 0.8, st.depth + 6),
		CFrame = frame(1 + st.depth / 2, roofY) * CFrame.Angles(math.rad(-5), 0, 0),
		Color = WHITE,
		Material = Enum.Material.Metal,
	})
	local fascia = Build.decor(folder, {
		Name = "Fascia",
		Size = Vector3.new(st.length + 4, 3, 0.5),
		CFrame = frame(-1.6, roofY + 1.2),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	-- the Front face (LookVector side) looks at the track
	label(fascia :: BasePart, Enum.NormalId.Front, nextSponsor() .. "  -  " .. st.name:upper(), ACCENT, DARK, 8)
end

-- Corner name boards (TrackData CornerBoards = true): one at the entry of
-- every named corner, outside the turn and set back behind the bands,
-- turned towards the drivers coming up to it.
function Scenery.cornerBoards(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, spec: any, parent: Instance)
	if not spec.CornerBoards then
		return
	end
	local folder = Build.folder(parent, "CornerBoards")
	local last: string? = nil
	for _, c in TrackLayout.corners(track, spec.Segments) do
		local name = c.name
		if not name or name == last or string.find(name, "Straight") then
			last = name
			continue
		end
		last = name
		-- entry sample of the corner
		local first = c.mid
		for i, smp in track.samples do
			if smp.segment == c.first then
				first = i
				break
			end
		end
		local smp = track.samples[first]
		local side = if c.angle > 0 then -1 else 1 -- outside of the turn
		local b = if side < 0 then zones[first].left else zones[first].right
		local dir = TrackLayout.outward(smp, side)
		local base = vector.create(smp.pos.x, 0, smp.pos.z) + dir * (smp.width / 2 + TrackLayout.bandEnd(b) + 14)
		if not TrackLayout.clearOfRoads(grid, base, 10, first, 12) then
			continue
		end
		base = vector.create(base.x, TrackLayout.groundY(TrackLayout.ground(track, grid, zones), base.x, base.z), base.z)
		-- face a point on the road some way before the corner
		local before = track.samples[TrackMath.wrap(first - 12, track.n)].pos
		local p = v3(base)
		local toward = Vector3.new(before.x, p.Y, before.z) - p
		local cf = CFrame.lookAt(p + Vector3.new(0, 5, 0), p + Vector3.new(0, 5, 0) + toward.Unit)
		for _, x in { -5.5, 5.5 } do
			Build.part(folder, {
				Name = "BoardPost",
				Size = Vector3.new(0.5, 7, 0.5),
				CFrame = cf * CFrame.new(x, -1.5, 0.3),
				Color = DARK,
				Material = Enum.Material.Metal,
			})
		end
		local board = Build.part(folder, {
			Name = "CornerBoard",
			Size = Vector3.new(13, 3.2, 0.4),
			CFrame = cf * CFrame.new(0, 0.6, 0),
			Color = Color3.fromRGB(18, 92, 60),
			Material = Enum.Material.SmoothPlastic,
		})
		-- the Front face (LookVector side) faces the drivers
		label(board, Enum.NormalId.Front, string.upper(name), WHITE, Color3.fromRGB(18, 92, 60), 14)
	end
end

function Scenery.stands(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, spec: any, parent: Instance)
	local folder = Build.folder(parent, "Grandstands")
	for _, st in TrackLayout.stands(track, grid, zones, spec.Segments) do
		grandstand(Build.folder(folder, st.name), st)
	end
end

-- Sponsor bridge over the longest straight (driven under).
function Scenery.bridge(track: TrackMath.Track, spec: any, parent: Instance)
	local i = TrackLayout.bridge(track, spec.Segments, spec.Bridge)
	if not i then
		return
	end
	local s = track.samples[i]
	local folder = Build.folder(parent, "Bridge")
	local half = s.width / 2 + 7
	local deckY = 16
	-- level frame even where the road is banked or on a slope
	local right = Vector3.new(s.right.x, 0, s.right.z).Unit
	local back = right:Cross(Vector3.new(0, 1, 0))
	local floor = s.pos.y + TrackLayout.LawnY - 1 -- towers sunk a little into the bank
	local top = s.pos.y + deckY
	for _, side in { -1, 1 } do
		local p = Vector3.new(s.pos.x, 0, s.pos.z) + right * (side * half)
		local h = top + 4 - floor
		Build.part(folder, {
			Name = "Tower",
			Size = Vector3.new(4, h, 6),
			CFrame = CFrame.fromMatrix(p + Vector3.new(0, floor + h / 2, 0), right, Vector3.new(0, 1, 0), back),
			Color = CONCRETE,
			Material = Enum.Material.Concrete,
		})
	end
	local deck = Build.part(folder, {
		Name = "Deck",
		Size = Vector3.new(half * 2 + 4, 4, 5),
		CFrame = CFrame.fromMatrix(v3(s.pos) + Vector3.new(0, deckY + 2, 0), right, Vector3.new(0, 1, 0), back),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
	})
	-- Back faces drivers approaching (towards -fwd), Front faces the other way
	label(deck, Enum.NormalId.Back, "GRIPLINE TYRES", WHITE, RED, 10)
	label(deck, Enum.NormalId.Front, "VOLT ENERGY", ACCENT, DARK, 10)
	Build.decor(folder, {
		Name = "Rail",
		Size = Vector3.new(half * 2 + 4, 1.4, 0.2),
		CFrame = CFrame.fromMatrix(v3(s.pos) + Vector3.new(0, deckY + 4.7, 0), right, Vector3.new(0, 1, 0), back),
		Color = FENCE,
		Material = Enum.Material.DiamondPlate,
		Transparency = 0.4,
	})
end

-- Tyre walls (red/white with a catch fence) and concrete walls in the gaps.
function Scenery.barriers(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, parent: Instance)
	local folder = Build.folder(parent, "Barriers")
	local function towardTrack(mid: Vector3): Vector3?
		local i = TrackLayout.nearest(grid, mid.X, mid.Z, 200)
		return if i then v3(track.samples[i].pos) else nil
	end
	for _, bar in TrackLayout.barriers(track, grid, zones) do
		local pts: { Vector3 } = {}
		for _, p in bar.points do
			table.insert(pts, v3(p))
		end
		if bar.kind == "tyres" then
			wallLine(folder, pts, 2.6, 2.2, WHITE, Enum.Material.Rubber, 7, towardTrack, true)
		else
			wallLine(folder, pts, 3.2, 1.4, CONCRETE, Enum.Material.Concrete, 5, nil)
		end
	end
end

-- Marshal posts: small booths with a flag on the inside of the big corners.
function Scenery.marshals(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, spec: any, parent: Instance)
	local folder = Build.folder(parent, "Marshals")
	for _, post in TrackLayout.marshals(track, grid, zones, spec.Segments) do
		local p = v3(post.pos)
		local f = v3(post.facing)
		local cf = CFrame.lookAt(p + Vector3.new(0, 1.6, 0), p + Vector3.new(0, 1.6, 0) + f)
		Build.part(folder, {
			Name = "Booth",
			Size = Vector3.new(3, 3.2, 2.6),
			CFrame = cf,
			Color = WHITE,
			Material = Enum.Material.SmoothPlastic,
		})
		Build.decor(folder, {
			Name = "BoothRoof",
			Size = Vector3.new(3.6, 0.4, 3.2),
			CFrame = cf + Vector3.new(0, 1.8, 0),
			Color = Color3.fromRGB(240, 110, 20),
			Material = Enum.Material.SmoothPlastic,
		})
		local pole = p + f:Cross(Vector3.new(0, 1, 0)) * 2
		Build.decor(folder, {
			Name = "FlagPole",
			Size = Vector3.new(0.2, 6, 0.2),
			CFrame = CFrame.new(pole + Vector3.new(0, 3, 0)),
			Color = DARK,
			Material = Enum.Material.Metal,
		})
		Build.decor(folder, {
			Name = "Flag",
			Size = Vector3.new(0.05, 1.2, 1.8),
			CFrame = CFrame.lookAt(pole + Vector3.new(0, 5.3, 0), pole + Vector3.new(0, 5.3, 0) + f:Cross(Vector3.new(0, 1, 0))) * CFrame.new(0, 0, -0.9),
			Color = Color3.fromRGB(255, 214, 0),
			Material = Enum.Material.Fabric,
		})
	end
end

-- A lake in the most open part of the facility (TrackData `Lake`): a big
-- round pool with one or two smaller lobes for a natural outline, a sandy
-- shore round each. The water is drivable but slows a kart to a crawl, so it
-- goes in the Track folder (the wheels' rays see it). Returns the circles so
-- trees can keep off them.
export type Circle = { x: number, z: number, r: number }
function Scenery.water(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, spec: any, trackFolder: Instance): { Circle }
	local pools: { Circle } = {}
	if not spec.Lake then
		return pools
	end
	local spots = TrackLayout.openGround(track, grid, zones, spec.Segments, 10, 70)
	local main = spots[1]
	if not main then
		return pools
	end
	local r = math.min(main.clear - 40, 150)
	if r < 30 then
		return pools
	end
	table.insert(pools, { x = main.pos.x, z = main.pos.z, r = r })
	-- lobes: open spots that overlap the main pool by about half their size
	for _, sp in spots do
		if #pools >= 3 then
			break
		end
		local lr = math.min(sp.clear - 40, r * 0.65)
		if lr >= 25 then
			local d = math.sqrt((sp.pos.x - main.pos.x) ^ 2 + (sp.pos.z - main.pos.z) ^ 2)
			local overlaps = d > r * 0.6 and d < r + lr * 0.5
			local apart = true
			for k = 2, #pools do
				local o = pools[k]
				if math.sqrt((sp.pos.x - o.x) ^ 2 + (sp.pos.z - o.z) ^ 2) < o.r + lr * 0.3 then
					apart = false
				end
			end
			if overlaps and apart then
				table.insert(pools, { x = sp.pos.x, z = sp.pos.z, r = lr })
			end
		end
	end
	local folder = Build.folder(trackFolder, "Lake")
	for _, c in pools do
		-- a flat disc: a cylinder lying with its axis vertical
		local up = CFrame.Angles(0, 0, math.rad(90))
		local shore = Build.part(folder, {
			Name = "Shore",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, c.r * 2 + 8, c.r * 2 + 8),
			CFrame = CFrame.new(c.x, TrackLayout.LawnY - 0.03, c.z) * up,
			Color = Color3.fromRGB(214, 196, 150),
			Material = Enum.Material.Sand,
		})
		shore:SetAttribute("Surface", "Gravel")
		local water = Build.part(folder, {
			Name = "Water",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, c.r * 2, c.r * 2),
			CFrame = CFrame.new(c.x, TrackLayout.LawnY - 0.01, c.z) * up,
			Color = Color3.fromRGB(38, 104, 148),
			Material = Enum.Material.Glass,
			Reflectance = 0.2,
			Transparency = 0.1,
			CastShadow = false,
		})
		water:SetAttribute("Surface", "Water")
	end
	return pools
end

-- Pine trees on the open ground (TrackData `Trees`), well away from the
-- road, the lake, the paddock and the grandstands.
function Scenery.trees(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, spec: any, pools: { Circle }, parent: Instance)
	if not spec.Trees then
		return
	end
	local folder = Build.folder(parent, "Trees")
	local rand = TrackLayout.random(track.n * 7919 + 17)
	local placed: { vector } = {}
	local spots = TrackLayout.openGround(track, grid, zones, spec.Segments, 10, 50)
	local ground = TrackLayout.ground(track, grid, zones)
	for _, sp in spots do
		if #placed >= 80 then
			break
		end
		local p = sp.pos + vector.create((rand() - 0.5) * 10, 0, (rand() - 0.5) * 10)
		local ok = true
		for _, q in placed do
			if vector.magnitude(p - q) < 30 + rand() * 12 then
				ok = false
				break
			end
		end
		for _, c in pools do
			if math.sqrt((p.x - c.x) ^ 2 + (p.z - c.z) ^ 2) < c.r + 18 then
				ok = false
			end
		end
		if ok then
			table.insert(placed, p)
			local k = 0.8 + rand() * 0.6
			-- on the lawn or up an embankment, sunk a little so no root floats
			local gy = TrackLayout.groundY(ground, p.x, p.z)
			local base = v3(vector.create(p.x, if gy > 0 then gy - 0.4 else 0, p.z))
			Build.part(folder, {
				Name = "Trunk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(9 * k, 1.4 * k, 1.4 * k),
				CFrame = CFrame.new(base + Vector3.new(0, 4.5 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(92, 62, 40),
				Material = Enum.Material.Wood,
			})
			for layer = 1, 3 do
				local w = (10 - layer * 2.4) * k
				local h = (9 - layer * 1.4) * k
				local leaves = Build.decor(folder, {
					Name = "Needles",
					Size = Vector3.new(w, h, w),
					CFrame = CFrame.new(base + Vector3.new(0, (5 + layer * 4.2) * k, 0)) * CFrame.Angles(0, rand() * 6.28, 0),
					Color = if layer == 2 then Color3.fromRGB(40, 92, 52) else Color3.fromRGB(32, 78, 44),
					Material = Enum.Material.Grass,
				})
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = leaves
			end
		end
	end
end

-- Lamp posts along the track for night races (TrackData `TrackLights`):
-- one every ~55 studs, beyond the kerbs and run-off on the side with room,
-- each with a downward spot light.
function Scenery.trackLights(track: TrackMath.Track, grid: TrackLayout.Grid, zones: TrackLayout.Zones, spec: any, parent: Instance)
	if not spec.TrackLights then
		return
	end
	local folder = Build.folder(parent, "TrackLights")
	-- close enough (and wide enough) that the pools of light overlap and
	-- reach across the road
	local every = math.max(1, math.floor(55 / track.spacing + 0.5))
	local flip = 1
	for i = 1, track.n, every do
		local smp = track.samples[i]
		-- prefer the outside of a corner, else alternate sides
		local curv = TrackLayout.smoothCurv(track, i, 4)
		local first = if math.abs(curv) > 1 / 400 then (if curv > 0 then -1 else 1) else flip
		flip = -flip
		for _, side in { first, -first } do
			local b = if side < 0 then zones[i].left else zones[i].right
			local out = TrackLayout.outward(smp, side)
			local base = vector.create(smp.pos.x, 0, smp.pos.z) + out * (smp.width / 2 + TrackLayout.bandEnd(b) + 9)
			if TrackLayout.clearOfRoads(grid, base, 20, i, 20) then
				local gy = TrackLayout.groundY(TrackLayout.ground(track, grid, zones), base.x, base.z)
				local p = v3(vector.create(base.x, gy, base.z))
				local toward = v3(-out)
				local height = 14
				Build.part(folder, {
					Name = "LampPost",
					Size = Vector3.new(0.6, height, 0.6),
					CFrame = CFrame.new(p + Vector3.new(0, height / 2, 0)),
					Color = Color3.fromRGB(70, 74, 80),
					Material = Enum.Material.Metal,
				})
				local armMid = p + toward * 2.4 + Vector3.new(0, height - 0.3, 0)
				Build.decor(folder, {
					Name = "LampArm",
					Size = Vector3.new(0.35, 0.35, 5),
					CFrame = CFrame.lookAt(armMid, armMid + toward),
					Color = Color3.fromRGB(70, 74, 80),
					Material = Enum.Material.Metal,
				})
				local headPos = p + toward * 4.6 + Vector3.new(0, height - 0.6, 0)
				local head = Build.decor(folder, {
					Name = "Lamp",
					Size = Vector3.new(1.6, 0.4, 1),
					CFrame = CFrame.lookAt(headPos, headPos + toward),
					Color = Color3.fromRGB(255, 240, 210),
					Material = Enum.Material.Neon,
					CastShadow = false,
				})
				local light = Instance.new("SpotLight")
				light.Face = Enum.NormalId.Bottom
				light.Angle = 150
				light.Range = 60
				light.Brightness = 4
				light.Color = Color3.fromRGB(255, 238, 205)
				light.Shadows = false
				light.Parent = head
				break
			end
		end
	end
end

-- Perimeter wall around the facility, floodlight towers, and the car park
-- that stretches to the horizon outside it. At night the towers are lit.
function Scenery.perimeter(track: TrackMath.Track, parent: Instance, spec: any?)
	local f = TrackLayout.facility(track)
	local folder = Build.folder(parent, "Perimeter")
	local corners = {
		Vector3.new(f.minX, 0, f.minZ),
		Vector3.new(f.maxX, 0, f.minZ),
		Vector3.new(f.maxX, 0, f.maxZ),
		Vector3.new(f.minX, 0, f.maxZ),
	}
	local center = Vector3.new((f.minX + f.maxX) / 2, 0, (f.minZ + f.maxZ) / 2)
	for k = 1, 4 do
		local a, b = corners[k], corners[k % 4 + 1]
		local pts: { Vector3 } = {}
		local len = (b - a).Magnitude
		local segs = math.ceil(len / 24)
		for s = 0, segs do
			table.insert(pts, a + (b - a) * (s / segs))
		end
		-- sponsor boards on the inner face
		wallLine(folder, pts, 4, 1.6, CONCRETE, Enum.Material.Concrete, 8, function()
			return center
		end)
	end
	-- floodlight towers just inside the corners and along the long sides
	local towers = {
		Vector3.new(f.minX + 14, 0, f.minZ + 14),
		Vector3.new(f.maxX - 14, 0, f.minZ + 14),
		Vector3.new(f.maxX - 14, 0, f.maxZ - 14),
		Vector3.new(f.minX + 14, 0, f.maxZ - 14),
		Vector3.new((f.minX + f.maxX) / 2, 0, f.maxZ - 14),
		Vector3.new(f.minX + 14, 0, (f.minZ + f.maxZ) / 2),
		Vector3.new(f.maxX - 14, 0, (f.minZ + f.maxZ) / 2),
	}
	for _, p in towers do
		Build.part(folder, {
			Name = "LightPole",
			Size = Vector3.new(1.6, 46, 1.6),
			CFrame = CFrame.new(p + Vector3.new(0, 23, 0)),
			Color = Color3.fromRGB(150, 152, 158),
			Material = Enum.Material.Metal,
		})
		local head = CFrame.lookAt(p + Vector3.new(0, 47, 0), center + Vector3.new(0, 47, 0)) * CFrame.Angles(math.rad(-25), 0, 0)
		Build.decor(folder, {
			Name = "LightHead",
			Size = Vector3.new(8, 4, 1),
			CFrame = head,
			Color = DARK,
			Material = Enum.Material.Metal,
		})
		local night = spec ~= nil and spec.Sky == "Night"
		local lamps = Build.decor(folder, {
			Name = "Lamps",
			Size = Vector3.new(7, 3, 0.2),
			CFrame = head * CFrame.new(0, 0, -0.6),
			Color = Color3.fromRGB(255, 250, 230),
			Material = Enum.Material.Neon,
			Transparency = if night then 0 else 0.3,
		})
		if night then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Angle = 80
			light.Range = 60
			light.Brightness = 4
			light.Color = Color3.fromRGB(255, 246, 225)
			light.Shadows = false
			light.Parent = lamps
		end
	end
	-- car park outside the walls (asphalt tiles, Part size limit is 2048)
	local outer = 900
	local tiles = {
		{ f.minX - outer, f.maxX + outer, f.maxZ, f.maxZ + outer },
		{ f.minX - outer, f.maxX + outer, f.minZ - outer, f.minZ },
		{ f.minX - outer, f.minX, f.minZ, f.maxZ },
		{ f.maxX, f.maxX + outer, f.minZ, f.maxZ },
	}
	for _, t in tiles do
		local x0, x1, z0, z1 = t[1], t[2], t[3], t[4]
		local nx = math.ceil((x1 - x0) / 2000)
		local nz = math.ceil((z1 - z0) / 2000)
		for ix = 0, nx - 1 do
			for iz = 0, nz - 1 do
				local ax0 = x0 + (x1 - x0) * ix / nx
				local ax1 = x0 + (x1 - x0) * (ix + 1) / nx
				local az0 = z0 + (z1 - z0) * iz / nz
				local az1 = z0 + (z1 - z0) * (iz + 1) / nz
				Build.part(folder, {
					Name = "CarPark",
					Size = Vector3.new(ax1 - ax0, 1, az1 - az0),
					CFrame = CFrame.new((ax0 + ax1) / 2, -0.6, (az0 + az1) / 2),
					Color = Color3.fromRGB(96, 98, 104),
					Material = Enum.Material.Asphalt,
					CastShadow = false,
				})
			end
		end
	end
	-- parking bay lines in the car park near the paddock side
	for k = 0, 40 do
		local x = f.minX + 20 + k * 12
		if x > f.maxX - 20 then
			break
		end
		Build.strip(folder, Vector3.new(x, -0.09, f.minZ - 30), Vector3.new(x, -0.09, f.minZ - 12), Vector3.new(0, 1, 0), 0.4, { Color = WHITE, Material = Enum.Material.SmoothPlastic })
	end
end

return Scenery
