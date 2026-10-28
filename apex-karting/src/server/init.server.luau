--!strict
-- Server entry point: finds out what this server is for (Session: a public
-- lobby, or a reserved practice / race / room server), builds the circuits,
-- then runs the race loop in that mode and the lobby's menu requests.
-- The first circuit (the one asked for, else the default) is built first and
-- goes live straight away; the others are built right after into
-- ServerStorage, ready to be voted in. A published lobby only shows one
-- circuit behind the menu, so it builds just that one.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local TrackData = require(Shared:WaitForChild("TrackData"))
local TrackLayout = require(Shared:WaitForChild("TrackLayout"))

local TrackBuilder = require(script:WaitForChild("TrackBuilder"))
local Scenery = require(script:WaitForChild("Scenery"))
local RaceManager = require(script:WaitForChild("RaceManager"))
local Stats = require(script:WaitForChild("Stats"))
local Session = require(script:WaitForChild("Session"))
local Lobby = require(script:WaitForChild("Lobby"))
local Rooms = require(script:WaitForChild("Rooms"))

-- Remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local raceEvent = Instance.new("RemoteEvent")
raceEvent.Name = "RaceEvent"
raceEvent.Parent = remotes
local request = Instance.new("RemoteEvent")
request.Name = "Request"
request.Parent = remotes
remotes.Parent = ReplicatedStorage

-- Collision groups: karts hit the world and each other; walking players and
-- seated drivers pass through karts (nobody gets run over in the paddock).
for _, name in { "Karts", "Drivers", "Players" } do
	PhysicsService:RegisterCollisionGroup(name)
end
PhysicsService:CollisionGroupSetCollidable("Karts", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Karts", "Drivers", false)
-- karts bump each other through their bumpers (KartPhysics), computed by each
-- driver's client; Roblox's own kart-on-kart collisions launch karts online
PhysicsService:CollisionGroupSetCollidable("Karts", "Karts", false)
for _, other in { "Default", "Players", "Drivers" } do
	PhysicsService:CollisionGroupSetCollidable("Drivers", other, false)
end

-- Purpose-built circuits made of parts (no terrain; hills are part-built
-- embankments). The live one is
-- built straight into workspace (pits first, so the spawn exists early);
-- the others into a folder that is parented when it is voted in.
local function buildCircuit(spec: any, live: boolean): RaceManager.Circuit
	local started = os.clock()
	local track = TrackMath.build(spec)
	local grid = TrackLayout.grid(track)
	local zones = TrackLayout.zones(track, grid)
	local world = Instance.new("Folder")
	world.Name = if live then "Circuit" else spec.Id
	world:SetAttribute("TrackId", spec.Id)
	if live then
		world.Parent = workspace
	end
	Scenery.begin(spec)
	Scenery.pits(track, spec, world)
	local trackFolder = TrackBuilder.build(track, zones, world)
	TrackBuilder.ground(track, trackFolder)
	TrackBuilder.embankments(track, TrackLayout.ground(track, grid, zones), trackFolder)
	TrackBuilder.crossings(track, TrackLayout.ground(track, grid, zones), trackFolder)
	Scenery.gantry(track, spec, trackFolder)
	Scenery.stands(track, grid, zones, spec, world)
	Scenery.bridge(track, spec, world)
	Scenery.barriers(track, grid, zones, world)
	Scenery.marshals(track, grid, zones, spec, world)
	Scenery.cornerBoards(track, grid, zones, spec, world)
	local pools = Scenery.water(track, grid, zones, spec, trackFolder)
	Scenery.trees(track, grid, zones, spec, pools, world)
	Scenery.trackLights(track, grid, zones, spec, world)
	Scenery.perimeter(track, world, spec)
	print(string.format("[A1KartRacing] %s built: %d samples, %.0f studs, %.1f s", spec.Name, track.n, track.length, os.clock() - started))
	return { id = spec.Id, spec = spec, track = track, zones = zones, folder = world }
end

-- a reserved server waits here until it knows what it is for
local role = Session.resolve()
workspace:SetAttribute("ServerMode", role.mode)
local studio = Session.studio()
local firstId = role.track or TrackData.Default
if role.mode == "lobby" and not studio then
	-- a different circuit behind the menu now and then
	firstId = TrackData.Order[math.random(1, #TrackData.Order)]
end

workspace.Terrain:Clear()
local first = buildCircuit(TrackData.get(firstId), true)
Scenery.lighting(first.spec)
-- each circuit brings its own weather
RaceManager.onTrackChanged = function(c)
	Scenery.lighting(c.spec)
end
workspace:SetAttribute("TrackReady", true)

Stats.init(function(name, t)
	raceEvent:FireAllClients("Record", { name = name, time = t })
end, first.id)
Stats.loadRecords(TrackData.Order)

Session.notify = function(p: Player, kind: string, data: { [string]: any })
	raceEvent:FireClient(p, kind, data)
end
Session.beforeLeave = Stats.saveNow
Session.switchHere = function(r: Session.Role)
	-- Studio: the menu sends everyone; this server becomes that
	if r.mode ~= "lobby" then
		Lobby.closed()
	end
	RaceManager.setMode(r)
end
Session.init()
RaceManager.onKick = function(p: Player, message: string)
	local code = workspace:GetAttribute("RoomCode") :: string?
	if code and not studio then
		task.spawn(Rooms.ban, code, p.UserId)
	end
	Session.kick(p, message)
end
RaceManager.start(first, remotes, role)
Lobby.init(remotes, RaceManager.mode)
if role.mode == "room" and role.code and not studio then
	Rooms.keep(role.code)
end

-- every player's ping, so other clients know how late their kart arrives
task.spawn(function()
	local Players = game:GetService("Players")
	while true do
		for _, p in Players:GetPlayers() do
			p:SetAttribute("Ping", math.floor(p:GetNetworkPing() * 1000 + 0.5) / 1000)
		end
		task.wait(2)
	end
end)

-- the other circuits, after the first player can already drive
if role.mode == "lobby" and not studio then
	return
end
task.defer(function()
	for _, id in TrackData.Order do
		if id ~= first.id then
			RaceManager.addCircuit(buildCircuit(TrackData.get(id), false))
			task.wait()
		end
	end
end)
