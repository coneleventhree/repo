"""Suzuka (GP layout, figure of eight) as straights + arcs for TrackData.

Centre line: TUMFTM racetrack-database (OSM based, LGPL-3.0), res.npy made from
it (s, x, y, curvature per metre). Heights: GSI 5 m laser ground model keys
(every 50 m from the timing line) as collected in suzuka.toml.

K studs per real metre, RMIN minimum radius (studs), WIDTH road width (studs).
The lap starts at the real start line (the first-corner end of the pits).
Writes suzuka_fit.json / .lua and plots.
"""
import json, math, re, sys
import numpy as np
from scipy.optimize import least_squares

W = "/tmp/claude-0/-home-claude/27a95dec-38e2-5550-9411-57feb6028f64/scratchpad/suzuka/"
K = float(sys.argv[1]) if len(sys.argv) > 1 else 0.8
RMIN = float(sys.argv[2]) if len(sys.argv) > 2 else 32.0
WIDTH = float(sys.argv[3]) if len(sys.argv) > 3 else 28.0
KY = float(sys.argv[4]) if len(sys.argv) > 4 else 0.8
SEP = float(sys.argv[5]) if len(sys.argv) > 5 else 46.0  # min centre-line gap (studs) between non-adjacent roads
OUT = W + "work/suzuka_fit"

ss, X, Y, KM = np.load(W + "work/res.npy").T
L = len(ss)  # 1 m steps
START = 337  # TUMFTM s of the real start line (toml 300 + 37)
# rotate so index 0 = start line
X = np.roll(X, -START); Y = np.roll(Y, -START); KM = np.roll(KM, -START)
KS = -KM  # + = right turn (TrackMath)

def r(a):  # TUMFTM s -> our s
    return (a - START) % L

# kind, from, to (TUMFTM metres), name; F = free straight
RAW = [
    ("S", 337, 639, "Main straight"),
    ("A", 639, 748, "First Curve"),
    ("S", 748, 771, None),
    ("A", 771, 931, "Second Curve"),
    ("S", 931, 1057, None),
    ("A", 1057, 1161, "S Curves"),
    ("S", 1161, 1172, None),
    ("A", 1172, 1273, "S Curves"),
    ("S", 1273, 1321, None),
    ("A", 1321, 1454, "S Curves"),
    ("S", 1454, 1473, None),
    ("A", 1473, 1644, "Gyaku Bank"),
    ("S", 1644, 1694, None),
    ("A", 1694, 1856, "Dunlop"),
    ("S", 1856, 1876, None),
    ("A", 1876, 2020, "Dunlop"),
    ("S", 2020, 2047, None),
    ("A", 2047, 2133, None),
    ("F", 2133, 2273, None),
    ("A", 2273, 2321, "Degner 1"),
    ("S", 2321, 2422, None),
    ("A", 2422, 2484, "Degner 2"),
    ("S", 2484, 2735, None),  # under the bridge
    ("A", 2735, 2824, "110R"),
    ("S", 2824, 2873, None),
    ("A", 2873, 2978, "Hairpin"),
    ("S", 2978, 3083, None),
    ("A", 3083, 3231, "200R"),
    ("S", 3231, 3253, None),
    ("A", 3253, 3341, None),
    ("S", 3341, 3427, None),
    ("A", 3427, 3633, None),
    ("S", 3633, 3766, None),
    ("A", 3766, 4096, "Spoon Curve"),
    ("F", 4096, 4447, "Back straight"),
    ("A", 4447, 4465, None),
    ("S", 4465, 4936, "Back straight"),  # over the bridge
    ("A", 4936, 5009, "130R"),
    ("S", 5009, 5153, None),
    ("S", 5153, 5363, None),
    ("A", 5363, 5417, "Casio Triangle"),
    ("S", 5417, 5420, None),
    ("A", 5420, 5475, "Casio Triangle"),
    ("S", 5475, 5481, None),
    ("A", 5481, 5586, "Last Curve"),
    ("S", 5586, 5603, None),
    ("A", 5603, 5734, "Last Curve"),
    ("S", 5734, 5803 + 337, "Main straight"),
]
RANGES = [(k, r(a), (r(b - 1) + 1), n) for k, a, b, n in RAW]
SUB = 45.0

def build_segments():
    raw, bounds = [], []
    for kind, s0, s1, name in RANGES:
        if kind in ("S", "F"):
            raw.append({"kind": "S", "m": s1 - s0, "free": kind == "F", "name": name})
            bounds.append(s1)
            continue
        ang_total = math.degrees(KS[s0:s1].sum())
        parts = 1 if abs(ang_total) < 20 else max(1, min(5, round((s1 - s0) / SUB)))
        edges = np.linspace(s0, s1, parts + 1).round().astype(int)
        for j in range(parts):
            a0, a1 = edges[j], edges[j + 1]
            raw.append({"kind": "A", "m": a1 - a0, "ang": math.degrees(KS[a0:a1].sum()), "name": name})
            bounds.append(a1)
    total = sum(r_["ang"] for r_ in raw if r_["kind"] == "A")
    resid = 0.0 - total
    lens = sum(r_["m"] for r_ in raw if r_["kind"] == "A")
    segs = []
    for r_ in raw:
        if r_["kind"] == "S":
            seg = {"kind": "S", "length": "free" if r_["free"] else round(r_["m"] * K, 1), "m": r_["m"]}
        else:
            ang = r_["ang"] + resid * r_["m"] / lens
            rad = max((r_["m"] * K) / max(math.radians(abs(ang)), 1e-6), RMIN)
            seg = {"kind": "A", "radius": round(min(rad, 99999), 1), "angle": round(ang, 2), "m": r_["m"]}
        if r_["name"]:
            seg["name"] = r_["name"]
        segs.append(seg)
    return segs, bounds, resid

def walk(segs, free, step=1.0, lens=None):
    x = z = th = 0.0
    pts = []
    f = 0
    for kseg, seg in enumerate(segs):
        if seg["kind"] == "S":
            Ls = free[f] if seg["length"] == "free" else seg["length"]
            if seg["length"] == "free":
                f += 1
            d = (math.cos(th), math.sin(th))
            cnt = max(1, int(Ls / step + 0.5))
            for j in range(cnt):
                t = j / cnt
                pts.append((x + d[0] * Ls * t, z + d[1] * Ls * t, kseg))
            x += d[0] * Ls; z += d[1] * Ls
        else:
            rr = seg["radius"]; ang = math.radians(seg["angle"]); sg = 1 if ang >= 0 else -1
            rd = (math.cos(th + math.pi / 2), math.sin(th + math.pi / 2))
            cx, cz = x + rd[0] * rr * sg, z + rd[1] * rr * sg
            a0 = math.atan2(z - cz, x - cx)
            Ls = rr * abs(ang)
            cnt = max(1, int(Ls / step + 0.5))
            for j in range(cnt):
                a = a0 + ang * j / cnt
                pts.append((cx + math.cos(a) * rr, cz + math.sin(a) * rr, kseg))
            a1 = a0 + ang
            x, z = cx + math.cos(a1) * rr, cz + math.sin(a1) * rr
            th += ang
    return x, z, th, pts

def solve(segs):
    dirs = []
    th = 0
    for seg in segs:
        if seg["kind"] == "S":
            if seg["length"] == "free":
                dirs.append((math.cos(th), math.sin(th)))
        else:
            th += math.radians(seg["angle"])
    ex, ez, _, _ = walk(segs, [0, 0], step=50)
    a, b, c, d = dirs[0][0], dirs[1][0], dirs[0][1], dirs[1][1]
    det = a * d - b * c
    return [(-ex * d + b * ez) / det, (-a * ez + c * ex) / det]

segs, bounds, resid = build_segments()
print(f"K={K} RMIN={RMIN}: residual angle {resid:.2f} deg, {len(segs)} segments")

# real line in studs, start heading +X, Roblox x/z (z = -y)
h0 = math.atan2(Y[20] - Y[0], X[20] - X[0])
c, s_ = math.cos(-h0), math.sin(-h0)
RX = ((X - X[0]) * c - (Y - Y[0]) * s_) * K
RY = ((X - X[0]) * s_ + (Y - Y[0]) * c) * K
real = np.c_[RX, -RY]

target = np.array([real[min(int(b), L - 1) if b < L else 0] for b in bounds])
arcs = [i for i, s in enumerate(segs) if s["kind"] == "A"]
ang0 = np.array([segs[i]["angle"] for i in arcs])
nseg = len(segs)

def endpoints(params, dense=False):
    x = z = th = 0.0
    out, pts = [], []
    angs = params[nseg:]
    ai = 0
    for k_, (seg, p) in enumerate(zip(segs, params[:nseg])):
        if seg["kind"] == "S":
            if dense:
                for t in np.linspace(0, 1, max(2, int(p / 8)))[:-1]:
                    pts.append((x + math.cos(th) * p * t, z + math.sin(th) * p * t, k_))
            x += math.cos(th) * p; z += math.sin(th) * p
        else:
            ang = math.radians(angs[ai]); ai += 1
            sg = 1 if ang >= 0 else -1
            rdx, rdz = math.cos(th + math.pi / 2), math.sin(th + math.pi / 2)
            cx, cz = x + rdx * p * sg, z + rdz * p * sg
            a0 = math.atan2(z - cz, x - cx)
            if dense:
                for t in np.linspace(0, 1, max(2, int(p * abs(ang) / 8)))[:-1]:
                    a = a0 + ang * t
                    pts.append((cx + math.cos(a) * p, cz + math.sin(a) * p, k_))
            a1 = a0 + ang
            x, z = cx + math.cos(a1) * p, cz + math.sin(a1) * p
            th += ang
        out.append((x, z))
    if dense:
        return np.array(out), pts
    return np.array(out)

# which segments are the back straight and the Spoon approach (keep them apart)
segB = [i for i, s in enumerate(segs) if s.get("name") == "Back straight"]
first_spoon = min(i for i, s in enumerate(segs) if s.get("name") == "Spoon Curve")
segA = list(range(first_spoon - 5, first_spoon))  # 200R exit .. before Spoon

p0, lo, hi = [], [], []
prev_b = 0
for i, seg in enumerate(segs):
    if seg["kind"] == "S":
        L0 = seg["m"] * K
        p0.append(L0); lo.append(0.0); hi.append(np.inf)
    else:
        p0.append(seg["radius"]); lo.append(RMIN); hi.append(np.inf)
for a in ang0:
    p0.append(a); lo.append(a - max(4.0, abs(a) * 0.12)); hi.append(a + max(4.0, abs(a) * 0.12))

def resid_fn(p):
    E, pts = endpoints(p, dense=True)
    e = (E - target).ravel()
    P = np.array([(q[0], q[1]) for q in pts]); seg_of = np.array([q[2] for q in pts])
    A_ = P[np.isin(seg_of, segA)]; B_ = P[np.isin(seg_of, segB)]
    sep = np.zeros(40)
    if len(A_) and len(B_):
        A_ = A_[np.linspace(0, len(A_) - 1, 40).round().astype(int)]
        d = np.sqrt(((A_[:, None, :] - B_[None, :, :]) ** 2).sum(-1)).min(axis=1)
        sep = np.maximum(SEP - d, 0) * 3.0
    return np.r_[e, (np.sum(p[nseg:]) - 0.0) * 50.0, (p[nseg:] - ang0) * 0.6, sep]

sol = least_squares(resid_fn, np.array(p0), bounds=(np.array(lo), np.array(hi)), max_nfev=400)
for i, a in zip(arcs, sol.x[nseg:]):
    segs[i]["angle"] = round(float(a), 2)
s_tot = sum(x["angle"] for x in segs if x["kind"] == "A")
big = max((x for x in segs if x["kind"] == "A"), key=lambda x: abs(x["angle"]))
big["angle"] = round(big["angle"] - s_tot, 2)
E = endpoints(sol.x)
print(f"boundary error: mean {np.mean(np.hypot(*(E - target).T)):.1f}, max {np.max(np.hypot(*(E - target).T)):.1f} studs")
for seg, p in zip(segs, sol.x[:nseg]):
    if seg["kind"] == "S":
        if seg["length"] != "free":
            seg["length"] = round(float(p), 1)
    else:
        seg["radius"] = round(float(p), 1)
free = solve(segs)
_, _, _, pts = walk(segs, free)
P = np.array([(q[0], q[1]) for q in pts])
dev = np.array([np.min(np.hypot(*(real - q).T)) for q in P[::5]])
print(f"free {free[0]:.0f} / {free[1]:.0f}, lap {len(P)} studs, deviation from the real line mean {dev.mean():.1f}, max {dev.max():.1f}")

# ---------------------------------------------------------------- heights
toml = open(W + "dl/suzuka.toml").read()
keys = [(float(a), float(b)) for a, b in re.findall(r'\[\[elevation\.key\]\]\s*\ns = ([\d.]+)\s*\ny = ([-\d.]+)', toml)]
ks = np.array([k_[0] for k_ in keys]); kh = np.array([k_[1] for k_ in keys])
def real_h(t_s):  # TUMFTM s -> metres above the lowest point (Second Curve)
    toml_s = ((t_s - 37) * 5811 / 5803) % 5811
    return np.interp(toml_s, np.r_[ks, 5811], np.r_[kh, 0]) + 20.1

json.dump({"segs": segs, "bounds": [int(b) for b in bounds], "free": [float(f) for f in free], "real": real.tolist()}, open(OUT + ".json", "w"), default=float)
print("segments:", len(segs))
