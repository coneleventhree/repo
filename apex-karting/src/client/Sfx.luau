--!strict
-- Sound effects: one-shots for race events and buttons, the crowd at the
-- grandstands, and the sound groups whose volumes follow the settings
-- (master x engine for engines, master x effects for everything else).
-- Ids come from Config.Audio; an empty id is silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local Sfx = {}

local AUDIO = Config.Audio :: { [string]: any }
local groups: { [string]: SoundGroup } = {}
local oneShots: { [string]: Sound } = {}
local crowd: { Sound } = {}

function Sfx.group(name: string): SoundGroup
	local g = groups[name]
	if not g then
		local made = Instance.new("SoundGroup")
		made.Name = "Kart" .. name
		made.Parent = SoundService
		groups[name] = made
		g = made
	end
	return g :: SoundGroup
end

local function applyVolumes()
	local master = Settings.get("MasterVolume") :: number
	Sfx.group("Engine").Volume = master * (Settings.get("EngineVolume") :: number)
	Sfx.group("Effects").Volume = master * (Settings.get("EffectsVolume") :: number)
end

-- Plays a one-shot ("Beep", "Go", "Lap", "Best", "Warning", "Penalty",
-- "Flag", "Finish", "Podium", "Bump", "Click"). False when that sound has no
-- id (so the caller can fall back to another one).
function Sfx.play(name: string, scale: number?): boolean
	local id = AUDIO[name .. "SoundId"]
	if type(id) ~= "string" or id == "" then
		return false
	end
	local s = oneShots[name]
	if not s then
		local made = Instance.new("Sound")
		made.Name = "Sfx" .. name
		made.SoundId = id
		made.SoundGroup = Sfx.group("Effects")
		made.Parent = SoundService
		oneShots[name] = made
		s = made
	end
	local snd = s :: Sound
	snd.Volume = (AUDIO[name .. "Volume"] or 0.5) * (scale or 1)
	snd.TimePosition = 0
	snd:Play()
	return true
end

-- Crowd noise from every grandstand of the circuit in use.
local function refreshCrowd()
	for _, s in crowd do
		s:Destroy()
	end
	table.clear(crowd)
	local id = AUDIO.CrowdSoundId
	if type(id) ~= "string" or id == "" then
		return
	end
	local circuit = workspace:FindFirstChild("Circuit")
	local stands = circuit and circuit:FindFirstChild("Grandstands")
	if not stands then
		return
	end
	for _, stand in stands:GetChildren() do
		local roof = stand:FindFirstChild("Roof")
		if roof and roof:IsA("BasePart") then
			local s = Instance.new("Sound")
			s.Name = "Crowd"
			s.SoundId = id
			s.Looped = true
			s.Volume = AUDIO.CrowdVolume or 0.5
			s.RollOffMinDistance = AUDIO.CrowdRollOffMin or 20
			s.RollOffMaxDistance = 260
			s.SoundGroup = Sfx.group("Effects")
			s.Parent = roof
			s:Play()
			table.insert(crowd, s)
		end
	end
end

function Sfx.init()
	applyVolumes()
	Settings.onChange(function(key)
		if key == "MasterVolume" or key == "EngineVolume" or key == "EffectsVolume" then
			applyVolumes()
		end
	end)
	refreshCrowd()
	workspace:GetAttributeChangedSignal("Track"):Connect(function()
		task.delay(1, refreshCrowd)
	end)
end

return Sfx
