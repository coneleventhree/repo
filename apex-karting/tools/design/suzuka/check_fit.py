import json, math, sys
import numpy as np
FIT=sys.argv[1] if len(sys.argv)>1 else "suzuka_fit"; sys.argv=[sys.argv[0]]
exec(open("fit_suzuka.py").read().split("segs, bounds, resid = build_segments()")[0])  # helpers only
J=json.load(open(W+"work/"+FIT+".json"))
segs=J["segs"]; free=J["free"]; real=np.array(J["real"])
_,_,_,pts=walk(segs,free)
P=np.array([(p[0],p[1]) for p in pts]); seg_of=np.array([p[2] for p in pts])
n=len(P)
from scipy.spatial import cKDTree
t=cKDTree(P)
close=[]
for i in range(0,n,4):
    for j in t.query_ball_point(P[i],60):
        sep=min(abs(i-j),n-abs(i-j))
        if sep>200:
            close.append((np.hypot(*(P[i]-P[j])),i,j))
close.sort()
seen=[]
for d,i,j in close:
    if any(abs(i-a)<120 for _,a,_ in seen): continue
    seen.append((d,i,j))
for d,i,j in seen[:10]:
    print(f"s {i:5d} ({segs[seg_of[i]].get('name')}) near s {j:5d} ({segs[seg_of[j]].get('name')}): {d:5.1f} studs")
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
fig,ax=plt.subplots(figsize=(13,11))
ax.plot(real[:,0],real[:,1],"r-",lw=0.8,label="real x0.8")
ax.plot(P[:,0],P[:,1],"k-",lw=1,label="fit")
for k,s in enumerate(segs):
    if s.get("name"):
        idx=np.where(seg_of==k)[0]
        if len(idx): m=idx[len(idx)//2]; ax.annotate(s["name"],P[m],fontsize=8,color="b")
ax.set_aspect("equal"); ax.invert_yaxis(); ax.legend(); ax.grid(alpha=0.3)
plt.savefig(FIT+".png",dpi=70)
