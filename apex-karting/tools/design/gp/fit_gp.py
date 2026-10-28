"""Fits a GP circuit as straights + arcs for TrackData, with heights.

    python3 -I fit_gp.py <Catalunya|Zandvoort|YasMarina> [--plot]

Real line: common.real_line (GeoJSON centre line, smoothed, 1 m steps, lap
from the start line). Segments come from the curvature: |k| below STRAIGHT_K
is straight, the rest arcs split at sign changes and every SUB metres.
Parameters (straight lengths, arc radii and angles) are fitted by least
squares to stay near the real ones while the lap closes; the straights in
`cuts` get a shorter target (long kart straights are dull), and the closing
error that leaves is spread over the rest. Non-adjacent centre lines are
kept SEP studs apart. Heights: a robust low envelope of the DEM profile
(structures and trees stick up), grade-limited, relative to the start line,
clamped at the lawn (y 0); the start and grid straights are level.
Writes <id>.json and <id>.lua (Segments for TrackData) into W.
"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from scipy.optimize import least_squares
from scipy.ndimage import percentile_filter
from scipy.spatial import cKDTree
from common import W, real_line, smooth_closed, curvature
from tracks import TRACKS

TID = sys.argv[1]
C = TRACKS[TID]
K = C["K"]
RMIN, SEP = C["RMIN"], C["SEP"]
STRAIGHT_K = C.get("STRAIGHT_K", 0.0022)  # 1/m
SUB = C.get("SUB", 45.0)  # metres per arc piece

x, y, h, lon0, lat0 = real_line(C["gid"])
L = len(x)
k = smooth_closed(-curvature(x, y), C.get("KSIGMA", 4.0))  # + = right turn
TOTAL = 360.0 if k.sum() > 0 else -360.0

# ---------------------------------------------------------------- segmentation
straight = np.abs(k) < STRAIGHT_K
runs = []  # [kind, s0, s1]
i = 0
while i < L:
    j = i
    while j < L and straight[j] == straight[i]:
        j += 1
    runs.append(["S" if straight[i] else "A", i, j])
    i = j
# short straights between arcs become part of the arcs (kept if >= MINS)
MINS = C.get("MINS", 8)
merged = []
for r in runs:
    if r[0] == "S" and r[2] - r[1] < MINS and 0 < r[1] and r[2] < L:
        r = ["A", r[1], r[2]]
    if merged and merged[-1][0] == r[0] == "A":
        merged[-1][2] = r[2]
    else:
        merged.append(r)
runs = merged
assert runs[0][0] == "S" and runs[-1][0] == "S", "the lap must start and end on a straight"

def name_at(s):
    for a, b, n in C["names"]:
        if a <= s < b:
            return n
    return None

raw = []  # dicts: kind, s0, s1, m, ang
for kind, s0, s1 in runs:
    if kind == "S":
        raw.append({"kind": "S", "s0": s0, "s1": s1})
        continue
    # split at sign changes of a clearly curved run, then every SUB metres
    sg = np.sign(np.where(np.abs(k[s0:s1]) < STRAIGHT_K, 0, k[s0:s1]))
    cuts_at = [s0]
    last = 0
    for q in range(s1 - s0):
        if sg[q] != 0:
            if last != 0 and sg[q] != last:
                cuts_at.append(s0 + q)
            last = sg[q]
    cuts_at.append(s1)
    for a, b in zip(cuts_at[:-1], cuts_at[1:]):
        if b - a < 3:
            continue
        ang = math.degrees(k[a:b].sum())
        parts = 1 if abs(ang) < 15 else max(1, min(6, round((b - a) / SUB)))
        edges = np.linspace(a, b, parts + 1).round().astype(int)
        for e0, e1 in zip(edges[:-1], edges[1:]):
            raw.append({"kind": "A", "s0": int(e0), "s1": int(e1), "ang": math.degrees(k[e0:e1].sum())})
# merge arc pieces that turn almost nothing into the neighbouring straight
segs = []
for r in raw:
    r["m"] = r["s1"] - r["s0"]
    r["name"] = name_at((r["s0"] + r["s1"]) / 2)
    if r["kind"] == "A" and abs(r["ang"]) < C.get("KINK", 1.0):
        r = {"kind": "S", "s0": r["s0"], "s1": r["s1"], "m": r["m"], "name": r["name"]}
    if segs and segs[-1]["kind"] == "S" and r["kind"] == "S":
        segs[-1]["s1"] = r["s1"]; segs[-1]["m"] += r["m"]
        segs[-1]["name"] = segs[-1]["name"] or r["name"]
    else:
        segs.append(dict(r))
# angles must add up to +-360 exactly: spread the rest over the arcs
arcs = [q for q in segs if q["kind"] == "A"]
rest = TOTAL - sum(q["ang"] for q in arcs)
arcm = sum(q["m"] for q in arcs)
for q in arcs:
    q["ang"] += rest * q["m"] / arcm
print(f"{TID}: lap {L} m, {len(segs)} segments ({len(arcs)} arcs), angle residual {rest:.2f} deg")

# ---------------------------------------------------------------- targets
nS = [i for i, q in enumerate(segs) if q["kind"] == "S"]
nA = [i for i, q in enumerate(segs) if q["kind"] == "A"]
cut = {}  # segment index -> target length (studs)
groups = []  # (cut straights, compensating ranges)
for a, b, studs, comp_ranges in C.get("cuts", []):
    inside = [i for i in nS if a <= (segs[i]["s0"] + segs[i]["s1"]) / 2 < b]
    tot = sum(segs[i]["m"] * K for i in inside)
    for i in inside:
        cut[i] = segs[i]["m"] * K * studs / tot
    groups.append((inside, comp_ranges))
p0, lo, hi, sig = [], [], [], []
for i in nS:
    Lr = segs[i]["m"] * K
    t = cut.get(i, Lr)
    p0.append(t); lo.append(max(4.0, min(t, Lr) * 0.6)); hi.append(max(t, Lr) * 1.35 + 10)
    sig.append(2.0 if i in cut else max(4.0, 0.1 * Lr))
for i in nA:
    q = segs[i]
    r0 = max(RMIN, q["m"] * K / max(math.radians(abs(q["ang"])), 1e-6))
    q["r0"] = r0
    p0.append(r0); lo.append(RMIN - 1e-6); hi.append(max(r0 * 1.4, RMIN + 1) + 1)
    sig.append(max(3.0, 0.1 * r0))
for i in nA:
    a = segs[i]["ang"]
    p0.append(a); lo.append(a - max(4.0, abs(a) * 0.15)); hi.append(a + max(4.0, abs(a) * 0.15))
    sig.append(max(1.5, abs(a) * 0.05))
p0, sig = np.array(p0), np.array(sig) * C.get("PARAM_SIGMA", 2.0)
target = p0.copy()
nP = len(nS) + len(nA)

# the real line in studs, start heading +X, Roblox x/z (z = -north); each
# cut straight is shortened in place (everything after it moves back along
# it) and the gap that leaves at the end of the lap is spread along the lap
h0r = math.atan2(y[20] - y[0], x[20] - x[0])
c_, s_ = math.cos(-h0r), math.sin(-h0r)
RX = (x * c_ - y * s_) * K
RZ = -(x * s_ + y * c_) * K
shift = np.zeros((L + 1, 2))
from scipy.optimize import lsq_linear

def direction(q):
    a_, b_ = q["s0"], min(q["s1"], L - 1)
    d = np.array([RX[b_] - RX[a_], RZ[b_] - RZ[a_]])
    return d / max(np.linalg.norm(d), 1e-9)

def stretch(q, change):
    """Lengthen straight q by `change` studs in the target line."""
    ramp = np.clip((np.arange(L + 1) - q["s0"]) / max(q["m"], 1), 0, 1)
    return np.outer(ramp, direction(q) * change)

# each cut is paired with compensating straights (pointing the other way)
# whose lengths change so that this cut alone leaves no gap: the corners
# in between keep their places
for inside, comp_ranges in groups:
    g = np.zeros(2)
    for i in inside:
        lost = segs[i]["m"] * K - cut[i]
        shift += stretch(segs[i], -lost)
        g -= direction(segs[i]) * lost
    comp = [i for i in nS if i not in cut and any(a <= (segs[i]["s0"] + segs[i]["s1"]) / 2 < b for a, b in comp_ranges)]
    if not comp:
        continue
    D = np.array([direction(segs[i]) for i in comp]).T
    lens = np.array([segs[i]["m"] * K for i in comp])
    W8 = 30.0
    A = np.vstack([D * lens * W8, 0.05 * np.eye(len(comp))])
    u = lsq_linear(A, np.r_[-g * W8, np.zeros(len(comp))], bounds=(-0.7, 0.5)).x
    for i, uu, ln in zip(comp, u, lens):
        cut[i] = ln * (1 + uu)
        shift += stretch(segs[i], ln * uu)
        j = nS.index(i)
        p0[j] = target[j] = cut[i]; sig[j] = 2.0 * C.get("PARAM_SIGMA", 2.0)
        lo[j] = min(lo[j], cut[i] * 0.8); hi[j] = max(hi[j], cut[i] * 1.2 + 4)
        print(f"  compensating straight {segs[i]['s0']}..{segs[i]['s1']} m: {ln:.0f} -> {cut[i]:.0f} studs")
TX = np.r_[RX, RX[0]] + shift[:, 0]
TZ = np.r_[RZ, RZ[0]] + shift[:, 1]
gap = np.array([TX[-1] - TX[0], TZ[-1] - TZ[0]])
frac = np.arange(L + 1) / L
TX -= gap[0] * frac; TZ -= gap[1] * frac
tgt = np.array([(TX[q["s1"]], TZ[q["s1"]]) for q in segs])
POS = C.get("POS_SIGMA", 4.0)
print(f"cuts leave a {np.hypot(*gap):.0f} stud gap, spread along the lap")

def layout(p):
    """-> per-segment kind/params in lap order."""
    out = [None] * len(segs)
    for j, i in enumerate(nS):
        out[i] = ("S", p[j], 0.0)
    for j, i in enumerate(nA):
        out[i] = ("A", p[len(nS) + j], p[nP + j])
    return out

def walk(p, step=None):
    x_ = z_ = th = 0.0
    pts, ends = [], []
    for kseg, (kind, a, b) in enumerate(layout(p)):
        if kind == "S":
            if step:
                n = max(1, int(a / step))
                for t in np.arange(n) / n:
                    pts.append((x_ + math.cos(th) * a * t, z_ + math.sin(th) * a * t, kseg))
            x_ += math.cos(th) * a; z_ += math.sin(th) * a
        else:
            ang = math.radians(b); sgn = 1 if ang >= 0 else -1
            cx = x_ + math.cos(th + math.pi / 2) * a * sgn
            cz = z_ + math.sin(th + math.pi / 2) * a * sgn
            a0 = math.atan2(z_ - cz, x_ - cx)
            if step:
                n = max(1, int(a * abs(ang) / step))
                for t in np.arange(n) / n:
                    pts.append((cx + math.cos(a0 + ang * t) * a, cz + math.sin(a0 + ang * t) * a, kseg))
            x_, z_ = cx + math.cos(a0 + ang) * a, cz + math.sin(a0 + ang) * a
            th += ang
        ends.append((x_, z_))
    return np.array(ends), pts

NSEP = 500
def sep_resid(pts):
    P = np.array([(q[0], q[1]) for q in pts])
    cum = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    tot = cum[-1]
    tree = cKDTree(P)
    pick = np.linspace(0, len(P) - 1, NSEP).round().astype(int)
    out = np.zeros(NSEP)
    for n_, i in enumerate(pick):
        best = SEP
        for j in tree.query_ball_point(P[i], SEP):
            dd = abs(cum[i] - cum[j]); dd = min(dd, tot - dd)
            if dd < SEP * 3.2:
                continue
            best = min(best, float(np.hypot(*(P[i] - P[j]))))
        out[n_] = (SEP - best) * 2.0
    return out

# extra gaps between two stretches (config `pairsep`: real-metre ranges and
# studs): e.g. a raised road beside a low one whose wide gravel trap would
# otherwise reach under it
PAIRS = []
for (a0, a1), (b0, b1), dmin in C.get("pairsep", []):
    A_ = [i for i, q in enumerate(segs) if q["s1"] > a0 and q["s0"] < a1]
    B_ = [i for i, q in enumerate(segs) if q["s1"] > b0 and q["s0"] < b1]
    PAIRS.append((set(A_), set(B_), dmin))

def pair_resid(pts):
    out = []
    P = np.array([(q[0], q[1]) for q in pts]); so = np.array([q[2] for q in pts])
    for A_, B_, dmin in PAIRS:
        ma = np.isin(so, list(A_)); mb = np.isin(so, list(B_))
        if not ma.any() or not mb.any():
            out.append(0.0)
            continue
        d = np.min(np.hypot(*(P[ma][:, None, :] - P[mb][None, :, :]).transpose(2, 0, 1)))
        out.append(max(0.0, dmin - d) * 3.0)
    return np.array(out)

def resid(p):
    E, pts = walk(p, step=6)
    close = E[-1] * 4.0
    turn = (np.sum(p[nP:]) - TOTAL) * 40.0
    return np.r_[close, turn, (p - target) / sig, ((E - tgt) / POS).ravel(), sep_resid(pts), pair_resid(pts)]

sol = least_squares(resid, p0, bounds=(np.array(lo), np.array(hi)), max_nfev=300)
p = sol.x
p[nP:] += (TOTAL - p[nP:].sum()) / len(nA)
E, pts = walk(p, step=2)
print(f"closing gap {np.hypot(*E[-1]):.2f} studs, separation worst {SEP - max(sep_resid(pts)) / 2:.1f} (min {SEP})")
for (A_, B_, dmin), r_ in zip(PAIRS, pair_resid(pts)):
    print(f"  pair gap short by {r_ / 3:.1f} studs (min {dmin})")
for i in cut:
    print(f"  cut straight at {segs[i]['s0']}..{segs[i]['s1']} m: {segs[i]['m'] * K:.0f} -> {p[nS.index(i)]:.0f} studs")

# ---------------------------------------------------------------- heights
hr = percentile_filter(h, C.get("HPCT", 25), size=C.get("HWIN", 61), mode="wrap")
hr = smooth_closed(hr, C.get("HSIGMA", 25.0))
G = C.get("GRADE", 0.07)
for _ in range(400):  # grade limit (per real metre)
    d = np.diff(np.r_[hr, hr[0]])
    over = np.abs(d) > G
    if not over.any():
        break
    hr = smooth_closed(hr, 2.0) if _ % 50 == 49 else hr
    for i in np.where(over)[0]:
        mid = (hr[i] + hr[(i + 1) % L]) / 2
        hr[i] = mid - np.sign(d[i]) * G / 2
        hr[(i + 1) % L] = mid + np.sign(d[i]) * G / 2
h0 = np.percentile(hr, C.get("DATUM_PCT", 5))  # this height = the lawn (y 0)
KY = C.get("KY", K)
lay = layout(p)
ys = []
for q in segs:
    ys.append(max(0.0, (hr[q["s1"] % L] - h0) * KY))
for a, b, ymin in C.get("ymin", []):
    for i, q in enumerate(segs):
        if a <= q["s1"] <= b:
            ys[i] = max(ys[i], ymin)
for a, b, ymax in C.get("ymax", []):
    for i, q in enumerate(segs):
        if a <= q["s1"] <= b:
            ys[i] = min(ys[i], ymax)

# ---------------------------------------------------------------- output
out = []
for i, (q, (kind, a, b)) in enumerate(zip(segs, lay)):
    e = {"kind": kind, "y": round(ys[i], 1), "s0": q["s0"], "s1": q["s1"]}
    if kind == "S":
        e["length"] = round(a, 1)
    else:
        e["radius"] = round(a, 1); e["angle"] = round(b, 2)
        if q["name"] and q["name"] in C.get("bank", {}):
            e["bank"] = C["bank"][q["name"]]
    if q["name"] and kind == "A":
        e["name"] = q["name"]
    out.append(e)
# rounded angles must still add up to exactly +-360: the biggest arc takes the rest
big = max((e for e in out if e["kind"] == "A"), key=lambda e: abs(e["angle"]))
big["angle"] = round(big["angle"] + TOTAL - sum(e["angle"] for e in out if e["kind"] == "A"), 2)
# exact closure: two straights become "free" (TrackMath solves them): the
# pair (not the start or grid straight) that is long and far from parallel
heads, th = [], 0.0
for kind, a, b in lay:
    heads.append(th)
    if kind == "A":
        th += math.radians(b)
cand = [i for i in nS if 0 < i < len(segs) - 1 and i not in cut]
best, pair = -1, None
for ii, i in enumerate(cand):
    for j in cand[ii + 1:]:
        sc = min(out[i]["length"], out[j]["length"]) * abs(math.sin(heads[i] - heads[j]))
        if sc > best:
            best, pair = sc, (i, j)
for i in pair:
    out[i]["length"] = "free"
# start and grid: the first straight level for LEVEL0 studs, the last
# straight split into a slope and a level part LEVEL1 long
L0, L1 = C.get("LEVEL0", 120), C.get("LEVEL1", 220)
first, last = out[0], out[-1]
if first["length"] != "free" and first["length"] > L0 + 40 and first["y"] > 0:
    rest_ = first["length"] - L0
    out[0] = dict(first, length=L0, y=0.0)
    out.insert(1, {"kind": "S", "length": round(rest_, 1), "y": first["y"]})
else:
    out[0]["y"] = 0.0
last = out[-1]
if last["length"] != "free" and last["length"] > L1 + 40:
    out[-1] = dict(last, length=round(last["length"] - L1, 1), y=0.0)
    out.append({"kind": "S", "length": float(L1), "y": 0.0})
out[-1]["y"] = 0.0
out[-2]["y"] = min(out[-2]["y"], 0.0) if out[-2]["kind"] == "S" else out[-2]["y"]
for key, w in C.get("width", {}).items():
    out[key]["width"] = w

json.dump({"segs": out, "real": np.c_[x, y, hr].tolist(), "K": K, "fit": [list(q) for q in pts[::3]]},
          open(W + TID + ".json", "w"), default=float)

def num(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")
lines = []
for s in out:
    parts = [f'kind = "{s["kind"]}"']
    if s["kind"] == "S":
        parts.append('length = "free"' if s["length"] == "free" else f'length = {num(s["length"])}')
    else:
        parts += [f'radius = {num(s["radius"])}', f'angle = {num(s["angle"])}']
        if "bank" in s:
            parts.append(f'bank = {s["bank"]}')
    parts.append(f'y = {num(s["y"])}')
    if "width" in s:
        parts.append(f'width = {s["width"]}')
    if s.get("name"):
        parts.append(f'name = "{s["name"]}"')
    lines.append("\t\t{ " + ", ".join(parts) + " },")
open(W + TID + ".lua", "w").write("\n".join(lines) + "\n")
lap = sum((s["length"] if s["kind"] == "S" and s["length"] != "free" else 0) for s in out) + \
    sum(s["radius"] * math.radians(abs(s["angle"])) for s in out if s["kind"] == "A")
print(f"{len(out)} segments, about {lap:.0f} studs + free, y {min(s['y'] for s in out)}..{max(s['y'] for s in out)}")

if "--plot" in sys.argv:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    RY = RZ
    P = np.array([(q[0], q[1]) for q in pts])
    fig, ax = plt.subplots(1, 2, figsize=(20, 9), gridspec_kw={"width_ratios": [1.3, 1]})
    ax[0].plot(RX, RY, "-", color="0.75", lw=6, label="real (x K)")
    ax[0].plot(TX, TZ, "-", color="c", lw=1, label="target (cuts)")
    ax[0].plot(P[:, 0], P[:, 1], "-r", lw=1.2, label="fitted")
    for i, (e, q) in enumerate(zip(E, segs)):
        ax[0].annotate(str(i), e, fontsize=7)
        if q["name"] and (i == 0 or segs[i - 1]["name"] != q["name"]):
            ax[0].annotate(q["name"], e, fontsize=9, color="b")
    ax[0].plot(0, 0, "og"); ax[0].set_aspect("equal"); ax[0].invert_yaxis(); ax[0].legend()
    ax[0].set_title(f"{TID} plan (z down = south)")
    ss = np.arange(L)
    ax[1].plot(ss, (h - h0) * KY, lw=0.5, color="0.6", label="DEM")
    ax[1].plot(ss, (hr - h0) * KY, lw=2, label="used (x KY)")
    ax[1].plot([q["s1"] for q in segs], ys, ".k")
    ax[1].legend(); ax[1].grid(alpha=0.3); ax[1].set_title("height (studs) vs real metres")
    plt.tight_layout(); plt.savefig(W + TID + ".png", dpi=70)
