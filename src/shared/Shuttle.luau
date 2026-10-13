--!strict
-- 셔틀콕 물리: 중력 + 속도 제곱 공기 저항(quadratic drag).
-- 셔틀콕은 처음엔 빠르게 날아가다가 급격히 느려지고 거의 수직으로 떨어지는데,
-- 이 특징이 quadratic drag에서 자연스럽게 나온다.

local Config = require(script.Parent.Config)

local Shuttle = {}

export type Body = { x: number, y: number, vx: number, vy: number }

export type Flight = {
	landX: number, -- 바닥(y = 0)에 닿는 x
	landTime: number,
	netY: number?, -- 네트 평면(x = NET_X)을 지날 때의 높이, 지나지 않으면 nil
	apexY: number,
}

local GRAVITY = Config.GRAVITY
local DRAG = Config.DRAG
local NET_X = Config.NET_X
local SOLVER_DT = 1 / 120

-- 한 스텝 적분. drag 항은 암시적(implicit)으로 처리해 큰 속도에서도 안정적이다.
function Shuttle.step(body: Body, dt: number)
	local speed = math.sqrt(body.vx * body.vx + body.vy * body.vy)
	local f = 1 / (1 + DRAG * speed * dt)
	body.vx *= f
	body.vy = body.vy * f - GRAVITY * dt
	body.x += body.vx * dt
	body.y += body.vy * dt
end

-- 주어진 초기 상태에서 바닥에 닿을 때까지 비행을 시뮬레이션한다 (네트 충돌은 무시).
function Shuttle.simulate(x: number, y: number, vx: number, vy: number, maxTime: number?): Flight
	local limit = maxTime or 8
	local body = { x = x, y = y, vx = vx, vy = vy }
	local t = 0
	local netY: number? = nil
	local apex = y
	if y <= 0 then
		return { landX = x, landTime = 0, netY = nil, apexY = y }
	end
	while t < limit do
		local px, py = body.x, body.y
		Shuttle.step(body, SOLVER_DT)
		t += SOLVER_DT
		if body.y > apex then
			apex = body.y
		end
		if netY == nil and px ~= body.x and (px - NET_X) * (body.x - NET_X) <= 0 then
			local a = (NET_X - px) / (body.x - px)
			netY = py + (body.y - py) * a
		end
		if body.y <= 0 then
			local a = py / (py - body.y)
			return {
				landX = px + (body.x - px) * a,
				landTime = t - SOLVER_DT + SOLVER_DT * a,
				netY = netY,
				apexY = apex,
			}
		end
	end
	return { landX = body.x, landTime = t, netY = netY, apexY = apex }
end

local function launch(angle: number, speed: number, dir: number): (number, number)
	return math.cos(angle) * speed * dir, math.sin(angle) * speed
end

-- 고정된 발사 각도에서 (landX - x0) * dir == distance 가 되는 속도를 이분 탐색으로 찾는다.
function Shuttle.solveSpeed(x0: number, y0: number, angle: number, dir: number, distance: number): (number, Flight)
	local function fly(speed: number): Flight
		local vx, vy = launch(angle, speed, dir)
		return Shuttle.simulate(x0, y0, vx, vy)
	end
	-- 대부분의 샷은 24 이하의 속도라서 먼저 좁은 구간을 확인해 계산량을 줄인다
	local lo, hi = 1, 24
	local hiFlight = fly(hi)
	if (hiFlight.landX - x0) * dir < distance then
		lo, hi = 24, 80
		hiFlight = fly(hi)
		if (hiFlight.landX - x0) * dir <= distance then
			return hi, hiFlight
		end
	end
	for _ = 1, 12 do
		local mid = (lo + hi) / 2
		local flight = fly(mid)
		if (flight.landX - x0) * dir < distance then
			lo = mid
		else
			hi, hiFlight = mid, flight
		end
	end
	return hi, hiFlight
end

-- 고정된 속도에서 원하는 비거리가 나오는 각도를 찾는다 (스매시용, 각도 구간 안에서 단조 증가 가정).
function Shuttle.solveAngle(
	x0: number,
	y0: number,
	speed: number,
	dir: number,
	distance: number,
	minAngle: number,
	maxAngle: number
): (number, Flight)
	local lo, hi = minAngle, maxAngle
	for _ = 1, 16 do
		local mid = (lo + hi) / 2
		local vx, vy = launch(mid, speed, dir)
		local flight = Shuttle.simulate(x0, y0, vx, vy)
		if (flight.landX - x0) * dir < distance then
			lo = mid
		else
			hi = mid
		end
	end
	local angle = (lo + hi) / 2
	local vx, vy = launch(angle, speed, dir)
	return angle, Shuttle.simulate(x0, y0, vx, vy)
end

-- 네트를 margin 이상 여유 있게 넘어 상대 코트에 떨어지는지
function Shuttle.clearsNet(flight: Flight, dir: number, margin: number): boolean
	if (flight.landX - NET_X) * dir <= 0 then
		return false
	end
	local netY = flight.netY
	return netY == nil or netY >= Config.NET_HEIGHT + margin
end

Shuttle.launch = launch

return Shuttle
