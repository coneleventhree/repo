-- Touch screens: the on-screen buttons let go when the finger lifts anywhere
-- (not only over the button), and a look-around finger that lifted unheard
-- does not swing the camera later. The user saw the kart spin on its own on a
-- phone. Run from the project root (after python3 tests/mock/gen.py):
--   luau tests/touch_test.luau
local Game = require("./lib/game")

local pass, total = 0, 0
local function check(ok: boolean, label: string)
	total += 1
	if ok then
		pass += 1
	end
	print(string.format("%-4s %s", if ok then "PASS" else "FAIL", label))
	return ok
end

local G = Game.boot({ printErrors = true, reserved = { mode = "race" } })
G.touch = true
local A = G.addPlayer("Alice", 101)
local ctx = G.startClient(A, Game.ClientSpec)
G.run(3)
local Input = Game.clientModule(G, ctx, "Input")
local KC = Game.clientModule(G, ctx, "KartController")
check(KC.isDriving(), "driving on a touch screen")
local gui = A:FindFirstChild("PlayerGui"):FindFirstChild("TouchDrive")
check(gui ~= nil and gui.Enabled, "touch buttons shown while driving")
local left, gas = gui:FindFirstChild("Left"), gui:FindFirstChild("Gas")

local function kartYaw(): number
	local c = KC.chassis()
	local l = c.CFrame.LookVector
	return math.deg(math.atan2(l.Z, l.X))
end
local function turned(a: number, b: number): number
	return math.abs((b - a + 540) % 360 - 180)
end

print("== Steering buttons ==")
local io = G.touchBegin(left)
G.run(0.3)
check(Input.get().steer < -0.5, string.format("holding < steers left (%.2f)", Input.get().steer))
-- the thumb slides off the button and lifts beside it: no InputEnded on it
G.touchEnd(io, false)
G.run(0.05)
check(Input.get().steer == 0, string.format("lifting off the button lets go (%.2f)", Input.get().steer))
io = G.touchBegin(left)
G.run(0.2)
G.touchLost(io) -- the end never reported (app switched away): only the state changed
G.run(0.05)
check(Input.get().steer == 0, "a touch that ended unheard lets go too")
-- two thumbs on one button: held until both lift
local a, b = G.touchBegin(left), G.touchBegin(left)
G.touchEnd(a)
G.run(0.1)
check(Input.get().steer < 0, "still held by the second touch")
G.touchEnd(b, false)
G.run(0.05)
check(Input.get().steer == 0, "and released with it")

print("== Gas ==")
io = G.touchBegin(gas)
G.run(1)
check(Input.get().throttle > 0.9, "GAS held: throttle")
G.touchEnd(io, false)
G.run(0.05)
check(Input.get().throttle == 0, "GAS lifted beside the button: no throttle")
-- the kart rolls to a stop and stays put with no finger on the screen
G.run(6)
local y0 = kartYaw()
local p0 = KC.chassis().Position
G.run(8)
local drift = turned(y0, kartYaw())
check(drift < 1 and (KC.chassis().Position - p0).Magnitude < 1, string.format("no fingers: the kart stays put (turned %.2f deg)", drift))

print("== Camera look-around ==")
local cam = G.workspace.CurrentCamera
local function camAngle(): number
	local c = KC.chassis()
	local l, k = cam.CFrame.LookVector, c.CFrame.LookVector
	return turned(math.deg(math.atan2(k.Z, k.X)), math.deg(math.atan2(l.Z, l.X)))
end
local before = camAngle()
local look = G.touchBegin(nil) -- a finger on the empty screen
G.touchMove(look, 120, 0)
G.run(0.3)
local swung = camAngle()
check(math.abs(swung - before) > 10, string.format("dragging the empty screen swings the camera (%.0f -> %.0f deg)", before, swung))
-- that finger lifts over a button, so the camera never hears it end, and the
-- next touch (on GAS, a processed one) reuses the InputObject
G.touchLost(look)
G.run(0.1)
G.touchBegin(gas, look)
G.touchMove(look, 160, 0)
G.touchMove(look, 160, 0)
G.run(0.3)
local after = camAngle()
check(math.abs(after - swung) < 2, string.format("a finger moving on GAS does not swing the camera (%.0f -> %.0f deg)", swung, after))
G.touchEnd(look)
G.run(0.1)
check(#G.errors == 0, "no script errors")

print(string.format("%d/%d passed", pass, total))
