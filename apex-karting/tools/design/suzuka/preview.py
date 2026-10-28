import sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import LinearSegmentedColormap
S = "/tmp/claude-0/-home-claude/27a95dec-38e2-5550-9411-57feb6028f64/scratchpad/suzuka/work/"
OUT = sys.argv[1]
T = np.array([[float(v) for v in l.split(",")] for l in open(S + "suzuka_track.csv") if not l.startswith("#")])
x, y, z, w = T[:, 2], T[:, 3], T[:, 4], T[:, 8]
s = T[:, 1]; n = len(T)
sp = {}
names = {}
for l in open(S + "suzuka_speed.csv"):
    if l.startswith("#"):
        continue
    p = l.rstrip("\n").split(",")
    sp[int(p[0])] = float(p[4]); names[int(p[0])] = p[10]
kmh = np.array([sp.get(i + 1, np.nan) for i in range(n)])
nm = [names.get(i + 1, "") for i in range(n)]

INK, MUTED, GRID, BG = "#1f1f1d", "#6b6a66", "#e4e2dc", "#fbfaf7"
ramp = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
cmap = LinearSegmentedColormap.from_list("h", ramp)
plt.rcParams.update({"font.family": "DejaVu Sans", "text.color": INK, "axes.labelcolor": MUTED,
                     "xtick.color": MUTED, "ytick.color": MUTED, "axes.edgecolor": GRID})

# crossing samples
P = np.c_[x, z]
best = (1e9, 0, 0)
for a in range(n):
    d = np.hypot(*(P - P[a]).T)
    sep = np.minimum(abs(np.arange(n) - a), n - abs(np.arange(n) - a)); d[sep < 40] = 1e9
    b = int(np.argmin(d))
    if d[b] < best[0]:
        best = (d[b], a, b)
_, a, b = best
lo, hi = (a, b) if y[a] < y[b] else (b, a)

fig = plt.figure(figsize=(16, 13), facecolor=BG)
gs = fig.add_gridspec(2, 2, height_ratios=[1.75, 1], wspace=0.1, hspace=0.18,
                      left=0.04, right=0.98, top=0.92, bottom=0.05)
ax = fig.add_subplot(gs[0, :]); ax.set_facecolor(BG)
fig.suptitle("Suzuka (figure of eight) - 3D layout preview", x=0.03, ha="left", fontsize=17, fontweight="bold")
fig.text(0.03, 0.94, f"Lap {s[-1] + s[1]:.0f} studs  |  road 28 studs wide (start straight 30)  |  height 0-{y.max():.1f} studs  |  autopilot lap 69.6 s (players ~63-66 s)",
         ha="left", fontsize=11, color=MUTED)

# road: casing then colour by height; the bridge pass drawn last so it sits on top
def road(idx, lw):
    pts = np.c_[x[idx], z[idx]]
    segs = np.stack([pts[:-1], pts[1:]], 1)
    ax.add_collection(LineCollection(segs, colors="#ffffff", linewidths=lw + 4, capstyle="round", zorder=2))
    lc = LineCollection(segs, cmap=cmap, norm=plt.Normalize(0, y.max()), linewidths=lw, capstyle="round", zorder=3)
    lc.set_array((y[idx][:-1] + y[idx][1:]) / 2); ax.add_collection(lc)
    return lc
order = np.r_[np.arange(n), 0]
over = set(range(hi - 12, hi + 13))
rest = [i for i in order if i not in over]
# split rest into contiguous runs
runs, cur = [], [rest[0]]
for i in rest[1:]:
    if i == cur[-1] + 1 or (cur[-1] == n - 1 and i == 0):
        cur.append(i)
    else:
        runs.append(cur); cur = [i]
runs.append(cur)
for r in runs:
    lc = road(np.array(r), 6.5)
lc = road(np.arange(hi - 13, hi + 14) % n, 6.5)
cax = ax.inset_axes([0.76, 0.08, 0.2, 0.022])
cb = fig.colorbar(lc, cax=cax, orientation="horizontal")
cb.set_label("road height (studs)"); cb.outline.set_visible(False)

# start line + direction
ax.plot([x[0], x[0]], [z[0] - 18, z[0] + 18], color=INK, lw=3, zorder=5)
ax.annotate("", xy=(x[8], z[8] - 30), xytext=(x[0], z[0] - 30), arrowprops=dict(arrowstyle="->", color=INK, lw=1.6))
ax.text(x[0], z[0] + 26, "START", ha="center", va="top", fontsize=9, color=INK, fontweight="bold")
# pits / paddock band
ax.add_patch(plt.Rectangle((x[0] - 260, -150), 470, 115, color="#e9e6de", zorder=1))
ax.text(x[0] - 25, -92, "pits / paddock (level, at the lawn)", ha="center", va="center", fontsize=9, color=MUTED)

# corner labels: minimum speed in each named corner
SKIP = {"", "Main straight", "Back straight"}
groups, cur, curn = [], [], None
for i in range(n):
    if nm[i] != curn:
        if cur: groups.append((curn, cur))
        cur, curn = [], nm[i]
    cur.append(i)
groups.append((curn, cur))
merged = {}
for name, idx in groups:
    if name in SKIP: continue
    merged.setdefault(name, []).append(idx)
OFF = {"First Curve": (40, -10), "Second Curve": (55, 10), "S Curves": (0, -48), "Gyaku Bank": (-20, 50),
       "Dunlop": (40, -45), "Degner 1": (60, 0), "Degner 2": (40, 40), "Under the bridge": (0, 0),
       "110R": (55, 0), "Hairpin": (-30, -45), "200R": (-70, 25), "Spoon Curve": (-40, -70),
       "130R": (-80, 0), "Casio Triangle": (-95, 0), "Last Curve": (-30, -45)}
for name, runs_ in merged.items():
    for idx in runs_:
        if name == "Under the bridge":
            continue
        k = idx[int(np.nanargmin(kmh[idx]))]
        dx, dz = OFF.get(name, (40, 30))
        ax.annotate(f"{name}\n{kmh[k]:.0f} km/h", xy=(x[k], z[k]), xytext=(x[k] + dx, z[k] + dz), fontsize=8.5,
                    ha="center", va="center", color=INK, zorder=6,
                    bbox=dict(boxstyle="round,pad=0.25", fc="#ffffff", ec=GRID, lw=0.8),
                    arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.7))
        break
ax.annotate(f"BRIDGE\nback straight passes over\n{y[hi] - y[lo]:.1f} studs headroom", xy=(x[lo], z[lo]),
            xytext=(x[lo] + 150, z[lo] + 120), fontsize=9, ha="center", color=INK, fontweight="bold", zorder=6,
            bbox=dict(boxstyle="round,pad=0.3", fc="#fff6e0", ec="#e0b85c", lw=1),
            arrowprops=dict(arrowstyle="->", color=INK, lw=1))
# scale bar
sx, sz = -1250, -100
ax.plot([sx, sx + 200], [sz, sz], color=INK, lw=2)
ax.text(sx + 100, sz - 12, "200 studs", ha="center", fontsize=8.5, color=MUTED)
ax.set_aspect("equal"); ax.invert_yaxis(); ax.axis("off")
ax.set_xlim(x.min() - 60, x.max() + 90); ax.set_ylim(z.max() + 40, z.min() - 165)

# elevation profile
KEY = [("T2 (lowest)", 0), ("Esses climb", 0), ("Dunlop crest", 0), ("under bridge", 0), ("Hairpin", 0), ("Spoon (top)", 0),
       ("back straight dip", 0), ("over bridge", 0), ("chicane", 0)]
def first(name):
    return next(i for i in range(n) if nm[i] == name)
ax2 = fig.add_subplot(gs[1, 0]); ax2.set_facecolor(BG)
ax2.fill_between(s, 0, y, color="#cde2fb", lw=0)
ax2.plot(s, y, color="#256abf", lw=2)
marks = [("T1-T2: lowest", first("Second Curve")),
         ("Dunlop crest", int(np.argmax(np.where((s > 1100) & (s < 1700), y, -1)))),
         ("under the bridge", lo), ("Hairpin", first("Hairpin")),
         ("Spoon - top", int(np.argmax(y))),
         ("back-straight dip", int(np.argmin(np.where((s > 3000) & (s < 3500), y, 99)))),
         ("over the bridge", hi), ("Last Curve\n(downhill)", first("Last Curve") + 25)]
for lab, k in marks:
    ax2.plot(s[k], y[k], "o", ms=6, color="#0d366b", mec="#ffffff", mew=1.5, zorder=4)
    ax2.annotate(lab, (s[k], y[k]), xytext=(0, 9 if y[k] < 28 else -16), textcoords="offset points", ha="center", fontsize=8.5, color=INK)
ax2.annotate("", xy=(s[hi], y[hi]), xytext=(s[lo], y[lo]), arrowprops=dict(arrowstyle="-", ls=":", color=MUTED))
ax2.set_title("Height along the lap (studs)", loc="left", fontsize=11.5, color=INK, fontweight="bold")
ax2.set_xlim(0, s[-1]); ax2.set_ylim(-2, 40); ax2.grid(color=GRID, lw=0.8); ax2.set_axisbelow(True)
for sp_ in ax2.spines.values(): sp_.set_visible(False)
ax2.set_xlabel("distance from the start line (studs)")

ax3 = fig.add_subplot(gs[1, 1]); ax3.set_facecolor(BG)
ax3.plot(s, kmh, color="#256abf", lw=2)
ax3.set_title("Autopilot speed (km/h) - a careful bot, players go faster", loc="left", fontsize=11.5, color=INK, fontweight="bold")
ax3.set_ylim(30, 100); ax3.set_xlim(0, s[-1]); ax3.grid(color=GRID, lw=0.8); ax3.set_axisbelow(True)
for sp_ in ax3.spines.values(): sp_.set_visible(False)
for lab, nmx in [("Hairpin", "Hairpin"), ("Casio", "Casio Triangle"), ("130R", "130R"), ("Spoon", "Spoon Curve"), ("Degner", "Degner 1")]:
    idx = [i for i in range(n) if nm[i] == nmx]
    k = idx[int(np.nanargmin(kmh[idx]))]
    ax3.annotate(lab, (s[k], kmh[k]), xytext=(0, -14), textcoords="offset points", ha="center", fontsize=8.5, color=INK)
ax3.set_xlabel("distance from the start line (studs)")
fig.savefig(OUT, dpi=90, facecolor=BG)
print("saved", OUT)
