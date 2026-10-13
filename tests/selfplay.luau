-- AI끼리 경기를 시켜 랠리 길이, 득점 이유, 샷 분포를 출력한다. 밸런스 조정용.
-- 실행: lune run tests/selfplay
local Loader = require("./Loader")
local Config = Loader.shared("Config")
local Match = Loader.shared("Match")
local Bot = Loader.shared("Bot")

local function summarize(counts: { [string]: number }): string
	local parts = {}
	for key, value in counts do
		table.insert(parts, key .. "=" .. value)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

local function play(left: string, right: string, seed: number)
	local match = Match.new({ seed = seed })
	local bots = { Bot.new(1, left, seed * 3 + 1), Bot.new(2, right, seed * 5 + 2) }
	local rallies, totalHits, ticks = 0, 0, 0
	local qualitySum, qualityCount = 0, 0
	local reasons, shots = {}, {}
	while match.phase ~= "over" and ticks < 60 * 60 * 20 do
		local events = match:step(Config.TICK, { bots[1]:update(match), bots[2]:update(match) })
		ticks += 1
		for _, event in events do
			if event.kind == "point" then
				rallies += 1
				totalHits += match.hitCount
				local reason = event.reason or "?"
				reasons[reason] = (reasons[reason] or 0) + 1
			elseif event.kind == "hit" then
				local shot = event.shot or "?"
				shots[shot] = (shots[shot] or 0) + 1
				qualitySum += event.quality or 0
				qualityCount += 1
			end
		end
	end
	print(
		string.format(
			"%-6s vs %-6s %2d-%-2d %4.0fs  rallies=%2d avgHits=%5.2f avgQuality=%.2f | %s | %s",
			left,
			right,
			match.score[1],
			match.score[2],
			ticks * Config.TICK,
			rallies,
			totalHits / math.max(rallies, 1),
			qualitySum / math.max(qualityCount, 1),
			summarize(reasons),
			summarize(shots)
		)
	)
end

for seed = 1, 2 do
	play("Hard", "Hard", seed)
	play("Normal", "Normal", seed)
	play("Easy", "Easy", seed)
	play("Hard", "Normal", seed)
	play("Normal", "Easy", seed)
end
