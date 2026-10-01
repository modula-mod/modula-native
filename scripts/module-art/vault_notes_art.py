from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math

TEAL=(54,156,170); DEEP=(17,72,82); MINT=(140,214,206); INK=(23,36,38)

def gradient(w,h,c1,c2,angle=135):
    img=Image.new('RGB',(w,h)); px=img.load()
    a=math.radians(angle); dx,dy=math.cos(a),math.sin(a)
    L=abs(w*dx)+abs(h*dy)
    for y in range(h):
        for x in range(w):
            t=((x*dx+y*dy)-min(0,w*dx)-min(0,h*dy))/L
            px[x,y]=tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3))
    return img

def glow(img, xy, r, color, alpha=90):
    layer=Image.new('RGBA',img.size,(0,0,0,0)); d=ImageDraw.Draw(layer)
    x,y=xy; d.ellipse((x-r,y-r,x+r,y+r),fill=color+(alpha,))
    layer=layer.filter(ImageFilter.GaussianBlur(r/2.2))
    img.alpha_composite(layer)

def sheet(img, box, radius, fold, lines, check=False, shadow=True, fill=(250,253,253)):
    x0,y0,x1,y1=box
    if shadow:
        sh=Image.new('RGBA',img.size,(0,0,0,0)); d=ImageDraw.Draw(sh)
        d.rounded_rectangle((x0+radius*0.2,y0+radius*0.6,x1+radius*0.2,y1+radius*0.6),radius,fill=(5,30,35,110))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(radius*0.6)))
    paper=Image.new('RGBA',img.size,(0,0,0,0)); pd=ImageDraw.Draw(paper)
    pd.rounded_rectangle(box,radius,fill=fill)
    f=fold
    pd.rectangle((x1-radius,y0,x1,y0+radius),fill=fill)
    pd.polygon([(x1-f-1,y0-1),(x1+1,y0-1),(x1+1,y0+f+1)],fill=(0,0,0,0))
    pd.polygon([(x1-f,y0),(x1,y0+f),(x1-f+radius*0.25,y0+f)],fill=(196,226,226))
    pd.polygon([(x1-f,y0),(x1-f+radius*0.25,y0+f),(x1-f,y0+f-radius*0.1)],fill=(196,226,226))
    img.alpha_composite(paper)
    d=ImageDraw.Draw(img)
    w=x1-x0; lh=max(4,int(w*0.055))
    yy=y0+int((y1-y0)*0.24)
    for i,frac in enumerate(lines):
        lx=x0+int(w*0.16)
        if check and i>=1:
            s=int(lh*2.2); d.rounded_rectangle((lx,yy-s//3,lx+s,yy-s//3+s),int(s*0.28),outline=TEAL,width=max(2,lh//2))
            if i==1:
                d.line([(lx+s*0.22,yy-s//3+s*0.52),(lx+s*0.44,yy-s//3+s*0.74),(lx+s*0.8,yy-s//3+s*0.26)],fill=TEAL,width=max(2,lh//2))
            lx+=int(s*1.5)
        col=(23,36,38) if i==0 else (150,172,175)
        d.rounded_rectangle((lx,yy,lx+int((x1-lx-w*0.16)*frac),yy+lh*(2 if i==0 else 1)),lh,fill=col if i else TEAL)
        yy+=int(lh*(4.2 if i==0 else 3.4))

def icon(size=1024):
    img=gradient(size,size,(64,176,188),(16,78,90)).convert('RGBA')
    glow(img,(int(size*0.25),int(size*0.2)),int(size*0.45),(170,236,228),80)
    glow(img,(int(size*0.85),int(size*0.95)),int(size*0.4),(8,40,48),120)
    # back sheet
    s=size
    back=Image.new('RGBA',img.size,(0,0,0,0))
    sheet(back,(int(s*.30),int(s*.18),int(s*.80),int(s*.76)),int(s*.07),int(s*.11),[0.5,0.8,0.6],fill=(196,232,230))
    back=back.rotate(9,center=(s/2,s/2),resample=Image.BICUBIC)
    img.alpha_composite(back)
    sheet(img,(int(s*.22),int(s*.24),int(s*.72),int(s*.84)),int(s*.07),int(s*.12),[0.55,0.9,0.75,0.82],check=True)
    # vault lock badge
    d=ImageDraw.Draw(img); cx,cy,r=int(s*.72),int(s*.76),int(s*.13)
    sh=Image.new('RGBA',img.size,(0,0,0,0)); ImageDraw.Draw(sh).ellipse((cx-r,cy-r+12,cx+r,cy+r+12),fill=(0,30,35,120))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))
    d=ImageDraw.Draw(img)
    d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=(23,36,38))
    d.ellipse((cx-r+10,cy-r+10,cx+r-10,cy+r-10),outline=MINT,width=8)
    bw,bh=int(r*.9),int(r*.72)
    d.arc((cx-bw*0.34,cy-bh*1.05,cx+bw*0.34,cy-bh*0.05+6),180,360,fill=MINT,width=int(r*.13))
    d.rounded_rectangle((cx-bw/2,cy-bh*0.38,cx+bw/2,cy+bh*0.62),int(r*.12),fill=MINT)
    d.ellipse((cx-r*.09,cy-r*.02,cx+r*.09,cy+r*.16),fill=(23,36,38))
    return img.convert('RGB')

def font(size, weight=700):
    f=ImageFont.truetype('/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf',size)
    try: f.set_variation_by_axes([28, weight])
    except Exception: pass
    return f

def cover(w=1600,h=900):
    """Text-free hero art, composed around the centre so any aspect-fill crop works."""
    img=gradient(w,h,(28,108,120),(10,46,54),160).convert('RGBA')
    glow(img,(int(w*.62),int(h*.22)),int(h*.6),(110,210,206),70)
    glow(img,(int(w*.2),int(h*1.0)),int(h*.5),(5,25,30),120)
    glow(img,(int(w*.35),int(h*.35)),int(h*.35),(70,170,170),40)
    layer=Image.new('RGBA',img.size,(0,0,0,0))
    sheet(layer,(int(w*.49),int(h*.12),int(w*.70),int(h*.68)),28,46,[0.6,0.9,0.7,0.8],fill=(214,238,236))
    layer=layer.rotate(-9,center=(w*.6,h*.4),resample=Image.BICUBIC); img.alpha_composite(layer)
    layer=Image.new('RGBA',img.size,(0,0,0,0))
    sheet(layer,(int(w*.31),int(h*.22),int(w*.53),int(h*.86)),28,46,[0.5,0.85,0.7,0.6],check=True)
    layer=layer.rotate(6,center=(w*.42,h*.54),resample=Image.BICUBIC); img.alpha_composite(layer)
    d=ImageDraw.Draw(img)
    for x,y,r,a in [(.2,.3,10,90),(.78,.72,14,70),(.84,.28,8,90),(.16,.7,6,70),(.72,.9,7,60)]:
        d.ellipse((w*x-r,h*y-r,w*x+r,h*y+r),fill=(196,236,232,a))
    return img.convert('RGB')

icon().save('vault-notes-icon.png')
cover().save('vault-notes-cover.jpg',quality=88)
print('ok')
