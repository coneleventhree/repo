--!strict
-- The loading screen: shown while the game loads (the Loading script in
-- ReplicatedFirst) and when a player moves to another server (the menu
-- hands it to TeleportService:SetTeleportGui, so it stays up through the
-- teleport and the next server's Loading script carries on with it).
-- Plain frames and text, so there is nothing to download first.

local LoadingGui = {}

local BG = Color3.fromRGB(12, 13, 18)
local PANEL = Color3.fromRGB(30, 32, 40)
local ACCENT = Color3.fromRGB(255, 196, 0)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 175, 190)
local W, H = 520, 250

LoadingGui.Tips = {
	"Brake in a straight line, then turn in.",
	"All four wheels past the kerb is a track limit.",
	"Tuck in behind a kart on the straight: the slipstream tows you along.",
	"Qualifying is one lap with ghosts. Nobody can push you off.",
	"A clean lap beats a fast lap that gets deleted.",
	"Off the track? Press R (or the reset button) to get back on.",
	"PRIVATE ROOM: share the 4-digit code with your friends.",
	"Scroll or press C to change the camera. Zoom all the way in for the cockpit.",
	"Kerbs are fine to use. Grass and gravel are slow.",
	"Your best lap on every track is saved. Check RECORDS in the menu.",
}

local function label(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, textSize: number, font: Enum.Font, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = text
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextSize = textSize
	t.TextColor3 = color
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.Parent = parent
	return t
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

-- A fresh loading screen (not parented yet).
function LoadingGui.create(status: string?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "A1Loading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = BG
	back.BorderSizePixel = 0
	back.Parent = gui

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromOffset(W, H)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.BackgroundTransparency = 1
	box.Parent = back
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = box

	-- a racing stripe across the screen, just above the logo (inside the box
	-- so it scales with it; the box does not clip, so it runs edge to edge)
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.fromOffset(6000, 5)
	stripe.Position = UDim2.fromOffset(W / 2 - 3000, -16)
	stripe.BackgroundColor3 = ACCENT
	stripe.BackgroundTransparency = 0.6
	stripe.BorderSizePixel = 0
	stripe.Parent = box

	label(box, "Logo", "A1", UDim2.fromOffset(W, 76), UDim2.fromOffset(0, 0), 72, Enum.Font.GothamBlack, ACCENT)
	label(box, "Name", "K A R T   R A C I N G", UDim2.fromOffset(W, 26), UDim2.fromOffset(0, 78), 22, Enum.Font.GothamBold, WHITE)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromOffset(W - 80, 10)
	bar.Position = UDim2.fromOffset(40, 132)
	bar.BackgroundColor3 = PANEL
	bar.BorderSizePixel = 0
	corner(bar, 5)
	bar.Parent = box
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	corner(fill, 5)
	fill.Parent = bar
	-- a little kart riding the end of the bar
	local kart = Instance.new("Frame")
	kart.Name = "Kart"
	kart.Size = UDim2.fromOffset(22, 12)
	kart.AnchorPoint = Vector2.new(0.5, 1)
	kart.Position = UDim2.new(0, 0, 0, -3)
	kart.BackgroundColor3 = WHITE
	kart.BorderSizePixel = 0
	corner(kart, 3)
	kart.Parent = bar
	for i, x in { 4, 18 } do
		local wheel = Instance.new("Frame")
		wheel.Name = "Wheel" .. i
		wheel.Size = UDim2.fromOffset(7, 7)
		wheel.AnchorPoint = Vector2.new(0.5, 0.5)
		wheel.Position = UDim2.fromOffset(x, 12)
		wheel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		wheel.BorderSizePixel = 0
		corner(wheel, 4)
		wheel.Parent = kart
	end

	label(box, "Status", status or "Loading", UDim2.fromOffset(W, 24), UDim2.fromOffset(0, 156), 18, Enum.Font.GothamBold, WHITE)
	label(box, "Tip", "", UDim2.fromOffset(W - 40, 44), UDim2.fromOffset(20, 196), 15, Enum.Font.GothamMedium, MUTED)
	LoadingGui.tip(gui, math.random(1, #LoadingGui.Tips))
	LoadingGui.fit(gui)
	return gui
end

local function part(gui: ScreenGui, path: { string }): Instance?
	local node: Instance? = gui
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Fits the box to small screens (phones).
function LoadingGui.fit(gui: ScreenGui)
	local cam = workspace.CurrentCamera
	local s = part(gui, { "Back", "Box", "Scale" })
	if cam and s and s:IsA("UIScale") then
		local vp = cam.ViewportSize
		s.Scale = math.clamp(math.min(vp.X / (W + 40), vp.Y / (H + 120)), 0.55, 1.4)
	end
end

-- Progress 0..1, and optionally a new status line.
function LoadingGui.set(gui: ScreenGui, progress: number, status: string?)
	local a = math.clamp(progress, 0, 1)
	local fill = part(gui, { "Back", "Box", "Bar", "Fill" })
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(a, 1)
	end
	local kart = part(gui, { "Back", "Box", "Bar", "Kart" })
	if kart and kart:IsA("Frame") then
		kart.Position = UDim2.new(a, 0, 0, -3)
	end
	if status then
		local st = part(gui, { "Back", "Box", "Status" })
		if st and st:IsA("TextLabel") then
			st.Text = status
		end
	end
end

function LoadingGui.tip(gui: ScreenGui, index: number)
	local t = part(gui, { "Back", "Box", "Tip" })
	if t and t:IsA("TextLabel") then
		local n = #LoadingGui.Tips
		t.Text = "TIP: " .. LoadingGui.Tips[(index - 1) % n + 1]
	end
end

-- What the next server is, for the status line (teleport data or the
-- "Teleport" message: mode, track name, room code).
function LoadingGui.describe(info: any): string
	if type(info) ~= "table" then
		return "Loading"
	end
	if type(info.label) == "string" and info.label ~= "" then
		return info.label
	end
	if info.mode == "practice" then
		return "Loading practice"
	elseif info.mode == "race" then
		return "Joining the race"
	elseif info.mode == "room" then
		return if type(info.code) == "string" then "Joining room " .. info.code else "Joining the room"
	elseif info.mode == "lobby" then
		return "Back to the lobby"
	end
	return "Loading"
end

return LoadingGui
