#!/usr/bin/env python3
"""PNG frames -> looping GIF.   tools/gif.py <frames-dir> <out.gif> [fps=10]"""
import glob, os, sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
fps = float(sys.argv[3]) if len(sys.argv) > 3 else 10
files = sorted(glob.glob(os.path.join(src, '*.png')))
frames = [Image.open(f).convert('RGB').quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
          for f in files]
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
frames[0].save(out, save_all=True, append_images=frames[1:], duration=round(1000 / fps), loop=0, optimize=True)
print(out, len(frames), 'frames', round(os.path.getsize(out) / 1e6, 2), 'MB')
