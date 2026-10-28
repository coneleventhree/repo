"""suzuka_fit2.json -> Lua segments with heights (y), widths and the crossing.

    python3 -I gen_lua.py suzuka_fit2.json out.lua [KY LOW DECK]
"""
import json, re, sys
import numpy as np

W = "/tmp/claude-0/-home-claude/27a95dec-38e2-5550-9411-57feb6028f64/scratchpad/suzuka/"
fit, out = sys.argv[1], sys.argv[2]
KY = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8
LOW = float(sys.argv[4]) if len(sys.argv) > 4 else 14.0   # lower road under the bridge
DECK = float(sys.argv[5]) if len(sys.argv) > 5 else 30.0  # back straight over it
START = 337
J = json.load(open(fit))
segs, bounds = J["segs"], J["bounds"]

toml = open(W + "dl/suzuka.toml").read()
keys = [(float(a), float(b)) for a, b in re.findall(r'\[\[elevation\.key\]\]\s*\ns = ([\d.]+)\s*\ny = ([-\d.]+)', toml)]
ks = np.array([k[0] for k in keys]); kh = np.array([k[1] for k in keys])
def real_h(t_s):  # TUMFTM s -> metres above the lowest point (Second Curve)
    toml_s = ((t_s - 37) * 5811 / 5803) % 5811
    return float(np.interp(toml_s, np.r_[ks, 5811], np.r_[kh, kh[0]])) + 20.1

out_segs = []
for k, (s, b) in enumerate(zip(segs, bounds)):
    e = dict(s)
    e["y"] = round(real_h(b + START) * KY, 1)
    out_segs.append(e)

def idx(pred):
    return [i for i, s in enumerate(out_segs) if pred(s)]

# 1. start line to the Second Curve: level at the lawn (pits and grid at y = 0)
second = idx(lambda s: s.get("name") == "Second Curve")[0]
for i in range(0, second):
    out_segs[i]["y"] = 0.0

# 2. Last Curve: down from the chicane to LCX, then the main straight drops to 0
#    over SLOPE studs and stays level to the line (the grid and the pits)
SLOPE = 120.0
last = len(out_segs) - 1
assert out_segs[last].get("name") == "Main straight" and out_segs[last]["kind"] == "S"
chic = idx(lambda s: s.get("name") == "Casio Triangle")[-1]
y0 = out_segs[chic]["y"]
lens = []
for i in range(chic + 1, last):
    s = out_segs[i]
    lens.append(s["length"] if s["kind"] == "S" else s["radius"] * abs(np.radians(s["angle"])))
tot = sum(lens); acc = 0
LCX = y0 * SLOPE / (tot + SLOPE)  # one even slope from the chicane to the level part
for i, L in zip(range(chic + 1, last), lens):
    acc += L
    out_segs[i]["y"] = round(y0 + (LCX - y0) * acc / tot, 1)
ms = out_segs[last]
total_len = ms["length"]
out_segs[last] = dict(ms, length=round(SLOPE, 1), y=0.0)
out_segs.append({"kind": "S", "length": round(total_len - SLOPE, 1), "y": 0.0, "level": True})

# 3. the crossing: the straight after Degner 2 dips under the bridge
d2 = idx(lambda s: s.get("name") == "Degner 2")[-1]
under = d2 + 1
assert out_segs[under]["kind"] == "S"
U = out_segs[under]["length"]
CROSS_AT = float(sys.argv[6]) if len(sys.argv) > 6 else 50.0  # studs into that straight
a = CROSS_AT + 35
out_segs[d2]["y"] = round(LOW + 3, 1)
nxt_y = out_segs[under]["y"]
out_segs[under] = {"kind": "S", "length": round(a, 1), "y": LOW, "name": "Under the bridge"}
out_segs.insert(under + 1, {"kind": "S", "length": round(U - a, 1), "y": nxt_y})
# the back straight's free part ends just after the bridge
fr = idx(lambda s: s.get("length") == "free")[1]
out_segs[fr]["y"] = DECK
# 130R stays up at deck level, then the gentle rise to the chicane as before
r130 = idx(lambda s: s.get("name") == "130R")
for i in r130:
    out_segs[i]["y"] = round(max(out_segs[i]["y"], DECK), 1)

# widths and banking
for s in out_segs:
    s.pop("m", None)
out_segs[0]["width"] = 30
out_segs[1]["width"] = 28
for s in out_segs:
    if s.get("name") == "Gyaku Bank":
        pass  # the real one is off-camber; any negative bank throws karts off here
for s in out_segs:
    if s.get("name") == "Main straight" and s is not out_segs[0]:
        s["width"] = 30

def num(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")

lines = []
for s in out_segs:
    parts = [f'kind = "{s["kind"]}"']
    if s["kind"] == "S":
        parts.append('length = "free"' if s["length"] == "free" else f'length = {num(s["length"])}')
    else:
        parts.append(f'radius = {num(s["radius"])}')
        parts.append(f'angle = {num(s["angle"])}')
        if "bank" in s:
            parts.append(f'bank = {s["bank"]}')
    parts.append(f'y = {num(s["y"])}')
    if "width" in s:
        parts.append(f'width = {s["width"]}')
    if s.get("name"):
        parts.append(f'name = "{s["name"]}"')
    lines.append("\t\t{ " + ", ".join(parts) + " },")
open(out, "w").write("\n".join(lines) + "\n")
ang = sum(s["angle"] for s in out_segs if s["kind"] == "A")
print(f"{len(out_segs)} segments, total angle {ang:.4f}, y range {min(s['y'] for s in out_segs)} .. {max(s['y'] for s in out_segs)}")
