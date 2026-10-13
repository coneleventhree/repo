-- Lune에서 src/shared 모듈을 Roblox와 같은 방식(require(script.Parent.X))으로 불러오는 작은 로더.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

local cache: { [string]: any } = {}
local load: (string) -> any

local sharedFolder = setmetatable({}, {
	__index = function(_, name: string)
		return { __sharedModule = name }
	end,
})

local function fakeRequire(target: any): any
	if type(target) == "table" and target.__sharedModule then
		return load(target.__sharedModule)
	end
	error("tests/Loader: unsupported require target " .. tostring(target))
end

function load(name: string): any
	local cached = cache[name]
	if cached ~= nil then
		return cached
	end
	local path = "src/shared/" .. name .. ".luau"
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			script = { Name = name, Parent = sharedFolder },
			require = fakeRequire,
		},
	})
	local result = chunk()
	cache[name] = result
	return result
end

Loader.shared = load

return Loader
