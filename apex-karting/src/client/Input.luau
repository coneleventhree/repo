--!strict
-- Driver input from keyboard, gamepad and on-screen touch buttons, merged
-- into one Controls table for KartPhysics. Also raises one-shot actions
-- (reset, camera) through callbacks.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PEDALS = Config.Pedals

local Input = {}

-- `steer` is the raw request; `digital` says it came from keys or touch
-- buttons (KartController smooths those, see SteerFilter).
export type Controls = { throttle: number, brake: number, steer: number, digital: boolean }

local controls: Controls = { throttle = 0, brake = 0, steer = 0, digital = true }
local touch = { left = false, right = false, gas = false, brake = false }
-- the touches (or clicks) holding each on-screen button. A button's own
-- InputEnded does not fire when the finger slides off it before lifting, and
-- with a press counter that left the button held for good (the kart kept
-- steering in circles with no finger on the screen). So a touch is dropped
-- when UserInputService says it ended, and every frame once its state is End.
local holders: { [string]: { [InputObject]: boolean } } = { left = {}, right = {}, gas = {}, brake = {} }
local buttons: { [string]: GuiObject } = {}
local actions: { [string]: () -> () } = {}
local touchGui: ScreenGui? = nil
local enabled = false
local kbThrottle, kbBrake = 0, 0

local DEADZONE = 0.12

local function fireAction(name: string)
	local f = actions[name]
	if f then
		f()
	end
end

function Input.onAction(name: string, callback: () -> ())
	actions[name] = callback
end

local function axis(v: number): number
	if math.abs(v) < DEADZONE then
		return 0
	end
	return (v - math.sign(v) * DEADZONE) / (1 - DEADZONE)
end

local function ended(io: InputObject): boolean
	local st = io.UserInputState
	return st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel
end

-- touch.<key> from the touches still holding each button
local function refreshTouch()
	for key, set in holders do
		for io in set do
			if ended(io) then
				set[io] = nil
			end
		end
		local on = next(set) ~= nil
		(touch :: any)[key] = on
		local b = buttons[key]
		if b then
			b.BackgroundTransparency = if on then 0.1 else 0.35
		end
	end
end

local function releaseInput(io: InputObject)
	for _, set in holders do
		set[io] = nil
	end
	refreshTouch()
end

local function releaseAll()
	for _, set in holders do
		table.clear(set)
	end
	refreshTouch()
end

-- Call once per frame while driving.
function Input.update(dt: number): Controls
	if not enabled then
		controls.throttle, controls.brake, controls.steer = 0, 0, 0
		return controls
	end
	refreshTouch()
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local function down(...: Enum.KeyCode): boolean
		if typing then
			return false
		end
		for _, k in { ... } do
			if UserInputService:IsKeyDown(k) then
				return true
			end
		end
		return false
	end
	-- keys and touch buttons are on/off: throttle and brake ramp in (Config.Pedals)
	local wantGas = down(Enum.KeyCode.W, Enum.KeyCode.Up) or touch.gas
	local wantBrake = down(Enum.KeyCode.S, Enum.KeyCode.Down) or touch.brake
	kbThrottle = if wantGas then math.min(kbThrottle + dt * PEDALS.ThrottleRise, 1) else 0
	kbBrake = if wantBrake then math.min(kbBrake + dt * PEDALS.BrakeRise, 1) else 0
	local kbSteer = (if down(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0) - (if down(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0)

	-- gamepad: analog triggers and stick
	local padThrottle, padBrake, padSteer = 0, 0, 0
	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, obj in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if obj.KeyCode == Enum.KeyCode.ButtonR2 then
				padThrottle = obj.Position.Z
			elseif obj.KeyCode == Enum.KeyCode.ButtonL2 then
				padBrake = obj.Position.Z
			elseif obj.KeyCode == Enum.KeyCode.Thumbstick1 then
				padSteer = axis(obj.Position.X)
			end
		end
	end

	-- touch buttons
	local tSteer = (if touch.right then 1 else 0) - (if touch.left then 1 else 0)

	controls.throttle = math.clamp(math.max(kbThrottle, padThrottle), 0, 1)
	controls.brake = math.clamp(math.max(kbBrake, padBrake), 0, 1)
	controls.steer = math.clamp(kbSteer + padSteer + tSteer, -1, 1)
	controls.digital = padSteer == 0
	return controls
end

function Input.get(): Controls
	return controls
end

----------------------------------------------------------------------------
-- Touch controls
----------------------------------------------------------------------------
local function makeButton(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.35
	b.AutoButtonColor = false
	b.Position = pos
	b.Size = size
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.5
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.28, 0)
	pad.PaddingBottom = UDim.new(0.28, 0)
	pad.Parent = b
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = b
	b.Parent = parent
	return b
end

local function hold(button: TextButton, key: string)
	buttons[key] = button
	button.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			holders[key][io] = true
			refreshTouch()
		end
	end)
	button.InputEnded:Connect(function(io)
		if holders[key][io] then
			holders[key][io] = nil
			refreshTouch()
		end
	end)
end

local function buildTouch()
	if touchGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchDrive"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local s = UDim2.fromScale(0, 0.2)
	local left = makeButton(gui, "Left", "<", UDim2.fromScale(0.09, 0.8), s, Color3.fromRGB(40, 40, 46))
	local right = makeButton(gui, "Right", ">", UDim2.fromScale(0.23, 0.8), s, Color3.fromRGB(40, 40, 46))
	local gas = makeButton(gui, "Gas", "GAS", UDim2.fromScale(0.9, 0.74), UDim2.fromScale(0, 0.24), Color3.fromRGB(30, 150, 70))
	local brake = makeButton(gui, "Brake", "BRK", UDim2.fromScale(0.76, 0.84), UDim2.fromScale(0, 0.17), Color3.fromRGB(190, 40, 40))
	-- small buttons near the pedals, clear of the minimap/standings (top right)
	-- and the speedometer (bottom centre on touch screens)
	local reset = makeButton(gui, "Reset", "R", UDim2.fromScale(0.765, 0.62), UDim2.fromScale(0, 0.1), Color3.fromRGB(60, 60, 70))
	local cam = makeButton(gui, "Camera", "CAM", UDim2.fromScale(0.645, 0.86), UDim2.fromScale(0, 0.1), Color3.fromRGB(60, 60, 70))
	for _, b in { left, right, gas, brake, reset, cam } do
		-- sizes are a fraction of screen height, kept square
		b.SizeConstraint = Enum.SizeConstraint.RelativeYY
		b.Size = UDim2.fromScale(b.Size.Y.Scale, b.Size.Y.Scale)
	end
	hold(left, "left")
	hold(right, "right")
	hold(gas, "gas")
	hold(brake, "brake")
	reset.Activated:Connect(function()
		fireAction("Reset")
	end)
	cam.Activated:Connect(function()
		fireAction("Camera")
	end)
	touchGui = gui
end

function Input.setEnabled(on: boolean)
	enabled = on
	if not on then
		releaseAll()
		kbThrottle, kbBrake = 0, 0
	end
	if touchGui then
		touchGui.Enabled = on and UserInputService.TouchEnabled
	end
end

function Input.init()
	if UserInputService.TouchEnabled then
		buildTouch()
	end
	-- a touch can end anywhere on the screen, not only over its button
	UserInputService.InputEnded:Connect(releaseInput)
	UserInputService.TouchEnded:Connect(function(io)
		releaseInput(io)
	end)
	-- switching apps mid-press never sends the ends
	UserInputService.WindowFocusReleased:Connect(releaseAll)
	UserInputService.InputBegan:Connect(function(io, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonY then
			if enabled then
				fireAction("Reset")
			end
		elseif k == Enum.KeyCode.C or k == Enum.KeyCode.ButtonX then
			fireAction("Camera")
		elseif k == Enum.KeyCode.K or k == Enum.KeyCode.ButtonSelect then
			fireAction("Kart")
		elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.DPadLeft then
			fireAction("SpectatePrev")
		elseif k == Enum.KeyCode.E or k == Enum.KeyCode.DPadRight then
			fireAction("SpectateNext")
		elseif k == Enum.KeyCode.M then
			fireAction("Tracks")
		elseif k == Enum.KeyCode.ButtonB then
			fireAction("TrackNext")
		else
			-- number keys pick a track on the track panel
			local digits = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
			local n = table.find(digits, k)
			if n then
				fireAction("Track" .. n)
			end
		end
	end)
end

return Input
