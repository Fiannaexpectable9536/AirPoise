#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Resources" / "AppIcon.iconset"
OUT.mkdir(parents=True, exist_ok=True)

SIZES = [16, 32, 64, 128, 256, 512, 1024]


def make(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size * 0.08
    # rounded square fill
    d.rounded_rectangle(
        [m, m, size - m, size - m],
        radius=size * 0.22,
        fill=(28, 32, 38, 255),
    )
    cx, cy = size / 2, size * 0.46
    r = size * 0.16
    # head
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(120, 220, 160, 255), width=max(1, size // 28))
    # spine with a hint of upright
    stem_w = max(1, size // 22)
    d.line([(cx, cy + r * 0.85), (cx, size * 0.78)], fill=(120, 220, 160, 255), width=stem_w)
    # ear-bud dots
    br = max(1, size * 0.035)
    d.ellipse([cx - r - br * 2, cy - br, cx - r, cy + br], fill=(90, 200, 255, 255))
    d.ellipse([cx + r, cy - br, cx + r + br * 2, cy + br], fill=(90, 200, 255, 255))
    if size >= 64:
        img = img.filter(ImageFilter.SMOOTH)
    return img


for s in SIZES:
    im = make(s)
    im.save(OUT / f"icon_{s}x{s}.png")
    if s <= 512:
        im2 = make(s * 2)
        im2.save(OUT / f"icon_{s}x{s}@2x.png")

print("wrote", OUT)
