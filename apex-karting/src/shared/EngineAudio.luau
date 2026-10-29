--!strict
-- The engine as layered loops (pure Luau: the client, the tests and
-- sounds/engine_preview.py all mix it the same way).
--
-- Each loop is the engine at one steady rpm and load (sounds/make_sounds.py
-- engine_layers). A single loop pitched across the whole rev range moved the
-- pipe and muffler resonances with it (a toy-like sound): here each loop is
-- pitched only towards its neighbours, and the two nearest are cross-faded
-- (equal power). On the throttle only the full-load loops play (layers 2..n);
-- with it closed, the idle loop (layer 1) at low revs and the overrun loop
-- (weak, uneven firings, pops) above them; the throttle fades between the two.

local EngineAudio = {}

export type Layer = { id: string, rpm: number }
export type Mix = { volumes: { number }, speeds: { number }, offVolume: number, offSpeed: number }

local OVERRUN_FADE = 800 -- rpm over which closed-throttle idle turns into overrun

-- equal-power weights for `rpm` between points `rpms` (sorted)
local function weights(rpms: { number }, rpm: number): { number }
	local n = #rpms
	local w = table.create(n, 0)
	if rpm <= rpms[1] then
		w[1] = 1
	elseif rpm >= rpms[n] then
		w[n] = 1
	else
		for i = 1, n - 1 do
			local a, b = rpms[i], rpms[i + 1]
			if rpm >= a and rpm < b then
				local f = (rpm - a) / (b - a)
				w[i] = math.cos(f * math.pi / 2)
				w[i + 1] = math.sin(f * math.pi / 2)
				break
			end
		end
	end
	return w
end

-- volumes (0..1) and playback speeds for `layers` (sorted by rpm: the idle,
-- then the full-load loops) and the overrun loop recorded at `offRpm`, at
-- engine speed `rpm` with the throttle at `load` (0..1)
function EngineAudio.mix(layers: { Layer }, offRpm: number, rpm: number, load: number): Mix
	local n = #layers
	local l = math.clamp(load, 0, 1)
	local full: { number } = {}
	for i = 2, n do
		table.insert(full, layers[i].rpm)
	end
	local wf = weights(full, rpm)
	local closed = weights({ layers[1].rpm, layers[1].rpm + OVERRUN_FADE }, rpm)
	local volumes = table.create(n, 0)
	local speeds = table.create(n, 1)
	for i = 1, n do
		speeds[i] = math.clamp(rpm / layers[i].rpm, 0.5, 2)
	end
	volumes[1] = closed[1] * (1 - l)
	for i = 2, n do
		volumes[i] = wf[i - 1] * l
	end
	return {
		volumes = volumes,
		speeds = speeds,
		offVolume = closed[2] * (1 - l),
		offSpeed = math.clamp(rpm / offRpm, 0.5, 2),
	}
end

-- the layers to use, or nil while any of their sounds is still to be
-- uploaded (the game then plays the single EngineSoundId loop)
function EngineAudio.layers(audio: any): { Layer }?
	local list = audio.EngineLayers
	if type(list) ~= "table" or #list < 2 or (audio.EngineOffSoundId or "") == "" then
		return nil
	end
	for _, l in list do
		if (l.id or "") == "" then
			return nil
		end
	end
	return list
end

return EngineAudio
