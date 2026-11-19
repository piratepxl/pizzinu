#!/usr/bin/env python3
"""Compone le immagini del README partendo dalle istantanee dell'app.

Uso:
    PIZZINU_SNAPSHOT_DIR=/tmp/snap build/Pizzinu.app/Contents/MacOS/Pizzinu
    python3 Scripts/make_screenshots.py /tmp/snap docs/images

Richiede Pillow. Produce desktop.png, themes.png, secret.png, markdown-reminder.png.
Liquid Glass non c'è: il vetro di sistema non compare nelle istantanee.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

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


def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def vgrad(w, h, top, bottom):
    g = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((w, h))

def fuchsia(W, H):
    """Sfondo fucsia di Pizzinu (lo stesso del sito e delle immagini social)."""
    # viewBox 1200×800 in «slice», come nel sito.
    k = max(W / 1200, H / 800) * 1.25
    ox, oy = (W - 1200 * k) / 2, (H - 800 * k) / 2
    bg = Image.new('RGB', (W, H))
    c0, c1 = hexc('#e51fb2'), hexc('#9d0c78')
    cx, cy, R = W / 2, H / 2, 0.8 * math.hypot(W, H) / math.sqrt(2)
    small = Image.new('RGB', (W // 4, H // 4))
    for y in range(small.height):
        for x in range(small.width):
            t = min(1, math.hypot(x * 4 - cx, y * 4 - cy) / R)
            small.putpixel((x, y), tuple(int(a + (b - a) * t) for a, b in zip(c0, c1)))
    bg = small.resize((W, H), Image.BICUBIC)
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    grads = {'A': ('#ff4fe0', '#c2108f'), 'B': ('#ffa6ee', '#f21fc0')}
    pills = [(-40, -90, 170, 560, 'A'), (135, 330, 170, 560, 'B'), (310, -90, 170, 560, 'B'),
             (485, 330, 170, 560, 'A'), (660, -90, 170, 560, 'A'), (835, 330, 170, 560, 'B'),
             (1010, -90, 170, 560, 'B'), (-40, 420, 170, 460, 'B'), (1010, 420, 170, 460, 'A')]
    for x, y, w, h, g in pills:
        X, Y, PW, PH = int(ox + x * k), int(oy + y * k), int(w * k), int(h * k)
        fill = vgrad(PW, PH, hexc(grads[g][0]), hexc(grads[g][1]))
        mask = Image.new('L', (PW, PH), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, PW - 1, PH - 1], radius=int(85 * k), fill=255)
        pill = fill.convert('RGBA'); pill.putalpha(mask)
        layer.alpha_composite(pill, (X, Y)) if X >= 0 and Y >= 0 else layer.paste(pill, (X, Y), pill)
    for pts, op in [([(730, 400), (665, 512), (535, 512), (470, 400), (535, 287), (665, 287)], 0.7),
                    ([(540, 640), (475, 752), (345, 752), (280, 640), (345, 527), (475, 527)], 0.45)]:
        P = [(ox + px * k, oy + py * k) for px, py in pts]
        xs, ys = [p[0] for p in P], [p[1] for p in P]
        bx, by, bw, bh = int(min(xs)), int(min(ys)), int(max(xs) - min(xs)) + 1, int(max(ys) - min(ys)) + 1
        fill = Image.new('RGB', (bw, bh))
        a, b = hexc('#8fd0ff'), hexc('#d985ff')
        for yy in range(bh):
            for xx in range(0, bw, 2):
                t = (xx / bw + yy / bh) / 2
                col = tuple(int(u + (v - u) * t) for u, v in zip(a, b))
                fill.putpixel((xx, yy), col)
                if xx + 1 < bw: fill.putpixel((xx + 1, yy), col)
        mask = Image.new('L', (bw, bh), 0)
        ImageDraw.Draw(mask).polygon([(x - bx, y - by) for x, y in P], fill=int(255 * op))
        hx = fill.convert('RGBA'); hx.putalpha(mask)
        layer.alpha_composite(hx, (bx, by))
    layer = layer.filter(ImageFilter.GaussianBlur(16 * k))
    out = bg.convert('RGBA'); out.alpha_composite(layer)
    # vignettatura come nel video
    vig = Image.new('L', (W // 4, H // 4))
    for y in range(vig.height):
        for x in range(vig.width):
            d = math.hypot((x * 4 - W / 2) / (W * 0.6), (y * 4 - H * 0.45) / (H * 0.6))
            vig.putpixel((x, y), int(255 * 0.12 * max(0, min(1, (d - 0.4) / 0.6))))
    vig = vig.resize((W, H), Image.BICUBIC)
    dark = Image.new('RGBA', (W, H), (40, 0, 30, 0)); dark.putalpha(vig)
    out.alpha_composite(dark)
    out = ImageEnhance.Brightness(out.convert('RGB')).enhance(1.10)
    out = ImageEnhance.Color(out).enhance(1.08)
    return out.convert('RGBA')


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
desk = fuchsia(W, H)
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
gal = fuchsia(cols * cell_w + 80, rows * cell_h + 80)
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
sec = fuchsia(1800, 820)
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
mr = fuchsia(W4, H4)
mr.alpha_composite(md, (70, 90))
mr.alpha_composite(tools, (560, H4 - tools.height - 50))
shadow = Image.new("RGBA", (picker.width + 80, picker.height + 80), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([40, 50, picker.width + 40, picker.height + 50], 28, fill=(60, 30, 80, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
px, py = W4 - picker.width - 90, (H4 - picker.height) // 2
mr.alpha_composite(shadow, (px - 40, py - 40))
mr.alpha_composite(picker, (px, py))
save(mr, "markdown-reminder.png")
