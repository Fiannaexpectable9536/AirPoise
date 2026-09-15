#!/usr/bin/env python3
"""Comic-style DMG window background: newsprint, ink, drop-to-Applications."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist" / "dmg-stage" / ".background" / "dmg-bg.png"
OUT.parent.mkdir(parents=True, exist_ok=True)

W, H = 1320, 840
PAPER = (242, 230, 196)
INK = (20, 17, 13)
POP = (227, 27, 35)
MUTE = (92, 83, 70)
BURST = (255, 214, 10)

img = Image.new("RGB", (W, H), PAPER)
d = ImageDraw.Draw(img)
for y in range(0, H, 5):
    for x in range((y // 5) % 2, W, 5):
        d.point((x, y), fill=(210, 196, 160))
d.rectangle((18, 18, W - 19, H - 19), outline=INK, width=8)
d.rectangle((36, 36, W - 37, H - 37), outline=INK, width=2)

def font(size, names):
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default()

bang = font(64, [
    str(ROOT / "Resources/Fonts/Bangers-Regular.ttf"),
    "/System/Library/Fonts/Supplemental/Impact.ttf",
])
inkf = font(28, [
    str(ROOT / "Resources/Fonts/ArchivoBlack-Regular.ttf"),
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
])
serif = font(22, [
    "/System/Library/Fonts/NewYork.ttf",
    "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
])

d.rectangle((470, 70, 850, 168), fill=BURST, outline=INK, width=5)
d.text((498, 86), "AIRPOISE", font=bang, fill=POP)
d.text((494, 82), "AIRPOISE", font=bang, fill=INK)
d.text((494, 82), "AIRPOISE", font=bang, fill=POP)

d.text((430, 190), "Drag the app onto Applications.", font=inkf, fill=INK)

# Arrow between the two drop targets (icons sit at ~160,220 and 500,220 in 660pt window = 2x)
d.polygon(
    [(560, 430), (740, 430), (740, 390), (820, 460), (740, 530), (740, 490), (560, 490)],
    fill=POP,
    outline=INK,
)

d.text((360, 720), "macOS 14+  ·  AirPods with Spatial Audio  ·  on-device", font=serif, fill=MUTE)

img.save(OUT, "PNG", optimize=True)
print("wrote", OUT)
