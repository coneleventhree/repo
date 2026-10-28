--!strict
-- The driving camera.
--
--   zoom     mouse wheel, pinch, or D-pad up/down moves the camera from far
--            behind the kart all the way in; past the closest chase distance
--            it drops into the cockpit (first person, like a sim racer)
--   presets  C (gamepad X, CAM button) cycles cockpit / near / far
--   orbit    behind the kart: hold the right mouse button and drag (or the
--            right stick, or drag a finger on an empty part of the screen) to
--            swing the camera anywhere around the kart; it stays there and
--            keeps following the kart. V (gamepad R3) puts it back behind.
--   look     in the cockpit the same controls turn your head; the view
--            recentres when you let go
--
-- The cockpit view comes from CockpitRig (smoothed tilt, head sway and
-- glance, no bounce-back). The avatar's own head and arms are hidden there and
-- KartVisuals draws arms with gloves on the wheel instead. When not driving
-- the normal Roblox camera is used (optionally following another racer).
-- After a race everyone looks at the podium for a few seconds. The view you
-- start in is a setting (Cockpit / Near / Far).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CockpitRig = require(Shared:WaitForChild("CockpitRig"))
local KartController = require(script.Parent:WaitForChild("KartController"))
local KartVisuals = require(script.Parent:WaitForChild("KartVisuals"))
local Input = require(script.Parent:WaitForChild("Input"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local ChaseCamera = {}

local player = Players.LocalPlayer
local C = Config.Camera
local CP = C.Cockpit

-- zoom: 0 means cockpit, otherwise the chase distance
local zoomTarget = C.Distance
local zoom = C.Distance
local yawDir: Vector3? = nil
local fov = C.FovMin
local active = false
local spectateTarget: BasePart? = nil

-- behind the kart: orbit angles that stay put (radians)
local orbitYaw, orbitPitch = 0, 0
local recentering = false
local sinceOrbit = 0
-- in the cockpit: head look that springs back (radians)
local lookYaw, lookPitch = 0, 0

-- who is dragging the view right now
local mouseDragging = false
local touchDrag: InputObject? = nil
local stick = Vector2.zero

local rig = CockpitRig.new()

-- smooth cut between cockpit and chase
local blendFrom: CFrame? = nil
local blendFov = 70
local blendT = 1
local BLEND_TIME = 0.22

-- parts of our avatar hidden in the cockpit
local hidden: { [BasePart]: boolean } = {}
local lastHideScan = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function refreshFilter()
	local list: { Instance } = { workspace.Terrain }
	local circuit = workspace:FindFirstChild("Circuit")
	if circuit then
		table.insert(list, circuit)
	end
	rayParams.FilterDescendantsInstances = list
end

function ChaseCamera.isCockpit(): boolean
	return zoomTarget == 0
end

function ChaseCamera.zoom(): number
	return zoomTarget
end

function ChaseCamera.mode(): string
	return if zoomTarget == 0 then "Cockpit" else "Chase"
end

-- Orbit angles behind the kart (radians), for tests and the HUD.
function ChaseCamera.orbit(): (number, number)
	return orbitYaw, orbitPitch
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function vec(v: Vector3): vector
	return (v :: any) :: vector
end
local function v3(v: vector): Vector3
	return (v :: any) :: Vector3
end

local function startBlend()
	local camera = workspace.CurrentCamera
	if camera and active then
		blendFrom = camera.CFrame
		blendFov = camera.FieldOfView
		blendT = 0
	end
end

local function setZoom(target: number)
	local wasCockpit = zoomTarget == 0
	if target < C.MinDistance - 1e-6 then
		target = 0
	else
		target = math.clamp(target, C.MinDistance, C.MaxDistance)
	end
	zoomTarget = target
	if (target == 0) ~= wasCockpit then
		if target ~= 0 then
			zoom = target -- leave the cockpit straight at the chosen distance
		else
			rig = CockpitRig.new()
		end
		lookYaw, lookPitch = 0, 0
		startBlend()
	end
end

-- One step in (negative) or out (positive), as a mouse-wheel notch.
function ChaseCamera.zoomStep(notches: number)
	if notches == 0 then
		return
	end
	if zoomTarget == 0 then
		if notches > 0 then
			setZoom(C.MinDistance)
		end
		return
	end
	local target = zoomTarget * C.ZoomStep ^ notches
	if notches < 0 and zoomTarget <= C.MinDistance + 1e-6 then
		target = 0
	end
	setZoom(target)
end

function ChaseCamera.cycle()
	local presets = C.Presets
	local nextIndex = 1
	for i, z in presets do
		if math.abs(z - zoomTarget) < 0.5 or (zoomTarget > 0 and z > zoomTarget) then
			nextIndex = if math.abs(z - zoomTarget) < 0.5 then i % #presets + 1 else i
			break
		end
	end
	setZoom(presets[nextIndex])
end

-- Swing the camera back behind the kart (smoothly).
function ChaseCamera.recenter()
	recentering = true
end

-- Camera elevation behind the kart before any orbit (radians).
local function baseElevation(): number
	local d = math.max(zoomTarget, C.MinDistance)
	return math.atan2(C.HeightBase + C.HeightPerStud * d, d)
end

local function clampOrbitPitch(p: number): number
	local base = baseElevation()
	return math.clamp(p, math.rad(C.OrbitPitchMin) - base, math.rad(C.OrbitPitchMax) - base)
end

-- Turn the view by a drag of (dx, dy) pixels at `sens` degrees per pixel.
local function drag(dx: number, dy: number, sens: number)
	local s = math.rad(sens)
	if zoomTarget == 0 then
		lookYaw = math.clamp(lookYaw - dx * s, math.rad(-130), math.rad(130))
		lookPitch = math.clamp(lookPitch - dy * s, math.rad(-50), math.rad(60))
	else
		recentering = false
		sinceOrbit = 0
		orbitYaw = (orbitYaw - dx * s + math.pi) % (2 * math.pi) - math.pi
		orbitPitch = clampOrbitPitch(orbitPitch + dy * s)
	end
end
ChaseCamera.drag = drag

-- Hides (or shows again) our avatar's head, accessories and arms.
local ARM_PARTS = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	Head = true,
}
local function setAvatarHidden(on: boolean)
	if not on then
		for part in hidden do
			if part.Parent then
				part.LocalTransparencyModifier = 0
			end
		end
		table.clear(hidden)
		return
	end
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local parent = d.Parent
			if ARM_PARTS[d.Name] or (parent and parent:IsA("Accessory")) then
				d.LocalTransparencyModifier = 1
				hidden[d] = true
			end
		end
	end
end

local function stopDragging()
	if mouseDragging then
		mouseDragging = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	touchDrag = nil
end

local function restoreDefault(camera: Camera)
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = spectateTarget or humanoid
	setAvatarHidden(false)
	KartVisuals.setCockpit(false)
	stopDragging()
end

local function cockpitCFrame(chassis: BasePart, dt: number): CFrame
	local cf = chassis.CFrame
	local pose: CockpitRig.Pose = {
		pos = vec(cf.Position),
		right = vec(cf.RightVector),
		up = vec(cf.UpVector),
		look = vec(cf.LookVector),
		vel = vec(chassis.AssemblyLinearVelocity),
		angVel = vec(chassis.AssemblyAngularVelocity),
	}
	local eye, look, up = CockpitRig.step(CP :: any, rig, pose, Config.Kart.RideHeight, Config.Kart.Gravity, lookYaw, lookPitch, dt)
	local e, l, u = v3(eye), v3(look), v3(up)
	return CFrame.lookAt(e, e + l, u)
end

local function chaseCFrame(chassis: BasePart, dt: number): CFrame
	local cf = chassis.CFrame
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local heading = flat(cf.LookVector)
	-- follow the direction of travel when moving forwards fast (shows drifts),
	-- the nose otherwise
	local travel = flat(vel)
	local forwardMotion = vel:Dot(cf.LookVector) > 3
	local blend = if forwardMotion then math.clamp((speed - 10) / 30, 0, 0.6) else 0
	local desired = (heading * (1 - blend) + travel * blend).Unit
	local current = yawDir or desired
	local k = 1 - math.exp(-C.Stiffness * dt)
	current = (current + (desired - current) * k).Unit
	yawDir = current

	zoom += (zoomTarget - zoom) * (1 - math.exp(-C.ZoomSpeed * dt))
	local dist = zoom
	local height = C.HeightBase + C.HeightPerStud * dist
	local reach = math.sqrt(dist * dist + height * height)
	-- the orbit swings the camera around the kart; it keeps following the
	-- kart's heading, so a side view stays a side view through the corners
	local dir = CFrame.Angles(0, orbitYaw, 0):VectorToWorldSpace(current)
	local elev = math.clamp(math.atan2(height, dist) + orbitPitch, math.rad(C.OrbitPitchMin), math.rad(C.OrbitPitchMax))
	local ahead = C.LookAhead * math.max(math.cos(orbitYaw), 0) * math.cos(elev)
	local focus = chassis.Position + Vector3.new(0, 1.6, 0) + dir * ahead
	local want = chassis.Position - dir * (reach * math.cos(elev)) + Vector3.new(0, reach * math.sin(elev), 0)
	-- keep the camera out of walls, stands and the floor
	local from = chassis.Position + Vector3.new(0, 2, 0)
	local hit = workspace:Raycast(from, want - from, rayParams)
	if hit then
		want = hit.Position + hit.Normal * 0.8
	end
	return CFrame.lookAt(want, focus)
end

-- The podium camera (Scenery puts a "Camera" part by the podium), while the
-- results are shown and the top three stand on it.
local podiumOn = false
local podiumTime = 0
local function podiumCamera(): BasePart?
	if workspace:GetAttribute("RaceState") ~= "Results" or not workspace:GetAttribute("Podium") then
		return nil
	end
	local circuit = workspace:FindFirstChild("Circuit")
	local pits = circuit and circuit:FindFirstChild("Pits")
	local podium = pits and pits:FindFirstChild("Podium")
	local cam = podium and podium:FindFirstChild("Camera")
	if cam and cam:IsA("BasePart") then
		return cam
	end
	return nil
end

function ChaseCamera.isPodium(): boolean
	return podiumOn
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local podiumCam = podiumCamera()
	if podiumCam then
		if not podiumOn then
			podiumOn = true
			podiumTime = 0
			active = false
			setAvatarHidden(false)
			KartVisuals.setCockpit(false)
			stopDragging()
		end
		-- a slow push towards the steps
		podiumTime += dt
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = podiumCam.CFrame * CFrame.new(0, 0, -math.min(podiumTime, 10) * 0.5)
		camera.FieldOfView = 55
		return
	elseif podiumOn then
		podiumOn = false
		restoreDefault(camera)
	end
	local chassis = KartController.chassis()
	if not (KartController.isDriving() and chassis) then
		if active then
			active = false
			restoreDefault(camera)
		end
		return
	end
	if not active then
		active = true
		yawDir = nil
		rig = CockpitRig.new()
		blendT = 1
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local cockpit = zoomTarget == 0
	local back = 1 - math.exp(-C.FreeLookReturn * dt)
	-- a look-around finger whose end we never heard about (it lifted over a
	-- button, or the app lost focus): let go of it, or the next touch that
	-- reuses the object would swing the camera
	local td = touchDrag
	if td and (td.UserInputState == Enum.UserInputState.End or td.UserInputState == Enum.UserInputState.Cancel) then
		touchDrag = nil
	end
	local looking = mouseDragging or touchDrag ~= nil
	if cockpit then
		-- the right stick turns the head directly; everything springs back
		if stick.Magnitude > 0 then
			lookYaw += (-stick.X * math.rad(100) - lookYaw) * back
			lookPitch += (stick.Y * math.rad(45) - lookPitch) * back
		elseif not looking then
			lookYaw -= lookYaw * back
			lookPitch -= lookPitch * back
		end
	else
		-- the right stick swings the orbit and it stays
		if stick.Magnitude > 0 then
			recentering = false
			sinceOrbit = 0
			local rate = math.rad(C.StickOrbitSpeed) * dt
			orbitYaw = (orbitYaw - stick.X * rate + math.pi) % (2 * math.pi) - math.pi
			orbitPitch = clampOrbitPitch(orbitPitch - stick.Y * rate * 0.6)
		end
		if C.AutoRecenter > 0 and not looking and stick.Magnitude == 0 and (orbitYaw ~= 0 or orbitPitch ~= 0) then
			sinceOrbit += dt
			if sinceOrbit > C.AutoRecenter and chassis.AssemblyLinearVelocity.Magnitude > 10 then
				recentering = true
			end
		end
		if recentering then
			orbitYaw -= orbitYaw * back
			orbitPitch -= orbitPitch * back
			if math.abs(orbitYaw) < 1e-3 and math.abs(orbitPitch) < 1e-3 then
				orbitYaw, orbitPitch = 0, 0
				recentering = false
			end
		end
	end

	local speedFrac = math.clamp(chassis.AssemblyLinearVelocity.Magnitude / Config.Kart.TopSpeed, 0, 1)
	local target: CFrame
	if cockpit then
		target = cockpitCFrame(chassis, dt)
		fov = CP.Fov + CP.FovSpeedGain * speedFrac
	else
		target = chaseCFrame(chassis, dt)
		local targetFov = C.FovMin + (C.FovMax - C.FovMin) * speedFrac
		fov += (targetFov - fov) * (1 - math.exp(-4 * dt))
	end

	-- avatar parts and the cockpit arms
	KartVisuals.setCockpit(cockpit)
	if cockpit then
		if next(hidden) == nil or os.clock() - lastHideScan > 0.5 then
			lastHideScan = os.clock()
			setAvatarHidden(true) -- also catches accessories that load late
		end
	elseif next(hidden) ~= nil then
		setAvatarHidden(false)
	end

	if blendT < 1 and blendFrom then
		blendT = math.min(blendT + dt / BLEND_TIME, 1)
		local a = blendT * blendT * (3 - 2 * blendT)
		camera.CFrame = blendFrom:Lerp(target, a)
		camera.FieldOfView = blendFov + (fov - blendFov) * a
	else
		camera.CFrame = target
		camera.FieldOfView = fov
	end
end

-- Spectating (not driving): follow another kart with the normal camera.
function ChaseCamera.spectate(target: BasePart?)
	spectateTarget = target
	if not KartController.isDriving() then
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = target or humanoid
	end
end

local function driving(): boolean
	return active and KartController.isDriving()
end

-- zoom for the "Camera" setting
local function startingZoom(): number
	local choice = Settings.get("Camera")
	if choice == "Cockpit" then
		return 0
	elseif choice == "Far" then
		return C.Presets[3] or C.MaxDistance
	end
	return C.Presets[2] or C.Distance
end

function ChaseCamera.init()
	refreshFilter()
	zoomTarget = startingZoom()
	zoom = math.max(zoomTarget, C.MinDistance)
	Settings.onChange(function(key)
		if key == "Camera" then
			setZoom(startingZoom())
		end
	end)
	workspace:GetAttributeChangedSignal("TrackReady"):Connect(refreshFilter)
	workspace:GetAttributeChangedSignal("Track"):Connect(refreshFilter)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Circuit" then
			task.defer(refreshFilter)
		end
	end)
	Input.onAction("Camera", function()
		ChaseCamera.cycle()
	end)

	UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if not driving() then
			return
		end
		local t = io.UserInputType
		if t == Enum.UserInputType.MouseButton2 and not processed then
			mouseDragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif t == Enum.UserInputType.Touch and not processed and touchDrag == nil then
			touchDrag = io -- a finger on an empty part of the screen
		elseif io.KeyCode == Enum.KeyCode.DPadUp then
			ChaseCamera.zoomStep(-1)
		elseif io.KeyCode == Enum.KeyCode.DPadDown then
			ChaseCamera.zoomStep(1)
		elseif (io.KeyCode == Enum.KeyCode.V and not processed) or io.KeyCode == Enum.KeyCode.ButtonR3 then
			ChaseCamera.recenter()
		end
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		local t = io.UserInputType
		if t == Enum.UserInputType.MouseButton2 and mouseDragging then
			mouseDragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif t == Enum.UserInputType.Touch and touchDrag == io then
			touchDrag = nil
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.zero
		end
	end)
	UserInputService.InputChanged:Connect(function(io: InputObject, processed: boolean)
		if not driving() then
			return
		end
		local t = io.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			if not processed then
				ChaseCamera.zoomStep(if io.Position.Z > 0 then -1 else 1)
			end
		elseif t == Enum.UserInputType.MouseMovement and mouseDragging then
			drag(io.Delta.X, io.Delta.Y, C.FreeLookSensitivity)
		elseif t == Enum.UserInputType.Touch and touchDrag == io then
			drag(io.Delta.X, io.Delta.Y, C.TouchSensitivity)
		elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(io.Position.X, io.Position.Y)
			stick = if v.Magnitude > 0.2 then v else Vector2.zero
		end
	end)

	UserInputService.TouchEnded:Connect(function(io: InputObject)
		if touchDrag == io then
			touchDrag = nil
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		touchDrag = nil
		stick = Vector2.zero
		if mouseDragging then
			mouseDragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	-- pinch to zoom on touch screens (two fingers: no orbit while pinching)
	local pinchStart = zoomTarget
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if not driving() or processed then
			return
		end
		touchDrag = nil
		if state == Enum.UserInputState.Begin then
			pinchStart = if zoomTarget == 0 then C.MinDistance * 0.9 else zoomTarget
		elseif state == Enum.UserInputState.Change and scale > 0 then
			setZoom(pinchStart / scale)
		end
	end)

	RunService:BindToRenderStep("KartCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return ChaseCamera
