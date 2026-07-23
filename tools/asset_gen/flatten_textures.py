"""One-off post-process for Plan B's flat-shading comparison
(docs/dev/phase/phase17-step1.md T7).

Usage:
    python tools/asset_gen/flatten_textures.py

gen_terrain_textures.py's output has shading baked in (grass clumps, stone
AO-like darkening, cliff vertical gradients) that reads as double-dark once
it also goes through the face-factor flat shader, unfairly disadvantaging
Plan B in the A/B comparison. This script does NOT touch gen_terrain_textures.py
or regenerate assets/terrain/textures/ - it reads the existing output and
writes a brightness-compressed copy to assets/terrain/flattened/ for
flat_validation.tscn's Plan B to use instead.

Throwaway: if Plan B is picked in step1, gen_terrain_textures.py gets
properly rewritten in step2 and this script (and assets/terrain/flattened/)
goes away.
"""

import colorsys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
SRC_DIR = ROOT / "assets" / "terrain" / "textures"
OUT_DIR = ROOT / "assets" / "terrain" / "flattened"

# How hard to pull each pixel's value toward the image's mean value.
# 0.0 = no change, 1.0 = every pixel flattens to the mean.
VALUE_COMPRESSION = 0.75


def flatten_image(image: Image.Image) -> tuple:
    """Returns (flattened_image, (before_spread, after_spread)) where spread
    is (max_v - min_v) over the image, in 0..1 value units."""
    rgb = image.convert("RGB")
    pixels = list(rgb.getdata())
    hsv_pixels = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255) for r, g, b in pixels]
    values = [v for _h, _s, v in hsv_pixels]
    mean_v = sum(values) / len(values)
    before_spread = max(values) - min(values)

    new_values = []
    out_pixels = []
    for h, s, v in hsv_pixels:
        new_v = mean_v + (v - mean_v) * (1.0 - VALUE_COMPRESSION)
        new_v = max(0.0, min(1.0, new_v))
        new_values.append(new_v)
        r, g, b = colorsys.hsv_to_rgb(h, s, new_v)
        out_pixels.append((round(r * 255), round(g * 255), round(b * 255)))

    out = Image.new("RGB", rgb.size)
    out.putdata(out_pixels)
    after_spread = max(new_values) - min(new_values)
    return out, (before_spread, after_spread)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for src_path in sorted(SRC_DIR.glob("*.png")):
        image = Image.open(src_path)
        flattened, (before_spread, after_spread) = flatten_image(image)
        out_path = OUT_DIR / src_path.name
        flattened.save(out_path)
        print(
            f"{src_path.name}: spread {before_spread * 100:.1f}% -> {after_spread * 100:.1f}%"
        )


if __name__ == "__main__":
    main()
