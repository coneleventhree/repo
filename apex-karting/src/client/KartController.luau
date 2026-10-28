--!strict
-- Drives the local player's kart. Every physics frame it runs KartPhysics
-- (the same code the headless tests drive) and writes the result into the
-- chassis' VectorForce and Torque. The client owns the kart's physics, so
-- this is what moves it; the server only places and watches.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local KartPhysics = require(Shared:WaitForChild("KartPhysics"))
local SteerFilter = require(Shared:WaitForChild("SteerFilter"))
local Input = require(script.Parent:WaitForChild("Input"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local KartController = {}

local player = Players.LocalPlayer
-- per-player copies: the steering assist and the key steering speed are settings
local cfg = table.clone(Config.Kart)
local steerCfg = table.clone(Config.Steering)
local SCALED_STEERING = { "RiseLow", "RiseHigh", "ReturnLow", "ReturnHigh", "Counter" }

local function applySettings()
	cfg.SteerAssist = Settings.get("SteerAssist") ~= false
	local k = (Settings.get("SteerSpeed") :: number?) or 1
	for _, key in SCALED_STEERING do
		(steerCfg :: any)[key] = (Config.Steering :: any)[key] * k
	end
end

local kart: Model? = nil
local chassis: BasePart? = nil
local seat: Seat? = nil
local driveForce: VectorForce? = nil
local spinTorque: Torque? = nil
local state = KartPhysics.newState(cfg)
local steerState = SteerFilter.new()
local physControls: KartPhysics.Controls = { throttle = 0, brake = 0, steer = 0 }
local telemetry: KartPhysics.Result? = nil
local wasContact = false
local driving = false
local flipTimer = 0
local lastResetRequest = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

local listeners: { (boolean) -> () } = {}
local requestRemote: RemoteEvent? = nil
local controlsModule: any = nil

local function vec(v: Vector3): vector
	return (v :: any) :: vector
end
local function v3(v: vector): Vector3
	return (v :: any) :: Vector3
end

-- Grip per surface: the part's "Surface" attribute names a Config.Surfaces
-- entry (the circuit builder sets it); otherwise the material name is used.
local surfaceCache: { [Instance]: { grip: number, roll: number } } = setmetatable({}, { __mode = "k" }) :: any
local function surfaceOf(inst: Instance, material: Enum.Material): { grip: number, roll: number }
	local s = surfaceCache[inst]
	if not s then
		local surfaces = Config.Surfaces :: any
		local name = inst:GetAttribute("Surface")
		s = (if type(name) == "string" then surfaces[name] else nil) or surfaces[material.Name] or surfaces.Default
		if inst:IsA("BasePart") and not inst:IsA("Terrain") then
			surfaceCache[inst] = s :: any
		end
	end
	return s :: any
end

-- Two rays a few centimetres apart per wheel, keeping the nearer hit: a single
-- ray can slip through the hairline seam between two road pieces and read the
-- ground as lower than it is for one frame, which felt like a bump.
local SEAM_OFFSET = Vector3.new(0.09, 0, 0.07)
local function raycast(origin: vector, dir: vector): KartPhysics.Hit?
	local o = v3(origin)
	local d = v3(dir)
	local r = workspace:Raycast(o, d, rayParams)
	local r2 = workspace:Raycast(o + SEAM_OFFSET, d, rayParams)
	if r2 and (not r or r2.Distance < r.Distance) then
		r = r2
	end
	if not r then
		return nil
	end
	local s = surfaceOf(r.Instance, r.Material)
	return { dist = r.Distance, normal = vec(r.Normal), grip = s.grip, roll = s.roll }
end

local function refreshRayFilter()
	local list: { Instance } = { workspace.Terrain }
	local circuit = workspace:FindFirstChild("Circuit")
	local track = circuit and circuit:FindFirstChild("Track")
	if track then
		table.insert(list, track)
	end
	rayParams.FilterDescendantsInstances = list
end

local function setControls(on: boolean)
	if not controlsModule then
		local ok, pm = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		end)
		if ok and pm then
			controlsModule = pm:GetControls()
		end
	end
	if controlsModule then
		if on then
			controlsModule:Enable()
		else
			controlsModule:Disable()
		end
	end
end

local function setJump(humanoid: Humanoid?, allowed: boolean)
	if not humanoid then
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, allowed)
	humanoid.JumpHeight = if allowed then 7.2 else 0
end

local function setDriving(on: boolean)
	if driving == on then
		return
	end
	driving = on
	local character = player.Character
	setJump(character and character:FindFirstChildOfClass("Humanoid"), not on)
	setControls(not on)
	Input.setEnabled(on)
	state = KartPhysics.newState(cfg)
	steerState = SteerFilter.new()
	flipTimer = 0
	for _, f in listeners do
		task.spawn(f, on)
	end
end

function KartController.onDrivingChanged(f: (boolean) -> ())
	table.insert(listeners, f)
end

function KartController.isDriving(): boolean
	return driving
end

function KartController.kart(): Model?
	return kart
end

function KartController.chassis(): BasePart?
	return chassis
end

function KartController.telemetry(): KartPhysics.Result?
	return telemetry
end

function KartController.requestReset()
	if not driving or not requestRemote then
		return
	end
	if os.clock() - lastResetRequest < Config.Race.ResetCooldown then
		return
	end
	lastResetRequest = os.clock()
	requestRemote:FireServer("Reset")
end

-- called by the server's "Reset" message: the kart was teleported
function KartController.onTeleported()
	state = KartPhysics.newState(cfg)
	flipTimer = 0
end

local function attach(model: Model)
	kart = model
	chassis = model:WaitForChild("Chassis", 5) :: BasePart?
	seat = model:WaitForChild("DriverSeat", 5) :: Seat?
	local c = chassis
	if c then
		driveForce = c:WaitForChild("Drive", 5) :: VectorForce?
		spinTorque = c:WaitForChild("Spin", 5) :: Torque?
	end
	refreshRayFilter()
end

local function detach()
	kart, chassis, seat, driveForce, spinTorque, telemetry = nil, nil, nil, nil, nil, nil
	setDriving(false)
end

local function isMine(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute("Owner") == player.UserId
end

-- Other karts near ours, for the bumpers. Their positions arrive late (their
-- driver -> server -> us), so each is moved ahead along its velocity by
-- about that delay (Config.Collision), and our own recent bumper pushes are
-- mirrored onto it (KartPhysics.echoApply: it got the opposite push, which
-- its late snapshot does not show yet).
local CC = Config.Collision
local kartsFolder: Instance? = nil
local myPing, pingAge = 0.1, math.huge
local others: { KartPhysics.Obstacle } = {}
local otherKarts: { Model } = {} -- same order as `others`
local echo: KartPhysics.Echo = setmetatable(KartPhysics.newEcho(), { __mode = "k" }) :: any
local function nearbyKarts(dt: number, here: Vector3, t: number): { KartPhysics.Obstacle }
	table.clear(others)
	table.clear(otherKarts)
	local folder = kartsFolder
	-- ghosts (qualifying, or our kart just reset onto another): nothing to
	-- bump into or draft behind
	if not folder or workspace:GetAttribute("Ghost") or (kart and kart:GetAttribute("Ghost")) then
		return others
	end
	pingAge += dt
	if pingAge > 1 then
		pingAge = 0
		myPing = player:GetNetworkPing()
	end
	for _, m in folder:GetChildren() do
		if m == kart or not m:IsA("Model") or m:GetAttribute("Ghost") then
			continue
		end
		local c = m.PrimaryPart
		if not c then
			continue
		end
		local d = c.Position - here
		-- (and not on the other level of a crossing: KartPhysics ignores those)
		if d.X * d.X + d.Z * d.Z > CC.Range * CC.Range or math.abs(d.Y) > 8 then
			continue
		end
		local vel = c.AssemblyLinearVelocity
		local lead = 0
		if not c.Anchored then
			local owner = Players:GetPlayerByUserId((m:GetAttribute("Owner") :: number?) or 0)
			local theirPing = (owner and owner:GetAttribute("Ping") :: number?) or myPing
			lead = math.clamp(CC.Lead + CC.PingShare * (myPing + theirPing), 0, CC.LeadMax)
		end
		local o: KartPhysics.Obstacle = {
			pos = vec(c.Position + vel * lead),
			look = vec(c.CFrame.LookVector),
			vel = vec(vel),
			angVel = vec(c.AssemblyAngularVelocity),
		}
		if lead > 0 then
			o = KartPhysics.echoApply(echo, m, o, t, lead + dt)
		end
		table.insert(others, o)
		table.insert(otherKarts, m)
	end
	return others
end

local function physicsStep(dt: number)
	local c, vf, tq = chassis, driveForce, spinTorque
	if not (kart and c and vf and tq and c.Parent) then
		if kart and not (kart.Parent) then
			detach()
		end
		return
	end
	-- driving = our humanoid sits in this kart's seat
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seated = humanoid ~= nil and seat ~= nil and humanoid.SeatPart == seat
	setDriving(seated)
	local ctrl = Input.update(dt)
	if not seated or c.Anchored then
		vf.Force = Vector3.zero
		tq.Torque = Vector3.zero
		telemetry = nil
		steerState = SteerFilter.new()
		return
	end
	local cf = c.CFrame
	-- keys ramp the steering in (speed-sensitive), the stick stays analog
	local forwardSpeed = c.AssemblyLinearVelocity:Dot(cf.LookVector)
	physControls.throttle = ctrl.throttle
	physControls.brake = ctrl.brake
	physControls.steer = SteerFilter.step(steerCfg, steerState, ctrl.steer, ctrl.digital, forwardSpeed, dt)
	local mass = c.AssemblyMass
	local body: KartPhysics.Body = {
		pos = vec(c.Position),
		right = vec(cf.RightVector),
		up = vec(cf.UpVector),
		look = vec(cf.LookVector),
		vel = vec(c.AssemblyLinearVelocity),
		angVel = vec(c.AssemblyAngularVelocity),
		mass = mass,
	}
	local t = os.clock()
	local res = KartPhysics.step(cfg, state, body, physControls, dt, raycast, nearbyKarts(dt, c.Position, t))
	telemetry = res
	for i, m in otherKarts do
		KartPhysics.echoAdd(echo, m, res.bumps[i], t)
	end
	-- a knock as the bumpers meet (not while they keep rubbing)
	local touching = res.contact > 0
	if touching and not wasContact then
		Sfx.play("Bump", math.clamp(res.contactSpeed / 25, 0.2, 1))
	end
	wasContact = touching
	-- Roblox gravity is stronger than the kart's real-world gravity: cancel the
	-- difference on the kart only.
	local lift = mass * (workspace.Gravity - cfg.Gravity)
	vf.Force = v3(res.force) + Vector3.new(0, lift, 0)
	tq.Torque = v3(res.torque)

	-- automatic recovery: upside down for a while, or fell off the world
	if cf.UpVector.Y < 0.25 and res.speed < 10 then
		flipTimer += dt
	else
		flipTimer = 0
	end
	if flipTimer > cfg.FlipResetTime or c.Position.Y < cfg.FallY then
		flipTimer = 0
		KartController.requestReset()
	end
end

function KartController.init(remotes: Folder)
	requestRemote = remotes:WaitForChild("Request") :: RemoteEvent
	applySettings()
	Settings.onChange(function(key)
		if key == "SteerAssist" or key == "SteerSpeed" then
			applySettings()
		end
	end)
	local folder = workspace:WaitForChild("Karts")
	kartsFolder = folder
	local function consider(child: Instance)
		if isMine(child) then
			attach(child :: Model)
		end
	end
	folder.ChildAdded:Connect(consider)
	folder.ChildRemoved:Connect(function(child)
		if child == kart then
			detach()
		end
	end)
	for _, child in folder:GetChildren() do
		consider(child)
	end
	-- the circuit folder is swapped when the track changes
	workspace:GetAttributeChangedSignal("TrackReady"):Connect(refreshRayFilter)
	workspace:GetAttributeChangedSignal("Track"):Connect(refreshRayFilter)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Circuit" then
			task.defer(refreshRayFilter)
		end
	end)
	RunService.PreSimulation:Connect(physicsStep)
	Input.onAction("Reset", KartController.requestReset)
	Input.onAction("Kart", function()
		if requestRemote then
			requestRemote:FireServer("Kart")
		end
	end)
end

return KartController
