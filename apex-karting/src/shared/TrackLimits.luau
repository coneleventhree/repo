--!strict
-- Track limits: a kart has left the track when all four tyres are entirely
-- beyond the edge of the road and its kerb (kerbs count as track, the turf,
-- run-off and gravel beyond do not). Pure Luau; TrackMath and the track's
-- zones (TrackLayout.zones) are passed in.
--
-- A Tracker turns the per-frame yes/no into violations: one per excursion,
-- counted once the kart has been fully out for MinTime while moving (a spin
-- that ends in the grass at walking pace is not one), and re-armed after it
-- has been back on track for ReArm seconds.

local TrackLimits = {}

type Sample = { pos: vector, fwd: vector, right: vector, width: number }
type Track = { samples: { Sample }, n: number, spacing: number }
type Bands = { kerb: number }
type Zones = { { left: Bands, right: Bands } }
type TrackMath = { nearest: (any, vector, number?, number?, number?) -> (number, number, number) }

export type Wheel = { pos: vector, half: number }

export type Tracker = {
	outTime: number,
	inTime: number,
	peak: number,
	counted: boolean,
	idx: number?, -- where on the lap the kart was last frame (search hint)
}

TrackLimits.MinTime = 0.2 -- seconds fully out before it counts
TrackLimits.MinSpeed = 8 -- studs/s: slower excursions (spins, crawling back) do not count
TrackLimits.ReArm = 0.4 -- seconds back on track before the next excursion can count
TrackLimits.Tolerance = 0.25 -- studs of grace beyond the kerb
TrackLimits.SearchReach = 40 -- studs beyond the edge still followed frame to frame (further: search the lap)

function TrackLimits.newTracker(): Tracker
	return { outTime = 0, inTime = 0, peak = 0, counted = false, idx = nil }
end

-- The sample nearest the kart, followed frame to frame in the tracker. The
-- race's own position can't be used as the hint: it holds still while a cut
-- or a jump is being checked, and from a stale hint every tyre looked far
-- off the road. If the kart is not near the windowed answer (a reset, a
-- respawn, or level with it but on another part of the circuit) the whole
-- lap is searched.
function TrackLimits.locate(tm: TrackMath, track: any, tr: Tracker, pos: vector): number
	local t = track :: Track
	local idx = tr.idx
	if idx then
		local found = tm.nearest(t, pos, idx, 10, 45)
		local smp = t.samples[found]
		local rel = pos - smp.pos
		local near = math.abs(vector.dot(rel, smp.fwd)) <= 2 * t.spacing
			and math.abs(vector.dot(rel, smp.right)) <= smp.width / 2 + TrackLimits.SearchReach
		if near then
			tr.idx = found
			return found
		end
	end
	local found = tm.nearest(t, pos)
	tr.idx = found
	return found
end

-- Is every tyre wholly beyond the road edge + kerb? `hint` is a nearby
-- sample index (the racer's last one) to keep the search short.
function TrackLimits.allOut(tm: TrackMath, track: any, zones: any, hint: number?, wheels: { Wheel }): boolean
	local t = track :: Track
	local z = zones :: Zones
	if #wheels == 0 then
		return false
	end
	for _, w in wheels do
		local idx, lateral = tm.nearest(t, w.pos, hint, 8, 16)
		local smp = t.samples[idx]
		local bands = if lateral < 0 then z[idx].left else z[idx].right
		local limit = smp.width / 2 + bands.kerb + TrackLimits.Tolerance
		-- the tyre's inner edge must be past the limit
		if math.abs(lateral) - w.half <= limit then
			return false
		end
	end
	return true
end

-- Feed one frame. Returns true when this excursion becomes a violation.
function TrackLimits.step(tr: Tracker, out: boolean, speed: number, dt: number): boolean
	if out then
		tr.inTime = 0
		tr.outTime += dt
		tr.peak = math.max(tr.peak, speed)
		if not tr.counted and tr.outTime >= TrackLimits.MinTime and tr.peak >= TrackLimits.MinSpeed then
			tr.counted = true
			return true
		end
	else
		tr.inTime += dt
		if tr.inTime >= TrackLimits.ReArm then
			tr.outTime = 0
			tr.peak = 0
			tr.counted = false
		end
	end
	return false
end

return TrackLimits
