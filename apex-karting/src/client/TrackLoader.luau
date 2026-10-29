--!strict
-- Track changes. The server swaps whole circuits (thousands of parts to
-- replicate) and holds everyone, anchored, in the new paddock: a character
-- let go before its client had the ground fell through it. This puts the
-- loading screen up until the new circuit has reached this client (a ray
-- finds the floor under the character and the road on the grid), then tells
-- the server (Request "TrackLoaded"), which lets the character and kart go.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TrackLoader = {}

local MIN_TIME = 0.8 -- seconds the screen stays up at least (no flash)
local player = Players.LocalPlayer
local requestRemote: RemoteEvent
local token = 0

local LoadingGui: any = nil
local function loadingModule(): any
	if not LoadingGui then
		local ok, m = pcall(function()
			local folder = ReplicatedFirst:WaitForChild("Loading", 5)
			local mod: any = (folder :: Instance):WaitForChild("LoadingGui", 5)
			return (require :: any)(mod)
		end)
		if ok then
			LoadingGui = m
		end
	end
	return LoadingGui
end

-- Has circuit `id` arrived: the floor under the character and the road just
-- behind the start line (every circuit starts at the origin heading +X)?
local function arrived(id: string): boolean
	local circuit = workspace:FindFirstChild("Circuit")
	if not circuit or circuit:GetAttribute("TrackId") ~= id then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { circuit }
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and not workspace:Raycast(root.Position + Vector3.new(0, 2, 0), Vector3.new(0, -80, 0), params) then
		return false
	end
	return workspace:Raycast(Vector3.new(-40, 120, 0), Vector3.new(0, -240, 0), params) ~= nil
end

local function begin(id: string, name: string)
	token += 1
	local my = token
	local LG = loadingModule()
	local gui: ScreenGui? = nil
	if LG then
		local g = LG.create("Loading  -  " .. name) :: ScreenGui
		LG.fit(g)
		LG.set(g, 0.1)
		g.Parent = player:WaitForChild("PlayerGui")
		gui = g
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - t0
		local done = my ~= token
		if not done then
			local ok = arrived(id)
			if gui and LG then
				LG.set(gui, if ok then 1 else math.min(0.9, 0.1 + elapsed / 8))
			end
			if (ok and elapsed >= MIN_TIME) or elapsed > Config.Race.TrackLoadTimeout then
				requestRemote:FireServer("TrackLoaded", id)
				done = true
			end
		end
		if done then
			conn:Disconnect()
			if gui then
				gui:Destroy()
			end
		end
	end)
end

function TrackLoader.init(remotes: Folder)
	requestRemote = remotes:WaitForChild("Request") :: RemoteEvent
	local raceEvent = remotes:WaitForChild("RaceEvent") :: RemoteEvent
	raceEvent.OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "Track" and type(data) == "table" and type(data.id) == "string" then
			begin(data.id, tostring(data.name or data.id))
		end
	end)
end

return TrackLoader
