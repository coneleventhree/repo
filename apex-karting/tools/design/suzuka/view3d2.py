import sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.colors import LinearSegmentedColormap
S = "/tmp/claude-0/-home-claude/27a95dec-38e2-5550-9411-57feb6028f64/scratchpad/suzuka/work/"
T = np.array([[float(v) for v in l.split(",")] for l in open(S + "suzuka_track.csv") if not l.startswith("#")])
x, y, z, rx, ry, rz, w = T[:, 2], T[:, 3], T[:, 4], T[:, 5], T[:, 6], T[:, 7], T[:, 8]
n = len(T)
EX = float(sys.argv[2]) if len(sys.argv) > 2 else 2.5
def P(px, py, pz):  # world (x, height, z) -> 3D with exaggerated height
    return np.array([px, py * EX, pz])
L = np.array([P(x[i] - rx[i] * w[i] / 2, y[i] - ry[i] * w[i] / 2, z[i] - rz[i] * w[i] / 2) for i in range(n)])
R = np.array([P(x[i] + rx[i] * w[i] / 2, y[i] + ry[i] * w[i] / 2, z[i] + rz[i] * w[i] / 2) for i in range(n)])
# camera: south-east of the circuit (z grows "south" on the plan), looking down at 30 degrees
c = np.array([x.mean(), 0, z.mean()])
az, el = np.radians(float(sys.argv[3]) if len(sys.argv) > 3 else 200), np.radians(32)
fwd = np.array([np.cos(az) * np.cos(el), -np.sin(el), np.sin(az) * np.cos(el)])
eye = c - fwd * 2600
right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
up = np.cross(right, fwd)
def proj(p):
    d = p - eye
    zc = d @ fwd
    return np.c_[(d @ right) / zc, (d @ up) / zc], zc
ramp = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
cmap = LinearSegmentedColormap.from_list("h", ramp)
P2 = np.c_[x, z]
deck = set()
for i in range(n):
    d = np.hypot(*(P2 - P2[i]).T); sep = np.minimum(abs(np.arange(n) - i), n - abs(np.arange(n) - i)); d[sep < 40] = 1e9
    j = int(np.argmin(d))
    if d[j] < 26 and y[i] > y[j] + 5:
        deck.add(i)
polys, depth, cols = [], [], []
GREEN = np.array([0.55, 0.70, 0.45])
for i in range(n):
    j = (i + 1) % n
    q = np.array([L[i], R[i], R[j], L[j]])
    xy, zc = proj(q)
    polys.append(xy); depth.append(zc.mean() - 2); cols.append(cmap(y[i] / y.max()))
    if i in deck:
        continue
    for E in (L, R):
        q = np.array([E[i], E[j], [E[j][0], 0, E[j][2]], [E[i][0], 0, E[i][2]]])
        xy, zc = proj(q)
        # shade by facing
        nrm = np.cross(E[j] - E[i], [0, 1, 0]); nrm /= np.linalg.norm(nrm) + 1e-9
        shade = 0.75 + 0.25 * abs(nrm @ np.array([0.6, 0, -0.8]))
        polys.append(xy); depth.append(zc.mean()); cols.append((*(GREEN * shade), 1.0))
order = np.argsort(depth)[::-1]
BG = "#fbfaf7"
fig, ax = plt.subplots(figsize=(16, 8.5), facecolor=BG)
ax.set_facecolor(BG)
ax.add_collection(PolyCollection([polys[k] for k in order], facecolors=[cols[k] for k in order], edgecolors=[cols[k] for k in order], linewidths=0.4))
allp = np.vstack(polys)
ax.set_xlim(allp[:, 0].min() - 0.01, allp[:, 0].max() + 0.01); ax.set_ylim(allp[:, 1].min() - 0.03, allp[:, 1].max() + 0.05)
ax.set_aspect("equal"); ax.axis("off")
fig.text(0.03, 0.94, f"Suzuka - the hills from the side (height drawn {EX:g}x so it reads from this far away)", fontsize=15, fontweight="bold", color="#1f1f1d")
fig.text(0.03, 0.905, "Green walls only mark how high the road is - in the game they become grassy slopes. The back straight crosses the Degner exit on a bridge.", fontsize=10.5, color="#6b6a66")
plt.subplots_adjust(0.02, 0.02, 0.98, 0.88)
fig.savefig(sys.argv[1], dpi=90, facecolor=BG)
print("saved")
