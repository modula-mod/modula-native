# Contact sheet from review renders.  python3 sheet.py <renderdir> <out.png> <title>
import sys, os
from PIL import Image, ImageDraw, ImageFont
d, outp, title = sys.argv[1], sys.argv[2], sys.argv[3]
rows = [[f"expr_{e}_{v}" for v in ("front", "three_quarter", "side")] for e in ("idle", "blink", "happy", "excited", "surprised", "sleepy", "sad")]
rows.append(["view_rear", "cap_off", "cap_on", "cap_closeup"])
tw, th = 360, 300; cols = max(len(r) for r in rows)
sheet = Image.new("RGB", (cols * tw, len(rows) * th + 50), (22, 24, 30)); dr = ImageDraw.Draw(sheet)
try: font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18); small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
except Exception: font = small = ImageFont.load_default()
dr.text((12, 14), title, fill=(235, 235, 245), font=font)
for r, row in enumerate(rows):
    for c, n in enumerate(row):
        p = os.path.join(d, n + ".png")
        if not os.path.exists(p): continue
        im = Image.open(p).convert("RGB"); im.thumbnail((tw, th)); sheet.paste(im, (c * tw, 50 + r * th))
        dr.text((c * tw + 6, 50 + r * th + 4), n, fill=(200, 200, 210), font=small)
sheet.save(outp); print("SHEET_OK", outp)
