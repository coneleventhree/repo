--!strict
-- 한 경기의 전체 상태와 규칙. Roblox 인스턴스를 전혀 쓰지 않는 순수 로직이라
-- 클라이언트(AI 대전), 서버(온라인 대전), Lune 테스트에서 똑같이 돌아간다.
--
-- 진행 순서: serve(서브 대기) -> rally(랠리) -> point(득점 연출) -> serve ... -> over(경기 종료)
-- 1번 선수는 왼쪽 코트(오른쪽을 바라봄, dir = +1), 2번 선수는 오른쪽 코트(dir = -1).

local Config = require(script.Parent.Config)
local Shuttle = require(script.Parent.Shuttle)
local Shots = require(script.Parent.Shots)
local Rng = require(script.Parent.Rng)

local NET_X = Config.NET_X
local HALF = Config.COURT_HALF_LENGTH
local HISTORY_SIZE = math.ceil(Config.MAX_LOOKBACK / Config.TICK) + 4

export type Input = {
	move: number, -- -1 ~ 1 (화면 기준 왼쪽/오른쪽)
	jump: boolean, -- 누르고 있는 동안 true
	hit: boolean, -- 이번 틱에 강타 버튼을 눌렀는지
	drop: boolean, -- 이번 틱에 드롭 버튼을 눌렀는지
	lookback: number?, -- 온라인 지연 보정 (초)
}

export type Player = {
	side: number,
	dir: number,
	x: number,
	y: number,
	vx: number,
	vy: number,
	onGround: boolean,
	swingT: number, -- 스윙 시작 후 경과 시간, 스윙 중이 아니면 -1
	swingKind: string, -- "power" | "soft"
	swingStyle: number, -- 0 = 오버헤드, 1 = 언더핸드 (그리기용)
	swingHit: boolean,
	cooldown: number,
	lookback: number,
}

export type ShuttleState = {
	x: number,
	y: number,
	vx: number,
	vy: number,
	grounded: boolean,
	hitNet: boolean,
}

export type Event = {
	kind: string, -- "serveReady" | "hit" | "net" | "point" | "gameOver"
	side: number?,
	shot: string?,
	quality: number?,
	reason: string?, -- point: "in" | "out" | "net" | "fault" | "short"
	x: number?,
	y: number?,
}

export type Options = {
	pointsToWin: number?,
	winBy: number?,
	maxPoints: number?,
	seed: number?,
	firstServer: number?,
}

-- 렌더러가 필요로 하는 최소한의 상태. Match 자체도 이 모양을 만족한다.
export type PlayerView = {
	x: number,
	y: number,
	vx: number,
	dir: number,
	onGround: boolean,
	swingT: number,
	swingStyle: number,
}

export type View = {
	time: number,
	phase: string,
	server: number,
	winner: number,
	score: { number },
	shuttle: { x: number, y: number, vx: number, vy: number, grounded: boolean },
	players: { PlayerView },
}

type HistoryEntry = {
	time: number,
	active: boolean,
	hitCount: number,
	sx: number,
	sy: number,
	px: { number },
	py: { number },
}

type MatchData = {
	time: number,
	phase: string,
	phaseTimer: number,
	serveTimer: number,
	server: number,
	winner: number,
	score: { number },
	lastHitter: number,
	hitCount: number,
	lastReason: string,
	pointsToWin: number,
	winBy: number,
	maxPoints: number,
	players: { Player },
	shuttle: ShuttleState,
	rng: Rng.Rng,
	pending: { Event },
	history: { HistoryEntry },
	historyHead: number,
}

local Match = {}
Match.__index = Match

export type Match = typeof(setmetatable({} :: MatchData, Match))

local EMPTY_INPUT: Input = { move = 0, jump = false, hit = false, drop = false }

local PHASE_CODES = { serve = 1, rally = 2, point = 3, over = 4 }
local PHASE_NAMES = { "serve", "rally", "point", "over" }

local function approach(value: number, target: number, maxDelta: number): number
	if value < target then
		return math.min(value + maxDelta, target)
	end
	return math.max(value - maxDelta, target)
end

local function newPlayer(side: number): Player
	return {
		side = side,
		dir = if side == 1 then 1 else -1,
		x = 0,
		y = 0,
		vx = 0,
		vy = 0,
		onGround = true,
		swingT = -1,
		swingKind = "power",
		swingStyle = 0,
		swingHit = false,
		cooldown = 0,
		lookback = 0,
	}
end

-- 선수가 움직일 수 있는 x 범위
function Match.bounds(side: number): (number, number)
	if side == 1 then
		return Config.WALL_MARGIN, NET_X - Config.PLAYER_HALF_WIDTH
	end
	return NET_X + Config.PLAYER_HALF_WIDTH, Config.VIEW_WIDTH - Config.WALL_MARGIN
end

-- (px, py)에 서서 dir 방향을 보는 선수에게 (sx, sy)의 셔틀이 타격 범위 안인지와 스윗 스팟까지의 거리
function Match.zoneInfo(px: number, py: number, dir: number, sx: number, sy: number): (boolean, number)
	local dx = (sx - px) * dir
	local dy = sy - py
	local inZone = dx >= Config.HIT_ZONE_BACK
		and dx <= Config.HIT_ZONE_FRONT
		and dy >= Config.HIT_ZONE_LOW
		and dy <= Config.HIT_ZONE_HIGH
	local ex = dx - Config.SWEET_SPOT_X
	local ey = 0
	if dy < Config.SWEET_SPOT_LOW then
		ey = dy - Config.SWEET_SPOT_LOW
	elseif dy > Config.SWEET_SPOT_HIGH then
		ey = dy - Config.SWEET_SPOT_HIGH
	end
	return inZone, math.sqrt(ex * ex + ey * ey)
end

function Match.qualityFromDistance(dist: number): number
	return 1 - math.clamp(dist / Config.SWEET_RADIUS, 0, 1)
end

function Match.new(options: Options?): Match
	local opts: Options = options or {}
	local self = setmetatable(
		{
			time = 0,
			phase = "serve",
			phaseTimer = 0,
			serveTimer = 0,
			server = opts.firstServer or 1,
			winner = 0,
			score = { 0, 0 },
			lastHitter = 0,
			hitCount = 0,
			lastReason = "",
			pointsToWin = opts.pointsToWin or Config.POINTS_TO_WIN,
			winBy = opts.winBy or Config.WIN_BY,
			maxPoints = opts.maxPoints or Config.MAX_POINTS,
			players = { newPlayer(1), newPlayer(2) },
			shuttle = { x = 0, y = 0, vx = 0, vy = 0, grounded = false, hitNet = false },
			rng = Rng.new(opts.seed),
			pending = {},
			history = {},
			historyHead = 0,
		} :: MatchData,
		Match
	)
	self:setupServe()
	return self
end

function Match.emit(self: Match, event: Event)
	table.insert(self.pending, event)
end

function Match.holdShuttle(self: Match)
	local p = self.players[self.server]
	local s = self.shuttle
	s.x = p.x + p.dir * 0.45
	s.y = Config.SERVE_CONTACT_HEIGHT
	s.vx = 0
	s.vy = 0
	s.grounded = false
	s.hitNet = false
end

function Match.setupServe(self: Match)
	self.phase = "serve"
	self.serveTimer = 0
	self.lastHitter = 0
	self.hitCount = 0
	for _, p in self.players do
		local distance = if p.side == self.server then 2.6 else 3.3
		p.x = NET_X - p.dir * distance
		p.y = 0
		p.vx = 0
		p.vy = 0
		p.onGround = true
		p.swingT = -1
		p.swingHit = false
		p.cooldown = 0
	end
	self:holdShuttle()
	self:emit({ kind = "serveReady", side = self.server })
end

function Match.isWon(self: Match, side: number): boolean
	local mine, theirs = self.score[side], self.score[3 - side]
	return mine >= self.maxPoints or (mine >= self.pointsToWin and mine - theirs >= self.winBy)
end

function Match.updatePlayer(self: Match, p: Player, input: Input, dt: number, locked: boolean)
	local move = input.move
	if locked or move ~= move then -- move ~= move 는 NaN 검사
		move = 0
	end
	move = math.clamp(move, -1, 1)

	local accel = if p.onGround then Config.GROUND_ACCEL else Config.AIR_ACCEL
	p.vx = approach(p.vx, move * Config.PLAYER_SPEED, accel * dt)
	if not locked and input.jump and p.onGround then
		p.vy = Config.JUMP_VELOCITY
		p.onGround = false
	end
	if not p.onGround then
		p.vy -= Config.PLAYER_GRAVITY * dt
	end
	p.x += p.vx * dt
	p.y += p.vy * dt
	if p.y <= 0 then
		p.y = 0
		p.vy = 0
		p.onGround = true
	end
	local minX, maxX = Match.bounds(p.side)
	if p.x < minX or p.x > maxX then
		p.x = math.clamp(p.x, minX, maxX)
		p.vx = 0
	end

	if p.swingT >= 0 then
		p.swingT += dt
		if p.swingT >= Config.SWING_DURATION then
			p.swingT = -1
			p.cooldown = Config.SWING_COOLDOWN
		end
	elseif p.cooldown > 0 then
		p.cooldown = math.max(0, p.cooldown - dt)
	end

	if not locked and (input.hit or input.drop) and p.swingT < 0 and p.cooldown <= 0 then
		p.swingT = 0
		p.swingKind = if input.hit then "power" else "soft"
		p.swingHit = false
		p.swingStyle = if self.shuttle.y - p.y < 1.25 then 1 else 0
		local lookback = input.lookback or 0
		p.lookback = if lookback == lookback then math.clamp(lookback, 0, Config.MAX_LOOKBACK) else 0
	end
end

function Match.serve(self: Match, short: boolean)
	local p = self.players[self.server]
	local s = self.shuttle
	local kind: Shots.ShotKind = if short then "serveShort" else "serveHigh"
	s.vx, s.vy = Shots.plan(kind, s.x, s.y, p.dir, 0.85, self.rng)
	p.swingT = 0
	p.swingKind = if short then "soft" else "power"
	p.swingStyle = 1
	p.swingHit = true
	self.lastHitter = p.side
	self.hitCount = 1
	self.phase = "rally"
	self:emit({ kind = "hit", side = p.side, shot = kind, quality = 0.85, x = s.x, y = s.y })
end

function Match.historyAt(self: Match, ago: number): HistoryEntry?
	local wanted = self.time - ago
	local best: HistoryEntry? = nil
	local bestDiff = Config.TICK * 0.75
	for _, h in self.history do
		local diff = math.abs(h.time - wanted)
		if diff < bestDiff then
			best = h
			bestDiff = diff
		end
	end
	return best
end

function Match.recordHistory(self: Match)
	self.historyHead = self.historyHead % HISTORY_SIZE + 1
	local h = self.history[self.historyHead]
	if not h then
		h = { time = 0, active = false, hitCount = 0, sx = 0, sy = 0, px = { 0, 0 }, py = { 0, 0 } }
		self.history[self.historyHead] = h
	end
	local s = self.shuttle
	h.time = self.time
	h.active = self.phase == "rally" and not s.grounded
	h.hitCount = self.hitCount
	h.sx = s.x
	h.sy = s.y
	for i, p in self.players do
		h.px[i] = p.x
		h.py[i] = p.y
	end
end

function Match.tryHit(self: Match, p: Player)
	if p.swingT < 0 or p.swingT > Config.SWING_ACTIVE or p.swingHit then
		return
	end
	local s = self.shuttle
	if self.lastHitter == p.side or s.grounded then
		return -- 같은 선수가 연속으로 칠 수 없다
	end

	local quality = -1 -- 0 이상이면 맞힌 것
	local contactY = s.y
	local airborne = not p.onGround

	-- 상대 코트 깊숙이 있는 셔틀은 칠 수 없다
	if (s.x - NET_X) * p.dir <= Config.NET_REACH then
		local inZone, dist = Match.zoneInfo(p.x, p.y, p.dir, s.x, s.y)
		if inZone then
			quality = Match.qualityFromDistance(dist)
		end
	end

	-- 온라인 지연 보정: 클라이언트 화면에 보였던 과거 시점에서도 판정해서 더 좋은 쪽을 쓴다
	if p.lookback > 0 then
		local h = self:historyAt(p.lookback)
		if h and h.active and h.hitCount == self.hitCount and (h.sx - NET_X) * p.dir <= Config.NET_REACH then
			local hy = h.py[p.side]
			local inZone, dist = Match.zoneInfo(h.px[p.side], hy, p.dir, h.sx, h.sy)
			local q = Match.qualityFromDistance(dist)
			if inZone and q > quality then
				quality = q
				contactY = h.sy
				airborne = hy > 0.01
			end
		end
	end

	if quality < 0 then
		return
	end
	-- 빠르게 날아오는 셔틀(스매시 등)과 달리면서 치는 샷은 정확하게 받아치기 어렵다
	local incoming = math.sqrt(s.vx * s.vx + s.vy * s.vy)
	quality *= 1 - math.clamp((incoming - Config.FAST_SHOT_SPEED) / 18, 0, 0.6)
	quality *= 1 - 0.2 * math.min(math.abs(p.vx) / Config.PLAYER_SPEED, 1)

	local shot: Shots.ShotKind
	if p.swingKind == "power" then
		if airborne and contactY >= Config.SMASH_MIN_HEIGHT then
			shot = "smash"
		elseif contactY < Config.LOW_CONTACT_HEIGHT then
			shot = "lift"
		else
			shot = "clear"
		end
	else
		shot = if contactY < Config.LOW_CONTACT_HEIGHT then "net" else "drop"
	end

	s.vx, s.vy = Shots.plan(shot, s.x, s.y, p.dir, quality, self.rng)
	s.hitNet = false
	p.swingHit = true
	self.lastHitter = p.side
	self.hitCount += 1
	self:emit({ kind = "hit", side = p.side, shot = shot, quality = quality, x = s.x, y = s.y })
end

function Match.endRally(self: Match, landX: number)
	local s = self.shuttle
	local fromNet = math.abs(landX - NET_X)
	local inBounds = fromNet <= HALF
	local landedSide = if landX < NET_X then 1 else 2
	local loser: number
	local reason: string

	if self.hitCount == 1 and landedSide ~= self.server and inBounds and fromNet < Config.SHORT_SERVICE_DIST then
		loser, reason = self.server, "short"
	elseif not inBounds then
		loser, reason = self.lastHitter, "out"
	elseif landedSide == self.lastHitter then
		loser, reason = landedSide, if s.hitNet then "net" else "fault"
	else
		loser, reason = landedSide, "in"
	end
	if loser ~= 1 and loser ~= 2 then
		loser = landedSide
	end

	local winner = 3 - loser
	self.score[winner] += 1
	self.server = winner
	self.phase = "point"
	self.phaseTimer = Config.POINT_PAUSE
	self.lastReason = reason
	if self:isWon(winner) then
		self.winner = winner
	end
	self:emit({ kind = "point", side = winner, reason = reason, x = landX })
end

function Match.moveShuttle(self: Match, dt: number)
	local s = self.shuttle
	if s.grounded then
		return
	end
	local steps = Config.SHUTTLE_SUBSTEPS
	local h = dt / steps
	for _ = 1, steps do
		local px, py = s.x, s.y
		Shuttle.step(s, h)

		-- 네트(x = NET_X, 0 <= y <= NET_HEIGHT)에 걸리면 온 쪽으로 힘없이 떨어진다
		if px ~= s.x and (px - NET_X) * (s.x - NET_X) <= 0 then
			local a = (NET_X - px) / (s.x - px)
			local crossY = py + (s.y - py) * a
			if crossY <= Config.NET_HEIGHT and crossY >= 0 then
				local back = if px < NET_X then -1 else 1
				s.x = NET_X + back * 0.07
				s.y = crossY
				s.vx = -s.vx * 0.12
				s.vy = math.min(s.vy, 0) * 0.3
				s.hitNet = true
				self:emit({ kind = "net", x = s.x, y = s.y })
				px, py = s.x, s.y
			end
		end

		if s.y <= 0 then
			if py > 0 then
				local a = py / (py - s.y)
				s.x = px + (s.x - px) * a
			end
			s.y = 0
			s.vx = 0
			s.vy = 0
			s.grounded = true
			if self.phase == "rally" then
				self:endRally(s.x)
			end
			return
		end
	end
end

-- 고정 시간 간격(dt)으로 한 틱 진행하고, 이번 틱에 일어난 이벤트 목록을 돌려준다.
function Match.step(self: Match, dt: number, inputs: { Input }): { Event }
	self.time += dt
	local phase = self.phase

	for i, p in self.players do
		local locked = phase == "over" or (phase == "serve" and i == self.server)
		self:updatePlayer(p, inputs[i] or EMPTY_INPUT, dt, locked)
	end

	if phase == "serve" then
		local input = inputs[self.server] or EMPTY_INPUT
		self:holdShuttle()
		self.serveTimer += dt
		if input.hit or input.drop or self.serveTimer >= Config.SERVE_TIMEOUT then
			self:serve(input.drop and not input.hit)
		end
	elseif phase == "rally" then
		for _, p in self.players do
			self:tryHit(p)
		end
		self:moveShuttle(dt)
	elseif phase == "point" then
		self:moveShuttle(dt)
		self.phaseTimer -= dt
		if self.phaseTimer <= 0 then
			if self.winner ~= 0 then
				self.phase = "over"
				self:emit({ kind = "gameOver", side = self.winner })
			else
				self:setupServe()
			end
		end
	end

	self:recordHistory()
	local events = self.pending
	self.pending = {}
	return events
end

-- 네트워크 전송용 압축 표현
function Match.pack(self: Match): { number }
	local s = self.shuttle
	local a, b = self.players[1], self.players[2]
	return {
		self.time,
		PHASE_CODES[self.phase] or 1,
		self.server,
		self.score[1],
		self.score[2],
		self.winner,
		s.x,
		s.y,
		s.vx,
		s.vy,
		if s.grounded then 1 else 0,
		a.x,
		a.y,
		a.vx,
		a.swingT,
		a.swingStyle,
		if a.onGround then 1 else 0,
		b.x,
		b.y,
		b.vx,
		b.swingT,
		b.swingStyle,
		if b.onGround then 1 else 0,
	}
end

local function num(value: any, default: number): number
	if typeof(value) == "number" and value == value then
		return value
	end
	return default
end

function Match.unpack(data: { any }): View
	local function playerAt(offset: number, dir: number): PlayerView
		return {
			x = num(data[offset], 0),
			y = num(data[offset + 1], 0),
			vx = num(data[offset + 2], 0),
			dir = dir,
			swingT = num(data[offset + 3], -1),
			swingStyle = num(data[offset + 4], 0),
			onGround = num(data[offset + 5], 1) == 1,
		}
	end
	return {
		time = num(data[1], 0),
		phase = PHASE_NAMES[num(data[2], 1)] or "serve",
		server = num(data[3], 1),
		score = { num(data[4], 0), num(data[5], 0) },
		winner = num(data[6], 0),
		shuttle = {
			x = num(data[7], NET_X),
			y = num(data[8], 0),
			vx = num(data[9], 0),
			vy = num(data[10], 0),
			grounded = num(data[11], 0) == 1,
		},
		players = { playerAt(12, 1), playerAt(18, -1) },
	}
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 두 스냅샷 사이를 보간한다 (t = 0 이면 a, 1 이면 b)
function Match.lerpView(a: View, b: View, t: number): View
	if a.phase ~= b.phase or t >= 1 then
		return b
	end
	if t <= 0 then
		return a
	end
	local players = {}
	for i, pb in b.players do
		local pa = a.players[i]
		local swingT = if t < 0.5 then pa.swingT else pb.swingT
		if pa.swingT >= 0 and pb.swingT >= pa.swingT then
			swingT = lerp(pa.swingT, pb.swingT, t)
		end
		players[i] = {
			x = lerp(pa.x, pb.x, t),
			y = lerp(pa.y, pb.y, t),
			vx = lerp(pa.vx, pb.vx, t),
			dir = pb.dir,
			onGround = pb.onGround,
			swingT = swingT,
			swingStyle = if t < 0.5 then pa.swingStyle else pb.swingStyle,
		}
	end
	local sa, sb = a.shuttle, b.shuttle
	return {
		time = lerp(a.time, b.time, t),
		phase = b.phase,
		server = b.server,
		winner = b.winner,
		score = b.score,
		shuttle = if sa.grounded ~= sb.grounded
			then sb
			else {
				x = lerp(sa.x, sb.x, t),
				y = lerp(sa.y, sb.y, t),
				vx = lerp(sa.vx, sb.vx, t),
				vy = lerp(sa.vy, sb.vy, t),
				grounded = sb.grounded,
			},
		players = players,
	}
end

return Match
