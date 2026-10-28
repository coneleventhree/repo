--!strict
-- Our loading screen in place of Roblox's: up from the first frame until the
-- game has loaded and this server has built its circuit (a reserved server
-- first finds out what it is for, then builds). After a teleport it carries
-- on with the screen the last server handed over, so there is no gap.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

local LoadingGui = require(script:WaitForChild("LoadingGui"))

local MIN_TIME = 2 -- seconds on screen at least (no flash)
local MAX_TIME = 60 -- never stuck behind it
local TIP_TIME = 4.5

local player = Players.LocalPlayer
local okArrive, arriving = pcall(function()
	return TeleportService:GetArrivingTeleportGui()
end)
local gui: ScreenGui
if okArrive and arriving and arriving:IsA("ScreenGui") and arriving:FindFirstChild("Back") then
	gui = arriving
else
	gui = LoadingGui.create()
end
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- where we are going (the lobby put it in the teleport data)
local okData, data = pcall(function()
	return TeleportService:GetLocalPlayerTeleportData()
end)
local status = LoadingGui.describe(if okData then data else nil)
LoadingGui.set(gui, 0.05, status)

local started = os.clock()
task.spawn(function()
	local i = math.random(1, #LoadingGui.Tips)
	while gui.Parent do
		task.wait(TIP_TIME)
		i += 1
		LoadingGui.tip(gui, i)
	end
end)

-- The bar: loading the game takes it to 60%, the circuit to 100%. Inside a
-- step it creeps towards the step's end so it never looks stuck.
local shown = 0.05
while true do
	local loaded = game:IsLoaded()
	local ready = workspace:GetAttribute("TrackReady") == true
	local queue = ContentProvider.RequestQueueSize
	local cap: number
	if loaded and ready then
		cap = 1
	elseif loaded then
		cap = 0.95
	else
		cap = 0.55 - 0.3 * math.clamp(queue / 60, 0, 1)
	end
	shown += (cap - shown) * 0.04
	local line = status
	if loaded and not ready then
		line = status .. "  -  building the circuit"
	end
	LoadingGui.set(gui, shown, line)
	LoadingGui.fit(gui)
	local t = os.clock() - started
	if (loaded and ready and t >= MIN_TIME) or t > MAX_TIME then
		break
	end
	task.wait(1 / 30)
end
LoadingGui.set(gui, 1, status)
task.wait(0.3)
gui:Destroy()
