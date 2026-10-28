--!strict
-- Draws the moving parts of every kart on this client: wheels that follow
-- the suspension, steer and spin, the steering wheel, tyre smoke and skid
-- marks, and (own kart, cockpit view only) the driver's arms and gloves on
-- the wheel. In ghost qualifying the other karts and their drivers are
-- see-through. Purely visual and local, so nothing here touches physics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local KartPhysics = require(Shared:WaitForChild("KartPhysics"))
local KartController = require(script.Parent:WaitForChild("KartController"))
local Input = require(script.Parent:WaitForChild("Input"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local KartVisuals = {}

local cfg = Config.Kart
local geo = KartPhysics.geometry(cfg)
local player = Players.LocalPlayer

type Wheel = { tyre: BasePart, shoulder: BasePart, rim: BasePart, hub: BasePart, smoke: Smoke?, spin: number, lastMark: Vector3?, spec: KartPhysics.WheelSpec }
type Piece = { part: BasePart, offset: CFrame }
type Arm = { sleeve: BasePart, glove: BasePart, shoulder: Vector3, angle: number }
type Visual = {
	model: Model,
	chassis: BasePart,
	folder: Folder,
	wheels: { Wheel },
	steering: { Piece },
	arms: { Arm }?,
	display: TextLabel?,
	displayAt: number,
	ghost: boolean?, -- drawn see-through (KartVisuals ghosts)
	steer: number,
	engine: Sound?,
	skid: Sound?,
	offroad: Sound?,
	kerb: Sound?,
	rpm: number,
}

local SW = cfg.SteeringWheel
local COCKPIT = Config.Camera.Cockpit
local cockpitOn = false

-- The camera tells us when the local player looks from the cockpit; then the
-- avatar's own arms are hidden and these arms hold the wheel instead.
function KartVisuals.setCockpit(on: boolean)
	cockpitOn = on
end

local AUDIO = Config.Audio

-- engines play in the Engine sound group, skids in Effects (settings volumes)
local function loopSound(parent: Instance, name: string, id: string?, volume: number, group: string): Sound?
	if id == nil or id == "" then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.SoundId = id
	snd.Looped = true
	snd.Volume = volume
	snd.RollOffMinDistance = 12
	snd.RollOffMaxDistance = 220
	snd.SoundGroup = Sfx.group(group)
	snd.Parent = parent
	snd:Play()
	return snd
end

-- what a wheel on this part sounds like: "kerb", or how loud the off-road
-- rumble is on it (gravel full, water and grass less), or nil on the road
local SURFACE_SOUND: { [string]: any } = { Kerb = "kerb", Gravel = 1, Water = 0.8, Grass = 0.6, Turf = 0.6 }
local surfaceSounds: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local function surfaceSound(inst: Instance): any
	local s = surfaceSounds[inst]
	if s == nil then
		local name = inst:GetAttribute("Surface")
		s = (if type(name) == "string" then SURFACE_SOUND[name] else nil) or false
		surfaceSounds[inst] = s
	end
	return if s == false then nil else s
end
-- road speed (studs/s) at which kerb_loop.ogg's 12 blocks a second match
-- the kerb's red/white blocks (one per ~6 stud track sample)
local KERB_RATE = 72

local visuals: { [Model]: Visual } = {}
local root: Folder
local marks: Folder
local markPool: { BasePart } = {}
local markIndex = 0
local MAX_MARKS = 450

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

local function decor(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function build(model: Model)
	local chassis = model:WaitForChild("Chassis", 5) :: BasePart?
	if not chassis or visuals[model] then
		return
	end
	local color = (model:GetAttribute("Color") :: Color3?) or Color3.new(1, 1, 1)
	local folder = Instance.new("Folder")
	folder.Name = model.Name
	folder.Parent = root
	local wheels: { Wheel } = {}
	for _, spec in cfg.Wheels do
		local width = spec.width
		-- slick tyre: a full-radius tread plus a slightly smaller, full-width
		-- body so the shoulders look rounded; magnesium rim and hub
		local tyre = decor(folder, {
			Name = "Tyre",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(width - 0.14, spec.radius * 2, spec.radius * 2),
			Color = Color3.fromRGB(26, 26, 28),
			Material = Enum.Material.Rubber,
		})
		local shoulder = decor(folder, {
			Name = "TyreShoulder",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(width, spec.radius * 2 - 0.12, spec.radius * 2 - 0.12),
			Color = Color3.fromRGB(32, 32, 35),
			Material = Enum.Material.Rubber,
		})
		local rim = decor(folder, {
			Name = "Rim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(width + 0.02, spec.radius * 1.12, spec.radius * 1.12),
			Color = Color3.fromRGB(196, 176, 118),
			Material = Enum.Material.Metal,
			CastShadow = false,
		})
		local hub = decor(folder, {
			Name = "Hub",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(width + 0.12, spec.radius * 0.42, spec.radius * 0.42),
			Color = Color3.fromRGB(150, 154, 162),
			Material = Enum.Material.Metal,
			CastShadow = false,
		})
		local smoke: Smoke? = nil
		if not spec.front then
			local s = Instance.new("Smoke")
			s.Color = Color3.fromRGB(225, 225, 225)
			s.Opacity = 0.12
			s.Size = 1.6
			s.RiseVelocity = 1.2
			s.TimeScale = 1
			s.Enabled = false
			s.Parent = tyre
			smoke = s
		end
		table.insert(wheels, { tyre = tyre, shoulder = shoulder, rim = rim, hub = hub, smoke = smoke, spin = 0, lastMark = nil, spec = spec })
	end
	-- Steering wheel: a rim of short tubes with three spokes and a hub, in a
	-- frame whose X axis is the column (pointing at the driver), Y is "up"
	-- on the wheel and Z points to the driver's left.
	local steering: { Piece } = {}
	local r = SW.Radius
	local segments = 12
	local segLen = 2 * r * math.sin(math.pi / segments) * 1.12
	for k = 0, segments - 1 do
		local a = (k + 0.5) / segments * 2 * math.pi
		local at = Vector3.new(0, r * math.cos(a), r * math.sin(a))
		local tangent = Vector3.new(0, -math.sin(a), math.cos(a))
		-- padded grips where the hands go (left and right of the rim)
		local grip = math.abs(math.cos(a)) < 0.6
		local part = decor(folder, {
			Name = "WheelRim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(segLen, if grip then 0.19 else 0.14, if grip then 0.19 else 0.14),
			Color = Color3.fromRGB(22, 22, 24),
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
		})
		table.insert(steering, { part = part, offset = CFrame.fromMatrix(at, tangent, Vector3.xAxis) })
	end
	for _, a in { math.pi / 2, -math.pi / 2, math.pi } do
		local dir = Vector3.new(0, math.cos(a), math.sin(a))
		local part = decor(folder, {
			Name = "WheelSpoke",
			Size = Vector3.new(0.05, r, 0.12),
			Color = Color3.fromRGB(150, 154, 162),
			Material = Enum.Material.Metal,
			CastShadow = false,
		})
		table.insert(steering, { part = part, offset = CFrame.fromMatrix(dir * (r / 2), Vector3.xAxis, dir) })
	end
	local hubPart = decor(folder, {
		Name = "WheelHub",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, 0.42, 0.42),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	})
	table.insert(steering, { part = hubPart, offset = CFrame.new(0.04, 0, 0) })
	-- data logger on the hub, facing the driver (speed readout)
	local displayPart = decor(folder, {
		Name = "WheelDisplay",
		Size = Vector3.new(0.08, 0.26, 0.46),
		Color = Color3.fromRGB(18, 18, 20),
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	})
	table.insert(steering, { part = displayPart, offset = CFrame.new(0.12, 0.1, 0) })
	local screen = Instance.new("SurfaceGui")
	screen.Face = Enum.NormalId.Right
	screen.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	screen.PixelsPerStud = 120
	screen.LightInfluence = 0
	screen.Parent = displayPart
	local readout = Instance.new("TextLabel")
	readout.Size = UDim2.fromScale(0.86, 0.72)
	readout.Position = UDim2.fromScale(0.07, 0.14)
	readout.BackgroundColor3 = Color3.fromRGB(30, 46, 40)
	readout.TextColor3 = Color3.fromRGB(150, 255, 170)
	readout.Font = Enum.Font.Code
	readout.TextScaled = true
	readout.Text = "0"
	readout.Parent = screen

	-- cockpit arms for our own kart (hidden until the camera is in the cockpit)
	local arms: { Arm }? = nil
	if model:GetAttribute("Owner") == player.UserId then
		local list: { Arm } = {}
		arms = list
		local sh = COCKPIT.Shoulders
		for _, side in { -1, 1 } do
			local sleeve = decor(folder, {
				Name = "CockpitSleeve",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 0.3, 0.3),
				Color = color,
				Material = Enum.Material.Fabric,
				Transparency = 1,
				CastShadow = false,
			})
			local glove = decor(folder, {
				Name = "CockpitGlove",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.34, 0.34, 0.34),
				Color = Color3.fromRGB(28, 28, 32),
				Material = Enum.Material.Fabric,
				Transparency = 1,
				CastShadow = false,
			})
			table.insert(list, {
				sleeve = sleeve,
				glove = glove,
				shoulder = Vector3.new(side * sh[1], sh[2] - cfg.RideHeight, -sh[3]),
				-- hands at ten-to-two; +angle is the driver's left on the rim
				angle = -side * math.rad(52),
			})
		end
	end
	-- our own name tag would only clutter the chase camera
	if model:GetAttribute("Owner") == player.UserId then
		local tag = chassis:FindFirstChild("NameTag")
		if tag and tag:IsA("BillboardGui") then
			tag.Enabled = false
		end
	end
	visuals[model] = {
		model = model,
		chassis = chassis,
		folder = folder,
		wheels = wheels,
		steering = steering,
		arms = arms,
		display = readout,
		displayAt = 0,
		steer = 0,
		engine = loopSound(chassis, "EngineSound", AUDIO.EngineSoundId, AUDIO.EngineVolume, "Engine"),
		skid = loopSound(chassis, "SkidSound", AUDIO.SkidSoundId, 0, "Effects"),
		offroad = loopSound(chassis, "OffroadSound", AUDIO.OffroadSoundId, 0, "Effects"),
		kerb = loopSound(chassis, "KerbSound", AUDIO.KerbSoundId, 0, "Effects"),
		rpm = AUDIO.EngineRpmIdle,
	}
end

local function unbuild(model: Model)
	local v = visuals[model]
	if v then
		if v.engine then
			v.engine:Destroy()
		end
		for _, snd in { v.skid, v.offroad, v.kerb } do
			if snd then
				snd:Destroy()
			end
		end
		v.folder:Destroy()
		visuals[model] = nil
	end
end

local function skidMark(a: Vector3, b: Vector3, up: Vector3)
	local len = (b - a).Magnitude
	if len < 0.2 or len > 6 then
		return
	end
	markIndex = markIndex % MAX_MARKS + 1
	local p = markPool[markIndex]
	if not p then
		p = decor(marks, {
			Name = "Skid",
			Color = Color3.fromRGB(18, 18, 18),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.45,
			CastShadow = false,
		})
		markPool[markIndex] = p
	end
	local look = (b - a).Unit
	local right = look:Cross(up).Unit
	local realUp = right:Cross(look)
	p.Size = Vector3.new(0.55, 0.02, len + 0.1)
	p.CFrame = CFrame.fromMatrix((a + b) / 2 + realUp * 0.025, right, realUp, -look)
end

-- Ghosts: the other karts (body, wheels and driver) see-through while the
-- server says so: workspace attribute Ghost (qualifying, every kart) or a
-- kart's own Ghost attribute (just reset onto another kart).
local ghostAt = 0
local ghostOn = false
local function fade(root: Instance?, amount: number)
	if not root then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = amount
		end
	end
end

local function setGhost(model: Model, v: Visual, amount: number)
	fade(model, amount)
	fade(v.folder, amount)
	local owner = Players:GetPlayerByUserId((model:GetAttribute("Owner") :: number?) or 0)
	fade(owner and owner.Character, amount)
end

local function updateGhosts()
	local all = workspace:GetAttribute("Ghost") == true
	-- new karts and new characters turn up: refresh twice a second
	if all == ghostOn and os.clock() - ghostAt < 0.5 then
		return
	end
	ghostAt = os.clock()
	local mine = KartController.kart()
	local amount = Config.Race.GhostTransparency
	for model, v in visuals do
		if model ~= mine then
			local on = all or model:GetAttribute("Ghost") == true
			if on then
				setGhost(model, v, amount)
			elseif v.ghost then
				setGhost(model, v, 0)
			end
			v.ghost = on
		end
	end
	if ghostOn and not all then
		-- the drivers outlive their qualifying karts (new karts on the grid)
		for _, p in Players:GetPlayers() do
			if p ~= Players.LocalPlayer then
				fade(p.Character, 0)
			end
		end
	end
	ghostOn = all
end

local function update(dt: number)
	updateGhosts()
	local mine = KartController.kart()
	local tele = KartController.telemetry()
	for model, v in visuals do
		local c = v.chassis
		if not c.Parent then
			continue
		end
		local cf = c.CFrame
		local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
		local vel = c.AssemblyLinearVelocity
		local fwdSpeed = vel:Dot(look)
		local ownTele = if model == mine then tele else nil

		-- steering angle: own kart from the model, others estimated from yaw rate
		local steer: number
		if ownTele then
			steer = ownTele.steerAngle
		else
			local yaw = c.AssemblyAngularVelocity:Dot(up)
			local target = if math.abs(fwdSpeed) > 2 then math.atan(-yaw * geo.wheelbase / fwdSpeed) else 0
			target = math.clamp(target, -math.rad(cfg.SteerLock), math.rad(cfg.SteerLock))
			steer = v.steer + (target - v.steer) * math.min(dt * 10, 1)
		end
		v.steer = steer

		-- body slip for smoke on other karts
		local slipAngle = 0
		if vel.Magnitude > 12 then
			slipAngle = math.deg(math.acos(math.clamp(vel.Unit:Dot(look), -1, 1)))
		end

		local anySliding = false
		-- wheels on the kerbs, and how much of the kart is off the road
		local hearSurface = v.offroad ~= nil or v.kerb ~= nil
		local onKerb, offRoad = 0, 0
		for i, w in v.wheels do
			local spec = w.spec
			local mount = cf.Position + right * spec.x + look * spec.f
			local dist: number
			local sliding = false
			local r: RaycastResult? = nil
			if ownTele then
				local wt = ownTele.wheels[i]
				dist = wt.hitDist
				sliding = wt.contact and (wt.usage > 1.03 or wt.spinning or wt.locked)
				if hearSurface and wt.contact then
					r = workspace:Raycast(mount, -up * geo.rayLength, rayParams)
				end
			else
				r = workspace:Raycast(mount, -up * geo.rayLength, rayParams)
				dist = if r then r.Distance else geo.rayLength
				sliding = r ~= nil and slipAngle > 9 and not spec.front
			end
			if hearSurface and r then
				local kind = surfaceSound(r.Instance)
				if kind == "kerb" then
					onKerb += 1
				elseif kind then
					offRoad += kind
				end
			end
			dist = math.clamp(dist, spec.radius * 0.6, geo.rayLength)
			local center = mount - up * (dist - spec.radius)
			local wheelSteer = 0
			if spec.front then
				wheelSteer = if ownTele then ownTele.wheels[i].steer else steer
			end
			-- axle direction: chassis right, turned by the steering angle
			local axle = (right * math.cos(wheelSteer) - look * math.sin(wheelSteer))
			local spinRate = (if ownTele then ownTele.wheels[i].longSpeed else fwdSpeed) / spec.radius
			if ownTele and ownTele.wheels[i].spinning then
				spinRate = math.max(spinRate, 60)
			end
			w.spin = (w.spin + spinRate * dt) % (2 * math.pi)
			local side = if spec.x < 0 then -1 else 1
			local base = CFrame.fromMatrix(center, axle, up)
			w.tyre.CFrame = base * CFrame.Angles(-w.spin, 0, 0)
			w.shoulder.CFrame = w.tyre.CFrame
			w.rim.CFrame = base * CFrame.Angles(-w.spin, 0, 0)
			w.hub.CFrame = base * CFrame.new(side * 0.04, 0, 0)
			if w.smoke then
				w.smoke.Enabled = sliding and math.abs(fwdSpeed) > 6
			end
			anySliding = anySliding or (sliding and math.abs(fwdSpeed) > 6)
			-- skid marks where the tyre slides on the ground
			local contact = center - up * spec.radius
			if sliding and dist < geo.rayLength - 0.01 then
				if w.lastMark then
					local d = (contact - w.lastMark).Magnitude
					if d > 1.2 then
						skidMark(w.lastMark, contact, up)
						w.lastMark = contact
					end
				else
					w.lastMark = contact
				end
			else
				w.lastMark = nil
			end
		end

		-- engine revs: a rental kart's one gear and centrifugal clutch. On the
		-- throttle the clutch slips at EngineRpmClutch until the road speed
		-- takes the revs higher; off it the revs stay with the road until the
		-- clutch lets go (EngineRpmRelease), then it idles. A little higher when
		-- the rear wheels spin. Other karts: on the throttle whenever they move.
		local speed = math.abs(fwdSpeed)
		if v.engine then
			local roadRpm = AUDIO.EngineRpmMax * math.clamp(speed / cfg.TopSpeed, 0, 1.1)
			local throttle = if ownTele then Input.get().throttle elseif speed > 2 then 1 else 0
			local rpm: number
			if throttle > 0.05 then
				local slip = AUDIO.EngineRpmIdle + (AUDIO.EngineRpmClutch - AUDIO.EngineRpmIdle) * math.min(throttle * 1.5, 1)
				rpm = math.max(roadRpm, slip)
			else
				rpm = if roadRpm > AUDIO.EngineRpmRelease then roadRpm else AUDIO.EngineRpmIdle
			end
			if ownTele then
				for _, wt in ownTele.wheels do
					if wt.spinning then
						rpm += 500
						break
					end
				end
			end
			v.rpm += (rpm - v.rpm) * math.min(dt * 8, 1)
			v.engine.PlaybackSpeed = v.rpm / AUDIO.EngineRpmLoop
			v.engine.Volume = AUDIO.EngineVolume * (if ownTele then 0.55 + 0.45 * throttle else 0.8)
		end
		-- off the road: a rumble and gravel crunch that grows with speed
		if v.offroad then
			local target = AUDIO.OffroadVolume * math.clamp(offRoad / 4, 0, 1) * math.clamp(speed / 30, 0, 1)
			v.offroad.Volume += (target - v.offroad.Volume) * math.min(dt * 10, 1)
			v.offroad.PlaybackSpeed = 0.75 + 0.5 * math.clamp(speed / cfg.TopSpeed, 0, 1)
		end
		-- on the kerbs: the loop drums 12 blocks a second at KERB_RATE studs/s
		if v.kerb then
			local target = AUDIO.KerbVolume * math.clamp(onKerb / 2, 0, 1) * math.clamp(speed / 15, 0, 1)
			v.kerb.Volume += (target - v.kerb.Volume) * math.min(dt * 14, 1)
			v.kerb.PlaybackSpeed = math.clamp(speed / KERB_RATE, 0.4, 1.6)
		end
		if v.skid then
			local target = if anySliding then AUDIO.SkidVolume else 0
			v.skid.Volume += (target - v.skid.Volume) * math.min(dt * 12, 1)
		end

		-- steering wheel in front of the seat; its face points back and up at
		-- the driver and it turns with the front wheels
		local tilt = math.rad(SW.Tilt)
		local pos = cf:PointToWorldSpace(Vector3.new(0, SW.Height - cfg.RideHeight, -SW.Forward))
		local normal = cf:VectorToWorldSpace(Vector3.new(0, math.sin(tilt), math.cos(tilt)))
		local upward = cf:VectorToWorldSpace(Vector3.new(0, math.cos(tilt), -math.sin(tilt)))
		local wheelCF = CFrame.fromMatrix(pos, normal, upward) * CFrame.Angles(-steer * SW.Ratio, 0, 0)
		for _, piece in v.steering do
			piece.part.CFrame = wheelCF * piece.offset
		end
		-- the logger shows our speed (ten times a second is plenty)
		local display = v.display
		if display and model == mine and os.clock() - v.displayAt > 0.1 then
			v.displayAt = os.clock()
			display.Text = string.format("%d", math.floor(math.abs(fwdSpeed) * Config.KmhPerStudPerSecond + 0.5))
		end
		local arms = v.arms
		if arms then
			local show = cockpitOn and model == mine
			for _, arm in arms do
				local want = if show then 0 else 1
				if arm.glove.Transparency ~= want then
					arm.glove.Transparency = want
					arm.sleeve.Transparency = want
				end
				if show then
					local hand = wheelCF * Vector3.new(0.1, SW.Radius * math.cos(arm.angle), SW.Radius * math.sin(arm.angle))
					local shoulder = cf:PointToWorldSpace(arm.shoulder)
					local reach = hand - shoulder
					arm.glove.CFrame = CFrame.new(hand)
					arm.sleeve.Size = Vector3.new(math.max(reach.Magnitude - 0.1, 0.2), 0.3, 0.3)
					arm.sleeve.CFrame = CFrame.lookAt((hand + shoulder) / 2, hand) * CFrame.Angles(0, math.rad(90), 0)
				end
			end
		end
	end
end

function KartVisuals.init()
	root = Instance.new("Folder")
	root.Name = "KartVisuals"
	root.Parent = workspace
	marks = Instance.new("Folder")
	marks.Name = "SkidMarks"
	marks.Parent = root
	local function filter()
		local list: { Instance } = { workspace.Terrain }
		local circuit = workspace:FindFirstChild("Circuit")
		local track = circuit and circuit:FindFirstChild("Track")
		if track then
			table.insert(list, track)
		end
		rayParams.FilterDescendantsInstances = list
	end
	filter()
	workspace:GetAttributeChangedSignal("TrackReady"):Connect(filter)
	workspace:GetAttributeChangedSignal("Track"):Connect(function()
		filter()
		-- skid marks belong to the old circuit
		for _, p in markPool do
			p:Destroy()
		end
		table.clear(markPool)
		markIndex = 0
	end)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Circuit" then
			task.defer(filter)
		end
	end)
	local folder = workspace:WaitForChild("Karts")
	folder.ChildAdded:Connect(function(m)
		if m:IsA("Model") then
			task.spawn(build, m)
		end
	end)
	folder.ChildRemoved:Connect(function(m)
		if m:IsA("Model") then
			unbuild(m)
		end
	end)
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			task.spawn(build, m)
		end
	end
	RunService:BindToRenderStep("KartVisuals", Enum.RenderPriority.Camera.Value + 2, update)
	local _ = player
end

return KartVisuals
