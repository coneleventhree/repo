--!strict
-- AI 상대. 사람과 똑같이 Match.Input만 만들어 내기 때문에 규칙상 반칙을 하지 않는다.
-- 상대가 친 뒤 반응 시간이 지나면 셔틀의 궤적을 예측해서 그 아래로 이동하고,
-- 셔틀이 스윗 스팟 근처에 오면 스윙한다. 난이도는 반응 속도, 위치 오차, 이동 속도 등으로 조절한다.

local Config = require(script.Parent.Config)
local Shuttle = require(script.Parent.Shuttle)
local Match = require(script.Parent.Match)
local Rng = require(script.Parent.Rng)

export type Difficulty = {
	reaction: number, -- 상대가 친 뒤 움직이기 시작할 때까지의 시간
	positionError: number, -- 예측 위치 오차 (월드 단위)
	speedScale: number, -- 최대 이동 속도 비율
	smashChance: number, -- 높은 공이 올 때 점프 스매시를 시도할 확률
	dropChance: number, -- 드롭을 선택하는 기본 확률
	swingWindow: number, -- 스윗 스팟과 이 거리 안이면 스윙
	mistakeChance: number, -- 날아오는 공마다 크게 잘못 판단할 확률
	judgeOut: number, -- 아웃될 공을 알아보고 치지 않을 확률
}

local Bot = {}
Bot.__index = Bot

Bot.Difficulties = {
	Easy = {
		reaction = 0.34,
		positionError = 0.75,
		speedScale = 0.72,
		smashChance = 0.1,
		dropChance = 0.15,
		swingWindow = 0.6,
		mistakeChance = 0.16,
		judgeOut = 0.3,
	} :: Difficulty,
	Normal = {
		reaction = 0.24,
		positionError = 0.4,
		speedScale = 0.86,
		smashChance = 0.45,
		dropChance = 0.3,
		swingWindow = 0.45,
		mistakeChance = 0.07,
		judgeOut = 0.65,
	} :: Difficulty,
	Hard = {
		reaction = 0.15,
		positionError = 0.25,
		speedScale = 1,
		smashChance = 0.8,
		dropChance = 0.35,
		swingWindow = 0.3,
		mistakeChance = 0.03,
		judgeOut = 0.9,
	} :: Difficulty,
}

type Plan = {
	targetX: number,
	jumpAt: number, -- 이 시간(match.time)이 되면 점프, 점프 안 하면 math.huge
}

type BotData = {
	side: number,
	difficulty: Difficulty,
	rng: Rng.Rng,
	seenHitCount: number,
	seenPhase: string,
	planReadyAt: number,
	plan: Plan?,
	leaving: boolean,
	swung: boolean,
	serveAt: number,
	errorOffset: number,
	lastDist: number,
}

export type Bot = typeof(setmetatable({} :: BotData, Bot))

local NET_X = Config.NET_X
local PREDICT_DT = 1 / 120
local JUMP_RISE_TIME = Config.JUMP_VELOCITY / Config.PLAYER_GRAVITY
local JUMP_HEIGHT = Config.JUMP_VELOCITY * Config.JUMP_VELOCITY / (2 * Config.PLAYER_GRAVITY)
local CONTACT_Y = 1.9 -- 땅에 서서 칠 때 노리는 타점 높이

function Bot.new(side: number, difficulty: Difficulty | string, seed: number?): Bot
	local diff: Difficulty
	if typeof(difficulty) == "string" then
		diff = (Bot.Difficulties :: any)[difficulty] or Bot.Difficulties.Normal
	else
		diff = difficulty
	end
	return setmetatable(
		{
			side = side,
			difficulty = diff,
			rng = Rng.new(seed or (side * 7919 + 17)),
			seenHitCount = -1,
			seenPhase = "",
			planReadyAt = 0,
			plan = nil,
			leaving = false,
			swung = false,
			serveAt = 0,
			errorOffset = 0,
			lastDist = math.huge,
		} :: BotData,
		Bot
	)
end

-- 셔틀이 내 코트에서 높이 contactY 아래로 내려오는 지점을 예측한다.
local function predictContact(match: Match.Match, dir: number, contactY: number): (number?, number?, number?)
	local s = match.shuttle
	local body = { x = s.x, y = s.y, vx = s.vx, vy = s.vy }
	local t = 0
	local lastMineX, lastMineT, lastMineY = nil, nil, nil
	while t < 4 do
		local px = body.x
		Shuttle.step(body, PREDICT_DT)
		t += PREDICT_DT
		-- 네트에 걸리는 궤적이면 넘어오지 않는다
		if (px - NET_X) * (body.x - NET_X) < 0 and body.y <= Config.NET_HEIGHT then
			return nil, nil, nil
		end
		local mine = (body.x - NET_X) * dir < 0
		if mine and body.y > Config.HIT_ZONE_LOW + 0.05 then
			lastMineX, lastMineT, lastMineY = body.x, t, body.y
			if body.vy < 0 and body.y <= contactY then
				return body.x, t, body.y
			end
		end
		if body.y <= 0 then
			break
		end
	end
	-- 원하는 높이까지 오지 않는 낮은 공이면 바닥에 닿기 직전 지점
	return lastMineX, lastMineT, lastMineY
end

function Bot.makePlan(self: Bot, match: Match.Match)
	local me = match.players[self.side]
	local diff = self.difficulty
	local dir = me.dir
	local jumpReach = CONTACT_Y + JUMP_HEIGHT * 0.9

	-- 아웃될 공은 치지 않고 보낸다
	local s = match.shuttle
	local flight = Shuttle.simulate(s.x, s.y, s.vx, s.vy)
	if math.abs(flight.landX - NET_X) > Config.COURT_HALF_LENGTH + 0.1 and self.rng:chance(diff.judgeOut) then
		self.leaving = true
		self.plan = nil
		return
	end

	local plan: Plan? = nil
	-- 높이 뜬 공이면 점프 스매시를 노린다
	if self.rng:chance(diff.smashChance) then
		local x, t, y = predictContact(match, dir, jumpReach)
		if x and t and y and t > JUMP_RISE_TIME and y >= jumpReach - 0.3 then
			plan = { targetX = x - dir * Config.SWEET_SPOT_X, jumpAt = match.time + t - JUMP_RISE_TIME * 0.95 }
		end
	end
	if not plan then
		local x = predictContact(match, dir, CONTACT_Y)
		if x then
			plan = { targetX = x - dir * Config.SWEET_SPOT_X, jumpAt = math.huge }
		end
	end
	if plan then
		local minX, maxX = Match.bounds(self.side)
		plan.targetX = math.clamp(plan.targetX + self.errorOffset, minX, maxX)
	end
	self.plan = plan
end

local function moveToward(me: Match.Player, targetX: number, speedScale: number): number
	local dx = targetX - me.x
	if math.abs(dx) < 0.06 then
		return 0
	end
	return math.clamp(dx * 4, -1, 1) * speedScale
end

function Bot.chooseSoft(self: Bot, match: Match.Match): boolean
	local opponent = match.players[3 - self.side]
	local oppDepth = math.abs(opponent.x - NET_X)
	local chance = self.difficulty.dropChance
	if oppDepth > 4.5 then
		chance += 0.3 -- 상대가 뒤에 있으면 네트 앞으로 떨어뜨린다
	elseif oppDepth < 2.8 then
		chance -= 0.2 -- 상대가 네트 앞이면 뒤로 길게
	end
	return self.rng:chance(chance)
end

function Bot.update(self: Bot, match: Match.Match): Match.Input
	local input: Match.Input = { move = 0, jump = false, hit = false, drop = false }
	local me = match.players[self.side]
	local diff = self.difficulty
	local baseX = NET_X - me.dir * 3.4

	if match.phase ~= self.seenPhase then
		self.seenPhase = match.phase
		if match.phase == "serve" then
			self.serveAt = match.time + self.rng:range(0.7, 1.5)
		end
	end

	if match.phase == "serve" then
		if match.server == self.side then
			if match.time >= self.serveAt then
				if self.rng:chance(0.3) then
					input.drop = true
				else
					input.hit = true
				end
			end
		else
			input.move = moveToward(me, baseX, diff.speedScale)
		end
		return input
	end

	if match.phase ~= "rally" then
		input.move = moveToward(me, baseX, diff.speedScale * 0.5)
		return input
	end

	-- 새 샷이 나왔는지 확인
	if match.hitCount ~= self.seenHitCount then
		self.seenHitCount = match.hitCount
		self.plan = nil
		self.leaving = false
		self.swung = false
		self.lastDist = math.huge
		self.planReadyAt = match.time + diff.reaction * self.rng:range(0.8, 1.25)
		if self.rng:chance(diff.mistakeChance) then
			-- 가끔은 낙하 지점을 크게 잘못 읽는다
			local sign = if self.rng:chance(0.5) then 1 else -1
			self.errorOffset = sign * self.rng:range(1.1, 1.9)
		else
			self.errorOffset = self.rng:spread() * diff.positionError
		end
	end

	if match.lastHitter == self.side then
		-- 내가 친 공이 넘어가는 중: 코트 중앙으로 복귀
		input.move = moveToward(me, baseX, diff.speedScale)
		return input
	end

	if match.time < self.planReadyAt then
		-- 아직 반응 전: 하던 대로 중앙 쪽으로
		input.move = moveToward(me, baseX, diff.speedScale * 0.6)
		return input
	end

	if not self.plan and not self.leaving then
		self:makePlan(match)
	end
	if self.leaving then
		input.move = moveToward(me, baseX, diff.speedScale * 0.5)
		return input
	end
	local plan = self.plan
	if plan then
		input.move = moveToward(me, plan.targetX, diff.speedScale)
		if me.onGround and match.time >= plan.jumpAt and math.abs(me.x - plan.targetX) < 0.8 then
			input.jump = true
		end
	end

	-- 셔틀이 스윗 스팟에 가장 가까워질 때쯤 스윙
	local s = match.shuttle
	local inZone, dist = Match.zoneInfo(me.x, me.y, me.dir, s.x, s.y)
	if inZone and not self.swung and me.swingT < 0 and me.cooldown <= 0 then
		local leaving = dist > self.lastDist
		if dist <= diff.swingWindow or leaving then
			self.swung = true
			local smash = not me.onGround and s.y >= Config.SMASH_MIN_HEIGHT
			if not smash and self:chooseSoft(match) then
				input.drop = true
			else
				input.hit = true
			end
		end
	end
	self.lastDist = if inZone then dist else math.huge
	-- 헛스윙했으면 셔틀이 아직 내 쪽에 있는 동안 다시 시도할 수 있게 한다
	if self.swung and me.swingT < 0 and not me.swingHit and not inZone then
		self.swung = false
	end

	return input
end

return Bot
