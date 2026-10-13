-- 공유 게임 로직 테스트. 실행: lune run tests/run
local process = require("@lune/process")
local Loader = require("./Loader")

local Config = Loader.shared("Config")
local Rng = Loader.shared("Rng")
local Shuttle = Loader.shared("Shuttle")
local Shots = Loader.shared("Shots")
local Match = Loader.shared("Match")
local Bot = Loader.shared("Bot")

local NET_X = Config.NET_X
local HALF = Config.COURT_HALF_LENGTH
local TICK = Config.TICK

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function near(a: number, b: number, tolerance: number, message: string)
	if math.abs(a - b) > tolerance then
		error(string.format("%s: expected %.4f, got %.4f", message, b, a), 2)
	end
end

local IDLE = { move = 0, jump = false, hit = false, drop = false }

local function findEvent(events: { Match.Event }, kind: string): Match.Event?
	for _, event in events do
		if event.kind == kind then
			return event
		end
	end
	return nil
end

-- 실제 경기와 같은 방식(서브스텝 + 네트 충돌)으로 셔틀만 날려서 결과를 본다
local function flyInMatch(x: number, y: number, vx: number, vy: number): (number, boolean)
	local match = Match.new({ seed = 1 })
	match.phase = "rally"
	match.lastHitter = if vx > 0 then 1 else 2
	match.hitCount = 2
	local s = match.shuttle
	s.x, s.y, s.vx, s.vy = x, y, vx, vy
	local hitNet = false
	for _ = 1, 60 * 10 do
		for _, event in match:step(TICK, { IDLE, IDLE }) do
			if event.kind == "net" then
				hitNet = true
			end
		end
		if s.grounded then
			break
		end
	end
	return s.x, hitNet
end

-- 랠리 중인 경기 상태를 만들고 셔틀을 바로 바닥 근처에 놓아 득점 판정을 확인한다
local function landAt(landX: number, lastHitter: number, hitCount: number, server: number?): Match.Match
	local match = Match.new({ seed = 2, firstServer = server or 1 })
	match.phase = "rally"
	match.lastHitter = lastHitter
	match.hitCount = hitCount
	-- 선수들이 셔틀을 치지 않도록 멀리 둔다
	match.players[1].x, match.players[2].x = Config.WALL_MARGIN, Config.VIEW_WIDTH - Config.WALL_MARGIN
	local s = match.shuttle
	s.x, s.y, s.vx, s.vy = landX, 0.05, 0, -5
	match:step(TICK, { IDLE, IDLE })
	return match
end

print("Rng")
test("same seed gives the same sequence", function()
	local a, b = Rng.new(42), Rng.new(42)
	for _ = 1, 100 do
		check(a:next() == b:next(), "sequences differ")
	end
end)
test("values stay in range", function()
	local rng = Rng.new(7)
	for _ = 1, 10000 do
		local v = rng:next()
		check(v >= 0 and v < 1, "next out of range")
		local s = rng:spread()
		check(s >= -1 and s <= 1, "spread out of range")
	end
end)

print("Shuttle physics")
test("falls at terminal velocity", function()
	local body = { x = 0, y = 1000, vx = 0, vy = 0 }
	for _ = 1, 600 * Config.SHUTTLE_SUBSTEPS do
		Shuttle.step(body, TICK / Config.SHUTTLE_SUBSTEPS)
	end
	near(body.vy, -Config.TERMINAL_VELOCITY, 0.05, "terminal velocity")
end)
test("fast shuttle slows down quickly", function()
	local body = { x = 0, y = 100, vx = 40, vy = 0 }
	for _ = 1, 30 do -- 0.5초
		Shuttle.step(body, 1 / 60)
	end
	check(body.vx < 15, "drag too weak: vx = " .. body.vx)
end)
test("solveSpeed hits the requested distance", function()
	for _, angle in { -10, 20, 45, 60 } do
		local _, flight = Shuttle.solveSpeed(2, 2, math.rad(angle), 1, 9)
		near(flight.landX, 11, 0.02, "angle " .. angle)
	end
end)
test("solver agrees with the in-match integrator", function()
	local rng = Rng.new(9)
	for _ = 1, 40 do
		local x, y = rng:range(1, 7), rng:range(1.5, 3)
		local vx, vy = Shots.plan("clear", x, y, 1, 1, rng)
		local expected = Shuttle.simulate(x, y, vx, vy).landX
		local landX = flyInMatch(x, y, vx, vy)
		near(landX, expected, 0.15, "landing mismatch")
	end
end)

print("Shots")
local function eachContact(
	count: number,
	xMin: number,
	xMax: number,
	yMin: number,
	yMax: number,
	fn: (number, number, Rng.Rng) -> ()
)
	local rng = Rng.new(1234)
	for _ = 1, count do
		fn(rng:range(xMin, xMax), rng:range(yMin, yMax), rng)
	end
end

local leftMin, leftMax = Match.bounds(1)

for _, case in
	{
		{ kind = "clear", yMin = 1.0, yMax = 2.75 },
		{ kind = "lift", yMin = 0.3, yMax = 1.0 },
		{ kind = "drop", yMin = 1.0, yMax = 3.9 },
	}
do
	test(case.kind .. " at perfect quality lands in from anywhere on court", function()
		eachContact(40, leftMin, leftMax, case.yMin, case.yMax, function(x, y, rng)
			local vx, vy = Shots.plan(case.kind :: Shots.ShotKind, x, y, 1, 1, rng)
			local landX, hitNet = flyInMatch(x, y, vx, vy)
			check(not hitNet, string.format("%s from (%.2f, %.2f) hit the net", case.kind, x, y))
			check(
				landX > NET_X and landX <= NET_X + HALF,
				string.format("%s from (%.2f, %.2f) landed at %.2f", case.kind, x, y, landX)
			)
		end)
	end)
end

test("net shot near the net drops short", function()
	eachContact(40, NET_X - 2.5, leftMax, 0.3, 1.0, function(x, y, rng)
		local vx, vy = Shots.plan("net", x, y, 1, 1, rng)
		local landX, hitNet = flyInMatch(x, y, vx, vy)
		check(not hitNet, string.format("net shot from (%.2f, %.2f) hit the net", x, y))
		check(landX > NET_X and landX < NET_X + 2.5, string.format("net shot landed at %.2f", landX))
	end)
end)

test("smash from a jump is fast and lands in", function()
	eachContact(40, 3, leftMax, Config.SMASH_MIN_HEIGHT, 3.9, function(x, y, rng)
		local vx, vy = Shots.plan("smash", x, y, 1, 1, rng)
		check(vy < 3, "smash should not go up much")
		local landX, hitNet = flyInMatch(x, y, vx, vy)
		check(not hitNet, string.format("smash from (%.2f, %.2f) hit the net", x, y))
		check(landX > NET_X and landX <= NET_X + HALF, string.format("smash landed at %.2f", landX))
	end)
end)

test("drop lands closer to the net than clear", function()
	local rng = Rng.new(5)
	local vx, vy = Shots.plan("drop", 3, 2, 1, 1, rng)
	local dropLand = flyInMatch(3, 2, vx, vy)
	vx, vy = Shots.plan("clear", 3, 2, 1, 1, rng)
	local clearLand = flyInMatch(3, 2, vx, vy)
	check(dropLand < NET_X + 3, "drop too deep: " .. dropLand)
	check(clearLand > NET_X + 4.5, "clear too short: " .. clearLand)
end)

test("shots to the left mirror shots to the right", function()
	local vxR = Shots.plan("clear", NET_X - 4, 2, 1, 1, Rng.new(77))
	local vxL = Shots.plan("clear", NET_X + 4, 2, -1, 1, Rng.new(77))
	near(vxL, -vxR, 1e-9, "mirrored vx")
end)

test("short serve passes the short service line", function()
	local rng = Rng.new(11)
	local x, y = NET_X - 2.6 + 0.45, Config.SERVE_CONTACT_HEIGHT
	for _ = 1, 30 do
		local vx, vy = Shots.plan("serveShort", x, y, 1, 0.85, rng)
		local landX, hitNet = flyInMatch(x, y, vx, vy)
		check(not hitNet, "short serve hit the net")
		check(landX > NET_X + Config.SHORT_SERVICE_DIST, "short serve landed short at " .. landX)
	end
end)

test("bad contact makes more errors than good contact", function()
	local function errors(quality: number): number
		local rng = Rng.new(99)
		local count = 0
		for _ = 1, 200 do
			local vx, vy = Shots.plan("clear", 3, 2, 1, quality, rng)
			local landX, hitNet = flyInMatch(3, 2, vx, vy)
			if hitNet or landX > NET_X + HALF then
				count += 1
			end
		end
		return count
	end
	local good, bad = errors(1), errors(0.1)
	check(good == 0, "perfect clears should never go out, got " .. good)
	check(bad > 20, "poor clears should go out sometimes, got " .. bad)
end)

print("Rules")
test("shuttle landing in on the receiver's side scores for the hitter", function()
	local match = landAt(NET_X + 3, 1, 3)
	check(match.score[1] == 1 and match.score[2] == 0, "score")
	check(match.lastReason == "in", "reason " .. match.lastReason)
	check(match.server == 1, "winner serves next")
	check(match.phase == "point", "phase")
end)
test("landing on the line counts as in", function()
	local match = landAt(NET_X + HALF, 1, 3)
	check(match.score[1] == 1, "line should be in")
end)
test("landing beyond the back line is out", function()
	local match = landAt(NET_X + HALF + 0.3, 1, 3)
	check(match.score[2] == 1 and match.score[1] == 0, "out goes to the receiver")
	check(match.lastReason == "out", "reason " .. match.lastReason)
end)
test("shot that falls on the hitter's own side is a fault", function()
	local match = landAt(NET_X - 1, 1, 3)
	check(match.score[2] == 1, "fault goes to the opponent")
	check(match.lastReason == "fault", "reason " .. match.lastReason)
end)
test("serve that lands before the short service line is a fault", function()
	local match = landAt(NET_X + 1, 1, 1, 1)
	check(match.score[2] == 1, "short serve should lose the point")
	check(match.lastReason == "short", "reason " .. match.lastReason)
end)
test("shuttle hitting the net falls back and loses the point", function()
	local match = Match.new({ seed = 3 })
	match.phase = "rally"
	match.lastHitter = 1
	match.hitCount = 3
	match.players[1].x = Config.WALL_MARGIN
	match.players[2].x = Config.VIEW_WIDTH - Config.WALL_MARGIN
	local s = match.shuttle
	s.x, s.y, s.vx, s.vy = NET_X - 1, 1, 8, 0
	local sawNet = false
	for _ = 1, 600 do
		for _, event in match:step(TICK, { IDLE, IDLE }) do
			sawNet = sawNet or event.kind == "net"
		end
		if s.grounded then
			break
		end
	end
	check(sawNet, "expected a net event")
	check(s.x < NET_X, "shuttle should fall back on the hitter's side")
	check(match.score[2] == 1 and match.lastReason == "net", "net point goes to the opponent")
end)
test("game ends at 11 with a two point lead", function()
	local match = Match.new()
	match.score = { 10, 10 }
	check(not match:isWon(1), "10-10 is not over")
	match.score = { 11, 10 }
	check(not match:isWon(1), "11-10 is not over")
	match.score = { 12, 10 }
	check(match:isWon(1), "12-10 is over")
	match.score = { 11, 5 }
	check(match:isWon(1), "11-5 is over")
	match.score = { 15, 14 }
	check(match:isWon(1), "the cap ends the game")
end)
test("match moves to game over after the winning point", function()
	local match = Match.new({ seed = 4 })
	match.score = { 10, 3 }
	match.phase = "rally"
	match.lastHitter = 1
	match.hitCount = 3
	match.players[1].x = Config.WALL_MARGIN
	match.players[2].x = Config.VIEW_WIDTH - Config.WALL_MARGIN
	match.shuttle.x, match.shuttle.y, match.shuttle.vy = NET_X + 2, 0.05, -5
	local gameOver = false
	for _ = 1, math.ceil(Config.POINT_PAUSE / TICK) + 5 do
		for _, event in match:step(TICK, { IDLE, IDLE }) do
			gameOver = gameOver or (event.kind == "gameOver" and event.side == 1)
		end
	end
	check(match.winner == 1 and match.phase == "over" and gameOver, "game should be over")
end)

print("Serving and hitting")
test("server is frozen until serving and the serve starts the rally", function()
	local match = Match.new({ seed = 5 })
	local startX = match.players[1].x
	match:step(TICK, { { move = 1, jump = true, hit = false, drop = false }, IDLE })
	check(match.players[1].x == startX and match.players[1].onGround, "server should not move")
	local serve = findEvent(match:step(TICK, { { move = 0, jump = false, hit = true, drop = false }, IDLE }), "hit")
	check(match.phase == "rally", "serve should start the rally")
	check(serve and serve.shot == "serveHigh", "serve event")
	check(match.shuttle.vx > 0, "serve goes toward the receiver")
end)
test("serve happens automatically after the timeout", function()
	local match = Match.new({ seed = 6 })
	for _ = 1, math.ceil(Config.SERVE_TIMEOUT / TICK) + 1 do
		match:step(TICK, { IDLE, IDLE })
	end
	check(match.phase == "rally", "auto serve")
end)
test("receiver can move while waiting for the serve", function()
	local match = Match.new({ seed = 7 })
	local startX = match.players[2].x
	match:step(TICK, { IDLE, { move = 1, jump = false, hit = false, drop = false } })
	check(match.players[2].x > startX, "receiver should move")
end)
test("player cannot leave their half", function()
	local match = Match.new({ seed = 8 })
	match.phase = "point"
	match.phaseTimer = 100
	for _ = 1, 300 do
		match:step(TICK, {
			{ move = 1, jump = false, hit = false, drop = false },
			{ move = -1, jump = false, hit = false, drop = false },
		})
	end
	check(match.players[1].x < NET_X and match.players[2].x > NET_X, "players crossed the net")
end)
test("NaN input is ignored", function()
	local match = Match.new({ seed = 9 })
	match:step(TICK, { IDLE, { move = 0 / 0, jump = false, hit = false, drop = false } })
	check(match.players[2].x == match.players[2].x, "x became NaN")
end)

-- 셔틀을 선수 스윗 스팟 근처로 떨어뜨리는 상황
local function incomingToPlayer2(): Match.Match
	local match = Match.new({ seed = 10 })
	match.phase = "rally"
	match.lastHitter = 1
	match.hitCount = 2
	local p = match.players[2]
	p.x = NET_X + 3
	local s = match.shuttle
	s.x, s.y, s.vx, s.vy = p.x - 0.6, 2.2, 0, -Config.TERMINAL_VELOCITY
	return match
end

test("swinging when the shuttle is in the zone returns it", function()
	local match = incomingToPlayer2()
	local hit = findEvent(match:step(TICK, { IDLE, { move = 0, jump = false, hit = true, drop = false } }), "hit")
	assert(hit, "expected a hit")
	check(hit.side == 2, "wrong hitter")
	check(hit.shot == "clear", "expected a clear, got " .. tostring(hit.shot))
	check(match.shuttle.vx < 0, "return should go to the left")
	check(match.lastHitter == 2 and match.hitCount == 3, "rally bookkeeping")
end)
test("drop button plays a drop", function()
	local match = incomingToPlayer2()
	local hit = findEvent(match:step(TICK, { IDLE, { move = 0, jump = false, hit = false, drop = true } }), "hit")
	check(hit and hit.shot == "drop", "expected a drop")
end)
test("cannot hit twice in a row", function()
	local match = incomingToPlayer2()
	match.lastHitter = 2
	local hit = findEvent(match:step(TICK, { IDLE, { move = 0, jump = false, hit = true, drop = false } }), "hit")
	check(hit == nil, "double hit should be ignored")
end)
test("swing too early misses", function()
	local match = incomingToPlayer2()
	match.shuttle.y = 6 -- 아직 한참 위에 있다
	match.shuttle.vy = -1
	local hit = false
	for i = 1, 20 do
		local input = { move = 0, jump = false, hit = i == 1, drop = false }
		for _, event in match:step(TICK, { IDLE, input }) do
			hit = hit or event.kind == "hit"
		end
	end
	check(not hit, "early swing should whiff")
end)
test("jumping and hitting a high shuttle is a smash", function()
	local match = Match.new({ seed = 12 })
	match.phase = "rally"
	match.lastHitter = 2
	match.hitCount = 2
	local p = match.players[1]
	p.x = NET_X - 3
	p.onGround = false
	p.y = 1.0
	p.vy = 0.5
	local s = match.shuttle
	s.x, s.y, s.vx, s.vy = p.x + 0.6, 3.1, 0, -2
	local hit = findEvent(match:step(TICK, { { move = 0, jump = false, hit = true, drop = false }, IDLE }), "hit")
	check(hit and hit.shot == "smash", "expected a smash, got " .. tostring(hit and hit.shot))
	check(match.shuttle.vx > 20, "smash should be fast")
end)
test("lag compensation accepts a swing the client saw in time", function()
	local function run(lookback: number): boolean
		local match = incomingToPlayer2()
		-- 셔틀이 0.2초 전에 스윗 스팟을 지나 지금은 범위 밖에 있다
		for _ = 1, 30 do
			match:step(TICK, { IDLE, IDLE })
			if match.shuttle.y < 0.2 then
				break
			end
		end
		local hit = false
		local input = { move = 0, jump = false, hit = true, drop = false, lookback = lookback }
		for _, event in match:step(TICK, { IDLE, input }) do
			hit = hit or event.kind == "hit"
		end
		return hit
	end
	check(not run(0), "without lookback the swing is late")
	check(run(0.2), "lookback should accept the swing")
end)

print("Networking helpers")
test("pack and unpack round trip", function()
	local match = Match.new({ seed = 13 })
	match.score = { 7, 9 }
	match.players[1].swingT = 0.1
	local view = Match.unpack(match:pack())
	check(view.score[1] == 7 and view.score[2] == 9, "score")
	check(view.phase == "serve" and view.server == match.server, "phase/server")
	near(view.players[1].x, match.players[1].x, 1e-9, "p1 x")
	near(view.players[2].x, match.players[2].x, 1e-9, "p2 x")
	near(view.players[1].swingT, 0.1, 1e-9, "swing")
	check(view.players[1].dir == 1 and view.players[2].dir == -1, "dirs")
	near(view.shuttle.x, match.shuttle.x, 1e-9, "shuttle x")
end)
test("unpack survives garbage", function()
	local view = Match.unpack({ "x", 0 / 0, nil, {} } :: any)
	check(view.phase == "serve" and view.score[1] == 0, "defaults")
end)
test("lerpView interpolates positions", function()
	local a = Match.unpack(Match.new({ seed = 14 }):pack())
	local b = Match.unpack(Match.new({ seed = 14 }):pack())
	b.time = a.time + 0.1
	b.players[1].x = a.players[1].x + 1
	local mid = Match.lerpView(a, b, 0.5)
	near(mid.players[1].x, a.players[1].x + 0.5, 1e-9, "lerp x")
	near(mid.time, a.time + 0.05, 1e-9, "lerp time")
end)

print("Full games")
for _, pairing in { { "Hard", "Hard" }, { "Normal", "Normal" }, { "Easy", "Easy" }, { "Normal", "Easy" } } do
	test(pairing[1] .. " bot vs " .. pairing[2] .. " bot finishes a game", function()
		for seed = 1, 3 do
			local match = Match.new({ seed = seed })
			local bots = { Bot.new(1, pairing[1], seed), Bot.new(2, pairing[2], seed + 100) }
			local hits, rallies = 0, 0
			local ticks = 0
			while match.phase ~= "over" and ticks < 60 * 60 * 30 do
				for _, event in match:step(TICK, { bots[1]:update(match), bots[2]:update(match) }) do
					if event.kind == "hit" then
						hits += 1
					elseif event.kind == "point" then
						rallies += 1
					end
				end
				ticks += 1
			end
			check(match.phase == "over", "game did not finish (seed " .. seed .. ")")
			local w = match.winner
			check(match:isWon(w) and not match:isWon(3 - w), "final score is consistent")
			check(rallies == match.score[1] + match.score[2], "every rally scored once")
			check(hits / rallies >= 2, string.format("bots should rally, avg %.2f hits", hits / rallies))
		end
	end)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
