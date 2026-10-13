--!strict
-- 메뉴, 매칭 대기, 점수판, 안내 문구, 결과 화면 등 아레나 위에 겹치는 UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Match = require(Shared:WaitForChild("Match"))
local Strings = require(script.Parent:WaitForChild("Strings"))

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(16, 20, 38)

export type Callbacks = {
	playAi: (difficulty: string) -> (),
	playOnline: () -> (),
	cancelQueue: () -> (),
	menu: () -> (),
	rematch: () -> (),
	forfeit: () -> (),
}

type InterfaceData = {
	gui: ScreenGui,
	menu: Frame,
	queue: Frame,
	queueLabel: TextLabel,
	result: Frame,
	resultTitle: TextLabel,
	resultScore: TextLabel,
	rematchButton: TextButton,
	hud: Frame,
	names: { TextLabel },
	scores: { TextLabel },
	serveDots: { TextLabel },
	message: TextLabel,
	messageAge: number,
	hint: TextLabel,
	exitButton: TextButton,
	queueTime: number,
}

local Interface = {}
Interface.__index = Interface

export type Interface = typeof(setmetatable({} :: InterfaceData, Interface))

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, maxText: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Size = size
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = WHITE
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxText
	limit.Parent = l
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.AutoButtonColor = true
	corner(b, 0.25)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.Parent = b
	b.Activated:Connect(onClick)
	b.Parent = parent
	return b
end

local function panel(parent: Instance, name: string, size: UDim2, aspect: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = size
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.12
	f.Visible = false
	corner(f, 0.06)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspect
	ratio.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 196, 64)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = f
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.05, 0)
	padding.PaddingBottom = UDim.new(0.05, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = f
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.025, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	f.Parent = parent
	return f
end

local function row(parent: Instance, height: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, height)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0.03, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	f.Parent = parent
	return f
end

local function order(gui: GuiObject, index: number): GuiObject
	gui.LayoutOrder = index
	return gui
end

function Interface.new(parent: Instance, callbacks: Callbacks): Interface
	local gui = Instance.new("ScreenGui")
	gui.Name = "BadmintonUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- 메인 메뉴
	local menu = panel(gui, "Menu", UDim2.fromScale(0.55, 0.85), 1.05)
	local title = order(label(menu, Strings.Title, UDim2.fromScale(1, 0.16), 64), 1) :: TextLabel
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 214, 90)
	order(label(menu, Strings.PlayAi, UDim2.fromScale(1, 0.07), 26), 2)
	local difficulties = order(row(menu, 0.12), 3)
	local diffs = {
		{ level = "Easy", text = Strings.Easy, color = Color3.fromRGB(70, 170, 110) },
		{ level = "Normal", text = Strings.Normal, color = Color3.fromRGB(60, 120, 220) },
		{ level = "Hard", text = Strings.Hard, color = Color3.fromRGB(210, 70, 80) },
	}
	for i, d in diffs do
		local b = button(difficulties, d.text, d.color, UDim2.fromScale(0.3, 1), function()
			callbacks.playAi(d.level)
		end)
		b.LayoutOrder = i
	end
	order(
		button(
			menu,
			Strings.PlayOnline,
			Color3.fromRGB(150, 90, 220),
			UDim2.fromScale(0.96, 0.12),
			callbacks.playOnline
		),
		4
	)
	local controls = order(label(menu, Strings.Controls, UDim2.fromScale(1, 0.16), 18), 5) :: TextLabel
	controls.Font = Enum.Font.Gotham
	controls.TextColor3 = Color3.fromRGB(200, 210, 235)
	local tip = order(label(menu, Strings.Tip, UDim2.fromScale(1, 0.06), 18), 6) :: TextLabel
	tip.TextColor3 = Color3.fromRGB(255, 214, 90)

	-- 매칭 대기
	local queue = panel(gui, "Queue", UDim2.fromScale(0.4, 0.4), 1.8)
	local queueLabel = order(label(queue, Strings.Searching, UDim2.fromScale(1, 0.35), 34), 1) :: TextLabel
	order(
		button(queue, Strings.Cancel, Color3.fromRGB(90, 96, 120), UDim2.fromScale(0.5, 0.3), callbacks.cancelQueue),
		2
	)

	-- 결과
	local result = panel(gui, "Result", UDim2.fromScale(0.42, 0.5), 1.4)
	local resultTitle = order(label(result, "", UDim2.fromScale(1, 0.32), 64), 1) :: TextLabel
	resultTitle.Font = Enum.Font.GothamBlack
	local resultScore = order(label(result, "", UDim2.fromScale(1, 0.2), 36), 2) :: TextLabel
	local resultButtons = order(row(result, 0.24), 3)
	local rematchButton = button(
		resultButtons,
		Strings.Rematch,
		Color3.fromRGB(60, 120, 220),
		UDim2.fromScale(0.45, 1),
		callbacks.rematch
	)
	rematchButton.LayoutOrder = 1
	local menuButton =
		button(resultButtons, Strings.Menu, Color3.fromRGB(90, 96, 120), UDim2.fromScale(0.45, 1), callbacks.menu)
	menuButton.LayoutOrder = 2

	-- 경기 중 HUD
	local hud = Instance.new("Frame")
	hud.Name = "Hud"
	hud.BackgroundTransparency = 1
	hud.Size = UDim2.fromScale(1, 1)
	hud.Visible = false
	hud.Parent = gui

	local board = Instance.new("Frame")
	board.AnchorPoint = Vector2.new(0.5, 0)
	board.Position = UDim2.fromScale(0.5, 0.03)
	board.Size = UDim2.fromScale(0.5, 0.09)
	board.BackgroundColor3 = PANEL
	board.BackgroundTransparency = 0.25
	corner(board, 0.3)
	local boardRatio = Instance.new("UIAspectRatioConstraint")
	boardRatio.AspectRatio = 7
	boardRatio.Parent = board
	board.Parent = hud

	local names, scores, serveDots = {}, {}, {}
	for i = 1, 2 do
		local left = i == 1
		local name = label(board, "", UDim2.fromScale(0.34, 0.5), 22)
		name.AnchorPoint = Vector2.new(if left then 0 else 1, 0.5)
		name.Position = UDim2.fromScale(if left then 0.04 else 0.96, 0.5)
		name.TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		names[i] = name

		local score = label(board, "0", UDim2.fromScale(0.12, 0.8), 48)
		score.Font = Enum.Font.GothamBlack
		score.AnchorPoint = Vector2.new(0.5, 0.5)
		score.Position = UDim2.fromScale(if left then 0.43 else 0.57, 0.5)
		scores[i] = score

		local dot = label(board, "●", UDim2.fromScale(0.04, 0.35), 18)
		dot.TextColor3 = Color3.fromRGB(255, 214, 90)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(if left then 0.36 else 0.64, 0.5)
		serveDots[i] = dot
	end
	local colon = label(board, ":", UDim2.fromScale(0.04, 0.7), 40)
	colon.AnchorPoint = Vector2.new(0.5, 0.5)
	colon.Position = UDim2.fromScale(0.5, 0.48)

	local message = label(hud, "", UDim2.fromScale(0.7, 0.13), 72)
	message.Font = Enum.Font.GothamBlack
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, 0.33)
	message.TextStrokeTransparency = 0.2
	message.TextTransparency = 1

	local hint = label(hud, "", UDim2.fromScale(0.7, 0.05), 22)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.fromScale(0.5, 0.15)
	hint.TextStrokeTransparency = 0.3
	hint.TextColor3 = Color3.fromRGB(255, 236, 160)

	local exitButton =
		button(hud, Strings.Menu, Color3.fromRGB(90, 96, 120), UDim2.fromScale(0.1, 0.06), callbacks.forfeit)
	exitButton.AnchorPoint = Vector2.new(1, 0)
	exitButton.Position = UDim2.fromScale(0.98, 0.03)
	exitButton.BackgroundTransparency = 0.3

	gui.Parent = parent

	return setmetatable(
		{
			gui = gui,
			menu = menu,
			queue = queue,
			queueLabel = queueLabel,
			result = result,
			resultTitle = resultTitle,
			resultScore = resultScore,
			rematchButton = rematchButton,
			hud = hud,
			names = names,
			scores = scores,
			serveDots = serveDots,
			message = message,
			messageAge = math.huge,
			hint = hint,
			exitButton = exitButton,
			queueTime = 0,
		} :: InterfaceData,
		Interface
	)
end

function Interface.showOnly(self: Interface, which: string)
	self.menu.Visible = which == "menu"
	self.queue.Visible = which == "queue"
	self.result.Visible = which == "result"
	self.hud.Visible = which == "game" or which == "result"
	self.exitButton.Visible = which == "game"
	if which ~= "game" then
		self.hint.Text = ""
	end
end

function Interface.showMenu(self: Interface)
	self:showOnly("menu")
end

function Interface.showQueue(self: Interface)
	self.queueTime = 0
	self:showOnly("queue")
end

-- names/colors는 화면 왼쪽, 오른쪽 순서
function Interface.showGame(self: Interface, names: { string }, colors: { Color3 }, online: boolean)
	for i = 1, 2 do
		self.names[i].Text = names[i]
		self.names[i].TextColor3 = colors[i]:Lerp(WHITE, 0.45)
		self.scores[i].Text = "0"
	end
	self.exitButton.Text = if online then Strings.Forfeit else Strings.Menu
	self.messageAge = math.huge
	self.message.TextTransparency = 1
	self.message.TextStrokeTransparency = 1
	self:showOnly("game")
end

-- leftSide: 화면 왼쪽에 보이는 선수 번호
function Interface.setScore(self: Interface, view: Match.View, leftSide: number)
	for i = 1, 2 do
		local side = if i == 1 then leftSide else 3 - leftSide
		self.scores[i].Text = tostring(view.score[side])
		self.serveDots[i].Visible = view.server == side and view.phase ~= "over"
	end
end

function Interface.showMessage(self: Interface, text: string, color: Color3)
	self.message.Text = text
	self.message.TextColor3 = color
	self.messageAge = 0
end

function Interface.setHint(self: Interface, text: string)
	self.hint.Text = text
end

function Interface.showResult(self: Interface, won: boolean, scoreText: string, subtitle: string?, online: boolean)
	self.resultTitle.Text = if won then Strings.Win else Strings.Lose
	self.resultTitle.TextColor3 = if won then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(170, 180, 210)
	self.resultScore.Text = if subtitle then subtitle .. "\n" .. scoreText else scoreText
	self.rematchButton.Text = if online then Strings.QueueAgain else Strings.Rematch
	self:showOnly("result")
end

function Interface.update(self: Interface, dt: number)
	self.messageAge += dt
	local t = self.messageAge
	if t < 1.4 then
		local pop = if t < 0.12 then 1.25 - t * 2 else 1
		self.message.Size = UDim2.fromScale(0.7 * pop, 0.13 * pop)
		local fade = math.clamp((t - 0.9) / 0.5, 0, 1)
		self.message.TextTransparency = fade
		self.message.TextStrokeTransparency = 0.2 + 0.8 * fade
	else
		self.message.TextTransparency = 1
		self.message.TextStrokeTransparency = 1
	end

	if self.queue.Visible then
		self.queueTime += dt
		self.queueLabel.Text = Strings.Searching:gsub("%.+$", "") .. string.rep(".", math.floor(self.queueTime * 2) % 4)
	end
end

return Interface
