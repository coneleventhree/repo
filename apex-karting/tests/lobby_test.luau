-- The lobby and the servers it sends players to: the menu over the fly-by,
-- the loading screen, PRACTICE (a reserved server on the chosen track), RACE
-- (the cross-server queue: 2 drivers, then 7 s), PRIVATE ROOM (codes), the
-- practice and room servers themselves, the LOBBY button, failures, and the
-- Studio fallback (one server switching in place).
-- Run from the project root (after python3 tests/mock/gen.py):
--   luau tests/lobby_test.luau
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

local function menuOf(p)
	return p.PlayerGui:FindFirstChild("Menu")
end
local function hudOf(p)
	return p.PlayerGui:FindFirstChild("RaceHud")
end
local function has(list, x): boolean
	return table.find(list, x) ~= nil
end
local function lastTeleport(G)
	return G.teleports[#G.teleports]
end
local function live(G, map: string, key: string)
	local m = G.memory[map]
	local e = m and m[key]
	if e and e.expires > G.time then
		return e.value
	end
	return nil
end

----------------------------------------------------------------------------
print("== Lobby (published game) ==")
local G = Game.boot({ printErrors = true, studio = false })
local ws = G.workspace
local ServerStorage = G.game:GetService("ServerStorage")
check(ws:GetAttribute("ServerMode") == "lobby", "a public server is a lobby")
local stored = ServerStorage:FindFirstChild("Circuits")
check(stored == nil or #stored:GetChildren() == 0, "a lobby builds only the circuit behind the menu")
local A = G.addPlayer("Alice", 101)
local ctxA = G.startClient(A, Game.ClientSpec)
G.run(2)
check(ws:GetAttribute("RaceState") == "Lobby", "state Lobby")
check(#ws.Karts:GetChildren() == 0, "no karts in the lobby")
local hum = A.Character and A.Character:FindFirstChildOfClass("Humanoid")
check(hum ~= nil and hum.WalkSpeed == 0, "the character stands still behind the menu")
local mA = menuOf(A)
check(mA ~= nil and mA.Home.Visible, "home menu on screen")
check(mA.Home.Race ~= nil and mA.Home.Practice ~= nil and mA.Home.Room ~= nil, "RACE / PRACTICE / PRIVATE ROOM")
check(not mA.Practice.Visible and not mA.Queue.Visible and not mA.Room.Visible, "other screens closed")
check(not mA.LobbyButton.Visible, "no LOBBY button in the lobby")
local sgui = A.PlayerGui:FindFirstChild("SettingsGui")
check(sgui ~= nil and not sgui.SettingsButton.Visible, "the HUD's SETTINGS button is hidden (the menu has its own)")
local trackName = ws:GetAttribute("TrackName")
check(mA.NowShowing.Visible and mA.NowShowing.Text:find(string.upper(trackName), 1, true) ~= nil, "now showing: " .. mA.NowShowing.Text)
local cam = ws.CurrentCamera
check(cam.CameraType.Name == "Scriptable", "the menu camera flies")
local p0 = cam.CFrame.Position
G.run(2)
check((cam.CFrame.Position - p0).Magnitude > 20, string.format("the fly-by moves along the track (%.0f studs in 2 s)", (cam.CFrame.Position - p0).Magnitude))
check(not hudOf(A).Banner.Visible, "no race banner over the menu")

----------------------------------------------------------------------------
print("== Loading screen ==")
G.localTeleportData = nil
Game.startLoading(G, ctxA)
G.step(2)
local lg = A.PlayerGui:FindFirstChild("A1Loading")
check(lg ~= nil and G.defaultLoadingRemoved == true, "our loading screen instead of Roblox's")
check(lg ~= nil and lg.Back.Box.Logo.Text == "A1", "logo")
check(lg ~= nil and string.sub(lg.Back.Box.Tip.Text, 1, 5) == "TIP: ", "a tip: " .. (if lg then lg.Back.Box.Tip.Text else "?"))
G.run(1)
local fill = lg and lg.Back.Box.Bar.Fill.Size.X.Scale or 0
check(fill > 0.05, string.format("the bar moves (%.2f)", fill))
G.run(3)
check(lg ~= nil and lg.Parent == nil, "gone once the game and the circuit are ready")
-- arriving from a teleport: carries on with the screen the last server handed over
do
	local LoadingGui = ctxA.require(G.first:FindFirstChild("LoadingGui"))
	local handed = LoadingGui.create("x")
	G.arrivingGui = handed
	G.localTeleportData = { mode = "practice", track = "Lakeside", label = "Practice  -  Lakeside International" }
	Game.startLoading(G, ctxA)
	G.step(2)
	check(handed.Parent == A.PlayerGui, "the teleport's loading screen carries on (no gap)")
	check(handed.Back.Box.Status.Text:find("Lakeside", 1, true) ~= nil, "says where we are: " .. handed.Back.Box.Status.Text)
	G.run(4)
	check(handed.Parent == nil, "and goes when ready")
	G.arrivingGui = nil
	G.localTeleportData = nil
end

----------------------------------------------------------------------------
print("== PRACTICE: pick a track, off to a reserved server ==")
mA.Home.Practice.Activated:Fire()
G.run(0.1)
check(mA.Practice.Visible and not mA.Home.Visible, "track cards")
local cards = mA.Practice.Cards
check(#cards:GetChildren() >= 5, "a card per track")
check(cards.Card_Lakeside.Best.Text == "NO TIME YET", "no best yet: " .. cards.Card_Lakeside.Best.Text)
cards.Card_Lakeside.Activated:Fire()
G.run(0.1)
check(cards.Card_Lakeside.Ring.Transparency == 0 and cards.Card_Tampines.Ring.Transparency == 1, "the picked card is highlighted")
mA.Practice.Drive.Activated:Fire()
G.run(1.5)
check(G.reservedCount == 1, "a server reserved")
local role = live(G, "A1Servers", "psid-1")
check(role ~= nil and role.mode == "practice" and role.track == "Lakeside", "its role noted for it to read")
local tp = lastTeleport(G)
check(tp ~= nil and tp.code == "access-1" and #tp.players == 1 and tp.players[1] == A, "Alice teleported to it")
check(tp ~= nil and tp.data.mode == "practice" and tp.data.track == "Lakeside", "teleport data: practice on Lakeside")
local leaving = A.PlayerGui:FindFirstChild("A1Loading")
check(leaving ~= nil, "loading screen up before the teleport")
check(leaving ~= nil and G.teleportGui[ctxA] == leaving, "and handed to the teleport")
check(leaving ~= nil and leaving.Back.Box.Status.Text:find("Lakeside", 1, true) ~= nil, "it names the track: " .. (if leaving then leaving.Back.Box.Status.Text else "?"))
local MenuA = Game.clientModule(G, ctxA, "Menu")
check(MenuA.isLeaving(), "menu knows we are leaving")
mA.Practice.Drive.Activated:Fire()
G.run(1)
check(#G.teleports == 1, "a second press while leaving does nothing")

----------------------------------------------------------------------------
print("== RACE: the queue ==")
local B = G.addPlayer("Bob", 202)
local C = G.addPlayer("Cara", 303)
G.startClient(B, Game.ClientSpec)
G.startClient(C, Game.ClientSpec)
G.run(2)
local mB, mC = menuOf(B), menuOf(C)
mB.Home.Race.Activated:Fire()
G.run(2)
check(B:GetAttribute("Queued") == true, "Bob waits for a race")
check(mB.Queue.Visible and not mB.Home.Visible, "queue screen")
check(mB.Queue.Status.Text:find("1/2", 1, true) ~= nil, "waiting for drivers: " .. mB.Queue.Status.Text)
check(live(G, "A1Queue", "202") ~= nil, "a ticket in the shared queue")
check(B:GetAttribute("QueueGo") == nil, "alone: no countdown")
mB.Queue.Cancel.Activated:Fire()
G.run(1)
check(B:GetAttribute("Queued") == nil and live(G, "A1Queue", "202") == nil, "CANCEL: out of the queue, ticket gone")
check(mB.Home.Visible, "back to the menu")
G.run(3)
check(#G.teleports == 1, "nobody sent anywhere")
mB.Home.Race.Activated:Fire()
G.run(1)
local joined = G.time
mC.Home.Race.Activated:Fire()
G.run(2)
local go = B:GetAttribute("QueueGo")
check(go ~= nil and C:GetAttribute("QueueGo") == go, "two drivers: a countdown for both")
check(go ~= nil and math.abs(go - (1.7e9 + joined) - 7) < 1, string.format("the race goes 7 s after the second driver (%.1f)", (go or 0) - (1.7e9 + joined)))
check(mC.Queue.Title.Text == "RACE FOUND" and mC.Queue.Status.Text:find("starting in", 1, true) ~= nil, "screen: " .. mC.Queue.Status.Text)
local before = #G.teleports
G.run(10, function()
	return #G.teleports > before
end)
tp = lastTeleport(G)
local waited = G.time - joined
check(#G.teleports == before + 1, "one teleport for the race")
check(tp.code ~= nil and #tp.players == 2 and has(tp.players, B) and has(tp.players, C), "Bob and Cara together, to one reserved server")
check(waited > 6.5 and waited < 9.5, string.format("after %.1f s", waited))
check(tp.data.mode == "race", "teleport data: race")
role = live(G, "A1Servers", "psid-" .. G.reservedCount)
check(role ~= nil and role.mode == "race", "the server knows it is a race server")
check(live(G, "A1Queue", "202") == nil and live(G, "A1Queue", "303") == nil, "tickets cleared")
check(B:GetAttribute("Queued") == nil and C:GetAttribute("Queued") == nil, "no longer queued")
check(B.PlayerGui:FindFirstChild("A1Loading") ~= nil and C.PlayerGui:FindFirstChild("A1Loading") ~= nil, "both see the loading screen")

----------------------------------------------------------------------------
print("== RACE: a driver on another lobby server ==")
local D = G.addPlayer("Dan", 404)
G.startClient(D, Game.ClientSpec)
G.run(2)
-- someone already waiting on another server (their ticket in the shared map)
G.memMap("A1Queue")
G.memory.A1Queue["909"] = { value = { job = "job-other", t = 1.7e9 + G.time - 1, name = "Remote" }, expires = G.time + 45 }
menuOf(D).Home.Race.Activated:Fire()
G.run(2)
check(D:GetAttribute("QueueCount") == 2 and D:GetAttribute("QueueGo") ~= nil, "counts the other server's driver: countdown")
before = #G.teleports
G.run(10, function()
	return #G.teleports > before
end)
tp = lastTeleport(G)
check(#G.teleports == before + 1 and #tp.players == 1 and tp.players[1] == D, "this server sends only its own driver")
local remote = live(G, "A1Queue", "909")
check(remote ~= nil and remote.code == tp.code, "the other driver's ticket has the same server (their lobby sends them)")
G.memory.A1Queue["909"] = nil

----------------------------------------------------------------------------
print("== PRIVATE ROOM ==")
local E = G.addPlayer("Eve", 505)
local F = G.addPlayer("Finn", 606)
G.startClient(E, Game.ClientSpec)
G.startClient(F, Game.ClientSpec)
G.run(2)
local mE, mF = menuOf(E), menuOf(F)
mE.Home.Room.Activated:Fire()
G.run(0.1)
check(mE.Room.Visible, "room screen")
before = #G.teleports
mE.Room.Create.Activated:Fire()
G.run(1.5)
tp = lastTeleport(G)
check(#G.teleports == before + 1 and tp.players[1] == E and tp.data.mode == "room", "CREATE: Eve off to her room")
local code = tp.data.code
check(type(code) == "string" and #code == 4 and string.match(code, "^%d+$") ~= nil, "a 4-digit code: " .. tostring(code))
check(tp.data.host == 505, "Eve is the host")
local entry = live(G, "A1Rooms", code)
check(entry ~= nil and entry.access == tp.code, "the code points at the room's server")
role = live(G, "A1Servers", "psid-" .. G.reservedCount)
check(role ~= nil and role.mode == "room" and role.code == code and role.host == 505, "the room server knows its code and host")
local roomAccess = tp.code
mF.Home.Room.Activated:Fire()
G.run(0.1)
mF.Room.Code.Text = "12"
mF.Room.Join.Activated:Fire()
G.run(0.2)
check(mF.Error.Visible and mF.Error.Text:find("4-digit", 1, true) ~= nil, "too short: " .. mF.Error.Text)
mF.Room.Code.Text = "98a76543"
G.step(1)
check(mF.Room.Code.Text == "9876", "the box keeps digits only, 4 of them: " .. mF.Room.Code.Text)
local wrong = if code == "0000" then "1111" else "0000"
mF.Room.Code.Text = wrong
mF.Room.Join.Activated:Fire()
G.run(1)
check(mF.Error.Visible and mF.Error.Text == "No room with that code", "unknown code: " .. mF.Error.Text)
before = #G.teleports
mF.Room.Code.Text = code
mF.Room.Join.Activated:Fire()
G.run(1.5)
tp = lastTeleport(G)
check(#G.teleports == before + 1 and tp.players[1] == F and tp.code == roomAccess, "the right code: Finn joins Eve's room")
check(tp.data.mode == "room" and tp.data.code == code, "teleport data: the room")

----------------------------------------------------------------------------
print("== When things fail ==")
local H = G.addPlayer("Hal", 707)
local ctxH = G.startClient(H, Game.ClientSpec)
G.run(2)
local mH = menuOf(H)
local MenuH = Game.clientModule(G, ctxH, "Menu")
G.reserveFails = true
before = #G.teleports
mH.Home.Practice.Activated:Fire()
G.run(0.1)
mH.Practice.Drive.Activated:Fire()
G.run(1.5)
check(#G.teleports == before and mH.Error.Visible and mH.Error.Text:find("practice", 1, true) ~= nil, "no server: " .. mH.Error.Text)
check(not MenuH.isLeaving() and mH.Practice.Visible, "still in the menu")
G.reserveFails = false
G.teleportFails = true
mH.Practice.Drive.Activated:Fire()
G.run(1.5)
check(mH.Error.Visible and mH.Error.Text:find("Couldn't move you", 1, true) ~= nil, "teleport failed: " .. mH.Error.Text)
check(H.PlayerGui:FindFirstChild("A1Loading") == nil and not MenuH.isLeaving(), "loading screen down again")
check(mH.Home.Visible, "back on the home screen")
G.teleportFails = false
before = #G.teleports
mH.Home.Practice.Activated:Fire()
G.run(0.1)
mH.Practice.Drive.Activated:Fire()
G.run(1.5)
check(#G.teleports == before + 1 and lastTeleport(G).players[1] == H, "and trying again works")
check(#G.errors == 0, "no script errors (lobby)")

----------------------------------------------------------------------------
print("== A practice server ==")
local P = Game.boot({ printErrors = true, studio = false, reserved = { mode = "practice", track = "Lakeside" } })
local pws = P.workspace
check(pws:GetAttribute("ServerMode") == "practice" and pws:GetAttribute("Track") == "Lakeside", "practice server on the track that was picked")
local A2 = P.addPlayer("Alice", 101)
P.startClient(A2, Game.ClientSpec)
P.run(4)
check(pws:GetAttribute("RaceState") == "Practice", "free practice")
check(pws.Karts:FindFirstChild("Kart_101") ~= nil, "a kart straight away")
check(hudOf(A2).Banner.Text.Text == "PRACTICE  -  LAKESIDE INTERNATIONAL", "banner: " .. hudOf(A2).Banner.Text.Text)
local m2 = menuOf(A2)
check(not m2.Home.Visible, "no menu here")
local lb = m2.LobbyButton
check(lb.Visible, "LOBBY button")
lb.Activated:Fire()
P.run(0.2)
check(lb.Text == "TAP AGAIN" and #P.teleports == 0, "first press only asks again")
P.run(3.5)
check(lb.Text == "LOBBY", "the question times out")
lb.Activated:Fire()
lb.Activated:Fire()
P.run(1.5)
local back = lastTeleport(P)
check(back ~= nil and back.players[1] == A2 and back.code == nil and back.data.mode == "lobby", "two presses: back to a public server (a lobby)")
P.run(2)
-- the race loop never starts here, whoever turns up
local A3 = P.addPlayer("Ann", 111)
P.run(4)
check(pws:GetAttribute("RaceState") == "Practice", "a practice server never goes to a race")
check(#P.errors == 0, "no script errors (practice server)")

----------------------------------------------------------------------------
print("== A private room's server: the waiting room ==")
local R = Game.boot({ printErrors = true, studio = false, reserved = { mode = "room", code = "4321", host = 101 } })
local rws = R.workspace
-- the room's code entry, as the lobby left it
R.memMap("A1Rooms")
R.memory.A1Rooms["4321"] = { value = { access = "access-room", host = 101, name = "Alice" }, expires = math.huge }
local Host = R.addPlayer("Alice", 101)
local Guest = R.addPlayer("Bob", 202)
R.startClient(Host, Game.ClientSpec)
R.startClient(Guest, Game.ClientSpec)
R.run(4)
check(rws:GetAttribute("ServerMode") == "room" and rws:GetAttribute("RoomCode") == "4321", "room 4321")
check(rws:GetAttribute("RoomHost") == 101 and rws:GetAttribute("RoomHostName") == "Alice", "Alice hosts")
check(rws:GetAttribute("RaceState") == "Lobby", "the waiting room first (no racing yet)")
check(#rws.Karts:GetChildren() == 0, "no karts in the waiting room")
local gHum = Guest.Character and Guest.Character:FindFirstChildOfClass("Humanoid")
check(gHum ~= nil and gHum.WalkSpeed == 0, "characters stand still behind it")
R.run(30, function()
	return #string.split(rws:GetAttribute("Tracks") or "", ",") >= 5
end)
R.run(0.5)
local hm, gm = menuOf(Host), menuOf(Guest)
local hr, gr = hm.RoomLobby, gm.RoomLobby
check(hr.Visible and gr.Visible, "both see the waiting room")
check(not hudOf(Host).Enabled and not hudOf(Guest).Enabled, "no race HUD over it")
check(not hm.LobbyButton.Visible and hr.Leave.Visible, "LEAVE instead of the LOBBY button")
check(R.workspace.CurrentCamera.CameraType.Name == "Scriptable", "the fly-by behind it")
check(hr.Code.Text == "4321", "the code is on screen")
check(hr.PlayersTitle.Text == "PLAYERS  2/12", hr.PlayersTitle.Text)
check(hr.Slot1.PlayerName.Text == "Alice" and hr.Slot1.Status.Text == "HOST", "slot 1: Alice, HOST")
check(hr.Slot2.PlayerName.Text == "Bob" and hr.Slot2.Status.Text == "NOT READY", "slot 2: Bob, NOT READY")
check(hr.Slot3.PlayerName.Text == "OPEN" and hr.Slot12.PlayerName.Text == "OPEN", "the rest OPEN (12 slots)")
check(hr.Slot2.Kick.Visible and not hr.Slot1.Kick.Visible, "the host can kick Bob (not herself)")
check(not gr.Slot1.Kick.Visible and not gr.Slot2.Kick.Visible, "a guest kicks nobody")
check(hr.Prev.Visible and hr.Next.Visible and not hr.HostPicks.Visible, "the host has the track arrows")
check(not gr.Prev.Visible and gr.HostPicks.Visible, "the guest sees who picks")
check(hr.Action.Title.Text == "START RACE" and hr.Status.Text:find("Waiting for 1 player", 1, true) ~= nil, "host: START RACE, waiting: " .. hr.Status.Text)
check(gr.Action.Title.Text == "READY", "guest: READY")
-- START before everyone is ready: nothing
hr.Action.Activated:Fire()
R.run(1)
check(rws:GetAttribute("RaceState") == "Lobby", "START with Bob not ready: still waiting")
check(hm.Error.Visible and hm.Error.Text:find("READY", 1, true) ~= nil, "the host is told: " .. hm.Error.Text)
-- the guest's buttons do nothing on the server
gr.Next.Activated:Fire()
gr.Len_Short.Activated:Fire()
R.run(1.5)
check(rws:GetAttribute("Track") == "Tampines" and rws:GetAttribute("RoomLength") == "Normal", "a guest cannot change the track or length")
-- the host picks the next track and SHORT
hr.Next.Activated:Fire()
R.run(1.5)
check(rws:GetAttribute("Track") == "Silverstone", "NEXT: Silverstone")
check(hr.Track.TrackName.Text == "SILVERSTONE" and gr.Track.TrackName.Text == "SILVERSTONE", "both see it")
hr.Len_Short.Activated:Fire()
R.run(0.5)
check(rws:GetAttribute("RoomLength") == "Short" and rws:GetAttribute("Laps") == 1, "SHORT: 1 lap")
check(gr.Len_Short.Title.Text == "SHORT 1" and gr.Track.Info.Text:find("1 lap", 1, true) ~= nil, "guest sees: " .. gr.Track.Info.Text)
hr.Prev.Activated:Fire()
R.run(1.5)
check(rws:GetAttribute("Track") == "Tampines" and rws:GetAttribute("Laps") == 2, "PREV: back to Tampines, SHORT there is 2 laps")
-- Bob gets ready
gr.Action.Activated:Fire()
R.run(0.5)
check(Guest:GetAttribute("Ready") == true and hr.Slot2.Status.Text == "READY", "Bob READY")
check(gr.Action.Title.Text == "NOT READY", "his button now takes it back")
check(hr.Status.Text == "Everyone is ready", "host: " .. hr.Status.Text)
gr.Action.Activated:Fire()
R.run(0.5)
check(Guest:GetAttribute("Ready") == false and hr.Slot2.Status.Text == "NOT READY", "and NOT READY again")
gr.Action.Activated:Fire()
R.run(0.5)
-- a third player turns up: not ready, so the host waits again
local Cara = R.addPlayer("Cara", 303)
R.run(1)
check(hr.Slot3.PlayerName.Text == "Cara" and hr.Slot3.Status.Text == "NOT READY", "Cara arrives, NOT READY")
hr.Action.Activated:Fire()
R.run(1)
check(rws:GetAttribute("RaceState") == "Lobby", "so no start yet")

print("== Kick ==")
hr.Slot3.Kick.Activated:Fire()
R.run(0.2)
check(hr.Slot3.Kick.Text == "SURE?" and #R.teleports == 0, "first tap only asks")
hr.Slot3.Kick.Activated:Fire()
R.run(1.5)
local out = lastTeleport(R)
check(out ~= nil and out.players[1] == Cara and out.code == nil and out.data.mode == "lobby", "second tap: Cara sent to a lobby")
check(out ~= nil and out.data.notice == "The host removed you from the room", "with a message for her there")
local entry4321 = live(R, "A1Rooms", "4321")
check(entry4321 ~= nil and type(entry4321.banned) == "table" and table.find(entry4321.banned, 303) ~= nil, "the code no longer lets her in")
R.removePlayer(Cara)
R.run(1)
local again = R.addPlayer("Cara", 303)
R.run(1)
out = lastTeleport(R)
check(out.players[1] == again and out.data.notice == "You were removed from this room", "coming back anyway: sent away again")
R.removePlayer(again)
R.run(1)

print("== START, the race, and back to the waiting room ==")
-- a short session for the test: qualifying ends at once, a 5 s race
local srvTrackData = Game.sharedModule(R, R.serverCtx, "TrackData")
srvTrackData.Tracks.Tampines.Qualifying = 0.5
local srvConfig = Game.sharedModule(R, R.serverCtx, "Config")
srvConfig.Race.QualiOvertime = 1
srvConfig.Race.MaxRaceTime = 5
R.run(0.5)
check(hr.Action.Title.Text == "START RACE" and hr.Status.Text == "Everyone is ready", "everyone ready again: " .. hr.Status.Text)
hr.Action.Activated:Fire()
R.run(0.5)
check(rws:GetAttribute("RaceState") == "Qualifying", "START: qualifying")
check(rws:GetAttribute("Ghost") == true, "with ghosts")
check(not hr.Visible and hudOf(Host).Enabled, "waiting room away, race HUD on")
local kh, kg = rws.Karts:FindFirstChild("Kart_101"), rws.Karts:FindFirstChild("Kart_202")
check(kh ~= nil and kg ~= nil, "both drivers in karts")
if kh and kg then
	local d = (kh.PrimaryPart.Position - kg.PrimaryPart.Position).Magnitude
	check(d < 3, string.format("both start from the same spot before the line (%.1f studs apart)", d))
end
check(hm.LobbyButton.Visible, "the LOBBY button while racing")
local back = R.run(40, function()
	return rws:GetAttribute("RaceState") == "Lobby"
end)
check(back, "after the podium: back to the waiting room")
R.run(0.5)
check(hr.Visible and #rws.Karts:GetChildren() == 0, "waiting room up, karts gone")
check(Guest:GetAttribute("Ready") ~= true and hr.Slot2.Status.Text == "NOT READY", "everyone NOT READY again")
check(rws:GetAttribute("Track") == "Tampines" and rws:GetAttribute("RoomLength") == "Short", "the host's track and length kept")
-- LEAVE
gr.Leave.Activated:Fire()
R.run(1.5)
out = lastTeleport(R)
check(out.players[1] == Guest and out.code == nil and out.data.mode == "lobby", "LEAVE: Bob back to a lobby")
R.removePlayer(Host)
R.run(1)
check(rws:GetAttribute("RoomHost") == 202 and rws:GetAttribute("RoomHostName") == "Bob", "the host left: Bob hosts now")
check(#R.errors == 0, "no script errors (room server)")

----------------------------------------------------------------------------
print("== The lobby: a removed player ==")
do
	-- the code refuses them
	G.memory.A1Rooms["7777"] = { value = { access = "access-7777", host = 1, banned = { 808 } }, expires = G.time + 600 }
	local Gus = G.addPlayer("Gus", 808)
	G.startClient(Gus, Game.ClientSpec)
	G.run(2)
	local mg = menuOf(Gus)
	mg.Home.Room.Activated:Fire()
	G.run(0.1)
	before = #G.teleports
	mg.Room.Code.Text = "7777"
	mg.Room.Join.Activated:Fire()
	G.run(1)
	check(#G.teleports == before and mg.Error.Text == "You were removed from this room", "the code refuses them: " .. mg.Error.Text)
	-- arriving in a lobby with the room's message
	G.localTeleportData = { mode = "lobby", notice = "The host removed you from the room" }
	local Ida = G.addPlayer("Ida", 909)
	G.startClient(Ida, Game.ClientSpec)
	G.run(2)
	local mi = menuOf(Ida)
	check(mi.Error.Visible and mi.Error.Text == "The host removed you from the room", "the message waits for them in the lobby")
	G.run(6)
	check(mi.Error.Visible, "long enough to read after the loading screen")
	G.localTeleportData = nil
	check(#G.errors == 0, "no script errors (lobby, removed player)")
end

----------------------------------------------------------------------------
print("== Studio: one server switches in place ==")
local S = Game.boot({ printErrors = true })
local sws = S.workspace
check(sws:GetAttribute("ServerMode") == "lobby", "Studio starts in the lobby")
local SA = S.addPlayer("Alice", 101)
local ctxS = S.startClient(SA, Game.ClientSpec)
S.run(3)
local ms = menuOf(SA)
check(ms.Home.Visible, "menu")
S.run(30, function()
	return #string.split(sws:GetAttribute("Tracks") or "", ",") >= 5
end)
ms.Home.Practice.Activated:Fire()
S.run(0.1)
ms.Practice.Cards.Card_Lakeside.Activated:Fire()
ms.Practice.Drive.Activated:Fire()
S.run(1)
check(SA.PlayerGui:FindFirstChild("A1Loading") ~= nil, "loading screen")
S.run(2)
check(sws:GetAttribute("ServerMode") == "practice" and sws:GetAttribute("Track") == "Lakeside", "PRACTICE: this server is practice on Lakeside now")
check(#S.teleports == 0, "no real teleport in Studio")
S.run(3)
check(SA.PlayerGui:FindFirstChild("A1Loading") == nil, "loading screen gone")
check(not ms.Home.Visible and ms.LobbyButton.Visible, "menu away, LOBBY button")
check(sws.Karts:FindFirstChild("Kart_101") ~= nil, "driving")
ms.LobbyButton.Activated:Fire()
ms.LobbyButton.Activated:Fire()
S.run(3)
check(sws:GetAttribute("ServerMode") == "lobby" and sws:GetAttribute("RaceState") == "Lobby", "LOBBY: back to the lobby")
check(#sws.Karts:GetChildren() == 0 and ms.Home.Visible, "kart gone, menu back")
check(sws.CurrentCamera.CameraType.Name == "Scriptable", "fly-by again")
ms.Home.Room.Activated:Fire()
S.run(0.1)
ms.Room.Create.Activated:Fire()
S.run(3)
check(sws:GetAttribute("ServerMode") == "room" and #(sws:GetAttribute("RoomCode") or "") == 4, "CREATE ROOM: a room here, code " .. tostring(sws:GetAttribute("RoomCode")))
check(sws:GetAttribute("RoomHost") == 101, "Alice hosts")
S.run(3)
check(sws:GetAttribute("RaceState") == "Lobby" and ms.RoomLobby.Visible, "its waiting room")
check(SA.PlayerGui:FindFirstChild("A1Loading") == nil, "loading screen gone")
ms.RoomLobby.Action.Activated:Fire()
S.run(1)
check(sws:GetAttribute("RaceState") == "Qualifying", "a room races with one driver (a test on your own)")
ms.LobbyButton.Activated:Fire()
ms.LobbyButton.Activated:Fire()
S.run(3)
check(sws:GetAttribute("ServerMode") == "lobby", "lobby again")
ms.Home.Race.Activated:Fire()
S.run(10, function()
	return sws:GetAttribute("ServerMode") == "race"
end)
check(sws:GetAttribute("ServerMode") == "race", "RACE in Studio: one driver is enough to go")
S.run(3)
check(sws:GetAttribute("RaceState") == "Practice" and hudOf(SA).Banner.Text.Text:find("WAITING FOR DRIVERS", 1, true) ~= nil, "a race server waits for a second driver: " .. hudOf(SA).Banner.Text.Text)
local _ = ctxS
-- Studio has one server: a kick there is a plain Player:Kick
ms.LobbyButton.Activated:Fire()
ms.LobbyButton.Activated:Fire()
S.run(3)
local SB = S.addPlayer("Bob", 202)
S.startClient(SB, Game.ClientSpec)
S.run(2)
ms.Home.Room.Activated:Fire()
S.run(0.1)
ms.Room.Create.Activated:Fire()
S.run(3)
check(sws:GetAttribute("ServerMode") == "room" and sws:GetAttribute("RaceState") == "Lobby", "Studio room with two players")
check(menuOf(SB).RoomLobby.Visible and ms.RoomLobby.Slot2.PlayerName.Text == "Bob", "Bob in slot 2")
ms.RoomLobby.Slot2.Kick.Activated:Fire()
ms.RoomLobby.Slot2.Kick.Activated:Fire()
S.run(1)
check(S.kicks[202] == "The host removed you from the room" and SB.Parent == nil, "KICK in Studio: Bob is disconnected with the message")
check(#S.errors == 0, "no script errors (Studio)")

print(string.format("%d/%d passed", pass, total))
