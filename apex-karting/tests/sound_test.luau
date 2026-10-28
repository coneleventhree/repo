-- Kart sounds that follow the driving: the engine revs (a rental kart's idle,
-- slipping centrifugal clutch and one gear), the off-road rumble on grass and
-- gravel, and the kerb drumming. Run from the project root (after
-- python3 tests/mock/gen.py):   luau tests/sound_test.luau
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
local A = G.addPlayer("Alice", 101)
local ctx = G.startClient(A, Game.ClientSpec)
local Config = Game.sharedModule(G, ctx, "Config")
for i, name in { "Engine", "Skid", "Offroad", "Kerb" } do
	Config.Audio[name .. "SoundId"] = "rbxassetid://" .. i
end
local AU = Config.Audio
G.run(3)
local KC = Game.clientModule(G, ctx, "KartController")
local TrackMath = Game.sharedModule(G, ctx, "TrackMath")
local TrackData = Game.sharedModule(G, ctx, "TrackData")
local TrackLayout = Game.sharedModule(G, ctx, "TrackLayout")
local D = require("./mock/datatypes")
local Vector3, CFrame = D.Vector3, D.CFrame
check(KC.isDriving(), "driving")
local track = TrackMath.build(TrackData.get(TrackData.Default))

local function chassis()
	return KC.chassis()
end
local function snd(name: string)
	return chassis():FindFirstChild(name)
end
local function rpm(): number
	return snd("EngineSound").PlaybackSpeed * AU.EngineRpmLoop
end
local KMH = Config.KmhPerStudPerSecond

print("== Engine revs ==")
G.run(2)
check(math.abs(rpm() - AU.EngineRpmIdle) < 150, string.format("standing still: idle (%.0f rpm)", rpm()))
G.pressKey("W")
G.run(0.6)
local slow = chassis().AssemblyLinearVelocity.Magnitude
check(rpm() > AU.EngineRpmClutch * 0.9 and rpm() > AU.EngineRpmMax * slow / Config.Kart.TopSpeed, string.format("pulling away: the clutch slips above the road speed (%.0f rpm at %.0f km/h)", rpm(), slow * KMH))
G.run(12)
local v = chassis().AssemblyLinearVelocity.Magnitude
local want = AU.EngineRpmMax * v / Config.Kart.TopSpeed
check(math.abs(rpm() - want) < want * 0.08, string.format("at speed the revs follow the road (%.0f rpm at %.0f km/h, one gear says %.0f)", rpm(), v * KMH, want))
check(rpm() <= AU.EngineRpmMax * 1.1, "never far past the governor")
G.releaseKey("W")
G.run(0.4)
local coast = AU.EngineRpmMax * chassis().AssemblyLinearVelocity.Magnitude / Config.Kart.TopSpeed
check(coast > AU.EngineRpmRelease and math.abs(rpm() - coast) < coast * 0.1, string.format("lifting at speed: the clutch holds, the revs stay with the road (%.0f rpm)", rpm()))
G.run(15)
check(math.abs(rpm() - AU.EngineRpmIdle) < 150, string.format("rolled to a stop: the clutch let go, idle again (%.0f rpm)", rpm()))

-- put the kart somewhere at a speed and let the sounds settle
local function placeAt(pos, fwd, speed: number)
	local c = chassis()
	local k = KC.kart()
	local p = Vector3.new(pos.x, pos.y + Config.Kart.RideHeight + 0.05, pos.z)
	local f = Vector3.new(fwd.x, 0, fwd.z).Unit
	k:PivotTo(CFrame.lookAt(p, p + f))
	c.AssemblyLinearVelocity = f * speed
	c.AssemblyAngularVelocity = Vector3.zero
end

print("== Off the road ==")
G.pressKey("W")
local grid = TrackLayout.grid(track)
local zones = TrackLayout.zones(track, grid)
local spot = TrackLayout.openGround(track, grid, zones, TrackData.get(TrackData.Default).Segments, 20, 80)[1]
placeAt(vector.create(spot.pos.x, -0.1, spot.pos.z), vector.create(1, 0, 0), 25)
G.run(0.5)
local rumble = snd("OffroadSound")
check(rumble.Volume > 0.1, string.format("on the grass: the rumble (volume %.2f)", rumble.Volume))
check(snd("KerbSound").Volume < 0.01, "no kerb drumming on the grass")
local s1 = track.samples[10]
placeAt(s1.pos, s1.fwd, 25)
G.run(0.6)
check(rumble.Volume < 0.02, string.format("back on the asphalt: quiet again (%.3f)", rumble.Volume))

print("== Kerbs ==")
-- a sample with a kerb on its right: the right-hand wheels on it
local kerbAt = nil
for i = 1, track.n do
	if zones[i].right.kerb > 0 and zones[TrackMath.wrap(i + 2, track.n)].right.kerb > 0 then
		kerbAt = i
		break
	end
end
check(kerbAt ~= nil, "found a kerb")
local s = track.samples[kerbAt :: number]
local p = s.pos + s.right * (s.width / 2 - 0.4)
placeAt(p, s.fwd, 30)
local kerbVol, kerbRate = 0, 0
G.run(0.35, function()
	local k = snd("KerbSound")
	kerbVol = math.max(kerbVol, k.Volume)
	kerbRate = k.PlaybackSpeed
	return nil
end)
check(kerbVol > 0.05, string.format("wheels on the kerb: drumming (volume %.2f)", kerbVol))
local speedNow = chassis().AssemblyLinearVelocity.Magnitude
check(math.abs(kerbRate - math.clamp(speedNow / 72, 0.4, 1.6)) < 0.1, string.format("drumming rate follows the speed (x%.2f at %.0f km/h)", kerbRate, speedNow * KMH))
G.releaseKey("W")
check(#G.errors == 0, "no script errors")
print(string.format("%d/%d passed", pass, total))
