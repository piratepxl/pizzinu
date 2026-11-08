#!/usr/bin/env python3
"""Compone le immagini del README partendo dalle istantanee dell'app.

Uso:
    PIZZINU_SNAPSHOT_DIR=/tmp/snap build/Pizzinu.app/Contents/MacOS/Pizzinu
    python3 Scripts/make_screenshots.py /tmp/snap docs/images

Richiede Pillow. Produce desktop.png, themes.png, secret.png, markdown-reminder.png.
Liquid Glass non c'è: il vetro di sistema non compare nelle istantanee.
"""
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SNAP = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
VETRINA = SNAP / "vetrina"


def load(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def trim(im: Image.Image, pad: int = 24) -> Image.Image:
    """Toglie il margine trasparente lasciando un po' d'aria per l'ombra."""
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if not box:
        return im
    l, t, r, b = box
    return im.crop((max(l - pad, 0), max(t - pad, 0), min(r + pad, im.width), min(b + pad, im.height)))


def scale(im: Image.Image, factor: float) -> Image.Image:
    return im.resize((round(im.width * factor), round(im.height * factor)), Image.LANCZOS)


def wallpaper(w: int, h: int, colors, blobs, seed: int = 7) -> Image.Image:
    """Sfondo sfumato con macchie di colore morbide, nello stile delle scrivanie di macOS."""
    base = Image.new("RGB", (w, h))
    top, bottom = colors
    draw = ImageDraw.Draw(base)
    for y in range(h):
        t = y / (h - 1)
        draw.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    rnd = random.Random(seed)
    for color in blobs:
        r = rnd.randint(h // 3, h // 2)
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        ld.ellipse([x - r, y - r, x + r, y + r], fill=color + (150,))
    layer = layer.filter(ImageFilter.GaussianBlur(h // 6))
    out = base.convert("RGBA")
    out.alpha_composite(layer)
    return out


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def save(im: Image.Image, name: str, radius: int = 28) -> None:
    rounded(im, radius).save(OUT / name, optimize=True)
    print("==>", OUT / name, im.size)


# 1. Scrivania con i pizzini
W, H = 2400, 1400
desk = wallpaper(W, H, ((252, 214, 236), (196, 186, 252)),
                 [(255, 170, 214), (160, 200, 255), (255, 214, 160), (200, 160, 255)])
placements = [  # (file, x, y, scala)
    ("spesa", 140, 120, 1.0),
    ("chiamare", 700, 90, 1.0),
    ("libro", 1320, 120, 1.0),
    ("riunione", 1700, 420, 1.0),
    ("ricetta", 260, 720, 1.0),
    ("idea", 860, 640, 1.0),
    ("respira", 1420, 860, 0.9),
    ("bolletta", 1900, 920, 0.85),
]
for name, x, y, f in placements:
    desk.alpha_composite(scale(trim(load(VETRINA / f"{name}.png")), f), (x, y))
save(desk, "desktop.png")

# 2. Galleria dei temi
themes = [trim(load(p)) for p in sorted(VETRINA.glob("tema-*.png"))]
cols, cell_w, cell_h = 5, 440, 400
rows = (len(themes) + cols - 1) // cols
gal = wallpaper(cols * cell_w + 80, rows * cell_h + 80, ((255, 246, 251), (238, 232, 255)),
                [(255, 205, 232), (205, 225, 255)], seed=3)
for i, im in enumerate(themes):
    f = min((cell_w - 40) / im.width, (cell_h - 40) / im.height, 0.8)
    im = scale(im, f)
    in_row = min(cols, len(themes) - (i // cols) * cols)  # l'ultima riga resta centrata
    cx = 40 + (cols - in_row) * cell_w // 2 + (i % cols) * cell_w + (cell_w - im.width) // 2
    cy = 40 + (i // cols) * cell_h + (cell_h - im.height) // 2
    gal.alpha_composite(im, (cx, cy))
save(gal, "themes.png")

# 3. Pizzino segreto: aperto → sigillato
opened = trim(load(SNAP / "segreto-aperto.png"))
sealed = scale(trim(load(SNAP / "segreto-chiuso.png")), 1.5)
sec = wallpaper(1800, 820, ((248, 238, 222), (226, 210, 190)), [(255, 226, 190), (230, 196, 170)], seed=11)
sec.alpha_composite(opened, (110, (820 - opened.height) // 2))
arrow = ImageDraw.Draw(sec)
ax, ay = 110 + opened.width + 70, 410
arrow.line([(ax, ay), (ax + 200, ay)], fill=(150, 110, 80, 255), width=10)
arrow.polygon([(ax + 230, ay), (ax + 190, ay - 28), (ax + 190, ay + 28)], fill=(150, 110, 80, 255))
sec.alpha_composite(sealed, (ax + 320, (820 - sealed.height) // 2))
save(sec, "secret.png")

# 4. Foglio Markdown con la barra e selettore del promemoria
md = trim(load(SNAP / "markdown-scrittura.png"))
picker_full = load(SNAP / "promemoria.png")
# Il popover ha lo sfondo trasparente (lo disegna il sistema): lo si appoggia su una
# scheda bianca. La metà destra dell'istantanea è la versione scura.
picker = trim(picker_full.crop((0, 0, picker_full.width // 2 - 16, picker_full.height)), 4)
card = Image.new("RGBA", (picker.width + 48, picker.height + 48), (250, 250, 252, 255))
card.alpha_composite(picker, (24, 24))
picker = rounded(scale(card, 0.78), 30)
tools = scale(trim(load(VETRINA / "comandi.png")), 0.85)
W4, H4 = 2200, 1100
mr = wallpaper(W4, H4, ((236, 240, 255), (252, 222, 240)), [(190, 210, 255), (255, 200, 230)], seed=5)
mr.alpha_composite(md, (70, 90))
mr.alpha_composite(tools, (560, H4 - tools.height - 50))
shadow = Image.new("RGBA", (picker.width + 80, picker.height + 80), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([40, 50, picker.width + 40, picker.height + 50], 28, fill=(60, 30, 80, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
px, py = W4 - picker.width - 90, (H4 - picker.height) // 2
mr.alpha_composite(shadow, (px - 40, py - 40))
mr.alpha_composite(picker, (px, py))
save(mr, "markdown-reminder.png")
