--!strict
-- Builds a kart model and seats a player in it.
--
-- Only the invisible chassis core has mass; the hitbox and every visual part
-- are massless and welded to it, and the seated character is made massless
-- too, so the physics the client computes (KartPhysics) sees exactly the
-- body it was tested with. Wheels and the steering wheel are drawn by each
-- client (KartVisuals) because they move every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local KartFactory = {}

KartFactory.Colors = {
	Color3.fromRGB(214, 36, 36),
	Color3.fromRGB(28, 98, 214),
	Color3.fromRGB(255, 186, 0),
	Color3.fromRGB(30, 170, 80),
	Color3.fromRGB(240, 110, 20),
	Color3.fromRGB(140, 60, 200),
	Color3.fromRGB(20, 190, 200),
	Color3.fromRGB(235, 70, 150),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(40, 40, 46),
	Color3.fromRGB(150, 200, 40),
	Color3.fromRGB(120, 80, 50),
}

local cfg = Config.Kart

-- Local coordinates used below: x right, h height above the ground, f forward.
-- The chassis core's centre is at h = RideHeight, f = 0.
local RH = cfg.RideHeight
local function at(x: number, h: number, f: number): CFrame
	return CFrame.new(x, h - RH, -f)
end
local function pt(x: number, h: number, f: number): Vector3
	return Vector3.new(x, h - RH, -f)
end

local function visual(model: Model, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = chassis.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

-- Cylinder between two local points; `overlap` extends both ends (tubes use
-- it so joints meet without gaps, discs pass 0).
local function cylinderBetween(model: Model, chassis: BasePart, name: string, a: Vector3, b: Vector3, diameter: number, overlap: number, color: Color3, material: Enum.Material?): BasePart
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	local offset = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
	local p = visual(model, chassis, name, Vector3.new(dir.Magnitude + overlap, diameter, diameter), offset, color, material or Enum.Material.Metal)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Round tube between two local points.
local function tube(model: Model, chassis: BasePart, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return cylinderBetween(model, chassis, name, a, b, diameter, diameter * 0.5, color, material)
end

-- Disc (short cylinder) whose axis points along local `axis`.
local function disc(model: Model, chassis: BasePart, name: string, center: Vector3, axis: Vector3, radius: number, thickness: number, color: Color3, material: Enum.Material?): BasePart
	return cylinderBetween(model, chassis, name, center - axis.Unit * (thickness / 2), center + axis.Unit * (thickness / 2), radius * 2, 0, color, material)
end

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, ppm: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppm
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = color
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.Parent = gui
end

-- Ellipsoid: a block with a sphere mesh, which Roblox stretches to the
-- part's size (round shapes without uploading meshes).
local function ellipsoid(model: Model, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = visual(model, chassis, name, size, offset, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Frame whose Z axis runs from a to b and whose X axis is the kart's right
-- (width), Y the thickness. Used for panels and stretched ellipsoids.
local function between(a: Vector3, b: Vector3): (CFrame, number)
	local look = (b - a).Unit
	local right = Vector3.xAxis - look * Vector3.xAxis:Dot(look)
	if right.Magnitude < 1e-3 then
		right = Vector3.zAxis
	end
	right = right.Unit
	return CFrame.fromMatrix((a + b) / 2, right, right:Cross(look)), (b - a).Magnitude
end

local function slab(model: Model, chassis: BasePart, name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local cf, len = between(a, b)
	return visual(model, chassis, name, Vector3.new(width, thick, len), cf, color, material)
end

local function ellipsoidBetween(model: Model, chassis: BasePart, name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local cf, len = between(a, b)
	return ellipsoid(model, chassis, name, Vector3.new(width, thick, len), cf, color, material)
end

-- The face of a part (placed at `offset` in the kart) that points most along `dir`.
local function faceToward(offset: CFrame, dir: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -math.huge
	type Face = { id: Enum.NormalId, n: Vector3 }
	local faces: { Face } = {
		{ id = Enum.NormalId.Right, n = offset.RightVector },
		{ id = Enum.NormalId.Left, n = -offset.RightVector },
		{ id = Enum.NormalId.Top, n = offset.UpVector },
		{ id = Enum.NormalId.Bottom, n = -offset.UpVector },
		{ id = Enum.NormalId.Back, n = -offset.LookVector },
		{ id = Enum.NormalId.Front, n = offset.LookVector },
	}
	for _, f in faces do
		local d = f.n:Dot(dir)
		if d > bestDot then
			best, bestDot = f.id, d
		end
	end
	return best
end

-- A number panel: black plate with white digits, the digits on the face
-- that points along `dir` (kart-local).
local function numberPanel(model: Model, chassis: BasePart, name: string, size: Vector3, offset: CFrame, dir: Vector3, number: number)
	local plate = visual(model, chassis, name, size, offset, Color3.fromRGB(16, 16, 18))
	surfaceText(plate, faceToward(offset, dir), tostring(number), Color3.fromRGB(245, 245, 245), 60)
end

-- Bodywork modelled on a modern rental kart (the Sodi RT8 / SR5 kind):
-- one continuous black plastic bumper wraps round the whole kart, outside
-- all four wheels, so wheels never touch. Inside it: a tall hollow nose with
-- the number on top, flat side pods, guards over the rear wheels, a bucket
-- seat with a padded roll bar behind it, a translucent fuel tank between the
-- driver's knees and a 4-stroke engine on the right with its silencer
-- behind. The bumper ring is the same rounded rectangle the physics uses
-- for kart-to-kart contact (Config.Kart.Bumper). Wheels and the steering
-- wheel are drawn by each client (KartVisuals) because they move.
local function bodywork(model: Model, chassis: BasePart, number: number, color: Color3)
	local FRAME = Color3.fromRGB(72, 74, 80)
	local ALU = Color3.fromRGB(160, 164, 172)
	local BLACK = Color3.fromRGB(24, 24, 28)
	local PLASTIC = Color3.fromRGB(30, 31, 35)
	local DARK = Color3.fromRGB(46, 48, 54)
	local WHITE = Color3.fromRGB(242, 242, 242)
	local tubeD = 0.12
	local railH = 0.24

	----------------------------------------------------------------------
	-- Frame (powder-coated), mostly hidden under the plastic
	----------------------------------------------------------------------
	for _, s in { -1, 1 } do
		tube(model, chassis, "Rail", pt(s * 0.5, railH, 2.7), pt(s * 0.72, railH, 1.55), tubeD, FRAME)
		tube(model, chassis, "Rail", pt(s * 0.72, railH, 1.55), pt(s * 1.02, railH, 0.15), tubeD, FRAME)
		tube(model, chassis, "Rail", pt(s * 1.02, railH, 0.15), pt(s * 1.08, railH, -1.25), tubeD, FRAME)
		tube(model, chassis, "Rail", pt(s * 1.08, railH, -1.25), pt(s * 0.85, railH, -2.1), tubeD, FRAME)
		-- spindle carriers, kingpin, stub axle, steering arm and track rod
		tube(model, chassis, "CBracket", pt(s * 0.5, railH, 2.25), pt(s * 1.58, 0.36, 2.2), tubeD, FRAME)
		tube(model, chassis, "CBracket", pt(s * 0.55, railH, 2.45), pt(s * 1.58, 0.88, 2.22), tubeD * 0.9, FRAME)
		tube(model, chassis, "Kingpin", pt(s * 1.64, 0.3, 2.24), pt(s * 1.64, 0.94, 2.18), 0.15, BLACK)
		tube(model, chassis, "StubAxle", pt(s * 1.64, 0.62, 2.2), pt(s * 1.86, 0.62, 2.2), 0.12, ALU)
		tube(model, chassis, "SteeringArm", pt(s * 1.62, 0.5, 2.2), pt(s * 1.45, 0.46, 1.92), 0.08, ALU)
		tube(model, chassis, "TrackRod", pt(s * 0.12, 0.36, 2.0), pt(s * 1.45, 0.46, 1.92), 0.07, ALU)
		ellipsoid(model, chassis, "RodEnd", Vector3.one * 0.13, at(s * 1.45, 0.46, 1.92), BLACK)
		-- outriggers carrying the bumper ring
		tube(model, chassis, "BumperMount", pt(s * 0.75, railH, 1.4), pt(s * 2.95, 0.3, 1.32), tubeD, FRAME)
		tube(model, chassis, "BumperMount", pt(s * 1.05, railH, -0.6), pt(s * 2.95, 0.3, -0.62), tubeD, FRAME)
		tube(model, chassis, "BumperMount", pt(s * 0.5, railH, 2.7), pt(s * 1.2, 0.3, 3.4), tubeD, FRAME)
		tube(model, chassis, "BumperMount", pt(s * 0.85, railH, -2.1), pt(s * 1.4, 0.3, -2.65), tubeD, FRAME)
		-- rear bearing carriers and hubs
		visual(model, chassis, "BearingCarrier", Vector3.new(0.26, 0.6, 0.48), at(s * 1.1, 0.68, -1.6), ALU, Enum.Material.Metal)
		tube(model, chassis, "Upright", pt(s * 1.1, railH, -1.25), pt(s * 1.1, 0.5, -1.55), tubeD, FRAME)
		disc(model, chassis, "RearHub", pt(s * 1.62, 0.7, -1.6), Vector3.xAxis, 0.22, 0.32, ALU, Enum.Material.Metal)
	end
	for _, f in { 2.7, 2.25 } do
		tube(model, chassis, "Cross", pt(-0.5, railH, f), pt(0.5, railH, f), tubeD, FRAME)
	end
	tube(model, chassis, "Cross", pt(-1.04, railH, -0.3), pt(1.04, railH, -0.3), tubeD, FRAME)
	tube(model, chassis, "Cross", pt(-0.85, railH, -2.1), pt(0.85, railH, -2.1), tubeD, FRAME)
	-- rear axle, brake disc and caliper on the left, sprocket on the right
	tube(model, chassis, "RearAxle", pt(-1.9, 0.7, -1.6), pt(1.9, 0.7, -1.6), 0.18, ALU)
	disc(model, chassis, "BrakeDisc", pt(-0.5, 0.7, -1.6), Vector3.xAxis, 0.38, 0.09, Color3.fromRGB(90, 92, 98), Enum.Material.Metal)
	visual(model, chassis, "Caliper", Vector3.new(0.3, 0.3, 0.38), at(-0.5, 1.02, -1.52), Color3.fromRGB(200, 40, 30), Enum.Material.Metal)
	disc(model, chassis, "Sprocket", pt(0.92, 0.7, -1.6), Vector3.xAxis, 0.3, 0.05, BLACK, Enum.Material.Metal)
	-- floor tray and pedals (rubber-capped)
	visual(model, chassis, "FloorTray", Vector3.new(1.45, 0.05, 2.75), at(0, 0.19, 1.15), DARK, Enum.Material.Metal)
	for _, s in { -1, 1 } do
		visual(model, chassis, "Pedal", Vector3.new(0.28, 0.42, 0.07), at(s * 0.28, 0.46, 2.38) * CFrame.Angles(math.rad(-22), 0, 0), BLACK, Enum.Material.Rubber)
	end

	----------------------------------------------------------------------
	-- The bumper ring: one chunky plastic wall round the whole kart,
	-- following the rounded rectangle in Config.Kart.Bumper (outer face)
	----------------------------------------------------------------------
	local bm = cfg.Bumper
	local thick = 0.38
	local wallLo, wallHi = 0.14, 0.8
	do
		local inset = thick / 2
		local W, F, R = bm.HalfWidth - inset, bm.Front - inset, bm.Rear - inset
		local c = math.max(bm.Corner - inset, 0.05)
		-- centre line of the wall as a closed polyline (x, f)
		local pts: { Vector2 } = {}
		local function corner(cx: number, cf: number, a0: number)
			for k = 0, 3 do
				local a = a0 + (k / 3) * math.pi / 2
				table.insert(pts, Vector2.new(cx + math.cos(a) * c, cf + math.sin(a) * c))
			end
		end
		corner(W - c, F - c, 0)
		corner(-(W - c), F - c, math.pi / 2)
		corner(-(W - c), -R + c, math.pi)
		corner(W - c, -R + c, 3 * math.pi / 2)
		local midH = (wallLo + wallHi) / 2
		for i, a in pts do
			local b = pts[i % #pts + 1]
			local pa, pb = pt(a.X, midH, a.Y), pt(b.X, midH, b.Y)
			local len = (pb - pa).Magnitude
			if len > 0.02 then
				local cf = CFrame.lookAt((pa + pb) / 2, pb)
				visual(model, chassis, "BumperWall", Vector3.new(thick, wallHi - wallLo, len), cf, PLASTIC)
				-- rounded top lip and a slightly wider foot
				tube(model, chassis, "BumperLip", pt(a.X, wallHi, a.Y), pt(b.X, wallHi, b.Y), thick + 0.04, PLASTIC, Enum.Material.SmoothPlastic)
				visual(model, chassis, "BumperFoot", Vector3.new(thick + 0.08, 0.1, len), cf * CFrame.new(0, wallLo - midH + 0.05, 0), BLACK)
			end
			-- round joint
			cylinderBetween(model, chassis, "BumperJoint", pt(a.X, wallLo, a.Y), pt(a.X, wallHi, a.Y), thick, 0, PLASTIC, Enum.Material.SmoothPlastic)
		end
	end
	local outerX = bm.HalfWidth
	-- taller guards over the outside of the rear wheels
	for _, s in { -1, 1 } do
		local x = s * (outerX - thick / 2)
		visual(model, chassis, "RearGuard", Vector3.new(thick, 0.36, 2.2), at(x, wallHi + 0.2, -1.62), PLASTIC)
		tube(model, chassis, "RearGuardLip", pt(x, wallHi + 0.38, -2.7), pt(x, wallHi + 0.38, -0.54), thick + 0.04, PLASTIC, Enum.Material.SmoothPlastic)
		for _, f in { -2.72, -0.52 } do
			ellipsoid(model, chassis, "RearGuardEnd", Vector3.new(thick + 0.04, 0.74, 0.5), at(x, wallHi + 0.2, f), PLASTIC)
		end
		-- colour stripe along the guard
		visual(model, chassis, "GuardStripe", Vector3.new(0.03, 0.16, 2.0), at(s * (outerX + 0.005), wallHi + 0.18, -1.62), color)
	end
	-- colour stripes along the outside of the ring, and a white pinstripe
	for _, s in { -1, 1 } do
		visual(model, chassis, "RingStripe", Vector3.new(0.03, 0.12, 3.0), at(s * (outerX + 0.005), 0.5, 1.0), color)
		visual(model, chassis, "RingPinstripe", Vector3.new(0.03, 0.04, 3.0), at(s * (outerX + 0.005), 0.62, 1.0), WHITE)
	end
	visual(model, chassis, "FrontStripe", Vector3.new(4.2, 0.12, 0.03), at(0, 0.5, bm.Front + 0.005), color)

	----------------------------------------------------------------------
	-- Front deck between the bumper and the front wheels, hollow nose
	----------------------------------------------------------------------
	local deckF0, deckF1 = 2.95, bm.Front - thick
	local deck = visual(model, chassis, "FrontDeck", Vector3.new(2 * (outerX - thick) - 0.1, 0.12, deckF1 - deckF0), at(0, 0.66, (deckF0 + deckF1) / 2), PLASTIC)
	surfaceText(deck, Enum.NormalId.Top, "A1", Color3.fromRGB(150, 152, 160), 30)
	local noseLow, noseHigh = pt(0, 0.7, 3.45), pt(0, 1.46, 1.86)
	local noseCF, noseLen = between(noseLow, noseHigh)
	visual(model, chassis, "NoseTop", Vector3.new(1.5, 0.12, noseLen), noseCF, PLASTIC)
	-- rounded leading edge of the nose
	tube(model, chassis, "NoseEdge", pt(-0.75, 0.7, 3.45), pt(0.75, 0.7, 3.45), 0.24, PLASTIC, Enum.Material.SmoothPlastic)
	-- side walls (open underneath and at the back for the driver's legs)
	for _, s in { -1, 1 } do
		visual(model, chassis, "NoseSide", Vector3.new(0.08, 0.72, 1.6), at(s * 0.73, 0.68 + 0.36, 2.66), PLASTIC, nil, "WedgePart")
		-- colour flash along the top edge of each side
		local a, b = pt(s * 0.77, 0.78, 3.38), pt(s * 0.77, 1.4, 1.92)
		slab(model, chassis, "NoseFlash", a, b, 0.03, 0.2, color)
		slab(model, chassis, "NosePinstripe", a + Vector3.new(0, -0.16, 0), b + Vector3.new(0, -0.16, 0), 0.03, 0.05, WHITE)
	end
	-- the number on the nose, facing up and forward
	numberPanel(model, chassis, "NoseNumber", Vector3.new(0.9, 0.02, 0.72), noseCF * CFrame.new(0, 0.07, -0.05), (Vector3.yAxis - Vector3.zAxis).Unit, number)
	visual(model, chassis, "NoseNumberRing", Vector3.new(1.04, 0.015, 0.86), noseCF * CFrame.new(0, 0.065, -0.05), color)

	-- steering column (the wheel and its display are drawn by KartVisuals)
	local sw = cfg.SteeringWheel
	local tilt = math.rad(sw.Tilt)
	local hubH = sw.Height - math.sin(tilt) * 0.12
	local hubF = sw.Forward + math.cos(tilt) * 0.12
	local run = (hubH - 0.45) / math.sin(tilt)
	tube(model, chassis, "Column", pt(0, 0.45, hubF + run * math.cos(tilt)), pt(0, hubH, hubF), 0.14, FRAME)

	-- translucent fuel tank between the knees
	local tank = ellipsoid(model, chassis, "FuelTank", Vector3.new(0.6, 0.5, 1.0), at(0, 0.46, 1.1), Color3.fromRGB(236, 212, 120))
	tank.Transparency = 0.15
	disc(model, chassis, "FuelCap", pt(0, 0.72, 1.35), Vector3.yAxis, 0.1, 0.08, BLACK)

	----------------------------------------------------------------------
	-- Side pods: flat plastic between the seat and the bumper ring
	----------------------------------------------------------------------
	for _, s in { -1, 1 } do
		local x0, x1 = 1.3, outerX - thick + 0.02
		local f0, f1 = -0.78, 1.46
		local cx = s * (x0 + x1) / 2
		local top = 0.82
		visual(model, chassis, "SidePod", Vector3.new(x1 - x0, 0.12, f1 - f0), at(cx, top - 0.06, (f0 + f1) / 2), PLASTIC)
		-- inner wall down to the floor, with a rounded edge where the arm rests
		visual(model, chassis, "SidePodWall", Vector3.new(0.08, top - railH, f1 - f0), at(s * x0, (top + railH) / 2, (f0 + f1) / 2), PLASTIC)
		tube(model, chassis, "SidePodEdge", pt(s * x0, top, f0), pt(s * x0, top, f1), 0.18, PLASTIC, Enum.Material.SmoothPlastic)
		-- colour panel on top with a white pinstripe
		visual(model, chassis, "SidePodPanel", Vector3.new(x1 - x0 - 0.35, 0.02, f1 - f0 - 0.4), at(cx, top + 0.005, (f0 + f1) / 2), color)
		visual(model, chassis, "SidePodPinstripe", Vector3.new(0.05, 0.022, f1 - f0 - 0.4), at(s * (x0 + 0.24), top + 0.006, (f0 + f1) / 2), WHITE)
		numberPanel(model, chassis, "SideNumber", Vector3.new(0.7, 0.02, 0.62), at(s * (x0 + x1) / 2 + s * 0.15, top + 0.02, 0.65), Vector3.yAxis, number)
	end

	----------------------------------------------------------------------
	-- Rear: deck over the bumper behind the axle, number on the back
	----------------------------------------------------------------------
	local rearDeckF0, rearDeckF1 = -(bm.Rear - thick), -2.38
	visual(model, chassis, "RearDeck", Vector3.new(2 * (outerX - thick), 0.12, rearDeckF1 - rearDeckF0), at(0, 0.72, (rearDeckF0 + rearDeckF1) / 2), PLASTIC)
	numberPanel(model, chassis, "RearNumber", Vector3.new(0.9, 0.42, 0.03), at(0, 0.48, -bm.Rear - 0.02), Vector3.zAxis, number)
	visual(model, chassis, "RearStripe", Vector3.new(4.6, 0.12, 0.03), at(0, 0.74, -bm.Rear - 0.012), color)

	----------------------------------------------------------------------
	-- Seat and roll bar
	----------------------------------------------------------------------
	local SEAT = Color3.fromRGB(28, 30, 36)
	ellipsoid(model, chassis, "SeatPan", Vector3.new(1.3, 0.3, 1.2), at(0, 0.5, -0.6), SEAT, Enum.Material.SmoothPlastic)
	slab(model, chassis, "SeatBack", pt(0, 0.62, -1.0), pt(0, 1.92, -1.48), 1.3, 0.12, SEAT, Enum.Material.SmoothPlastic)
	ellipsoidBetween(model, chassis, "SeatTop", pt(0, 1.8, -1.43), pt(0, 2.08, -1.54), 1.3, 0.18, SEAT, Enum.Material.SmoothPlastic)
	for _, s in { -1, 1 } do
		ellipsoidBetween(model, chassis, "SeatSide", pt(s * 0.64, 0.48, -0.45), pt(s * 0.64, 1.55, -1.28), 0.12, 0.5, SEAT, Enum.Material.SmoothPlastic)
		tube(model, chassis, "SeatMount", pt(s * 0.45, 0.42, -0.25), pt(s * 1.02, railH, -0.1), 0.08, FRAME)
	end
	-- roll bar: a hoop behind the seat, braced back to the frame, padded top
	local barF, barTop = -1.78, 2.62
	for _, s in { -1, 1 } do
		tube(model, chassis, "RollBar", pt(s * 0.72, railH, barF), pt(s * 0.62, barTop - 0.15, barF), 0.13, BLACK)
		tube(model, chassis, "RollBar", pt(s * 0.62, barTop - 0.15, barF), pt(s * 0.4, barTop, barF), 0.13, BLACK)
		tube(model, chassis, "RollBarBrace", pt(s * 0.62, barTop - 0.3, barF), pt(s * 0.85, railH + 0.05, -2.32), 0.1, BLACK)
	end
	tube(model, chassis, "RollBar", pt(-0.4, barTop, barF), pt(0.4, barTop, barF), 0.13, BLACK)
	visual(model, chassis, "RollBarPad", Vector3.new(0.7, 0.62, 0.22), at(0, barTop - 0.38, barF + 0.12), Color3.fromRGB(40, 40, 46), Enum.Material.Fabric)

	----------------------------------------------------------------------
	-- 4-stroke engine on the right of the seat, silencer behind it
	----------------------------------------------------------------------
	local ENGINE = Color3.fromRGB(150, 154, 160)
	visual(model, chassis, "EngineMount", Vector3.new(0.75, 0.1, 0.95), at(1.32, 0.3, -1.05), ALU, Enum.Material.Metal)
	visual(model, chassis, "Crankcase", Vector3.new(0.72, 0.62, 0.86), at(1.36, 0.66, -1.05), ENGINE, Enum.Material.Metal)
	-- cylinder leaning towards the outside, with a black valve cover
	local cylCF = at(1.6, 1.12, -1.0) * CFrame.Angles(0, 0, math.rad(-25))
	visual(model, chassis, "Cylinder", Vector3.new(0.5, 0.5, 0.56), cylCF, Color3.fromRGB(176, 180, 188), Enum.Material.Metal)
	visual(model, chassis, "ValveCover", Vector3.new(0.52, 0.16, 0.58), cylCF * CFrame.new(0, 0.32, 0), BLACK, Enum.Material.SmoothPlastic)
	-- recoil starter facing forward, air filter on top towards the seat
	disc(model, chassis, "Starter", pt(1.36, 0.72, -0.56), Vector3.zAxis, 0.3, 0.1, Color3.fromRGB(190, 30, 30))
	disc(model, chassis, "StarterCup", pt(1.36, 0.72, -0.5), Vector3.zAxis, 0.12, 0.05, BLACK)
	local filter = visual(model, chassis, "AirFilter", Vector3.new(0.5, 0.42, 0.62), at(1.12, 1.2, -1.15), BLACK, Enum.Material.SmoothPlastic)
	surfaceText(filter, Enum.NormalId.Right, "AK 270", Color3.fromRGB(220, 220, 220), 40)
	-- chain from the clutch to the axle sprocket, under a guard
	tube(model, chassis, "Chain", pt(0.93, 0.85, -1.05), pt(0.93, 1.0, -1.6), 0.05, DARK)
	tube(model, chassis, "Chain", pt(0.93, 0.47, -1.05), pt(0.93, 0.4, -1.6), 0.05, DARK)
	visual(model, chassis, "ChainGuard", Vector3.new(0.05, 0.5, 0.75), at(0.84, 0.72, -1.32), BLACK, Enum.Material.SmoothPlastic)
	-- exhaust: header round the back to a silencer with a heat shield
	local PIPE = Color3.fromRGB(150, 140, 132)
	tube(model, chassis, "Header", pt(1.72, 1.0, -1.3), pt(1.6, 0.98, -2.0), 0.14, PIPE, Enum.Material.Metal)
	tube(model, chassis, "Silencer", pt(1.7, 1.02, -2.12), pt(0.45, 1.02, -2.12), 0.42, ALU, Enum.Material.Metal)
	visual(model, chassis, "HeatShield", Vector3.new(1.15, 0.05, 0.5), at(1.08, 1.27, -2.12), BLACK, Enum.Material.DiamondPlate)
	tube(model, chassis, "Tailpipe", pt(0.45, 1.0, -2.14), pt(0.3, 1.0, -2.22), 0.12, DARK)
end

function KartFactory.create(player: Player, number: number, cf: CFrame, color: Color3, anchored: boolean, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Kart_" .. player.UserId

	-- the root: a compact block that carries all the mass (sets the inertia)
	local core = cfg.CoreSize
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(core[1], core[2], core[3])
	chassis.CFrame = cf
	chassis.Transparency = 1
	chassis.CanCollide = false
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.Anchored = anchored
	chassis.RootPriority = 100
	chassis.CollisionGroup = "Karts"
	chassis.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, 0.12, 0.2, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- the collision shape: a massless box around the whole kart
	local box = cfg.BoxSize
	local hit = visual(model, chassis, "Hitbox", Vector3.new(box[1], box[2], box[3]), CFrame.new(0, cfg.BoxOffsetY, 0), Color3.new(1, 1, 1))
	hit.Transparency = 1
	hit.CanCollide = true
	hit.CollisionGroup = "Karts"
	hit.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.12, 0.2, 1, 1)

	-- forces set by the driving client every frame
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = chassis
	local vf = Instance.new("VectorForce")
	vf.Name = "Drive"
	vf.Attachment0 = center
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = chassis
	local tq = Instance.new("Torque")
	tq.Name = "Spin"
	tq.Attachment0 = center
	tq.RelativeTo = Enum.ActuatorRelativeTo.World
	tq.Torque = Vector3.zero
	tq.Parent = chassis

	bodywork(model, chassis, number, color)

	-- the seat the character sits on (cannot be sat on by touching it)
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.4, 0.3, 1.2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false
	seat.Massless = true
	seat.Anchored = false
	seat.CFrame = chassis.CFrame * at(0, 0.82, -0.5)
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = chassis
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = model

	-- name above the kart
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(180, 36)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 5.6, 0)
	tag.MaxDistance = 140
	tag.LightInfluence = 0
	tag.Parent = chassis
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Text = string.format("%d  %s", number, player.DisplayName)
	nameLabel.Parent = tag

	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Number", number)
	model:SetAttribute("Color", color)
	model.Parent = parent
	return model
end

local function setCharacterParts(character: Model, group: string, massless: boolean)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
			d.Massless = massless
		end
	end
end

KartFactory.setCharacterParts = setCharacterParts

-- Seats the player's character in the kart. Returns true when seated.
function KartFactory.seat(model: Model, player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = model:FindFirstChild("DriverSeat") :: Seat?
	if not (character and humanoid and seat) or humanoid.Health <= 0 then
		return false
	end
	if humanoid.SeatPart and humanoid.SeatPart ~= seat then
		humanoid.Sit = false
		task.wait()
	end
	setCharacterParts(character, "Drivers", true)
	seat:Sit(humanoid)
	return true
end

-- Gives physics control of an unanchored kart to its driver.
function KartFactory.handOver(model: Model, player: Player)
	local chassis = model.PrimaryPart
	if chassis and not chassis.Anchored and chassis:CanSetNetworkOwnership() then
		chassis:SetNetworkOwner(player)
	end
end

-- Moves a kart to a pose (pos on the road surface), stopped and unanchored,
-- then hands it back to the driver. Used for grid placement and resets.
function KartFactory.place(model: Model, player: Player?, pos: Vector3, fwd: Vector3, up: Vector3, anchored: boolean)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	chassis.Anchored = true
	local center = pos + up * (cfg.RideHeight + 0.15)
	model:PivotTo(CFrame.lookAt(center, center + fwd, up))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	if not anchored then
		chassis.Anchored = false
		if player then
			KartFactory.handOver(model, player)
		end
	end
end

-- Restores a character that leaves a kart.
function KartFactory.release(player: Player)
	local character = player.Character
	if character then
		setCharacterParts(character, "Players", false)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = false
		end
	end
end

return KartFactory
