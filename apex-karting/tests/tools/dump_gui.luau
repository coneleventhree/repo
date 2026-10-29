-- Dumps the players' screen GUIs in a few menu / HUD states (for
-- tests/tools/render_gui.py, which draws them as PNGs).
-- Run from the project root (after python3 tests/mock/gen.py):
--   luau tests/tools/dump_gui.luau > gui.txt && python3 tests/tools/render_gui.py gui.txt out/
local Game = require("../lib/game")

local function q(s: string): string
	return '"' .. string.gsub(string.gsub(s, "\\", "\\\\"), '"', '\\"') .. '"'
end
local function json(v: any): string
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" or t == "number" then
		return tostring(v)
	elseif t == "string" then
		return q(v)
	end
	local parts = {}
	if #v > 0 then
		for _, x in v do
			table.insert(parts, json(x))
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	for k, x in v do
		table.insert(parts, q(tostring(k)) .. ":" .. json(x))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function udim2(u: any)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end
local function rgb(c: any)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local function try(fn)
	local ok, v = pcall(fn)
	return if ok then v else nil
end

local GUI = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true }

local function node(inst: any, out: { string }, parent: number, counter: { n: number })
	counter.n += 1
	local id = counter.n
	local cls = inst.ClassName
	local d: { [string]: any } = { id = id, parent = parent, class = cls, name = inst.Name }
	if cls == "ScreenGui" then
		d.enabled = inst.Enabled
		d.order = inst.DisplayOrder
		d.inset = not inst.IgnoreGuiInset
	elseif GUI[cls] then
		d.visible = inst.Visible
		d.size = udim2(inst.Size)
		d.pos = udim2(inst.Position)
		d.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		d.z = inst.ZIndex
		d.order = inst.LayoutOrder
		d.bg = rgb(inst.BackgroundColor3)
		d.bgT = inst.BackgroundTransparency
		d.auto = inst.AutomaticSize.Name
		if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then
			local text = inst.Text
			local color = inst.TextColor3
			if cls == "TextBox" and text == "" then
				text = inst.PlaceholderText
				color = inst.PlaceholderColor3
			end
			d.text = text
			d.textSize = inst.TextSize
			d.textColor = rgb(color)
			d.textT = inst.TextTransparency
			d.xAlign = inst.TextXAlignment.Name
			d.yAlign = inst.TextYAlignment.Name
			d.scaled = inst.TextScaled
			d.wrapped = inst.TextWrapped
			d.font = try(function()
				return inst.Font.Name
			end) or ""
		end
	elseif cls == "UICorner" then
		d.radius = { inst.CornerRadius.Scale, inst.CornerRadius.Offset }
	elseif cls == "UIStroke" then
		d.color = rgb(inst.Color)
		d.thickness = inst.Thickness
		d.t = inst.Transparency
		d.enabled = try(function()
			return inst.Enabled
		end) ~= false
	elseif cls == "UIScale" then
		d.scale = inst.Scale
	elseif cls == "UIPadding" then
		local function u(name)
			local v = try(function()
				return inst[name]
			end)
			return if v then { v.Scale, v.Offset } else { 0, 0 }
		end
		d.pad = { u("PaddingLeft"), u("PaddingRight"), u("PaddingTop"), u("PaddingBottom") }
	elseif cls == "UIListLayout" then
		local pad = try(function()
			return inst.Padding
		end)
		d.padding = if pad then { pad.Scale, pad.Offset } else { 0, 0 }
		local function e(name, default)
			local v = try(function()
				return inst[name]
			end)
			return if v then v.Name else default
		end
		d.dir = e("FillDirection", "Vertical")
		d.hAlign = e("HorizontalAlignment", "Left")
		d.vAlign = e("VerticalAlignment", "Top")
	elseif cls == "UIGridLayout" then
		local cell = try(function()
			return inst.CellSize
		end)
		local cp = try(function()
			return inst.CellPadding
		end)
		d.cell = if cell then udim2(cell) else { 0, 100, 0, 100 }
		d.cellPad = if cp then udim2(cp) else { 0, 5, 0, 5 }
		d.maxCells = try(function()
			return inst.FillDirectionMaxCells
		end) or 0
	else
		return
	end
	table.insert(out, json(d))
	for _, c in inst:GetChildren() do
		node(c, out, id, counter)
	end
end

local function dump(G, player, scene: string)
	G.run(0.3)
	local out = {}
	local vp = G.viewport
	print(string.format("== SCENE %s %d %d", scene, vp.X, vp.Y))
	local counter = { n = 0 }
	for _, sg in player.PlayerGui:GetChildren() do
		if sg.ClassName == "ScreenGui" then
			node(sg, out, 0, counter)
		end
	end
	for _, line in out do
		print(line)
	end
end

local D = require("../mock/datatypes")
local Vector2 = D.Vector2
local DESKTOP = Vector2.new(1280, 720)
local PHONE = Vector2.new(844, 390)

local function boot(opts, phone: boolean)
	local G = Game.boot(opts)
	G.touch = phone
	G.setViewport(if phone then PHONE else DESKTOP)
	return G
end

-- the lobby
for _, phone in { false, true } do
	local tag = if phone then "phone" else "desktop"
	local G = boot({ studio = false }, phone)
	local A = G.addPlayer("Alice", 101)
	local ctx = G.startClient(A, Game.ClientSpec)
	G.run(3)
	local menu = A.PlayerGui.Menu
	dump(G, A, "home_" .. tag)
	menu.Home.Practice.Activated:Fire()
	G.run(0.1)
	menu.Practice.Cards.Card_Hillside.Activated:Fire()
	dump(G, A, "practice_" .. tag)
	menu.Practice.Back.Activated:Fire()
	menu.Home.Room.Activated:Fire()
	G.run(0.1)
	menu.Room.Code.Text = "12"
	menu.Room.Join.Activated:Fire()
	dump(G, A, "room_" .. tag)
	menu.Room.Back.Activated:Fire()
	G.run(4.5) -- the red error line fades before the next screens
	menu.Home.Records.Activated:Fire()
	dump(G, A, "records_" .. tag)
	menu.Records.Back.Activated:Fire()
	menu.Home.Race.Activated:Fire()
	G.run(2)
	dump(G, A, "queue_" .. tag)
	menu.Queue.Cancel.Activated:Fire()
	G.run(1)
	-- the loading screen as it looks when leaving for a practice server
	local LoadingGui = ctx.require(G.first:FindFirstChild("LoadingGui"))
	local lg = LoadingGui.create("Practice  -  Hillside Raceway")
	LoadingGui.set(lg, 0.62)
	lg.Parent = A.PlayerGui
	dump(G, A, "loading_" .. tag)
	lg:Destroy()
end

-- a private room's waiting room, seen by the host and by a guest
for _, phone in { false, true } do
	local tag = if phone then "phone" else "desktop"
	local R = boot({ studio = false, reserved = { mode = "room", code = "4321", host = 101 } }, phone)
	local H = R.addPlayer("Alice", 101)
	local B = R.addPlayer("Bob", 202)
	R.addPlayer("Cara", 303)
	R.addPlayer("Daniel_Ricciardo_Fan", 404)
	R.startClient(H, Game.ClientSpec)
	R.startClient(B, Game.ClientSpec)
	R.run(30, function()
		return #string.split(R.workspace:GetAttribute("Tracks") or "", ",") >= 5
	end)
	R.run(2)
	B.PlayerGui.Menu.RoomLobby.Action.Activated:Fire()
	R.run(0.5)
	dump(R, H, "roomlobby_host_" .. tag)
	dump(R, B, "roomlobby_guest_" .. tag)
	H.PlayerGui.Menu.RoomLobby.Change.Activated:Fire()
	dump(R, H, "roomtracks_" .. tag)
end

-- the HUD's track panel (M) on a practice server, every circuit built
for _, phone in { false, true } do
	local tag = if phone then "phone" else "desktop"
	local P = boot({ studio = false, reserved = { mode = "practice", track = "Lakeside" } }, phone)
	local A = P.addPlayer("Alice", 101)
	P.startClient(A, Game.ClientSpec)
	P.run(60, function()
		return A:GetAttribute("Best_Lakeside") ~= nil
			or #string.split(P.workspace:GetAttribute("Tracks") or "", ",") >= 9
	end)
	P.run(3)
	P.pressKey("M")
	P.run(0.2)
	P.releaseKey("M")
	P.run(0.5)
	dump(P, A, "trackpanel_" .. tag)
end
