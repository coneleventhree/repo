import sys, numpy as np, os
RENDER = "/home/claude/apex-karting/tests/tools/render.py"
world, out, cx, cz, half = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
src = open(RENDER).read()
cut = src.index('kart = [p for p in parts if ".Kart_" in p["path"]]')
sys.argv = [RENDER, world, os.path.dirname(out) + "/_r"]
g = {"__name__": "render_lib"}
exec(compile(src[:cut], RENDER, "exec"), g)
parts, render = g["parts"], g["render"]
sel = [p for p in parts if abs(p["pos"][0] - cx) < half * 2.2 or np.max(p["size"]) > half]
sel = [p for p in sel if abs(p["pos"][2] - cz) < half * 1.6 or np.max(p["size"]) > half]
hide = os.environ.get("HIDE", "")
if hide:
    sel = [p for p in sel if not any(h in p["path"] for h in hide.split(","))]
render(sel, (cx, 400, cz), (cx, 0, cz), out, ortho=half, size=(14, 10), up=(0, 0, -1), segs=10)
print("ok")
