"""Puts several screenshots side by side in one image: sheet.py out.jpg pattern1 pattern2 ..."""
import sys, glob, os
from PIL import Image
out = sys.argv[1]
files = []
for pat in sys.argv[2:]:
    m = sorted(glob.glob(pat))
    if m: files.append(m[0])
ims = [Image.open(f) for f in files]
h = max(i.height for i in ims)
ims = [i.resize((int(i.width * h / i.height), h)) for i in ims]
W = sum(i.width for i in ims) + 10 * (len(ims) - 1)
sheet = Image.new("RGB", (W, h), (60, 60, 60))
x = 0
for i in ims:
    sheet.paste(i, (x, 0)); x += i.width + 10
sheet.save(out, quality=70)
print(out, [os.path.basename(f)[:50] for f in files])
