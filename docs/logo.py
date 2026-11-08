#!/usr/bin/env python3
"""The serdab mark: a horseshoe arch, three steps going down, light at the bottom.

Writes docs/logo.svg (the mark), app/assets/icon.svg (launcher icon with
background) and app/assets/icon-fg.svg (adaptive foreground, sized for the 16%
inset Android adds), then renders PNGs with headless Chrome. ImageMagick's own
SVG renderer drops the gradients, so Chrome it is. Run from the repo root.
"""
import math
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

r, cx, cy, a = 230, 512, 470, math.radians(20)
lx, rx, y = cx - r * math.cos(a), cx + r * math.cos(a), cy + r * math.sin(a)
ARCH = f"M {lx:.1f} 800 L {lx:.1f} {y:.1f} A {r} {r} 0 1 1 {rx:.1f} {y:.1f} L {rx:.1f} 800"

MARK = f'''
  <defs>
    <linearGradient id="glow" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#F2B65A" stop-opacity="0"/>
      <stop offset="55%" stop-color="#F2B65A" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="#F2B65A" stop-opacity="0.85"/>
    </linearGradient>
    <radialGradient id="lamp" cx="0.5" cy="1" r="0.75">
      <stop offset="0%" stop-color="#FFD58A" stop-opacity="0.95"/>
      <stop offset="60%" stop-color="#F2B65A" stop-opacity="0.15"/>
      <stop offset="100%" stop-color="#F2B65A" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="door"><path d="{ARCH} Z"/></clipPath>
  </defs>
  <g clip-path="url(#door)">
    <rect x="200" y="200" width="624" height="600" fill="url(#glow)"/>
    <rect x="200" y="200" width="624" height="600" fill="url(#lamp)"/>
  </g>
  <rect x="362" y="598" width="300" height="22" rx="11" fill="#E8C48A" fill-opacity="0.45"/>
  <rect x="392" y="658" width="240" height="22" rx="11" fill="#E8C48A" fill-opacity="0.7"/>
  <rect x="422" y="718" width="180" height="22" rx="11" fill="#F6D9A6"/>
  <path d="{ARCH}" fill="none" stroke="#E8C48A" stroke-width="28" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M 190 800 H 834" stroke="#E8C48A" stroke-width="28" stroke-linecap="round"/>
'''


def svg(path: pathlib.Path, background: bool, scale: float) -> None:
    t = 512 - 512 * scale
    bg = '<rect width="1024" height="1024" fill="#120F0C"/>' if background else ""
    path.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
        f'{bg}<g transform="translate({t:.1f} {t:.1f}) scale({scale})">{MARK}</g></svg>\n'
    )


def png(src: pathlib.Path, dst: pathlib.Path, size: int = 1024) -> None:
    subprocess.run(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000",
         f"--window-size={size},{size}", f"--screenshot={dst}", f"file://{src}"],
        check=True, capture_output=True,
    )


if __name__ == "__main__":
    jobs = [
        (ROOT / "app/assets/icon.svg", True, 0.80, ROOT / "app/assets/icon.png"),
        (ROOT / "app/assets/icon-fg.svg", False, 0.80, ROOT / "app/assets/icon-fg.png"),
        (ROOT / "docs/logo.svg", False, 1.00, ROOT / "docs/logo.png"),
        (ROOT / "app/assets/logo.svg", False, 1.00, None),
    ]
    for src, background, scale, dst in jobs:
        svg(src, background, scale)
        if dst:
            png(src, dst)
        print("wrote", src.relative_to(ROOT), "+ png" if dst else "")
