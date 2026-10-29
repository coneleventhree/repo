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

print("== Layered engine (EngineAudio) ==")
do
	-- the mix itself: the nearest two loops, each pitched only a little
	local EA = Game.sharedModule(G, ctx, "EngineAudio")
	local layers = { { id = "a", rpm = 1700 }, { id = "b", rpm = 2800 }, { id = "c", rpm = 4000 } }
	local worstPower, worstPitch = 0, 1
	for _, ld in { 0, 0.5, 1 } do
		for r = 2600, 4200, 50 do
			local m = EA.mix(layers, 3400, r, ld)
			local p2 = m.offVolume ^ 2
			if m.offVolume >= 0.5 then
				worstPitch = math.max(worstPitch, m.offSpeed, 1 / m.offSpeed)
			end
			for i, vol in m.volumes do
				p2 += vol * vol
				-- (what you mostly hear: a loop at half volume or more)
				if vol >= 0.5 then
					worstPitch = math.max(worstPitch, m.speeds[i], 1 / m.speeds[i])
				end
			end
			if ld ~= 0.5 then
				worstPower = math.max(worstPower, math.abs(p2 - 1))
			end
		end
	end
	check(worstPower < 1e-6, "on or off the throttle: the cross-fade keeps the power constant")
	check(worstPitch < 1.35, string.format("driving (2600 rpm up), the loop you hear is never pitched more than x%.2f (the old one: x1.89 between idle and top, moving its resonances)", worstPitch))
	local pull = EA.mix(layers, 3400, 2400, 1)
	check(pull.volumes[1] == 0 and pull.volumes[2] == 1, "on the throttle at low revs: the full-load loop, not the idle")
	local lift = EA.mix(layers, 3400, 3500, 0)
	check(lift.volumes[2] == 0 and lift.volumes[3] == 0 and lift.offVolume > 0.9, "throttle closed at speed: the overrun loop only")
	local idle = EA.mix(layers, 3400, 1600, 0)
	check(idle.volumes[1] == 1 and idle.offVolume == 0, "standing: the idle loop")
	check(EA.layers({ EngineLayers = { { id = "", rpm = 1700 }, { id = "x", rpm = 2800 } }, EngineOffSoundId = "y" }) == nil, "not used until every loop is uploaded")
end
do
	-- in the game, with the loops uploaded
	local G2 = Game.boot({ printErrors = true, reserved = { mode = "race" } })
	local B = G2.addPlayer("Bob", 202)
	local ctx2 = G2.startClient(B, Game.ClientSpec)
	local C2 = Game.sharedModule(G2, ctx2, "Config")
	for i, l in C2.Audio.EngineLayers do
		l.id = "rbxassetid://9" .. i
	end
	C2.Audio.EngineOffSoundId = "rbxassetid://99"
	G2.run(5)
	local KC2 = Game.clientModule(G2, ctx2, "KartController")
	local c = KC2.chassis()
	local function s(name: string)
		return c:FindFirstChild(name)
	end
	check(s("EngineSound") == nil and s("Engine1700") ~= nil and s("Engine4000") ~= nil and s("EngineOff") ~= nil, "the layered engine replaces the single loop")
	G2.run(1)
	check(s("Engine1700").Volume > 1 and s("Engine2800").Volume < 0.05 and s("EngineOff").Volume < 0.05, string.format("idle: the idle loop (%.2f)", s("Engine1700").Volume))
	G2.pressKey("W")
	G2.run(8)
	local v2 = c.AssemblyLinearVelocity.Magnitude
	local loaded = s("Engine2800").Volume + s("Engine4000").Volume
	check(loaded > 1.5 and s("Engine1700").Volume < 0.1 and s("EngineOff").Volume < 0.1, string.format("on the throttle at %.0f km/h: the full-throttle loops (%.2f)", v2 * KMH, loaded))
	G2.releaseKey("W")
	G2.run(0.6)
	check(s("EngineOff").Volume > 1 and s("Engine4000").Volume < 0.3, string.format("lifting at speed: the overrun loop (%.2f)", s("EngineOff").Volume))
	check(#G2.errors == 0, "no script errors (layered engine)")
end
print(string.format("%d/%d passed", pass, total))
