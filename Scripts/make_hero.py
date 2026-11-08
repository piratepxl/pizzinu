#!/usr/bin/env python3
"""Fotografa la scena iniziale della landing page per l'immagine d'apertura del README.

Uso:
    python3 Scripts/make_hero.py ../HTML/Pizzinu.html docs/images/hero.png

Richiede Google Chrome e Pillow. Nasconde il riquadro «Provalo qui» e la scritta
«trascinami!» (hanno senso solo nella pagina interattiva) e rende trasparenti gli
angoli arrotondati, così l'immagine sta bene anche col tema scuro di GitHub.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2])
WIDTH, SCALE, RADIUS = 1440, 2, 28

inject = """<style>header.top,footer,main>*:not(#prova),#desk .panel,#desk .hint{display:none!important}
html,body{margin:0!important;padding:0!important;overflow:hidden}#prova{margin:0 auto!important;padding:24px!important}</style>
<script>addEventListener('load',()=>{const d=document.getElementById('desk').getBoundingClientRect();
document.title=JSON.stringify([d.x,d.y,d.width,d.height])})</script></body>"""

with tempfile.TemporaryDirectory() as tmp:
    page = Path(tmp) / "hero.html"
    page.write_text(SRC.read_text(encoding="utf-8").replace("</body>", inject, 1), encoding="utf-8")
    shot = Path(tmp) / "shot.png"
    common = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
              f"--window-size={WIDTH},900", "--virtual-time-budget=6000"]
    subprocess.run(common + [f"--force-device-scale-factor={SCALE}", f"--screenshot={shot}", page.as_uri()],
                   check=True, capture_output=True)
    dom = subprocess.run(common + ["--dump-dom", page.as_uri()], check=True, capture_output=True, text=True).stdout
    x, y, w, h = json.loads(re.search(r"<title>(.*?)</title>", dom).group(1))
    im = Image.open(shot).convert("RGBA").crop(
        (round(x * SCALE), round(y * SCALE), round((x + w) * SCALE), round((y + h) * SCALE)))

mask = Image.new("L", im.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], RADIUS * SCALE, fill=255)
im.putalpha(mask)
OUT.parent.mkdir(parents=True, exist_ok=True)
im.save(OUT, optimize=True)
print("==>", OUT, im.size)
