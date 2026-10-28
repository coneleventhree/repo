--!strict
-- The local player's settings (see Config.Settings). Values come from the
-- server as player attributes S_<key> (loaded from their saved data); a
-- change made here applies at once and is sent to the server to be saved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Settings = {}

local player = Players.LocalPlayer
local pending: { [string]: any } = {}
local listeners: { (string, any) -> () } = {}
local requestRemote: RemoteEvent? = nil

function Settings.get(key: string): any
	local v = pending[key]
	if v ~= nil then
		return v
	end
	v = player:GetAttribute("S_" .. key)
	if v ~= nil then
		return v
	end
	local item = Config.Settings.Items[key]
	return item and item.default
end

local function notify(key: string, value: any)
	for _, fn in listeners do
		task.spawn(fn, key, value)
	end
end

function Settings.set(key: string, value: any)
	pending[key] = value
	notify(key, value)
	local remote = requestRemote
	if remote then
		remote:FireServer("Setting", { key = key, value = value })
	end
end

-- UI scale for a screen of this size. At 1 (ordinary screens) and 2 (very
-- large ones) every element sits on whole pixels, which keeps text sharp; a
-- scale like 1.07 put everything between pixels and blurred the text. Only
-- small screens (phones, tiny windows) shrink, where fitting matters more.
function Settings.pixelScale(vp: Vector2): number
	local fit = math.min(vp.X / 1280, vp.Y / 720)
	if fit >= 2 then
		return 2
	elseif fit >= 0.85 then
		return 1
	end
	return math.max(fit, 0.55)
end

-- fn(key, value) after any change (local, or loaded from the server)
function Settings.onChange(fn: (string, any) -> ())
	table.insert(listeners, fn)
end

function Settings.init(remotes: Folder)
	requestRemote = remotes:WaitForChild("Request") :: RemoteEvent
	for key in Config.Settings.Items do
		local k = key :: string
		player:GetAttributeChangedSignal("S_" .. k):Connect(function()
			local v = player:GetAttribute("S_" .. k)
			local mine = pending[k]
			if mine ~= nil then
				-- the server's echo of our latest change: from now on the
				-- attribute is the value. An echo of an earlier click (several
				-- clicks in a row) is not, so the pending value stays.
				local same = mine == v or (type(mine) == "number" and type(v) == "number" and math.abs(mine - v) < 1e-6)
				if not same then
					return
				end
				pending[k] = nil
			end
			notify(k, v)
		end)
	end
end

return Settings
