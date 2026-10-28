import numpy as np, math, sys
sys.argv=sys.argv[:1]
src=open("fit_suzuka.py").read().split("segs, bounds, resid = build_segments()")[0]
exec(src)
for kind,s0,s1,name in RANGES:
    a=math.degrees(KS[s0:s1].sum()); m=s1-s0
    R=m/max(abs(math.radians(a)),1e-6)
    print(f"{kind} {s0:5d}-{s1:5d} {m:4d} m  ang {a:7.2f}  R {R:8.1f} m  {name or ''}")
