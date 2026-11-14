"""Joins preview.py's frames into one image per clip. Runs in plain Python with Pillow."""

import glob
import os
import sys

from PIL import Image, ImageDraw

folder = sys.argv[1]
names = sorted({os.path.basename(p).split("__")[0] for p in glob.glob(os.path.join(folder, "*__*.png"))})
for name in names:
    paths = sorted(glob.glob(os.path.join(folder, name + "__*.png")))
    images = [Image.open(p).convert("RGB") for p in paths]
    w, h = images[0].size
    columns = min(len(images), 7)
    rows = (len(images) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * w, rows * h), "white")
    draw = ImageDraw.Draw(sheet)
    for i, (image, path) in enumerate(zip(images, paths)):
        x, y = (i % columns) * w, (i // columns) * h
        sheet.paste(image, (x, y))
        draw.text((x + 6, y + 4), path.rsplit("__", 1)[1][:3], fill="black")
    sheet.save(os.path.join(folder, "SHEET_" + name + ".png"))
    for p in paths:
        os.remove(p)
print("sheets", len(names))
