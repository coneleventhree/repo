from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
b=np.asarray(Image.open("icon_b.png").convert("RGB")).astype(float)/255
w=np.asarray(Image.open("icon_w.png").convert("RGB")).astype(float)/255
a=1-np.clip((w-b).mean(axis=2),0,1)
c=np.where(a[...,None]>1e-3, b/np.maximum(a[...,None],1e-3), 0)
kart=Image.fromarray((np.dstack([np.clip(c,0,1),a])*255).astype(np.uint8),"RGBA")
kart=kart.crop(kart.getbbox())
N=1024
img=Image.new("RGBA",(N,N),(20,22,28,255))
d=ImageDraw.Draw(img)
Y=(255,196,0,255)
d.polygon([(0,N*0.98),(N,N*0.50),(N,N*0.70),(0,N*1.18)],fill=Y)
d.polygon([(0,N*0.90),(N,N*0.42),(N,N*0.455),(0,N*0.935)],fill=Y)
sq=26
for i in range(8):
    for j in range(3):
        if (i+j)%2==0:
            x0=N-8*sq+i*sq-30; y0=36+j*sq
            d.rectangle([x0,y0,x0+sq,y0+sq],fill=(240,240,240,255))
F=ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc",430)
tw=d.textbbox((0,0),"A1",font=F)
d.text((50-tw[0],10-tw[1]),"A1",font=F,fill=Y,stroke_width=14,stroke_fill=(20,22,28,255))
k=kart
scale=1.05*N/k.size[0]
k=k.resize((int(k.size[0]*scale),int(k.size[1]*scale)),Image.LANCZOS)
sh=Image.new("RGBA",k.size,(0,0,0,0)); sh.putalpha(k.getchannel("A").point(lambda v:int(v*0.55)))
sh=sh.filter(ImageFilter.GaussianBlur(14))
px=N-k.size[0]+60; py=N-k.size[1]+40
img.alpha_composite(sh,(px+14,py+18)); img.alpha_composite(k,(px,py))
img=img.convert("RGB")
img.resize((512,512),Image.LANCZOS).save("A1-icon-512.png")
