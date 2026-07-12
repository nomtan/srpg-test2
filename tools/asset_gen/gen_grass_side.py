"""Generate the 16x16 grass-block side texture.

Edit ``GRASS_COLORS`` to tune the green hues, then run:

    python tools/asset_gen/gen_grass_side.py

The default output is ``assets/texture/grass/grass_side_01.png``.
"""

import argparse
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_OUT = ROOT / "assets" / "texture" / "grass" / "grass_side_01.png"

# Dark -> light. These are the only values to edit when adjusting the grass.
GRASS_COLORS = (
    "#3c6e2c",
    "#437a32",
    "#4f8f3b"
)

# Dark -> light dirt colors.
DIRT_COLORS = (
    "#64482d",
    "#6e5033",
    "#7a5a3a"
)

# Pattern levels 0-4 are grass; 5-9 are dirt. They are automatically remapped
# across the current palette, so GRASS_COLORS and DIRT_COLORS may contain any
# number of colors while preserving the original light/dark distribution.
PIXEL_MAP = (
    "3222014402230133",
    "1440333012001442",
    "3040332213314422",
    "2045516644966900",
    "5557799797776795",
    "9996779659777759",
    "9996696655999759",
    "9995887658855589",
    "7777567777587778",
    "8555655887777568",
    "8888587887668887",
    "7865885588888877",
    "9696769865589888",
    "9885885776887777",
    "8855889556759988",
    "6686899588779855",
)


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def generate(output_path: Path) -> None:
    grass_palette = tuple(hex_to_rgb(color) for color in GRASS_COLORS)
    dirt_palette = tuple(hex_to_rgb(color) for color in DIRT_COLORS)
    if not grass_palette or not dirt_palette:
        raise ValueError("GRASS_COLORS and DIRT_COLORS must not be empty")

    def pattern_color(pattern_index: int) -> tuple[int, int, int]:
        source_level = pattern_index if pattern_index < 5 else pattern_index - 5
        palette = grass_palette if pattern_index < 5 else dirt_palette
        target_index = round(source_level / 4 * (len(palette) - 1))
        return palette[target_index]

    image = Image.new("RGB", (16, 16))
    pixels = image.load()
    for y, row in enumerate(PIXEL_MAP):
        for x, pattern_index in enumerate(row):
            pixels[x, y] = pattern_color(int(pattern_index))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)
    print(f"wrote {output_path}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def main() -> None:
    generate(parse_args().out.resolve())


if __name__ == "__main__":
    main()
