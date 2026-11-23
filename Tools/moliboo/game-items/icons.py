import json,os,cairosvg,math
cat=json.load(open('catalogue.json'))
os.makedirs('icons',exist_ok=True)
M='fill="url(#m)" stroke="url(#o)" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"'
A='fill="url(#a)" stroke="url(#o)" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"'
W='fill="#FFFFFF" opacity="0.55"'
def star(cx,cy,r,ri=None,n=5,attr=A):
  ri=ri or r*0.45;p=[]
  for k in range(2*n):
    rr=r if k%2==0 else ri;a=-math.pi/2+k*math.pi/n;p.append(f'{cx+rr*math.cos(a):.1f},{cy+rr*math.sin(a):.1f}')
  return f'<polygon points="{" ".join(p)}" {attr}/>'
def gl(x,y,rx,ry,rot=-20): return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" transform="rotate({rot} {x} {y})" {W}/>'
S={
'halo':f'<ellipse cx="128" cy="128" rx="88" ry="40" fill="none" stroke="url(#o)" stroke-width="30"/><ellipse cx="128" cy="128" rx="88" ry="40" fill="none" stroke="url(#a)" stroke-width="20"/>'+gl(90,100,22,6,-12),
'curls':''.join(f'<circle cx="{x}" cy="{y}" r="{r}" {M}/>' for x,y,r in [(80,140,40),(176,140,40),(128,110,50),(100,165,34),(156,165,34)])+gl(110,85,18,9),
'tunic':f'<path d="M80 60 L104 52 Q128 74 152 52 L176 60 L214 100 L188 124 L176 112 L176 206 L80 206 L80 112 L68 124 L42 100 Z" {M}/><path d="M104 52 Q128 74 152 52" fill="none" stroke="url(#a)" stroke-width="10"/>'+star(128,140,22)+gl(100,90,16,8),
'wings':f'<path d="M124 150 C80 40 20 70 30 120 C36 160 80 180 124 150Z" {M}/><path d="M132 150 C176 40 236 70 226 120 C220 160 176 180 132 150Z" {M}/><path d="M60 120 Q84 130 108 140 M196 120 Q172 130 148 140" stroke="url(#a)" stroke-width="7" fill="none" stroke-linecap="round"/>'+gl(60,95,16,7,-30)+gl(196,95,16,7,30),
'glow':f'<circle cx="128" cy="128" r="90" fill="url(#rg)"/><circle cx="128" cy="128" r="44" {A}/>'+gl(112,108,16,9),
'crown':f'<path d="M48 176 L40 76 L88 116 L128 56 L168 116 L216 76 L208 176 Z" {A}/><rect x="48" y="170" width="160" height="30" rx="10" {M}/>'+''.join(f'<circle cx="{x}" cy="185" r="8" fill="url(#m)" stroke="url(#o)" stroke-width="3"/>' for x in (88,128,168))+gl(90,110,14,8),
'sweep':f'<path d="M40 150 C40 70 120 40 200 70 C230 82 222 120 196 110 C160 96 120 110 96 170 C80 200 40 190 40 150Z" {M}/><path d="M80 120 C110 90 150 80 190 86" stroke="#fff" stroke-opacity=".5" stroke-width="10" fill="none" stroke-linecap="round"/>',
'trumpet':f'<path d="M40 116 L150 108 L210 68 L210 188 L150 148 L40 140 Z" {A}/><rect x="70" y="140" width="16" height="30" rx="6" {M}/><rect x="100" y="140" width="16" height="30" rx="6" {M}/>'+gl(180,96,10,22,0),
'rays':''.join(f'<path d="M128 128 L{128+100*math.cos(a-0.16):.0f} {128+100*math.sin(a-0.16):.0f} L{128+100*math.cos(a+0.16):.0f} {128+100*math.sin(a+0.16):.0f}Z" {A}/>' for a in [k*math.pi/4 for k in range(8)])+f'<circle cx="128" cy="128" r="46" {M}/>'+gl(112,110,16,9),
'tiara':f'<path d="M36 170 Q128 120 220 170 L206 186 Q128 146 50 186Z" {M}/><path d="M86 150 L104 100 L128 136 L152 100 L170 150 Q128 136 86 150Z" {A}/>'+star(128,84,26,attr=M)+gl(120,76,6,4),
'locks':f'<path d="M50 200 C30 110 60 50 128 46 C196 50 226 110 206 200 C190 210 178 196 176 160 C172 120 150 100 128 100 C106 100 84 120 80 160 C78 196 66 210 50 200Z" {M}/>'+gl(90,80,22,10),
'cape':f'<path d="M84 56 L172 56 L212 210 Q128 230 44 210 Z" {M}/><path d="M84 56 L172 56 L162 80 L94 80Z" {A}/><circle cx="128" cy="72" r="12" {A}/>'+gl(96,120,10,40,10),
'cap':f'<path d="M50 150 C50 80 206 80 206 150 Z" {M}/><path d="M120 150 L230 150 Q230 176 196 176 L120 170Z" {A}/><circle cx="128" cy="86" r="10" {A}/>'+gl(96,110,20,10),
'spiky':f'<path d="M40 190 L56 110 L80 150 L96 60 L124 130 L150 50 L164 130 L196 70 L196 150 L222 120 L214 190Z" {M}/>'+gl(96,120,8,22,10),
'hoodie':f'<path d="M78 70 Q128 20 178 70 L214 110 L190 132 L178 120 L178 208 L78 208 L78 120 L66 132 L42 110Z" {M}/><path d="M98 70 Q128 100 158 70" {A}/><rect x="100" y="160" width="56" height="30" rx="10" {A}/>'+gl(96,100,14,8),
'shoes':f'<path d="M36 170 L40 110 Q70 96 96 120 Q140 140 204 140 Q228 150 220 176 Z" {M}/><rect x="32" y="168" width="194" height="22" rx="11" {A}/><path d="M80 120 L96 140 M100 118 L114 138" stroke="url(#o)" stroke-width="6" stroke-linecap="round"/>'+gl(70,124,14,6),
'board':f'<rect x="28" y="100" width="200" height="44" rx="22" {M}/><path d="M50 122 L206 122" stroke="url(#a)" stroke-width="8" stroke-dasharray="14 12" stroke-linecap="round"/><circle cx="70" cy="162" r="16" {A}/><circle cx="186" cy="162" r="16" {A}/>'+gl(80,110,30,5,0),
'headphones':f'<path d="M50 150 C50 50 206 50 206 150" fill="none" stroke="url(#o)" stroke-width="26" stroke-linecap="round"/><path d="M50 150 C50 50 206 50 206 150" fill="none" stroke="url(#m)" stroke-width="16" stroke-linecap="round"/><rect x="28" y="130" width="50" height="76" rx="22" {A}/><rect x="178" y="130" width="50" height="76" rx="22" {A}/>'+gl(44,150,8,16,0)+gl(194,150,8,16,0),
'fringe':f'<path d="M36 140 C40 70 216 70 220 140 L196 128 L184 156 L162 126 L146 160 L128 128 L110 160 L94 126 L72 156 L60 128 Z" {M}/>'+gl(96,96,24,9),
'tee':f'<path d="M84 58 Q128 84 172 58 L216 92 L194 128 L176 116 L176 206 L80 206 L80 116 L62 128 L40 92 Z" {M}/>'+star(128,146,26)+gl(100,92,14,7),
'shades':f'<rect x="28" y="96" width="88" height="62" rx="26" {A}/><rect x="140" y="96" width="88" height="62" rx="26" {A}/><path d="M116 112 Q128 102 140 112" stroke="url(#o)" stroke-width="8" fill="none"/>'+gl(56,114,18,8)+gl(168,114,18,8),
'rings':''.join(f'<circle cx="128" cy="128" r="{r}" fill="none" stroke="url(#a)" stroke-width="12" opacity="{o}"/>' for r,o in [(96,.45),(70,.7),(44,1)])+f'<circle cx="128" cy="128" r="20" {M}/>',
'band':f'<path d="M30 150 Q128 70 226 150" fill="none" stroke="url(#o)" stroke-width="30" stroke-linecap="round"/><path d="M30 150 Q128 70 226 150" fill="none" stroke="url(#m)" stroke-width="20" stroke-linecap="round"/>'+star(128,88,36),
'mohawk':f'<path d="M70 200 C60 150 80 120 96 70 L110 110 L120 40 L136 100 L150 50 L160 110 L178 80 C190 130 196 160 186 200 Z" {M}/>'+gl(112,120,8,26,8),
'jacket':f'<path d="M82 56 L174 56 L214 96 L192 124 L176 110 L176 208 L80 208 L80 110 L64 124 L42 96 Z" {M}/><path d="M128 60 L128 208" stroke="url(#o)" stroke-width="6"/><path d="M104 56 L128 98 L152 56" {A}/><rect x="92" y="150" width="24" height="20" rx="5" {A}/><rect x="140" y="150" width="24" height="20" rx="5" {A}/>'+gl(100,96,12,8),
'glitch':''.join(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="6" {A if i%2 else M} opacity="{o}"/>' for i,(x,y,s,o) in enumerate([(40,60,40,.5),(90,90,48,.75),(150,70,36,.6),(130,140,56,1),(60,150,44,.9),(180,150,30,.5)])),
'leafcap':f'<path d="M50 160 C50 80 206 80 206 160Z" {M}/><path d="M128 92 C100 40 160 20 190 30 C186 70 160 96 128 92Z" {A}/><path d="M128 92 Q150 60 180 38" stroke="url(#o)" stroke-width="4" fill="none"/>'+gl(90,126,18,8),
'pack':f'<rect x="58" y="70" width="140" height="140" rx="40" {M}/><rect x="84" y="128" width="88" height="56" rx="16" {A}/><path d="M96 70 Q128 30 160 70" fill="none" stroke="url(#o)" stroke-width="12"/>'+gl(88,96,16,9),
'wand':f'<path d="M60 210 L150 110" stroke="url(#o)" stroke-width="18" stroke-linecap="round"/><path d="M60 210 L150 110" stroke="url(#m)" stroke-width="10" stroke-linecap="round"/>'+star(170,86,52)+gl(158,72,8,5),
'beret':f'<ellipse cx="128" cy="140" rx="98" ry="50" {M}/><rect x="70" y="160" width="116" height="22" rx="10" {A}/><circle cx="128" cy="88" r="10" {A}/>'+gl(90,124,26,10),
'buns':f'<circle cx="68" cy="88" r="40" {M}/><circle cx="188" cy="88" r="40" {M}/><path d="M40 190 C40 100 216 100 216 190Z" {M}/><rect x="84" y="64" width="12" height="40" rx="6" transform="rotate(30 68 88)" {A}/><rect x="160" y="64" width="12" height="40" rx="6" transform="rotate(-30 188 88)" {A}/>'+gl(56,74,10,6)+gl(176,74,10,6),
'petals':''.join(f'<ellipse cx="{x}" cy="{y}" rx="26" ry="14" transform="rotate({r} {x} {y})" {A if i%2 else M}/>' for i,(x,y,r) in enumerate([(70,70,30),(180,80,-40),(120,130,10),(60,170,-20),(190,180,50)])),
'antlers':f'<path d="M110 200 C100 150 70 130 50 80 M76 130 C50 120 40 100 40 90 M70 104 C80 84 82 70 78 52" fill="none" stroke="url(#o)" stroke-width="22" stroke-linecap="round"/><path d="M110 200 C100 150 70 130 50 80 M76 130 C50 120 40 100 40 90 M70 104 C80 84 82 70 78 52" fill="none" stroke="url(#m)" stroke-width="13" stroke-linecap="round"/><path d="M146 200 C156 150 186 130 206 80 M180 130 C206 120 216 100 216 90 M186 104 C176 84 174 70 178 52" fill="none" stroke="url(#o)" stroke-width="22" stroke-linecap="round"/><path d="M146 200 C156 150 186 130 206 80 M180 130 C206 120 216 100 216 90 M186 104 C176 84 174 70 178 52" fill="none" stroke="url(#m)" stroke-width="13" stroke-linecap="round"/>'+''.join(f'<circle cx="{x}" cy="{y}" r="9" {A}/>' for x,y in [(50,80),(206,80),(78,52),(178,52)]),
'freckles':''.join(star(x,y,r) for x,y,r in [(70,100,24),(186,100,24),(100,160,16),(156,160,16),(128,90,14)]),
'sparkle':''.join(star(x,y,r,r*0.28,4) for x,y,r in [(110,110,60),(186,74,30),(178,180,36),(60,190,24)]),
'helmet':f'<circle cx="128" cy="128" r="90" {M}/><path d="M64 120 Q128 80 192 120 L192 160 Q128 190 64 160Z" {A}/>'+gl(100,140,26,10,-10)+gl(84,70,14,8),
'telescope':f'<g transform="rotate(-28 128 128)"><rect x="30" y="104" width="70" height="48" rx="12" {M}/><rect x="96" y="96" width="70" height="64" rx="12" {A}/><rect x="162" y="86" width="64" height="84" rx="14" {M}/></g><path d="M118 168 L90 220 M130 168 L160 220" stroke="url(#o)" stroke-width="8" stroke-linecap="round"/>'+gl(180,90,8,16,30),
'nightcap':f'<path d="M44 178 C60 100 120 40 200 60 C176 80 164 120 212 178 Z" {M}/><rect x="36" y="168" width="184" height="32" rx="16" {A}/><circle cx="204" cy="60" r="18" {A}/>'+star(110,130,14,attr=A)+gl(90,140,10,20,20),
'slippers':f'<ellipse cx="128" cy="160" rx="96" ry="42" {M}/><ellipse cx="80" cy="100" rx="14" ry="36" transform="rotate(-15 80 100)" {M}/><ellipse cx="116" cy="96" rx="14" ry="36" transform="rotate(10 116 96)" {M}/><ellipse cx="80" cy="106" rx="6" ry="22" transform="rotate(-15 80 100)" {A}/><ellipse cx="116" cy="102" rx="6" ry="22" transform="rotate(10 116 96)" {A}/><circle cx="196" cy="150" r="12" {A}/>'+gl(110,146,30,8,0),
'star':star(128,132,96,46,attr=M)+'<circle cx="108" cy="130" r="7" fill="#2B2B3D"/><circle cx="148" cy="130" r="7" fill="#2B2B3D"/><path d="M116 150 Q128 160 140 150" stroke="#2B2B3D" stroke-width="5" fill="none" stroke-linecap="round"/>'+gl(104,96,14,7),
'lantern':f'<path d="M128 30 L128 56" stroke="url(#o)" stroke-width="8"/><rect x="88" y="52" width="80" height="20" rx="8" {A}/><path d="M80 72 L176 72 Q196 136 176 196 L80 196 Q60 136 80 72Z" {M}/><circle cx="128" cy="136" r="26" fill="#FFF3B0" opacity=".9"/><rect x="88" y="196" width="80" height="18" rx="8" {A}/>'+gl(96,100,8,20,0),
'mask':f'<path d="M24 120 C40 80 108 86 128 110 C148 86 216 80 232 120 C224 170 150 170 128 140 C106 170 32 170 24 120Z" {M}/><path d="M60 124 Q80 112 100 124 M156 124 Q176 112 196 124" stroke="url(#o)" stroke-width="7" fill="none" stroke-linecap="round"/>'+star(128,90,14)+gl(64,108,18,6),
'bubbles':''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#a)" fill-opacity=".45" stroke="url(#o)" stroke-width="4"/><ellipse cx="{x-r*.35}" cy="{y-r*.4}" rx="{r*.3}" ry="{r*.16}" transform="rotate(-30 {x-r*.35} {y-r*.4})" {W}/>' for x,y,r in [(100,110,60),(184,80,30),(176,180,36),(60,200,20)]),
'notes':f'<path d="M80 180 L80 70 L190 50 L190 160" fill="none" stroke="url(#o)" stroke-width="12" stroke-linejoin="round"/><ellipse cx="62" cy="182" rx="28" ry="20" {A}/><ellipse cx="172" cy="162" rx="28" ry="20" {A}/><path d="M80 90 L190 70" stroke="url(#o)" stroke-width="12"/>'+gl(56,174,8,4),
'shorts':f'<path d="M58 60 L198 60 L214 196 L144 196 L128 120 L112 196 L42 196 Z" {M}/><rect x="56" y="56" width="144" height="24" rx="8" {A}/>'+gl(80,110,10,26,8),
'skirt':f'<path d="M78 62 L178 62 L222 196 Q128 220 34 196 Z" {M}/><rect x="74" y="54" width="108" height="26" rx="10" {A}/><path d="M100 90 L80 196 M128 90 L128 205 M156 90 L176 196" stroke="url(#o)" stroke-opacity=".35" stroke-width="5"/>'+gl(90,120,8,26,15),
'cone':f'<path d="M128 30 L210 206 Q128 226 46 206Z" {M}/><path d="M92 110 L164 110 M74 150 L182 150" stroke="url(#a)" stroke-width="14" stroke-linecap="round"/><circle cx="128" cy="30" r="20" {A}/>'+gl(110,96,8,22,22),
'beanie':f'<path d="M44 170 C44 60 212 60 212 170Z" {M}/><rect x="36" y="160" width="184" height="40" rx="16" {A}/><circle cx="128" cy="52" r="24" {A}/>'+''.join(f'<path d="M{x} 166 L{x} 196" stroke="url(#o)" stroke-opacity=".3" stroke-width="5"/>' for x in range(60,210,20))+gl(92,110,22,10),
'glasses':f'<circle cx="76" cy="128" r="44" fill="url(#a)" fill-opacity=".35" stroke="url(#o)" stroke-width="12"/><circle cx="180" cy="128" r="44" fill="url(#a)" fill-opacity=".35" stroke="url(#o)" stroke-width="12"/><path d="M120 120 Q128 110 136 120" stroke="url(#o)" stroke-width="10" fill="none"/>'+gl(62,110,14,7)+gl(166,110,14,7),
'boots':f'<path d="M70 40 L140 40 L140 150 Q210 150 214 192 L70 192 Z" {M}/><rect x="62" y="184" width="160" height="22" rx="10" {A}/><rect x="64" y="36" width="82" height="24" rx="10" {A}/>'+gl(90,90,10,30,0),
}
def svg(shape,pal,tile=True):
  c0,c1,c2,c3=pal
  bg=f'<rect x="8" y="8" width="240" height="240" rx="56" fill="url(#bg)"/><rect x="8" y="8" width="240" height="120" rx="56" fill="#fff" opacity=".18"/>' if tile else ''
  return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="512" height="512"><defs>
<linearGradient id="m" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c2}"/><stop offset="1" stop-color="{c0}"/></linearGradient>
<linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".35"/><stop offset=".25" stop-color="{c1}"/><stop offset="1" stop-color="{c1}"/></linearGradient>
<linearGradient id="o" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c3}"/><stop offset="1" stop-color="{c3}"/></linearGradient>
<radialGradient id="rg"><stop offset="0" stop-color="{c1}" stop-opacity=".9"/><stop offset="1" stop-color="{c1}" stop-opacity="0"/></radialGradient>
<radialGradient id="bg" cx=".5" cy=".35" r=".8"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="{c2}"/></radialGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="6" stdDeviation="6" flood-color="{c3}" flood-opacity=".35"/></filter></defs>
{bg}<g filter="url(#sh)" transform="translate(128 128) scale(0.78) translate(-128 -128)">{S[shape]}</g></svg>'''
for i in cat['items']:
  s=svg(i['shape'],i['palette']); open(f"icons/{i['iconKey']}.svg",'w').write(s)
  cairosvg.svg2png(bytestring=s.encode(),write_to=f"icons/{i['iconKey']}.png",output_width=256,output_height=256)
print('ok',len(cat['items']))
items={i['itemId']:i for i in cat['items']}
pos=[(128,72,.56),(70,138,.46),(186,138,.46),(86,198,.4),(170,198,.4)]
for o in cat['outfits']:
  pal=items[o['itemIds'][0]]['palette'];c0,c1,c2,c3=pal
  inner=''
  for (x,y,sc),iid in zip(pos,o['itemIds']):
    inner+=f'<g transform="translate({x} {y}) scale({sc}) translate(-128 -128)">{S[items[iid]["shape"]]}</g>'
  s=svg('halo',pal).replace(S['halo'],inner)
  open(f"icons/{o['iconKey']}.svg",'w').write(s)
  cairosvg.svg2png(bytestring=s.encode(),write_to=f"icons/{o['iconKey']}.png",output_width=256,output_height=256)
# contact sheet
from PIL import Image,ImageDraw,ImageFont
ents=[(o['iconKey'],o['name']+' (set)') for o in cat['outfits']]+[(i['iconKey'],i['name']) for i in cat['items']]
cols=12;cw,ch=170,200;rows=-(-len(ents)//cols)
sheet=Image.new('RGB',(cols*cw+20,rows*ch+80),'#F4F1FA');d=ImageDraw.Draw(sheet)
try: f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13);F=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',26)
except: f=F=ImageFont.load_default()
d.text((20,22),f"Moliboo items batch v1 — {len(cat['outfits'])} full outfits + {len(cat['items'])} items (glossy 2D)",fill='#3A3060',font=F)
for k,(key,name) in enumerate(ents):
  x=10+(k%cols)*cw;y=70+(k//cols)*ch
  im=Image.open(f'icons/{key}.png').convert('RGBA').resize((150,150));sheet.paste(im,(x+10,y),im)
  t=name if len(name)<22 else name[:21]+'…';w=d.textlength(t,font=f);d.text((x+cw/2-w/2,y+158),t,fill='#3A3060',font=f)
sheet.save('/workspace/modula-design/moliboo-items-batch.png');print(sheet.size)
