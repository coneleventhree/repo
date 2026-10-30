--!strict
-- The lobby menu (every public server): RACE (quick race with other
-- players), PRACTICE (pick a track, drive alone), PRIVATE ROOM (make one or
-- join with a code), RECORDS and SETTINGS, over a slow camera fly-by of the
-- circuit behind it. Off to another server, it puts up the loading screen
-- (the same one ReplicatedFirst shows) and hands it to the teleport.
-- A private room's server opens on its waiting room (like a custom-game
-- lobby): the code, twelve player slots (HOST / READY / NOT READY / OPEN;
-- the host can KICK, tap twice), the host's track and length, READY for the
-- guests, START RACE for the host once everyone is ready, and LEAVE.
-- On every other server it adds a LOBBY button (press twice) to go back.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackData = require(Shared:WaitForChild("TrackData"))
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local SettingsMenu = require(script.Parent:WaitForChild("SettingsMenu"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local TrackOutline = require(script.Parent:WaitForChild("TrackOutline"))

local Menu = {}

local player = Players.LocalPlayer
local L = Config.Lobby
local ACCENT = Color3.fromRGB(255, 196, 0)
local PANEL = Color3.fromRGB(14, 15, 20)
local CARD = Color3.fromRGB(30, 32, 40)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 175, 190)
local RED = Color3.fromRGB(235, 70, 60)
local GREEN = Color3.fromRGB(70, 220, 120)
local CHOSEN = Color3.fromRGB(90, 70, 10)
local LENGTHS = { "Short", "Normal", "Long" }

type Screen = "home" | "practice" | "queue" | "room" | "records"

local gui: ScreenGui
local uiScale: UIScale
local requestRemote: RemoteEvent
local screen: Screen = "home"
local panels: { [string]: Frame } = {}
local selected = TrackData.Default
local cards: { [string]: TextButton } = {}
local recordRows: { [string]: Frame } = {}
local errorText: TextLabel
local errorUntil = 0
local queueTitle: TextLabel
local queueElapsed: TextLabel
local queueStatus: TextLabel
local queuedAt: number? = nil
local codeBox: TextBox
local lobbyButton: TextButton
local lobbyArmed = 0
local nowShowing: TextLabel
local loading: ScreenGui? = nil
local loadingSince = 0
local leaving = false
local wasMenu: boolean? = nil
local lastMode: string? = nil

-- the private room's waiting room
type Slot = { frame: Frame, name: TextLabel, status: TextLabel, kick: TextButton, me: UIStroke }
local slots: { Slot } = {}
local slotUser: { [number]: number } = {} -- slot -> UserId
local kickArmed: { [number]: number } = {} -- UserId -> until
local roomCodeL: TextLabel
local playersTitle: TextLabel
local roomTrackThumb: Frame
local roomTrackName: TextLabel
local roomTrackInfo: TextLabel
local roomChange: TextButton
local hostPicks: TextLabel
local roomPicking = false -- the host has the track cards open
local roomCards: { [string]: TextButton } = {}
local roomLengths: { [string]: TextButton } = {}
local roomAction: TextButton
local roomStatus: TextLabel
local drawnTrack = ""

----------------------------------------------------------------------------
-- small UI helpers
----------------------------------------------------------------------------
local function corner(p: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = p
end

local function stroke(p: Instance, color: Color3?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Name = "Ring"
	s.Color = color or WHITE
	s.Thickness = if color then 2 else 1
	s.Transparency = transparency or 0.8
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end

local function label(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, textSize: number, font: Enum.Font?, color: Color3?, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = text
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = font or Enum.Font.GothamBold
	t.TextSize = textSize
	t.TextColor3 = color or WHITE
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local function panel(name: string, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromOffset(w, h)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	f.Visible = false
	corner(f, 14)
	stroke(f)
	f.Parent = gui
	panels[name] = f
	return f
end

-- A big menu button: a title and a line under it.
local function menuButton(parent: Instance, name: string, title: string, sub: string?, size: UDim2, pos: UDim2, primary: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = if primary then ACCENT else CARD
	b.BackgroundTransparency = if primary then 0 else 0.1
	b.BorderSizePixel = 0
	corner(b, 10)
	if not primary then
		stroke(b)
	end
	local fg = if primary then PANEL else WHITE
	local h = size.Y.Offset
	if sub then
		label(b, "Title", title, UDim2.new(1, -36, 0, 26), UDim2.fromOffset(18, math.floor(h / 2) - 24), 24, Enum.Font.GothamBlack, fg)
		label(b, "Sub", sub, UDim2.new(1, -36, 0, 18), UDim2.fromOffset(18, math.floor(h / 2) + 3), 15, Enum.Font.GothamMedium, if primary then Color3.fromRGB(70, 55, 0) else MUTED)
	else
		label(b, "Title", title, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), 18, Enum.Font.GothamBlack, fg, Enum.TextXAlignment.Center)
	end
	b.Parent = parent
	return b
end

local function fmt(t: number?): string
	if not t then
		return "--:--.---"
	end
	local m = math.floor(t / 60)
	return string.format("%d:%06.3f", m, t - m * 60)
end

local function trackIds(): { string }
	local list = {}
	for _, id in TrackData.Order do
		if TrackData.Tracks[id] then
			table.insert(list, id)
		end
	end
	return list
end

local function isLobby(): boolean
	return workspace:GetAttribute("ServerMode") == "lobby"
end

-- a private room between races: its waiting room
local function roomWaiting(): boolean
	return workspace:GetAttribute("ServerMode") == "room" and workspace:GetAttribute("RaceState") == "Lobby"
end

local function showError(message: string, seconds: number?)
	errorText.Text = message
	errorText.Visible = true
	errorUntil = os.clock() + (seconds or 4)
	Sfx.play("Penalty")
end

local function show(s: Screen)
	screen = s
end

----------------------------------------------------------------------------
-- leaving for another server: the loading screen
----------------------------------------------------------------------------
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

local function hideLoading()
	local g = loading
	loading = nil
	if g then
		g:Destroy()
	end
end

local function onTeleport(info: any)
	leaving = true
	queuedAt = nil
	hideLoading()
	local LG = loadingModule()
	if not LG then
		return
	end
	local g = LG.create(LG.describe(info)) :: ScreenGui
	LG.set(g, 0.1)
	g.Parent = player:WaitForChild("PlayerGui")
	loading = g
	loadingSince = os.clock()
	-- it stays up through the teleport; the next server's Loading script
	-- picks it up (GetArrivingTeleportGui)
	pcall(function()
		TeleportService:SetTeleportGui(g :: any)
	end)
end

----------------------------------------------------------------------------
-- build
----------------------------------------------------------------------------
local function buildHome()
	local home = Instance.new("Frame")
	home.Name = "Home"
	home.Size = UDim2.fromOffset(360, 480)
	home.AnchorPoint = Vector2.new(0, 0.5)
	home.Position = UDim2.new(0, 48, 0.5, 0)
	home.BackgroundTransparency = 1
	home.Visible = false
	home.Parent = gui
	panels.Home = home
	local logo = label(home, "Logo", "A1", UDim2.fromOffset(360, 84), UDim2.fromOffset(0, 0), 84, Enum.Font.GothamBlack, ACCENT)
	logo.TextStrokeTransparency = 0.6
	local name = label(home, "Name", "K A R T   R A C I N G", UDim2.fromOffset(360, 28), UDim2.fromOffset(4, 84), 22, Enum.Font.GothamBlack, WHITE)
	name.TextStrokeTransparency = 0.6
	local race = menuButton(home, "Race", "RACE", "Race other players: qualify, then race", UDim2.fromOffset(340, 74), UDim2.fromOffset(0, 136), true)
	local practice = menuButton(home, "Practice", "PRACTICE", "Pick a track, drive on your own", UDim2.fromOffset(340, 66), UDim2.fromOffset(0, 222), false)
	local room = menuButton(home, "Room", "PRIVATE ROOM", "Race your friends with a code", UDim2.fromOffset(340, 66), UDim2.fromOffset(0, 300), false)
	local records = menuButton(home, "Records", "RECORDS", nil, UDim2.fromOffset(164, 46), UDim2.fromOffset(0, 380), false)
	local settings = menuButton(home, "Settings", "SETTINGS", nil, UDim2.fromOffset(164, 46), UDim2.fromOffset(176, 380), false)
	race.Activated:Connect(function()
		if leaving then
			return
		end
		Sfx.play("Click")
		requestRemote:FireServer("Queue", true)
		queuedAt = os.clock()
		show("queue")
	end)
	practice.Activated:Connect(function()
		Sfx.play("Click")
		show("practice")
	end)
	room.Activated:Connect(function()
		Sfx.play("Click")
		show("room")
	end)
	records.Activated:Connect(function()
		Sfx.play("Click")
		show("records")
	end)
	settings.Activated:Connect(function()
		SettingsMenu.toggle()
	end)

	nowShowing = label(gui, "NowShowing", "", UDim2.fromOffset(420, 20), UDim2.new(1, -24, 1, -18), 14, Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Right)
	nowShowing.AnchorPoint = Vector2.new(1, 1)
	nowShowing.TextStrokeTransparency = 0.5
end

-- three cards a row, three rows in view; more scroll
local CARD_W, CARD_H = 238, 100
-- `registry`: where the card is kept by id; `onPick`: what a click does
local function buildCard(parent: Instance, id: string, registry: { [string]: TextButton }, onPick: (string) -> ()): TextButton
	local spec = TrackData.get(id)
	local t = TrackOutline.track(id)
	local card = Instance.new("TextButton")
	card.Name = "Card_" .. id
	card.Text = ""
	card.AutoButtonColor = true
	card.BackgroundColor3 = CARD
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	corner(card, 10)
	local ring = stroke(card, ACCENT, 1)
	ring.Name = "Ring"
	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromOffset(84, 84)
	thumb.Position = UDim2.fromOffset(8, 8)
	thumb.BackgroundTransparency = 1
	thumb.Parent = card
	TrackOutline.draw(thumb, t, 84, 6, math.max(2, t.n // 120), 2)
	-- two lines for the longer names ("LAKESIDE / INTERNATIONAL")
	local nameL = label(card, "Name", string.upper(spec.Name), UDim2.fromOffset(CARD_W - 108, 32), UDim2.fromOffset(100, 7), 13, Enum.Font.GothamBlack, WHITE)
	nameL.TextWrapped = true
	nameL.TextTruncate = Enum.TextTruncate.None
	nameL.TextYAlignment = Enum.TextYAlignment.Top
	local km = t.length * Config.StudMeters / 1000
	label(card, "Info", string.format("%.2f km", km), UDim2.fromOffset(CARD_W - 108, 14), UDim2.fromOffset(100, 41), 12, Enum.Font.GothamMedium, MUTED)
	label(card, "Best", "", UDim2.fromOffset(CARD_W - 108, 16), UDim2.fromOffset(100, 59), 12, Enum.Font.GothamBold, WHITE)
	local recL = label(card, "Record", "", UDim2.fromOffset(CARD_W - 108, 14), UDim2.fromOffset(100, 78), 11, Enum.Font.GothamMedium, MUTED)
	recL.TextTruncate = Enum.TextTruncate.AtEnd
	card.Parent = parent
	card.Activated:Connect(function()
		Sfx.play("Click")
		onPick(id)
	end)
	registry[id] = card
	return card
end

-- a grid of track cards in panel `p` (the practice and room pickers): three
-- a row, three rows in view, the rest a scroll away
local function cardGrid(p: Frame, registry: { [string]: TextButton }, onPick: (string) -> ())
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Cards"
	grid.Size = UDim2.fromOffset(756, 320) -- three cards a row (742) and the scroll bar
	grid.Position = UDim2.fromOffset(24, 60)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = ACCENT
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = p
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	layout.CellPadding = UDim2.fromOffset(14, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, id in trackIds() do
		buildCard(grid, id, registry, onPick).LayoutOrder = i
	end
end

-- best and record lines on the cards; the ring on `chosen`
local function updateCards(registry: { [string]: TextButton }, chosen: string)
	for id, card in registry do
		local ring = card:FindFirstChild("Ring") :: UIStroke
		ring.Transparency = if id == chosen then 0 else 1
		local best = player:GetAttribute("Best_" .. id) :: number?
		local rec = workspace:GetAttribute("Record_" .. id) :: number?
		local by = workspace:GetAttribute("RecordBy_" .. id) :: string?
		local bestL = card:FindFirstChild("Best") :: TextLabel
		local recL = card:FindFirstChild("Record") :: TextLabel
		bestL.Text = if best then "BEST  " .. fmt(best) else "NO TIME YET"
		recL.Text = if rec then string.format("REC  %s  %s", fmt(rec), by or "") else ""
	end
end

local function buildPractice()
	local p = panel("Practice", 790, 460)
	label(p, "Title", "PRACTICE  -  PICK A TRACK", UDim2.fromOffset(600, 30), UDim2.fromOffset(24, 16), 22, Enum.Font.GothamBlack, ACCENT)
	cardGrid(p, cards, function(id)
		selected = id
	end)
	local back = menuButton(p, "Back", "BACK", nil, UDim2.fromOffset(160, 50), UDim2.new(0, 24, 1, -70), false)
	local drive = menuButton(p, "Drive", "DRIVE", nil, UDim2.fromOffset(240, 50), UDim2.new(1, -264, 1, -70), true)
	back.Activated:Connect(function()
		Sfx.play("Click")
		show("home")
	end)
	drive.Activated:Connect(function()
		if leaving then
			return
		end
		Sfx.play("Click")
		requestRemote:FireServer("Practice", selected)
	end)
end

local function buildQueue()
	local p = panel("Queue", 440, 270)
	queueTitle = label(p, "Title", "FINDING A RACE", UDim2.new(1, -40, 0, 30), UDim2.fromOffset(20, 18), 22, Enum.Font.GothamBlack, ACCENT, Enum.TextXAlignment.Center)
	queueElapsed = label(p, "Elapsed", "0:00", UDim2.new(1, -40, 0, 60), UDim2.fromOffset(20, 56), 54, Enum.Font.GothamBlack, WHITE, Enum.TextXAlignment.Center)
	queueStatus = label(p, "Status", "", UDim2.new(1, -40, 0, 40), UDim2.fromOffset(20, 122), 16, Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Center)
	queueStatus.TextWrapped = true
	local cancel = menuButton(p, "Cancel", "CANCEL", nil, UDim2.fromOffset(200, 50), UDim2.new(0.5, -100, 1, -72), false)
	cancel.Activated:Connect(function()
		Sfx.play("Click")
		requestRemote:FireServer("Queue", false)
		queuedAt = nil
		show("home")
	end)
end

local function buildRoom()
	local p = panel("Room", 480, 330)
	label(p, "Title", "PRIVATE ROOM", UDim2.new(1, -48, 0, 30), UDim2.fromOffset(24, 16), 22, Enum.Font.GothamBlack, ACCENT)
	local create = menuButton(p, "Create", "CREATE A ROOM", "You pick the track; friends join with the code", UDim2.fromOffset(432, 72), UDim2.fromOffset(24, 60), true)
	label(p, "Or", "OR JOIN WITH A CODE", UDim2.new(1, -48, 0, 20), UDim2.fromOffset(24, 146), 14, Enum.Font.GothamBold, MUTED)
	codeBox = Instance.new("TextBox")
	codeBox.Name = "Code"
	codeBox.Text = ""
	codeBox.PlaceholderText = string.rep("0", L.RoomDigits)
	codeBox.ClearTextOnFocus = false
	codeBox.Size = UDim2.fromOffset(210, 56)
	codeBox.Position = UDim2.fromOffset(24, 172)
	codeBox.BackgroundColor3 = CARD
	codeBox.TextColor3 = WHITE
	codeBox.PlaceholderColor3 = Color3.fromRGB(90, 94, 106)
	codeBox.Font = Enum.Font.GothamBlack
	codeBox.TextSize = 30
	codeBox.BorderSizePixel = 0
	corner(codeBox, 10)
	stroke(codeBox)
	codeBox.Parent = p
	local join = menuButton(p, "Join", "JOIN", nil, UDim2.fromOffset(210, 56), UDim2.fromOffset(246, 172), false)
	local back = menuButton(p, "Back", "BACK", nil, UDim2.fromOffset(160, 46), UDim2.new(0, 24, 1, -64), false)
	create.Activated:Connect(function()
		if leaving then
			return
		end
		Sfx.play("Click")
		requestRemote:FireServer("CreateRoom")
	end)
	local function doJoin()
		if leaving then
			return
		end
		local code = string.gsub(codeBox.Text, "%D", "")
		if #code ~= L.RoomDigits then
			showError(string.format("Enter the %d-digit room code", L.RoomDigits))
			return
		end
		Sfx.play("Click")
		requestRemote:FireServer("JoinRoom", code)
	end
	join.Activated:Connect(doJoin)
	codeBox.FocusLost:Connect(function(enter)
		if enter then
			doJoin()
		end
	end)
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		-- digits only, and no more than a code has
		local clean = string.sub(string.gsub(codeBox.Text, "%D", ""), 1, L.RoomDigits)
		if clean ~= codeBox.Text then
			codeBox.Text = clean
		end
	end)
	back.Activated:Connect(function()
		Sfx.play("Click")
		show("home")
	end)
end

local function buildRecords()
	local ids = trackIds()
	local p = panel("Records", 640, 120 + #ids * 46 + 70)
	label(p, "Title", "RECORDS", UDim2.new(1, -48, 0, 30), UDim2.fromOffset(24, 16), 22, Enum.Font.GothamBlack, ACCENT)
	label(p, "HeadBest", "YOUR BEST", UDim2.fromOffset(130, 18), UDim2.fromOffset(300, 58), 12, Enum.Font.GothamBold, MUTED)
	label(p, "HeadRecord", "TRACK RECORD", UDim2.fromOffset(180, 18), UDim2.fromOffset(436, 58), 12, Enum.Font.GothamBold, MUTED)
	for i, id in ids do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. id
		row.Size = UDim2.fromOffset(592, 40)
		row.Position = UDim2.fromOffset(24, 80 + (i - 1) * 46)
		row.BackgroundColor3 = CARD
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		corner(row, 8)
		row.Parent = p
		label(row, "Track", string.upper(TrackData.get(id).Name), UDim2.fromOffset(260, 40), UDim2.fromOffset(12, 0), 15, Enum.Font.GothamBlack, WHITE)
		local best = label(row, "Best", "", UDim2.fromOffset(130, 40), UDim2.fromOffset(276, 0), 16, Enum.Font.GothamBold, ACCENT)
		best.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
		local rec = label(row, "Record", "", UDim2.fromOffset(180, 40), UDim2.fromOffset(412, 0), 14, Enum.Font.GothamBold, WHITE)
		rec.TextWrapped = false
		recordRows[id] = row
	end
	local back = menuButton(p, "Back", "BACK", nil, UDim2.fromOffset(160, 46), UDim2.new(0, 24, 1, -62), false)
	back.Activated:Connect(function()
		Sfx.play("Click")
		show("home")
	end)
end

-- The private room's waiting room (790 x 460, like the track cards).
local SLOT_W, SLOT_H = 234, 34
-- the host's track cards for the waiting room: a click picks it (only a note
-- on the server until START) and goes back
local function buildRoomTracks()
	local p = panel("RoomTracks", 790, 460)
	label(p, "Title", "ROOM  -  PICK THE TRACK", UDim2.fromOffset(600, 30), UDim2.fromOffset(24, 16), 22, Enum.Font.GothamBlack, ACCENT)
	cardGrid(p, roomCards, function(id)
		requestRemote:FireServer("Vote", id)
		roomPicking = false
	end)
	local back = menuButton(p, "Back", "BACK", nil, UDim2.fromOffset(160, 50), UDim2.new(0, 24, 1, -70), false)
	back.Activated:Connect(function()
		Sfx.play("Click")
		roomPicking = false
	end)
end

local function buildRoomLobby()
	local p = panel("RoomLobby", 790, 460)
	label(p, "Title", "PRIVATE ROOM", UDim2.fromOffset(400, 30), UDim2.fromOffset(24, 14), 22, Enum.Font.GothamBlack, ACCENT)
	label(p, "Hint", "Friends join from the menu: PRIVATE ROOM, then the code", UDim2.fromOffset(470, 18), UDim2.fromOffset(24, 44), 13, Enum.Font.GothamMedium, MUTED)
	label(p, "CodeTitle", "ROOM CODE", UDim2.fromOffset(200, 16), UDim2.new(1, -224, 0, 12), 12, Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Right)
	roomCodeL = label(p, "Code", "", UDim2.fromOffset(200, 40), UDim2.new(1, -224, 0, 26), 38, Enum.Font.GothamBlack, WHITE, Enum.TextXAlignment.Right)

	-- players: two columns of six
	playersTitle = label(p, "PlayersTitle", "PLAYERS", UDim2.fromOffset(300, 18), UDim2.fromOffset(24, 76), 13, Enum.Font.GothamBold, MUTED)
	local max = Config.Race.MaxRacers
	for i = 1, max do
		local col, row = (i - 1) % 2, (i - 1) // 2
		local f = Instance.new("Frame")
		f.Name = "Slot" .. i
		f.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
		f.Position = UDim2.fromOffset(24 + col * (SLOT_W + 12), 98 + row * (SLOT_H + 6))
		f.BackgroundColor3 = CARD
		f.BorderSizePixel = 0
		corner(f, 8)
		local me = stroke(f, ACCENT, 1)
		me.Name = "Me"
		f.Parent = p
		local nameL = label(f, "PlayerName", "OPEN", UDim2.fromOffset(112, SLOT_H), UDim2.fromOffset(10, 0), 14, Enum.Font.GothamBold, WHITE)
		local status = label(f, "Status", "", UDim2.fromOffset(76, SLOT_H), UDim2.fromOffset(105, 0), 11, Enum.Font.GothamBlack, MUTED, Enum.TextXAlignment.Right)
		local kick = Instance.new("TextButton")
		kick.Name = "Kick"
		kick.Text = "KICK"
		kick.Font = Enum.Font.GothamBlack
		kick.TextSize = 11
		kick.TextColor3 = WHITE
		kick.BackgroundColor3 = Color3.fromRGB(120, 40, 36)
		kick.Size = UDim2.fromOffset(44, 24)
		kick.Position = UDim2.fromOffset(SLOT_W - 49, 5)
		kick.BorderSizePixel = 0
		kick.Visible = false
		corner(kick, 6)
		kick.Parent = f
		kick.Activated:Connect(function()
			local uid = slotUser[i]
			if not uid then
				return
			end
			Sfx.play("Click")
			local armed = kickArmed[uid]
			if armed and os.clock() < armed then
				kickArmed[uid] = nil
				requestRemote:FireServer("Kick", uid)
			else
				kickArmed[uid] = os.clock() + L.KickConfirm
			end
		end)
		slots[i] = { frame = f, name = nameL, status = status, kick = kick, me = me }
	end

	-- the track and length (the host picks)
	label(p, "TrackTitle", "TRACK", UDim2.fromOffset(238, 18), UDim2.fromOffset(528, 76), 13, Enum.Font.GothamBold, MUTED)
	local card = Instance.new("Frame")
	card.Name = "Track"
	card.Size = UDim2.fromOffset(238, 104)
	card.Position = UDim2.fromOffset(528, 98)
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	corner(card, 10)
	card.Parent = p
	roomTrackThumb = Instance.new("Frame")
	roomTrackThumb.Name = "Thumb"
	roomTrackThumb.Size = UDim2.fromOffset(84, 84)
	roomTrackThumb.Position = UDim2.fromOffset(10, 10)
	roomTrackThumb.BackgroundTransparency = 1
	roomTrackThumb.Parent = card
	roomTrackName = label(card, "TrackName", "", UDim2.fromOffset(130, 48), UDim2.fromOffset(102, 10), 13, Enum.Font.GothamBlack, WHITE)
	roomTrackName.TextWrapped = true
	roomTrackName.TextTruncate = Enum.TextTruncate.None
	roomTrackName.TextYAlignment = Enum.TextYAlignment.Top
	roomTrackInfo = label(card, "Info", "", UDim2.fromOffset(130, 16), UDim2.fromOffset(102, 66), 13, Enum.Font.GothamMedium, MUTED)
	roomChange = menuButton(p, "Change", "CHANGE TRACK", nil, UDim2.fromOffset(238, 34), UDim2.fromOffset(528, 208), false)
	hostPicks = label(p, "HostPicks", "THE HOST PICKS THE TRACK", UDim2.fromOffset(238, 34), UDim2.fromOffset(528, 208), 12, Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Center)
	roomChange.Activated:Connect(function()
		Sfx.play("Click")
		roomPicking = true
	end)
	label(p, "LengthTitle", "LENGTH", UDim2.fromOffset(238, 18), UDim2.fromOffset(528, 252), 13, Enum.Font.GothamBold, MUTED)
	for i, len in LENGTHS do
		local b = menuButton(p, "Len_" .. len, string.upper(len), nil, UDim2.fromOffset(74, 34), UDim2.fromOffset(528 + (i - 1) * 82, 274), false)
		-- "NORMAL 3" needs the whole button
		local t = b:FindFirstChild("Title") :: TextLabel
		t.TextSize = 11
		t.Size = UDim2.new(1, -4, 1, 0)
		t.Position = UDim2.fromOffset(2, 0)
		b.Activated:Connect(function()
			Sfx.play("Click")
			requestRemote:FireServer("Length", len)
		end)
		roomLengths[len] = b
	end

	-- leave / status / READY or START RACE
	local leave = menuButton(p, "Leave", "LEAVE", nil, UDim2.fromOffset(160, 50), UDim2.new(0, 24, 1, -70), false)
	leave.Activated:Connect(function()
		if leaving then
			return
		end
		Sfx.play("Click")
		requestRemote:FireServer("ToLobby")
	end)
	roomStatus = label(p, "Status", "", UDim2.fromOffset(310, 50), UDim2.new(0, 196, 1, -70), 13, Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Center)
	roomStatus.TextWrapped = true
	roomAction = menuButton(p, "Action", "READY", nil, UDim2.fromOffset(250, 50), UDim2.new(1, -274, 1, -70), true)
	roomAction.Activated:Connect(function()
		if leaving then
			return
		end
		Sfx.play("Click")
		if workspace:GetAttribute("RoomHost") == player.UserId then
			if roomStatus:GetAttribute("AllReady") then
				requestRemote:FireServer("Start")
			else
				showError("Everyone has to be READY first")
			end
		else
			requestRemote:FireServer("Ready", player:GetAttribute("Ready") ~= true)
		end
	end)
end

local function setButton(b: TextButton, text: string, bg: Color3, fg: Color3)
	b.BackgroundColor3 = bg
	b.BackgroundTransparency = 0
	local t = b:FindFirstChild("Title") :: TextLabel?
	if t then
		t.Text = text
		t.TextColor3 = fg
	end
end

-- the waiting room, every frame it is up
local function updateRoomLobby()
	roomCodeL.Text = (workspace:GetAttribute("RoomCode") :: string?) or ""
	local hostId = workspace:GetAttribute("RoomHost") :: number?
	local amHost = hostId == player.UserId
	-- the host first, then everyone in the order they came
	local list = Players:GetPlayers()
	local ordered: { Player } = {}
	for _, p in list do
		if p.UserId == hostId then
			table.insert(ordered, p)
		end
	end
	for _, p in list do
		if p.UserId ~= hostId then
			table.insert(ordered, p)
		end
	end
	playersTitle.Text = string.format("PLAYERS  %d/%d", #ordered, Config.Race.MaxRacers)
	local waiting = 0
	table.clear(slotUser)
	for i, slot in slots do
		local p = ordered[i]
		if p then
			slotUser[i] = p.UserId
			slot.name.Text = p.DisplayName
			slot.name.TextColor3 = WHITE
			slot.frame.BackgroundTransparency = 0.05
			if p.UserId == hostId then
				slot.status.Text = "HOST"
				slot.status.TextColor3 = ACCENT
			elseif p:GetAttribute("Ready") == true then
				slot.status.Text = "READY"
				slot.status.TextColor3 = GREEN
			else
				slot.status.Text = "NOT READY"
				slot.status.TextColor3 = MUTED
				waiting += 1
			end
			slot.me.Transparency = if p == player then 0.2 else 1
			local canKick = amHost and p ~= player
			slot.kick.Visible = canKick
			local armed = kickArmed[p.UserId]
			local isArmed = armed ~= nil and os.clock() < armed
			slot.kick.Text = if isArmed then "SURE?" else "KICK"
			slot.kick.BackgroundColor3 = if isArmed then RED else Color3.fromRGB(120, 40, 36)
			-- the status moves left of the KICK button; long names are cut short
			local statusX = if canKick then SLOT_W - 49 - 4 - 76 else SLOT_W - 8 - 76
			slot.status.Position = UDim2.fromOffset(statusX, 0)
			slot.name.Size = UDim2.fromOffset(statusX - 14, SLOT_H)
		else
			slot.name.Text = "OPEN"
			slot.name.TextColor3 = Color3.fromRGB(90, 94, 106)
			slot.status.Text = ""
			slot.kick.Visible = false
			slot.me.Transparency = 1
			slot.frame.BackgroundTransparency = 0.6
		end
	end

	-- the track (the host's pick; the circuit itself changes at START)
	local id = (workspace:GetAttribute("RoomTrack") :: string?) or (workspace:GetAttribute("Track") :: string?) or TrackData.Default
	local laps = (workspace:GetAttribute("Laps") :: number?) or 3
	if id ~= drawnTrack then
		drawnTrack = id
		for _, c in roomTrackThumb:GetChildren() do
			c:Destroy()
		end
		local t = TrackOutline.track(id)
		TrackOutline.draw(roomTrackThumb, t, 84, 6, math.max(2, t.n // 120), 2)
		roomTrackName.Text = string.upper(TrackData.get(id).Name)
		roomTrackInfo:SetAttribute("Km", t.length * Config.StudMeters / 1000)
	end
	roomTrackInfo.Text = string.format("%.2f km  -  %d lap%s", (roomTrackInfo:GetAttribute("Km") :: number?) or 0, laps, if laps == 1 then "" else "s")
	roomChange.Visible = amHost
	hostPicks.Visible = not amHost
	if not amHost then
		roomPicking = false
	end
	if roomPicking then
		updateCards(roomCards, id)
	end
	local spec = TrackData.get(id)
	local opts = spec.Lengths or { spec.Laps or 3, spec.Laps or 3, spec.Laps or 3 }
	local chosen = (workspace:GetAttribute("RoomLength") :: string?) or "Normal"
	for i, len in LENGTHS do
		local b = roomLengths[len]
		b.AutoButtonColor = amHost
		setButton(b, string.format("%s %d", string.upper(len), opts[i]), if chosen == len then CHOSEN else CARD, if chosen == len or amHost then WHITE else MUTED)
	end

	-- READY / START RACE
	local allReady = waiting == 0
	roomStatus:SetAttribute("AllReady", allReady)
	if amHost then
		if allReady then
			setButton(roomAction, "START RACE", ACCENT, PANEL)
			roomStatus.Text = if #ordered == 1 then "Share the code, or start on your own" else "Everyone is ready"
		else
			setButton(roomAction, "START RACE", CARD, MUTED)
			roomStatus.Text = string.format("Waiting for %d player%s to get ready", waiting, if waiting == 1 then "" else "s")
		end
	else
		if player:GetAttribute("Ready") == true then
			setButton(roomAction, "NOT READY", CARD, WHITE)
			roomStatus.Text = "You are ready. The host starts the race"
		else
			setButton(roomAction, "READY", GREEN, PANEL)
			roomStatus.Text = "Press READY when you are set"
		end
	end
end

----------------------------------------------------------------------------
-- the fly-by camera behind the menu
----------------------------------------------------------------------------
local flyArc = 0
local flyTrack: TrackMath.Track? = nil
local flyId = ""
local flying = false

local function poseAt(t: TrackMath.Track, arc: number): (Vector3, Vector3, Vector3)
	local f = (arc % t.length) / t.spacing
	local i0 = math.floor(f)
	local a = t.samples[TrackMath.wrap(i0 + 1, t.n)]
	local b = t.samples[TrackMath.wrap(i0 + 2, t.n)]
	local k = f - i0
	local pos = a.pos + (b.pos - a.pos) * k
	local right = a.right + (b.right - a.right) * k
	local up = a.up + (b.up - a.up) * k
	return Vector3.new(pos.x, pos.y, pos.z), Vector3.new(right.x, right.y, right.z), Vector3.new(up.x, up.y, up.z)
end

local function flyby(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not (isLobby() or roomWaiting()) then
		if flying then
			flying = false
			camera.CameraType = Enum.CameraType.Custom
			local character = player.Character
			camera.CameraSubject = character and character:FindFirstChildOfClass("Humanoid")
		end
		return
	end
	local id = (workspace:GetAttribute("Track") :: string?) or TrackData.Default
	if id ~= flyId or not flyTrack then
		flyId = id
		flyTrack = TrackOutline.track(id)
		flyArc = math.random() * (flyTrack :: TrackMath.Track).length
		flying = false
	end
	local t = flyTrack :: TrackMath.Track
	flyArc += L.FlybySpeed * dt
	local pos, right, up = poseAt(t, flyArc)
	local ahead = poseAt(t, flyArc + 60)
	local eye = pos + right * L.FlybySide + up * L.FlybyHeight
	local want = CFrame.lookAt(eye, ahead + up * 2)
	camera.CameraType = Enum.CameraType.Scriptable
	if not flying then
		flying = true
		camera.CFrame = want
	else
		camera.CFrame = camera.CFrame:Lerp(want, 1 - math.exp(-2.5 * dt))
	end
	camera.FieldOfView = 60
end

----------------------------------------------------------------------------
-- per frame
----------------------------------------------------------------------------
local function update(_dt: number)
	local mode = workspace:GetAttribute("ServerMode") :: string?
	local lobby = mode == "lobby"
	local waitingRoom = roomWaiting()
	local menuUp = lobby or waitingRoom
	if mode ~= lastMode then
		lastMode = mode
		if lobby then
			show("home")
		end
		-- Studio switches in place: the new mode is here, the screen can go
		-- (once the new circuit has had a moment to show up)
		local g = loading
		if g then
			task.delay(1.2, function()
				if loading == g then
					hideLoading()
				end
			end)
		end
		leaving = false
	end
	if menuUp ~= wasMenu then
		wasMenu = menuUp
		SettingsMenu.setButtonVisible(not menuUp)
	end
	if loading and os.clock() - loadingSince > 30 then
		-- nothing came of it
		hideLoading()
		leaving = false
	end
	local queued = player:GetAttribute("Queued") == true
	if lobby and queued and screen ~= "queue" and not leaving then
		show("queue")
	end
	for name, f in panels do
		local want: boolean
		if name == "Home" then
			want = lobby and screen == "home"
		elseif name == "RoomLobby" then
			want = waitingRoom and not leaving and not roomPicking
		elseif name == "RoomTracks" then
			want = waitingRoom and not leaving and roomPicking
		else
			want = lobby and string.lower(name) == screen
		end
		f.Visible = want
	end
	nowShowing.Visible = lobby and screen == "home"
	if lobby then
		local name = TrackData.get((workspace:GetAttribute("Track") :: string?) or TrackData.Default).Name
		nowShowing.Text = "NOW SHOWING  -  " .. string.upper(name)
	end
	errorText.Visible = os.clock() < errorUntil
	lobbyButton.Visible = not menuUp and not leaving and mode ~= nil
	if lobbyArmed > 0 and os.clock() > lobbyArmed then
		lobbyArmed = 0
	end
	lobbyButton.Text = if lobbyArmed > 0 then "TAP AGAIN" else "LOBBY"
	lobbyButton.BackgroundColor3 = if lobbyArmed > 0 then RED else Color3.fromRGB(230, 232, 240)
	if waitingRoom then
		updateRoomLobby()
	end
	if not lobby then
		return
	end

	if screen == "practice" then
		updateCards(cards, selected)
	elseif screen == "queue" then
		local since = queuedAt or os.clock()
		local e = math.floor(os.clock() - since)
		queueElapsed.Text = string.format("%d:%02d", e // 60, e % 60)
		local count = (player:GetAttribute("QueueCount") :: number?) or 1
		local go = player:GetAttribute("QueueGo") :: number?
		if leaving then
			queueTitle.Text = "RACE FOUND"
			queueStatus.Text = "Off to the race server..."
		elseif go then
			local left = math.max(0, math.ceil(go - workspace:GetServerTimeNow()))
			queueTitle.Text = "RACE FOUND"
			queueStatus.Text = string.format("%d drivers  -  starting in %d", count, left)
		else
			queueTitle.Text = "FINDING A RACE"
			queueStatus.Text = string.format("Waiting for drivers (%d/%d)", count, L.QueueMin)
		end
		if not queued and not leaving and queuedAt and os.clock() - queuedAt > 3 then
			-- the server dropped us from the queue (or never took us)
			queuedAt = nil
			show("home")
		end
	elseif screen == "records" then
		for id, row in recordRows do
			local best = player:GetAttribute("Best_" .. id) :: number?
			local rec = workspace:GetAttribute("Record_" .. id) :: number?
			local by = workspace:GetAttribute("RecordBy_" .. id) :: string?
			local bestL = row:FindFirstChild("Best") :: TextLabel
			local recL = row:FindFirstChild("Record") :: TextLabel
			bestL.Text = fmt(best)
			recL.Text = if rec then string.format("%s  %s", fmt(rec), by or "") else "--"
		end
	end
end

local function onRaceEvent(kind: string, data: any)
	if kind == "Teleport" then
		onTeleport(data)
	elseif kind == "TeleportFailed" then
		hideLoading()
		leaving = false
		queuedAt = nil
		show("home")
		showError((type(data) == "table" and data.message) or "Couldn't move you. Try again.")
	elseif kind == "MenuError" then
		leaving = false
		showError((type(data) == "table" and data.message) or "Something went wrong")
	end
end

function Menu.init(remotes: Folder)
	requestRemote = remotes:WaitForChild("Request") :: RemoteEvent
	gui = Instance.new("ScreenGui")
	gui.Name = "Menu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	selected = (workspace:GetAttribute("Track") :: string?) or TrackData.Default
	buildHome()
	buildPractice()
	buildQueue()
	buildRoom()
	buildRecords()
	buildRoomLobby()
	buildRoomTracks()

	errorText = label(gui, "Error", "", UDim2.fromOffset(640, 30), UDim2.new(0.5, -320, 1, -70), 18, Enum.Font.GothamBlack, RED, Enum.TextXAlignment.Center)
	errorText.TextStrokeTransparency = 0.4
	errorText.Visible = false

	-- back to the lobby from any other server (press twice)
	lobbyButton = Instance.new("TextButton")
	lobbyButton.Name = "LobbyButton"
	lobbyButton.Text = "LOBBY"
	lobbyButton.Font = Enum.Font.GothamBlack
	lobbyButton.TextScaled = true
	lobbyButton.TextColor3 = PANEL
	lobbyButton.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
	lobbyButton.Size = UDim2.fromOffset(120, 40)
	lobbyButton.AnchorPoint = Vector2.new(0, 1)
	lobbyButton.Position = UDim2.new(0, 506, 1, -16)
	corner(lobbyButton, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 9)
	pad.PaddingBottom = UDim.new(0, 9)
	pad.Parent = lobbyButton
	if UserInputService.TouchEnabled then
		-- top left, under Roblox's bar and above the lap times: well away from
		-- the steering buttons (and no tap on it by accident mid-corner)
		lobbyButton.AnchorPoint = Vector2.zero
		lobbyButton.Size = UDim2.fromOffset(110, 36)
		lobbyButton.Position = UDim2.fromOffset(16, 6)
	end
	lobbyButton.Visible = false
	lobbyButton.Parent = gui
	lobbyButton.Activated:Connect(function()
		Sfx.play("Click")
		if lobbyArmed > 0 then
			lobbyArmed = 0
			requestRemote:FireServer("ToLobby")
		else
			lobbyArmed = os.clock() + L.LobbyConfirm
		end
	end)

	-- The menu has room to grow on phones: fit the biggest screen (track
	-- cards 790 x 460, home 480 high) under the top bar, rather than the
	-- HUD's small-screen step. Big screens keep the HUD's crisp 1x / 2x.
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		local inset = 58
		pcall(function()
			inset = GuiService:GetGuiInset().Y
		end)
		local fit = math.min((vp.X - 24) / 814, (vp.Y - inset - 12) / 480)
		uiScale.Scale = if fit >= 1 then Settings.pixelScale(vp) else math.max(fit, 0.5)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local raceEvent = remotes:WaitForChild("RaceEvent") :: RemoteEvent
	raceEvent.OnClientEvent:Connect(onRaceEvent)
	RunService.RenderStepped:Connect(update)
	RunService:BindToRenderStep("LobbyCamera", Enum.RenderPriority.Camera.Value + 5, flyby)
	-- sent here with a message (the room's host removed us)
	local okData, data = pcall(function()
		return TeleportService:GetLocalPlayerTeleportData()
	end)
	if okData and type(data) == "table" and type((data :: any).notice) == "string" then
		showError((data :: any).notice, 9)
	end
end

-- (tests) what the menu shows
function Menu.screen(): string
	return screen
end

function Menu.isLeaving(): boolean
	return leaving
end

return Menu
