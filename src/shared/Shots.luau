--!strict
-- 샷 종류별로 목표 지점을 정하고, 셔틀콕 물리로 역산해서 발사 속도를 구한다.
-- quality(0~1)는 스윗 스팟에 얼마나 가깝게 맞혔는지이며, 낮을수록 오차가 커진다.

local Config = require(script.Parent.Config)
local Shuttle = require(script.Parent.Shuttle)
local Rng = require(script.Parent.Rng)

local Shots = {}

export type ShotKind = "clear" | "lift" | "drop" | "net" | "smash" | "serveHigh" | "serveShort"

local NET_X = Config.NET_X
local HALF = Config.COURT_HALF_LENGTH
local DEG = math.pi / 180

-- 코트 깊숙이 보내는 높은 샷. 필요한 속도가 너무 크면(멀리서 치면) 각도를 낮춰서
-- 셔틀이 화면 위로 너무 높이 뜨지 않게 한다.
local function deepArc(
	x0: number,
	y0: number,
	dir: number,
	distance: number,
	angleDeg: number,
	maxSpeed: number
): (number, number)
	local angle = angleDeg
	local speed = Shuttle.solveSpeed(x0, y0, angle * DEG, dir, distance)
	while speed > maxSpeed and angle > 26 do
		angle -= 4
		speed = Shuttle.solveSpeed(x0, y0, angle * DEG, dir, distance)
	end
	return Shuttle.launch(angle * DEG, speed, dir)
end

-- 목표 지점에 떨어지면서 네트를 margin 이상 넘는 가장 낮은 각도를 고른다.
-- 낮은 각도일수록 빠르고 공격적인 샷이 된다. 10도 간격으로 훑은 뒤 경계를 이분 탐색한다.
local function lowestClearingArc(
	x0: number,
	y0: number,
	dir: number,
	distance: number,
	fromDeg: number,
	toDeg: number,
	margin: number
): (number, number)
	local function try(deg: number): (number, boolean)
		local speed, flight = Shuttle.solveSpeed(x0, y0, deg * DEG, dir, distance)
		return speed, Shuttle.clearsNet(flight, dir, margin)
	end

	local failedDeg = fromDeg
	for deg = fromDeg, toDeg, 10 do
		local speed, ok = try(deg)
		if ok then
			if deg == fromDeg then
				return Shuttle.launch(deg * DEG, speed, dir)
			end
			local lo, hi, hiSpeed = failedDeg, deg, speed
			for _ = 1, 4 do
				local mid = (lo + hi) / 2
				local midSpeed, midOk = try(mid)
				if midOk then
					hi, hiSpeed = mid, midSpeed
				else
					lo = mid
				end
			end
			return Shuttle.launch(hi * DEG, hiSpeed, dir)
		end
		failedDeg = deg
	end
	-- 너무 멀거나 낮은 타점이라 짧게 넘길 수 없으면 높게 띄워 넘긴다
	return deepArc(x0, y0, dir, distance, 45, 36)
end

-- 품질이 낮을수록 실수(아웃, 네트)가 나올 확률이 급격히 커진다
local function blunder(rng: Rng.Rng, err: number, scale: number): boolean
	return rng:chance(err * err * scale)
end

-- dir: 샷을 보내는 방향 (+1 = 오른쪽 코트로)
function Shots.plan(
	kind: ShotKind,
	x0: number,
	y0: number,
	dir: number,
	quality: number,
	rng: Rng.Rng
): (number, number)
	local err = 1 - math.clamp(quality, 0, 1)
	local backLine = NET_X + dir * HALF

	if kind == "clear" or kind == "lift" then
		-- 품질이 낮으면 대부분 짧게(코트 중간에) 떨어지고, 가끔 길게 나가 아웃이 된다
		local targetX = backLine - dir * (rng:range(0.6, 1.6) + err * rng:range(0, 4)) + dir * rng:spread() * err * 2.2
		if blunder(rng, err, 0.6) then
			targetX = backLine + dir * rng:range(0.15, 1.3)
		end
		if kind == "lift" then
			return deepArc(x0, y0, dir, (targetX - x0) * dir, rng:range(52, 60), 36)
		end
		return deepArc(x0, y0, dir, (targetX - x0) * dir, rng:range(44, 52), 34)
	elseif kind == "serveHigh" then
		local targetX = backLine - dir * rng:range(0.5, 1.4) + dir * rng:spread() * err * 2
		return deepArc(x0, y0, dir, (targetX - x0) * dir, rng:range(52, 58), 36)
	elseif kind == "drop" then
		local targetX = NET_X + dir * (rng:range(0.9, 2.3) + math.abs(rng:spread()) * err * 2)
		local margin = 0.25 - err * 0.35 + rng:range(0, 0.1)
		if blunder(rng, err, 0.5) then
			margin = rng:range(-0.25, -0.02)
		end
		return lowestClearingArc(x0, y0, dir, (targetX - x0) * dir, -30, 75, margin)
	elseif kind == "net" then
		local targetX = NET_X + dir * (rng:range(0.45, 1.15) + err * 0.8)
		local margin = 0.12 - err * 0.25 + rng:range(0, 0.1)
		if blunder(rng, err, 0.5) then
			margin = rng:range(-0.25, -0.02)
		end
		return lowestClearingArc(x0, y0, dir, (targetX - x0) * dir, 15, 85, margin)
	elseif kind == "serveShort" then
		local targetX = NET_X + dir * (Config.SHORT_SERVICE_DIST + rng:range(0.3, 1.0))
		return lowestClearingArc(x0, y0, dir, (targetX - x0) * dir, 5, 75, rng:range(0.1, 0.2))
	else -- smash
		local speed = Config.SMASH_SPEED * (0.85 + 0.15 * (1 - err))
		local targetX = NET_X + dir * rng:range(1.6, 5.2)
		local distance = math.max((targetX - x0) * dir, 0.5)
		local angle, flight = Shuttle.solveAngle(x0, y0, speed, dir, distance, -70 * DEG, 20 * DEG)
		-- 네트에 걸리는 각도면 조금씩 들어 올린다. 그래도 낮은 타점이면 네트에 걸릴 수 있다.
		local tries = 0
		local margin = 0.06 + 0.2 * (1 - err)
		while not Shuttle.clearsNet(flight, dir, margin) and angle < 25 * DEG and tries < 20 do
			angle += 2 * DEG
			local vx, vy = Shuttle.launch(angle, speed, dir)
			flight = Shuttle.simulate(x0, y0, vx, vy)
			tries += 1
		end
		angle += rng:spread() * err * 8 * DEG
		if blunder(rng, err, 0.5) then
			angle -= rng:range(3, 7) * DEG
		end
		return Shuttle.launch(angle, speed, dir)
	end
end

return Shots
