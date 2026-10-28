-- A headless mock of the parts of Roblox this game uses, good enough to run
-- the real server and client scripts end to end:
--   * instances checked against the real API (unknown members and wrong
--     value types raise errors, like the engine does)
--   * virtual time, task library, deferred signals, RunService events
--   * per-context threads (server / client) so LocalPlayer and remotes route
--   * ray casts against parts (blocks, wedges, balls, cylinders) and terrain
--   * a rigid-body integrator for karts (VectorForce + Torque + gravity)
-- It is not a physics engine; it only has to be faithful where the game
-- depends on it.

local D = require("./datatypes")
local Api = require("./gen/api")

local Vector3, CFrame, Color3, Vector2, UDim2 = D.Vector3, D.CFrame, D.Color3, D.Vector2, D.UDim2
local isV3, isCF = D.isV3, D.isCF

local M = {}

function M.new(opts: { [string]: any }?)
	opts = opts or {}
	local G: { [string]: any } = { errors = {}, logs = {}, time = 0, frame = 0 }

	------------------------------------------------------------------------
	-- Threads, contexts, scheduler
	------------------------------------------------------------------------
	local threadCtx = setmetatable({}, { __mode = "k" })
	local testCtx = { name = "test" }
	local sleeping: { { co: thread, at: number } } = {}
	local deferred: { { fn: any, args: { any }, n: number, ctx: any } } = {}

	local function currentCtx()
		local co = coroutine.running()
		return threadCtx[co] or testCtx
	end
	G.currentCtx = currentCtx

	local function report(co, err)
		local tb = debug.traceback(co, tostring(err))
		table.insert(G.errors, tb)
		if opts.printErrors then
			print("[mock error] " .. tb)
		end
	end

	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			report(co, err)
		end
	end

	local function spawnIn(ctx, fn, ...)
		local co = if type(fn) == "thread" then fn else coroutine.create(fn)
		threadCtx[co] = ctx
		resume(co, ...)
		return co
	end
	G.spawnIn = spawnIn

	local function deferIn(ctx, fn, ...)
		table.insert(deferred, { fn = fn, args = { ... }, n = select("#", ...), ctx = ctx })
	end

	local function drainDeferred()
		local guard = 0
		while #deferred > 0 and guard < 10000 do
			guard += 1
			local d = table.remove(deferred, 1)
			spawnIn(d.ctx, d.fn, table.unpack(d.args, 1, d.n))
		end
	end

	local function sleep(seconds: number?)
		local co = coroutine.running()
		assert(threadCtx[co], "task.wait called outside a mock thread")
		local start = G.time
		table.insert(sleeping, { co = co, at = G.time + math.max(seconds or 0, 1 / 60) - 1e-9 })
		coroutine.yield()
		return G.time - start
	end

	local function wakeSleepers()
		local due = {}
		for i = #sleeping, 1, -1 do
			local s = sleeping[i]
			if s.at <= G.time then
				table.remove(sleeping, i)
				table.insert(due, 1, s)
			end
		end
		table.sort(due, function(a, b)
			return a.at < b.at
		end)
		for _, s in due do
			resume(s.co)
		end
	end

	local task = {
		wait = sleep,
		spawn = function(fn, ...)
			return spawnIn(currentCtx(), fn, ...)
		end,
		defer = function(fn, ...)
			deferIn(currentCtx(), fn, ...)
		end,
		delay = function(t, fn, ...)
			local ctx = currentCtx()
			local args = table.pack(...)
			spawnIn(ctx, function()
				sleep(t)
				fn(table.unpack(args, 1, args.n))
			end)
		end,
		cancel = function() end,
	}
	G.task = task

	------------------------------------------------------------------------
	-- Signals (deferred like Roblox's default SignalBehavior)
	------------------------------------------------------------------------
	local Signal = {}
	Signal.__index = Signal
	local SignalMT = { __index = Signal, __type = "RBXScriptSignal" }
	local function newSignal(immediate: boolean?)
		return setmetatable({ conns = {}, waiting = {}, immediate = immediate }, SignalMT)
	end
	G.newSignal = newSignal
	function Signal:Connect(fn)
		assert(type(fn) == "function", "Connect expects a function")
		local c = { fn = fn, ctx = currentCtx(), connected = true }
		table.insert(self.conns, c)
		local sig = self
		c.Disconnect = function()
			c.connected = false
			local i = table.find(sig.conns, c)
			if i then
				table.remove(sig.conns, i)
			end
		end
		c.Connected = true
		return c
	end
	function Signal:Once(fn)
		local c
		c = self:Connect(function(...)
			c.Disconnect()
			fn(...)
		end)
		return c
	end
	function Signal:Wait()
		local co = coroutine.running()
		table.insert(self.waiting, co)
		return coroutine.yield()
	end
	-- fire to every connection (optionally only those of one context)
	function Signal:_fire(onlyCtx, ...)
		for _, c in table.clone(self.conns) do
			if c.connected and (onlyCtx == nil or c.ctx == onlyCtx) then
				if self.immediate then
					spawnIn(c.ctx, c.fn, ...)
				else
					deferIn(c.ctx, c.fn, ...)
				end
			end
		end
		local w = self.waiting
		self.waiting = {}
		for _, co in w do
			if onlyCtx == nil or threadCtx[co] == onlyCtx then
				local args = table.pack(...)
				table.insert(deferred, {
					fn = co,
					args = { table.unpack(args, 1, args.n) },
					n = args.n,
					ctx = threadCtx[co],
				})
			else
				table.insert(self.waiting, co)
			end
		end
	end
	function Signal:Fire(...)
		self:_fire(nil, ...)
	end

	------------------------------------------------------------------------
	-- Enum
	------------------------------------------------------------------------
	local enumCache = {}
	local EnumItemMT = { __type = "EnumItem" }
	EnumItemMT.__index = EnumItemMT
	EnumItemMT.__tostring = function(e)
		return "Enum." .. e._enum .. "." .. e.Name
	end
	local EnumMT = { __type = "Enum" }
	local Enum = setmetatable({}, {
		__index = function(_, enumName)
			local items = Api.enums[enumName]
			if not items then
				error("Enum." .. tostring(enumName) .. " does not exist", 2)
			end
			local cached = enumCache[enumName]
			if cached then
				return cached
			end
			local e = setmetatable({ Name = enumName }, EnumMT)
			local list = {}
			for i, n in items do
				local item = setmetatable({ Name = n, Value = i - 1, EnumType = e, _enum = enumName }, EnumItemMT)
				rawset(e, n, item)
				table.insert(list, item)
			end
			rawset(e, "GetEnumItems", function()
				return table.clone(list)
			end)
			EnumMT.__index = function(_, k)
				error(tostring(k) .. " is not a valid EnumItem", 2)
			end
			enumCache[enumName] = e
			return e
		end,
	})
	G.Enum = Enum

	------------------------------------------------------------------------
	-- Instances
	------------------------------------------------------------------------
	local flat: { [string]: { props: { [string]: string }, methods: { [string]: boolean }, chain: { [string]: boolean } } } = {}
	local function classInfo(name: string)
		local f = flat[name]
		if f then
			return f
		end
		local c = Api.classes[name]
		if not c then
			error("mock: unknown class " .. tostring(name))
		end
		local props, methods, chain = {}, {}, { [name] = true }
		if c.super then
			local s = classInfo(c.super)
			for k, v in s.props do
				props[k] = v
			end
			for k in s.methods do
				methods[k] = true
			end
			for k in s.chain do
				chain[k] = true
			end
		end
		for k, v in c.props do
			props[k] = v
		end
		for k in c.methods do
			methods[k] = true
		end
		f = { props = props, methods = methods, chain = chain }
		flat[name] = f
		return f
	end

	local Instance = {}
	local InstMT = { __instance = true, __type = "Instance" }
	local behaviors: { [string]: { [string]: any } } = {} -- per class: methods/getters/setters

	local defaults: { [string]: { [string]: any } } = {
		BasePart = {
			Anchored = false,
			CanCollide = true,
			CanQuery = true,
			CanTouch = true,
			CastShadow = true,
			Transparency = 0,
			Massless = false,
			Locked = false,
			CollisionGroup = "Default",
			RootPriority = 0,
		},
		GuiObject = { Visible = true, BackgroundTransparency = 0, Rotation = 0, ZIndex = 1 },
		-- Roblox's own defaults where the first enum item / zero would be wrong
		-- (they matter for tools/dump_gui + render_gui.py)
		TextLabel = { TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextSize = 14 },
		TextButton = { TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextSize = 14 },
		TextBox = { TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextSize = 14 },
		UIListLayout = {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = D.UDim.new(0, 0),
		},
		UIGridLayout = {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			CellSize = UDim2.new(0, 100, 0, 100),
			CellPadding = UDim2.new(0, 5, 0, 5),
		},
		UIPadding = { PaddingLeft = D.UDim.new(0, 0), PaddingRight = D.UDim.new(0, 0), PaddingTop = D.UDim.new(0, 0), PaddingBottom = D.UDim.new(0, 0) },
		UIStroke = { Enabled = true, Thickness = 1 },
		UIScale = { Scale = 1 },
		UICorner = { CornerRadius = D.UDim.new(0, 8) },
		LayerCollector = { Enabled = true, ResetOnSpawn = true },
		Constraint = { Enabled = true },
		Humanoid = { Health = 100, MaxHealth = 100, JumpHeight = 7.2, WalkSpeed = 16 },
		Light = { Enabled = true },
		Smoke = { Enabled = true },
	}

	local function defaultFor(inst, key, typ)
		for cls in pairs(inst._info.chain) do
			local d = defaults[cls]
			if d and d[key] ~= nil then
				return d[key]
			end
		end
		if typ == "boolean" then
			return false
		elseif typ == "number" then
			return 0
		elseif typ == "string" then
			return ""
		elseif typ == "Vector3" then
			return Vector3.zero
		elseif typ == "CFrame" then
			return CFrame.new()
		elseif typ == "Color3" then
			return Color3.new(0.64, 0.64, 0.64)
		elseif typ == "UDim2" then
			return UDim2.new(0, 0, 0, 0)
		elseif typ == "Vector2" then
			return Vector2.zero
		elseif typeof(typ) == "string" and typ:sub(1, 4) == "Enum" then
			local enumName = typ:sub(5):gsub("%?$", "")
			local ok, e = pcall(function()
				return Enum[enumName]
			end)
			if ok then
				return e:GetEnumItems()[1]
			end
		end
		return nil
	end

	local function checkType(className, key, typ, v)
		local nullable = typ:sub(-1) == "?"
		local t = typ:gsub("%?$", "")
		if v == nil then
			if t == "boolean" or t == "number" or t == "string" or t == "Vector3" or t == "CFrame" or t == "Color3" or t == "UDim2" then
				error(string.format("%s.%s cannot be set to nil", className, key), 3)
			end
			return
		end
		local ok = true
		if t == "boolean" or t == "number" or t == "string" then
			ok = type(v) == t
		elseif t == "Vector3" then
			ok = isV3(v)
		elseif t == "CFrame" then
			ok = isCF(v)
		elseif t == "Color3" or t == "UDim2" or t == "UDim" or t == "Vector2" or t == "PhysicalProperties" or t == "NumberRange" or t == "NumberSequence" or t == "ColorSequence" or t == "Font" then
			ok = D.typeof(v) == t
		elseif t:sub(1, 4) == "Enum" and t ~= "EnumItem" then
			ok = D.typeof(v) == "EnumItem" and v._enum == t:sub(5)
			if not ok and type(v) == "string" then
				ok = true -- Roblox accepts enum names as strings
			end
		elseif Api.classes[t] then
			ok = type(v) == "table" and getmetatable(v) == InstMT and v._info.chain[t] == true
		end
		if not ok then
			error(string.format("bad value for %s.%s: expected %s, got %s", className, key, t, D.typeof(v)), 3)
		end
		local _ = nullable
	end

	local function newInstance(className: string)
		local info = classInfo(className)
		local inst = setmetatable({
			_class = className,
			_info = info,
			_props = { Name = className },
			_children = {},
			_parent = nil,
			_attrs = {},
			_signals = {},
			_attrSignals = {},
			_propSignals = {},
		}, InstMT)
		return inst
	end

	local function signalOf(inst, name)
		local s = inst._signals[name]
		if not s then
			s = newSignal()
			inst._signals[name] = s
		end
		return s
	end

	local function isDescendantOf(inst, ancestor)
		local p = inst._parent
		while p do
			if p == ancestor then
				return true
			end
			p = p._parent
		end
		return false
	end

	local function behaviorFor(inst, key)
		for cls in pairs(inst._info.chain) do
			local b = behaviors[cls]
			if b and b[key] ~= nil then
				return b[key]
			end
		end
		return nil
	end

	local getters: { [string]: { [string]: (any) -> any } } = {}
	local setters: { [string]: { [string]: (any, any) -> () } } = {}
	local function getterFor(inst, key)
		for cls in pairs(inst._info.chain) do
			local g = getters[cls]
			if g and g[key] then
				return g[key]
			end
		end
		return nil
	end
	local function setterFor(inst, key)
		for cls in pairs(inst._info.chain) do
			local s = setters[cls]
			if s and s[key] then
				return s[key]
			end
		end
		return nil
	end

	local partRegistry: { [any]: boolean } = {}
	local workspaceRef
	local onPartMoved: (any, string?) -> () = function() end

	local function fireDescendantAdded(inst, child)
		local p = inst
		while p do
			local s = p._signals.DescendantAdded
			if s then
				s:Fire(child)
			end
			p = p._parent
		end
	end

	local function registerTree(inst, add: boolean)
		if inst._info.chain.BasePart and inst._class ~= "Terrain" then
			partRegistry[inst] = if add then true else nil
			onPartMoved(inst, if add then "add" else "remove")
		end
		for _, c in inst._children do
			registerTree(c, add)
		end
	end

	local function setParent(inst, parent)
		if inst._destroyed and parent ~= nil then
			error("The Parent property of " .. inst._props.Name .. " is locked", 3)
		end
		local old = inst._parent
		if old == parent then
			return
		end
		local wasInWs = workspaceRef and (inst == workspaceRef or isDescendantOf(inst, workspaceRef))
		if old then
			local i = table.find(old._children, inst)
			if i then
				table.remove(old._children, i)
			end
			if old._signals.ChildRemoved then
				old._signals.ChildRemoved:Fire(inst)
			end
		end
		inst._parent = parent
		if parent then
			table.insert(parent._children, inst)
			if parent._signals.ChildAdded then
				parent._signals.ChildAdded:Fire(inst)
			end
			fireDescendantAdded(parent, inst)
			local function deep(i)
				for _, c in i._children do
					fireDescendantAdded(parent, c)
					deep(c)
				end
			end
			deep(inst)
		end
		local nowInWs = workspaceRef and parent and (parent == workspaceRef or isDescendantOf(inst, workspaceRef))
		if wasInWs and not nowInWs then
			registerTree(inst, false)
		elseif nowInWs and not wasInWs then
			registerTree(inst, true)
		end
		if inst._signals.AncestryChanged then
			inst._signals.AncestryChanged:Fire(inst, parent)
		end
	end

	InstMT.__index = function(self, key)
		-- internal fields (_parent, _destroyed, ...) default to nil
		if type(key) == "string" and string.byte(key, 1) == 95 then
			return nil
		end
		-- generic Instance methods
		local generic = Instance[key]
		if generic then
			return generic
		end
		local b = behaviorFor(self, key)
		if b ~= nil then
			return b
		end
		if key == "Parent" then
			return self._parent
		elseif key == "ClassName" then
			return self._class
		end
		local g = getterFor(self, key)
		if g then
			return g(self)
		end
		local typ = self._info.props[key]
		if typ then
			if typ:sub(1, 15) == "RBXScriptSignal" then
				return signalOf(self, key)
			end
			local v = self._props[key]
			if v == nil then
				v = defaultFor(self, key, typ)
			end
			return v
		end
		if self._info.methods[key] then
			return function()
				error("mock: " .. self._class .. ":" .. key .. " is not implemented", 2)
			end
		end
		for _, c in self._children do
			if c._props.Name == key then
				return c
			end
		end
		error(tostring(key) .. " is not a valid member of " .. self._class .. ' "' .. tostring(self._props.Name) .. '"', 2)
	end

	InstMT.__newindex = function(self, key, v)
		if type(key) == "string" and string.byte(key, 1) == 95 then
			rawset(self, key, v)
			return
		end
		if key == "Parent" then
			if v ~= nil and not (type(v) == "table" and getmetatable(v) == InstMT) then
				error("Parent must be an Instance", 2)
			end
			setParent(self, v)
			return
		end
		local typ = self._info.props[key]
		if not typ then
			error(tostring(key) .. " is not a valid member of " .. self._class, 2)
		end
		if typ:sub(1, 15) == "RBXScriptSignal" then
			error("cannot assign to event " .. key, 2)
		end
		checkType(self._class, key, typ, v)
		if type(v) == "string" and typ:sub(1, 4) == "Enum" then
			v = (Enum :: any)[typ:sub(5):gsub("%?$", "")][v]
		end
		local s = setterFor(self, key)
		if s then
			s(self, v)
		else
			self._props[key] = v
		end
		local ps = self._propSignals[key]
		if ps then
			ps:Fire()
		end
		if self._signals.Changed then
			self._signals.Changed:Fire(key)
		end
	end
	InstMT.__tostring = function(self)
		return self._props.Name
	end

	function Instance.GetChildren(self)
		return table.clone(self._children)
	end
	function Instance.GetDescendants(self)
		local out = {}
		local function walk(i)
			for _, c in i._children do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function Instance.FindFirstChild(self, name, recursive)
		for _, c in self._children do
			if c._props.Name == name then
				return c
			end
		end
		if recursive then
			for _, c in self._children do
				local f = Instance.FindFirstChild(c, name, true)
				if f then
					return f
				end
			end
		end
		return nil
	end
	function Instance.FindFirstChildOfClass(self, cls)
		for _, c in self._children do
			if c._class == cls then
				return c
			end
		end
		return nil
	end
	function Instance.FindFirstChildWhichIsA(self, cls)
		for _, c in self._children do
			if c._info.chain[cls] then
				return c
			end
		end
		return nil
	end
	function Instance.FindFirstAncestor(self, name)
		local p = self._parent
		while p do
			if p._props.Name == name then
				return p
			end
			p = p._parent
		end
		return nil
	end
	function Instance.FindFirstAncestorOfClass(self, cls)
		local p = self._parent
		while p do
			if p._class == cls then
				return p
			end
			p = p._parent
		end
		return nil
	end
	function Instance.WaitForChild(self, name, timeout)
		local found = Instance.FindFirstChild(self, name)
		if found then
			return found
		end
		local co = coroutine.running()
		if not threadCtx[co] then
			error("WaitForChild(" .. name .. ") on " .. self._props.Name .. " would block the test thread", 2)
		end
		local deadline = G.time + (timeout or 30)
		while G.time < deadline do
			sleep(1 / 60)
			found = Instance.FindFirstChild(self, name)
			if found then
				return found
			end
		end
		if not timeout then
			error("Infinite yield: WaitForChild(" .. name .. ") on " .. self._props.Name, 2)
		end
		return nil
	end
	function Instance.IsA(self, cls)
		return self._info.chain[cls] == true
	end
	function Instance.IsDescendantOf(self, other)
		return isDescendantOf(self, other)
	end
	function Instance.IsAncestorOf(self, other)
		return isDescendantOf(other, self)
	end
	function Instance.Destroy(self)
		for _, c in table.clone(self._children) do
			Instance.Destroy(c)
		end
		setParent(self, nil)
		self._destroyed = true
		if self._signals.Destroying then
			self._signals.Destroying:Fire()
		end
	end
	function Instance.ClearAllChildren(self)
		for _, c in table.clone(self._children) do
			Instance.Destroy(c)
		end
	end
	function Instance.GetAttribute(self, name)
		return self._attrs[name]
	end
	function Instance.GetAttributes(self)
		return table.clone(self._attrs)
	end
	function Instance.SetAttribute(self, name, value)
		local tv = D.typeof(value)
		local okTypes = { ["nil"] = true, boolean = true, number = true, string = true, Vector3 = true, Color3 = true, UDim2 = true, Vector2 = true, CFrame = true, EnumItem = true }
		if not okTypes[tv] then
			error("SetAttribute: unsupported value type " .. tv, 2)
		end
		if self._attrs[name] == value then
			return
		end
		self._attrs[name] = value
		local s = self._attrSignals[name]
		if s then
			s:Fire()
		end
		if self._signals.AttributeChanged then
			self._signals.AttributeChanged:Fire(name)
		end
	end
	function Instance.GetAttributeChangedSignal(self, name)
		local s = self._attrSignals[name]
		if not s then
			s = newSignal()
			self._attrSignals[name] = s
		end
		return s
	end
	function Instance.GetPropertyChangedSignal(self, name)
		if not self._info.props[name] then
			error(name .. " is not a valid property of " .. self._class, 2)
		end
		local s = self._propSignals[name]
		if not s then
			s = newSignal()
			self._propSignals[name] = s
		end
		return s
	end
	function Instance.GetFullName(self)
		local parts = {}
		local p = self
		while p and p._class ~= "DataModel" do
			table.insert(parts, 1, p._props.Name)
			p = p._parent
		end
		return table.concat(parts, ".")
	end

	local InstanceLib = {
		new = function(className, parent)
			if not Api.classes[className] then
				error("Unable to create an Instance of type " .. tostring(className), 2)
			end
			local inst = newInstance(className)
			local init = behaviorFor(inst, "_init")
			if init then
				init(inst)
			end
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
	}
	G.Instance = InstanceLib
	G.newInstance = function(className)
		return InstanceLib.new(className)
	end
	G.InstMT = InstMT

	------------------------------------------------------------------------
	-- BasePart / Model behaviour
	------------------------------------------------------------------------
	local function partCF(p)
		return p._props.CFrame or CFrame.new()
	end
	getters.BasePart = {
		Position = function(p)
			return partCF(p).Position
		end,
		Size = function(p)
			return p._props.Size or Vector3.new(4, 1, 2)
		end,
		Mass = function(p)
			return M.partMass(p)
		end,
		AssemblyMass = function(p)
			return M.assemblyMass(G, p)
		end,
		AssemblyLinearVelocity = function(p)
			local root = M.rootOf(p)
			return root._props._vel or Vector3.zero
		end,
		AssemblyAngularVelocity = function(p)
			local root = M.rootOf(p)
			return root._props._angVel or Vector3.zero
		end,
		AssemblyCenterOfMass = function(p)
			return partCF(M.rootOf(p)).Position
		end,
		ReceiveAge = function()
			return 0
		end,
	}
	setters.BasePart = {
		CFrame = function(p, v)
			p._props.CFrame = v
			onPartMoved(p)
		end,
		Position = function(p, v)
			local c = partCF(p)
			p._props.CFrame = c.Rotation + v
			onPartMoved(p)
		end,
		Size = function(p, v)
			assert(v.X >= 0 and v.Y >= 0 and v.Z >= 0, "negative part size")
			if p._class == "Part" and (p._props.Shape == nil or p._props.Shape.Name == "Block") then
				-- Roblox clamps very small sizes; keep as given
			end
			assert(v.X <= 2048 and v.Y <= 2048 and v.Z <= 2048, "Part size above 2048: " .. tostring(v))
			p._props.Size = v
			onPartMoved(p)
		end,
		AssemblyLinearVelocity = function(p, v)
			M.rootOf(p)._props._vel = v
		end,
		AssemblyAngularVelocity = function(p, v)
			M.rootOf(p)._props._angVel = v
		end,
		Anchored = function(p, v)
			p._props.Anchored = v
			if v then
				p._props._owner = nil
			end
			onPartMoved(p)
		end,
	}
	behaviors.BasePart = {
		SetNetworkOwner = function(p, player)
			if M.rootOf(p)._props.Anchored then
				error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.", 2)
			end
			if not (workspaceRef and isDescendantOf(p, workspaceRef)) then
				error("Can only call Network Ownership API on a part that is descendant of Workspace", 2)
			end
			M.rootOf(p)._props._owner = player
		end,
		CanSetNetworkOwnership = function(p)
			local ok = not M.rootOf(p)._props.Anchored and workspaceRef ~= nil and isDescendantOf(p, workspaceRef)
			return ok, if ok then nil else "anchored or not in workspace"
		end,
		GetNetworkOwner = function(p)
			return M.rootOf(p)._props._owner
		end,
		ApplyImpulse = function(p, j)
			local r = M.rootOf(p)
			r._props._vel = (r._props._vel or Vector3.zero) + j / M.assemblyMass(G, r)
		end,
		GetMass = function(p)
			return M.partMass(p)
		end,
	}
	getters.Model = {
		WorldPivot = function(m)
			return if m._props.PrimaryPart then partCF(m._props.PrimaryPart) else CFrame.new()
		end,
	}
	behaviors.Model = {
		GetPivot = function(m)
			local pp = m._props.PrimaryPart
			if pp then
				return partCF(pp)
			end
			return CFrame.new()
		end,
		PivotTo = function(m, target)
			assert(isCF(target), "PivotTo expects a CFrame")
			local pp = m._props.PrimaryPart
			local from = if pp then partCF(pp) else CFrame.new()
			local delta = target * from:Inverse()
			for _, d in Instance.GetDescendants(m) do
				if d._info.chain.BasePart then
					d._props.CFrame = delta * partCF(d)
					onPartMoved(d)
				end
			end
		end,
	}

	behaviors.Seat = {
		Sit = function(seat, humanoid)
			assert(humanoid and humanoid._class == "Humanoid", "Seat:Sit expects a Humanoid")
			if humanoid._props.Health <= 0 then
				return
			end
			humanoid._props.SeatPart = seat
			humanoid._props.Sit = true
			seat._props.Occupant = humanoid
			local weld = InstanceLib.new("Weld")
			weld._props.Name = "SeatWeld"
			weld._props.Part0 = seat
			local character = humanoid._parent
			weld._props.Part1 = character and character:FindFirstChild("HumanoidRootPart")
			weld.Parent = seat
			local ps = humanoid._propSignals.SeatPart
			if ps then
				ps:Fire()
			end
		end,
	}
	setters.Humanoid = {
		Sit = function(h, v)
			h._props.Sit = v
			if not v and h._props.SeatPart then
				local seat = h._props.SeatPart
				h._props.SeatPart = nil
				seat._props.Occupant = nil
				local w = seat:FindFirstChild("SeatWeld")
				if w then
					w:Destroy()
				end
			end
		end,
		Health = function(h, v)
			local was = h._props.Health or 100
			h._props.Health = v
			if v <= 0 and was > 0 then
				signalOf(h, "Died"):Fire()
			end
		end,
	}
	behaviors.Humanoid = {
		SetStateEnabled = function(h, state, on)
			h._props._states = h._props._states or {}
			h._props._states[state.Name] = on
		end,
		GetStateEnabled = function(h, state)
			local s = h._props._states
			return not s or s[state.Name] ~= false
		end,
		TakeDamage = function(h, d)
			h.Health = h.Health - d
		end,
	}
	behaviors.Sound = {
		Play = function(snd)
			assert(type(snd._props.SoundId) == "string" and snd._props.SoundId ~= "", "Sound:Play() without a SoundId")
			snd._props.IsPlaying = true
		end,
		Stop = function(snd)
			snd._props.IsPlaying = false
		end,
	}

	------------------------------------------------------------------------
	-- Remotes
	------------------------------------------------------------------------
	behaviors.RemoteEvent = {
		FireServer = function(re, ...)
			local ctx = currentCtx()
			assert(ctx.player, "FireServer called outside a client")
			local sig = signalOf(re, "OnServerEvent")
			for _, c in table.clone(sig.conns) do
				if c.ctx == G.serverCtx then
					deferIn(c.ctx, c.fn, ctx.player, ...)
				end
			end
		end,
		FireClient = function(re, player, ...)
			assert(currentCtx() == G.serverCtx, "FireClient called outside the server")
			assert(type(player) == "table" and player._class == "Player", "FireClient needs a Player")
			local cctx = G.clientCtx[player]
			if cctx then
				signalOf(re, "OnClientEvent"):_fire(cctx, ...)
			end
		end,
		FireAllClients = function(re, ...)
			assert(currentCtx() == G.serverCtx, "FireAllClients called outside the server")
			for _, cctx in G.clientCtx do
				signalOf(re, "OnClientEvent"):_fire(cctx, ...)
			end
		end,
	}

	------------------------------------------------------------------------
	-- DataModel and services
	------------------------------------------------------------------------
	local game = newInstance("DataModel")
	game._props.Name = "Game"
	-- a public server of a published place unless the test says otherwise
	game._props.PlaceId = 4242
	game._props.JobId = opts.jobId or "job-1"
	game._props.PrivateServerId = opts.privateServerId or ""
	game._props.PrivateServerOwnerId = 0
	G.game = game
	G.studio = opts.studio ~= false
	local services = {}
	local function service(name)
		local s = services[name]
		if not s then
			s = newInstance(name)
			s._props.Name = name
			setParent(s, game)
			services[name] = s
		end
		return s
	end
	behaviors.DataModel = {
		GetService = function(_, name)
			return service(name)
		end,
		BindToClose = function(_, fn)
			G.closeHandlers = G.closeHandlers or {}
			table.insert(G.closeHandlers, fn)
		end,
		IsLoaded = function()
			return true
		end,
	}
	getters.DataModel = {
		Workspace = function()
			return service("Workspace")
		end,
	}

	local workspace = service("Workspace")
	workspaceRef = workspace
	workspace._props.Gravity = 196.2
	local terrain = newInstance("Terrain")
	terrain._props.Name = "Terrain"
	setParent(terrain, workspace)
	workspace._props.Terrain = terrain
	local camera = newInstance("Camera")
	camera._props.Name = "Camera"
	camera._props.FieldOfView = 70
	camera._props.CFrame = CFrame.new(0, 20, 20)
	setParent(camera, workspace)
	workspace._props.CurrentCamera = camera
	G.viewport = Vector2.new(1280, 720)
	getters.Camera = {
		ViewportSize = function()
			return G.viewport
		end,
	}
	-- resize the game window (fires the camera's ViewportSize change)
	G.setViewport = function(v)
		G.viewport = v
		local ps = camera._propSignals.ViewportSize
		if ps then
			ps:Fire()
		end
	end
	G.workspace = workspace
	G.terrain = terrain

	behaviors.Workspace = {
		GetServerTimeNow = function()
			return 1.7e9 + G.time
		end,
		Raycast = function(_, origin, dir, params)
			return M.raycast(G, origin, dir, params)
		end,
	}

	-- Players
	local players = service("Players")
	getters.Players = {
		LocalPlayer = function()
			return currentCtx().player
		end,
	}
	behaviors.Players = {
		GetPlayers = function(ps)
			local out = {}
			for _, c in ps._children do
				if c._class == "Player" then
					table.insert(out, c)
				end
			end
			return out
		end,
		GetPlayerByUserId = function(ps, id)
			for _, c in ps._children do
				if c._class == "Player" and c._props.UserId == id then
					return c
				end
			end
			return nil
		end,
	}

	-- Player: a network ping per player (seconds, round trip; tests may set it)
	G.pings = {}
	-- teleport data a player arrived with (tests set G.joinData[userId])
	G.joinData = {}
	behaviors.Player = {
		GetNetworkPing = function(p)
			return G.pings[p] or 0.06
		end,
		GetJoinData = function(p)
			return { TeleportData = G.joinData[p._props.UserId] }
		end,
		-- disconnects the player (G.kicks[userId] = the message)
		Kick = function(p, message)
			G.kicks[p._props.UserId] = message or ""
			task.defer(function()
				if p._parent then
					G.removePlayer(p)
				end
			end)
		end,
	}
	G.kicks = {}

	-- RunService
	local runService = service("RunService")
	local renderBindings: { { name: string, priority: number, fn: any, ctx: any } } = {}
	local function immediateSignal(inst, name)
		local s = newSignal(true)
		inst._signals[name] = s
		return s
	end
	immediateSignal(runService, "Heartbeat")
	immediateSignal(runService, "PreSimulation")
	immediateSignal(runService, "PostSimulation")
	immediateSignal(runService, "Stepped")
	immediateSignal(runService, "RenderStepped")
	immediateSignal(runService, "PreRender")
	behaviors.RunService = {
		BindToRenderStep = function(_, name, priority, fn)
			table.insert(renderBindings, { name = name, priority = priority, fn = fn, ctx = currentCtx() })
			table.sort(renderBindings, function(a, b)
				return a.priority < b.priority
			end)
		end,
		UnbindFromRenderStep = function(_, name)
			for i = #renderBindings, 1, -1 do
				if renderBindings[i].name == name and renderBindings[i].ctx == currentCtx() then
					table.remove(renderBindings, i)
				end
			end
		end,
		IsServer = function()
			return currentCtx() == G.serverCtx
		end,
		IsClient = function()
			return currentCtx().player ~= nil
		end,
		IsStudio = function()
			return G.studio
		end,
	}

	-- UserInputService (driven by the test)
	local uis = service("UserInputService")
	G.keys = {}
	G.gamepad = nil
	getters.UserInputService = {
		TouchEnabled = function()
			return G.touch == true
		end,
		KeyboardEnabled = function()
			return G.touch ~= true
		end,
		GamepadEnabled = function()
			return G.gamepad ~= nil
		end,
	}
	behaviors.UserInputService = {
		IsKeyDown = function(_, key)
			return G.keys[key.Name] == true
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		GetGamepadConnected = function()
			return G.gamepad ~= nil
		end,
		GetGamepadState = function()
			local out = {}
			local gp = G.gamepad or {}
			table.insert(out, { KeyCode = Enum.KeyCode.ButtonR2, Position = Vector3.new(0, 0, gp.r2 or 0) })
			table.insert(out, { KeyCode = Enum.KeyCode.ButtonL2, Position = Vector3.new(0, 0, gp.l2 or 0) })
			table.insert(out, { KeyCode = Enum.KeyCode.Thumbstick1, Position = Vector3.new(gp.x or 0, 0, 0) })
			return out
		end,
	}
	G.pressKey = function(name: string)
		G.keys[name] = true
		local io = { KeyCode = Enum.KeyCode[name], UserInputType = Enum.UserInputType.Keyboard }
		signalOf(uis, "InputBegan"):Fire(io, false)
	end
	G.releaseKey = function(name: string)
		G.keys[name] = nil
		local io = { KeyCode = Enum.KeyCode[name], UserInputType = Enum.UserInputType.Keyboard }
		signalOf(uis, "InputEnded"):Fire(io, false)
	end
	-- mouse: wheel notches (+ = away from you = zoom in), right button, movement
	local function mouseIO(kind: string, pos: any, delta: any)
		-- (KeyCode would be Enum.KeyCode.Unknown in Roblox; the API dump lacks it)
		return {
			UserInputType = Enum.UserInputType[kind],
			Position = pos or Vector3.zero,
			Delta = delta or Vector3.zero,
		}
	end
	G.wheel = function(notches: number)
		signalOf(uis, "InputChanged"):Fire(mouseIO("MouseWheel", Vector3.new(0, 0, notches)), false)
	end
	G.mouseButton2 = function(down: boolean)
		signalOf(uis, if down then "InputBegan" else "InputEnded"):Fire(mouseIO("MouseButton2"), false)
	end
	G.mouseMove = function(dx: number, dy: number)
		signalOf(uis, "InputChanged"):Fire(mouseIO("MouseMovement", nil, Vector3.new(dx, dy, 0)), false)
	end
	-- touches (set G.touch = true before a client starts for TouchEnabled).
	-- A finger goes down on a GUI button (processed) or on the empty screen,
	-- moves, and lifts over its button or somewhere else: like Roblox, the
	-- button's own InputEnded only fires when it lifts over the button.
	-- `G.touchLost` only flips the state to End (an end the scripts never
	-- hear about, e.g. the app lost focus); passing an old `io` to touchBegin
	-- starts a new touch on the same InputObject, as Roblox recycles them.
	G.touchBegin = function(button: any?, io: any?)
		io = io or { UserInputType = Enum.UserInputType.Touch, Position = Vector3.zero, Delta = Vector3.zero }
		io.UserInputState = Enum.UserInputState.Begin
		io._button = button
		if button then
			signalOf(button, "InputBegan"):Fire(io)
		end
		signalOf(uis, "InputBegan"):Fire(io, button ~= nil)
		signalOf(uis, "TouchStarted"):Fire(io, button ~= nil)
		return io
	end
	G.touchMove = function(io: any, dx: number, dy: number)
		io.UserInputState = Enum.UserInputState.Change
		io.Delta = Vector3.new(dx, dy, 0)
		io.Position = io.Position + io.Delta
		signalOf(uis, "InputChanged"):Fire(io, io._button ~= nil)
		signalOf(uis, "TouchMoved"):Fire(io, io._button ~= nil)
	end
	G.touchEnd = function(io: any, overButton: boolean?)
		io.UserInputState = Enum.UserInputState.End
		if io._button and overButton ~= false then
			signalOf(io._button, "InputEnded"):Fire(io)
		end
		signalOf(uis, "InputEnded"):Fire(io, io._button ~= nil)
		signalOf(uis, "TouchEnded"):Fire(io, io._button ~= nil)
	end
	G.touchLost = function(io: any)
		io.UserInputState = Enum.UserInputState.End
	end

	-- PhysicsService
	local physicsService = service("PhysicsService")
	G.collisionGroups = { Default = true }
	G.collidable = {}
	behaviors.PhysicsService = {
		RegisterCollisionGroup = function(_, name)
			G.collisionGroups[name] = true
		end,
		CollisionGroupSetCollidable = function(_, a, b, on)
			assert(G.collisionGroups[a] and G.collisionGroups[b], "unknown collision group " .. a .. "/" .. b)
			G.collidable[a .. "|" .. b] = on
			G.collidable[b .. "|" .. a] = on
		end,
	}
	local _ = physicsService

	-- DataStoreService (in memory)
	local dss = service("DataStoreService")
	G.datastore = {}
	behaviors.DataStoreService = {
		GetDataStore = function(_, name)
			if G.datastoreFails then
				error("API Services are disabled")
			end
			local data = G.datastore
			local store = {}
			function store:GetAsync(key)
				sleep(0.05)
				return data[name .. "/" .. key]
			end
			function store:SetAsync(key, value)
				sleep(0.05)
				data[name .. "/" .. key] = value
			end
			function store:UpdateAsync(key, fn)
				sleep(0.05)
				local v = fn(data[name .. "/" .. key])
				if v ~= nil then
					data[name .. "/" .. key] = v
				end
				return v
			end
			return store
		end,
	}
	local _ = dss

	-- MemoryStoreService (in memory, shared by "every server" of the test).
	-- Sorted maps and hash maps are the same tables here; expiry runs on the
	-- game clock. G.memoryFails makes every request fail.
	service("MemoryStoreService")
	G.memory = {}
	local function deepCopy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end
	local function memMap(name)
		G.memory[name] = G.memory[name] or {}
		local data = G.memory[name]
		local function live(key)
			local e = data[key]
			if e and e.expires <= G.time then
				data[key] = nil
				return nil
			end
			return e
		end
		local function request()
			sleep(0.02)
			if G.memoryFails then
				error("MemoryStore request failed")
			end
		end
		local m = {}
		function m:GetAsync(key)
			assert(type(key) == "string", "MemoryStore keys are strings")
			request()
			local e = live(key)
			return if e then deepCopy(e.value) else nil
		end
		function m:SetAsync(key, value, expiration)
			assert(type(key) == "string" and type(expiration) == "number", "SetAsync(key, value, expiration)")
			request()
			data[key] = { value = deepCopy(value), expires = G.time + expiration }
			return true
		end
		function m:UpdateAsync(key, fn, expiration)
			assert(type(key) == "string" and type(expiration) == "number", "UpdateAsync(key, fn, expiration)")
			request()
			local e = live(key)
			local v = fn(if e then deepCopy(e.value) else nil)
			if v ~= nil then
				data[key] = { value = deepCopy(v), expires = G.time + expiration }
			end
			return v
		end
		function m:RemoveAsync(key)
			request()
			data[key] = nil
		end
		function m:GetRangeAsync(_direction, count)
			request()
			local keys = {}
			for k in data do
				if live(k) then
					table.insert(keys, k)
				end
			end
			table.sort(keys)
			local out = {}
			for i = 1, math.min(#keys, count) do
				table.insert(out, { key = keys[i], value = deepCopy(data[keys[i]].value) })
			end
			return out
		end
		return m
	end
	G.memMap = memMap
	behaviors.MemoryStoreService = {
		GetSortedMap = function(_, name)
			return memMap(name)
		end,
		GetHashMap = function(_, name)
			return memMap(name)
		end,
	}

	-- TeleportService: reserved servers and teleports are recorded
	-- (G.teleports); G.teleportFails / G.reserveFails make them fail.
	service("TeleportService")
	G.teleports = {}
	G.reservedCount = 0
	G.teleportGui = {}
	behaviors.TeleportService = {
		ReserveServerAsync = function(_, placeId)
			assert(type(placeId) == "number", "ReserveServerAsync(placeId)")
			sleep(0.05)
			if G.reserveFails then
				error("HTTP 500 (Internal Server Error)")
			end
			G.reservedCount += 1
			return "access-" .. G.reservedCount, "psid-" .. G.reservedCount
		end,
		TeleportAsync = function(_, placeId, players, options)
			assert(type(placeId) == "number" and type(players) == "table", "TeleportAsync(placeId, players, options)")
			sleep(0.05)
			if G.teleportFails then
				error("Teleport failed: Unauthorized")
			end
			local code = options and options._props.ReservedServerAccessCode
			table.insert(G.teleports, {
				placeId = placeId,
				players = table.clone(players),
				code = if code and code ~= "" then code else nil,
				data = options and options._props._teleportData,
				time = G.time,
			})
			return {}
		end,
		SetTeleportGui = function(_, gui)
			G.teleportGui[currentCtx()] = gui
		end,
		GetArrivingTeleportGui = function()
			return G.arrivingGui
		end,
		GetLocalPlayerTeleportData = function()
			return G.localTeleportData
		end,
	}
	behaviors.TeleportOptions = {
		SetTeleportData = function(self, data)
			self._props._teleportData = deepCopy(data)
		end,
		GetTeleportData = function(self)
			return self._props._teleportData
		end,
	}

	-- ReplicatedFirst and ContentProvider (the loading screen)
	service("ReplicatedFirst")
	behaviors.ReplicatedFirst = {
		RemoveDefaultLoadingScreen = function()
			G.defaultLoadingRemoved = true
		end,
	}
	service("ContentProvider")
	getters.ContentProvider = {
		RequestQueueSize = function()
			return G.requestQueue or 0
		end,
	}

	-- TweenService: numbers move linearly over the tween's time, one step per
	-- frame (so a fade that is not cancelled keeps changing the property, as in
	-- Roblox); other values jump to the goal at the end. Cancel stops it.
	service("TweenService")
	behaviors.TweenService = {
		Create = function(_, inst, info, goals)
			local duration = (info and info.Time) or 1
			local cancelled = false
			local tween
			tween = {
				Play = function()
					cancelled = false
					local from = {}
					for k in goals do
						from[k] = inst[k]
					end
					local start = G.time
					spawnIn(currentCtx(), function()
						while not cancelled do
							local a = if duration > 0 then math.min((G.time - start) / duration, 1) else 1
							for k, v in goals do
								if type(v) == "number" and type(from[k]) == "number" then
									inst[k] = from[k] + (v - from[k]) * a
								elseif a >= 1 then
									inst[k] = v
								end
							end
							if a >= 1 then
								tween.Completed:Fire()
								return
							end
							sleep(1 / 60)
						end
					end)
				end,
				Cancel = function()
					cancelled = true
				end,
				Completed = newSignal(),
			}
			return tween
		end,
	}

	for _, name in { "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Lighting", "SoundService", "StarterGui", "ServerStorage" } do
		service(name)
	end
	local starterPlayer = service("StarterPlayer")
	local sps = newInstance("StarterPlayerScripts")
	sps._props.Name = "StarterPlayerScripts"
	setParent(sps, starterPlayer)

	-- Terrain
	G.voxels = {} -- [ix][iz] = { surface = number, material = EnumItem }
	behaviors.Terrain = {
		Clear = function()
			G.voxels = {}
		end,
		SetMaterialColor = function(_, mat, color)
			assert(D.typeof(mat) == "EnumItem" and mat._enum == "Material" and D.typeof(color) == "Color3", "SetMaterialColor arguments")
		end,
		WriteVoxels = function(_, region, res, materials, occupancy)
			M.writeVoxels(G, region, res, materials, occupancy)
		end,
		FillBlock = function()
			error("mock: FillBlock not implemented")
		end,
	}

	------------------------------------------------------------------------
	-- require and script environments
	------------------------------------------------------------------------
	local chunks = opts.chunks or {}
	local function makeEnv(ctx, scriptInst, requireFn)
		return {
			game = game,
			workspace = workspace,
			script = scriptInst,
			Instance = InstanceLib,
			Vector3 = Vector3,
			Vector2 = Vector2,
			CFrame = CFrame,
			Color3 = Color3,
			UDim = D.UDim,
			UDim2 = UDim2,
			Enum = Enum,
			PhysicalProperties = D.PhysicalProperties,
			Region3 = D.Region3,
			RaycastParams = D.RaycastParams,
			TweenInfo = D.TweenInfo,
			Font = D.Font,
			NumberSequence = D.NumberSequence,
			NumberSequenceKeypoint = D.NumberSequenceKeypoint,
			ColorSequence = D.ColorSequence,
			ColorSequenceKeypoint = D.ColorSequenceKeypoint,
			NumberRange = D.NumberRange,
			task = task,
			require = requireFn,
			print = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring((select(i, ...)))
				end
				table.insert(G.logs, "[" .. ctx.name .. "] " .. table.concat(parts, " "))
			end,
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring((select(i, ...)))
				end
				table.insert(G.logs, "[" .. ctx.name .. " WARN] " .. table.concat(parts, " "))
			end,
			os = setmetatable({ clock = function()
				return G.time
			end }, { __index = os }),
			vector = D.vector,
			typeof = D.typeof,
			tick = function()
				return G.time
			end,
			Random = nil,
			DateTime = {
				now = function()
					return { UnixTimestampMillis = math.floor((1.7e9 + G.time) * 1000) }
				end,
			},
		}
	end

	local function makeRequire(ctx)
		local cache = {}
		local function req(target)
			if type(target) ~= "table" or getmetatable(target) ~= InstMT or target._class ~= "ModuleScript" then
				error("require expects a ModuleScript", 2)
			end
			if cache[target] ~= nil then
				return cache[target]
			end
			if target._props._moduleValue ~= nil then
				cache[target] = target._props._moduleValue
				return cache[target]
			end
			local chunk = chunks[target._props._source]
			assert(chunk, "no source for module " .. target:GetFullName())
			local value = chunk(makeEnv(ctx, target, req))
			if value == nil then
				error("module " .. target:GetFullName() .. " did not return a value")
			end
			cache[target] = value
			return value
		end
		return req
	end

	G.makeRequire = makeRequire
	G.serverCtx = { name = "server" }
	G.clientCtx = {}

	-- Builds an instance tree for a Rojo-style folder of sources.
	-- spec: { name, class, source?, children = {...} }
	function G.mount(parent, spec)
		local inst = newInstance(spec.class)
		inst._props.Name = spec.name
		inst._props._source = spec.source
		for _, child in spec.children or {} do
			G.mount(inst, child)
		end
		setParent(inst, parent)
		return inst
	end

	function G.runScript(ctx, scriptInst)
		local chunk = chunks[scriptInst._props._source]
		assert(chunk, "no source for script " .. scriptInst:GetFullName())
		local req = ctx.require or makeRequire(ctx)
		ctx.require = req
		spawnIn(ctx, chunk, makeEnv(ctx, scriptInst, req))
	end

	------------------------------------------------------------------------
	-- Players and characters
	------------------------------------------------------------------------
	local function buildCharacter(player)
		local character = newInstance("Model")
		character._props.Name = player._props.Name
		local root = newInstance("Part")
		root._props.Name = "HumanoidRootPart"
		root._props.Size = Vector3.new(2, 2, 1)
		root._props.Transparency = 1
		local spawn = nil
		for _, d in Instance.GetDescendants(workspace) do
			if d._class == "SpawnLocation" then
				spawn = d
				break
			end
		end
		local base = if spawn then partCF(spawn).Position + Vector3.new(0, 4, 0) else Vector3.new(0, 10, 0)
		root._props.CFrame = CFrame.new(base)
		root._props.Anchored = true -- characters stand still in the mock
		setParent(root, character)
		for _, spec in { { "Head", Vector3.new(2, 1, 1), 2.5 }, { "UpperTorso", Vector3.new(2, 1.6, 1), 0.2 }, { "LowerTorso", Vector3.new(2, 0.4, 1), -0.8 } } do
			local p = newInstance("MeshPart")
			p._props.Name = spec[1]
			p._props.Size = spec[2]
			p._props.CFrame = CFrame.new(base + Vector3.new(0, spec[3], 0))
			p._props.Anchored = true
			setParent(p, character)
		end
		local hum = newInstance("Humanoid")
		hum._props.Health = 100
		setParent(hum, character)
		character._props.PrimaryPart = root
		player._props.Character = character
		setParent(character, workspace)
		signalOf(player, "CharacterAdded"):Fire(character)
		return character
	end
	G.buildCharacter = buildCharacter

	function G.addPlayer(name: string, userId: number)
		local p = newInstance("Player")
		p._props.Name = name
		p._props.DisplayName = name
		p._props.UserId = userId
		local gui = newInstance("PlayerGui")
		gui._props.Name = "PlayerGui"
		setParent(gui, p)
		local ps = newInstance("PlayerScripts")
		ps._props.Name = "PlayerScripts"
		setParent(ps, p)
		local pm = newInstance("ModuleScript")
		pm._props.Name = "PlayerModule"
		local controls = { enabled = true }
		function controls:Enable()
			self.enabled = true
		end
		function controls:Disable()
			self.enabled = false
		end
		pm._props._moduleValue = {
			GetControls = function()
				return controls
			end,
		}
		p._props._controls = controls
		setParent(pm, ps)
		setParent(p, players)
		signalOf(players, "PlayerAdded"):Fire(p)
		task.delay(0.2, function()
			buildCharacter(p)
		end)
		return p
	end

	function G.removePlayer(p)
		signalOf(players, "PlayerRemoving"):Fire(p)
		G.clientCtx[p] = nil
		drainDeferred()
		local c = p._props.Character
		if c then
			Instance.Destroy(c)
		end
		Instance.Destroy(p)
	end

	function G.kill(p)
		local c = p._props.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h then
			h.Health = 0
			task.delay(3, function()
				if p._parent then
					if c then
						Instance.Destroy(c)
					end
					buildCharacter(p)
				end
			end)
		end
	end

	-- Starts the client scripts for a player (copies StarterPlayerScripts).
	function G.startClient(p, spec)
		local ctx = { name = "client:" .. p._props.Name, player = p }
		G.clientCtx[p] = ctx
		local ps = p:FindFirstChild("PlayerScripts")
		local inst = G.mount(ps, spec)
		G.runScript(ctx, inst)
		return ctx
	end

	------------------------------------------------------------------------
	-- Frame loop
	------------------------------------------------------------------------
	local FRAME = 1 / 60
	function G.step(frames: number?)
		for _ = 1, frames or 1 do
			G.frame += 1
			G.time += FRAME
			wakeSleepers()
			drainDeferred()
			runService._signals.PreSimulation:_fire(nil, FRAME)
			runService._signals.Stepped:_fire(nil, G.time, FRAME)
			drainDeferred()
			M.physics(G, FRAME)
			runService._signals.PostSimulation:_fire(nil, FRAME)
			runService._signals.Heartbeat:_fire(nil, FRAME)
			drainDeferred()
			runService._signals.RenderStepped:_fire(nil, FRAME)
			for _, b in table.clone(renderBindings) do
				spawnIn(b.ctx, b.fn, FRAME)
			end
			drainDeferred()
			if G.onFrame then
				G.onFrame(G)
			end
		end
	end

	function G.run(seconds: number, until_: (() -> boolean)?)
		local frames = math.floor(seconds * 60 + 0.5)
		for _ = 1, frames do
			G.step(1)
			if until_ and until_() then
				return true
			end
		end
		return false
	end

	-- hook for the physics/raycast module
	G.partRegistry = partRegistry
	G.setPartMovedHook = function(fn)
		onPartMoved = fn
	end
	G.partCF = partCF
	G.isDescendantOf = isDescendantOf
	G.signalOf = signalOf
	G.services = services
	return G
end

----------------------------------------------------------------------------
-- Mass, assemblies
----------------------------------------------------------------------------
local function density(p): number
	local cpp = p._props.CustomPhysicalProperties
	if cpp then
		return cpp.Density
	end
	return 0.7
end

function M.partMass(p): number
	local s = p._props.Size or Vector3.new(4, 1, 2)
	local vol = s.X * s.Y * s.Z
	local shape = p._props.Shape
	if p._class == "WedgePart" then
		vol /= 2
	elseif shape and shape.Name == "Ball" then
		vol = 4 / 3 * math.pi * (math.min(s.X, s.Y, s.Z) / 2) ^ 3
	elseif shape and shape.Name == "Cylinder" then
		vol = math.pi * (math.min(s.Y, s.Z) / 2) ^ 2 * s.X
	end
	return vol * density(p)
end

-- Welded parts of an assembly: WeldConstraints whose Part0 is the root,
-- plus a seated character (SeatWeld on a seat welded to the root).
function M.assemblyParts(root): { any }
	local out = { root }
	local model = root._parent
	if not model then
		return out
	end
	for _, d in model:GetDescendants() do
		if (d._class == "WeldConstraint" or d._class == "Weld") and d._props.Part0 == root and d._props.Part1 then
			table.insert(out, d._props.Part1)
			local seat = d._props.Part1
			if seat._class == "Seat" then
				local sw = seat:FindFirstChild("SeatWeld")
				local occ = seat._props.Occupant
				if sw and occ and occ._parent then
					for _, cp in occ._parent:GetDescendants() do
						if cp._info.chain.BasePart then
							table.insert(out, cp)
						end
					end
				end
			end
		end
	end
	return out
end

function M.rootOf(p)
	-- in this game the only assemblies are karts: the chassis is the root of
	-- everything welded to it (RootPriority 100)
	local model = p._parent
	if model and model._class == "Model" and model._props.PrimaryPart then
		local pp = model._props.PrimaryPart
		if pp._props.RootPriority == 100 then
			return pp
		end
	end
	return p
end

function M.assemblyMass(G, p): number
	local root = M.rootOf(p)
	local total = M.partMass(root)
	for i, part in M.assemblyParts(root) do
		if i > 1 and not part._props.Massless then
			total += M.partMass(part)
		end
	end
	return total
end

----------------------------------------------------------------------------
-- Ray casting
----------------------------------------------------------------------------
local GRID = 32
local function cellKey(cx, cz)
	return cx * 100003 + cz
end

local function aabb(G, p)
	local cf = G.partCF(p)
	local s = p._props.Size or Vector3.new(4, 1, 2)
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(l.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
	local c = cf.Position
	p._props._box = { c.X - ex, c.X + ex, c.Y - ey, c.Y + ey, c.Z - ez, c.Z + ez }
	return c.X - ex, c.X + ex, c.Z - ez, c.Z + ez
end

-- slab test of a ray against a part's world AABB (cached for static parts)
local function rayHitsBox(G, p, o, d, len)
	local b = p._props._box
	if not b or p._props._moved then
		aabb(G, p)
		b = p._props._box
	end
	local tmin, tmax = 0, len
	local oo = { o.X, o.Y, o.Z }
	local dd = { d.X, d.Y, d.Z }
	for a = 1, 3 do
		local lo, hi = b[a * 2 - 1] - 1e-4, b[a * 2] + 1e-4
		if math.abs(dd[a]) < 1e-12 then
			if oo[a] < lo or oo[a] > hi then
				return false
			end
		else
			local t1, t2 = (lo - oo[a]) / dd[a], (hi - oo[a]) / dd[a]
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return false
			end
		end
	end
	return true
end

local function ensureIndex(G)
	if G.rayIndex then
		return G.rayIndex
	end
	local idx = { cells = {}, dynamic = {} }
	for p in G.partRegistry do
		if p._props.Anchored and not p._props._moved then
			p._props._indexed = true
			local x0, x1, z0, z1 = aabb(G, p)
			for cx = math.floor(x0 / GRID), math.floor(x1 / GRID) do
				for cz = math.floor(z0 / GRID), math.floor(z1 / GRID) do
					local k = cellKey(cx, cz)
					local list = idx.cells[k]
					if not list then
						list = {}
						idx.cells[k] = list
					end
					table.insert(list, p)
				end
			end
		else
			idx.dynamic[p] = true
		end
	end
	G.rayIndex = idx
	return idx
end

local function indexPart(G, idx, p)
	p._props._indexed = true
	local x0, x1, z0, z1 = aabb(G, p)
	for cx = math.floor(x0 / GRID), math.floor(x1 / GRID) do
		for cz = math.floor(z0 / GRID), math.floor(z1 / GRID) do
			local k = cellKey(cx, cz)
			local list = idx.cells[k]
			if not list then
				list = {}
				idx.cells[k] = list
			end
			table.insert(list, p)
		end
	end
end

local function installHooks(G)
	if G._hooks then
		return
	end
	G._hooks = true
	G.kartRoots = G.kartRoots or {}
	G.setPartMovedHook(function(p, event)
		if event == "add" and p._props.RootPriority == 100 then
			G.kartRoots[p] = true
		elseif event == "remove" then
			G.kartRoots[p] = nil
		end
		local idx = G.rayIndex
		if not idx then
			return
		end
		if event == "add" and p._props.Anchored and not p._props._moved and not p._props._indexed then
			indexPart(G, idx, p) -- a new static part
		elseif event == "add" and p._props.Anchored and not p._props._moved then
			-- a static part back in the workspace (a circuit swapped in again):
			-- it never left the index (rays skip parts outside the workspace)
		elseif event == nil and not G.partRegistry[p] then
			-- placed or moved outside the workspace (a circuit being built in
			-- ServerStorage): rays can't see it there, so it stays static and is
			-- indexed when it enters the workspace. Only a part already in the
			-- index has a stale cell now and must be checked brute force later.
			if p._props._indexed then
				p._props._moved = true
			end
		elseif event ~= "remove" then
			-- moved (or dynamic from the start): checked brute force from now on
			p._props._moved = true
			idx.dynamic[p] = true
		else
			idx.dynamic[p] = nil
		end
	end)
end
M.installHooks = installHooks

-- Ray against a convex shape in its local space. Returns t, local normal.
local function rayConvex(o, d, planes, tmax)
	local tnear, tfar = 0, tmax
	local nnear = nil
	for _, pl in planes do
		local n, dist = pl[1], pl[2]
		local denom = n.X * d.X + n.Y * d.Y + n.Z * d.Z
		local num = dist - (n.X * o.X + n.Y * o.Y + n.Z * o.Z)
		if math.abs(denom) < 1e-12 then
			if num < 0 then
				return nil
			end
		else
			local t = num / denom
			if denom < 0 then
				if t > tnear then
					tnear, nnear = t, n
				end
			else
				if t < tfar then
					tfar = t
				end
			end
		end
		if tnear > tfar then
			return nil
		end
	end
	if not nnear then
		return nil -- origin inside the shape: Roblox ignores the part
	end
	return tnear, nnear
end

local function shapePlanes(p)
	local s = p._props.Size or Vector3.new(4, 1, 2)
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local planes = {
		{ Vector3.new(1, 0, 0), hx },
		{ Vector3.new(-1, 0, 0), hx },
		{ Vector3.new(0, -1, 0), hy },
		{ Vector3.new(0, 0, 1), hz },
	}
	if p._class == "WedgePart" then
		-- slope from the bottom-front edge (y=-hy, z=-hz) to the top-back edge (y=+hy, z=+hz)
		local n = Vector3.new(0, 2 * hz, -2 * hy).Unit
		table.insert(planes, { n, 0 })
	else
		table.insert(planes, { Vector3.new(0, 1, 0), hy })
		table.insert(planes, { Vector3.new(0, 0, -1), hz })
	end
	return planes
end

local function rayPart(G, p, origin, dir, len)
	local cf = G.partCF(p)
	local inv = cf:Inverse()
	local o = inv * origin
	local d = cf:VectorToObjectSpace(dir)
	local shape = p._props.Shape
	local s = p._props.Size or Vector3.new(4, 1, 2)
	if p._class == "Part" and shape and shape.Name == "Ball" then
		local r = math.min(s.X, s.Y, s.Z) / 2
		local b = o:Dot(d)
		local c = o:Dot(o) - r * r
		local disc = b * b - c
		if disc < 0 or c < 0 then
			return nil
		end
		local t = -b - math.sqrt(disc)
		if t < 0 or t > len then
			return nil
		end
		local hitL = o + d * t
		return t, cf:VectorToWorldSpace(hitL.Unit)
	elseif (p._class == "Part" and shape and shape.Name == "Cylinder") then
		-- axis X; check the side surface and the caps
		local r = math.min(s.Y, s.Z) / 2
		local hx = s.X / 2
		local best, bn = nil, nil
		local a = d.Y * d.Y + d.Z * d.Z
		local b = o.Y * d.Y + o.Z * d.Z
		local c = o.Y * o.Y + o.Z * o.Z - r * r
		if a > 1e-12 then
			local disc = b * b - a * c
			if disc >= 0 then
				local t = (-b - math.sqrt(disc)) / a
				if t >= 0 and t <= len then
					local x = o.X + d.X * t
					if math.abs(x) <= hx then
						best, bn = t, Vector3.new(0, o.Y + d.Y * t, o.Z + d.Z * t).Unit
					end
				end
			end
		end
		for _, sx in { -1, 1 } do
			if math.abs(d.X) > 1e-12 then
				local t = (sx * hx - o.X) / d.X
				if t >= 0 and t <= len and (not best or t < best) then
					local y, z = o.Y + d.Y * t, o.Z + d.Z * t
					if y * y + z * z <= r * r and o.X * sx > hx then
						best, bn = t, Vector3.new(sx, 0, 0)
					end
				end
			end
		end
		if best then
			return best, cf:VectorToWorldSpace(bn)
		end
		return nil
	end
	local t, n = rayConvex(o, d, shapePlanes(p), len)
	if t then
		return t, cf:VectorToWorldSpace(n)
	end
	return nil
end

local function terrainSurface(G, x, z)
	-- bilinear over column centres
	local res = G.voxelRes or 4
	local fx, fz = x / res - 0.5, z / res - 0.5
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = fx - ix, fz - iz
	local function h(i, k)
		local col = G.voxels[i] and G.voxels[i][k]
		return if col then col.surface else nil
	end
	local h00, h10, h01, h11 = h(ix, iz), h(ix + 1, iz), h(ix, iz + 1), h(ix + 1, iz + 1)
	if not (h00 and h10 and h01 and h11) then
		return nil, nil
	end
	local y = h00 * (1 - tx) * (1 - tz) + h10 * tx * (1 - tz) + h01 * (1 - tx) * tz + h11 * tx * tz
	local mi = if tx < 0.5 then ix else ix + 1
	local mk = if tz < 0.5 then iz else iz + 1
	return y, G.voxels[mi][mk].material
end

M.terrainSurface = terrainSurface
local function rayTerrain(G, origin, dir, len)
	local step = 0.5
	local n = math.max(1, math.ceil(len / step))
	local prevT, prevAbove = 0, nil
	for i = 0, n do
		local t = math.min(i * step, len)
		local p = origin + dir * t
		local sy = terrainSurface(G, p.X, p.Z)
		if sy then
			local above = p.Y - sy
			if above <= 0 then
				if i == 0 then
					return nil -- starts inside the ground
				end
				-- bisect between prevT and t
				local lo, hi = prevT, t
				for _ = 1, 20 do
					local mid = (lo + hi) / 2
					local q = origin + dir * mid
					local qy = terrainSurface(G, q.X, q.Z)
					if qy and q.Y - qy <= 0 then
						hi = mid
					else
						lo = mid
					end
				end
				local hit = origin + dir * hi
				local e = 0.5
				local hx1 = terrainSurface(G, hit.X + e, hit.Z) or hit.Y
				local hx0 = terrainSurface(G, hit.X - e, hit.Z) or hit.Y
				local hz1 = terrainSurface(G, hit.X, hit.Z + e) or hit.Y
				local hz0 = terrainSurface(G, hit.X, hit.Z - e) or hit.Y
				local normal = Vector3.new(-(hx1 - hx0) / (2 * e), 1, -(hz1 - hz0) / (2 * e)).Unit
				local _, mat = terrainSurface(G, hit.X, hit.Z)
				return hi, normal, mat
			end
			prevAbove = above
		end
		prevT = t
	end
	local _ = prevAbove
	return nil
end

function M.raycast(G, origin, dir, params)
	assert(isV3(origin) and isV3(dir), "Raycast expects Vector3 origin and direction")
	installHooks(G)
	local len = dir.Magnitude
	if len < 1e-9 then
		return nil
	end
	local d = dir / len
	params = params or D.RaycastParams.new()
	local list = params.FilterDescendantsInstances or {}
	local include = params.FilterType and params.FilterType.Name == "Include"
	if params._cacheList ~= list then
		params._cacheList = list
		params._cache = {}
	end
	local cache = params._cache
	local function allowed(p)
		local c = cache[p]
		if c ~= nil then
			return c
		end
		local inList = false
		for _, f in list do
			if p == f or G.isDescendantOf(p, f) then
				inList = true
				break
			end
		end
		local result = if include then inList else not inList
		cache[p] = result
		return result
	end
	local best, bestN, bestPart, bestMat = len + 1e-9, nil, nil, nil
	local idx = ensureIndex(G)
	local seen = {}
	local function test(p)
		if seen[p] then
			return
		end
		seen[p] = true
		if p._props.CanQuery == false or not G.partRegistry[p] then
			return
		end
		if not rayHitsBox(G, p, origin, d, best) or not allowed(p) then
			return
		end
		local t, n = rayPart(G, p, origin, d, best)
		if t and t < best then
			best, bestN, bestPart, bestMat = t, n, p, p._props.Material
		end
	end
	-- cells along the ray
	local steps = math.max(1, math.ceil(len / (GRID / 2)))
	for i = 0, steps do
		local q = origin + d * (len * i / steps)
		local cell = idx.cells[cellKey(math.floor(q.X / GRID), math.floor(q.Z / GRID))]
		if cell then
			for _, p in cell do
				if not p._props._moved then
					test(p)
				end
			end
		end
	end
	for p in idx.dynamic do
		test(p)
	end
	-- terrain
	local terrainAllowed
	if include then
		terrainAllowed = table.find(list, G.terrain) ~= nil
	else
		terrainAllowed = table.find(list, G.terrain) == nil
	end
	if terrainAllowed and next(G.voxels) then
		local t, n, mat = rayTerrain(G, origin, d, math.min(best, len))
		if t and t < best then
			best, bestN, bestPart, bestMat = t, n, G.terrain, mat
		end
	end
	if not bestPart then
		return nil
	end
	local Enum = G.Enum
	return {
		Position = origin + d * best,
		Normal = bestN,
		Distance = best,
		Instance = bestPart,
		Material = bestMat or Enum.Material.Plastic,
	}
end

----------------------------------------------------------------------------
-- Terrain voxels
----------------------------------------------------------------------------
function M.writeVoxels(G, region, res, materials, occupancy)
	assert(res == 4, "WriteVoxels resolution must be 4")
	local size = region.Size
	local nx, ny, nz = size.X / res, size.Y / res, size.Z / res
	assert(nx == math.floor(nx) and ny == math.floor(ny) and nz == math.floor(nz), "region not aligned to the voxel grid")
	for _, axis in { region.Min.X, region.Min.Y, region.Min.Z } do
		assert(axis % res == 0, "region not aligned to the voxel grid")
	end
	assert(#materials == nx and #occupancy == nx, string.format("WriteVoxels x size mismatch (%d vs %d)", #materials, nx))
	G.voxelRes = res
	local x0, y0, z0 = region.Min.X / res, region.Min.Y, region.Min.Z / res
	for ix = 1, nx do
		assert(#materials[ix] == ny and #occupancy[ix] == ny, "WriteVoxels y size mismatch")
		for iz = 1, nz do
			local surface = nil
			local mat = nil
			for iy = 1, ny do
				local m = materials[ix][iy][iz]
				local o = occupancy[ix][iy][iz]
				assert(m ~= nil and o ~= nil, "WriteVoxels hole in arrays")
				assert(D.typeof(m) == "EnumItem" and m._enum == "Material", "WriteVoxels material must be Enum.Material")
				assert(type(o) == "number" and o >= 0 and o <= 1, "occupancy out of range")
				if m.Name ~= "Air" and m.Name ~= "Water" and o > 0 then
					surface = y0 + (iy - 1) * res + o * res
					mat = m
				end
			end
			local cx = x0 + ix - 1
			local cz = z0 + iz - 1
			G.voxels[cx] = G.voxels[cx] or {}
			G.voxels[cx][cz] = { surface = surface or (y0 - 100), material = mat }
		end
	end
end

----------------------------------------------------------------------------
-- Physics: karts only (roots with a VectorForce)
----------------------------------------------------------------------------
local function rotate(v, axis, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return v * c + axis:Cross(v) * s + axis * (axis:Dot(v) * (1 - c))
end

function M.physics(G, dt)
	installHooks(G)
	G.karts = G.karts or {}
	local sub = 4
	local h = dt / sub
	for p in G.kartRoots do
		if p._props.Anchored or not G.partRegistry[p] then
			continue
		end
		local vf = p:FindFirstChild("Drive")
		local tq = p:FindFirstChild("Spin")
		if not (vf and tq) then
			continue
		end
		local mass = M.assemblyMass(G, p)
		local s = p._props.Size
		local rootMass = M.partMass(p)
		-- inertia of the chassis box (the only massive part when set up right)
		local ix = rootMass * (s.Y * s.Y + s.Z * s.Z) / 12
		local iy = rootMass * (s.X * s.X + s.Z * s.Z) / 12
		local iz = rootMass * (s.X * s.X + s.Y * s.Y) / 12
		local force = vf._props.Force or Vector3.zero
		local torque = tq._props.Torque or Vector3.zero
		local cf = G.partCF(p)
		local pos = cf.Position
		local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
		local vel = p._props._vel or Vector3.zero
		local w = p._props._angVel or Vector3.zero
		for _ = 1, sub do
			vel += (force / mass + Vector3.new(0, -G.workspace._props.Gravity, 0)) * h
			local back = -look
			local wl = Vector3.new(w:Dot(right), w:Dot(up), w:Dot(back))
			local tl = Vector3.new(torque:Dot(right), torque:Dot(up), torque:Dot(back))
			local Iw = Vector3.new(ix * wl.X, iy * wl.Y, iz * wl.Z)
			local gyro = wl:Cross(Iw)
			wl += Vector3.new((tl.X - gyro.X) / ix, (tl.Y - gyro.Y) / iy, (tl.Z - gyro.Z) / iz) * h
			w = right * wl.X + up * wl.Y + back * wl.Z
			pos += vel * h
			local wm = w.Magnitude
			if wm > 1e-9 then
				local axis = w / wm
				right = rotate(right, axis, wm * h)
				up = rotate(up, axis, wm * h)
				look = rotate(look, axis, wm * h)
			end
			look = look.Unit
			right = look:Cross(up).Unit
			up = right:Cross(look)
		end
		-- crude chassis-ground contact so a bad suspension shows up as scraping
		local params = G.groundParams
		if not params then
			params = D.RaycastParams.new()
			params.FilterType = G.Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = G.groundFilter or {}
			G.groundParams = params
		end
		-- collide with the hitbox when the kart has one, else the root part
		local hb = p._parent and p._parent:FindFirstChild("Hitbox")
		local hs, hoff = s, Vector3.zero
		if hb then
			hs = hb._props.Size
			hoff = cf:PointToObjectSpace(G.partCF(hb).Position)
		end
		for _, corner in { Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1) } do
			local cp = pos + right * (corner.X * hs.X / 2 + hoff.X) + up * (corner.Y * hs.Y / 2 + hoff.Y) - look * (corner.Z * hs.Z / 2 + hoff.Z)
			local hit = M.raycast(G, cp + Vector3.new(0, 3, 0), Vector3.new(0, -3.5, 0), params)
			if hit and hit.Position.Y > cp.Y then
				local pen = hit.Position.Y - cp.Y
				pos += Vector3.new(0, pen, 0)
				if vel.Y < 0 then
					vel = Vector3.new(vel.X * 0.98, 0, vel.Z * 0.98)
				end
				G.scrapes = (G.scrapes or 0) + 1
				G.lastScrape = string.format("%s hit=%s corner=%s", hit.Instance:GetFullName(), tostring(hit.Position), tostring(cp))
			end
		end
		p._props._vel = vel
		p._props._angVel = w
		local newCF = CFrame.fromMatrix(pos, right, up, -look)
		-- move the whole assembly
		local delta = newCF * cf:Inverse()
		for _, part in M.assemblyParts(p) do
			part._props.CFrame = delta * G.partCF(part)
		end
		p._props.CFrame = newCF
	end
end

return M
