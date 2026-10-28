--!strict
-- Client entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
-- wait until the server has built the circuit (rays and the minimap need it)
if not workspace:GetAttribute("TrackReady") then
	workspace:GetAttributeChangedSignal("TrackReady"):Wait()
end

local Settings = require(script:WaitForChild("Settings"))
local Sfx = require(script:WaitForChild("Sfx"))
local SettingsMenu = require(script:WaitForChild("SettingsMenu"))
local Input = require(script:WaitForChild("Input"))
local KartController = require(script:WaitForChild("KartController"))
local KartVisuals = require(script:WaitForChild("KartVisuals"))
local ChaseCamera = require(script:WaitForChild("ChaseCamera"))
local Hud = require(script:WaitForChild("Hud"))
local Menu = require(script:WaitForChild("Menu"))

Settings.init(remotes)
Sfx.init()
Input.init()
KartController.init(remotes)
KartVisuals.init()
ChaseCamera.init()
Hud.init(remotes)
SettingsMenu.init()
Menu.init(remotes)
