"""Plots tests/tools/speedmap.luau output: the circuit from above coloured by
autopilot speed (km/h), corner names with their minimum speed, and the
height profile along the lap.

    python3 tests/tools/speedmap.py hillside_speed.csv hillside_speed.png
"""
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def main():
    path, out = sys.argv[1], sys.argv[2]
    title = ""
    rows = []
    for line in open(path):
        if line.startswith("#"):
            title = line[1:].strip()
            continue
        p = line.rstrip("\n").split(",")
        if len(p) < 11:
            continue
        rows.append((int(p[0]), float(p[1]), float(p[2]), float(p[3]), float(p[4]), float(p[5]), float(p[6]), float(p[7]), float(p[8]), int(p[9]), p[10]))
    rows.sort()
    x = np.array([r[1] for r in rows])
    y = np.array([r[2] for r in rows])
    z = np.array([r[3] for r in rows])
    v = np.array([r[4] for r in rows])
    thr = np.array([r[5] for r in rows])
    steer = np.array([r[7] for r in rows])
    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_axes([0.04, 0.3, 0.7, 0.65])
    sc = ax.scatter(x, z, c=v, cmap="turbo", s=10, vmin=30, vmax=100)
    ax.set_aspect("equal")
    ax.invert_yaxis()
    ax.set_title(title)
    fig.colorbar(sc, ax=ax, label="km/h", fraction=0.03)
    ax.plot(x[0], z[0], "ks", ms=8)
    # corner names at the slowest point of each named run of samples
    names = {}
    for r in rows:
        if r[10]:
            names.setdefault(r[10], []).append(r)
    for name, rs in names.items():
        slow = min(rs, key=lambda r: r[4])
        ax.annotate(f"{name}\n{slow[4]:.0f} km/h", (slow[1], slow[3]), fontsize=8, ha="center", xytext=(0, 12), textcoords="offset points",
                    bbox=dict(boxstyle="round,pad=0.2", fc="white", alpha=0.7))
    # profile
    s = np.arange(len(rows))
    a2 = fig.add_axes([0.04, 0.05, 0.9, 0.2])
    a2.plot(s, v, label="km/h", color="tab:red")
    a2.plot(s, y * 2, label="height x2 (studs)", color="tab:green")
    a2.plot(s, thr * 20, label="throttle x20", color="tab:gray", lw=0.6)
    a2.plot(s, steer * 40, label="steer x40", color="tab:blue", lw=0.6)
    a2.legend(loc="upper right", fontsize=8)
    a2.set_xlim(0, len(rows))
    a2.grid(alpha=0.3)
    fig.savefig(out, dpi=90)


if __name__ == "__main__":
    main()
