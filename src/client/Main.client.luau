--!strict
-- 클라이언트 진입점. 화면 상태를 관리한다.
--   demo   : 메뉴 뒤에서 AI끼리 경기하는 배경 화면
--   local  : 내 기기에서 AI와 대결 (시뮬레이션을 직접 돌린다)
--   queue  : 온라인 상대를 기다리는 중 (배경은 demo)
--   online : 서버가 돌리는 경기를 스냅샷으로 받아 보간해서 그린다
--   result : 경기 결과 화면

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Match = require(Shared:WaitForChild("Match"))
local Bot = require(Shared:WaitForChild("Bot"))

local Renderer = require(script.Parent:WaitForChild("Renderer"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local Interface = require(script.Parent:WaitForChild("Interface"))
local Strings = require(script.Parent:WaitForChild("Strings"))

local TICK = Config.TICK
local MY_COLOR = Color3.fromRGB(70, 140, 255)
local OPPONENT_COLOR = Color3.fromRGB(240, 80, 80)
local IDLE: Match.Input = { move = 0, jump = false, hit = false, drop = false }

-- 캐릭터 없이 GUI로만 플레이하므로 기본 조작(터치 조이스틱 등)과 불필요한 코어 UI를 끈다
task.spawn(function()
	pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if module and module:IsA("ModuleScript") then
			local playerModule: any = (require :: any)(module)
			playerModule:GetControls():Disable()
		end
	end)
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

type Remotes = {
	queue: RemoteEvent,
	input: RemoteEvent,
	matchEvent: RemoteEvent,
	snapshot: UnreliableRemoteEvent,
}

type TimedEvent = { time: number, event: Match.Event }

local renderer = Renderer.new(playerGui)
local controls = Controls.new(playerGui)
local interface: Interface.Interface

local mode = "demo"
local difficulty = "Normal"
local lastGameOnline = false

-- 로컬 시뮬레이션 (demo, local)
local match = Match.new()
local bots: { [number]: Bot.Bot } = {}
local accumulator = 0
local previousView = Match.unpack(match:pack())
local currentView = previousView

-- 온라인
local remotes: Remotes? = nil
local onlineSide = 1
local snapshots: { Match.View } = {}
local clockOffset: number? = nil
local pendingEvents: { TimedEvent } = {}
local lastSentMove, lastSentJump = 0, false

local function resetLocalMatch(newBots: { [number]: Bot.Bot })
	match = Match.new({ seed = math.random(1, 2 ^ 30) })
	bots = newBots
	accumulator = 0
	previousView = Match.unpack(match:pack())
	currentView = previousView
end

local function startDemo()
	mode = "demo"
	controls:setEnabled(false)
	resetLocalMatch({
		[1] = Bot.new(1, "Hard", math.random(1, 10000)),
		[2] = Bot.new(2, "Normal", math.random(1, 10000)),
	})
	renderer:setPlayers({ { name = "", color = MY_COLOR }, { name = "", color = OPPONENT_COLOR } }, false)
end

local function showMenu()
	startDemo()
	interface:showMenu()
end

local function scoreText(view: Match.View, mySide: number): string
	return string.format("%d : %d", view.score[mySide], view.score[3 - mySide])
end

-- 점수 문구, 이펙트 등 이벤트 공통 처리
local function presentEvent(event: Match.Event, mySide: number)
	renderer:handleEvent(event)
	if event.kind == "point" then
		local won = event.side == mySide
		local texts: { [string]: string } = if won then Strings.PointWon else Strings.PointLost
		interface:showMessage(
			texts[event.reason or "in"] or "",
			if won then Color3.fromRGB(120, 255, 160) else Color3.fromRGB(255, 120, 120)
		)
	end
end

local function updateHint(view: Match.View, mySide: number)
	if view.phase == "serve" and view.server == mySide then
		interface:setHint(if controls:isTouch() then Strings.ServeHintTouch else Strings.ServeHint)
	else
		interface:setHint("")
	end
end

-- AI 대결 -------------------------------------------------------------------

local function startLocal(level: string)
	difficulty = level
	lastGameOnline = false
	mode = "local"
	resetLocalMatch({ [2] = Bot.new(2, level, math.random(1, 10000)) })
	local label = (Strings :: any)[level] or level
	local names = { player.DisplayName, "AI (" .. label .. ")" }
	renderer:setPlayers({
		{ name = names[1], userId = player.UserId, color = MY_COLOR },
		{ name = names[2], color = OPPONENT_COLOR },
	}, false)
	interface:showGame(names, { MY_COLOR, OPPONENT_COLOR }, false)
	controls:setEnabled(true)
end

local function stepLocal(dt: number): Match.View
	accumulator += dt
	local steps = 0
	while accumulator >= TICK do
		accumulator -= TICK
		steps += 1
		if steps > 6 then
			accumulator = 0 -- 너무 밀렸으면 따라잡기를 포기한다
			break
		end
		local inputs = {}
		for side = 1, 2 do
			local bot = bots[side]
			if bot then
				inputs[side] = bot:update(match)
			elseif mode == "local" then
				inputs[side] = controls:sample(false)
			else
				inputs[side] = IDLE
			end
		end
		previousView = currentView
		local events = match:step(TICK, inputs)
		currentView = Match.unpack(match:pack())
		for _, event in events do
			if mode == "demo" or mode == "queue" then
				renderer:handleEvent(event)
			else
				presentEvent(event, 1)
				if event.kind == "gameOver" and mode == "local" then
					mode = "result"
					controls:setEnabled(false)
					interface:showResult(event.side == 1, scoreText(currentView, 1), nil, false)
				end
			end
		end
	end
	if (mode == "demo" or mode == "queue") and match.phase == "over" then
		local waiting = mode == "queue"
		startDemo()
		if waiting then
			mode = "queue"
		end
	end
	return Match.lerpView(previousView, currentView, accumulator / TICK)
end

-- 온라인 대결 ---------------------------------------------------------------

local function playOnline()
	local net = remotes
	if net then
		-- 응답(start)은 빨라도 다음 프레임에 오므로 먼저 보내도 된다
		net.queue:FireServer("join")
		lastGameOnline = true
		if mode ~= "demo" and mode ~= "queue" then
			startDemo()
		end
		mode = "queue"
		interface:showQueue()
	end
end

local function cancelQueue()
	local net = remotes
	if net then
		net.queue:FireServer("leave")
	end
	showMenu()
end

local function pushSnapshot(data: { any })
	local view = Match.unpack(data)
	local offset = view.time - os.clock()
	local current = clockOffset
	if current == nil or math.abs(offset - current) > 0.5 then
		clockOffset = offset
	elseif offset > current then
		clockOffset = current + (offset - current) * 0.3 -- 가장 빨리 도착한 스냅샷 쪽으로 빠르게
	else
		clockOffset = current + (offset - current) * 0.02
	end
	local last = snapshots[#snapshots]
	if last and view.time <= last.time then
		return -- 순서가 뒤바뀐 스냅샷은 버린다
	end
	table.insert(snapshots, view)
	while #snapshots > 40 do
		table.remove(snapshots, 1)
	end
end

local function onlineRenderTime(): number?
	local offset = clockOffset
	if offset then
		return os.clock() + offset - Config.INTERP_DELAY
	end
	return nil
end

local function sampleOnline(renderTime: number): Match.View?
	while #snapshots >= 3 and snapshots[2].time <= renderTime do
		table.remove(snapshots, 1)
	end
	local a, b = snapshots[1], snapshots[2]
	if not a then
		return nil
	end
	if not b or renderTime <= a.time then
		return a
	end
	return Match.lerpView(a, b, math.min((renderTime - a.time) / (b.time - a.time), 1))
end

local function sendInput()
	local input = controls:sample(renderer.mirror)
	local changed = input.hit or input.drop or input.move ~= lastSentMove or input.jump ~= lastSentJump
	local net = remotes
	if net and changed then
		net.input:FireServer(input.move, input.jump, input.hit, input.drop)
		lastSentMove, lastSentJump = input.move, input.jump
	end
end

local function startOnline(payload: any)
	if mode ~= "queue" then
		-- 대기를 취소한 직후에 매칭된 경우: 서버의 경기를 바로 끝낸다
		local net = remotes
		if net then
			net.queue:FireServer("forfeit")
		end
		return
	end
	onlineSide = if payload.side == 2 then 2 else 1
	local names = { tostring(payload.names[1]), tostring(payload.names[2]) }
	local userIds = { tonumber(payload.userIds[1]), tonumber(payload.userIds[2]) }
	local infos = {}
	for side = 1, 2 do
		infos[side] = {
			name = names[side],
			userId = userIds[side],
			color = if side == onlineSide then MY_COLOR else OPPONENT_COLOR,
		}
	end
	renderer:setPlayers(infos, onlineSide == 2)
	interface:showGame({ names[onlineSide], names[3 - onlineSide] }, { MY_COLOR, OPPONENT_COLOR }, true)
	table.clear(snapshots)
	table.clear(pendingEvents)
	clockOffset = nil
	lastSentMove, lastSentJump = 0, false
	mode = "online"
	controls:setEnabled(true)
end

local function finishOnline(won: boolean, subtitle: string?)
	local view = snapshots[#snapshots]
	mode = "result"
	controls:setEnabled(false)
	interface:showResult(won, if view then scoreText(view, onlineSide) else "", subtitle, true)
end

local function onMatchEvent(kind: string, payload: any)
	if kind == "start" then
		startOnline(payload)
	elseif kind == "events" and mode == "online" then
		for _, event in payload.events do
			table.insert(pendingEvents, { time = payload.time, event = event })
		end
	elseif kind == "end" and (mode == "online" or (mode == "result" and lastGameOnline)) then
		if payload.reason == "forfeit" and mode == "online" then
			finishOnline(payload.winner == onlineSide, Strings.OpponentLeft)
		end
	end
end

local function forfeit()
	if mode == "online" then
		local net = remotes
		if net then
			net.queue:FireServer("forfeit")
		end
	end
	showMenu()
end

local function rematch()
	if lastGameOnline then
		playOnline()
	else
		startLocal(difficulty)
	end
end

interface = Interface.new(playerGui, {
	playAi = startLocal,
	playOnline = playOnline,
	cancelQueue = cancelQueue,
	menu = function()
		if mode == "queue" then
			cancelQueue()
		else
			showMenu()
		end
	end,
	rematch = rematch,
	forfeit = forfeit,
})

-- 서버가 만든 리모트를 기다린다 (서버 스크립트가 없으면 AI 대결만 가능)
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER, 30)
	if not folder then
		warn("[Badminton] 서버 리모트를 찾지 못해 온라인 대결을 사용할 수 없습니다.")
		return
	end
	local net: Remotes = {
		queue = folder:WaitForChild("Queue") :: RemoteEvent,
		input = folder:WaitForChild("Input") :: RemoteEvent,
		matchEvent = folder:WaitForChild("MatchEvent") :: RemoteEvent,
		snapshot = folder:WaitForChild("Snapshot") :: UnreliableRemoteEvent,
	}
	net.matchEvent.OnClientEvent:Connect(onMatchEvent)
	net.snapshot.OnClientEvent:Connect(function(data: any)
		if (mode == "online" or mode == "result") and typeof(data) == "table" then
			pushSnapshot(data)
		end
	end)
	remotes = net
end)

-- 매 프레임 ------------------------------------------------------------------

RunService.RenderStepped:Connect(function(frameDt: number)
	local dt = math.min(frameDt, 0.1)
	if mode == "online" or (mode == "result" and lastGameOnline) then
		if mode == "online" then
			sendInput()
		end
		local renderTime = onlineRenderTime()
		if renderTime then
			-- 이벤트도 화면에 보이는 시점에 맞춰 늦게 보여준다
			while pendingEvents[1] and pendingEvents[1].time <= renderTime do
				local timed = table.remove(pendingEvents, 1) :: TimedEvent
				presentEvent(timed.event, onlineSide)
				if timed.event.kind == "gameOver" and mode == "online" then
					finishOnline(timed.event.side == onlineSide, nil)
				end
			end
			local view = sampleOnline(renderTime)
			if view then
				renderer:draw(view, dt)
				interface:setScore(view, onlineSide)
				if mode == "online" then
					updateHint(view, onlineSide)
				end
			end
		end
	else
		local view = stepLocal(dt)
		renderer:draw(view, dt)
		if mode == "local" or mode == "result" then
			interface:setScore(view, 1)
		end
		if mode == "local" then
			updateHint(view, 1)
		end
	end
	interface:update(dt)
end)

showMenu()
