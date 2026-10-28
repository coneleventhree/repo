"""Writes the Suzuka block (header + generated segments) into TrackData.luau."""
import re, sys
TD = "/home/claude/apex-karting/src/shared/TrackData.luau"
segs = open(sys.argv[1]).read()
header = '''-- Suzuka, Grand Prix layout: the only figure of eight in the game - the
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
''' + segs + '''	} :: { any },
}

'''
src = open(TD).read()
if "local Suzuka = {" in src:
    a = src.index("-- Suzuka, Grand Prix layout")
    b = src.index("local TrackData = {")
    src = src[:a] + header + src[b:]
else:
    b = src.index("local TrackData = {")
    src = src[:b] + header + src[b:]
    src = src.replace("\t\tHarbour = Harbour,\n\t} :: { [string]: any },", "\t\tHarbour = Harbour,\n\t\tSuzuka = Suzuka,\n\t} :: { [string]: any },")
open(TD, "w").write(src)
print("ok")
