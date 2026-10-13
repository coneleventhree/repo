--!strict
-- 키보드, 마우스, 게임패드, 터치 입력을 모아서 Match.Input으로 만든다.
-- 강타/드롭 같은 "눌린 순간" 입력은 sample()에서 한 번만 전달되고 지워진다.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Match = require(Shared:WaitForChild("Match"))
local Strings = require(script.Parent:WaitForChild("Strings"))

local LEFT_KEYS = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.DPadLeft] = true }
local RIGHT_KEYS = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.DPadRight] = true }
local JUMP_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
}
local HIT_KEYS = { [Enum.KeyCode.J] = true, [Enum.KeyCode.ButtonX] = true, [Enum.KeyCode.ButtonR2] = true }
local DROP_KEYS = { [Enum.KeyCode.K] = true, [Enum.KeyCode.ButtonB] = true, [Enum.KeyCode.ButtonL2] = true }

type ControlsData = {
	enabled: boolean,
	held: { [string]: boolean },
	stickX: number,
	hitPressed: boolean,
	dropPressed: boolean,
	touchOwners: { [InputObject]: string },
	connections: { RBXScriptConnection },
	touchGui: ScreenGui?,
}

local Controls = {}
Controls.__index = Controls

export type Controls = typeof(setmetatable({} :: ControlsData, Controls))

local function actionFor(keyCode: Enum.KeyCode): string?
	if LEFT_KEYS[keyCode] then
		return "left"
	elseif RIGHT_KEYS[keyCode] then
		return "right"
	elseif JUMP_KEYS[keyCode] then
		return "jump"
	elseif HIT_KEYS[keyCode] then
		return "hit"
	elseif DROP_KEYS[keyCode] then
		return "drop"
	end
	return nil
end

function Controls.new(parent: Instance): Controls
	local self = setmetatable(
		{
			enabled = false,
			held = {},
			stickX = 0,
			hitPressed = false,
			dropPressed = false,
			touchOwners = {},
			connections = {},
			touchGui = nil,
		} :: ControlsData,
		Controls
	)

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return -- 채팅 입력이나 버튼 클릭은 무시
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:press("hit")
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				self:press("drop")
			else
				local action = actionFor(input.KeyCode)
				if action then
					self:press(action)
				end
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			local action = actionFor(input.KeyCode)
			if action then
				self.held[action] = false
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local x = input.Position.X
				self.stickX = if math.abs(x) > 0.3 then x else 0
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.TouchEnded:Connect(function(touch)
			local action = self.touchOwners[touch]
			if action then
				self.touchOwners[touch] = nil
				self.held[action] = false
			end
		end)
	)

	if UserInputService.TouchEnabled then
		self:buildTouchButtons(parent)
	end
	return self
end

function Controls.press(self: Controls, action: string)
	if not self.enabled then
		return
	end
	self.held[action] = true
	if action == "hit" then
		self.hitPressed = true
	elseif action == "drop" then
		self.dropPressed = true
	end
end

function Controls.buildTouchButtons(self: Controls, parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BadmintonTouch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = parent
	self.touchGui = gui

	local function button(action: string, text: string, anchor: Vector2, position: UDim2, size: number, color: Color3)
		local b = Instance.new("TextButton")
		b.Text = text
		b.Font = Enum.Font.GothamBlack
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.BackgroundColor3 = color
		b.BackgroundTransparency = 0.35
		b.AutoButtonColor = false
		b.AnchorPoint = anchor
		b.Position = position
		b.Size = UDim2.fromScale(size, size)
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = b
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = b
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.18, 0)
		padding.PaddingRight = UDim.new(0.18, 0)
		padding.PaddingTop = UDim.new(0.18, 0)
		padding.PaddingBottom = UDim.new(0.18, 0)
		padding.Parent = b
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				self.touchOwners[input] = action
				self:press(action)
			end
		end)
		b.Parent = gui
	end

	local dark = Color3.fromRGB(30, 34, 50)
	button("left", "◀", Vector2.new(0, 1), UDim2.new(0.03, 0, 0.95, 0), 0.16, dark)
	button("right", "▶", Vector2.new(0, 1), UDim2.new(0.2, 0, 0.95, 0), 0.16, dark)
	button(
		"jump",
		Strings.TouchJump,
		Vector2.new(1, 1),
		UDim2.new(0.97, 0, 0.62, 0),
		0.14,
		Color3.fromRGB(60, 120, 220)
	)
	button("hit", Strings.TouchHit, Vector2.new(1, 1), UDim2.new(0.97, 0, 0.95, 0), 0.17, Color3.fromRGB(220, 70, 70))
	button("drop", Strings.TouchDrop, Vector2.new(1, 1), UDim2.new(0.8, 0, 0.95, 0), 0.14, Color3.fromRGB(70, 170, 110))
end

function Controls.setEnabled(self: Controls, enabled: boolean)
	self.enabled = enabled
	table.clear(self.held)
	table.clear(self.touchOwners)
	self.hitPressed = false
	self.dropPressed = false
	local gui = self.touchGui
	if gui then
		gui.Enabled = enabled
	end
end

function Controls.isTouch(self: Controls): boolean
	return self.touchGui ~= nil and not UserInputService.KeyboardEnabled
end

-- mirror = true 이면 화면이 좌우 반전되어 있으므로 이동 방향도 뒤집는다
function Controls.sample(self: Controls, mirror: boolean): Match.Input
	local move = self.stickX
	if self.held.left then
		move -= 1
	end
	if self.held.right then
		move += 1
	end
	move = math.clamp(move, -1, 1)
	if mirror then
		move = -move
	end
	local input: Match.Input = {
		move = move,
		jump = self.held.jump == true,
		hit = self.hitPressed,
		drop = self.dropPressed,
	}
	self.hitPressed = false
	self.dropPressed = false
	return input
end

function Controls.destroy(self: Controls)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	local gui = self.touchGui
	if gui then
		gui:Destroy()
	end
end

return Controls
