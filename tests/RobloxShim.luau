-- 통합 테스트용 가짜 Roblox 런타임.
-- 실제 클라이언트/서버 스크립트를 수정 없이 Lune에서 실행하기 위해 Instance, 이벤트,
-- 데이터 타입, 서비스, RemoteEvent 네트워크(지연·패킷 손실 포함)를 최소한으로 흉내 낸다.
-- 프로퍼티 이름/타입 검사는 luau-lsp 타입 검사가 담당하고, 여기서는 실행 흐름을 검증한다.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Shim = {}

-------------------------------------------------------------------------------
-- 이벤트

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	function connection.Disconnect()
		connection.Connected = false
	end
	table.insert(self.handlers, { fn = fn, connection = connection })
	return connection
end

function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		if handler.connection.Connected then
			handler.fn(...)
		end
	end
end

-------------------------------------------------------------------------------
-- 데이터 타입 (NaN이 GUI로 흘러가면 바로 실패시킨다)

local function finite(value: any, what: string): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error(what .. " received a non-finite number: " .. tostring(value), 3)
	end
	return value
end

local UDim = {}
function UDim.new(scale, offset)
	return { Scale = finite(scale or 0, "UDim"), Offset = finite(offset or 0, "UDim") }
end

local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end

local Vector2 = {}
function Vector2.new(x, y)
	return { X = finite(x or 0, "Vector2"), Y = finite(y or 0, "Vector2") }
end

local Vector3 = {}
function Vector3.new(x, y, z)
	return { X = x or 0, Y = y or 0, Z = z or 0 }
end

local Color3 = {}
local Color3Methods = {}
local function color(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, { __index = Color3Methods })
end
function Color3Methods.Lerp(self, other, t)
	return color(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t)
end
function Color3.new(r, g, b)
	return color(r or 0, g or 0, b or 0)
end
function Color3.fromRGB(r, g, b)
	return color((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

local function opaque(name)
	return {
		new = function(...)
			return { __type = name, args = { ... } }
		end,
	}
end

local Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, item)
				return "Enum." .. enumName .. "." .. item
			end,
		})
	end,
})
Shim.Enum = Enum

-------------------------------------------------------------------------------
-- Instance

local EVENTS = {
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	TouchEnded = true,
	Activated = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Heartbeat = true,
	RenderStepped = true,
	PlayerRemoving = true,
	PlayerAdded = true,
}

local BASES = {
	Frame = { "GuiObject", "GuiBase2d" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiObject", "GuiBase2d", "GuiButton" },
	ImageLabel = { "GuiObject", "GuiBase2d" },
	ScreenGui = { "LayerCollector", "GuiBase2d" },
	ModuleScript = { "LuaSourceContainer" },
	LocalScript = { "LuaSourceContainer", "BaseScript" },
	Script = { "LuaSourceContainer", "BaseScript" },
}

local internals = setmetatable({}, { __mode = "k" })
local Methods = {}

local function newInstance(className: string)
	local data = { props = { ClassName = className, Name = className }, children = {}, parent = nil }
	local instance = {}
	internals[instance] = data
	return setmetatable(instance, {
		__index = function(_, key)
			if key == "Parent" then
				return data.parent
			end
			local value = data.props[key]
			if value ~= nil then
				return value
			end
			if EVENTS[key] then
				local signal = Signal.new()
				data.props[key] = signal
				return signal
			end
			local method = Methods[key]
			if method then
				return method
			end
			for _, child in data.children do
				if child.Name == key then
					return child
				end
			end
			return nil
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = data.parent
				if old then
					local siblings = internals[old].children
					local index = table.find(siblings, instance)
					if index then
						table.remove(siblings, index)
					end
				end
				data.parent = value
				if value then
					table.insert(internals[value].children, instance)
				end
			else
				data.props[key] = value
			end
		end,
		__tostring = function()
			return data.props.Name
		end,
	})
end
Shim.newInstance = newInstance

function Shim.isInstance(value)
	return internals[value] ~= nil
end

function Shim.setInternal(instance, key, value)
	internals[instance].props[key] = value
end

function Methods.IsA(self, className)
	local own = self.ClassName
	if own == className or className == "Instance" then
		return true
	end
	return table.find(BASES[own] or {}, className) ~= nil
end

function Methods.Destroy(self)
	self.Parent = nil
	internals[self].props.__destroyed = true
end

function Methods.GetChildren(self)
	return table.clone(internals[self].children)
end

function Methods.GetDescendants(self)
	local result = {}
	local function walk(instance)
		for _, child in internals[instance].children do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(self)
	return result
end

function Methods.FindFirstChild(self, name)
	for _, child in internals[self].children do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function Methods.WaitForChild(self, name, timeout)
	local child = Methods.FindFirstChild(self, name)
	if child == nil and timeout == nil then
		error("WaitForChild would wait forever for " .. tostring(self) .. "." .. name, 2)
	end
	return child
end

function Methods.GetService(self, className)
	for _, child in internals[self].children do
		if child.ClassName == className then
			return child
		end
	end
	local service = newInstance(className)
	service.Parent = self
	return service
end

function Methods.GetPlayers(self)
	local result = {}
	for _, child in internals[self].children do
		if child.ClassName == "Player" then
			table.insert(result, child)
		end
	end
	return result
end

function Methods.GetNetworkPing(_self)
	return 0.08
end

function Methods.GetUserThumbnailAsync(_self, userId)
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId)
end

function Methods.SetCoreGuiEnabled() end

function Methods.FireServer(self, ...)
	internals[self].props.__fireServer(...)
end

function Methods.FireClient(self, player, ...)
	internals[self].props.__fireClient(player, ...)
end

-------------------------------------------------------------------------------
-- 스크립트 실행 환경

local function deepCopy(value)
	if type(value) ~= "table" or internals[value] then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy
end
Shim.deepCopy = deepCopy

export type World = {
	game: any,
	clock: () -> number,
	modules: { [any]: any },
	warnings: { string },
	require: (any) -> any,
}

local function makeEnv(world, scriptInstance)
	return {
		game = world.game,
		script = scriptInstance,
		require = world.require,
		Instance = { new = newInstance },
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Vector3 = Vector3,
		Color3 = Color3,
		ColorSequence = opaque("ColorSequence"),
		NumberSequence = opaque("NumberSequence"),
		NumberSequenceKeypoint = opaque("NumberSequenceKeypoint"),
		Enum = Enum,
		os = { clock = world.clock, time = os.time },
		task = {
			spawn = function(fn, ...)
				local thread = coroutine.create(fn)
				local ok, err = coroutine.resume(thread, ...)
				if not ok then
					error(err, 0)
				end
				return thread
			end,
		},
		warn = function(...)
			table.insert(world.warnings, table.concat({ ... }, " "))
		end,
		typeof = function(value)
			if internals[value] then
				return "Instance"
			end
			return typeof(value)
		end,
	}
end

local function runScript(world, instance)
	local path = internals[instance].props.__source
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = makeEnv(world, instance) })
	return chunk()
end

local function moduleScript(name: string, path: string, parent)
	local m = newInstance(
		if path:find("%.client%.") then "LocalScript" elseif path:find("%.server%.") then "Script" else "ModuleScript"
	)
	m.Name = name
	internals[m].props.__source = path
	m.Parent = parent
	return m
end

local function folderFrom(name: string, dir: string, parent)
	local folder = newInstance("Folder")
	folder.Name = name
	for _, file in fs.readDir(dir) do
		local base = file:match("^(.-)%.") :: string
		moduleScript(base, dir .. "/" .. file, folder)
	end
	folder.Parent = parent
	return folder
end

function Shim.newWorld(clock: () -> number): World
	local game = newInstance("DataModel")
	game.Name = "Game"
	local world = { game = game, clock = clock, modules = {}, warnings = {} }
	function world.require(target)
		assert(internals[target] and internals[target].props.__source, "require of a non-module: " .. tostring(target))
		local cached = world.modules[target]
		if cached ~= nil then
			return cached
		end
		local result = runScript(world, target)
		world.modules[target] = result
		return result
	end
	folderFrom("Shared", "src/shared", game:GetService("ReplicatedStorage"))
	return world
end

-- 서버 스크립트를 실행한다
function Shim.startServer(world: World)
	local folder = folderFrom("Server", "src/server", world.game:GetService("ServerScriptService"))
	for _, child in folder:GetChildren() do
		if child.ClassName == "Script" then
			runScript(world, child)
		end
	end
end

-- 로컬 플레이어를 만들고 클라이언트 스크립트를 실행한다
function Shim.startClient(world: World, userId: number, displayName: string)
	local players = world.game:GetService("Players")
	local player = newInstance("Player")
	player.Name = displayName
	player.DisplayName = displayName
	player.UserId = userId
	player.Parent = players
	internals[players].props.LocalPlayer = player
	local playerGui = newInstance("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	local playerScripts = newInstance("PlayerScripts")
	playerScripts.Name = "PlayerScripts"
	playerScripts.Parent = player
	local folder = folderFrom("Client", "src/client", playerScripts)
	for _, child in folder:GetChildren() do
		if child.ClassName == "LocalScript" then
			runScript(world, child)
		end
	end
	return player
end

Shim.Signal = Signal

return Shim
