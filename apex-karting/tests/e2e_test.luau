-- End-to-end test: runs the real server and client scripts in the mock Roblox
-- runtime and plays the game: practice laps with sectors and a live delta,
-- track limits, the settings menu and sounds, switching track in practice,
-- a two-player race weekend (length vote, READY, qualifying that sets the
-- grid, lights, laps, track-limit warnings and a penalty, results and the
-- podium), resets, wrong way, a track vote, and a race on the voted track
-- with a player leaving.
-- Run from the project root:
--   python3 tests/mock/gen.py && luau tests/e2e_test.luau
local Game = require("./lib/game")

local pass, total = 0, 0
local function check(ok: boolean, label: string)
	total += 1
	if ok then
		pass += 1
	end
	print(string.format("%-4s %s", if ok then "PASS" else "FAIL", label))
	return ok
end

local clock0 = os.clock()
local G = Game.boot({ printErrors = true, reserved = { mode = "race" } })
local function noErrors(label: string)
	local ok = #G.errors == 0
	check(ok, label .. " (no script errors)")
	if not ok then
		for i = 1, math.min(#G.errors, 3) do
			print("    " .. G.errors[i]:gsub("\n", "\n    "))
		end
		table.clear(G.errors)
	end
end
noErrors("server boots and builds the circuit")

local ws = G.workspace
local D = require("./mock/datatypes")
local Vector3 = D.Vector3
local Enum = G.Enum

-- Shared modules as seen by a test context (same code the game runs)
local testCtx = { name = "testmods" }
local TrackMath = Game.sharedModule(G, testCtx, "TrackMath")
local TrackData = Game.sharedModule(G, testCtx, "TrackData")
local KartPhysics = Game.sharedModule(G, testCtx, "KartPhysics")
local Config = Game.sharedModule(G, testCtx, "Config")
local TrackLimits = Game.sharedModule(G, testCtx, "TrackLimits")
local TrackLayout = Game.sharedModule(G, testCtx, "TrackLayout")
local trackId = TrackData.Default
local track = TrackMath.build(TrackData.get(trackId))
local cfg = Config.Kart
local surfaceY: (number, number, number) -> number?

----------------------------------------------------------------------------
print("== Circuit geometry ==")
-- height of the road triangles of quad i (and its neighbours) under (x, z)
local function triY(a, b, c, x, z): number?
	local o = Vector3.new(x, 1e4, z)
	local d = Vector3.new(0, -1, 0)
	local e1, e2 = b - a, c - a
	local pv = d:Cross(e2)
	local det = e1:Dot(pv)
	if math.abs(det) < 1e-9 then
		return nil
	end
	local tv = o - a
	local u = tv:Dot(pv) / det
	if u < -1e-6 or u > 1 + 1e-6 then
		return nil
	end
	local q = tv:Cross(e1)
	local v = d:Dot(q) / det
	if v < -1e-6 or u + v > 1 + 1e-6 then
		return nil
	end
	return o.Y - e2:Dot(q) / det
end
surfaceY = function(i0: number, x: number, z: number): number?
	-- the same pieces the game builds (twisted quads split, TrackLayout)
	for di = -1, 1 do
		local i = TrackMath.wrap(i0 + di, track.n)
		local across, along = TrackLayout.roadSplit(track, i)
		for _, t in TrackLayout.roadTriangles(track, i, across, along) do
			local y = triY(Vector3.new(t[1].x, t[1].y, t[1].z), Vector3.new(t[2].x, t[2].y, t[2].z), Vector3.new(t[3].x, t[3].y, t[3].z), x, z)
			if y then
				return y
			end
		end
	end
	return nil
end
local function checkGeometry(name: string, hilly: boolean?)
	print(string.format("    (%s)", name))
	local params = D.RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ws.Circuit.Track }
	local worst, misses, kerbHits = 0, 0, 0
	local function surfaceAt(p): (any, string?)
		local hit = ws:Raycast(p + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), params)
		return hit, hit and hit.Instance:GetAttribute("Surface")
	end
	for i = 1, track.n, 3 do
		local smp = track.samples[i]
		for _, f in { -0.9, -0.45, 0, 0.45, 0.9 } do
			local p = smp.pos + smp.right * (f * smp.width / 2)
			-- move a little along the lap so we are inside a triangle, not on an edge
			p += smp.fwd * 1.3
			local hit, surf = surfaceAt(p)
			if not hit then
				misses += 1
			else
				-- expected height: the same two triangles the physics tests use
				local expected = surfaceY(i, p.X, p.Z)
				worst = math.max(worst, math.abs(hit.Position.Y - (expected or math.huge)))
				if surf ~= "Asphalt" then
					kerbHits += 1
				end
			end
		end
	end
	check(misses == 0, string.format("rays hit the road everywhere (%d misses)", misses))
	check(worst < 0.005, string.format("road wedges match the track triangles (worst %.4f studs)", worst))
	check(kerbHits == 0, string.format("only asphalt inside the road edges (%d other)", kerbHits))

	-- kerbs: just outside the edge on a corner
	local found = 0
	for i = 1, track.n do
		local smp = track.samples[i]
		if math.abs(smp.curv) > 1 / 60 then
			for _, side in { -1, 1 } do
				local p = smp.pos + smp.right * (side * (smp.width / 2 + 1.0)) + smp.fwd * 1.3
				local _, surf = surfaceAt(p)
				if surf == "Kerb" then
					found += 1
				end
			end
		end
	end
	check(found > 20, string.format("kerbs beside tight corners (%d hits)", found))

	if hilly then
		-- the ground beside a raised road: from the road out past the bands and
		-- down the embankment (50 studs past the edge: further out, where two
		-- strips from different corners cross, a grassy crease of a few studs
		-- is left), every probe hits something and no step between two probes
		-- is a cliff (a hole would drop to the lawn far below)
		local cliffs, worst, holes, kinds, raised = 0, 0, 0, {}, 0
		local down = Vector3.new(0, -200, 0)
		for i = 1, track.n, 2 do
			local smp = track.samples[i]
			if smp.pos.Y > 3 then
				raised += 1
				for _, side in { -1, 1 } do
					local lastY: number? = nil
					for d = 0.6, smp.width / 2 + 50, 1.7 do
						local p = smp.pos + Vector3.new(smp.right.X, 0, smp.right.Z).Unit * (side * d) + smp.fwd * 0.9
						local hit = ws:Raycast(Vector3.new(p.X, smp.pos.Y + 60, p.Z), down, params)
						if not hit then
							holes += 1
							break
						end
						kinds[hit.Instance:GetAttribute("Surface") or "?"] = true
						if lastY then
							local step = math.abs(hit.Position.Y - lastY)
							worst = math.max(worst, step)
							if step > 2.5 then
								cliffs += 1
							end
						end
						lastY = hit.Position.Y
					end
				end
			end
		end
		check(raised > 50 and holes == 0, string.format("ground under the raised road everywhere (%d samples, %d holes)", raised, holes))
		check(cliffs == 0, string.format("no cliffs beside the raised road (biggest step %.2f studs)", worst))
		check(kinds.Grass and kinds.Turf and kinds.Asphalt, "road, verges and grassy embankments")
		local banks = ws.Circuit.Track:FindFirstChild("Embankments")
		check(banks ~= nil and #banks:GetChildren() > 200, string.format("embankment wedges (%d)", if banks then #banks:GetChildren() else 0))
		check(next(G.voxels) == nil, "no smooth terrain is used")
		return
	end
	-- flat floor: everywhere a kart can drive (road, bands and the lawn
	-- beyond) is within a hand's width of y = 0 and faces straight up,
	-- apart from the kerb crowns
	local highest, lowest, tilted, kinds = -math.huge, math.huge, 0, {}
	for i = 1, track.n, 2 do
		local smp = track.samples[i]
		for _, side in { -1, 1 } do
			for d = 0.6, smp.width / 2 + 60, 1.7 do
				local p = smp.pos + Vector3.new(smp.right.X, 0, smp.right.Z).Unit * (side * d) + smp.fwd * 0.9
				local hit, surf = surfaceAt(p)
				if hit then
					kinds[surf or "?"] = true
					if surf ~= "Kerb" then
						highest = math.max(highest, hit.Position.Y)
						lowest = math.min(lowest, hit.Position.Y)
						if hit.Normal.Y < 0.999 then
							tilted += 1
						end
					end
				else
					misses += 1
				end
			end
		end
	end
	check(highest <= 0.001 and lowest >= -0.11, string.format("drivable floor is flat (heights %.3f .. %.3f)", lowest, highest))
	check(tilted == 0, string.format("floor faces straight up everywhere (%d tilted hits)", tilted))
	check(kinds.Turf and kinds.RunOff and kinds.Gravel and kinds.Grass, "turf, run-off, gravel and lawn all present")
	check(misses == 0, string.format("no holes in the floor (%d misses)", misses))
	check(next(G.voxels) == nil, "no smooth terrain is used")
	local gantry = ws.Circuit.Track:FindFirstChild("Gantry")
	check(gantry ~= nil and #gantry.Lights:GetChildren() == 5, "start gantry with five lights")
	local spawn = ws.Circuit.Pits:FindFirstChild("LobbySpawn")
	check(spawn ~= nil, "lobby spawn exists")
end
checkGeometry(TrackData.get(trackId).Name)

----------------------------------------------------------------------------
-- Autopilot shared by the real client (through gamepad input) and the bot
----------------------------------------------------------------------------
local function makePlan(): { number }
	local n = track.n
	local v = table.create(n, 0)
	for i = 1, n do
		local k = 0
		for j = -2, 2 do
			k += math.abs(track.samples[TrackMath.wrap(i + j, n)].curv)
		end
		k /= 5
		v[i] = math.min(cfg.TopSpeed, math.sqrt(0.8 * cfg.Mu * cfg.Gravity / math.max(k, 1e-5)))
	end
	for _ = 1, 2 do
		for i = n, 1, -1 do
			local nx = v[TrackMath.wrap(i + 1, n)]
			v[i] = math.min(v[i], math.sqrt(nx * nx + 2 * cfg.Mu * cfg.Gravity * 0.5 * track.spacing))
		end
	end
	return v
end
local plan = makePlan()

type Pilot = { hint: number?, reverse: boolean, pace: number? }
local function autopilot(chassis, pilot: Pilot): (number, number, number)
	local cf = chassis.CFrame
	local pos = cf.Position
	local idx = TrackMath.nearest(track, pos, pilot.hint, 12, 40)
	if pilot.hint and (track.samples[idx].pos - pos).Magnitude > 40 then
		-- the kart was moved (grid, reset, respawn): find it again on the whole lap
		idx = TrackMath.nearest(track, pos)
	end
	pilot.hint = idx
	local look = cf.LookVector
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel:Dot(look)
	local dir = if pilot.reverse then -1 else 1
	local lookAhead = 7 + 0.3 * math.abs(speed)
	local steps = math.max(1, math.floor(lookAhead / track.spacing + 0.5))
	local target = track.samples[TrackMath.wrap(idx + dir * steps, track.n)].pos
	local to = target - pos
	local alpha = math.atan2(to:Dot(cf.RightVector), to:Dot(look))
	local g = KartPhysics.geometry(cfg)
	local delta = math.atan(2 * g.wheelbase * math.sin(alpha) / lookAhead)
	if math.abs(alpha) > math.pi / 2 then
		delta = math.sign(alpha) * math.rad(cfg.SteerLock) -- target behind: full lock round
	end
	local body = { pos = pos, right = cf.RightVector, up = cf.UpVector, look = look, vel = vel, angVel = chassis.AssemblyAngularVelocity, mass = 1 }
	local steer = KartPhysics.inputFor(cfg, delta, body)
	local vt = math.huge
	for j = 0, steps do
		vt = math.min(vt, plan[TrackMath.wrap(idx + dir * j, track.n)])
	end
	if pilot.reverse then
		vt = 25
	end
	vt *= pilot.pace or 1
	local throttle, brake = 0.3, 0
	if speed < vt - 1 then
		throttle, brake = 1, 0
	elseif speed > vt + 2 then
		throttle, brake = 0, math.clamp((speed - vt) / 10, 0.2, 1)
	end
	return throttle, brake, steer
end

-- the gamepad stick has a dead zone of 0.12 in Input; invert it
local function stick(u: number): number
	if math.abs(u) < 1e-3 then
		return 0
	end
	return math.sign(u) * (0.12 + math.abs(u) * 0.88)
end

local function kartOf(player)
	local folder = ws:FindFirstChild("Karts")
	return folder and folder:FindFirstChild("Kart_" .. player.UserId)
end

-- Puts a kart just past the track limits (all four tyres beyond the kerb)
-- a little ahead of where it is, rolling forward; the autopilot steers it
-- back. Uses the same zones and test as the server.
local zonesCache: { [string]: any } = {}
local function pushOffTrack(k): boolean
	local zs = zonesCache[trackId]
	if not zs then
		zs = TrackLayout.zones(track, TrackLayout.grid(track))
		zonesCache[trackId] = zs
	end
	local c = k.PrimaryPart
	local j = TrackMath.wrap(TrackMath.nearest(track, c.Position) + 2, track.n)
	local smp = track.samples[j]
	for _, side in { 1, -1 } do
		for extra = 3, 16, 0.5 do
			local p = smp.pos + smp.right * (side * (smp.width / 2 + extra)) + Vector3.new(0, cfg.RideHeight + 0.05, 0)
			local cf = D.CFrame.lookAt(p, p + smp.fwd)
			local wheels = {}
			for _, w in cfg.Wheels do
				table.insert(wheels, { pos = p + cf.RightVector * w.x + cf.LookVector * w.f, half = w.width / 2 })
			end
			if TrackLimits.allOut(TrackMath, track, zs, j, wheels) then
				-- a stud more than the least that counts
				local q = p + smp.right * side
				k:PivotTo(D.CFrame.lookAt(q, q + smp.fwd))
				c.AssemblyLinearVelocity = smp.fwd * 30
				c.AssemblyAngularVelocity = Vector3.zero
				return true
			end
		end
	end
	return false
end

-- runs until the kart is between `from` and `to` (fractions of the lap)
local function runUntilLapShare(player, from: number, to: number, limit: number): boolean
	return G.run(limit, function()
		local k = kartOf(player)
		if not (k and k.PrimaryPart) then
			return false
		end
		local i = TrackMath.nearest(track, k.PrimaryPart.Position)
		return i > track.n * from and i < track.n * to
	end)
end

-- per-frame drivers
local pilotA: Pilot = { hint = nil, reverse = false }
local driveA = true
local A, B
local clientA
local botCtx
local botState = nil
local pilotB: Pilot = { hint = nil, reverse = false }
local driveB = true
local holdB = false -- bot keeps its physics running with no input

-- follow the server when it puts another circuit in use
local function useTrack(id: string)
	trackId = id
	track = TrackMath.build(TrackData.get(id))
	plan = makePlan()
	pilotA.hint = nil
	pilotB.hint = nil
	G.groundFilter = { ws.Circuit.Track }
	G.groundParams = nil
end

G.onFrame = function()
	local id = ws:GetAttribute("Track")
	if id and id ~= trackId and ws.Circuit:GetAttribute("TrackId") == id then
		useTrack(id)
	end
	if A and driveA then
		local k = kartOf(A)
		if k and k.PrimaryPart and not k.PrimaryPart.Anchored then
			local th, br, st = autopilot(k.PrimaryPart, pilotA)
			G.gamepad = { r2 = th, l2 = br, x = stick(st) }
		else
			G.gamepad = { r2 = 0, l2 = 0, x = 0 }
		end
	end
end

-- Player B has no real client: a bot drives its kart with the same physics
-- module, the way KartController would.
local function startBot(player)
	botCtx = { name = "bot:" .. player.Name, player = player }
	local BotPhysics = Game.sharedModule(G, botCtx, "KartPhysics")
	local BotConfig = Game.sharedModule(G, botCtx, "Config")
	local rs = G.game:GetService("RunService")
	local params = D.RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ws.Circuit.Track }
	local currentKart = nil
	G.spawnIn(botCtx, function()
		rs.PreSimulation:Connect(function(dt)
			local k = kartOf(player)
			if k ~= currentKart then
				currentKart = k
				botState = BotPhysics.newState(BotConfig.Kart)
			end
			if not (k and k.PrimaryPart and driveB) then
				return
			end
			local c = k.PrimaryPart
			if c.Anchored then
				return
			end
			if params.FilterDescendantsInstances[1] ~= ws.Circuit.Track then
				params.FilterDescendantsInstances = { ws.Circuit.Track }
			end
			local th, br, st = 0, 0, 0
			if not holdB then
				th, br, st = autopilot(c, pilotB)
			end
			local cf = c.CFrame
			local body = { pos = c.Position, right = cf.RightVector, up = cf.UpVector, look = cf.LookVector, vel = c.AssemblyLinearVelocity, angVel = c.AssemblyAngularVelocity, mass = c.AssemblyMass }
			-- the other kart, for the bumpers (no network delay in the mock);
			-- none in ghost qualifying, like KartController
			local others = {}
			local ka = A and kartOf(A)
			if ka and ka.PrimaryPart and not ws:GetAttribute("Ghost") then
				local pa = ka.PrimaryPart
				table.insert(others, { pos = pa.Position, look = pa.CFrame.LookVector, vel = pa.AssemblyLinearVelocity, angVel = pa.AssemblyAngularVelocity })
			end
			local res = BotPhysics.step(BotConfig.Kart, botState, body, { throttle = th, brake = br, steer = st }, dt, function(o, d)
				local r = ws:Raycast(o, d, params)
				if not r then
					return nil
				end
				local s = BotConfig.Surfaces[r.Instance:GetAttribute("Surface") or ""] or BotConfig.Surfaces.Default
				return { dist = r.Distance, normal = r.Normal, grip = s.grip, roll = s.roll }
			end, others)
			c.Drive.Force = res.force + Vector3.new(0, c.AssemblyMass * (ws.Gravity - BotConfig.Kart.Gravity), 0)
			c.Spin.Torque = res.torque
		end)
	end)
end

local function hud()
	local gui = A:FindFirstChild("PlayerGui"):FindFirstChild("RaceHud")
	return gui
end

-- the bot (player B) sends a request the way its client would
local function botRequest(kind: string, arg: any)
	G.spawnIn(botCtx, function()
		G.game:GetService("ReplicatedStorage").Remotes.Request:FireServer(kind, arg)
	end)
end


----------------------------------------------------------------------------
print("== Joining and practice ==")
A = G.addPlayer("Alice", 101)
clientA = G.startClient(A, Game.ClientSpec)
-- turn the optional sounds on for this client so that code path runs too
local clientConfig = Game.sharedModule(G, clientA, "Config")
for i, name in { "Engine", "Skid", "Offroad", "Kerb", "Bump", "Beep", "Go", "Lap", "Best", "Warning", "Penalty", "Flag", "Finish", "Podium", "Click", "Crowd" } do
	clientConfig.Audio[name .. "SoundId"] = "rbxassetid://" .. i
end
local SoundService = G.game:GetService("SoundService")
local function sfxPlayed(name: string): boolean
	local s = SoundService:FindFirstChild("Sfx" .. name)
	return s ~= nil and s.SoundGroup ~= nil and s.SoundGroup.Name == "KartEffects"
end
G.run(3)
noErrors("client boots")
local KC = Game.clientModule(G, clientA, "KartController")
local kA = kartOf(A)
check(kA ~= nil, "practice kart spawned for the first player")
local humA = A.Character:FindFirstChildOfClass("Humanoid")
check(kA ~= nil and humA.SeatPart == kA.DriverSeat, "player is seated in the kart")
check(KC.isDriving(), "client is in driving mode")
local engineSnd = kA and kA.PrimaryPart:FindFirstChild("EngineSound") :: Sound?
check(engineSnd ~= nil and engineSnd.IsPlaying, "engine sound plays when an id is configured")
check(engineSnd ~= nil and engineSnd.SoundGroup ~= nil and engineSnd.SoundGroup.Name == "KartEngine", "engine sound in the engine volume group")
check(A._props._controls.enabled == false, "default character controls disabled while driving")
check(ws:GetAttribute("RaceState") == "Practice", "state is Practice with one player")
local banner = hud().Banner.Text.Text
check(banner:find("WAITING FOR DRIVERS") ~= nil, "a quick-race server alone: waiting for drivers, practising: " .. banner)
if kA then
	local chassis = kA.PrimaryPart
	check(math.abs(chassis.AssemblyMass - chassis.Mass) < 1e-6, string.format("kart mass is the chassis only (%.2f vs %.2f): driver and bodywork massless", chassis.AssemblyMass, chassis.Mass))
	check(chassis:GetNetworkOwner() == A, "driver owns the kart physics")
	-- settles at ride height on the grid
	local y0 = chassis.Position.Y
	local gpos = TrackMath.nearest(track, chassis.Position)
	local ground = track.samples[gpos].pos.Y
	check(math.abs((y0 - ground) - cfg.RideHeight) < 0.12, string.format("rests at ride height (%.2f)", y0 - ground))
end

-- drive a lap and a bit
local lapToast = nil
local t0 = G.time
G.run(80, function()
	local toast = hud().Toast
	if toast.Visible and toast.Text:find("LAP 1") then
		lapToast = toast.Text
		return true
	end
	return false
end)
noErrors("practice driving")
check(lapToast ~= nil, "practice lap is timed: " .. tostring(lapToast))
local lapTime = G.time - t0
check(A:GetAttribute("PersonalBest") ~= nil, string.format("personal best stored (%.3f)", A:GetAttribute("PersonalBest") or -1))
check(ws:GetAttribute("TrackRecord") ~= nil, "track record set")
check(hud().Timing.Visible and hud().Speed.Visible, "timing and speed panels while driving")
local speedText = hud().Speed.Value.Text
check(tonumber(speedText) ~= nil and tonumber(speedText) > 20, "speedometer reads " .. speedText .. " km/h")
print(string.format("    (first lap took %.1f s including the run to the line; scrapes %d)", lapTime, G.scrapes or 0))
check(sfxPlayed("Best") and not sfxPlayed("Lap"), "the first timed lap is a personal best: the best chime, not the lap one")
do
	-- engine revs: the clutch slips above idle on the throttle, the road speed
	-- takes over; the loop is recorded at EngineRpmLoop
	local snd = kartOf(A).PrimaryPart:FindFirstChild("EngineSound") :: Sound
	local rpm = snd.PlaybackSpeed * clientConfig.Audio.EngineRpmLoop
	check(rpm > clientConfig.Audio.EngineRpmClutch and rpm <= clientConfig.Audio.EngineRpmMax * 1.2, string.format("engine at %.0f rpm on the move", rpm))
	local loops = kartOf(A).PrimaryPart:FindFirstChild("OffroadSound") and kartOf(A).PrimaryPart:FindFirstChild("KerbSound")
	check(loops ~= nil, "off-road and kerb loops on the kart")
end

----------------------------------------------------------------------------
print("== Sectors, live delta, track limits ==")
do
	local timing = hud().Timing
	local s3 = timing.S3
	check(tonumber(timing.S1.Text) ~= nil and tonumber(timing.S2.Text) ~= nil and tonumber(s3.Text) ~= nil, string.format("three sector times after the lap (%s / %s / %s)", timing.S1.Text, timing.S2.Text, s3.Text))
	local sum = (tonumber(timing.S1.Text) or 0) + (tonumber(timing.S2.Text) or 0) + (tonumber(s3.Text) or 0)
	local best = A:GetAttribute("PersonalBest") or 0
	check(math.abs(sum - best) < 0.01, string.format("sectors add up to the lap (%.3f vs %.3f)", sum, best))
	local purple = s3.BackgroundColor3.R > 0.6 and s3.BackgroundColor3.B > 0.8 and s3.BackgroundColor3.G < 0.6
	check(purple, "first sector times of the session are purple")
	-- into the next lap: S1 again, the others blank, and a delta to the best lap
	local s1Again = G.run(30, function()
		return tonumber(timing.S1.Text) ~= nil and timing.S2.Text == "S2"
	end)
	check(s1Again, "next lap: sector 1 time, sectors 2 and 3 cleared")
	local delta = timing.Delta.Text
	check(delta:match("^[%+%-]%d+%.%d%d$") ~= nil, "live delta to the best lap: " .. delta)
	local d = tonumber(delta) or 99
	-- the first lap began slowly (from the pits), so this one is ahead
	check(d < 0 and d > -4, string.format("flying lap ahead of the first one (%+.2f s)", d))
	-- all four wheels past the kerb: the lap is struck off
	runUntilLapShare(A, 0.4, 0.75, 40)
	driveA = true
	local pushed = pushOffTrack(kartOf(A))
	pilotA.hint = nil
	check(pushed, "kart put just past the track limits")
	local deleted = G.run(2, function()
		return hud().Toast.Visible and hud().Toast.Text:find("LAP DELETED") ~= nil
	end)
	check(deleted, "practice: going wide deletes the lap (" .. hud().Toast.Text .. ")")
	check(timing.Delta.Text == "DELETED" and timing.Cur.TextColor3.R > 0.8 and timing.Cur.TextColor3.G < 0.4, "timing shows the lap as deleted")
	check(sfxPlayed("Penalty"), "lap deleted: the penalty buzzer")
	G.run(2)
	local i, lat = TrackMath.nearest(track, kartOf(A).PrimaryPart.Position)
	check(math.abs(lat) < track.samples[i].width / 2, string.format("back on track (lateral %.1f)", lat))
	noErrors("sectors and track limits")
end


----------------------------------------------------------------------------
print("== HUD text stays sharp ==")
do
	-- park, so no lap or track-limit message lands in the middle of this
	driveA = false
	G.gamepad = { r2 = 0, l2 = 0.6, x = 0 }
	G.run(2)
	local timing = hud().Timing
	local cur = timing.Cur
	local face = cur.FontFace
	check(not cur.TextScaled and cur.TextSize >= 24 and face ~= nil and face.Family:find("RobotoMono") ~= nil and face.Weight == Enum.FontWeight.Bold, "lap clock: bold monospace at a fixed size")
	check(cur.Text:match("^%d+:%d%d%.%d%d%d$") ~= nil, "lap clock shows the running time: " .. cur.Text)
	local same = true
	for _, n in { "Last", "Best", "Rec", "Delta", "S1", "S2", "S3" } do
		local l = timing[n]
		if l.TextScaled or l.FontFace == nil or l.FontFace.Weight ~= Enum.FontWeight.Bold then
			same = false
		end
	end
	check(same, "every time in the panel drawn the same way")
	-- whole-pixel scale; centred panels start on a whole pixel
	local uiScale = hud():FindFirstChildOfClass("UIScale")
	local menu = A.PlayerGui.SettingsGui
	local function onPixels(vp): (boolean, string)
		for _, n in { "Banner", "Toast", "Lights", "Big", "Warning", "Hint" } do
			local o = hud()[n]
			local x = o.Position.X
			local want = math.floor((vp.X / uiScale.Scale - o.Size.X.Offset) / 2)
			if x.Scale ~= 0 or x.Offset ~= want or o.AnchorPoint.X ~= 0 then
				return false, n
			end
		end
		local p = menu.Panel.Position
		if p.X.Scale ~= 0 or p.Y.Scale ~= 0 or p.X.Offset ~= math.floor(p.X.Offset) or p.Y.Offset ~= math.floor(p.Y.Offset) then
			return false, "settings panel"
		end
		return true, ""
	end
	type Screen = { w: number, h: number, scale: number }
	local screens: { Screen } = {
		{ w = 1280, h = 720, scale = 1 },
		{ w = 1367, h = 769, scale = 1 },
		{ w = 1921, h = 1081, scale = 1 },
		{ w = 2560, h = 1440, scale = 2 },
		{ w = 800, h = 450, scale = 0.625 },
	}
	for _, sc in screens do
		local vp = D.Vector2.new(sc.w, sc.h)
		G.setViewport(vp)
		G.run(0.1)
		local ok, which = onPixels(vp)
		local menuScale = menu:FindFirstChildOfClass("UIScale").Scale
		check(math.abs(uiScale.Scale - sc.scale) < 1e-9 and math.abs(menuScale - sc.scale) < 1e-9 and ok, string.format("%dx%d: scale %.3f, centred panels on whole pixels %s", sc.w, sc.h, uiScale.Scale, which))
	end
	G.setViewport(D.Vector2.new(1280, 720))
	G.run(0.1)
	-- a message that arrives while the last one is fading stays fully opaque
	local re = G.game:GetService("ReplicatedStorage").Remotes.RaceEvent
	local function serverFire(kind: string, data: any)
		G.spawnIn(G.serverCtx, function()
			re:FireClient(A, kind, data)
		end)
	end
	local toast = hud().Toast
	local outline = toast:FindFirstChildOfClass("UIStroke")
	serverFire("Chequered", {})
	G.run(3.3)
	check(toast.TextTransparency > 0.2 and toast.TextTransparency < 0.9 and outline.Transparency > toast.TextTransparency * 0.5, string.format("an old message fades, outline with it (text %.2f, outline %.2f)", toast.TextTransparency, outline.Transparency))
	serverFire("AllReady", {})
	local worst = 0
	G.run(2, function()
		worst = math.max(worst, toast.TextTransparency, outline.Transparency - 0.3)
		return false
	end)
	check(worst < 0.01 and toast.Text:find("EVERYONE") ~= nil, string.format("the new one stays sharp (worst fade %.2f)", worst))
	G.run(1.5)
	check(toast.TextTransparency > 0.99 and outline.Transparency > 0.99, "and fades out cleanly when its time is up")
	noErrors("HUD text")
	driveA = true
	pilotA.hint = nil
end

----------------------------------------------------------------------------
print("== Camera and minimap ==")
do
	local cam = ws.CurrentCamera
	local c = kartOf(A).PrimaryPart
	check(cam.CameraType.Name == "Scriptable", "chase camera active while driving (" .. tostring(cam.CameraType) .. ")")
	local d = (cam.CFrame.Position - c.Position).Magnitude
	check(d > 8 and d < 22, string.format("camera follows the kart (%.1f studs away)", d))
	local dots = 0
	for _, f in hud().Minimap:GetChildren() do
		if f:IsA("Frame") and f.ZIndex >= 5 then
			dots += 1
		end
	end
	check(dots == 1, string.format("minimap shows the kart (%d dots)", dots))

	-- mouse wheel zoom out / in
	local function camDist(): number
		return (cam.CFrame.Position - kartOf(A).PrimaryPart.Position).Magnitude
	end
	for _ = 1, 4 do
		G.wheel(-1)
		G.run(0.05)
	end
	G.run(1)
	local far = camDist()
	check(far > d * 1.6, string.format("wheel zooms out (%.1f -> %.1f studs)", d, far))
	for _ = 1, 4 do
		G.wheel(1)
		G.run(0.05)
	end
	G.run(1)
	check(math.abs(camDist() - d) < 2, string.format("wheel zooms back in (%.1f studs)", camDist()))

	-- keep zooming in: the camera drops into the cockpit
	local CamMod = Game.clientModule(G, clientA, "ChaseCamera")
	local CamCfg = Game.sharedModule(G, clientA, "Config").Camera
	for _ = 1, 12 do
		G.wheel(1)
		G.run(0.05)
	end
	G.run(0.5)
	local k = kartOf(A).PrimaryPart
	local eye = CamCfg.Cockpit.Eye
	local eyeWorld = k.CFrame:PointToWorldSpace(Vector3.new(eye[1], eye[2] - cfg.RideHeight, -eye[3]))
	check(CamMod.isCockpit(), "zooming in far enough switches to the cockpit")
	check((cam.CFrame.Position - eyeWorld).Magnitude < 0.4, string.format("cockpit camera sits at the driver's eyes (%.2f studs off)", (cam.CFrame.Position - eyeWorld).Magnitude))
	local lookFwd = cam.CFrame.LookVector:Dot(k.CFrame.LookVector)
	check(lookFwd > 0.95, string.format("cockpit view looks down the road (%.3f)", lookFwd))
	check(math.abs(cam.FieldOfView - CamCfg.Cockpit.Fov) < CamCfg.Cockpit.FovSpeedGain + 1, string.format("cockpit field of view %.1f", cam.FieldOfView))
	local head = A.Character:FindFirstChild("Head")
	check(head ~= nil and head.LocalTransparencyModifier == 1, "own head hidden in the cockpit")
	local gloves = 0
	for _, part in ws.KartVisuals["Kart_" .. A.UserId]:GetChildren() do
		if part.Name == "CockpitGlove" and part.Transparency == 0 then
			gloves += 1
			-- the hands are on the wheel rim, in front of the eyes and below them
			local rel = k.CFrame:PointToObjectSpace(part.Position)
			if not (rel.Z < 0 and part.Position.Y < cam.CFrame.Position.Y) then
				gloves -= 10
			end
		end
	end
	check(gloves == 2, "both gloves on the steering wheel in front of the driver")
	-- the wheel itself is in view (lower part of the screen)
	local wheelTop = nil
	for _, part in ws.KartVisuals["Kart_" .. A.UserId]:GetChildren() do
		if part.Name == "WheelRim" then
			local rel = cam.CFrame:PointToObjectSpace(part.Position)
			local vAngle = math.deg(math.atan2(rel.Y, -rel.Z))
			if not wheelTop or vAngle > wheelTop then
				wheelTop = vAngle
			end
		end
	end
	check(wheelTop ~= nil and wheelTop < -8 and wheelTop > -cam.FieldOfView / 2, string.format("top of the steering wheel visible at %.1f deg below the view centre", wheelTop or 0))

	-- free look with the right mouse button, then recentre
	G.mouseButton2(true)
	G.mouseMove(240, 0)
	G.run(0.1)
	local sideLook = cam.CFrame.LookVector:Dot(kartOf(A).PrimaryPart.CFrame.RightVector)
	check(sideLook > 0.5, string.format("right-drag looks to the side (%.2f)", sideLook))
	check(G.services.UserInputService.MouseBehavior.Name == "LockCurrentPosition", "mouse locked while looking")
	G.mouseButton2(false)
	G.run(1.2)
	local back = cam.CFrame.LookVector:Dot(kartOf(A).PrimaryPart.CFrame.LookVector)
	check(back > 0.95, string.format("view recentres after letting go (%.3f)", back))
	check(G.services.UserInputService.MouseBehavior.Name == "Default", "mouse released")

	-- wheel out of the cockpit, then C cycles the presets
	G.wheel(-1)
	G.run(0.6)
	check(not CamMod.isCockpit() and head.LocalTransparencyModifier == 0, "wheel out leaves the cockpit and shows the avatar again")
	check(math.abs(CamMod.zoom() - CamCfg.MinDistance) < 0.01, string.format("closest chase distance after the cockpit (%.1f)", CamMod.zoom()))
	local seen = {}
	for _ = 1, 3 do
		G.pressKey("C")
		G.run(0.1)
		G.releaseKey("C")
		table.insert(seen, CamMod.zoom())
	end
	check(seen[1] == 13 and seen[2] == 22 and seen[3] == 0, "C cycles near / far / cockpit: " .. table.concat(seen, ", "))
	G.pressKey("C")
	G.run(0.1)
	G.releaseKey("C")
	G.run(1)
	check(CamMod.zoom() == 13 and not CamMod.isCockpit(), "and back to the normal chase view")

	-- behind the kart: right-drag swings the camera around and it stays there
	local function camAngle(): (number, number)
		local kk = kartOf(A).PrimaryPart
		local rel = cam.CFrame.Position - kk.Position
		local flatRel = Vector3.new(rel.X, 0, rel.Z).Unit
		local behind = -Vector3.new(kk.CFrame.LookVector.X, 0, kk.CFrame.LookVector.Z).Unit
		local yaw = math.deg(math.acos(math.clamp(flatRel:Dot(behind), -1, 1)))
		local elev = math.deg(math.asin(math.clamp(rel.Unit.Y, -1, 1)))
		return yaw, elev
	end
	local _, elev0 = camAngle()
	G.mouseButton2(true)
	G.mouseMove(360, 0)
	G.mouseMove(0, 80)
	G.run(0.1)
	G.mouseButton2(false)
	G.run(2)
	local yawOff, elev1 = camAngle()
	check(yawOff > 60, string.format("right-drag swings the camera around the kart (%.0f deg from behind)", yawOff))
	check(elev1 > elev0 + 10, string.format("dragging down raises it (%.0f -> %.0f deg)", elev0, elev1))
	G.run(2)
	local yawLater = camAngle()
	check(math.abs(yawLater - yawOff) < 12, string.format("it stays there while driving (%.0f deg after 2 s more)", yawLater))
	G.pressKey("V")
	G.run(0.1)
	G.releaseKey("V")
	G.run(1.5)
	local yawBack, elevBack = camAngle()
	check(yawBack < 15 and math.abs(elevBack - elev0) < 6, string.format("V puts it back behind (%.0f deg, elevation %.0f)", yawBack, elevBack))
	noErrors("camera")
end

----------------------------------------------------------------------------
print("== Settings menu ==")
do
	local sgui = A.PlayerGui:FindFirstChild("SettingsGui")
	check(sgui ~= nil and sgui.SettingsButton.Visible, "SETTINGS button on screen")
	check(A:GetAttribute("S_Units") == "KMH" and A:GetAttribute("S_Camera") == "Near" and A:GetAttribute("S_MasterVolume") == 1, "server sends the player's settings (defaults)")
	local panel = sgui.Panel
	check(not panel.Visible, "settings panel closed at first")
	sgui.SettingsButton.Activated:Fire()
	G.run(0.2)
	check(panel.Visible, "SETTINGS opens the panel")
	check(sfxPlayed("Click"), "buttons click")
	local rows = 0
	for _, r in panel:GetChildren() do
		if r.Name:sub(1, 4) == "Row_" then
			rows += 1
		end
	end
	check(rows == #Config.Settings.Order, string.format("one row per setting (%d)", rows))
	-- speed units
	panel.Row_Units.Right.Activated:Fire()
	G.run(0.5)
	check(A:GetAttribute("S_Units") == "MPH" and panel.Row_Units.Value.Text == "MPH", "units switched to MPH (server has it too)")
	local c = kartOf(A).PrimaryPart
	local mph = math.abs(c.AssemblyLinearVelocity:Dot(c.CFrame.LookVector)) * Config.KmhPerStudPerSecond * 0.621371
	local shown = tonumber(hud().Speed.Value.Text) or -1
	check(hud().Speed.Unit.Text == "MPH" and math.abs(shown - mph) < 6, string.format("speedometer in MPH (%d, kart at %.0f)", shown, mph))
	-- volume: five clicks down (sent faster than the server echoes them)
	for _ = 1, 5 do
		panel.Row_MasterVolume.Left.Activated:Fire()
	end
	G.run(0.5)
	local engineGroup = SoundService:FindFirstChild("KartEngine")
	local effectsGroup = SoundService:FindFirstChild("KartEffects")
	check(A:GetAttribute("S_MasterVolume") == 0.5 and panel.Row_MasterVolume.Value.Text == "50%", "master volume 50% after five clicks: " .. panel.Row_MasterVolume.Value.Text)
	check(engineGroup and math.abs(engineGroup.Volume - 0.4) < 1e-6 and effectsGroup and math.abs(effectsGroup.Volume - 0.4) < 1e-6, string.format("sound groups follow (engine %.2f, effects %.2f)", engineGroup and engineGroup.Volume or -1, effectsGroup and effectsGroup.Volume or -1))
	-- minimap size and off
	panel.Row_Minimap.Right.Activated:Fire()
	G.run(0.3)
	check(hud().Minimap.Visible and hud().Minimap.Size.X.Offset == 280, "large minimap")
	panel.Row_Minimap.Right.Activated:Fire()
	G.run(0.3)
	check(not hud().Minimap.Visible and A:GetAttribute("S_Minimap") == "Off", "minimap off (options wrap round)")
	panel.Row_Minimap.Left.Activated:Fire()
	panel.Row_Minimap.Left.Activated:Fire()
	G.run(0.3)
	check(hud().Minimap.Visible and hud().Minimap.Size.X.Offset == 210 and A:GetAttribute("S_Minimap") == "Normal", "back to the normal minimap")
	-- starting camera
	local CamMod = Game.clientModule(G, clientA, "ChaseCamera")
	panel.Row_Camera.Right.Activated:Fire()
	G.run(0.3)
	check(CamMod.zoom() == 22, string.format("camera setting Far moves the camera out (%.1f)", CamMod.zoom()))
	panel.Row_Camera.Left.Activated:Fire()
	G.run(0.3)
	check(CamMod.zoom() == 13, "and Near brings it back")
	-- steering speed: a bad value from a client is clamped by the server
	G.spawnIn(clientA, function()
		G.game:GetService("ReplicatedStorage").Remotes.Request:FireServer("Setting", { key = "SteerSpeed", value = 99 })
		G.game:GetService("ReplicatedStorage").Remotes.Request:FireServer("Setting", { key = "Nonsense", value = 1 })
	end)
	G.run(0.3)
	check(A:GetAttribute("S_SteerSpeed") == 1.6 and A:GetAttribute("S_Nonsense") == nil, "server clamps settings and ignores unknown ones")
	for _ = 1, 6 do
		panel.Row_SteerSpeed.Left.Activated:Fire()
	end
	G.run(0.3)
	check(math.abs((A:GetAttribute("S_SteerSpeed") or 0) - 1) < 1e-6, "steering speed back to 100%: " .. panel.Row_SteerSpeed.Value.Text)
	panel.Done.Activated:Fire()
	G.run(0.2)
	check(not panel.Visible, "DONE closes the panel")
	-- saved with the player's data a few seconds later
	G.run(9)
	local saved = G.datastore["ApexKarting_v1/p_101"]
	check(type(saved) == "table" and type(saved.settings) == "table" and saved.settings.Units == "MPH" and saved.settings.MasterVolume == 0.5, "settings saved to the DataStore")
	noErrors("settings")
end

----------------------------------------------------------------------------
print("== Keyboard steering ramps in ==")
do
	driveA = false
	G.gamepad = { r2 = 0.6, l2 = 0, x = 0 }
	G.run(1)
	G.pressKey("D")
	G.run(0.1)
	local early = KC.telemetry().steerAngle
	G.run(0.6)
	local later = KC.telemetry().steerAngle
	G.releaseKey("D")
	G.run(0.8)
	local after = KC.telemetry().steerAngle
	check(early > 0 and early < later * 0.5, string.format("D key: wheels at %.1f deg after 0.1 s, %.1f deg after 0.7 s (no snap)", math.deg(early), math.deg(later)))
	check(math.abs(after) < math.abs(later) * 0.2, string.format("released: back to %.1f deg", math.deg(after)))
	noErrors("keyboard steering")
	driveA = true
	pilotA.hint = nil
end

----------------------------------------------------------------------------
print("== Recovery ==")
do
	-- flip the kart onto its roof in the grass: it must come back by itself
	driveA = false
	G.gamepad = { r2 = 0, l2 = 0, x = 0 }
	local k = kartOf(A)
	local c = k.PrimaryPart
	local smp = track.samples[60]
	local off = smp.pos + smp.right * (smp.width / 2 + 25) + Vector3.new(0, 3, 0)
	k:PivotTo(D.CFrame.lookAt(off, off + smp.fwd) * D.CFrame.Angles(0, 0, math.pi))
	c.AssemblyLinearVelocity = Vector3.zero
	c.AssemblyAngularVelocity = Vector3.zero
	local recovered = G.run(8, function()
		local kk = kartOf(A)
		if not kk then
			return false
		end
		local cc = kk.PrimaryPart
		local i, lat = TrackMath.nearest(track, cc.Position)
		return cc.CFrame.UpVector.Y > 0.9 and math.abs(lat) < track.samples[i].width / 2
	end)
	check(recovered, "upside-down kart resets itself onto the track")
	-- R key: drive onto the grass, press R
	G.run(1)
	k = kartOf(A)
	c = k.PrimaryPart
	local smp2 = track.samples[200]
	local grass = smp2.pos + smp2.right * (smp2.width / 2 + 30) + Vector3.new(0, 1.2, 0)
	k:PivotTo(D.CFrame.lookAt(grass, grass + smp2.fwd))
	c.AssemblyLinearVelocity = Vector3.zero
	G.run(4)
	G.pressKey("R")
	G.run(0.5)
	G.releaseKey("R")
	G.run(1)
	local i2, lat2 = TrackMath.nearest(track, kartOf(A).PrimaryPart.Position)
	check(math.abs(lat2) < 3, string.format("R puts the kart back on the racing line (lateral %.1f, sample %d)", lat2, i2))
	noErrors("recovery")
	driveA = true
	pilotA.hint = nil
end

----------------------------------------------------------------------------
print("== Wrong way ==")
do
	pilotA.reverse = true
	local warned = G.run(15, function()
		return hud().Warning.Visible and hud().Warning.Text == "WRONG WAY"
	end)
	check(warned, "driving backwards shows WRONG WAY")
	check(A:GetAttribute("WrongWay") == true, "server flags the wrong way")
	pilotA.reverse = false
	pilotA.hint = nil
	-- turn around: reset puts us facing the right way
	G.run(3.5)
	G.pressKey("R")
	G.run(0.3)
	G.releaseKey("R")
	local cleared = G.run(8, function()
		return not hud().Warning.Visible
	end)
	check(cleared, "warning clears once going the right way")
end

----------------------------------------------------------------------------
print("== Walk / drive toggle ==")
do
	G.pressKey("K")
	G.run(0.3)
	G.releaseKey("K")
	G.run(1)
	check(kartOf(A) == nil, "K leaves the kart")
	check(not KC.isDriving() and A._props._controls.enabled, "walking controls restored")
	check(ws.CurrentCamera.CameraType.Name == "Custom", "normal camera when walking")
	check(hud().Drive.Text:find("DRIVE") ~= nil, "button offers DRIVE")
	G.run(3)
	check(kartOf(A) == nil, "stays walking (no kart forced on the player)")
	G.pressKey("K")
	G.run(0.3)
	G.releaseKey("K")
	G.run(1)
	check(kartOf(A) ~= nil and KC.isDriving(), "K again gets a kart")
	noErrors("toggle")
end

----------------------------------------------------------------------------
print("== Track panel: switching track in practice ==")
local stored = G.game:GetService("ServerStorage"):FindFirstChild("Circuits")
do
	local ready = G.run(90, function()
		local list = ws:GetAttribute("Tracks") or ""
		for _, id in TrackData.Order do
			if not list:find(id) then
				return false
			end
		end
		return true
	end)
	check(ready, "every circuit built after start-up: " .. tostring(ws:GetAttribute("Tracks")))
	check(stored ~= nil and stored:FindFirstChild("Silverstone") ~= nil, "they wait in ServerStorage")
	-- each new kart circuit brings its own scenery
	local lake = stored:FindFirstChild("Lakeside") and stored.Lakeside.Track:FindFirstChild("Lake")
	local water = lake and lake:FindFirstChild("Water")
	check(water ~= nil and water:GetAttribute("Surface") == "Water", "Lakeside has a lake (in the Track folder, slows karts)")
	local trees = stored:FindFirstChild("Hillside") and stored.Hillside:FindFirstChild("Trees")
	local trunks = 0
	if trees then
		for _, t in trees:GetChildren() do
			if t.Name == "Trunk" then
				trunks += 1
			end
		end
	end
	check(trunks >= 20, string.format("Hillside has pines (%d)", trunks))
	local lampsFolder = stored:FindFirstChild("Harbour") and stored.Harbour:FindFirstChild("TrackLights")
	local spots = 0
	if lampsFolder then
		for _, d in lampsFolder:GetDescendants() do
			if d:IsA("SpotLight") then
				spots += 1
			end
		end
	end
	check(spots >= 40, string.format("Harbour has lamp posts along the track (%d lights)", spots))
	local pbFirst = A:GetAttribute("PersonalBest")
	local recFirst = ws:GetAttribute("TrackRecord")
	check(hud().TrackButton.Visible, "TRACK button shown in practice")
	check(not hud().Tracks.Visible, "track panel closed until asked for")
	G.pressKey("M")
	G.run(0.2)
	G.releaseKey("M")
	G.run(0.2)
	local cards = 0
	for _, c in hud().Tracks.Cards:GetChildren() do
		if c.Name:sub(1, 5) == "Card_" and c.Visible then
			cards += 1
		end
	end
	check(hud().Tracks.Visible and cards == #TrackData.Order, string.format("M opens the track panel (%d cards)", cards))
	check(hud().Tracks.Cards.Card_Tampines.Tag.Text == "NOW", "current track marked NOW")
	G.pressKey("Two")
	G.run(0.2)
	G.releaseKey("Two")
	local switched = G.run(5, function()
		return ws:GetAttribute("Track") == "Silverstone"
	end)
	check(switched, "key 2 switches practice to Silverstone")
	G.run(1)
	check(kartOf(A) == nil, "no kart while the new circuit loads")
	G.run(5, function()
		return kartOf(A) ~= nil and KC.isDriving()
	end)
	G.run(0.5)
	check(ws.Circuit:GetAttribute("TrackId") == "Silverstone" and stored:FindFirstChild("Tampines") ~= nil, "Silverstone in workspace, Tampines put away")
	check(ws:GetAttribute("Laps") == TrackData.get("Silverstone").Laps, "lap count follows the track")
	check(hud().Minimap.TrackName.Text == "SILVERSTONE", "minimap redrawn for " .. hud().Minimap.TrackName.Text)
	check(not hud().Tracks.Visible, "panel closes after switching")
	check(kartOf(A) ~= nil and KC.isDriving(), "practice kart again, on the new track")
	check(A:GetAttribute("PersonalBest") == nil and ws:GetAttribute("TrackRecord") == nil, "best lap and record are per track")
	checkGeometry("Silverstone")
	local crowd = 0
	for _, d in ws.Circuit.Grandstands:GetDescendants() do
		if d:IsA("Sound") and d.Name == "Crowd" and d.IsPlaying then
			crowd += 1
		end
	end
	check(crowd > 0, string.format("crowd noise at the grandstands (%d)", crowd))
	-- drive a third of a lap: Abbey, Farm, Village, the Loop, Aintree
	G.run(28)
	local k = kartOf(A)
	local i, lat = TrackMath.nearest(track, k.PrimaryPart.Position)
	check(math.abs(lat) < track.samples[i].width / 2 and i > track.n * 0.2, string.format("drives Silverstone (sample %d of %d, lateral %.1f)", i, track.n, lat))
	noErrors("Silverstone practice")
	-- and back for the rest of the test
	G.pressKey("M")
	G.run(0.2)
	G.releaseKey("M")
	G.pressKey("One")
	G.run(0.2)
	G.releaseKey("One")
	local back = G.run(5, function()
		return ws:GetAttribute("Track") == "Tampines"
	end)
	G.run(5, function()
		return kartOf(A) ~= nil and KC.isDriving()
	end)
	check(back and ws.Circuit:GetAttribute("TrackId") == "Tampines", "key 1 switches back")
	check(A:GetAttribute("PersonalBest") == pbFirst and ws:GetAttribute("TrackRecord") == recFirst, "first track's best lap and record come back")
	noErrors("track switching")

	-- the night circuit: dark sky, the lamps light the track
	local lighting = G.game:GetService("Lighting")
	G.run(3.5) -- track change cooldown
	G.pressKey("M")
	G.run(0.2)
	G.releaseKey("M")
	G.pressKey("Five")
	G.run(0.2)
	G.releaseKey("Five")
	local night = G.run(5, function()
		return ws:GetAttribute("Track") == "Harbour"
	end)
	G.run(5, function()
		return kartOf(A) ~= nil and KC.isDriving()
	end)
	G.run(0.5)
	check(night and ws.Circuit:GetAttribute("TrackId") == "Harbour", "key 5 switches practice to the Harbour Night Circuit")
	-- night, but with enough fill light to read the road on a phone
	check(lighting.ClockTime > 20 and lighting.Ambient.R > 0.35 and lighting.ExposureCompensation >= 0.5, string.format("it is night there (clock %.1f) but the road stays readable (ambient %.2f)", lighting.ClockTime, lighting.Ambient.R))
	checkGeometry("Harbour Night Circuit")
	G.run(15)
	local k = kartOf(A)
	local i, lat = TrackMath.nearest(track, k.PrimaryPart.Position)
	check(math.abs(lat) < track.samples[i].width / 2 and i > 20, string.format("drives the night circuit (sample %d of %d)", i, track.n))
	noErrors("night circuit")

	-- the hill circuit: embankments under the raised road, drive up the hill
	G.run(3.5)
	G.pressKey("M")
	G.run(0.2)
	G.releaseKey("M")
	G.pressKey("Four")
	G.run(0.2)
	G.releaseKey("Four")
	local hill = G.run(5, function()
		return ws:GetAttribute("Track") == "Hillside"
	end)
	G.run(5, function()
		return kartOf(A) ~= nil and KC.isDriving()
	end)
	G.run(0.5)
	check(hill and ws.Circuit:GetAttribute("TrackId") == "Hillside", "key 4 switches practice to Hillside Raceway")
	check(math.abs(lighting.ClockTime - 14.6) < 0.01, "back in daylight")
	checkGeometry("Hillside Raceway", true)
	local top = 0
	G.run(25, function()
		local kk = kartOf(A)
		if kk and kk.PrimaryPart then
			top = math.max(top, kk.PrimaryPart.Position.Y)
		end
		return nil
	end)
	k = kartOf(A)
	i, lat = TrackMath.nearest(track, k.PrimaryPart.Position)
	check(math.abs(lat) < track.samples[i].width / 2 and i > 60, string.format("drives up the hill (sample %d of %d, up to %.1f studs)", i, track.n, top))
	check(top > 20, "reaches the top of the hill")
	noErrors("hill circuit")
	G.run(3.5)
	G.pressKey("M")
	G.run(0.2)
	G.releaseKey("M")
	G.pressKey("One")
	G.run(0.2)
	G.releaseKey("One")
	G.run(5, function()
		return ws:GetAttribute("Track") == "Tampines"
	end)
	G.run(5, function()
		return kartOf(A) ~= nil and KC.isDriving()
	end)
	check(ws.Circuit:GetAttribute("TrackId") == "Tampines" and math.abs(lighting.ClockTime - 14.6) < 0.01, "and back to Tampines in daylight")
	noErrors("back to the first circuit")
end

----------------------------------------------------------------------------
print("== Second player: intermission, ready, qualifying, grid, lights ==")
-- qualifying is one timed lap: time enough for the run-up and a slow lap on
-- the first track, next to none on the second (the server reads these when
-- a session starts)
local serverTrackData = Game.sharedModule(G, G.serverCtx, "TrackData")
serverTrackData.Tracks.Tampines.Qualifying = math.floor(lapTime * 2.5 + 20)
serverTrackData.Tracks.Silverstone.Qualifying = 0.5
B = G.addPlayer("Bob", 202)
startBot(B)
G.run(3)
noErrors("second player joins")
check(kartOf(B) ~= nil, "second player gets a practice kart")

-- bumpers: park the bot's kart overlapping ours side by side; both clients'
-- physics push the karts apart (Roblox's kart-on-kart collisions are off)
do
	check(G.collidable["Karts|Karts"] == false, "Roblox collisions between karts are off")
	G.run(2)
	check(type(A:GetAttribute("Ping")) == "number", string.format("server shares each player's ping (%s)", tostring(A:GetAttribute("Ping"))))
	driveA, holdB = false, true
	-- both karts parked on the straight, ours with no input
	G.gamepad = { r2 = 0, l2 = 0, x = 0 }
	local ca = kartOf(A).PrimaryPart
	local smp = track.samples[3]
	kartOf(A):PivotTo(D.CFrame.lookAt(smp.pos + Vector3.new(0, cfg.RideHeight + 0.05, 0), smp.pos + Vector3.new(0, cfg.RideHeight + 0.05, 0) + smp.fwd))
	ca.AssemblyLinearVelocity = Vector3.zero
	ca.AssemblyAngularVelocity = Vector3.zero
	G.run(1)
	check(ca.AssemblyLinearVelocity.Magnitude < 1, string.format("our kart parked (%.2f studs/s)", ca.AssemblyLinearVelocity.Magnitude))
	local kb = kartOf(B)
	local Bumper = cfg.Bumper
	local beside = ca.CFrame * D.CFrame.new(Bumper.HalfWidth * 2 - 1.0, 0, 0)
	kb:PivotTo(beside)
	kb.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
	kb.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
	local d0 = (kb.PrimaryPart.Position - ca.Position).Magnitude
	local maxVy = 0
	G.run(2, function()
		maxVy = math.max(maxVy, math.abs(ca.AssemblyLinearVelocity.Y), math.abs(kb.PrimaryPart.AssemblyLinearVelocity.Y))
		return false
	end)
	local d1 = (kb.PrimaryPart.Position - ca.Position).Magnitude
	check(d1 > Bumper.HalfWidth * 2 - 0.15 and d1 < Bumper.HalfWidth * 2 + 1.5, string.format("overlapping karts eased apart until they just touch (%.2f -> %.2f studs between centres)", d0, d1))
	check(maxVy < 1.5 and ca.CFrame.UpVector.Y > 0.99 and kb.PrimaryPart.CFrame.UpVector.Y > 0.99, string.format("without launching either (vertical %.2f studs/s)", maxVy))
	check(KC.telemetry() ~= nil, "the driver's client felt the contact")
	driveA, holdB = true, false
	pilotA.hint, pilotB.hint = nil, nil
	noErrors("bumpers")
end
check(ws:GetAttribute("RaceState") == "Intermission", "two players -> Intermission")
check(hud().Banner.Text.Text:find("QUALIFYING IN") ~= nil, "banner counts down to qualifying: " .. hud().Banner.Text.Text)
do
	local panel = hud().Tracks
	check(panel.Visible and panel.Length.Visible and panel.Ready.Visible, "vote panel with race length and READY")
	local short = TrackData.get("Tampines").Lengths[1]
	check(panel.Length.Short.Text:find("SHORT " .. short) ~= nil, "length buttons show the laps: " .. panel.Length.Short.Text)
	panel.Length.Short.Activated:Fire()
	botRequest("Length", "Short")
	G.run(0.4)
	check(A:GetAttribute("LengthVote") == "Short" and ws:GetAttribute("LenVotes_Short") == 2, "both vote for a short race")
	panel.Ready.Activated:Fire()
	G.run(0.4)
	check(A:GetAttribute("Ready") == true and ws:GetAttribute("ReadyCount") == 1, "READY counts the first player")
	check(panel.Ready.Text:find("READY!") ~= nil and panel.Title.Text:find("1/2 READY") ~= nil, "panel shows it: " .. panel.Title.Text)
	local before = ws:GetAttribute("StateEnd") - ws:GetServerTimeNow()
	botRequest("Ready", true)
	G.run(0.4)
	local left = ws:GetAttribute("StateEnd") - ws:GetServerTimeNow()
	check(before > 6 and left <= Config.Race.ReadyCountdown + 0.1, string.format("everyone ready: the countdown drops to %.1f s (was %.1f)", left, before))
	check(hud().Toast.Text:find("EVERYONE IS READY") ~= nil, "toast: " .. hud().Toast.Text)
end
local quali = G.run(6, function()
	return ws:GetAttribute("RaceState") == "Qualifying"
end)
check(quali, "intermission ends -> Qualifying")
check(ws:GetAttribute("Track") == "Tampines", "no track votes: the track stays")
check(A:GetAttribute("Ready") == nil and ws:GetAttribute("ReadyCount") == 0, "READY cleared for next time")
-- The bot drives slower, so the grid order is known.
pilotB.pace = 0.75
local qStart = G.time
G.run(0.5)
do
	local kq, kb = kartOf(A), kartOf(B)
	check(kq ~= nil and kb ~= nil and not kq.PrimaryPart.Anchored and A:GetAttribute("InRace") == true and B:GetAttribute("InRace") == true, "both out on track in qualifying (karts free)")
	-- one timed lap with ghosts: everyone from the same spot before the line
	local _, _, sArc = TrackMath.nearest(track, kq.PrimaryPart.Position)
	local behind = -TrackMath.arcDelta(track, sArc, 0)
	local apart = (kq.PrimaryPart.Position - kb.PrimaryPart.Position).Magnitude
	check(math.abs(behind - Config.Race.QualiRunUp) < 15 and apart < 6, string.format("one-lap qualifying: both start together %.0f studs before the line (%.1f studs apart)", behind, apart))
	check(ws:GetAttribute("Ghost") == true, "ghost mode on in qualifying")
	check(hud().Banner.Text.Text:find("CLOCK STARTS AT THE LINE") ~= nil, "banner: " .. hud().Banner.Text.Text)
	check(hud().Big.Text == "QUALIFYING" and hud().Position.Visible and hud().Position.Lap.Text == "QUALIFYING", "QUALIFYING shown with the position panel")
	-- driving through each other: no bumper contact, the other kart see-through
	local contact = 0
	G.run(1.5, function()
		local tele = KC.telemetry()
		if tele then
			contact = math.max(contact, tele.contact)
		end
		return false
	end)
	local apart2 = (kartOf(A).PrimaryPart.Position - kartOf(B).PrimaryPart.Position).Magnitude
	check(contact == 0, string.format("ghosts: no bumper contact while the karts overlap (%.1f studs apart after 1.5 s)", apart2))
	check(math.abs(kartOf(B).PrimaryPart.LocalTransparencyModifier - Config.Race.GhostTransparency) < 1e-6 and kartOf(A).PrimaryPart.LocalTransparencyModifier == 0, "the other kart is see-through, ours is not")
	check(KC.telemetry() ~= nil and KC.telemetry().draft == 0, "no slipstream from a ghost")
	local standingsQ, lapQ, doneToast, qBest, timedBanner = 0, false, nil, nil, false
	local lastQToast = ""
	local grid = G.run(240, function()
		if hud().Standings.Visible then
			local rows = 0
			for _, r in hud().Standings:GetChildren() do
				if r:IsA("Frame") and r.Visible then
					rows += 1
					if r.Name == "Row1" and r.Gap.Text:find(":") then
						qBest = r.Gap.Text
					end
				end
			end
			standingsQ = math.max(standingsQ, rows)
		end
		timedBanner = timedBanner or hud().Banner.Text.Text:find("ONE TIMED LAP") ~= nil
		local toast = hud().Toast
		if toast.Visible and toast.Text ~= lastQToast then
			lastQToast = toast.Text
			print(string.format("    [%.1f] %s", G.time, toast.Text))
		end
		if toast.Visible and toast.Text:find("QUALIFYING LAP") then
			doneToast = toast.Text
		end
		if toast.Visible and toast.Text:find("%d:%d%d%.%d%d%d") then
			lapQ = true
		end
		return ws:GetAttribute("RaceState") == "Grid"
	end)
	noErrors("qualifying")
	check(timedBanner, "banner while the lap is timed: ONE TIMED LAP - GHOSTS ON")
	check(standingsQ == 2, string.format("qualifying standings list both drivers (%d)", standingsQ))
	check(qBest ~= nil, "standings show the fastest lap: " .. tostring(qBest))
	check(lapQ and doneToast ~= nil and doneToast:find("P1 SO FAR") ~= nil, "our one lap is timed and placed: " .. tostring(doneToast))
	check(grid and ws:GetAttribute("Ghost") == false, "everyone done: straight on to the Grid, ghosts off")
	check(G.time - qStart < lapTime * 2.5, string.format("over once both laps are in (%.0f s, no waiting for the clock)", G.time - qStart))
	check(A:GetAttribute("GridSlot") == 1 and B:GetAttribute("GridSlot") == 2, string.format("faster lap starts on pole (A slot %s, B slot %s)", tostring(A:GetAttribute("GridSlot")), tostring(B:GetAttribute("GridSlot"))))
	check(hud().Toast.Text:find("POLE POSITION") ~= nil and hud().Toast.Text:find("Alice") ~= nil, "pole announced: " .. hud().Toast.Text)
	check(ws:GetAttribute("Laps") == TrackData.get("Tampines").Lengths[1], string.format("short race: %s laps", tostring(ws:GetAttribute("Laps"))))
	check(kartOf(B) and kartOf(B).PrimaryPart.LocalTransparencyModifier == 0, "solid again for the race")
	pilotB.pace = nil
end
G.run(0.5)
local kA2, kB2 = kartOf(A), kartOf(B)
check(kA2 ~= nil and kB2 ~= nil and kA2.PrimaryPart.Anchored and kB2.PrimaryPart.Anchored, "both karts placed on the grid, held still")
check(A:GetAttribute("InRace") == true and B:GetAttribute("InRace") == true, "both players are racers")
check(hud().Lights.Visible, "start lights shown")
local lightsSeen = {}
local gantryOn = 0
local go = G.run(12, function()
	local count = 0
	for _, d in hud().Lights:GetChildren() do
		if d:IsA("Frame") and d.BackgroundColor3.R > 0.8 then
			count += 1
		end
	end
	lightsSeen[count] = true
	local lamps = 0
	for _, l in ws.Circuit.Track.Gantry.Lights:GetChildren() do
		if l.Material.Name == "Neon" then
			lamps += 1
		end
	end
	gantryOn = math.max(gantryOn, lamps)
	return ws:GetAttribute("RaceState") == "Racing"
end)
check(go, "lights out -> Racing")
check(lightsSeen[1] and lightsSeen[3] and lightsSeen[5], "the five red lights come on one by one")
check(gantryOn == 5, "gantry lamps light up too")
G.run(0.2)
check(not kartOf(A).PrimaryPart.Anchored and kartOf(A).PrimaryPart:GetNetworkOwner() == A, "kart released to its driver at GO")
check(hud().Big.Text == "GO!", "GO! shown")
noErrors("race start")

----------------------------------------------------------------------------
print("== Racing ==")
local finishedA, resultsShown = false, false
local posSeen = {}
local lapToasts = 0
local lastToast = ""
local standingsRows = 0
local minimapDots = 0
local limitToasts = {}
local pushes, pushAt = 0, -math.huge
local onTrackSince: number? = nil
local lastWarn = 0
local raceLaps = ws:GetAttribute("Laps")
-- the bot (second on the grid) waits a moment at the start, so the two
-- autopilots don't arrive at the first corner nose to tail and knock the
-- leader off (the start hold is random, so that happened in some runs)
local raceGo = G.time
holdB = true
G.run(200, function()
	if holdB and G.time - raceGo > 1.5 then
		holdB = false
		pilotB.hint = nil
	end
	local dots = 0
	for _, f in hud().Minimap:GetChildren() do
		if f:IsA("Frame") and f.ZIndex >= 5 then
			dots += 1
		end
	end
	minimapDots = math.max(minimapDots, dots)
	local pa = A:GetAttribute("Position")
	if pa then
		posSeen[pa] = true
	end
	local toast = hud().Toast
	if toast.Visible and toast.Text ~= lastToast then
		lastToast = toast.Text
		if toast.Text:find("TRACK LIMITS") then
			table.insert(limitToasts, toast.Text)
		elseif toast.Text:find("LAP") then
			lapToasts += 1
		end
	end
	if hud().Standings.Visible then
		local rows = 0
		for _, r in hud().Standings:GetChildren() do
			if r:IsA("Frame") and r.Visible then
				rows += 1
			end
		end
		standingsRows = math.max(standingsRows, rows)
	end
	-- on the first lap, away from the pit straight: run wide four times
	-- (three warnings, then a penalty)
	-- (each time once the kart has been back on the road for a moment, so
	-- every excursion is a new one)
	local k = kartOf(A)
	if k and k.PrimaryPart then
		local i, lat = TrackMath.nearest(track, k.PrimaryPart.Position)
		if math.abs(lat) < track.samples[i].width / 2 then
			onTrackSince = onTrackSince or G.time
		else
			onTrackSince = nil
		end
	end
	if pushes < 4 and G.time - pushAt > 2.5 and onTrackSince and G.time - onTrackSince > 0.8 and k and k.PrimaryPart and not A:GetAttribute("Finished") then
		local i = TrackMath.nearest(track, k.PrimaryPart.Position)
		-- on a nearly straight bit (turf or run-off beside it, not a gravel trap)
		local straightish = math.abs(track.samples[i].curv) < 1 / 150
		if straightish and i > track.n * 0.3 and i < track.n * 0.85 and ws:GetAttribute("RaceState") == "Racing" then
			pushAt = G.time
			if pushOffTrack(k) then
				pushes += 1
			end
			pilotA.hint = nil
		end
	end
	if A:GetAttribute("Finished") then
		finishedA = true
	end
	local w = A:GetAttribute("Warnings") or 0
	if w ~= lastWarn and k and k.PrimaryPart then
		lastWarn = w
		local i, lat = TrackMath.nearest(track, k.PrimaryPart.Position)
		print(string.format("    (warning %d %.2f s after a push, sample %d, %.1f studs from the centre line)", w, G.time - pushAt, i, lat))
	end
	if hud().Results.Visible then
		resultsShown = true
		return true
	end
	return false
end)
noErrors("racing")
check(finishedA, "first player finishes the race")
check(lapToasts >= raceLaps, string.format("lap times shown for every lap (%d of %d)", lapToasts, raceLaps))
check(standingsRows == 2, string.format("live standings list both drivers (%d rows)", standingsRows))
check(minimapDots == 2, string.format("minimap shows both karts (%d dots)", minimapDots))
check(posSeen[1] ~= nil, "position shown in the HUD")
check(sfxPlayed("Go") and sfxPlayed("Finish") and sfxPlayed("Bump"), "start, finish and bump sounds")
check(sfxPlayed("Flag") and sfxPlayed("Warning") and sfxPlayed("Lap"), "qualifying flag, track-limits warning and lap sounds")
-- the autopilot can also run wide by itself now and then (a start-line
-- scuffle, say); every excursion counts, and there is a message for each
local warnings = A:GetAttribute("Warnings") or 0
check(pushes == 4 and warnings >= 4 and #limitToasts == warnings, string.format("every excursion counted, one message each (%d pushes, %d warnings, %d messages)", pushes, warnings, #limitToasts))
check(limitToasts[1] and limitToasts[1]:find("WARNING 1/3") ~= nil and limitToasts[3] and limitToasts[3]:find("WARNING 3/3") ~= nil, "first three are warnings: " .. tostring(limitToasts[1]) .. " / " .. tostring(limitToasts[3]))
check(limitToasts[4] and limitToasts[4]:find("%+" .. Config.Race.TrackLimitPenalty .. " s PENALTY") ~= nil, "the fourth costs time: " .. tostring(limitToasts[4]))
local penaltyWant = (warnings - Config.Race.TrackLimitWarnings) * Config.Race.TrackLimitPenalty
check(A:GetAttribute("Penalty") == penaltyWant, string.format("server: %d warnings -> +%s s", warnings, tostring(A:GetAttribute("Penalty"))))
check(resultsShown, "results panel shown")
local rows = {}
local penaltyShown = false
for _, r in hud().Results.List:GetChildren() do
	if r:IsA("Frame") then
		table.insert(rows, r)
		if r:FindFirstChild("Name").Text:find("Alice") then
			penaltyShown = r:FindFirstChild("Time").Text:find("%(%+" .. tostring(A:GetAttribute("Penalty")) .. "s%)") ~= nil
		end
	end
end
check(#rows == 2, string.format("results list both drivers (%d)", #rows))
check(penaltyShown, "the penalty is in the result time")
local winsA = A.leaderstats.Wins.Value
local winsB = B.leaderstats.Wins.Value
check(winsA + winsB == 1, string.format("exactly one win recorded (A %d, B %d)", winsA, winsB))
check(ws:GetAttribute("RaceState") == "Results", "state is Results")
print(string.format("    race finished at %.1f s virtual", G.time))

----------------------------------------------------------------------------
print("== Podium ==")
do
	G.run(0.3)
	local podium = ws.Circuit.Pits:FindFirstChild("Podium")
	check(podium ~= nil and podium:FindFirstChild("Step1") and podium:FindFirstChild("Step2") and podium:FindFirstChild("Step3"), "podium with three steps in the paddock")
	check(ws:GetAttribute("Podium") == true, "podium in use")
	check(sfxPlayed("Podium"), "results: the podium cheer")
	local onSteps = 0
	for _, pl in { A, B } do
		local k = kartOf(pl)
		if k and k.PrimaryPart.Anchored then
			for n = 1, 3 do
				local st = podium["Step" .. n]
				local top = st.Position + Vector3.new(0, st.Size.Y / 2, 0)
				local flat = Vector3.new(k.PrimaryPart.Position.X - top.X, 0, k.PrimaryPart.Position.Z - top.Z).Magnitude
				if flat < 1 and k.PrimaryPart.Position.Y > top.Y then
					onSteps += 1
				end
			end
		end
	end
	local finishers = 0
	for _, pl in { A, B } do
		if pl:GetAttribute("Finished") then
			finishers += 1
		end
	end
	check(finishers >= 1 and onSteps == finishers, string.format("every finisher's kart stands on a step (%d of %d)", onSteps, finishers))
	local cam = ws.CurrentCamera
	local mark = podium.Camera
	check(cam.CameraType.Name == "Scriptable" and (cam.CFrame.Position - mark.Position).Magnitude < 6, string.format("everyone looks at the podium (%.1f studs from the mark)", (cam.CFrame.Position - mark.Position).Magnitude))
	local confetti = 0
	for _, e in podium.Confetti:GetChildren() do
		if e:IsA("ParticleEmitter") and e.Enabled then
			confetti += 1
		end
	end
	check(confetti > 0, "confetti")
	check(hud().Banner.Text.Text:find("PODIUM") ~= nil, "banner: " .. hud().Banner.Text.Text)
	local resultsEnd = ws:GetAttribute("StateEnd") - ws:GetServerTimeNow()
	check(resultsEnd <= Config.Race.ResultsTime + 0.1, string.format("short podium: next round in %.1f s", resultsEnd))
end

----------------------------------------------------------------------------
print("== Back to practice ==")
local back = G.run(15, function()
	return ws:GetAttribute("RaceState") == "Intermission"
end)
check(back, "results -> Intermission again")
G.run(1)
check(kartOf(A) ~= nil and kartOf(B) ~= nil, "everyone gets a practice kart again")
check(KC.isDriving(), "client driving again")
do
	local podium = ws.Circuit.Pits.Podium
	local confetti = 0
	for _, e in podium.Confetti:GetChildren() do
		if e:IsA("ParticleEmitter") and e.Enabled then
			confetti += 1
		end
	end
	check(confetti == 0 and ws:GetAttribute("Podium") == false, "podium over, confetti off")
	local cam = ws.CurrentCamera
	local d = (cam.CFrame.Position - kartOf(A).PrimaryPart.Position).Magnitude
	check(cam.CameraType.Name == "Scriptable" and d < 25, string.format("camera back behind our kart (%.1f studs)", d))
	check(A:GetAttribute("Warnings") == nil and A:GetAttribute("Penalty") == nil, "warnings and penalties cleared")
end
noErrors("after the race")

----------------------------------------------------------------------------
print("== Track vote ==")
do
	check(hud().Tracks.Visible and hud().Tracks.Title.Text:find("NEXT RACE") ~= nil, "vote panel opens by itself: " .. hud().Tracks.Title.Text)
	hud().Tracks.Cards.Card_Silverstone.Activated:Fire()
	G.run(0.5)
	check(A:GetAttribute("Vote") == "Silverstone", "clicking a card votes")
	G.spawnIn(botCtx, function()
		G.game:GetService("ReplicatedStorage").Remotes.Request:FireServer("Vote", "Silverstone")
	end)
	G.run(0.5)
	check(ws:GetAttribute("Votes_Silverstone") == 2 and ws:GetAttribute("Votes_Tampines") == 0, "server counts both votes")
	check(hud().Tracks.Cards.Card_Silverstone.Votes.Text == "2", "card shows the count")
	check(ws:GetAttribute("Track") == "Tampines", "the track only changes when the race starts")
	local shortSil = TrackData.get("Silverstone").Lengths[1]
	check(hud().Tracks.Length.Short.Text:find("SHORT " .. shortSil) ~= nil, "length buttons show the voted track's laps: " .. hud().Tracks.Length.Short.Text)
	hud().Tracks.Length.Short.Activated:Fire()
	botRequest("Length", "Short")
	hud().Tracks.Ready.Activated:Fire()
	botRequest("Ready", true)
	G.run(0.5)
	check(ws:GetAttribute("ReadyCount") == 2, "both ready")
	noErrors("vote")
end


----------------------------------------------------------------------------
print("== Second race: a crash and a player leaving ==")
do
	local sawQuali = false
	local grid = G.run(60, function()
		sawQuali = sawQuali or ws:GetAttribute("RaceState") == "Qualifying"
		return ws:GetAttribute("RaceState") == "Racing"
	end)
	check(grid and sawQuali, "qualifying, then the next race starts")
	check(ws:GetAttribute("Laps") == TrackData.get("Silverstone").Lengths[1], "short race on the new track: " .. tostring(ws:GetAttribute("Laps")))
	check(A:GetAttribute("GridSlot") ~= nil and B:GetAttribute("GridSlot") ~= nil, "no qualifying times: everyone still gets a grid slot")
	check(ws:GetAttribute("Track") == "Silverstone" and ws.Circuit:GetAttribute("TrackId") == "Silverstone", "it runs on the voted track")
	check(A:GetAttribute("Vote") == nil, "votes cleared for the next time")
	G.run(12)
	-- the first player "dies" mid-race: they come back in a new kart and carry on
	local lapBefore = A:GetAttribute("Lap")
	G.kill(A)
	G.run(1)
	check(kartOf(A) == nil, "kart removed when the driver dies")
	local back2 = G.run(10, function()
		return kartOf(A) ~= nil and KC.isDriving()
	end)
	check(back2, "driver respawns into a new kart and keeps racing")
	pilotA.hint = nil
	check(A:GetAttribute("InRace") == true, "still in the race after respawning")
	G.run(10)
	-- the second player leaves
	G.removePlayer(B)
	G.run(2)
	check(kartOf(B) == nil, "leaving player's kart removed")
	check(G.datastore["ApexKarting_v1/p_202"] ~= nil, "leaving player's stats saved")
	local done = G.run(320, function()
		return ws:GetAttribute("RaceState") == "Results"
	end)
	check(done, "race finishes with the remaining driver")
	check(A:GetAttribute("Finished") == true, string.format("remaining driver finished (lap was %s)", tostring(lapBefore)))
	G.run(12)
	check(ws:GetAttribute("RaceState") == "Practice", "one player left -> Practice")
	noErrors("second race")
end

print(string.format("\nelapsed %.1fs real, %.1fs virtual", os.clock() - clock0, G.time))
print(string.format("%d/%d passed", pass, total))
