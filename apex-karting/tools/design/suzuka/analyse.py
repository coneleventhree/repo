import sys, numpy as np
rows=[l.split(",") for l in open(sys.argv[1]) if not l.startswith("#")]
A=np.array([[float(v) for v in r] for r in rows])
i,s,x,y,z,w=A[:,0],A[:,1],A[:,2],A[:,3],A[:,4],A[:,8]
n=len(A)
P=np.c_[x,z]
best=(1e9,0,0)
for a in range(n):
    d=np.hypot(*(P-P[a]).T)
    sep=np.minimum(abs(np.arange(n)-a), n-abs(np.arange(n)-a))
    d[sep<40]=1e9
    b=int(np.argmin(d))
    if d[b]<best[0]: best=(d[b],a,b)
d,a,b=best
lo,hi=(a,b) if y[a]<y[b] else (b,a)
print(f"crossing: samples {lo+1} (y {y[lo]:.1f}) under {hi+1} (y {y[hi]:.1f}), xz gap {d:.1f}, clearance {y[hi]-y[lo]:.1f}")
fl=np.r_[P[(lo+1)%n]-P[lo-1]]; fh=np.r_[P[(hi+1)%n]-P[hi-1]]
ang=np.degrees(np.arccos(abs(np.dot(fl,fh))/np.linalg.norm(fl)/np.linalg.norm(fh)))
print(f"crossing angle {ang:.0f} deg at x {x[lo]:.0f} z {z[lo]:.0f}")
# clearance over the whole overlap: for each low sample within 40 of the high road
for k in range(lo-8,lo+9):
    kk=k%n
    d=np.hypot(*(P-P[kk]).T); sep=np.minimum(abs(np.arange(n)-kk), n-abs(np.arange(n)-kk)); d[sep<40]=1e9
    j=int(np.argmin(d))
    print(f"  low {kk+1:4d} y {y[kk]:5.1f}  nearest high {j+1:4d} d {d[j]:5.1f} y {y[j]:5.1f}  dy {y[j]-y[kk]:5.1f}")
g=np.diff(np.r_[y,y[0]])/np.diff(np.r_[s,s[-1]+s[1]-s[0]])
print(f"max climb {g.max()*100:.1f}% at {np.argmax(g)+1}, max drop {g.min()*100:.1f}% at {np.argmin(g)+1}")
lev=np.where(abs(y)<0.3)[0]
print("level samples near start:", [int(v)+1 for v in lev if v<60 or v>n-60][:3], "...", len(lev))
# level run containing sample 1
k=0
while abs(y[(k-1)%n])<0.3 and k>-n: k-=1
m=0
while abs(y[(m+1)%n])<0.3: m+=1
print(f"level run around the line: samples {k%n+1}..{m+1} = {(m-k)*6:.0f} studs; y max {y.max():.1f}")
