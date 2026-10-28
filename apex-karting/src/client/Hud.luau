--!strict
-- Race HUD: position and lap, lap timing with sector splits and a live
-- delta to your best lap, speed and slipstream, minimap, live standings
-- (race order, or best laps in qualifying), start lights (on screen and on
-- the gantry), track-limit warnings, toasts, results, and the track panel
-- (switch track in practice; vote track and race length and press READY
-- before a race; in a private room the host picks both and presses START).
-- Hidden in the lobby (Menu). All text is ASCII so it renders in every font.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local TrackData = require(Shared:WaitForChild("TrackData"))
local KartController = require(script.Parent:WaitForChild("KartController"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local Input = require(script.Parent:WaitForChild("Input"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local TrackOutline = require(script.Parent:WaitForChild("TrackOutline"))

local Hud = {}

local player = Players.LocalPlayer
local ACCENT = Color3.fromRGB(255, 196, 0)
local PANEL = Color3.fromRGB(14, 15, 20)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 175, 190)
local PURPLE = Color3.fromRGB(200, 135, 255)
local GREEN = Color3.fromRGB(70, 220, 120)
local RED = Color3.fromRGB(235, 50, 50)
local ORANGE = Color3.fromRGB(255, 140, 30)
local CARD = Color3.fromRGB(30, 32, 40)
local CHOSEN = Color3.fromRGB(78, 62, 8)
local SECTOR_COLOURS: { [string]: Color3 } = {
	purple = PURPLE,
	green = GREEN,
	yellow = ACCENT,
	invalid = Color3.fromRGB(110, 112, 122),
}
-- Times are drawn in bold Roboto Mono at fixed sizes: every digit has the
-- same width (the clock does not jitter) and the strokes are thick enough
-- to stay sharp over the track. TextScaled made the regular-weight font pick
-- a smaller size whenever a line got longer, and it went thin and faint.
local MONO_BOLD = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local LIGHT = Color3.fromRGB(225, 228, 236)
local LENGTHS = { "Short", "Normal", "Long" }
local MAP_SIZES: { [string]: number } = { Off = 0, Small = 150, Normal = 210, Large = 280 }

local gui: ScreenGui
local track: TrackMath.Track
local trackId = ""
local requestRemote: RemoteEvent

-- timing state
local lapStart: number? = nil
local lastLap: number? = nil
local sessionBest: number? = nil
local lapInvalid = false
local standings: { any } = {}
local standingsMode = "race"
local spectateIndex = 0

-- live delta: the lap time reached at every DELTA_STEP studs of the current
-- lap, and the same for the best clean lap of the session
local DELTA_STEP = 15
local curProfile: { [number]: number } = {}
local bestProfile: { [number]: number }? = nil
local deltaHint: number? = nil

----------------------------------------------------------------------------
-- small UI helpers
----------------------------------------------------------------------------
local function corner(p: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = p
end

local function stroke(p: Instance, color: Color3?, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or WHITE
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.8
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
end

local function textStroke(p: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Transparency = 0.3
	s.Parent = p
end

local function panel(parent: Instance, name: string, size: UDim2, pos: UDim2, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	corner(f)
	stroke(f)
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, str: string, size: UDim2, pos: UDim2, font: Enum.Font?, color: Color3?, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = str
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = font or Enum.Font.GothamBold
	t.TextColor3 = color or WHITE
	t.TextScaled = true
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

-- A label at a fixed text size (no TextScaled). `mono` = bold Roboto Mono.
local function fixed(parent: Instance, name: string, str: string, size: UDim2, pos: UDim2, textSize: number, mono: boolean, color: Color3?, align: Enum.TextXAlignment?): TextLabel
	local t = text(parent, name, str, size, pos, Enum.Font.GothamBold, color, align)
	t.TextScaled = false
	t.TextSize = textSize
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	if mono then
		t.FontFace = MONO_BOLD
	end
	return t
end

-- Elements centred on the screen are placed from the left edge on a whole
-- pixel (AnchorPoint 0.5 on an odd-width screen lands on half a pixel).
type Centred = { obj: GuiObject, width: number, y: UDim }
local centred: { Centred } = {}
local uiScale: UIScale
local function centre(obj: GuiObject)
	obj.AnchorPoint = Vector2.new(0, obj.AnchorPoint.Y)
	table.insert(centred, { obj = obj, width = obj.Size.X.Offset, y = obj.Position.Y })
end
local function placeCentred()
	local vp = workspace.CurrentCamera.ViewportSize
	local s = uiScale.Scale
	for _, c in centred do
		local x = math.floor((vp.X / s - c.width) / 2)
		c.obj.Position = UDim2.new(0, x, c.y.Scale, c.y.Offset)
	end
end

local function bigButton(parent: Instance, name: string, str: string, size: UDim2, pos: UDim2, bg: Color3, padding: number?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = bg
	b.TextColor3 = PANEL
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.Text = str
	corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, padding or 9)
	pad.PaddingBottom = UDim.new(0, padding or 9)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function fmt(t: number?): string
	if not t or t ~= t or t < 0 then
		return "--:--.---"
	end
	local m = math.floor(t / 60)
	local s = t - m * 60
	return string.format("%d:%06.3f", m, s)
end

local function fmtShort(t: number): string
	if t >= 60 then
		return fmt(t)
	end
	return string.format("%.3f", t)
end

local function ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		local d = n % 10
		suffix = if d == 1 then "st" elseif d == 2 then "nd" elseif d == 3 then "rd" else "th"
	end
	return tostring(n) .. suffix
end

local function now(): number
	return workspace:GetServerTimeNow()
end

----------------------------------------------------------------------------
-- widgets (created in Hud.init)
----------------------------------------------------------------------------
local banner: Frame
local bannerText: TextLabel
local posPanel: Frame
local posText: TextLabel
local posOf: TextLabel
local lapText: TextLabel
local timePanel: Frame
local curLapText: TextLabel
local deltaText: TextLabel
local sectorBoxes: { TextLabel } = {}
local lastLapText: TextLabel
local bestLapText: TextLabel
local recordText: TextLabel
local recordHolder: TextLabel
local speedPanel: Frame
local speedText: TextLabel
local unitText: TextLabel
local revBar: Frame
local gearText: TextLabel
local slipText: TextLabel
local warnText: TextLabel
local bigText: TextLabel
local toast: TextLabel
local lightsFrame: Frame
local lightDots: { Frame } = {}
local standingsPanel: Frame
local standingsRows: { Frame } = {}
local mapFrame: Frame
local mapDots: { [Model]: Frame } = {}
local mapScale = 1
local mapMin = Vector2.zero
local mapSize = 210
local resultsPanel: Frame
local resultsList: Frame
local driveButton: TextButton
local trackButton: TextButton
local trackPanel: Frame
local trackTitle: TextLabel
local trackCards: { [string]: TextButton } = {}
local lengthRow: Frame
local lengthButtons: { [string]: TextButton } = {}
local readyButton: TextButton
local trackPanelOpen = false -- practice: opened with M / the button
local trackPanelClosed = false -- intermission: closed with M
local mapName: TextLabel
local spectateBar: Frame
local spectateText: TextLabel
local hintText: TextLabel

local MAP_PAD = 12

local function mapPoint(x: number, z: number): Vector2
	return Vector2.new((x - mapMin.X) * mapScale + MAP_PAD, (z - mapMin.Y) * mapScale + MAP_PAD)
end

-- The sampled track for a circuit id, and outlines (TrackOutline).
local function trackFor(id: string): TrackMath.Track
	return TrackOutline.track(id)
end

local function drawOutline(frame: GuiObject, t: TrackMath.Track, size: number, pad: number, every: number, thick: number): (number, Vector2)
	return TrackOutline.draw(frame, t, size, pad, every, thick)
end

-- the standings sit under the minimap (or in its place when it is off)
local function placeStandings()
	if standingsPanel then
		local top = if mapSize > 0 then 16 + mapSize + 10 else 16
		standingsPanel.Position = UDim2.new(1, -16, 0, top)
		standingsPanel.Size = UDim2.fromOffset(math.max(mapSize, 230), 30)
	end
end

local function drawMinimap()
	for _, c in mapFrame:GetChildren() do
		if c.Name == "Outline" then
			c:Destroy()
		end
	end
	mapSize = MAP_SIZES[Settings.get("Minimap") :: string] or 210
	mapFrame.Visible = mapSize > 0
	placeStandings()
	if mapSize <= 0 then
		return
	end
	mapFrame.Size = UDim2.fromOffset(mapSize, mapSize)
	-- longer circuits get a finer outline step so corners stay round
	local every = if track.n > 600 then 3 else 2
	mapScale, mapMin = drawOutline(mapFrame, track, mapSize, MAP_PAD, every, if mapSize < 180 then 3 else 4)
	mapName.Text = string.upper(TrackData.get(trackId).Name)
end

local function buildMinimap()
	mapFrame = panel(gui, "Minimap", UDim2.fromOffset(mapSize, mapSize), UDim2.new(1, -16, 0, 16), Vector2.new(1, 0))
	mapFrame.ClipsDescendants = true
	mapName = text(mapFrame, "TrackName", "", UDim2.new(1, -16, 0, 14), UDim2.new(0, 8, 1, -18), Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Right)
	mapName.ZIndex = 4
	drawMinimap()
end

local function mapDot(model: Model): Frame
	local existing = mapDots[model]
	if existing then
		return existing
	end
	local mine = model:GetAttribute("Owner") == player.UserId
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Size = UDim2.fromOffset(if mine then 13 else 10, if mine then 13 else 10)
	d.BackgroundColor3 = (model:GetAttribute("Color") :: Color3?) or WHITE
	d.BorderSizePixel = 0
	d.ZIndex = if mine then 6 else 5
	corner(d, 7)
	stroke(d, if mine then WHITE else Color3.new(0, 0, 0), 2, 0)
	d.Parent = mapFrame
	mapDots[model] = d
	return d
end

local function buildStandings()
	standingsPanel = panel(gui, "Standings", UDim2.fromOffset(230, 30), UDim2.new(1, -16, 0, 236), Vector2.new(1, 0))
	standingsPanel.AutomaticSize = Enum.AutomaticSize.Y
	standingsPanel.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = standingsPanel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = standingsPanel
	for i = 1, Config.Race.MaxRacers do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 20)
		row.BackgroundTransparency = 1
		row.Visible = false
		row.Parent = standingsPanel
		text(row, "Pos", tostring(i), UDim2.new(0, 22, 1, 0), UDim2.fromOffset(0, 0), Enum.Font.GothamBlack, ACCENT, Enum.TextXAlignment.Center)
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.Size = UDim2.fromOffset(6, 16)
		chip.Position = UDim2.fromOffset(26, 2)
		chip.BorderSizePixel = 0
		chip.Parent = row
		text(row, "Name", "", UDim2.new(1, -124, 1, -2), UDim2.fromOffset(38, 1), Enum.Font.GothamMedium, WHITE)
		fixed(row, "Gap", "", UDim2.new(0, 82, 1, 0), UDim2.new(1, -82, 0, 0), 14, true, LIGHT, Enum.TextXAlignment.Right)
		standingsRows[i] = row
	end
	placeStandings()
end

local function buildResults()
	-- left of centre, so the podium behind it stays in view
	resultsPanel = panel(gui, "Results", UDim2.fromOffset(460, 80), UDim2.fromOffset(16, 150))
	resultsPanel.AutomaticSize = Enum.AutomaticSize.Y
	resultsPanel.Visible = false
	resultsPanel.BackgroundTransparency = 0.1
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = resultsPanel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = resultsPanel
	local title = text(resultsPanel, "Title", "RACE RESULTS", UDim2.new(1, 0, 0, 34), UDim2.new(), Enum.Font.GothamBlack, ACCENT)
	title.LayoutOrder = 0
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 16)
	header.BackgroundTransparency = 1
	header.Parent = resultsPanel
	text(header, "A", "POS   DRIVER", UDim2.new(0.5, 0, 1, 0), UDim2.new(), Enum.Font.GothamBold, MUTED)
	text(header, "B", "TIME", UDim2.new(0.25, 0, 1, 0), UDim2.fromScale(0.5, 0), Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Right)
	text(header, "C", "BEST LAP", UDim2.new(0.25, 0, 1, 0), UDim2.fromScale(0.75, 0), Enum.Font.GothamBold, MUTED, Enum.TextXAlignment.Right)
	resultsList = Instance.new("Frame")
	resultsList.Name = "List"
	resultsList.LayoutOrder = 2
	resultsList.Size = UDim2.new(1, 0, 0, 0)
	resultsList.AutomaticSize = Enum.AutomaticSize.Y
	resultsList.BackgroundTransparency = 1
	resultsList.Parent = resultsPanel
	local l2 = Instance.new("UIListLayout")
	l2.SortOrder = Enum.SortOrder.LayoutOrder
	l2.Padding = UDim.new(0, 3)
	l2.Parent = resultsList
end

local function showResults(list: { any })
	for _, c in resultsList:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, e in list do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 26)
		row.BackgroundColor3 = if e.userId == player.UserId then Color3.fromRGB(60, 50, 10) else CARD
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		corner(row, 6)
		row.Parent = resultsList
		local chip = Instance.new("Frame")
		chip.Size = UDim2.fromOffset(6, 18)
		chip.Position = UDim2.fromOffset(40, 4)
		chip.BackgroundColor3 = e.color or WHITE
		chip.BorderSizePixel = 0
		chip.Parent = row
		text(row, "Pos", tostring(i), UDim2.fromOffset(32, 20), UDim2.fromOffset(4, 3), Enum.Font.GothamBlack, if i == 1 then ACCENT else WHITE, Enum.TextXAlignment.Center)
		text(row, "Name", string.format("#%d %s", e.number or 0, e.name or "?"), UDim2.new(0.5, -54, 0, 18), UDim2.fromOffset(52, 4), Enum.Font.GothamMedium, WHITE)
		local timeStr = if e.finished then fmt(e.time) else "DNF"
		if e.finished and e.penalty and e.penalty > 0 then
			-- the time already includes it
			timeStr = string.format("%s (+%ds)", fmt(e.time), e.penalty)
		end
		fixed(row, "Time", timeStr, UDim2.new(0.25, -4, 0, 20), UDim2.new(0.5, 0, 0, 3), 15, true, if e.finished then WHITE else RED, Enum.TextXAlignment.Right)
		fixed(row, "Best", fmt(e.best), UDim2.new(0.25, -8, 0, 20), UDim2.new(0.75, 0, 0, 3), 15, true, LIGHT, Enum.TextXAlignment.Right)
	end
	resultsPanel.Visible = true
	task.delay(Config.Race.ResultsTime - 0.3, function()
		resultsPanel.Visible = false
	end)
end

local toastToken = 0
local toastStroke: UIStroke
local toastFade: { Tween } = {}
local function showToast(str: string, color: Color3?, seconds: number?)
	toastToken += 1
	local my = toastToken
	-- a fade still running from the last message would wash this one out
	for _, tw in toastFade do
		tw:Cancel()
	end
	table.clear(toastFade)
	toast.Text = str
	toast.TextColor3 = color or WHITE
	toast.TextTransparency = 0
	toastStroke.Transparency = 0.3
	toast.Visible = true
	task.delay(seconds or 3, function()
		if my == toastToken then
			-- the outline fades with the letters (left alone it lingers as a blur)
			local info = TweenInfo.new(0.6)
			toastFade = {
				TweenService:Create(toast, info, { TextTransparency = 1 }),
				TweenService:Create(toastStroke, info, { Transparency = 1 }),
			}
			for _, tw in toastFade do
				tw:Play()
			end
		end
	end)
end

local bigToken = 0
local function showBig(str: string, color: Color3?, seconds: number?)
	bigToken += 1
	local my = bigToken
	bigText.Text = str
	bigText.TextColor3 = color or WHITE
	bigText.Visible = true
	task.delay(seconds or 1.5, function()
		if my == bigToken then
			bigText.Visible = false
		end
	end)
end

----------------------------------------------------------------------------
-- Sector boxes and the live delta
----------------------------------------------------------------------------
local function clearSectors(from: number)
	for i = from, #sectorBoxes do
		local b = sectorBoxes[i]
		b.Text = string.format("S%d", i)
		b.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
		b.TextColor3 = MUTED
	end
end

local function setSector(index: number, t: number, colour: string)
	local b = sectorBoxes[index]
	if not b then
		return
	end
	if index == 1 then
		clearSectors(2)
	end
	b.Text = fmtShort(t)
	b.BackgroundColor3 = SECTOR_COLOURS[colour] or MUTED
	b.TextColor3 = PANEL
end

local function resetLap()
	lapStart = nil
	lastLap = nil
	lapInvalid = false
	curProfile = {}
	deltaHint = nil
	clearSectors(1)
end

local function resetSession()
	resetLap()
	sessionBest = nil
	bestProfile = nil
end

local function updateDelta(chassis: BasePart?, t: number)
	deltaText.Text = ""
	local start = lapStart
	if not (chassis and start) then
		return
	end
	local elapsed = t - start
	if elapsed < 0 then
		return
	end
	local idx, _, s = TrackMath.nearest(track, (chassis.Position :: any) :: vector, deltaHint, 6, 30)
	deltaHint = idx
	-- just after the line the nearest point can still be the end of the lap
	if elapsed < 4 and s > track.length * 0.5 then
		return
	end
	local k = math.floor(s / DELTA_STEP)
	if curProfile[k] == nil then
		curProfile[k] = elapsed
	end
	local ref = bestProfile
	if not ref or lapInvalid or Settings.get("Delta") == false then
		return
	end
	local a, b = ref[k], ref[k + 1]
	if not a then
		return
	end
	local refT = if b then a + (b - a) * ((s - k * DELTA_STEP) / DELTA_STEP) else a
	local d = elapsed - refT
	deltaText.Text = string.format("%+.2f", d)
	deltaText.TextColor3 = if d <= 0 then GREEN else RED
end

----------------------------------------------------------------------------
-- Track panel: in practice a click changes the track; in the intermission it
-- is a vote for the next race (the server counts them), with the race length
-- and the READY button
----------------------------------------------------------------------------
-- cards sit two to a row (five circuits and counting)
local CARD_W, CARD_H, CARD_GAP = 228, 62, 6
local PANEL_W = CARD_W * 2 + CARD_GAP
local cardGrid: Frame

local function trackIds(): { string }
	local list = {}
	local attr = workspace:GetAttribute("Tracks") :: string?
	for id in string.gmatch(attr or "", "[^,]+") do
		if TrackData.Tracks[id] then
			table.insert(list, id)
		end
	end
	return list
end

local function serverMode(): string
	return (workspace:GetAttribute("ServerMode") :: string?) or "race"
end

local function pickTrack(id: string)
	Sfx.play("Click")
	requestRemote:FireServer("Vote", id)
end

local function lengthsOf(spec: any): { number }
	local laps = spec.Laps or 3
	return spec.Lengths or { laps, laps, laps }
end

local function buildTrackCard(id: string): TextButton
	local spec = TrackData.get(id)
	local t = trackFor(id)
	local card = Instance.new("TextButton")
	card.Name = "Card_" .. id
	card.Text = ""
	card.AutoButtonColor = true
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = CARD
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	corner(card, 8)
	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = ACCENT
	ring.Thickness = 2
	ring.Transparency = 1
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = card
	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromOffset(50, 50)
	thumb.Position = UDim2.fromOffset(6, 6)
	thumb.BackgroundTransparency = 1
	thumb.Parent = card
	drawOutline(thumb, t, 50, 4, math.max(2, t.n // 120), 2)
	local km = t.length * Config.StudMeters / 1000
	local l = lengthsOf(spec)
	fixed(card, "Name", string.upper(spec.Name), UDim2.fromOffset(CARD_W - 104, 18), UDim2.fromOffset(62, 5), 13, false, WHITE).Font = Enum.Font.GothamBlack
	fixed(card, "Blurb", spec.Blurb or "", UDim2.fromOffset(CARD_W - 104, 14), UDim2.fromOffset(62, 24), 11, false, MUTED).Font = Enum.Font.GothamMedium
	fixed(card, "Info", string.format("%.2f km - %d/%d/%d laps", km, l[1], l[2], l[3]), UDim2.fromOffset(CARD_W - 104, 14), UDim2.fromOffset(62, 41), 11, true, MUTED)
	fixed(card, "Key", "", UDim2.fromOffset(14, 14), UDim2.new(1, -40, 0, 4), 11, false, MUTED, Enum.TextXAlignment.Right)
	fixed(card, "Votes", "", UDim2.fromOffset(36, 28), UDim2.new(1, -40, 0, 26), 24, false, ACCENT, Enum.TextXAlignment.Center).Font = Enum.Font.GothamBlack
	fixed(card, "Tag", "", UDim2.fromOffset(36, 14), UDim2.new(1, -40, 0, 4), 11, false, GREEN, Enum.TextXAlignment.Center)
	card.Parent = cardGrid
	card.Activated:Connect(function()
		pickTrack(id)
	end)
	trackCards[id] = card :: any
	return card
end

local function buildTrackPanel()
	trackPanel = panel(gui, "Tracks", UDim2.fromOffset(PANEL_W + 16, 40), UDim2.fromOffset(16, 274))
	trackPanel.AutomaticSize = Enum.AutomaticSize.Y
	trackPanel.Visible = false
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = trackPanel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = trackPanel
	trackTitle = text(trackPanel, "Title", "TRACK", UDim2.fromOffset(PANEL_W, 18), UDim2.new(), Enum.Font.GothamBlack, ACCENT)
	trackTitle.LayoutOrder = 0
	cardGrid = Instance.new("Frame")
	cardGrid.Name = "Cards"
	cardGrid.LayoutOrder = 1
	cardGrid.Size = UDim2.fromOffset(PANEL_W, 0)
	cardGrid.AutomaticSize = Enum.AutomaticSize.Y
	cardGrid.BackgroundTransparency = 1
	cardGrid.Parent = trackPanel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	gridLayout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	gridLayout.FillDirectionMaxCells = 2
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = cardGrid
	-- race length: three buttons with the vote counts
	lengthRow = Instance.new("Frame")
	lengthRow.Name = "Length"
	lengthRow.LayoutOrder = 100
	lengthRow.Size = UDim2.fromOffset(PANEL_W, 34)
	lengthRow.BackgroundTransparency = 1
	lengthRow.Visible = false
	lengthRow.Parent = trackPanel
	local w = math.floor((PANEL_W - 12) / 3)
	for i, len in LENGTHS do
		local b = bigButton(lengthRow, len, string.upper(len), UDim2.fromOffset(w, 34), UDim2.fromOffset((i - 1) * (w + 6), 0), CARD, 9)
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.Activated:Connect(function()
			Sfx.play("Click")
			requestRemote:FireServer("Length", len)
		end)
		lengthButtons[len] = b
	end
	readyButton = bigButton(trackPanel, "Ready", "READY", UDim2.fromOffset(PANEL_W, 42), UDim2.new(), GREEN)
	readyButton.LayoutOrder = 101
	readyButton.Visible = false
	readyButton.Activated:Connect(function()
		Sfx.play("Click")
		requestRemote:FireServer("Ready", player:GetAttribute("Ready") ~= true)
	end)
end

local function updateTrackPanel(state: string?, remaining: number)
	local ids = trackIds()
	local voting = state == "Intermission"
	local practice = state == "Practice"
	local several = #ids > 1
	trackButton.Visible = (several and practice) or voting
	trackButton.Text = if voting then "VOTE  [M]" else "TRACK  [M]"
	local show = (voting and not trackPanelClosed) or (several and practice and trackPanelOpen)
	trackPanel.Visible = show
	if not show then
		return
	end
	if voting then
		local readyCount = (workspace:GetAttribute("ReadyCount") :: number?) or 0
		local count = (workspace:GetAttribute("PlayerCount") :: number?) or 1
		trackTitle.Text = string.format("NEXT RACE  -  %d s  -  %d/%d READY", remaining, readyCount, count)
	else
		trackTitle.Text = "CHANGE TRACK (CLICK OR NUMBER KEY)"
	end
	local myVote = player:GetAttribute("Vote") :: string?
	for i, id in ids do
		local card = trackCards[id] or buildTrackCard(id)
		card.LayoutOrder = i
		local here = id == trackId
		local mine = voting and myVote == id
		card.BackgroundColor3 = if mine then CHOSEN else CARD
		local ring = card:FindFirstChild("Ring") :: UIStroke
		ring.Transparency = if mine or (not voting and here) then 0 else 1
		local votesL = card:FindFirstChild("Votes") :: TextLabel
		votesL.Text = if voting then tostring((workspace:GetAttribute("Votes_" .. id) :: number?) or 0) else ""
		local tag = card:FindFirstChild("Tag") :: TextLabel
		tag.Text = if here then "NOW" else ""
		local key = card:FindFirstChild("Key") :: TextLabel
		key.Text = if UserInputService.KeyboardEnabled and i <= 6 then tostring(i) else ""
	end
	for id, card in trackCards do
		-- with one circuit there is nothing to pick, only the length and READY
		card.Visible = several and table.find(ids, id) ~= nil
	end
	lengthRow.Visible = voting
	readyButton.Visible = voting
	if voting then
		local myLen = player:GetAttribute("LengthVote") :: string?
		local laps = lengthsOf(TrackData.get(myVote or trackId))
		for i, len in LENGTHS do
			local b = lengthButtons[len]
			local n = (workspace:GetAttribute("LenVotes_" .. len) :: number?) or 0
			b.Text = string.format("%s %d  (%d)", string.upper(len), laps[i], n)
			b.BackgroundColor3 = if myLen == len then CHOSEN else CARD
		end
		local isReady = player:GetAttribute("Ready") == true
		readyButton.Text = if isReady then "READY!  (CLICK TO UNDO)" else "READY"
		readyButton.BackgroundColor3 = if isReady then ACCENT else GREEN
	end
end

local function onTracksKey()
	local state = workspace:GetAttribute("RaceState")
	if state == "Intermission" then
		trackPanelClosed = not trackPanelClosed
	elseif state == "Practice" then
		trackPanelOpen = not trackPanelOpen
	end
	Sfx.play("Click")
end

local function onTrackNumber(n: number)
	if not trackPanel.Visible then
		return
	end
	local id = trackIds()[n]
	if id then
		pickTrack(id)
	end
end

-- gamepad: B steps to the next track (practice: switches; intermission: votes)
local function onTrackNext()
	local state = workspace:GetAttribute("RaceState")
	if state ~= "Practice" and state ~= "Intermission" then
		return
	end
	local ids = trackIds()
	if #ids < 2 then
		return
	end
	local from = if state == "Intermission" then (player:GetAttribute("Vote") :: string?) or trackId else trackId
	local i = table.find(ids, from) or 0
	if state == "Practice" then
		trackPanelOpen = true
	else
		trackPanelClosed = false
	end
	pickTrack(ids[i % #ids + 1])
end

----------------------------------------------------------------------------
-- Gantry lights in the world
----------------------------------------------------------------------------
local gantryLights: { BasePart } = {}
local function findGantry()
	local circuit = workspace:FindFirstChild("Circuit")
	local trk = circuit and circuit:FindFirstChild("Track")
	local gantry = trk and trk:FindFirstChild("Gantry")
	local lights = gantry and gantry:FindFirstChild("Lights")
	if lights then
		gantryLights = {}
		for _, l in lights:GetChildren() do
			if l:IsA("BasePart") then
				local idx = l:GetAttribute("Index") :: number?
				if idx then
					gantryLights[idx] = l
				end
			end
		end
	end
end

local function setLights(count: number)
	for i = 1, 5 do
		local on = i <= count
		local dot = lightDots[i]
		if dot then
			dot.BackgroundColor3 = if on then RED else Color3.fromRGB(40, 12, 12)
		end
		local l = gantryLights[i]
		if l then
			l.Color = if on then Color3.fromRGB(255, 40, 30) else Color3.fromRGB(40, 8, 8)
			l.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

----------------------------------------------------------------------------
-- per-frame update
----------------------------------------------------------------------------
local function bannerMessage(state: string?, t: number, remaining: number, inRace: boolean, laps: number): string
	local mode = serverMode()
	if state == "Practice" then
		if mode == "practice" then
			return "PRACTICE  -  " .. string.upper((workspace:GetAttribute("TrackName") :: string?) or "")
		end
		local count = (workspace:GetAttribute("PlayerCount") :: number?) or 1
		local need = (workspace:GetAttribute("MinPlayers") :: number?) or 2
		return string.format("WAITING FOR DRIVERS (%d/%d)  -  PRACTISE MEANWHILE", count, need)
	elseif state == "Intermission" then
		local readyCount = (workspace:GetAttribute("ReadyCount") :: number?) or 0
		local count = (workspace:GetAttribute("PlayerCount") :: number?) or 1
		return string.format("QUALIFYING IN %d  -  VOTE, THEN PRESS READY (%d/%d)", remaining, readyCount, count)
	elseif state == "Qualifying" then
		if workspace:GetAttribute("QualiClosing") then
			return "CHEQUERED FLAG  -  FINISH YOUR LAP"
		end
		local clock = string.format("%d:%02d", remaining // 60, remaining % 60)
		if player:GetAttribute("QualiDone") then
			return "QUALIFYING DONE  -  WAITING FOR THE OTHERS  " .. clock
		elseif not lapStart then
			return "QUALIFYING  -  ONE LAP  -  THE CLOCK STARTS AT THE LINE  " .. clock
		end
		return "QUALIFYING  -  ONE TIMED LAP  -  GHOSTS ON  " .. clock
	elseif state == "Grid" then
		return if inRace then string.format("GET READY  -  %d LAP%s", laps, if laps == 1 then "" else "S") else "RACE STARTING - SPECTATING"
	elseif state == "Racing" then
		local deadline = workspace:GetAttribute("FinishDeadline") :: number?
		if not inRace then
			return "RACE IN PROGRESS - SPECTATING (Q / E)"
		elseif deadline and deadline > t then
			return string.format("WINNER IS IN!  %d s LEFT TO FINISH", math.ceil(deadline - t))
		end
	elseif state == "Results" then
		return (if mode == "room" then "PODIUM  -  BACK TO THE ROOM IN " else "PODIUM  -  NEXT ROUND IN ") .. remaining
	end
	return ""
end

local wasLightsCount = -1
local function update(_dt: number)
	local t = now()
	local state = workspace:GetAttribute("RaceState") :: string?
	local stateEnd = (workspace:GetAttribute("StateEnd") :: number?) or 0
	local laps = (workspace:GetAttribute("Laps") :: number?) or TrackData.get(trackId).Laps
	local inRace = player:GetAttribute("InRace") == true
	local driving = KartController.isDriving()
	local remaining = math.max(0, math.ceil(stateEnd - t))

	-- the lobby menu and a private room's waiting room cover the screen
	gui.Enabled = serverMode() ~= "lobby" and not (serverMode() == "room" and state == "Lobby")
	local msg = bannerMessage(state, t, remaining, inRace, laps)
	bannerText.Text = msg
	banner.Visible = msg ~= ""

	-- position and lap (race), or position by best lap (qualifying)
	local qualifying = state == "Qualifying"
	local racing = state == "Racing" and inRace
	posPanel.Visible = inRace and (racing or state == "Grid" or qualifying)
	if posPanel.Visible then
		local pos = (player:GetAttribute("Position") :: number?) or (player:GetAttribute("GridSlot") :: number?) or 1
		local field = math.max(#standings, 1)
		posText.Text = "P" .. pos
		posOf.Text = "/" .. field
		if qualifying then
			lapText.Text = "QUALIFYING"
		else
			local lap = (player:GetAttribute("Lap") :: number?) or 1
			local pen = (player:GetAttribute("Penalty") :: number?) or 0
			local base = if player:GetAttribute("Finished") then "FINISHED" else string.format("LAP %d/%d", lap, laps)
			lapText.Text = if pen > 0 then string.format("%s   +%ds", base, pen) else base
		end
	end

	-- timing
	local chassis = KartController.chassis()
	timePanel.Visible = driving or racing
	if timePanel.Visible then
		local cur = if lapStart and not player:GetAttribute("Finished") then t - lapStart else nil
		curLapText.Text = fmt(cur)
		curLapText.TextColor3 = if lapInvalid then RED else WHITE
		lastLapText.Text = fmt(lastLap)
		bestLapText.Text = fmt(sessionBest)
		local rec = workspace:GetAttribute("TrackRecord") :: number?
		local holder = workspace:GetAttribute("TrackRecordHolder") :: string?
		recordText.Text = fmt(rec)
		recordHolder.Text = if rec then holder or "" else ""
		updateDelta(if driving and not player:GetAttribute("Finished") then chassis else nil, t)
		if lapInvalid then
			deltaText.Text = "DELETED"
			deltaText.TextColor3 = RED
		end
	end

	-- speed and slipstream
	speedPanel.Visible = driving and chassis ~= nil
	if speedPanel.Visible and chassis then
		local tele = KartController.telemetry()
		local v = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		local kmh = math.abs(v) * Config.KmhPerStudPerSecond
		local mph = Settings.get("Units") == "MPH"
		speedText.Text = string.format("%d", math.floor((if mph then kmh * 0.621371 else kmh) + 0.5))
		unitText.Text = if mph then "MPH" else "KM/H"
		local revs = math.clamp(math.abs(v) / Config.Kart.TopSpeed, 0, 1)
		if tele then
			for _, w in tele.wheels do
				if w.spinning then
					revs = math.min(revs + 0.25, 1)
					break
				end
			end
		end
		revBar.Size = UDim2.new(revs, 0, 1, 0)
		revBar.BackgroundColor3 = if revs > 0.92 then RED elseif revs > 0.75 then ACCENT else GREEN
		gearText.Text = if tele and tele.reverse then "R" else "D"
		slipText.Visible = tele ~= nil and tele.draft > 0.25
	end

	-- warnings
	local warn = ""
	if driving and state ~= "Grid" and state ~= "Results" then
		if player:GetAttribute("OffCourse") then
			warn = "OFF TRACK  -  PRESS R TO RETURN"
		elseif player:GetAttribute("WrongWay") then
			warn = "WRONG WAY"
		end
	end
	warnText.Text = warn
	warnText.Visible = warn ~= ""

	-- start lights, with a beep for each one
	local lightsStart = workspace:GetAttribute("LightsStart") :: number?
	local count = 0
	lightsFrame.Visible = false
	if state == "Grid" and lightsStart then
		lightsFrame.Visible = true
		count = math.clamp(math.floor(t - lightsStart) + 1, 0, 5)
	end
	if count ~= wasLightsCount then
		if count > wasLightsCount and count > 0 then
			Sfx.play("Beep")
		end
		wasLightsCount = count
		setLights(count)
	end

	-- minimap dots
	local karts = workspace:FindFirstChild("Karts")
	if karts and mapSize > 0 then
		for _, m in karts:GetChildren() do
			if m:IsA("Model") and m.PrimaryPart then
				local d = mapDot(m)
				local p = mapPoint(m.PrimaryPart.Position.X, m.PrimaryPart.Position.Z)
				d.Position = UDim2.fromOffset(p.X, p.Y)
			end
		end
	end
	for m, d in mapDots do
		if not m.Parent then
			d:Destroy()
			mapDots[m] = nil
		end
	end

	-- drive / walk button (practice only)
	local practicing = state == "Practice" or state == "Intermission"
	driveButton.Visible = practicing and not UserInputService.GamepadEnabled
	driveButton.Text = if KartController.kart() then "WALK  [K]" else "DRIVE  [K]"
	updateTrackPanel(state, remaining)
	spectateBar.Visible = state == "Racing" and not inRace and #standings > 0
	hintText.Visible = driving and not UserInputService.TouchEnabled
	standingsPanel.Visible = #standings > 0 and (state == "Racing" or qualifying)
end

local function updateStandings(list: { any }, mode: string)
	standings = list
	standingsMode = mode
	for i, row in standingsRows do
		local e = list[i]
		row.Visible = e ~= nil
		if e then
			local chip = row:FindFirstChild("Chip") :: Frame
			local nameL = row:FindFirstChild("Name") :: TextLabel
			local gapL = row:FindFirstChild("Gap") :: TextLabel
			chip.BackgroundColor3 = e.color or WHITE
			nameL.Text = string.format("#%d %s", e.number or 0, e.name or "?")
			nameL.TextColor3 = if e.userId == player.UserId then ACCENT else WHITE
			local gap = ""
			if mode == "quali" then
				if not e.best then
					gap = "NO TIME"
				elseif i == 1 then
					gap = fmt(e.best)
				else
					gap = string.format("+%.3f", e.gap or 0)
				end
			elseif e.finished then
				gap = fmt(e.time)
			elseif e.dnf then
				gap = "DNF"
			elseif i == 1 then
				gap = "LAP " .. tostring(e.lap)
			elseif e.gap then
				-- studs to seconds at a typical race pace (about 70 studs/s)
				gap = string.format("+%.1fs", e.gap / 70)
			end
			if mode ~= "quali" and not e.finished and e.penalty and e.penalty > 0 then
				gap ..= string.format(" P%d", e.penalty)
			end
			gapL.Text = gap
		end
	end
end

local function spectateStep(dir: number)
	if #standings == 0 or standingsMode ~= "race" then
		return
	end
	spectateIndex = (spectateIndex + dir - 1) % #standings + 1
	local e = standings[spectateIndex]
	local karts = workspace:FindFirstChild("Karts")
	local model = karts and karts:FindFirstChild("Kart_" .. tostring(e.userId))
	local chassis = model and (model :: Model).PrimaryPart
	ChaseCamera.spectate(chassis)
	spectateText.Text = string.format("WATCHING  #%d %s", e.number or 0, e.name or "?")
end

----------------------------------------------------------------------------
-- messages from the server
----------------------------------------------------------------------------
local function onLap(data: any)
	lastLap = data.time
	local clean = data.time ~= nil and not data.invalid
	if clean and (not sessionBest or data.time <= sessionBest) then
		sessionBest = data.time
		bestProfile = curProfile
	end
	-- a personal best or the fastest lap of the session gets its own chime
	if not ((data.pb or data.colour == "purple") and not data.invalid and Sfx.play("Best")) then
		Sfx.play("Lap")
	end
	local label = if data.final then "FINAL LAP" else string.format("LAP %d", data.lap or 0)
	if data.invalid then
		showToast(string.format("%s   %s   DELETED - TRACK LIMITS", label, fmt(data.time)), RED, 3.5)
	elseif data.time then
		local purple = data.colour == "purple"
		local tag = if purple then "   FASTEST" elseif data.pb then "   PERSONAL BEST" else ""
		showToast(string.format("%s   %s%s", label, fmt(data.time), tag), if purple or data.pb then PURPLE else WHITE, 3.5)
	end
end

local function onTrackLimits(data: any)
	local punished = data.deleted or (data.added or 0) > 0
	if not Sfx.play(if punished then "Penalty" else "Warning") then
		Sfx.play("Beep")
	end
	if data.deleted then
		lapInvalid = true
		showToast("TRACK LIMITS  -  LAP DELETED", RED, 3)
	elseif (data.added or 0) > 0 then
		showToast(string.format("TRACK LIMITS  -  +%d s PENALTY  (TOTAL +%d s)", data.added, data.penalty or data.added), RED, 3.5)
	else
		showToast(string.format("TRACK LIMITS  -  WARNING %d/%d", data.warnings or 1, data.max or 3), ORANGE, 3)
	end
end

local function onRaceEvent(kind: string, data: any)
	if kind == "LapStart" then
		lapStart = data.time
		lapInvalid = false
		curProfile = {}
		deltaHint = nil
	elseif kind == "Sector" then
		setSector(data.index, data.time, data.colour)
	elseif kind == "Lap" then
		onLap(data)
	elseif kind == "TrackLimits" then
		onTrackLimits(data)
	elseif kind == "Qualifying" then
		Sfx.play("Flag")
		resetSession()
		showBig("QUALIFYING", ACCENT, 2)
		showToast("ONE TIMED LAP  -  GHOSTS ON  -  THE CLOCK STARTS AT THE LINE", WHITE, 4)
	elseif kind == "Chequered" then
		Sfx.play("Flag")
		showToast("CHEQUERED FLAG  -  FINISH YOUR LAP", WHITE, 3)
	elseif kind == "QualiDone" then
		if data.best then
			local place = if data.place then string.format("  -  P%d SO FAR", data.place) else ""
			showToast(string.format("QUALIFYING LAP  %s%s", fmt(data.best), place), ACCENT, 4)
		else
			showToast("NO TIME  -  YOU START AT THE BACK", RED, 4)
		end
	elseif kind == "QualiResult" then
		local pole = data.list and data.list[1]
		if pole and pole.best then
			showBig("POLE: " .. string.upper(pole.name or "?"), PURPLE, 2.5)
			showToast(string.format("POLE POSITION  %s  %s", pole.name or "?", fmt(pole.best)), PURPLE, 4)
		end
		standings = {}
		resetSession()
	elseif kind == "AllReady" then
		showToast("EVERYONE IS READY  -  STARTING", GREEN, 2.5)
	elseif kind == "Go" then
		setLights(0)
		wasLightsCount = 0
		Sfx.play("Go")
		showBig("GO!", GREEN, 1.2)
		resetSession()
	elseif kind == "Finish" then
		if data.userId == player.UserId then
			Sfx.play("Finish")
			showBig(string.format("FINISHED %s", ordinal(data.position)), if data.position == 1 then ACCENT else WHITE, 4)
		elseif data.position == 1 then
			showToast(string.format("%s WINS!  %s", data.name, fmt(data.time)), ACCENT, 4)
		end
	elseif kind == "Results" then
		Sfx.play("Podium")
		standingsPanel.Visible = false
		standings = {}
		showResults(data.list or {})
		lapStart = nil
	elseif kind == "Standings" then
		updateStandings(data.list or {}, data.mode or "race")
	elseif kind == "Record" then
		-- your own record lap already chimed as a personal best
		if data.name ~= player.DisplayName then
			Sfx.play("Best")
		end
		showToast(string.format("NEW TRACK RECORD  %s  %s", data.name, fmt(data.time)), PURPLE, 5)
	elseif kind == "Reset" then
		KartController.onTeleported()
	elseif kind == "Track" then
		resetSession()
		trackPanelOpen = false
		showToast(string.format("TRACK: %s  -  %d LAPS", string.upper(data.name or "?"), data.laps or 3), ACCENT, 4)
	end
end

-- the circuit in use changed (or the HUD starts): redraw what depends on it
local function onTrackChanged()
	local id = (workspace:GetAttribute("Track") :: string?) or TrackData.Default
	if id == trackId then
		return
	end
	trackId = id
	track = trackFor(id)
	deltaHint = nil
	drawMinimap()
	task.defer(findGantry)
end

----------------------------------------------------------------------------
-- build
----------------------------------------------------------------------------
local function buildTiming()
	timePanel = panel(gui, "Timing", UDim2.fromOffset(292, 150), UDim2.fromOffset(16, 112))
	timePanel.BackgroundTransparency = 0.12
	local function caption(name: string, str: string, y: number)
		fixed(timePanel, name, str, UDim2.fromOffset(40, 16), UDim2.fromOffset(12, y), 12, false, MUTED)
	end
	-- current lap (big) and the delta to the best lap
	caption("LapLabel", "LAP", 13)
	curLapText = fixed(timePanel, "Cur", "", UDim2.fromOffset(136, 30), UDim2.fromOffset(52, 6), 26, true, WHITE)
	deltaText = fixed(timePanel, "Delta", "", UDim2.fromOffset(96, 30), UDim2.fromOffset(184, 6), 20, true, GREEN, Enum.TextXAlignment.Right)
	-- sector boxes
	local boxW = math.floor((292 - 24 - 8) / 3)
	for i = 1, 3 do
		local b = fixed(timePanel, "S" .. i, "S" .. i, UDim2.fromOffset(boxW, 22), UDim2.fromOffset(12 + (i - 1) * (boxW + 4), 42), 15, true, MUTED, Enum.TextXAlignment.Center)
		b.BackgroundTransparency = 0
		b.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
		corner(b, 4)
		sectorBoxes[i] = b
	end
	-- last, best and the track record
	caption("LastLabel", "LAST", 75)
	lastLapText = fixed(timePanel, "Last", "", UDim2.fromOffset(120, 22), UDim2.fromOffset(52, 72), 18, true, LIGHT)
	caption("BestLabel", "BEST", 99)
	bestLapText = fixed(timePanel, "Best", "", UDim2.fromOffset(120, 22), UDim2.fromOffset(52, 96), 18, true, PURPLE)
	caption("RecLabel", "REC", 123)
	recordText = fixed(timePanel, "Rec", "", UDim2.fromOffset(96, 20), UDim2.fromOffset(52, 121), 15, true, ACCENT)
	recordHolder = fixed(timePanel, "RecHolder", "", UDim2.fromOffset(130, 20), UDim2.fromOffset(150, 121), 13, false, MUTED)
end

local function buildSpeed()
	-- bottom right, or bottom centre on touch screens where the buttons sit
	local touchScreen = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	speedPanel = panel(gui, "Speed", UDim2.fromOffset(190, 92), if touchScreen then UDim2.new(0.5, 0, 1, -16) else UDim2.new(1, -16, 1, -16), if touchScreen then Vector2.new(0.5, 1) else Vector2.new(1, 1))
	speedText = text(speedPanel, "Value", "0", UDim2.fromOffset(120, 54), UDim2.fromOffset(12, 6), Enum.Font.GothamBlack, WHITE, Enum.TextXAlignment.Right)
	unitText = text(speedPanel, "Unit", "KM/H", UDim2.fromOffset(46, 18), UDim2.fromOffset(136, 34), Enum.Font.GothamBold, MUTED)
	gearText = text(speedPanel, "Gear", "D", UDim2.fromOffset(30, 26), UDim2.fromOffset(142, 6), Enum.Font.GothamBlack, ACCENT, Enum.TextXAlignment.Center)
	local revBack = Instance.new("Frame")
	revBack.Size = UDim2.new(1, -24, 0, 10)
	revBack.Position = UDim2.new(0, 12, 1, -20)
	revBack.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
	revBack.BorderSizePixel = 0
	corner(revBack, 4)
	revBack.Parent = speedPanel
	revBar = Instance.new("Frame")
	revBar.Size = UDim2.fromScale(0, 1)
	revBar.BackgroundColor3 = GREEN
	revBar.BorderSizePixel = 0
	corner(revBar, 4)
	revBar.Parent = revBack
	slipText = text(speedPanel, "Slipstream", "SLIPSTREAM", UDim2.fromOffset(160, 20), UDim2.new(0.5, -80, 0, -26), Enum.Font.GothamBlack, Color3.fromRGB(120, 200, 255), Enum.TextXAlignment.Center)
	slipText.Visible = false
	textStroke(slipText, 2)
end

function Hud.init(remotes: Folder)
	requestRemote = remotes:WaitForChild("Request") :: RemoteEvent
	trackId = (workspace:GetAttribute("Track") :: string?) or TrackData.Default
	track = trackFor(trackId)
	gui = Instance.new("ScreenGui")
	gui.Name = "RaceHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- banner
	banner = panel(gui, "Banner", UDim2.fromOffset(660, 40), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0))
	bannerText = text(banner, "Text", "", UDim2.new(1, -24, 1, -14), UDim2.fromOffset(12, 7), Enum.Font.GothamBold, WHITE, Enum.TextXAlignment.Center)

	-- position
	posPanel = panel(gui, "Position", UDim2.fromOffset(200, 86), UDim2.fromOffset(16, 16))
	posText = text(posPanel, "Pos", "P1", UDim2.fromOffset(100, 56), UDim2.fromOffset(12, 6), Enum.Font.GothamBlack, ACCENT)
	posOf = text(posPanel, "Of", "/1", UDim2.fromOffset(60, 28), UDim2.fromOffset(112, 28), Enum.Font.GothamBold, MUTED)
	lapText = text(posPanel, "Lap", "LAP 1/3", UDim2.fromOffset(176, 20), UDim2.fromOffset(12, 60), Enum.Font.GothamBold, WHITE)

	buildTiming()
	buildSpeed()

	-- centre texts
	warnText = text(gui, "Warning", "", UDim2.fromOffset(700, 44), UDim2.new(0.5, -350, 0, 216), Enum.Font.GothamBlack, RED, Enum.TextXAlignment.Center)
	textStroke(warnText, 2)
	bigText = text(gui, "Big", "", UDim2.fromOffset(700, 90), UDim2.new(0.5, -350, 0, 158), Enum.Font.GothamBlack, WHITE, Enum.TextXAlignment.Center)
	bigText.Visible = false
	textStroke(bigText, 3)
	toast = text(gui, "Toast", "", UDim2.fromOffset(760, 34), UDim2.new(0.5, -380, 0, 64), Enum.Font.GothamBlack, WHITE, Enum.TextXAlignment.Center)
	toast.Visible = false
	textStroke(toast, 2)
	toastStroke = toast:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- start lights
	lightsFrame = panel(gui, "Lights", UDim2.fromOffset(330, 78), UDim2.new(0.5, 0, 0, 104), Vector2.new(0.5, 0))
	lightsFrame.Visible = false
	for i = 1, 5 do
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(50, 50)
		d.Position = UDim2.fromOffset(14 + (i - 1) * 62, 14)
		d.BackgroundColor3 = Color3.fromRGB(40, 12, 12)
		d.BorderSizePixel = 0
		corner(d, 25)
		stroke(d, Color3.new(0, 0, 0), 3, 0)
		d.Parent = lightsFrame
		lightDots[i] = d
	end

	buildMinimap()
	buildStandings()
	buildResults()
	buildTrackPanel()

	-- drive / walk and track buttons (the SETTINGS button sits after them)
	driveButton = bigButton(gui, "Drive", "DRIVE", UDim2.fromOffset(150, 40), UDim2.new(0, 16, 1, -16), ACCENT)
	driveButton.AnchorPoint = Vector2.new(0, 1)
	driveButton.Activated:Connect(function()
		Sfx.play("Click")
		requestRemote:FireServer("Kart")
	end)
	trackButton = bigButton(gui, "TrackButton", "TRACK  [M]", UDim2.fromOffset(180, 40), UDim2.new(0, 176, 1, -16), Color3.fromRGB(230, 232, 240))
	trackButton.AnchorPoint = Vector2.new(0, 1)
	trackButton.Visible = false
	trackButton.Activated:Connect(onTracksKey)
	if UserInputService.TouchEnabled then
		-- keep clear of the steering buttons
		driveButton.Position = UDim2.new(0, 16, 0, 240)
		driveButton.AnchorPoint = Vector2.zero
		trackButton.Position = UDim2.new(0, 16, 0, 288)
		trackButton.AnchorPoint = Vector2.zero
		-- the track / vote / room panel at the top in the middle, under the
		-- banner: down the left it covered the steering buttons
		trackPanel.Position = UDim2.fromOffset(0, 58)
	end

	-- spectate bar
	spectateBar = panel(gui, "Spectate", UDim2.fromOffset(360, 44), UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1))
	spectateBar.Visible = false
	spectateText = text(spectateBar, "Who", "WATCHING", UDim2.new(1, -110, 1, -16), UDim2.fromOffset(55, 8), Enum.Font.GothamBold, WHITE, Enum.TextXAlignment.Center)
	type ArrowSpec = { label: string, dir: number, pos: UDim2 }
	local arrows: { ArrowSpec } = {
		{ label = "<", dir = -1, pos = UDim2.fromOffset(6, 6) },
		{ label = ">", dir = 1, pos = UDim2.new(1, -46, 0, 6) },
	}
	for _, spec in arrows do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(40, 32)
		b.Position = spec.pos
		b.Text = spec.label
		b.Font = Enum.Font.GothamBlack
		b.TextScaled = true
		b.TextColor3 = PANEL
		b.BackgroundColor3 = ACCENT
		corner(b, 6)
		b.Parent = spectateBar
		b.Activated:Connect(function()
			spectateStep(spec.dir)
		end)
	end

	-- keyboard hint while driving
	hintText = text(gui, "Hint", "W/S gas-brake   A/D steer   R reset   wheel/C camera   right-drag rotate   V reset view   M track", UDim2.fromOffset(640, 18), UDim2.new(0.5, 0, 1, -10), Enum.Font.GothamMedium, MUTED, Enum.TextXAlignment.Center)
	hintText.AnchorPoint = Vector2.new(0.5, 1)

	-- whole-pixel scale, and centred elements snapped to whole pixels
	local toCentre: { GuiObject } = { banner, warnText, bigText, toast, lightsFrame, spectateBar, hintText }
	if UserInputService.TouchEnabled then
		table.insert(toCentre, trackPanel)
	end
	for _, obj in toCentre do
		centre(obj)
	end
	if speedPanel.AnchorPoint.X == 0.5 then
		centre(speedPanel)
	end
	local function rescale()
		uiScale.Scale = Settings.pixelScale(workspace.CurrentCamera.ViewportSize)
		placeCentred()
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	hintText.TextTransparency = 0.2

	Input.onAction("SpectateNext", function()
		spectateStep(1)
	end)
	Input.onAction("SpectatePrev", function()
		spectateStep(-1)
	end)
	Input.onAction("Tracks", onTracksKey)
	Input.onAction("TrackNext", onTrackNext)
	for n = 1, 6 do
		Input.onAction("Track" .. n, function()
			onTrackNumber(n)
		end)
	end

	Settings.onChange(function(key)
		if key == "Minimap" then
			drawMinimap()
		end
	end)

	findGantry()
	workspace:GetAttributeChangedSignal("TrackReady"):Connect(findGantry)
	workspace:GetAttributeChangedSignal("Track"):Connect(onTrackChanged)
	workspace:GetAttributeChangedSignal("RaceState"):Connect(function()
		local s = workspace:GetAttribute("RaceState")
		if s ~= "Racing" then
			ChaseCamera.spectate(nil)
		end
		if s == "Grid" then
			resetLap()
			findGantry()
		elseif s == "Intermission" then
			trackPanelClosed = false
			standings = {}
		elseif s == "Practice" then
			standings = {}
			trackPanelClosed = false
		end
	end)
	local raceEvent = remotes:WaitForChild("RaceEvent") :: RemoteEvent
	raceEvent.OnClientEvent:Connect(onRaceEvent)
	RunService.RenderStepped:Connect(update)
end

return Hud
