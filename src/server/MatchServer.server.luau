--!strict
-- 온라인 1:1 매칭과 경기 진행. 서버가 Match 시뮬레이션을 직접 돌리고(서버 권위),
-- 클라이언트는 입력만 보내고 스냅샷을 받아 그린다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Match = require(Shared:WaitForChild("Match"))

local TICK = Config.TICK
local SNAPSHOT_INTERVAL = 1 / Config.SNAPSHOT_RATE
local END_DELAY = 3 -- 경기가 끝난 뒤 결과를 보여주는 시간

-- 이 게임은 GUI로만 플레이하므로 3D 캐릭터는 필요 없다
Players.CharacterAutoLoads = false
for _, p in Players:GetPlayers() do
	if p.Character then
		p.Character:Destroy()
	end
end

local remotes = Instance.new("Folder")
remotes.Name = Config.REMOTES_FOLDER
local queueRemote = Instance.new("RemoteEvent")
queueRemote.Name = "Queue"
queueRemote.Parent = remotes
local inputRemote = Instance.new("RemoteEvent")
inputRemote.Name = "Input"
inputRemote.Parent = remotes
local eventRemote = Instance.new("RemoteEvent")
eventRemote.Name = "MatchEvent"
eventRemote.Parent = remotes
local snapshotRemote = Instance.new("UnreliableRemoteEvent")
snapshotRemote.Name = "Snapshot"
snapshotRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

type Session = {
	players: { Player },
	match: Match.Match,
	inputs: { Match.Input },
	accumulator: number,
	snapshotTimer: number,
	overTime: number,
	finished: boolean,
}

local waiting: { Player } = {}
local sessions: { Session } = {}
local sessionOf: { [Player]: Session } = {}
local sideOf: { [Player]: number } = {}

local function newInput(): Match.Input
	return { move = 0, jump = false, hit = false, drop = false, lookback = 0 }
end

local function sendAll(session: Session, kind: string, payload: any)
	for _, p in session.players do
		if p.Parent then
			eventRemote:FireClient(p, kind, payload)
		end
	end
end

-- 클라이언트가 스윙을 눌렀을 때 보고 있던 화면은 (왕복 지연 + 보간 지연)만큼 과거다
local function lookbackFor(p: Player): number
	local ok, ping = pcall(function()
		return p:GetNetworkPing()
	end)
	local rtt = if ok and typeof(ping) == "number" then ping else 0.1
	return math.clamp(rtt + Config.INTERP_DELAY + SNAPSHOT_INTERVAL / 2, 0, Config.MAX_LOOKBACK)
end

local function removeWaiting(p: Player)
	local index = table.find(waiting, p)
	if index then
		table.remove(waiting, index)
	end
end

local function startSession(a: Player, b: Player)
	local session: Session = {
		players = { a, b },
		match = Match.new({ seed = math.random(1, 2 ^ 30), firstServer = math.random(1, 2) }),
		inputs = { newInput(), newInput() },
		accumulator = 0,
		snapshotTimer = 0,
		overTime = 0,
		finished = false,
	}
	table.insert(sessions, session)
	local names = { a.DisplayName, b.DisplayName }
	local userIds = { a.UserId, b.UserId }
	for side, p in session.players do
		sessionOf[p] = session
		sideOf[p] = side
		eventRemote:FireClient(p, "start", { side = side, names = names, userIds = userIds })
	end
end

local function endSession(session: Session, winner: number, reason: string)
	if session.finished then
		return
	end
	session.finished = true
	sendAll(session, "end", { winner = winner, reason = reason })
	for _, p in session.players do
		if sessionOf[p] == session then
			sessionOf[p] = nil
			sideOf[p] = nil
		end
	end
	local index = table.find(sessions, session)
	if index then
		table.remove(sessions, index)
	end
end

local function forfeit(p: Player)
	local session = sessionOf[p]
	local side = sideOf[p]
	if session and side then
		endSession(session, 3 - side, "forfeit")
	end
end

queueRemote.OnServerEvent:Connect(function(p: Player, action: any)
	if action == "join" then
		if sessionOf[p] or table.find(waiting, p) then
			return
		end
		table.insert(waiting, p)
		eventRemote:FireClient(p, "queued", { count = #waiting })
		while #waiting >= 2 do
			local a = table.remove(waiting, 1) :: Player
			local b = table.remove(waiting, 1) :: Player
			startSession(a, b)
		end
	elseif action == "leave" then
		removeWaiting(p)
	elseif action == "forfeit" then
		forfeit(p)
	end
end)

inputRemote.OnServerEvent:Connect(function(p: Player, move: any, jump: any, hit: any, drop: any)
	local session = sessionOf[p]
	local side = sideOf[p]
	if not session or not side then
		return
	end
	local input = session.inputs[side]
	input.move = if typeof(move) == "number" and move == move then math.clamp(move, -1, 1) else 0
	input.jump = jump == true
	-- 눌린 순간 입력은 다음 틱에서 처리될 때까지 유지한다
	if hit == true then
		input.hit = true
	end
	if drop == true then
		input.drop = true
	end
end)

Players.PlayerRemoving:Connect(function(p: Player)
	removeWaiting(p)
	forfeit(p)
end)

RunService.Heartbeat:Connect(function(dt: number)
	for i = #sessions, 1, -1 do
		local session = sessions[i]
		local match = session.match
		local batch: { Match.Event } = {}

		session.accumulator = math.min(session.accumulator + dt, TICK * 8)
		while session.accumulator >= TICK do
			session.accumulator -= TICK
			for side, p in session.players do
				session.inputs[side].lookback = lookbackFor(p)
			end
			for _, event in match:step(TICK, session.inputs) do
				table.insert(batch, event)
			end
			for _, input in session.inputs do
				input.hit = false
				input.drop = false
			end
		end

		if #batch > 0 then
			sendAll(session, "events", { time = match.time, events = batch })
		end

		session.snapshotTimer += dt
		if session.snapshotTimer >= SNAPSHOT_INTERVAL then
			session.snapshotTimer = math.min(session.snapshotTimer - SNAPSHOT_INTERVAL, SNAPSHOT_INTERVAL)
			local packed = match:pack()
			for _, p in session.players do
				if p.Parent then
					snapshotRemote:FireClient(p, packed)
				end
			end
		end

		if match.phase == "over" then
			session.overTime += dt
			if session.overTime >= END_DELAY then
				endSession(session, match.winner, "finished")
			end
		end
	end
end)
