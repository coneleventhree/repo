--!strict
-- 경기 화면(체육관, 코트, 네트, 선수, 셔틀콕, 효과)을 ScreenGui 프레임으로 그린다.
-- 월드 좌표 1단위는 화면에서 가로·세로 같은 픽셀 수가 되도록 16:9 아레나 안에 배치한다.
-- mirror = true 이면 좌우를 뒤집어서 그린다 (온라인에서 2번 선수도 자기가 왼쪽에 보이도록).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Match = require(Shared:WaitForChild("Match"))
local Strings = require(script.Parent:WaitForChild("Strings"))

local VIEW_W = Config.VIEW_WIDTH
local VIEW_H = Config.VIEW_HEIGHT
local VIEW_BOTTOM = Config.VIEW_BOTTOM
local VIEW_TOP = VIEW_BOTTOM + VIEW_H
local NET_X = Config.NET_X
local HALF = Config.COURT_HALF_LENGTH

local SKIN = Color3.fromRGB(255, 214, 170)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

export type PlayerInfo = {
	name: string,
	userId: number?,
	color: Color3,
}

type PlayerParts = {
	group: Frame,
	shadow: Frame,
	legs: { Frame },
	body: Frame,
	head: ImageLabel,
	eyes: { Frame },
	racket: Frame,
	nameTag: TextLabel,
	runPhase: number,
}

type Effect = {
	kind: string,
	age: number,
	life: number,
	x: number,
	y: number,
	gui: GuiObject,
	stroke: UIStroke?,
}

type RendererData = {
	gui: ScreenGui,
	root: Frame,
	arena: Frame,
	world: Frame,
	mirror: boolean,
	players: { PlayerParts },
	shuttle: Frame,
	shuttleShadow: Frame,
	offscreen: TextLabel,
	trail: { Frame },
	trailPoints: { Vector2 },
	shuttleAngle: number,
	effects: { Effect },
	shake: number,
	thumbnailRequest: number,
}

local Renderer = {}
Renderer.__index = Renderer

export type Renderer = typeof(setmetatable({} :: RendererData, Renderer))

-- 화면 기준 월드 좌표 -> 아레나 안의 Scale 좌표
local function toScale(x: number, y: number): UDim2
	return UDim2.fromScale(x / VIEW_W, 1 - (y - VIEW_BOTTOM) / VIEW_H)
end

local function sizeOf(w: number, h: number): UDim2
	return UDim2.fromScale(w / VIEW_W, h / VIEW_H)
end

local function newFrame(parent: Instance, color: Color3, transparency: number?, zIndex: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = zIndex or 1
	f.Parent = parent
	return f
end

local function rounded(gui: GuiObject, radius: UDim?): GuiObject
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0.5, 0)
	corner.Parent = gui
	return gui
end

-- 월드 직사각형 (왼쪽 위 모서리 left, top과 너비, 높이)
local function placeRect(f: GuiObject, left: number, top: number, w: number, h: number)
	f.AnchorPoint = Vector2.new(0, 0)
	f.Position = toScale(left, top)
	f.Size = sizeOf(w, h)
end

-- (px, py)에서 angle(도, 반시계 방향) 쪽으로 length만큼 뻗은 막대로 배치한다
local function placeBar(f: GuiObject, px: number, py: number, angle: number, length: number, thickness: number)
	local rad = math.rad(angle)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = toScale(px + math.cos(rad) * length / 2, py + math.sin(rad) * length / 2)
	f.Size = sizeOf(length, thickness)
	f.Rotation = -angle
end

local function newText(parent: Instance, text: string, zIndex: number, maxSize: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.4
	label.ZIndex = zIndex
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize or 40
	limit.Parent = label
	label.Parent = parent
	return label
end

local function easeOut(t: number): number
	local u = 1 - math.clamp(t, 0, 1)
	return 1 - u * u * u
end

-- 바라보는 방향이 오른쪽일 때의 라켓 각도 (도)
local function racketAngle(swingT: number, style: number, ready: boolean): number
	if swingT < 0 then
		return if ready then -125 else 65
	end
	local e = easeOut(swingT / Config.SWING_DURATION)
	if style == 0 then
		return 165 - 215 * e -- 오버헤드: 머리 뒤에서 앞 아래로
	end
	return -140 + 200 * e -- 언더핸드: 뒤 아래에서 앞 위로
end

local function buildBackground(world: Frame)
	-- 체육관 벽
	local wall = newFrame(world, Color3.fromRGB(38, 52, 92), 0, 1)
	placeRect(wall, 0, VIEW_TOP, VIEW_W, VIEW_H)
	local wallGradient = Instance.new("UIGradient")
	wallGradient.Rotation = 90
	wallGradient.Color = ColorSequence.new(Color3.fromRGB(22, 28, 54), Color3.fromRGB(58, 78, 128))
	wallGradient.Parent = wall

	-- 천장 조명
	for i = 1, 5 do
		local light = newFrame(world, Color3.fromRGB(255, 248, 220), 0.15, 2)
		rounded(light, UDim.new(0.3, 0))
		placeRect(light, i * VIEW_W / 6 - 0.6, VIEW_TOP - 0.15, 1.2, 0.14)
		local glow = newFrame(world, Color3.fromRGB(255, 248, 220), 0.9, 2)
		rounded(glow)
		placeRect(glow, i * VIEW_W / 6 - 1.2, VIEW_TOP - 0.05, 2.4, 0.5)
	end

	-- 벽의 큰 글씨
	local title = newText(world, Strings.Subtitle, 2, 120)
	title.Position = toScale(VIEW_W / 2, 5.6)
	title.Size = sizeOf(10, 1.3)
	title.TextTransparency = 0.88
	title.TextStrokeTransparency = 1

	-- 광고판 띠
	local board = newFrame(world, Color3.fromRGB(26, 34, 66), 0, 2)
	placeRect(board, 0, 1.05, VIEW_W, 0.75)
	local boardLine = newFrame(world, Color3.fromRGB(255, 196, 64), 0, 2)
	placeRect(boardLine, 0, 1.08, VIEW_W, 0.05)

	-- 나무 바닥
	local floor = newFrame(world, Color3.fromRGB(190, 132, 78), 0, 3)
	placeRect(floor, 0, 0.3, VIEW_W, 0.3 - VIEW_BOTTOM)
	local floorGradient = Instance.new("UIGradient")
	floorGradient.Rotation = 90
	floorGradient.Color = ColorSequence.new(Color3.fromRGB(214, 156, 98), Color3.fromRGB(120, 76, 40))
	floorGradient.Parent = floor

	-- 코트 (초록색 면 + 흰 라인). 바닥 위쪽 0.3 두께는 원근감을 위한 코트 윗면
	local court = newFrame(world, Color3.fromRGB(40, 132, 86), 0, 4)
	placeRect(court, NET_X - HALF - 0.4, 0.3, HALF * 2 + 0.8, 0.5)
	local courtGradient = Instance.new("UIGradient")
	courtGradient.Rotation = 90
	courtGradient.Color = ColorSequence.new(Color3.fromRGB(52, 156, 104), Color3.fromRGB(30, 100, 66))
	courtGradient.Parent = court
	local lines = { -HALF, -Config.SHORT_SERVICE_DIST, Config.SHORT_SERVICE_DIST, HALF }
	for _, offset in lines do
		local line = newFrame(world, WHITE, 0.05, 5)
		placeRect(line, NET_X + offset - 0.04, 0.3, 0.08, 0.3)
	end
	local edge = newFrame(world, WHITE, 0.6, 5)
	placeRect(edge, NET_X - HALF - 0.4, 0.02, HALF * 2 + 0.8, 0.04)
end

local function buildNet(world: Frame)
	local post = newFrame(world, Color3.fromRGB(70, 70, 80), 0, 9)
	placeRect(post, NET_X - 0.045, Config.NET_HEIGHT + 0.06, 0.09, Config.NET_HEIGHT + 0.06)
	local mesh = newFrame(world, Color3.fromRGB(235, 240, 255), 0.55, 9)
	placeRect(mesh, NET_X - 0.11, Config.NET_HEIGHT, 0.22, 0.76)
	local stripes = Instance.new("UIGradient")
	stripes.Rotation = 90
	stripes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	stripes.Parent = mesh
	local tape = newFrame(world, WHITE, 0, 10)
	placeRect(tape, NET_X - 0.13, Config.NET_HEIGHT + 0.03, 0.26, 0.07)
end

local function buildPlayer(world: Frame, zBase: number): PlayerParts
	local group = Instance.new("Frame")
	group.Name = "Player"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.ZIndex = zBase
	group.Parent = world

	local shadow = rounded(newFrame(group, BLACK, 0.65, zBase)) :: Frame
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)

	local legs = {}
	for i = 1, 2 do
		local leg = rounded(newFrame(group, Color3.fromRGB(40, 44, 60), 0, zBase + 1), UDim.new(0.4, 0)) :: Frame
		legs[i] = leg
	end

	local body = rounded(newFrame(group, WHITE, 0, zBase + 2), UDim.new(0.3, 0)) :: Frame
	body.AnchorPoint = Vector2.new(0.5, 1)
	local stripe = newFrame(body, WHITE, 0.25, zBase + 3)
	stripe.Size = UDim2.fromScale(1, 0.14)
	stripe.Position = UDim2.fromScale(0, 0.35)

	local head = Instance.new("ImageLabel")
	head.BackgroundColor3 = SKIN
	head.BorderSizePixel = 0
	head.ZIndex = zBase + 4
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.ScaleType = Enum.ScaleType.Crop
	rounded(head)
	head.Parent = group

	local eyes = {}
	for i = 1, 2 do
		local eye = rounded(newFrame(head, Color3.fromRGB(30, 30, 40), 0, zBase + 5)) :: Frame
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Size = UDim2.fromScale(0.13, 0.2)
		eyes[i] = eye
	end

	-- 팔 + 라켓. 컨테이너의 +x 방향이 라켓이 뻗는 방향이다.
	local racket = Instance.new("Frame")
	racket.BackgroundTransparency = 1
	racket.ZIndex = zBase + 6
	racket.Parent = group
	local arm = rounded(newFrame(racket, SKIN, 0, zBase + 6), UDim.new(0.5, 0)) :: Frame
	arm.AnchorPoint = Vector2.new(0, 0.5)
	arm.Position = UDim2.fromScale(0, 0.5)
	arm.Size = UDim2.fromScale(0.34, 0.36)
	local handle = newFrame(racket, Color3.fromRGB(40, 40, 48), 0, zBase + 6)
	handle.AnchorPoint = Vector2.new(0, 0.5)
	handle.Position = UDim2.fromScale(0.3, 0.5)
	handle.Size = UDim2.fromScale(0.34, 0.16)
	local frameRing = rounded(newFrame(racket, WHITE, 0.6, zBase + 7)) :: Frame
	frameRing.AnchorPoint = Vector2.new(0, 0.5)
	frameRing.Position = UDim2.fromScale(0.6, 0.5)
	frameRing.Size = UDim2.fromScale(0.4, 1)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 2.5
	ringStroke.Color = Color3.fromRGB(230, 60, 70)
	ringStroke.Parent = frameRing

	local nameTag = newText(group, "", zBase + 8, 22)
	nameTag.Font = Enum.Font.GothamBold

	return {
		group = group,
		shadow = shadow,
		legs = legs,
		body = body,
		head = head,
		eyes = eyes,
		racket = racket,
		nameTag = nameTag,
		runPhase = 0,
	}
end

function Renderer.new(parent: Instance): Renderer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BadmintonArena"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1

	local root = newFrame(gui, Color3.fromRGB(10, 12, 24), 0, 1)
	root.Size = UDim2.fromScale(1, 1)

	local arena = Instance.new("Frame")
	arena.Name = "Arena"
	arena.BackgroundTransparency = 1
	arena.AnchorPoint = Vector2.new(0.5, 0.5)
	arena.Position = UDim2.fromScale(0.5, 0.5)
	arena.Size = UDim2.fromScale(1, 1)
	arena.ClipsDescendants = true
	arena.ZIndex = 1
	arena.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = VIEW_W / VIEW_H
	aspect.Parent = arena

	-- 화면 흔들림은 world를 움직여서 표현한다
	local world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.Size = UDim2.fromScale(1, 1)
	world.Parent = arena

	buildBackground(world)
	buildNet(world)

	local shuttleShadow = rounded(newFrame(world, BLACK, 0.6, 6)) :: Frame
	shuttleShadow.AnchorPoint = Vector2.new(0.5, 0.5)

	local players = { buildPlayer(world, 20), buildPlayer(world, 40) }

	local trail = {}
	for i = 1, 8 do
		local dot = rounded(newFrame(world, WHITE, 1, 60)) :: Frame
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		trail[i] = dot
	end

	-- 셔틀콕: 컨테이너의 +x 방향이 코르크(머리) 쪽
	local shuttle = Instance.new("Frame")
	shuttle.Name = "Shuttle"
	shuttle.BackgroundTransparency = 1
	shuttle.ZIndex = 61
	shuttle.Parent = world
	local skirtShapes = { { 0, 0.36, 1 }, { 0.3, 0.3, 0.78 }, { 0.55, 0.15, 0.55 } }
	for _, shape in skirtShapes do
		local feather = newFrame(shuttle, WHITE, 0.08, 61)
		feather.AnchorPoint = Vector2.new(0, 0.5)
		feather.Position = UDim2.fromScale(shape[1], 0.5)
		feather.Size = UDim2.fromScale(shape[2], shape[3])
		rounded(feather, UDim.new(0.2, 0))
	end
	local cork = rounded(newFrame(shuttle, Color3.fromRGB(250, 236, 205), 0, 62)) :: Frame
	cork.AnchorPoint = Vector2.new(0, 0.5)
	cork.Position = UDim2.fromScale(0.62, 0.5)
	cork.Size = UDim2.fromScale(0.38, 0.62)
	local corkStroke = Instance.new("UIStroke")
	corkStroke.Thickness = 1
	corkStroke.Color = Color3.fromRGB(150, 110, 70)
	corkStroke.Parent = cork

	local offscreen = newText(world, "▲", 70, 30)
	offscreen.TextColor3 = Color3.fromRGB(255, 230, 120)
	offscreen.Size = sizeOf(0.5, 0.4)
	offscreen.Visible = false

	gui.Parent = parent

	local self = setmetatable(
		{
			gui = gui,
			root = root,
			arena = arena,
			world = world,
			mirror = false,
			players = players,
			shuttle = shuttle,
			shuttleShadow = shuttleShadow,
			offscreen = offscreen,
			trail = trail,
			trailPoints = {},
			shuttleAngle = -90,
			effects = {},
			shake = 0,
			thumbnailRequest = 0,
		} :: RendererData,
		Renderer
	)
	return self
end

-- 월드 x -> 화면 기준 x (mirror 반영)
function Renderer.screenX(self: Renderer, x: number): number
	return if self.mirror then VIEW_W - x else x
end

function Renderer.setPlayers(self: Renderer, infos: { PlayerInfo }, mirror: boolean)
	self.mirror = mirror
	self.thumbnailRequest += 1
	local request = self.thumbnailRequest
	for i, parts in self.players do
		local info = infos[i]
		parts.body.BackgroundColor3 = info.color
		parts.nameTag.Text = info.name
		parts.nameTag.TextColor3 = info.color:Lerp(WHITE, 0.55)
		parts.head.Image = ""
		for _, eye in parts.eyes do
			eye.Visible = true
		end
		local userId = info.userId
		if userId and userId > 0 then
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(
						userId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size100x100
					)
				end)
				if ok and request == self.thumbnailRequest then
					parts.head.Image = content
					for _, eye in parts.eyes do
						eye.Visible = false
					end
				end
			end)
		end
	end
	self:reset()
end

function Renderer.reset(self: Renderer)
	for _, effect in self.effects do
		effect.gui:Destroy()
	end
	table.clear(self.effects)
	table.clear(self.trailPoints)
	self.shake = 0
end

function Renderer.drawPlayer(self: Renderer, parts: PlayerParts, p: Match.PlayerView, ready: boolean, dt: number)
	local x = self:screenX(p.x)
	local y = p.y
	local dir = if self.mirror then -p.dir else p.dir
	local vx = if self.mirror then -p.vx else p.vx
	local speedRatio = math.min(math.abs(vx) / Config.PLAYER_SPEED, 1)

	local lift = math.min(y / 2.5, 0.6)
	parts.shadow.Position = toScale(x, 0.12)
	parts.shadow.Size = sizeOf(0.95 * (1 - lift), 0.16 * (1 - lift))
	parts.shadow.BackgroundTransparency = 0.6 + lift * 0.5

	-- 다리: 달릴 때 앞뒤로 흔들고, 공중에서는 접는다
	local hipY = y + 0.58
	local legLength = 0.6
	if p.onGround then
		parts.runPhase += math.abs(vx) * dt * 2.4
		local swing = math.sin(parts.runPhase) * 30 * speedRatio
		placeBar(parts.legs[1], x - 0.1, hipY, -90 + swing, legLength, 0.17)
		placeBar(parts.legs[2], x + 0.1, hipY, -90 - swing, legLength, 0.17)
	else
		placeBar(parts.legs[1], x - 0.1, hipY, -90 - 30 * dir, legLength * 0.85, 0.17)
		placeBar(parts.legs[2], x + 0.1, hipY, -90 + 15 * dir, legLength * 0.9, 0.17)
	end

	parts.body.Position = toScale(x, y + 0.46)
	parts.body.Size = sizeOf(0.64, 0.8)
	parts.body.Rotation = vx / Config.PLAYER_SPEED * 7

	local bob = if p.onGround then math.abs(math.sin(parts.runPhase)) * 0.05 * speedRatio else 0
	parts.head.Position = toScale(x + dir * 0.03, y + 1.56 + bob)
	parts.head.Size = sizeOf(0.6, 0.6)
	parts.eyes[1].Position = UDim2.fromScale(0.5 + dir * 0.12, 0.45)
	parts.eyes[2].Position = UDim2.fromScale(0.5 + dir * 0.34, 0.45)

	local angle = racketAngle(p.swingT, p.swingStyle, ready)
	if dir < 0 then
		angle = 180 - angle
	end
	placeBar(parts.racket, x + dir * 0.12, y + 1.1, angle, 1.25, 0.36)

	parts.nameTag.Position = toScale(x, y + 2.65)
	parts.nameTag.Size = sizeOf(3, 0.36)
end

local function shortestAngle(from: number, to: number): number
	return (to - from + 180) % 360 - 180
end

function Renderer.drawShuttle(self: Renderer, view: Match.View, dt: number)
	local s = view.shuttle
	local x = self:screenX(s.x)
	local vx = if self.mirror then -s.vx else s.vx
	local speed = math.sqrt(vx * vx + s.vy * s.vy)

	local target = self.shuttleAngle
	if s.grounded then
		target = if self.shuttleAngle > -90 and self.shuttleAngle < 90 then 15 else 165
	elseif speed > 0.5 then
		target = math.deg(math.atan2(s.vy, vx))
	elseif view.phase == "serve" then
		target = -90
	end
	local alpha = math.min(dt * 25, 1)
	self.shuttleAngle += shortestAngle(self.shuttleAngle, target) * alpha
	local drawY = if s.grounded then 0.12 else s.y
	local rad = math.rad(self.shuttleAngle)
	placeBar(self.shuttle, x - math.cos(rad) * 0.23, drawY - math.sin(rad) * 0.23, self.shuttleAngle, 0.46, 0.27)

	local height = math.clamp(s.y / 8, 0, 1)
	self.shuttleShadow.Position = toScale(x, 0.14)
	self.shuttleShadow.Size = sizeOf(0.36 * (1 - height * 0.5), 0.08)
	self.shuttleShadow.BackgroundTransparency = 0.45 + height * 0.45

	-- 빠른 샷에는 잔상을 남긴다
	table.insert(self.trailPoints, 1, Vector2.new(x, drawY))
	if #self.trailPoints > #self.trail then
		table.remove(self.trailPoints)
	end
	local fast = speed > 13 and not s.grounded
	for i, dot in self.trail do
		local point = self.trailPoints[i + 1]
		if fast and point then
			dot.Position = toScale(point.X, point.Y)
			local size = 0.14 * (1 - i / (#self.trail + 2))
			dot.Size = sizeOf(size, size)
			dot.BackgroundTransparency = 0.35 + i * 0.08
		else
			dot.BackgroundTransparency = 1
		end
	end

	local above = s.y > VIEW_TOP - 0.2
	self.offscreen.Visible = above
	if above then
		self.offscreen.Position = toScale(x, VIEW_TOP - 0.3)
	end
end

function Renderer.draw(self: Renderer, view: Match.View, dt: number)
	for i, parts in self.players do
		local p = view.players[i]
		if p then
			local ready = view.phase == "serve" and view.server == i
			self:drawPlayer(parts, p, ready, dt)
		end
	end
	self:drawShuttle(view, dt)
	self:updateEffects(dt)
end

function Renderer.addEffect(
	self: Renderer,
	kind: string,
	x: number,
	y: number,
	gui: GuiObject,
	life: number,
	stroke: UIStroke?
)
	table.insert(self.effects, { kind = kind, age = 0, life = life, x = x, y = y, gui = gui, stroke = stroke })
end

function Renderer.ring(self: Renderer, x: number, y: number, color: Color3)
	local ring = rounded(newFrame(self.world, color, 1, 80)) :: Frame
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.Parent = ring
	self:addEffect("ring", self:screenX(x), y, ring, 0.3, stroke)
end

function Renderer.popup(self: Renderer, x: number, y: number, text: string, color: Color3)
	local label = newText(self.world, text, 85, 36)
	label.TextColor3 = color
	label.Size = sizeOf(3, 0.6)
	self:addEffect("popup", self:screenX(x), y, label, 0.9)
end

function Renderer.landingMark(self: Renderer, x: number, good: boolean)
	local color = if good then Color3.fromRGB(110, 255, 150) else Color3.fromRGB(255, 90, 90)
	local mark = rounded(newFrame(self.world, color, 0.2, 7)) :: Frame
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	self:addEffect("mark", self:screenX(x), 0.14, mark, Config.POINT_PAUSE)
end

-- 경기 이벤트에 맞는 효과를 보여준다
function Renderer.handleEvent(self: Renderer, event: Match.Event)
	local x, y = event.x or NET_X, event.y or 1
	if event.kind == "hit" then
		local smash = event.shot == "smash"
		self:ring(x, y, if smash then Color3.fromRGB(255, 200, 80) else WHITE)
		if smash then
			self.shake = 0.18
			self:popup(x, y + 0.9, Strings.Smash, Color3.fromRGB(255, 210, 90))
		elseif (event.quality or 0) > 0.93 then
			self:popup(x, y + 0.9, Strings.Perfect, Color3.fromRGB(140, 230, 255))
		end
	elseif event.kind == "net" then
		self:ring(x, y, Color3.fromRGB(255, 120, 120))
		self.shake = math.max(self.shake, 0.08)
	elseif event.kind == "point" then
		local inBounds = math.abs(x - NET_X) <= HALF
		self:landingMark(x, inBounds)
	end
end

function Renderer.updateEffects(self: Renderer, dt: number)
	for i = #self.effects, 1, -1 do
		local effect = self.effects[i]
		effect.age += dt
		local t = effect.age / effect.life
		if t >= 1 then
			effect.gui:Destroy()
			table.remove(self.effects, i)
		elseif effect.kind == "ring" then
			local size = 0.3 + 1.1 * easeOut(t)
			effect.gui.Position = toScale(effect.x, effect.y)
			effect.gui.Size = sizeOf(size, size)
			local stroke = effect.stroke
			if stroke then
				stroke.Transparency = t
			end
		elseif effect.kind == "popup" then
			local label = effect.gui :: TextLabel
			label.Position = toScale(effect.x, effect.y + 0.8 * easeOut(t))
			label.TextTransparency = math.max(0, t * 2 - 1)
			label.TextStrokeTransparency = 0.4 + 0.6 * math.max(0, t * 2 - 1)
		elseif effect.kind == "mark" then
			local pulse = 0.5 + 0.12 * math.sin(effect.age * 10)
			effect.gui.Position = toScale(effect.x, effect.y)
			effect.gui.Size = sizeOf(pulse, pulse * 0.3)
			effect.gui.BackgroundTransparency = 0.2 + 0.8 * t * t
		end
	end

	if self.shake > 0 then
		self.shake = math.max(0, self.shake - dt)
		local amount = self.shake * 0.04
		self.world.Position = UDim2.fromScale((math.random() - 0.5) * amount, (math.random() - 0.5) * amount)
	else
		self.world.Position = UDim2.fromScale(0, 0)
	end
end

function Renderer.destroy(self: Renderer)
	self.gui:Destroy()
end

return Renderer
