import json, sys, numpy as np, math
ARG=sys.argv[1]; sys.argv=sys.argv[:1]
exec(open("fit_suzuka.py").read().split("segs, bounds, resid = build_segments()")[0])
J=json.load(open(ARG))
segs=J["segs"]; free=J["free"]; real=np.array(J["real"])
_,_,_,pts=walk(segs,free)
P=np.array([(p[0],p[1]) for p in pts]); so=np.array([p[2] for p in pts])
from scipy.spatial import cKDTree
t=cKDTree(real)
d,_=t.query(P)
for k,s in enumerate(segs):
    idx=np.where(so==k)[0]
    if len(idx)==0: continue
    print(f"{k:2d} {idx[0]:5d} {s['kind']} {str(s.get('length',s.get('radius'))):>7} {s.get('angle',''):>8} {str(s.get('name') or ''):15s} dev max {d[idx].max():5.1f}")
