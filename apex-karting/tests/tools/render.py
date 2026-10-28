#!/usr/bin/env python3
"""Preview renderer for the part dump made by dump_world.luau.

A tiny flat-shaded painter's-algorithm renderer: every part becomes polygons
(blocks, wedges, cylinders, balls), they are projected with a pinhole or
orthographic camera and drawn far to near with matplotlib. Good enough to
check shapes, proportions and layout without Roblox Studio.

usage: render.py world.txt out_dir
"""
import os
import sys
import math, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

world, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(out_dir, exist_ok=True)

parts = []
camera = None
for line in open(world):
    f = line.rstrip("\n").split("|")
    if f[0] == "CAMERA":
        camera = [np.array([float(v) for v in f[k].split(",")]) for k in (1, 2, 3)] + [float(f[4])]
        continue
    if len(f) < 9:
        continue
    path, cls, shape = f[0], f[1], f[2]
    size = np.array([float(v) for v in f[3].split(",")])
    pos = np.array([float(v) for v in f[4].split(",")])
    m = np.array([float(v) for v in f[5].split(",")]).reshape(3, 3)
    color = np.array([float(v) for v in f[6].split(",")])
    transp = float(f[7])
    material = f[8]
    parts.append(dict(path=path, cls=cls, shape=shape, size=size, pos=pos, rot=m, color=color, t=transp, mat=material))


def polys(p, segs=14):
    """World-space polygons (list of Nx3 arrays) for a part."""
    sx, sy, sz = p["size"] / 2
    R, c = p["rot"], p["pos"]
    def w(local):
        return (R @ np.asarray(local, dtype=float).T).T + c
    out = []
    if p["cls"] == "WedgePart":
        # slope from bottom-front (y=-, z=-) to top-back (y=+, z=+)
        v = {
            "a": (-sx, -sy, -sz), "b": (sx, -sy, -sz), "c": (sx, -sy, sz), "d": (-sx, -sy, sz),
            "e": (-sx, sy, sz), "f": (sx, sy, sz),
        }
        faces = [("a", "b", "c", "d"), ("d", "c", "f", "e"), ("a", "e", "f", "b"), ("a", "d", "e"), ("b", "f", "c")]
        for fc in faces:
            out.append(w([v[k] for k in fc]))
        return out
    if p["shape"] == "Cylinder":
        r = min(sy, sz)
        ang = np.linspace(0, 2 * math.pi, segs, endpoint=False)
        ring = np.stack([np.cos(ang) * r, np.sin(ang) * r], 1)
        left = [(-sx, y, z) for y, z in ring]
        right = [(sx, y, z) for y, z in ring]
        out.append(w(left))
        out.append(w(right))
        for i in range(segs):
            j = (i + 1) % segs
            out.append(w([left[i], left[j], right[j], right[i]]))
        return out
    if p["shape"] == "Ellipsoid":
        lat = np.linspace(-math.pi / 2, math.pi / 2, 9)
        lon = np.linspace(0, 2 * math.pi, 15)
        for a in range(len(lat) - 1):
            for b in range(len(lon) - 1):
                q = []
                for la, lo in ((lat[a], lon[b]), (lat[a], lon[b + 1]), (lat[a + 1], lon[b + 1]), (lat[a + 1], lon[b])):
                    q.append((sx * math.cos(la) * math.cos(lo), sy * math.sin(la), sz * math.cos(la) * math.sin(lo)))
                out.append(w(q))
        return out
    if p["shape"] == "Ball":
        r = min(sx, sy, sz)
        lat = np.linspace(-math.pi / 2, math.pi / 2, 7)
        lon = np.linspace(0, 2 * math.pi, 10)
        for a in range(len(lat) - 1):
            for b in range(len(lon) - 1):
                q = []
                for la, lo in ((lat[a], lon[b]), (lat[a], lon[b + 1]), (lat[a + 1], lon[b + 1]), (lat[a + 1], lon[b])):
                    q.append((r * math.cos(la) * math.cos(lo), r * math.sin(la), r * math.cos(la) * math.sin(lo)))
                out.append(w(q))
        return out
    v = [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for fc in faces:
        out.append(w([v[k] for k in fc]))
    return out


NEAR = 0.3


def clip_near(x, y, z):
    """Sutherland-Hodgman clip of a polygon against the plane z = NEAR."""
    ox, oy, oz = [], [], []
    n = len(z)
    for i in range(n):
        j = (i + 1) % n
        a_in, b_in = z[i] >= NEAR, z[j] >= NEAR
        if a_in:
            ox.append(x[i]); oy.append(y[i]); oz.append(z[i])
        if a_in != b_in:
            t = (NEAR - z[i]) / (z[j] - z[i])
            ox.append(x[i] + (x[j] - x[i]) * t); oy.append(y[i] + (y[j] - y[i]) * t); oz.append(NEAR)
    return np.array(ox), np.array(oy), np.array(oz)


LIGHT = np.array([0.35, 0.85, 0.4])
LIGHT /= np.linalg.norm(LIGHT)


def shade(color, normal, mat):
    d = abs(float(np.dot(normal, LIGHT)))
    k = 0.42 + 0.58 * d
    if mat == "Neon":
        k = 1.25
    return np.clip(color * k, 0, 1)


def render(sel, cam_pos, target, out, fov=50, ortho=None, size=(12, 8), bg="#bcd4ea", title=None, up=(0, 1, 0), segs=14, cull_back=True):
    cam_pos, target = np.array(cam_pos, float), np.array(target, float)
    fwd = target - cam_pos
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, np.array(up, float))
    right /= np.linalg.norm(right)
    upv = np.cross(right, fwd)
    f = 1 / math.tan(math.radians(fov) / 2)
    aspect = size[0] / size[1]
    items = []
    for p in sel:
        for poly in polys(p, segs):
            rel = poly - cam_pos
            x = rel @ right
            y = rel @ upv
            z = rel @ fwd
            if ortho is None:
                if np.all(z < NEAR):
                    continue
                if np.any(z < NEAR):
                    x, y, z = clip_near(x, y, z)
                    if len(z) < 3:
                        continue
                px, py = x / z * f, y / z * f
            else:
                px, py = x / ortho, y / ortho
            n = np.cross(poly[1] - poly[0], poly[2] - poly[0])
            nn = np.linalg.norm(n)
            if nn < 1e-9:
                continue
            n /= nn
            # make the normal face the camera for shading
            view = cam_pos - poly.mean(0) if ortho is None else -fwd
            if np.dot(n, view) < 0:
                n = -n
            if np.min(px) > 1.2 * aspect or np.max(px) < -1.2 * aspect or np.min(py) > 1.2 or np.max(py) < -1.2:
                continue
            flat_ground = float(poly[:, 1].max()) <= 0.06 and abs(n[1]) > 0.99
            if not flat_ground and float(poly[:, 1].max()) <= -0.09 and cam_pos[1] > 0:
                continue  # sides of floor slabs, hidden under the floor
            # ground polygons first (lowest first), then the rest far to near
            key = (0, float(poly[:, 1].max()), 0.0) if flat_ground else (1, 0.0, -float(z.max() * 0.5 + z.mean() * 0.5))
            if p["path"].endswith(".TurfBase") and not flat_ground:
                # the turf base under a raised road's bands: big merged triangles
                # that would paint over the bands on top of them
                key = (1, 0.0, key[2] - 30.0)
            items.append((key, np.stack([px, py], 1), shade(p["color"], n, p["mat"]), 1 - p["t"]))
    items.sort(key=lambda it: it[0])
    fig = plt.figure(figsize=size)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_facecolor(bg)
    cols = [np.append(c, a) for _, _, c, a in items]
    pc = PolyCollection([it[1] for it in items], facecolors=cols, edgecolors=cols, linewidths=0.3)
    ax.add_collection(pc)
    ax.set_xlim(-aspect, aspect)
    ax.set_ylim(-1, 1)
    ax.set_aspect("equal")
    ax.axis("off")
    if title:
        ax.text(-aspect + 0.03, 0.92, title, fontsize=12, color="k")
    fig.savefig(out, dpi=90, facecolor=bg)
    plt.close(fig)


def topdown(sel, out, bounds, size=(14, 11)):
    """Orthographic map: top faces drawn lowest first."""
    minx, maxx, minz, maxz = bounds
    items = []
    for p in sel:
        for poly in polys(p, 10):
            n = np.cross(poly[1] - poly[0], poly[2] - poly[0])
            nn = np.linalg.norm(n)
            if nn < 1e-9:
                continue
            n /= nn
            if abs(n[1]) < 0.2:
                continue
            items.append((float(poly[:, 1].max()), poly[:, [0, 2]], shade(p["color"], n, p["mat"]), 1 - p["t"]))
    items.sort(key=lambda it: it[0])
    fig = plt.figure(figsize=size)
    ax = fig.add_axes([0, 0, 1, 1])
    cols = [np.append(c, a) for _, _, c, a in items]
    ax.add_collection(PolyCollection([it[1] for it in items], facecolors=cols, edgecolors=cols, linewidths=0.2))
    ax.set_xlim(minx, maxx)
    ax.set_ylim(maxz, minz)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.savefig(out, dpi=80)
    plt.close(fig)


kart = [p for p in parts if ".Kart_" in p["path"]]
kc = np.mean([p["pos"] for p in kart if p["path"].endswith(".Chassis") or "FloorTray" in p["path"]] or [kart[0]["pos"]], 0)
look = None
for p in kart:
    if p["path"].endswith("FloorTray"):
        look = -p["rot"][:, 2]
if look is None:
    look = np.array([1.0, 0, 0])
look[1] = 0
look /= np.linalg.norm(look)
side = np.cross(look, [0, 1, 0])
near = [p for p in parts if np.linalg.norm(p["pos"] - kc) < 9 and "Workspace.Alice" not in p["path"] and ".Grid." not in p["path"] and "Paint" not in p["path"] and "Cockpit" not in p["path"]]
ground = [p for p in parts if ("Road" in p["path"] or "Lawn" in p["path"]) and np.linalg.norm((p["pos"] - kc)[[0, 2]]) < max(40, float(p["size"].max()))]
kart_scene = near + ground
c = kc + np.array([0, 0.3, 0])
render(kart_scene, c + look * 7 + side * 5.5 + np.array([0, 3.2, 0]), c, f"{out_dir}/kart_front34.png", fov=45, title="kart: front 3/4")
render(kart_scene, c - look * 7 + side * -5.5 + np.array([0, 3.6, 0]), c, f"{out_dir}/kart_rear34.png", fov=45, title="kart: rear 3/4")
render(kart_scene, c + side * 10 + np.array([0, 0.6, 0]), c, f"{out_dir}/kart_side.png", fov=40, title="kart: side")
render(kart_scene, c + np.array([0, 14, 0]) + look * 0.01, c, f"{out_dir}/kart_top.png", fov=40, up=tuple(look), title="kart: top")
render(kart_scene, c + look * 11 + np.array([0, 1.4, 0]), c, f"{out_dir}/kart_front.png", fov=40, title="kart: front")
render(kart_scene, c + look * 4.5 + side * 6.5 + np.array([0, 1.1, 0]), c + look * 0.5, f"{out_dir}/kart_low.png", fov=50, title="kart: low front 3/4")

if os.environ.get("KART_ONLY"):
    sys.exit(0)

# circuit views
everything = [p for p in parts if "Workspace.Alice" not in p["path"]]

# the podium in the paddock, from where the podium camera looks at it
podium = [p for p in parts if ".Pits.Podium." in p["path"]]
step1 = [p for p in podium if p["path"].endswith(".Step1")]
if step1:
    sp = step1[0]["pos"]
    render(everything, sp + np.array([0, 5.5, 30]), sp + np.array([0, 2.5, 0]), f"{out_dir}/view_podium.png", fov=55, size=(14, 8), title="podium", segs=12)
if os.environ.get("PODIUM_ONLY"):
    sys.exit(0)
xs = [p["pos"][0] for p in parts if "Perimeter" in p["path"] and "CarPark" not in p["path"]]
zs = [p["pos"][2] for p in parts if "Perimeter" in p["path"] and "CarPark" not in p["path"]]
topdown(everything, f"{out_dir}/circuit_top.png", (min(xs) - 20, max(xs) + 20, min(zs) - 20, max(zs) + 20))
render(everything, c - look * 22 + np.array([0, 7, 0]) + side * 3, c + look * 60, f"{out_dir}/view_grid.png", fov=70, size=(14, 8), title="behind the grid", segs=10)
if camera:
    cpos, clook, cup, cfov = camera
    render(everything, cpos, cpos + clook * 10, f"{out_dir}/view_cockpit.png", fov=cfov, size=(14, 8), title="cockpit (mouse wheel all the way in)", up=tuple(cup), segs=16)
mid = np.array([(min(xs) + max(xs)) / 2, 0, (min(zs) + max(zs)) / 2])
span = max(max(xs) - min(xs), max(zs) - min(zs)) / 1050  # 1 for the first circuit
render(everything, mid + np.array([-150, 380, -650]) * span, mid + np.array([0, 0, 40]) * span, f"{out_dir}/view_aerial.png", fov=55, size=(14, 9), title="aerial", segs=8)
print("rendered", len(parts), "parts")

# extra views: VIEWS="name:ex,ey,ez:tx,ty,tz;name2:..." (eye and target in studs)
for spec in filter(None, os.environ.get("VIEWS", "").split(";")):
    name, eye, target = spec.split(":")
    e = np.array([float(v) for v in eye.split(",")])
    t = np.array([float(v) for v in target.split(",")])
    render(everything, e, t, f"{out_dir}/view_{name}.png", fov=65, size=(14, 8), title=name, segs=10)
if os.environ.get("VIEWS_ONLY"):
    sys.exit(0)

# a closer look at a corner grandstand and the hairpin from the track
stand = [p for p in parts if ".Grandstands.T1." in p["path"]]
if stand:
    sc = np.mean([p["pos"] for p in stand], 0)
    sc[1] = 6
    render(everything, sc + np.array([-70, 18, 95]), sc, f"{out_dir}/view_t1.png", fov=60, size=(14, 8), title="T1 grandstand", segs=10)
hp = [p for p in parts if ".Grandstands.T3 hairpin." in p["path"]]
if hp:
    hc = np.mean([p["pos"] for p in hp], 0)
    render(everything, hc + np.array([-60, 30, -40]), hc + np.array([-40, 0, -50]), f"{out_dir}/view_hairpin.png", fov=70, size=(14, 8), title="hairpin", segs=10)

# every corner grandstand, seen from its top row towards the road
roads = [p for p in parts if ".Track.Road." in p["path"]]
road_xz = np.array([p["pos"][[0, 2]] for p in roads]) if roads else None
names = sorted({p["path"].split(".Grandstands.")[1].split(".")[0] for p in parts if ".Grandstands." in p["path"]})
for name in names:
    if name in ("Main", "T1", "T3 hairpin") or road_xz is None:
        continue
    st = [p for p in parts if f".Grandstands.{name}." in p["path"]]
    sc = np.mean([p["pos"] for p in st], 0)
    j = int(np.argmin(np.linalg.norm(road_xz - sc[[0, 2]], axis=1)))
    target = np.array([road_xz[j][0], 0.0, road_xz[j][1]])
    away = sc - target
    away[1] = 0
    away /= max(np.linalg.norm(away), 1e-6)
    eye = sc - away * 18 + np.array([0, 16, 0])
    render(everything, eye, target - away * 40, f"{out_dir}/view_{name.replace(' ', '_').lower()}.png", fov=70, size=(14, 8), title=f"{name} grandstand", segs=10)

boards = [p for p in parts if ".CornerBoards.CornerBoard" in p["path"]]
for k, b in enumerate(boards[:2]):
    bp = b["pos"].copy()
    fwd = -b["rot"][:, 2]  # LookVector: the side facing the drivers
    fwd[1] = 0
    fwd /= max(np.linalg.norm(fwd), 1e-6)
    render(everything, bp + fwd * 45 + np.array([0, 4, 0]), bp, f"{out_dir}/view_board{k + 1}.png", fov=60, size=(14, 8), title="corner board", segs=10)
