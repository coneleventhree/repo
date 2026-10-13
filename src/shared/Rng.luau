--!strict
-- 시드 고정이 가능한 작은 xorshift32 난수 생성기.
-- Roblox의 Random 대신 사용해서 테스트(Lune)에서도 같은 결과를 재현할 수 있게 한다.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number?): Rng
	local s = math.floor(seed or 0x2545F491) % 4294967296
	if s == 0 then
		s = 0x2545F491
	end
	return setmetatable({ state = s }, Rng)
end

-- [0, 1) 범위의 실수
function Rng.next(self: Rng): number
	local s = self.state
	s = bit32.bxor(s, bit32.lshift(s, 13))
	s = bit32.bxor(s, bit32.rshift(s, 17))
	s = bit32.bxor(s, bit32.lshift(s, 5))
	self.state = s
	return s / 4294967296
end

function Rng.range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:next()
end

-- -1 ~ 1 사이, 0 근처가 더 자주 나오는 값 (두 균등 분포의 평균)
function Rng.spread(self: Rng): number
	return self:next() + self:next() - 1
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

return Rng
