#!/usr/bin/env python3
"""Place the retained demo screenshots inside original, generic device frames.

The frames are drawn here with ImageMagick primitives; no Apple marketing device art is used.
Run from the project root (requires ImageMagick 7, `brew install imagemagick`):

    python3 Scripts/generate-device-mockups.py

Output: docs/screenshots/mockups/*.png (transparent background with a soft shadow).
"""
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path.cwd()
SOURCE = ROOT / "docs/screenshots"
OUTPUT = SOURCE / "mockups"
MAGICK = shutil.which("magick") or "magick"


def run(*args: object) -> None:
    subprocess.run([MAGICK, *map(str, args)], check=True)


def size(path: Path) -> tuple[int, int]:
    out = subprocess.run([MAGICK, "identify", "-format", "%w %h", str(path)], check=True, capture_output=True, text=True)
    w, h = out.stdout.split()
    return int(w), int(h)


def rrect(x: float, y: float, w: float, h: float, r: float) -> str:
    return f"roundrectangle {x:g},{y:g} {x + w - 1:g},{y + h - 1:g} {r:g},{r:g}"


class Layer:
    """Accumulates ImageMagick operations onto one transparent canvas."""

    def __init__(self, width: int, height: int, tmp: Path):
        self.width, self.height, self.tmp = width, height, tmp
        self.ops: list[object] = ["-size", f"{width}x{height}", "xc:none"]
        self.count = 0

    def fill(self, color: str, shape: str) -> None:
        self.ops += ["-fill", color, "-stroke", "none", "-draw", shape]

    def gradient(self, x: float, y: float, w: float, h: float, r: float, start: str, end: str, angle: int = 135) -> None:
        """A rounded rectangle filled with a linear gradient."""
        self.count += 1
        tile = self.tmp / f"g{self.count}.png"
        run("-size", f"{int(w)}x{int(h)}", "-define", f"gradient:angle={angle}", f"gradient:{start}-{end}",
            "(", "-size", f"{int(w)}x{int(h)}", "xc:black", "-fill", "white", "-draw", rrect(0, 0, w, h, r), ")",
            "-alpha", "off", "-compose", "CopyOpacity", "-composite", tile)
        self.image(tile, x, y)

    def image(self, path: Path, x: float, y: float, radius: float | None = None) -> None:
        if radius is not None:
            w, h = size(path)
            self.count += 1
            masked = self.tmp / f"m{self.count}.png"
            run(path, "-alpha", "set",
                "(", "-size", f"{w}x{h}", "xc:none", "-fill", "white", "-draw", rrect(0, 0, w, h, radius), ")",
                "-compose", "DstIn", "-composite", masked)
            path = masked
        self.ops += [path, "-geometry", f"+{int(x)}+{int(y)}", "-compose", "Over", "-composite"]

    def save(self, path: Path, shadow: tuple[int, int] = (60, 40), width: int | None = None) -> None:
        blur, offset = shadow
        flat = self.tmp / f"flat-{path.name}"
        run(*self.ops, flat)
        resize = ["-resize", f"{width}x"] if width else []
        # Shadow uses the full silhouette, then the device is laid over it on the same canvas.
        run(flat, "(", "+clone", "-background", "black", "-shadow", f"28x{blur // 2}+0+{offset}", ")",
            "+swap", "-background", "none", "-layers", "merge", "+repage",
            "-gravity", "center", "-extent", f"{self.width}x{self.height + offset}",
            *resize, "-strip", path)
        print(f"wrote {path.relative_to(ROOT)} {'x'.join(map(str, size(path)))}")


def iphone(source: str, name: str, tmp: Path) -> None:
    shot = SOURCE / source
    sw, sh = size(shot)  # 1206 x 2622: 6.3-inch class display at 3x
    bezel, rim, margin, radius = 42, 14, 120, 165
    bw, bh = sw + 2 * (bezel + rim), sh + 2 * (bezel + rim)
    layer = Layer(bw + 2 * margin, bh + 2 * margin, tmp)
    x, y = margin, margin
    for bx, by, h in [(x - 9, y + 420, 110), (x - 9, y + 620, 200), (x - 9, y + 860, 200),  # action, volume
                      (x + bw - 7, y + 720, 300), (x + bw - 7, y + 1560, 190)]:          # side, camera control
        layer.fill("#3a3a3e", rrect(bx, by, 16, h, 8))
    layer.gradient(x, y, bw, bh, radius + bezel + rim, "#76767a", "#404044")
    layer.fill("#0a0a0b", rrect(x + rim, y + rim, bw - 2 * rim, bh - 2 * rim, radius + bezel))
    dx, dy = x + rim + bezel, y + rim + bezel
    layer.image(shot, dx, dy, radius)
    layer.fill("black", rrect(dx + sw / 2 - 189, dy + 33, 378, 111, 55.5))  # Dynamic Island, 126 x 37 pt
    layer.save(OUTPUT / name, shadow=(90, 40), width=900)


def watch(source: str, name: str, tmp: Path) -> None:
    shot = SOURCE / source
    sw, sh = size(shot)  # 416 x 496: 46 mm class display
    bezel, rim, margin, band, radius = 34, 16, 70, 150, 92
    cw, ch = sw + 2 * (bezel + rim), sh + 2 * (bezel + rim)
    layer = Layer(cw + 2 * margin + 30, ch + 2 * (band + margin), tmp)
    x, y = margin, margin + band
    band_w = int(cw * 0.74)
    bx = x + (cw - band_w) // 2
    layer.gradient(bx, margin - 20, band_w, band + 80, 46, "#2e383200", "#242c28", angle=180)
    layer.gradient(bx, y + ch - 60, band_w, band + 80, 46, "#242c28", "#2e383200", angle=180)
    layer.gradient(x + cw - 10, y + 120, 34, 96, 12, "#96969a", "#545458", angle=180)  # Digital Crown
    for gy in range(y + 134, y + 204, 8):
        layer.fill("#3c3c40b0", f"rectangle {x + cw + 8},{gy} {x + cw + 22},{gy + 1}")
    layer.fill("#5c5c60", rrect(x + cw - 8, y + 290, 18, 120, 8))  # side button
    layer.gradient(x, y, cw, ch, radius + bezel + rim, "#7c7c80", "#46464a")
    layer.fill("black", rrect(x + rim, y + rim, cw - 2 * rim, ch - 2 * rim, radius + bezel))
    layer.image(shot, x + rim + bezel, y + rim + bezel, radius)
    layer.save(OUTPUT / name, shadow=(40, 20))


def macbook(source: str, name: str, tmp: Path) -> None:
    shot = SOURCE / source
    ww, wh = size(shot)  # 1200 x 800 window with its own rounded corners
    dw, dh, menu, bezel, lid_rim, margin = 1600, 1000, 30, 34, 6, 60
    lw, lh = dw + 2 * (bezel + lid_rim), dh + 2 * bezel + lid_rim + 30
    base_w, base_h = lw + 280, 42
    layer = Layer(base_w + 2 * margin, margin + lh + base_h + margin, tmp)
    lx, ly = margin + 140, margin
    layer.gradient(lx, ly, lw, lh, 40, "#aaacb0", "#787a7e", angle=180)
    layer.fill("#0c0c0d", rrect(lx + lid_rim, ly + lid_rim, lw - 2 * lid_rim, lh - 2 * lid_rim, 34))
    # Base with rounded front corners and a finger notch.
    by = ly + lh - 2
    layer.gradient(margin, by, base_w, base_h, 22, "#d6d8dc", "#76787c", angle=180)
    layer.fill("#d6d8dc", f"rectangle {margin},{by} {margin + base_w - 1},{by + 18}")
    layer.fill("#96989c", rrect(margin + base_w / 2 - 150, by - 7, 300, 21, 10))
    # Desktop: brand cream-to-lime wallpaper, menu bar, camera housing, then the app window.
    dx, dy = lx + lid_rim + bezel, ly + lid_rim + bezel
    layer.gradient(dx, dy, dw, dh, 12, "#eceede", "#304a3a", angle=145)
    layer.fill("#fafaf4b8", f"rectangle {dx},{dy} {dx + dw - 1},{dy + menu - 1}")
    layer.fill("#0c0c0d", rrect(dx + dw / 2 - 90, dy - 12, 180, menu + 12, 12))
    window_shadow = tmp / "window-shadow.png"
    run(shot, "(", "+clone", "-background", "black", "-shadow", "35x20+0+18", ")", "+swap",
        "-background", "none", "-layers", "merge", "+repage", window_shadow)
    sx, sy = size(window_shadow)
    wx, wy = dx + (dw - ww) / 2, dy + menu + (dh - menu - wh) / 2
    layer.image(window_shadow, wx - (sx - ww) / 2, wy - (sy - wh - 18) / 2 + 9)
    layer.save(OUTPUT / name, shadow=(60, 30), width=1800)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        macbook("07-mac.png", "07-mac-macbook.png", tmp)
        iphone("01-library.png", "01-library-iphone.png", tmp)
        for shot in ["06-watch", "08-watch-player", "09-watch-library", "10-watch-queue", "11-watch-ambient"]:
            watch(f"{shot}.png", f"{shot}-watch.png", tmp)


if __name__ == "__main__":
    main()
