"""Writes the fitted GP circuits (W/<id>.lua from fit_gp.py) into
src/shared/TrackData.luau: replaces each `local <Id> = {...}` block (or adds
it before the registry) and makes sure the id is in Order and Tracks.

    python3 -I put_tracks.py
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import W

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
TD = os.path.join(ROOT, "src", "shared", "TrackData.luau")

META = {
    "Catalunya": dict(
        comment="Catalunya (Spanish GP, Barcelona, 2023 layout without the chicane): the\n"
        "-- real centre line at 0.8 studs per metre with its real hills (Copernicus DEM,\n"
        "-- 21 studs from Turn 1 up to Turn 12), the main and back straights shortened.",
        fields='''	Name = "Catalunya",
	Blurb = "Spanish GP, Barcelona - long Turn 3 and hills",
	Laps = 3,
	Lengths = { 2, 3, 5 },
	Qualifying = 150,
	Spacing = 5, -- finer samples on a hilly circuit: a smoother road (TrackLayout road pieces)
	Smoothing = 10,
	BankSmoothing = 22,
	CornerBoards = true,
	Trees = true,'''),
    "Zandvoort": dict(
        comment="Zandvoort (Dutch GP): the real centre line at 0.8 studs per metre through the\n"
        "-- dunes (heights x 1.6 the plan scale so the crests read), the banked\n"
        "-- Hugenholtz hairpin and Arie Luyendyk final corner (12 and 9 degrees), the\n"
        "-- main straight shortened.",
        fields='''	Name = "Zandvoort",
	Blurb = "Dutch GP - dunes and two banked corners",
	Laps = 3,
	Lengths = { 2, 3, 5 },
	Qualifying = 150,
	Spacing = 5, -- finer samples on a hilly circuit: a smoother road (TrackLayout road pieces)
	Smoothing = 10,
	BankSmoothing = 40, -- long bank transitions: a rigid kart rocks on a fast twist
	CornerBoards = true,
	Trees = true,
	Sky = "Cloudy",'''),
    "YasMarina": dict(
        comment="Yas Marina (Abu Dhabi GP, 2021 layout) at sunset (the race starts at dusk): the real\n"
        "-- centre line at 0.8 studs per metre, nearly flat like the real one, the two\n"
        "-- long straights shortened, the long Turn 9 left gently banked.",
        fields='''	Name = "Yas Marina",
	Blurb = "Abu Dhabi GP - sunset race, hairpin and hotel section",
	Laps = 3,
	Lengths = { 2, 3, 5 },
	Qualifying = 150,
	Spacing = 5, -- finer samples: a smoother road on the banked Turn 9
	Smoothing = 10,
	BankSmoothing = 40,
	CornerBoards = true,
	Sky = "Sunset",
	TrackLights = true,'''),
}

src = open(TD).read()
for tid, m in META.items():
    segs = open(os.path.join(W, tid + ".lua")).read().rstrip("\n")
    block = (f"-- {m['comment']}\nlocal {tid} = {{\n\tId = \"{tid}\",\n{m['fields']}\n\tSegments = {{\n"
             f"{segs}\n\t}} :: {{ any }},\n}}\n")
    pat = re.compile(r"(-- [^\n]*\n)*local " + tid + r" = \{\n.*?\n\} :: \{ any \},\n\}\n", re.S)
    pat2 = re.compile(r"(-- [^\n]*\n)*local " + tid + r" = \{\n.*?\n\}\n", re.S)
    if re.search(r"^local " + tid + r" = \{", src, re.M):
        start = src.index(f"local {tid} = {{")
        # back up over the comment lines above it
        while True:
            prev = src.rfind("\n", 0, start - 1)
            line = src[prev + 1:start]
            if line.startswith("--"):
                start = prev + 1
            else:
                break
        end = src.index("\n}\n", src.index(f"local {tid} = {{")) + 3
        src = src[:start] + block + src[end:]
    else:
        at = src.index("local TrackData = {")
        src = src[:at] + block + "\n" + src[at:]
    om = re.search(r"Order = \{([^}]*)\}", src)
    ids = [x.strip().strip('"') for x in om.group(1).split(",") if x.strip()]
    if tid not in ids:
        ids.append(tid)
        src = src[:om.start(1)] + " " + ", ".join(f'"{i}"' for i in ids) + " " + src[om.end(1):]
    tm = re.search(r"\tTracks = \{\n(.*?)\n\t\}", src, re.S)
    if f"\t\t{tid} = {tid}," not in tm.group(1):
        src = src[:tm.end(1)] + f"\n\t\t{tid} = {tid}," + src[tm.end(1):]
open(TD, "w").write(src)
print("TrackData updated")
