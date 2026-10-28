"""Renders views of a dumped world. views.py world.txt track.csv out_prefix view...
view = name:eye:target[:fov]  with eye/target "s<idx>,dx,dy,dz" (sample idx, offsets
right/up/forward in the road frame) or "x,y,z"."""
import sys, numpy as np, os
RENDER = "/home/claude/apex-karting/tests/tools/render.py"
world, trackcsv, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
views = sys.argv[4:]
src = open(RENDER).read()
cut = src.index('kart = [p for p in parts if ".Kart_" in p["path"]]')
sys.argv = [RENDER, world, os.path.dirname(prefix) + "/_r"]
g = {"__name__": "render_lib"}
exec(compile(src[:cut], RENDER, "exec"), g)
parts, render = g["parts"], g["render"]
T = np.array([[float(v) for v in l.split(",")] for l in open(trackcsv) if not l.startswith("#")])
def pt(spec):
    if spec.startswith("s"):
        f = spec[1:].split(",")
        i = int(f[0]) - 1
        dx, dy, dz = (float(v) for v in f[1:4])
        pos = T[i, 2:5]; right = T[i, 5:8]
        nxt = T[(i + 1) % len(T), 2:5]; fwd = nxt - pos; fwd /= np.linalg.norm(fwd)
        return pos + right * dx + np.array([0, 1.0, 0]) * dy + fwd * dz
    return np.array([float(v) for v in spec.split(",")])
for v in views:
    f = v.split(":")
    name, eye, tgt = f[0], pt(f[1]), pt(f[2])
    fov = float(f[3]) if len(f) > 3 else 60
    near = float(f[4]) if len(f) > 4 else 0
    sel = parts if near <= 0 else [p for p in parts if np.linalg.norm(p["pos"] - tgt) < near or np.max(p["size"]) > near]
    sel = [p for p in sel if not p["path"].startswith("Workspace.Karts") and "Driver" not in p["path"]]
    render(sel, eye, tgt, f"{prefix}-{name}.png", fov=fov, size=(16, 9), segs=12)
    print("rendered", name, np.round(eye, 1), np.round(tgt, 1))
