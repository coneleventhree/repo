-- Mock Roblox datatypes for the headless runtime: Vector3 (table based, with
-- both X and x fields), CFrame, Color3, Vector2, UDim, UDim2,
-- PhysicalProperties, Region3, RaycastParams, TweenInfo, plus a `vector`
-- library shim that works on the same Vector3 values.

local D = {}

local function typed(name: string)
	local mt = { __type = name }
	mt.__index = mt
	return mt
end
D.typed = typed

----------------------------------------------------------------------------
-- Vector3
----------------------------------------------------------------------------
local V3 = typed("Vector3")
local function v3(x: number, y: number, z: number)
	return setmetatable({ X = x, Y = y, Z = z, x = x, y = y, z = z }, V3)
end
local function isV3(v: any): boolean
	return type(v) == "table" and getmetatable(v) == V3
end
D.isV3 = isV3

V3.__add = function(a, b)
	assert(isV3(a) and isV3(b), "Vector3 + expects two Vector3")
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	assert(isV3(a) and isV3(b), "Vector3 - expects two Vector3")
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	assert(isV3(a) and isV3(b), "bad Vector3 multiply")
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__idiv = function(a, b)
	return v3(a.X // b, a.Y // b, a.Z // b)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
local V3methods = {}
function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3methods.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3methods.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3methods.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3methods.FuzzyEq(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-5)
end
V3.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	local f = V3methods[k]
	if f then
		return f
	end
	error(tostring(k) .. " is not a valid member of Vector3", 2)
end
V3.__newindex = function()
	error("Vector3 is immutable", 2)
end

D.Vector3 = {
	new = function(x: number?, y: number?, z: number?)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

-- `vector` library shim over the same values
D.vector = {
	create = function(x, y, z)
		return v3(x, y, z)
	end,
	dot = function(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end,
	cross = function(a, b)
		return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end,
	magnitude = function(a)
		return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
	end,
	normalize = function(a)
		local m = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
		return v3(a.X / m, a.Y / m, a.Z / m)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
}

----------------------------------------------------------------------------
-- CFrame (position + rotation matrix with columns right, up, back)
----------------------------------------------------------------------------
local CF = typed("CFrame")
local function cf(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	-- r(row)(col); columns are RightVector, UpVector, -LookVector
	return setmetatable({ px = px, py = py, pz = pz, m = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } }, CF)
end
local function isCF(v)
	return type(v) == "table" and getmetatable(v) == CF
end
D.isCF = isCF

local function fromAxes(p, rx, ry, rz)
	return cf(p.X, p.Y, p.Z, rx.X, ry.X, rz.X, rx.Y, ry.Y, rz.Y, rx.Z, ry.Z, rz.Z)
end

local function mulVec(c, x, y, z)
	local m = c.m
	return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end

CF.__mul = function(a, b)
	if isCF(b) then
		local m, n = a.m, b.m
		local px, py, pz = mulVec(a, b.px, b.py, b.pz)
		local r = {}
		for i = 0, 2 do
			for j = 0, 2 do
				r[i * 3 + j + 1] = m[i * 3 + 1] * n[j + 1] + m[i * 3 + 2] * n[3 + j + 1] + m[i * 3 + 3] * n[6 + j + 1]
			end
		end
		return cf(px + a.px, py + a.py, pz + a.pz, table.unpack(r))
	elseif isV3(b) then
		local x, y, z = mulVec(a, b.X, b.Y, b.Z)
		return v3(x + a.px, y + a.py, z + a.pz)
	end
	error("bad CFrame multiply", 2)
end
CF.__add = function(a, b)
	assert(isV3(b), "CFrame + expects Vector3")
	local m = a.m
	return cf(a.px + b.X, a.py + b.Y, a.pz + b.Z, table.unpack(m))
end
CF.__sub = function(a, b)
	assert(isV3(b), "CFrame - expects Vector3")
	local m = a.m
	return cf(a.px - b.X, a.py - b.Y, a.pz - b.Z, table.unpack(m))
end
CF.__tostring = function(a)
	return string.format("CFrame(%g, %g, %g)", a.px, a.py, a.pz)
end
CF.__eq = function(a, b)
	if a.px ~= b.px or a.py ~= b.py or a.pz ~= b.pz then
		return false
	end
	for i = 1, 9 do
		if a.m[i] ~= b.m[i] then
			return false
		end
	end
	return true
end

local CFmethods = {}
function CFmethods.Inverse(a)
	local m = a.m
	-- transpose rotation
	local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
	local inv = cf(0, 0, 0, table.unpack(t))
	local x, y, z = mulVec(inv, -a.px, -a.py, -a.pz)
	return cf(x, y, z, table.unpack(t))
end
function CFmethods.PointToWorldSpace(a, v)
	return a * v
end
function CFmethods.VectorToWorldSpace(a, v)
	local x, y, z = mulVec(a, v.X, v.Y, v.Z)
	return v3(x, y, z)
end
function CFmethods.PointToObjectSpace(a, v)
	return CFmethods.Inverse(a) * v
end
function CFmethods.VectorToObjectSpace(a, v)
	local m = a.m
	return v3(m[1] * v.X + m[4] * v.Y + m[7] * v.Z, m[2] * v.X + m[5] * v.Y + m[8] * v.Z, m[3] * v.X + m[6] * v.Y + m[9] * v.Z)
end
function CFmethods.ToWorldSpace(a, b)
	return a * b
end
function CFmethods.ToObjectSpace(a, b)
	return CFmethods.Inverse(a) * b
end
function CFmethods.GetComponents(a)
	return a.px, a.py, a.pz, table.unpack(a.m)
end
function CFmethods.Lerp(a, b, t)
	-- good enough for tests: lerp position, keep b's rotation when t >= 0.5
	local p = v3(a.px, a.py, a.pz):Lerp(v3(b.px, b.py, b.pz), t)
	local base = if t < 0.5 then a else b
	return cf(p.X, p.Y, p.Z, table.unpack(base.m))
end
CF.__index = function(self, k)
	local m = self.m
	if k == "Position" or k == "p" then
		return v3(self.px, self.py, self.pz)
	elseif k == "X" then
		return self.px
	elseif k == "Y" then
		return self.py
	elseif k == "Z" then
		return self.pz
	elseif k == "RightVector" or k == "XVector" then
		return v3(m[1], m[4], m[7])
	elseif k == "UpVector" or k == "YVector" then
		return v3(m[2], m[5], m[8])
	elseif k == "LookVector" then
		return v3(-m[3], -m[6], -m[9])
	elseif k == "ZVector" then
		return v3(m[3], m[6], m[9])
	elseif k == "Rotation" then
		return cf(0, 0, 0, table.unpack(m))
	end
	local f = CFmethods[k]
	if f then
		return f
	end
	error(tostring(k) .. " is not a valid member of CFrame", 2)
end
CF.__newindex = function()
	error("CFrame is immutable", 2)
end

local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

local function lookAt(pos, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - pos).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return fromAxes(pos, right, up2, -look)
end

D.CFrame = {
	new = function(a, b, c, ...)
		if a == nil then
			return cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif isV3(a) and isV3(b) then
			return lookAt(a, b)
		elseif isV3(a) then
			return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif select("#", ...) == 9 then
			return cf(a, b, c, ...)
		end
		assert(type(a) == "number" and type(b) == "number" and type(c) == "number", "bad CFrame.new arguments")
		return cf(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end,
	lookAt = lookAt,
	fromMatrix = function(pos, vx, vy, vz)
		assert(isV3(pos) and isV3(vx) and isV3(vy), "bad fromMatrix arguments")
		if vz then
			-- Roblox CFrames are proper rotations: a mirrored (left-handed)
			-- basis does not give the orientation the caller expects
			assert(vx:Cross(vy):Dot(vz) > 0, "CFrame.fromMatrix: left-handed basis")
		end
		vz = vz or vx:Cross(vy).Unit
		return fromAxes(pos, vx, vy, vz)
	end,
	Angles = function(rx, ry, rz)
		return rotX(rx) * rotY(ry) * rotZ(rz)
	end,
	fromEulerAnglesXYZ = function(rx, ry, rz)
		return rotX(rx) * rotY(ry) * rotZ(rz)
	end,
	fromAxisAngle = function(axis, angle)
		local u = axis.Unit
		local c, s = math.cos(angle), math.sin(angle)
		local t = 1 - c
		local x, y, z = u.X, u.Y, u.Z
		return cf(0, 0, 0, t * x * x + c, t * x * y - s * z, t * x * z + s * y, t * x * y + s * z, t * y * y + c, t * y * z - s * x, t * x * z - s * y, t * y * z + s * x, t * z * z + c)
	end,
	identity = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
}

----------------------------------------------------------------------------
-- small value types
----------------------------------------------------------------------------
local C3 = typed("Color3")
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b, Lerp = function(a, o, t)
		return setmetatable({ R = a.R + (o.R - a.R) * t, G = a.G + (o.G - a.G) * t, B = a.B + (o.B - a.B) * t }, C3)
	end }, C3)
end
D.Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "bad fromRGB")
		return c3(r / 255, g / 255, b / 255)
	end,
}

local V2 = typed("Vector2")
local function v2(x, y)
	return setmetatable({ X = x, Y = y, x = x, y = y }, V2)
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	return v2(a.X / b, a.Y / b)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	elseif k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y)
		return v2(self.X / m, self.Y / m)
	end
	error(tostring(k) .. " is not a valid member of Vector2", 2)
end
D.Vector2 = {
	new = function(x, y)
		return v2(x or 0, y or 0)
	end,
	zero = v2(0, 0),
	one = v2(1, 1),
}

local UD = typed("UDim")
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD)
end
D.UDim = { new = udim }
local UD2 = typed("UDim2")
local function udim2(xs, xo, ys, yo)
	local x, y = udim(xs, xo), udim(ys, yo)
	return setmetatable({ X = x, Y = y, Width = x, Height = y }, UD2)
end
UD2.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
D.UDim2 = {
	new = function(xs, xo, ys, yo)
		for _, v in { xs or 0, xo or 0, ys or 0, yo or 0 } do
			assert(type(v) == "number", "UDim2.new expects numbers")
		end
		return udim2(xs or 0, xo or 0, ys or 0, yo or 0)
	end,
	fromScale = function(x, y)
		assert(type(x) == "number" and type(y) == "number", "UDim2.fromScale expects numbers")
		return udim2(x, 0, y, 0)
	end,
	fromOffset = function(x, y)
		assert(type(x) == "number" and type(y) == "number", "UDim2.fromOffset expects numbers")
		return udim2(0, x, 0, y)
	end,
}

local PP = typed("PhysicalProperties")
D.PhysicalProperties = {
	new = function(density, friction, elasticity, fw, ew)
		assert(type(density) == "number", "PhysicalProperties.new needs numbers")
		assert(density >= 0.0001 and density <= 100, "density out of range")
		assert(friction == nil or (friction >= 0 and friction <= 2), "friction out of range")
		assert(elasticity == nil or (elasticity >= 0 and elasticity <= 1), "elasticity out of range")
		return setmetatable({ Density = density, Friction = friction or 0.3, Elasticity = elasticity or 0.5, FrictionWeight = fw or 1, ElasticityWeight = ew or 1 }, PP)
	end,
}

local R3 = typed("Region3")
D.Region3 = {
	new = function(min, max)
		assert(isV3(min) and isV3(max), "Region3.new expects Vector3s")
		local size = max - min
		return setmetatable({ Min = min, Max = max, Size = size, CFrame = D.CFrame.new((min + max) / 2) }, R3)
	end,
}

local RP = typed("RaycastParams")
D.RaycastParams = {
	new = function()
		return setmetatable({ FilterType = nil, FilterDescendantsInstances = {}, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false }, RP)
	end,
}

local TI = typed("TweenInfo")
D.TweenInfo = {
	new = function(t, ...)
		return setmetatable({ Time = t or 1 }, TI)
	end,
}

-- Font (FontFace): family asset, weight and style
local FT = typed("Font")
D.Font = {
	new = function(family, weight, style)
		assert(type(family) == "string" and family:sub(1, 11) == "rbxasset://", "Font.new expects an rbxasset:// family")
		return setmetatable({ Family = family, Weight = weight, Style = style, Bold = false }, FT)
	end,
	fromEnum = function(e)
		return setmetatable({ Family = "rbxasset://fonts/families/" .. tostring(e) .. ".json" }, FT)
	end,
	fromName = function(name, weight, style)
		return setmetatable({ Family = "rbxasset://fonts/families/" .. name .. ".json", Weight = weight, Style = style }, FT)
	end,
}

-- particle emitter value types (only stored, never evaluated)
local NS = typed("NumberSequence")
local CS = typed("ColorSequence")
local NR = typed("NumberRange")
D.NumberSequence = {
	new = function(a, b)
		assert(type(a) == "number" or type(a) == "table", "NumberSequence.new expects numbers or keypoints")
		return setmetatable({ Keypoints = if type(a) == "table" then a else { a, b or a } }, NS)
	end,
}
D.NumberSequenceKeypoint = {
	new = function(t, v, e)
		assert(type(t) == "number" and type(v) == "number", "NumberSequenceKeypoint.new expects numbers")
		return { Time = t, Value = v, Envelope = e or 0 }
	end,
}
D.ColorSequence = {
	new = function(a, b)
		return setmetatable({ Keypoints = if D.typeof(a) == "Color3" then { a, b or a } else a }, CS)
	end,
}
D.ColorSequenceKeypoint = {
	new = function(t, c)
		assert(type(t) == "number" and D.typeof(c) == "Color3", "ColorSequenceKeypoint.new expects a number and a Color3")
		return { Time = t, Value = c }
	end,
}
D.NumberRange = {
	new = function(a, b)
		assert(type(a) == "number", "NumberRange.new expects numbers")
		return setmetatable({ Min = a, Max = b or a }, NR)
	end,
}

function D.typeof(v: any): string
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
		if type(mt) == "table" and rawget(mt, "__instance") then
			return "Instance"
		end
	end
	return typeof(v)
end

return D
