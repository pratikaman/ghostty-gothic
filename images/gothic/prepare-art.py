#!/usr/bin/env python3
"""Turn the Codex source art in images/gothic/art-src into the 2x UI
assets the macOS app loads from Resources/ghostty/gothic/art.

    python3 images/gothic/prepare-art.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "images/gothic/art-src"
OUT = ROOT / "gothic/art"
DIVIDER_PX = 24  # 12pt split divider at 2x


def rgba(name):
    img = Image.open(SRC / name).convert("RGBA")
    return img.crop(img.getbbox())


def save(img, name, size):
    img.resize(size, Image.LANCZOS).save(OUT / name, optimize=True)


def ends(profile, axis_len):
    """Where the wide ends (capital/base, corbels) stop and start, given
    the opaque extent across each row or column."""
    mid = profile[int(axis_len * 0.4):int(axis_len * 0.6)]
    wide = profile > np.median(mid) * 1.15
    first = next(i for i in range(axis_len // 2, -1, -1) if wide[i]) + 1
    last = next(i for i in range(axis_len // 2, axis_len) if wide[i])
    return first, last


def column():
    img = rgba("column.png")
    w, h = img.size
    top, bottom = ends((np.array(img)[:, :, 3] > 32).sum(axis=1), h)
    scale = DIVIDER_PX / w
    save(img.crop((0, 0, w, top)), "column-top.png", (DIVIDER_PX, round(top * scale)))
    save(img.crop((0, bottom, w, h)), "column-bottom.png", (DIVIDER_PX, round((h - bottom) * scale)))
    # The shaft is a plain cylinder: average a band into one row so it
    # tiles without seams.
    band = np.array(img.crop((0, h // 2 - 40, w, h // 2 + 40))).astype(float).mean(axis=0, keepdims=True)
    row = Image.fromarray(np.repeat(band, 8, axis=0).round().astype(np.uint8), "RGBA")
    save(row, "column-shaft.png", (DIVIDER_PX, 8))


def beam():
    img = rgba("beam.png")
    w, h = img.size
    left, right = ends((np.array(img)[:, :, 3] > 32).sum(axis=0), w)
    scale = DIVIDER_PX / h
    save(img.crop((0, 0, left, h)), "beam-left.png", (round(left * scale), DIVIDER_PX))
    save(img.crop((right, 0, w, h)), "beam-right.png", (round((w - right) * scale), DIVIDER_PX))

    # Cut the middle to a whole number of ornament repeats so it tiles.
    lum = np.array(img.convert("L")).astype(float)
    profile = lum[:, left:right].mean(axis=0)
    profile -= profile.mean()
    lags = range(12, min(240, len(profile) // 3))
    corr = [np.dot(profile[:-lag], profile[lag:]) / (len(profile) - lag) for lag in lags]
    period = lags[int(np.argmax(corr))]
    repeats = max(1, round(120 / period))
    start = (left + right) // 2
    tile = img.crop((start, 0, start + period * repeats, h))
    save(tile, "beam-shaft.png", (max(1, round(tile.width * scale)), DIVIDER_PX))
    print(f"beam: ends at {left}/{right}, ornament period {period}px x{repeats}")


def doors():
    img = Image.open(SRC / "doors.png").convert("RGB")
    w, h = img.size
    for name, box in (("door-left.png", (0, 0, w // 2, h)), ("door-right.png", (w // 2, 0, w, h))):
        save(img.crop(box), name, (640, 960))


def main():
    OUT.mkdir(exist_ok=True)
    column()
    beam()
    doors()
    save(Image.open(SRC / "stone-tile.png").convert("RGB"), "stone.png", (256, 256))
    save(Image.open(SRC / "glass-tile.png").convert("RGB"), "glass.png", (256, 256))
    save(Image.open(SRC / "parchment.png").convert("RGB"), "parchment.png", (768, 768))
    save(Image.open(SRC / "initial-G.png").convert("RGBA"), "initial-G.png", (192, 192))
    for f in sorted(OUT.glob("*.png")):
        print(f"{f.name}: {Image.open(f).size}")


if __name__ == "__main__":
    main()
