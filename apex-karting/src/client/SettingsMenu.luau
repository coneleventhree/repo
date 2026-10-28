--!strict
-- The SETTINGS button and panel: one row per Config.Settings item with
-- < value > arrows (works the same with a mouse, a finger or a gamepad
-- cursor). Changes apply at once and are saved with the player's data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local SettingsMenu = {}

local player = Players.LocalPlayer
local ACCENT = Color3.fromRGB(255, 196, 0)
local PANEL = Color3.fromRGB(14, 15, 20)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 175, 190)

local gui: ScreenGui
local panel: Frame? = nil
local openButton: TextButton? = nil
local valueLabels: { [string]: TextLabel } = {}

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function label(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, font: Enum.Font, color: Color3, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = text
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextColor3 = color
	t.TextScaled = true
	t.TextXAlignment = align
	t.Parent = parent
	return t
end

local function button(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, bg: Color3, fg: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = bg
	b.TextColor3 = fg
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.AutoButtonColor = true
	corner(b, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function show(key: string, value: any): string
	local item = Config.Settings.Items[key]
	if type(value) == "boolean" then
		return if value then "ON" else "OFF"
	elseif item.percent and type(value) == "number" then
		return string.format("%d%%", math.floor(value * 100 + 0.5))
	end
	return string.upper(tostring(value))
end

-- the next value one step left (-1) or right (+1)
local function stepValue(key: string, dir: number): any
	local item = Config.Settings.Items[key]
	local v = Settings.get(key)
	if type(item.default) == "boolean" then
		return not v
	elseif item.options then
		local i = table.find(item.options, v) or 1
		return item.options[(i - 1 + dir) % #item.options + 1]
	end
	local n = math.clamp((v :: number) + dir * item.step, item.min, item.max)
	return math.floor((n - item.min) / item.step + 0.5) * item.step + item.min
end

local function refresh(key: string)
	local l = valueLabels[key]
	if l then
		l.Text = show(key, Settings.get(key))
	end
end

function SettingsMenu.isOpen(): boolean
	local p = panel
	return p ~= nil and p.Visible
end

function SettingsMenu.toggle()
	local p = panel
	if p then
		p.Visible = not p.Visible
		Sfx.play("Click")
	end
end

-- The lobby menu has its own SETTINGS button: this one hides there.
function SettingsMenu.setButtonVisible(on: boolean)
	local b = openButton
	if b then
		b.Visible = on
	end
end

function SettingsMenu.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SettingsGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- the button sits after DRIVE and TRACK at the bottom left
	local open = button(gui, "SettingsButton", "SETTINGS", UDim2.fromOffset(130, 40), UDim2.new(0, 366, 1, -16), Color3.fromRGB(230, 232, 240), PANEL)
	open.AnchorPoint = Vector2.new(0, 1)
	if UserInputService.TouchEnabled then
		open.Position = UDim2.new(0, 16, 0, 336)
		open.AnchorPoint = Vector2.zero
	end
	open.Activated:Connect(SettingsMenu.toggle)
	openButton = open
	open.Visible = workspace:GetAttribute("ServerMode") ~= "lobby"

	local order = Config.Settings.Order
	local rowH = 34
	local frame = Instance.new("Frame")
	panel = frame
	frame.Name = "Panel"
	frame.Size = UDim2.fromOffset(470, 70 + #order * (rowH + 6) + 56)
	-- centred on whole pixels (see Settings.pixelScale)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	corner(frame, 12)
	frame.Parent = gui
	label(frame, "Title", "SETTINGS", UDim2.fromOffset(300, 30), UDim2.fromOffset(20, 16), Enum.Font.GothamBlack, ACCENT, Enum.TextXAlignment.Left)

	for i, key in order do
		local item = Config.Settings.Items[key]
		local y = 60 + (i - 1) * (rowH + 6)
		local row = Instance.new("Frame")
		row.Name = "Row_" .. key
		row.Size = UDim2.new(1, -40, 0, rowH)
		row.Position = UDim2.fromOffset(20, y)
		row.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		corner(row, 6)
		row.Parent = frame
		label(row, "Label", item.label, UDim2.new(0.55, -10, 1, -12), UDim2.fromOffset(10, 6), Enum.Font.GothamMedium, WHITE, Enum.TextXAlignment.Left)
		local left = button(row, "Left", "<", UDim2.fromOffset(34, rowH - 6), UDim2.new(1, -170, 0, 3), ACCENT, PANEL)
		local value = label(row, "Value", "", UDim2.fromOffset(92, rowH - 14), UDim2.new(1, -132, 0, 7), Enum.Font.GothamBold, ACCENT, Enum.TextXAlignment.Center)
		local right = button(row, "Right", ">", UDim2.fromOffset(34, rowH - 6), UDim2.new(1, -38, 0, 3), ACCENT, PANEL)
		valueLabels[key] = value
		left.Activated:Connect(function()
			Settings.set(key, stepValue(key, -1))
			Sfx.play("Click")
		end)
		right.Activated:Connect(function()
			Settings.set(key, stepValue(key, 1))
			Sfx.play("Click")
		end)
		refresh(key)
	end
	local done = button(frame, "Done", "DONE", UDim2.fromOffset(140, 38), UDim2.new(0.5, -70, 1, -52), ACCENT, PANEL)
	done.Activated:Connect(SettingsMenu.toggle)
	label(frame, "Hint", "Saved to your account", UDim2.fromOffset(200, 14), UDim2.new(1, -220, 0, 26), Enum.Font.GothamMedium, MUTED, Enum.TextXAlignment.Right)

	Settings.onChange(function(key)
		refresh(key)
	end)

	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		local s = Settings.pixelScale(vp)
		uiScale.Scale = s
		local size = frame.Size
		frame.Position = UDim2.fromOffset(math.floor((vp.X / s - size.X.Offset) / 2), math.max(0, math.floor((vp.Y / s - size.Y.Offset) / 2) - 18))
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

return SettingsMenu
