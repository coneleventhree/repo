import numpy as np, math, sys
sys.argv=sys.argv[:1]
exec(open("fit_suzuka.py").read().split("segs, bounds, resid = build_segments()")[0])
for a,b in [(2620,2760),(2980,3110),(3700,4140),(4560,4840),(5380,5803)]:
    print(f"--- {a}-{b} (our s; deg per 20 m)")
    row=[]
    for s in range(a,b,20):
        row.append(f"{s}:{math.degrees(KS[s:s+20].sum()):+.1f}")
    print("  ".join(row))
