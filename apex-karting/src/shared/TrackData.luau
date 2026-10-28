--!strict
-- Every circuit in the game. Each one is drawn like a real track plan:
-- straights (S) and constant-radius corners (A). Positive angles are
-- right-handers. Two straights are "free": their lengths are solved so the lap
-- closes exactly. The lap starts at the start/finish line heading +X; the last
-- segment is the straight that leads onto it (the grid sits there). Consecutive
-- arcs with the same name are one corner (stands and marshal posts go by corner).
-- Most circuits are dead flat (like most kart tracks); Hillside has hills and
-- banking:
--   y      road height at the end of the segment (blended along the lap)
--   bank   corner banking in degrees (applied towards the inside)
--   width  road width from this segment on
-- Per circuit: Name (shown in game), Blurb (one line on the vote card), Laps
-- (Normal race length), Lengths (laps for Short / Normal / Long), Qualifying
-- (session length in seconds), Sectors (split points as lap fractions,
-- default thirds),
-- Bridge (name of the straight the sponsor bridge spans; default: the longest),
-- Sky ("Sunny" / "Cloudy" / "Sunset" / "Night"), PitStyle ("Wing" = sweeping
-- roof over the pits), CornerBoards (name boards at every named corner),
-- Lake (a lake on the most open ground inside the fence), Trees (pines in the
-- open ground), TrackLights (lamp posts along the track, for night races).

local Tampines = {
	Id = "Tampines",
	Name = "Tampines Ring",
	Blurb = "Kart circuit - tight and technical",
	Laps = 3, -- the Normal length
	Lengths = { 2, 3, 5 }, -- laps for Short / Normal / Long
	Qualifying = 120, -- seconds
	Spacing = 6, -- studs between samples
	Smoothing = 10,
	BankSmoothing = 22,
	Segments = {
		{ kind = "S", length = 240, width = 42, name = "Main straight" },
		{ kind = "A", radius = 80, angle = 90, width = 36, name = "T1" },
		{ kind = "S", length = 120, width = 34 },
		{ kind = "A", radius = 140, angle = -40, name = "T2" },
		{ kind = "S", length = 80 },
		{ kind = "A", radius = 38, angle = 180, name = "T3 hairpin" },
		{ kind = "S", length = 140 },
		{ kind = "A", radius = 70, angle = -50, name = "T4" },
		{ kind = "S", length = 90 },
		{ kind = "A", radius = 60, angle = -90, name = "T5" },
		{ kind = "S", length = "free" },
		{ kind = "A", radius = 55, angle = 90, name = "T6" },
		{ kind = "S", length = 320, name = "Back straight" },
		{ kind = "A", radius = 110, angle = 60, name = "T7" },
		{ kind = "A", radius = 65, angle = 60, name = "T8" },
		{ kind = "S", length = 160 },
		{ kind = "A", radius = 50, angle = -40, name = "Chicane" },
		{ kind = "A", radius = 50, angle = 40 },
		{ kind = "S", length = 130 },
		{ kind = "A", radius = 85, angle = 60, width = 38, name = "T10" },
		{ kind = "S", length = "free", width = 42 },
	} :: { any },
}

-- Silverstone, Grand Prix layout (clockwise), at 1 stud per real metre: the
-- lap is about 5.9 km of real track drawn 28% size, so the karts take the
-- fast corners (Copse, Maggotts-Becketts, Stowe) the way a GP car does.
-- Slow corners are opened to at least 30 studs radius for the kart-width road.
-- Fitted to the centre line in the TUMFTM racetrack-database (OpenStreetMap
-- based, LGPL-3.0): every corner boundary lands within a few studs of it.
local Silverstone = {
	Id = "Silverstone",
	Name = "Silverstone",
	Blurb = "Grand Prix circuit - fast sweeping corners",
	Laps = 2,
	Lengths = { 1, 2, 3 },
	Qualifying = 180,
	Spacing = 6,
	Smoothing = 10,
	BankSmoothing = 22,
	Bridge = "Hangar Straight",
	Sky = "Cloudy",
	PitStyle = "Wing",
	CornerBoards = true,
	Segments = {
		{ kind = "S", length = 261.9, width = 36, name = "Hamilton Straight" },
		{ kind = "A", radius = 60.4, angle = 41.96, width = 32, name = "Abbey" },
		{ kind = "A", radius = 156.7, angle = 16.25, name = "Abbey" },
		{ kind = "S", length = 108 },
		{ kind = "A", radius = 183.4, angle = -12.91, name = "Farm" },
		{ kind = "A", radius = 131.1, angle = -17.94, name = "Farm" },
		{ kind = "A", radius = 163.9, angle = -14.22, name = "Farm" },
		{ kind = "S", length = 159.2 },
		{ kind = "A", radius = 43.6, angle = 49.16, name = "Village" },
		{ kind = "A", radius = 30.9, angle = 67.91, name = "Village" },
		{ kind = "S", length = 72.5 },
		{ kind = "A", radius = 30, angle = -97.11, name = "The Loop" },
		{ kind = "A", radius = 43.5, angle = -52.4, name = "The Loop" },
		{ kind = "S", length = 24.8 },
		{ kind = "A", radius = 355.6, angle = -6.63, name = "Aintree" },
		{ kind = "A", radius = 367.9, angle = -6.61, name = "Aintree" },
		{ kind = "A", radius = 94.8, angle = -24.85, name = "Aintree" },
		{ kind = "A", radius = 82, angle = -28.11, name = "Aintree" },
		{ kind = "S", length = "free", name = "Wellington Straight" },
		{ kind = "A", radius = 83.5, angle = -33.24, name = "Brooklands" },
		{ kind = "A", radius = 60.3, angle = -44.81, name = "Brooklands" },
		{ kind = "A", radius = 52.5, angle = -51.22, name = "Brooklands" },
		{ kind = "S", length = 41.9 },
		{ kind = "A", radius = 75.1, angle = 41.9, name = "Luffield" },
		{ kind = "A", radius = 47.1, angle = 64.33, name = "Luffield" },
		{ kind = "A", radius = 54.6, angle = 56.33, name = "Luffield" },
		{ kind = "A", radius = 75.1, angle = 42.03, name = "Luffield" },
		{ kind = "S", length = 116.6 },
		{ kind = "A", radius = 183.9, angle = 13.7, name = "Woodcote" },
		{ kind = "A", radius = 339.4, angle = 7.25, name = "Woodcote" },
		{ kind = "S", length = 23.9 },
		{ kind = "A", radius = 116.8, angle = 22, name = "Woodcote" },
		{ kind = "A", radius = 212.7, angle = 12.42, name = "Woodcote" },
		{ kind = "A", radius = 5769, angle = 3.88, name = "National Straight" },
		{ kind = "A", radius = 122, angle = 18.83, name = "Copse" },
		{ kind = "A", radius = 186.1, angle = 12.06, name = "Copse" },
		{ kind = "A", radius = 92.4, angle = 24.58, name = "Copse" },
		{ kind = "A", radius = 100.4, angle = 22.57, name = "Copse" },
		{ kind = "A", radius = 1562.7, angle = 14.9 },
		{ kind = "A", radius = 153.1, angle = -18.25, name = "Maggotts" },
		{ kind = "A", radius = 196.8, angle = -14.6, name = "Maggotts" },
		{ kind = "S", length = 7.3 },
		{ kind = "A", radius = 68, angle = 29.83, name = "Becketts" },
		{ kind = "A", radius = 84.3, angle = 24.21, name = "Becketts" },
		{ kind = "S", length = 54.2 },
		{ kind = "A", radius = 206.5, angle = -12.23, name = "Becketts" },
		{ kind = "A", radius = 94.8, angle = -25.83, name = "Becketts" },
		{ kind = "A", radius = 108.2, angle = -23.19, name = "Becketts" },
		{ kind = "S", length = 11.2 },
		{ kind = "A", radius = 92.9, angle = 24.6, name = "Becketts" },
		{ kind = "A", radius = 67.2, angle = 33.01, name = "Becketts" },
		{ kind = "A", radius = 75.9, angle = 30.12, name = "Becketts" },
		{ kind = "A", radius = 175.4, angle = 13.08, name = "Becketts" },
		{ kind = "S", length = 37 },
		{ kind = "A", radius = 163.8, angle = -12.87, name = "Chapel" },
		{ kind = "A", radius = 114.8, angle = -17.91, name = "Chapel" },
		{ kind = "S", length = "free", name = "Hangar Straight" },
		{ kind = "A", radius = 101.2, angle = 29.13, name = "Stowe" },
		{ kind = "A", radius = 91.1, angle = 31.98, name = "Stowe" },
		{ kind = "A", radius = 81.5, angle = 36.41, name = "Stowe" },
		{ kind = "A", radius = 117.5, angle = 25.47, name = "Stowe" },
		{ kind = "A", radius = 1082.7, angle = -17.5 },
		{ kind = "A", radius = 33.8, angle = -91.99, name = "Vale" },
		{ kind = "S", length = 3.7 },
		{ kind = "A", radius = 40.2, angle = 84.33, name = "Club" },
		{ kind = "A", radius = 153.8, angle = 22.71, name = "Club" },
		{ kind = "A", radius = 220.9, angle = 16.18, name = "Club" },
		{ kind = "A", radius = 68.4, angle = 51.3, name = "Club" },
		{ kind = "S", length = 200, width = 36, name = "Hamilton Straight" },
	} :: { any },
}

-- The kart circuits below follow the FIA karting circuit licence criteria
-- (scaled at 1 stud = 0.28 m like the karts): 8-12 m wide, start straight
-- 120-200 m with at least 50 m from the line to the first corner and 70 m
-- from the last corner to the line, no straight over 200 m, and at least
-- 6 m between neighbouring parts of the track. Corner radii are kart-sized
-- (hairpins about 11-12 m), so most corners are taken at 45-70 km/h.

-- An international-style circuit (~1.03 km): a long start straight into a
-- fast right, a hairpin at each end of the infield, a 180-degree carousel,
-- esses and a fast double right onto the straight. A lake beside the circuit.
local Lakeside = {
	Id = "Lakeside",
	Name = "Lakeside International",
	Blurb = "International kart circuit - fast and flowing",
	Laps = 3,
	Lengths = { 2, 3, 5 },
	Qualifying = 150,
	Spacing = 6,
	Smoothing = 10,
	BankSmoothing = 22,
	CornerBoards = true,
	Lake = true,
	Segments = {
		{ kind = "S", length = 399.6, width = 36, name = "Start straight" },
		{ kind = "A", radius = 100, angle = 90, width = 34, name = "Boathouse" },
		{ kind = "S", length = 117.3 },
		{ kind = "A", radius = 45, angle = 90, name = "Jetty" },
		{ kind = "S", length = 152.6 },
		{ kind = "A", radius = 40, angle = -180, name = "Pier hairpin" },
		{ kind = "S", length = 223.9 },
		{ kind = "A", radius = 70, angle = 180, name = "Carousel" },
		{ kind = "S", length = "free", name = "Back straight" },
		{ kind = "A", radius = 38, angle = 180, name = "Reed hairpin" },
		{ kind = "S", length = 118.3 },
		{ kind = "A", radius = 65, angle = -50, name = "Esses" },
		{ kind = "A", radius = 65, angle = 50, name = "Esses" },
		{ kind = "S", length = 59.6 },
		{ kind = "A", radius = 45, angle = -180, name = "Lighthouse" },
		{ kind = "S", length = 310.4 },
		{ kind = "A", radius = 150, angle = 45, name = "Willow" },
		{ kind = "S", length = 36.3 },
		{ kind = "A", radius = 55, angle = 45, name = "Willow" },
		{ kind = "S", length = "free" },
		{ kind = "A", radius = 90, angle = 90, name = "Last corner" },
		{ kind = "S", length = 252.2, width = 36 },
	} :: { any },
}

-- A hill circuit (~1.03 km), the only one that is not flat: up a long climb
-- with uphill esses to a blind crest (9 m up), down through a corkscrew to a
-- 12-degree banked Karussell hairpin and a 12-degree banked bowl, then a dip
-- and a steep climb (Eau Rouge / Raidillon) before two hairpins and a banked
-- double right onto the straight. Grades up to 10 %; the grid and pits are flat.
-- Banking leans the road towards the inside of the corner, so part of the
-- road's push on the kart points into the turn and it can go faster.
local Hillside = {
	Id = "Hillside",
	Name = "Hillside Raceway",
	Blurb = "Hills, crests and banked corners",
	Laps = 3,
	Lengths = { 2, 3, 5 },
	Qualifying = 150,
	Spacing = 5, -- finer samples on a hilly circuit: a smoother road (TrackLayout road pieces)
	Smoothing = 10,
	BankSmoothing = 40, -- long bank transitions: a rigid kart rocks on a fast twist
	CornerBoards = true,
	Trees = true,
	Segments = {
		{ kind = "S", length = 209, width = 33 },
		{ kind = "A", radius = 55, angle = 90, width = 32, name = "Turn 1" },
		{ kind = "S", length = "free", y = 8 },
		{ kind = "A", radius = 90, angle = -30, y = 12, name = "Uphill esses" },
		{ kind = "A", radius = 90, angle = 30, y = 16, name = "Uphill esses" },
		{ kind = "S", length = 196, y = 27, name = "Hill climb" },
		-- the sling: a fast right-left flick at the top of the climb, then
		-- brake for the blind crest
		{ kind = "A", radius = 85, angle = 28, y = 29, name = "Sling" },
		{ kind = "A", radius = 85, angle = -28, y = 30, name = "Sling" },
		{ kind = "S", length = 44, y = 30 },
		{ kind = "A", radius = 50, angle = 90, y = 32, name = "Crest" },
		{ kind = "S", length = 174, y = 28 },
		{ kind = "A", radius = 34, angle = -50, y = 26, name = "Corkscrew" },
		{ kind = "A", radius = 34, angle = 50, y = 24, name = "Corkscrew" },
		{ kind = "S", length = 246, y = 24 },
		{ kind = "A", radius = 45, angle = 180, bank = 12, y = 24, name = "Karussell" },
		{ kind = "S", length = 251, y = 25 },
		{ kind = "A", radius = 60, angle = -150, bank = 12, y = 26, name = "Bowl" },
		{ kind = "S", length = 257, y = 4, name = "Downhill" },
		{ kind = "A", radius = 60, angle = -20, y = 0, name = "Eau Rouge" },
		{ kind = "A", radius = 60, angle = 110, y = 10, name = "Raidillon" },
		{ kind = "S", length = 92, y = 13 },
		{ kind = "A", radius = 45, angle = 60, y = 12, name = "Top hairpin" },
		{ kind = "S", length = "free", y = 5 },
		{ kind = "A", radius = 40, angle = -180, y = 2, name = "Hairpin" },
		{ kind = "S", length = 349, y = 2 },
		-- one long, constant sweep: hold the steering all the way round
		{ kind = "A", radius = 72, angle = 180, bank = 6, y = 3, name = "Long sweeper" },
		{ kind = "S", length = 120, y = 0, width = 33 },
		{ kind = "S", length = 131, y = 0 }, -- level for the grid
	} :: { any },
}

-- A night race (~0.88 km) under floodlights by the water: long diagonal
-- legs out to a deep hairpin, a flat-out double kink on the way back (a
-- good place to slipstream) and a twisty infield before the last corner.
local Harbour = {
	Id = "Harbour",
	Name = "Harbour Night Circuit",
	Blurb = "Night race under the lights",
	Laps = 3,
	Lengths = { 2, 3, 5 },
	Qualifying = 150,
	Spacing = 6,
	Smoothing = 10,
	BankSmoothing = 22,
	Sky = "Night",
	CornerBoards = true,
	TrackLights = true,
	Segments = {
		{ kind = "S", length = 305.7, width = 35, name = "Start straight" },
		{ kind = "A", radius = 55, angle = 135, width = 33, name = "Crane" },
		{ kind = "S", length = 237.6 },
		{ kind = "A", radius = 40, angle = -40, name = "Chicane" },
		{ kind = "A", radius = 40, angle = 40, name = "Chicane" },
		{ kind = "S", length = 184.1 },
		{ kind = "A", radius = 60, angle = -90, name = "Dock" },
		{ kind = "S", length = "free" },
		{ kind = "A", radius = 42, angle = 180, name = "Harbour hairpin" },
		{ kind = "S", length = 175 },
		{ kind = "A", radius = 180, angle = -30, name = "Breakwater" },
		{ kind = "S", length = 59.7 },
		{ kind = "A", radius = 180, angle = 30, name = "Breakwater" },
		{ kind = "S", length = 144 },
		{ kind = "A", radius = 60, angle = 45, name = "Anchor" },
		{ kind = "S", length = "free" },
		{ kind = "A", radius = 45, angle = 90, name = "Container" },
		{ kind = "S", length = 191.1 },
		{ kind = "A", radius = 42, angle = -180, name = "Quay hairpin" },
		{ kind = "S", length = 165.7 },
		{ kind = "A", radius = 50, angle = 90, name = "Bollard" },
		{ kind = "S", length = 38.2 },
		{ kind = "A", radius = 65, angle = 90, name = "Last corner" },
		{ kind = "S", length = 236, width = 35 },
	} :: { any },
}

-- Suzuka, Grand Prix layout: the only figure of eight in the game - the
-- back straight crosses over the run from Degner to the hairpin on a bridge.
-- Fitted to the TUMFTM racetrack-database centre line (OpenStreetMap based,
-- LGPL-3.0) at 0.8 studs per real metre, so the lap is shorter than
-- Silverstone's; heights follow the GSI 5 m laser survey at the same scale
-- (the lowest point, the Second Curve, is the lawn). Changed for the karts:
-- the start straight is level at the lawn for the pits and grid (the real
-- one runs downhill) and the Last Curve falls evenly to it, the road under
-- the bridge dips for headroom, 130R is opened to a near-flat-out radius,
-- and the back straight is moved off the Spoon approach to leave room for
-- barriers. Hairpin and Degner 2 are opened to the kart road's 32 studs.
local Suzuka = {
	Id = "Suzuka",
	Name = "Suzuka",
	Blurb = "Figure-eight GP circuit - hills, Esses and 130R",
	Laps = 2,
	Lengths = { 1, 2, 3 },
	Qualifying = 180,
	Spacing = 5, -- finer samples on a hilly circuit: a smoother road (TrackLayout road pieces)
	Smoothing = 10,
	BankSmoothing = 22,
	Bridge = "Main straight",
	CornerBoards = true,
	Trees = true,
	Segments = {
		{ kind = "S", length = 241.7, y = 0, width = 30, name = "Main straight" },
		{ kind = "A", radius = 107.6, angle = 22.76, y = 0, width = 28, name = "First Curve" },
		{ kind = "A", radius = 73.9, angle = 33.91, y = 0, name = "First Curve" },
		{ kind = "S", length = 18.4, y = 0 },
		{ kind = "A", radius = 70.9, angle = 25.66, y = 0.5, name = "Second Curve" },
		{ kind = "A", radius = 46.9, angle = 38.17, y = 1.3, name = "Second Curve" },
		{ kind = "A", radius = 44.5, angle = 40.16, y = 2.1, name = "Second Curve" },
		{ kind = "A", radius = 69.1, angle = 26.65, y = 2.5, name = "Second Curve" },
		{ kind = "S", length = 101, y = 4.2 },
		{ kind = "A", radius = 92.8, angle = -25, y = 5, name = "S Curves" },
		{ kind = "A", radius = 78.7, angle = -29.74, y = 6.2, name = "S Curves" },
		{ kind = "S", length = 9.8, y = 6.5 },
		{ kind = "A", radius = 64.3, angle = 35.19, y = 8.2, name = "S Curves" },
		{ kind = "A", radius = 60.6, angle = 36.36, y = 9.9, name = "S Curves" },
		{ kind = "S", length = 38.7, y = 11.6 },
		{ kind = "A", radius = 87.9, angle = -22.75, y = 13.2, name = "S Curves" },
		{ kind = "A", radius = 67.8, angle = -29.52, y = 14.9, name = "S Curves" },
		{ kind = "A", radius = 93.9, angle = -21.31, y = 16.4, name = "S Curves" },
		{ kind = "S", length = 15.7, y = 17 },
		{ kind = "A", radius = 82.4, angle = 23.82, y = 17.5, name = "Gyaku Bank" },
		{ kind = "A", radius = 69, angle = 27.94, y = 17.4, name = "Gyaku Bank" },
		{ kind = "A", radius = 61.3, angle = 30.44, y = 16.9, name = "Gyaku Bank" },
		{ kind = "A", radius = 72, angle = 27.22, y = 16.2, name = "Gyaku Bank" },
		{ kind = "S", length = 40.4, y = 16.5 },
		{ kind = "A", radius = 75.6, angle = -24.79, y = 18.4, name = "Dunlop" },
		{ kind = "A", radius = 63.9, angle = -28.31, y = 20.5, name = "Dunlop" },
		{ kind = "A", radius = 68.7, angle = -26.61, y = 23, name = "Dunlop" },
		{ kind = "A", radius = 215.9, angle = -8.75, y = 25.2, name = "Dunlop" },
		{ kind = "S", length = 15.9, y = 26.1 },
		{ kind = "A", radius = 125.2, angle = -17.64, y = 27.2, name = "Dunlop" },
		{ kind = "A", radius = 222.6, angle = -9.91, y = 27.4, name = "Dunlop" },
		{ kind = "A", radius = 109.6, angle = -20, y = 27, name = "Dunlop" },
		{ kind = "S", length = 21, y = 26.8 },
		{ kind = "A", radius = 141.3, angle = -13.72, y = 26.4 },
		{ kind = "A", radius = 177.3, angle = -11.07, y = 25.8 },
		{ kind = "S", length = "free", y = 24.4 },
		{ kind = "A", radius = 52.8, angle = 46.36, y = 23.7, name = "Degner 1" },
		{ kind = "S", length = 98.1, y = 21.6 },
		{ kind = "A", radius = 43.7, angle = 89.76, y = 17, name = "Degner 2" },
		{ kind = "S", length = 85, y = 14, name = "Under the bridge" },
		{ kind = "S", length = 98, y = 24.3 },
		{ kind = "A", radius = 96.8, angle = 20.46, y = 26, name = "110R" },
		{ kind = "A", radius = 119.3, angle = 17.89, y = 27.7, name = "110R" },
		{ kind = "S", length = 35.9, y = 29.6 },
		{ kind = "A", radius = 32, angle = -104.13, y = 30.5, name = "Hairpin" },
		{ kind = "A", radius = 32, angle = -81.9, y = 30.8, name = "Hairpin" },
		{ kind = "S", length = 84.9, y = 31.4 },
		{ kind = "A", radius = 163.6, angle = 14.01, y = 31.7, name = "200R" },
		{ kind = "A", radius = 114.2, angle = 19.85, y = 31.9, name = "200R" },
		{ kind = "A", radius = 83.6, angle = 25.87, y = 32.2, name = "200R" },
		{ kind = "S", length = 13.9, y = 32 },
		{ kind = "A", radius = 262.1, angle = 14.76, y = 29.8 },
		{ kind = "A", radius = 549.3, angle = 7.68, y = 28 },
		{ kind = "A", radius = 252, angle = 6.44, y = 28.2 },
		{ kind = "A", radius = 255.6, angle = 7.12, y = 29.1 },
		{ kind = "A", radius = 187.3, angle = 9.79, y = 30.1 },
		{ kind = "A", radius = 174.1, angle = 10.46, y = 30.9 },
		{ kind = "A", radius = 182.3, angle = 10.29, y = 31.5 },
		{ kind = "S", length = 106.1, y = 32.3 },
		{ kind = "A", radius = 63.9, angle = -46.14, y = 32.3, name = "Spoon Curve" },
		{ kind = "A", radius = 105.2, angle = -28.85, y = 32.5, name = "Spoon Curve" },
		{ kind = "A", radius = 66.1, angle = -46.11, y = 32.4, name = "Spoon Curve" },
		{ kind = "A", radius = 58.7, angle = -52.68, y = 31.3, name = "Spoon Curve" },
		{ kind = "A", radius = 112.6, angle = -27.85, y = 28.1, name = "Spoon Curve" },
		{ kind = "A", radius = 633.7, angle = -5.38, y = 23.8, name = "Back straight" },
		{ kind = "A", radius = 829.9, angle = -4.11, y = 21.7, name = "Back straight" },
		{ kind = "A", radius = 831.1, angle = -4.01, y = 22, name = "Back straight" },
		{ kind = "A", radius = 702.1, angle = -4.9, y = 23.3, name = "Back straight" },
		{ kind = "A", radius = 632.5, angle = -7.13, y = 24.7, name = "Back straight" },
		{ kind = "S", length = "free", y = 31, name = "Back straight" },
		{ kind = "A", radius = 106.3, angle = -17.77, y = 31, name = "130R" },
		{ kind = "A", radius = 106.3, angle = -17.37, y = 31, name = "130R" },
		{ kind = "A", radius = 293.3, angle = -3.96, y = 31, name = "130R" },
		{ kind = "A", radius = 182, angle = -12.86, y = 31, name = "130R" },
		{ kind = "A", radius = 286.3, angle = -7.96, y = 31, name = "130R" },
		{ kind = "S", length = 158.9, y = 30.2 },
		{ kind = "A", radius = 32, angle = 78.04, y = 29.7, name = "Casio Triangle" },
		{ kind = "S", length = 1.8, y = 29.7 },
		{ kind = "A", radius = 32, angle = -78.68, y = 28.9, name = "Casio Triangle" },
		{ kind = "S", length = 3.6, y = 28.6 },
		{ kind = "A", radius = 92.3, angle = 24.22, y = 25.5, name = "Last Curve" },
		{ kind = "A", radius = 81.8, angle = 29.34, y = 22.1, name = "Last Curve" },
		{ kind = "S", length = 13.9, y = 21 },
		{ kind = "A", radius = 118.6, angle = 17.03, y = 18.1, name = "Last Curve" },
		{ kind = "A", radius = 188.5, angle = 10.5, y = 15.3, name = "Last Curve" },
		{ kind = "A", radius = 211.8, angle = 9.32, y = 12.5, name = "Last Curve" },
		{ kind = "A", radius = 588.4, angle = 3.44, y = 9.7, name = "Last Curve" },
		{ kind = "S", length = 120, y = 0, width = 30, name = "Main straight" },
		{ kind = "S", length = 170.3, y = 0 },
	} :: { any },
}

local TrackData = {
	Default = "Tampines",
	Order = { "Tampines", "Silverstone", "Lakeside", "Hillside", "Harbour", "Suzuka" },
	Tracks = {
		Tampines = Tampines,
		Silverstone = Silverstone,
		Lakeside = Lakeside,
		Hillside = Hillside,
		Harbour = Harbour,
		Suzuka = Suzuka,
	} :: { [string]: any },
}

-- The circuit with this id, or the default one.
function TrackData.get(id: string?): any
	return TrackData.Tracks[id or ""] or TrackData.Tracks[TrackData.Default]
end

return TrackData
