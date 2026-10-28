"""Promo renders (thumbnails, icon) from dump_scene.luau output.

Reuses tests/tools/render.py (exec'd up to its own scene code), swaps the
mock's box characters for simple drivers (suit, helmet with visor, arms to
the steering wheel) and renders camera views at thumbnail size.

    python3 promo.py scene.txt out.png "eye" "target" fov [width height]
eye/target: "x,y,z" in studs, or "pack:dx,dy,dz" relative to the karts'
centre in the pack's frame (dx right, dy up, dz forward).
"""
import math, sys
import numpy as np

RENDER = "/home/claude/apex-karting/tests/tools/render.py"
scene, out = sys.argv[1], sys.argv[2]
eye_s, tgt_s, fov = sys.argv[3], sys.argv[4], float(sys.argv[5])
W = int(sys.argv[6]) if len(sys.argv) > 6 else 1920
H = int(sys.argv[7]) if len(sys.argv) > 7 else 1080
only_near = float(sys.argv[8]) if len(sys.argv) > 8 else 0.0

src = open(RENDER).read()
cut = src.index('kart = [p for p in parts if ".Kart_" in p["path"]]')
sys.argv = [RENDER, scene, "/tmp/claude-0/-home-claude/27a95dec-38e2-5550-9411-57feb6028f64/scratchpad/promo/_r"]
g = {"__name__": "render_lib"}
exec(compile(src[:cut], RENDER, "exec"), g)
parts = g["parts"]
render = g["render"]

parts = [p for p in parts if not p["path"].startswith("Workspace.Driver")]

def unit(v):
    return v / np.linalg.norm(v)

def part(path, shape, size, pos, R, color, mat="SmoothPlastic", t=0.0):
    return dict(path=path, cls="Part", shape=shape, size=np.array(size, float), pos=np.array(pos, float), rot=R, color=np.array(color, float), t=t, mat=mat)

def frame(right, up):
    back = np.cross(right, up)
    return np.stack([right, up, back], 1)

def cyl(path, a, b, dia, color, mat="SmoothPlastic"):
    d = b - a
    L = np.linalg.norm(d)
    x = d / L
    u = np.array([0, 1.0, 0]) if abs(x[1]) < 0.9 else np.array([1.0, 0, 0])
    y = unit(u - x * np.dot(u, x))
    z = np.cross(x, y)
    return part(path, "Cylinder", [L, dia, dia], (a + b) / 2, np.stack([x, y, z], 1), color, mat)

SUITS = [(0.95, 0.95, 0.97), (0.10, 0.12, 0.16), (0.95, 0.77, 0.10), (0.85, 0.20, 0.18), (0.18, 0.35, 0.80), (0.12, 0.55, 0.30)]
HELMETS = [(0.98, 0.78, 0.05), (0.95, 0.95, 0.97), (0.20, 0.45, 0.90), (0.95, 0.30, 0.25), (0.98, 0.98, 0.98), (0.95, 0.55, 0.10)]
karts = sorted({p["path"].split(".")[2] for p in parts if p["path"].startswith("Workspace.Karts.Kart_")})
seats = []
for k, name in enumerate(karts):
    kp = [p for p in parts if p["path"].startswith(f"Workspace.Karts.{name}.")]
    seat = next(p for p in kp if p["path"].endswith(".SeatPan"))
    tray = next((p for p in kp if p["path"].endswith("FloorTray")), seat)
    right, up, back = tray["rot"][:, 0], tray["rot"][:, 1], tray["rot"][:, 2]
    look = -back
    rims = [p["pos"] for p in parts if p["path"].startswith(f"Workspace.KartVisuals.{name}.WheelRim")]
    wheel = np.mean(rims, 0) if rims else seat["pos"] + look * 1.3 + up * 1.4
    s = seat["pos"]
    suit, helm = SUITS[k % len(SUITS)], HELMETS[k % len(HELMETS)]
    pitch = math.radians(16)
    up_t = unit(up * math.cos(pitch) - look * math.sin(pitch))
    R = frame(right, up_t)
    base = f"Workspace.Drivers.{name}."
    parts.append(part(base + "Torso", "Block", [1.45, 1.6, 0.8], s + up * 1.1 - look * 0.35, R, suit))
    parts.append(part(base + "Shoulders", "Block", [1.75, 0.45, 0.85], s + up * 1.85 - look * 0.55, R, suit))
    head = s + up * 2.65 - look * 0.55
    parts.append(part(base + "Neck", "Cylinder", [0.5, 0.55, 0.55], s + up * 2.15 - look * 0.55, frame(up, -right) if False else np.stack([up, -right, np.cross(up, -right)], 1), (0.1, 0.1, 0.12)))
    parts.append(part(base + "Helmet", "Ellipsoid", [1.3, 1.4, 1.5], head, R, helm))
    parts.append(part(base + "Visor", "Block", [0.95, 0.38, 0.12], head + look * 0.7 + up * 0.08, R, (0.06, 0.07, 0.09)))
    parts.append(part(base + "Stripe", "Block", [0.22, 0.08, 1.2], head + up * 0.7, R, (0.08, 0.08, 0.1)))
    for sgn in (-1, 1):
        sh = s + up * 1.85 - look * 0.5 + right * 0.8 * sgn
        grip = wheel + right * 0.42 * sgn
        elbow = (sh + grip) / 2 - up * 0.35 + right * 0.15 * sgn
        parts.append(cyl(base + f"UpperArm{sgn}", sh, elbow, 0.42, suit))
        parts.append(cyl(base + f"Forearm{sgn}", elbow, grip, 0.36, suit))
        parts.append(part(base + f"Glove{sgn}", "Ellipsoid", [0.36, 0.36, 0.4], grip, R, (0.08, 0.08, 0.1)))
        hip = s + up * 0.4 + right * 0.35 * sgn
        knee = s + look * 1.6 + up * 0.85 + right * 0.4 * sgn
        foot = s + look * 2.9 + up * 0.45 + right * 0.35 * sgn
        parts.append(cyl(base + f"Thigh{sgn}", hip, knee, 0.5, suit))
        parts.append(cyl(base + f"Shin{sgn}", knee, foot, 0.42, suit))
    seats.append((s, look, up, right))

centre = np.mean([q[0] for q in seats], 0)
look0 = unit(np.mean([q[1] for q in seats], 0))
up0 = np.array([0, 1.0, 0])
right0 = unit(np.cross(look0, up0))

def point(spec):
    if spec.startswith("pack:"):
        dx, dy, dz = [float(v) for v in spec[5:].split(",")]
        return centre + right0 * dx + up0 * dy + look0 * dz
    if spec.startswith("kart"):
        k, rest = spec[4:].split(":")
        s, lk, u, rt = seats[int(k)]
        dx, dy, dz = [float(v) for v in rest.split(",")]
        return s + rt * dx + u * dy + lk * dz
    return np.array([float(v) for v in spec.split(",")])

eye, tgt = point(eye_s), point(tgt_s)
sel = parts
if only_near > 0:
    sel = [p for p in parts if np.linalg.norm(p["pos"] - tgt) < only_near or np.max(p["size"]) > only_near]
import os
ok = os.environ.get("ONLY_KART")
if ok is not None:
    name = karts[int(ok)]
    sel = [p for p in parts if (f".{name}." in p["path"])]
    if os.environ.get("WITH_ROAD"):
        sel += [p for p in parts if ("Road" in p["path"] or "Lawn" in p["path"]) and np.linalg.norm((p["pos"] - tgt)[[0, 2]]) < 60]
hide = os.environ.get("HIDE_DRIVER")
if hide is not None:
    hn = karts[int(hide)]
    sel = [p for p in sel if not (p["path"].startswith(f"Workspace.Drivers.{hn}.") and any(w in p["path"] for w in ("Helmet", "Visor", "Stripe", "Neck", "Torso", "Shoulders")))]
lights = os.environ.get("LIGHTS")
if lights:
    for p in parts:
        if ".Gantry.Lights." in p["path"]:
            p["color"] = np.array([1.0, 0.16, 0.12]); p["mat"] = "Neon"
render(sel, eye, tgt, out, fov=fov, size=(W / 90, H / 90), segs=int(os.environ.get("SEGS", "18")), bg=os.environ.get("BG", "#bcd4ea"))
print("rendered", out, "eye", np.round(eye, 1), "target", np.round(tgt, 1))
