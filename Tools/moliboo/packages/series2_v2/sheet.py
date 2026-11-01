import sys
from pathlib import Path
from PIL import Image, ImageDraw
def sheet(items, cols, cell, out, bg=(246, 243, 250)):
    rows = (len(items) + cols - 1) // cols
    lab = 18
    sh = Image.new("RGB", (cols * cell, rows * (cell + lab)), bg); d = ImageDraw.Draw(sh)
    for i, (label, im) in enumerate(items):
        r, k = divmod(i, cols)
        t = im.copy().convert("RGBA"); t.thumbnail((cell - 8, cell - 8), Image.Resampling.LANCZOS)
        tile = Image.new("RGBA", (cell, cell), bg + (255,))
        # cell frame shows the full 640 canvas so clipping would be visible
        tile.alpha_composite(t, ((cell - t.width) // 2, (cell - t.height) // 2))
        ImageDraw.Draw(tile).rectangle([(cell - t.width) // 2, (cell - t.height) // 2, (cell + t.width) // 2 - 1, (cell + t.height) // 2 - 1], outline=(225, 220, 235))
        sh.paste(tile.convert("RGB"), (k * cell, r * (cell + lab)))
        d.text((k * cell + 4, r * (cell + lab) + cell + 2), label, fill=(50, 40, 60))
    sh.save(out)
if __name__ == "__main__":
    src = Path(sys.argv[1]); nums = sys.argv[3:]
    items = []
    for n in nums:
        f = next(src.glob(f"{int(n):03d}_*"))
        items.append((f.name, Image.open(f / "portrait.png")))
    sheet(items, min(len(items), 7), 220, sys.argv[2])
