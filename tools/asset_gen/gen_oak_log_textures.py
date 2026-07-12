"""Generate deterministic 32x32 pixel-art textures for an oak-log block.

Usage:
    python tools/asset_gen/gen_oak_log_textures.py
    python tools/asset_gen/gen_oak_log_textures.py --out assets/texture/oak_log
"""

import argparse
import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "oak_log"
SIZE = 32


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def generate_end_grain(colors: dict, seed: int = 5101) -> Image.Image:
    """Light oak end grain with square-ish rings and a narrow bark rim."""
    rng = Random(seed)
    bark = [hex_to_rgb(color) for color in colors["bark"]]
    wood = [hex_to_rgb(color) for color in colors["end_grain"]]
    ring = hex_to_rgb(colors["ring"])
    heart = hex_to_rgb(colors["heart"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    center_x, center_y = 15.0, 16.0
    for y in range(SIZE):
        for x in range(SIZE):
            edge = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
            bark_depth = 3 + ((x * 5 + y * 7 + seed) % 2)
            if edge < bark_depth:
                pixels[x, y] = bark[(x // 3 + y // 3 + rng.randrange(2)) % len(bark)]
                continue

            dx = abs(x - center_x)
            dy = abs(y - center_y)
            radius = max(dx, dy) + min(dx, dy) * 0.12
            wobble = ((x * 11 + y * 19 + seed) % 5 - 2) * 0.12
            ring_index = int((radius + wobble) / 2.8)
            if int(radius + wobble) % 3 == 0:
                pixels[x, y] = ring
            else:
                pixels[x, y] = wood[(ring_index + (x + y) // 9) % len(wood)]

    for y in range(14, 18):
        for x in range(13, 17):
            if (x + y) % 3:
                pixels[x, y] = heart if (x + y) % 2 else wood[0]
    return image


def generate_bark_side(colors: dict, seed: int = 5201) -> Image.Image:
    """Mostly vertical oak bark strips with short cracks and knots."""
    rng = Random(seed)
    bark = [hex_to_rgb(color) for color in colors["bark"]]
    dark = hex_to_rgb(colors["bark_shadow"])
    light = hex_to_rgb(colors["bark_highlight"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    widths = []
    remaining = SIZE
    while remaining > 0:
        width = min(rng.randint(2, 5), remaining)
        widths.append(width)
        remaining -= width

    x_start = 0
    for strip_index, width in enumerate(widths):
        phase = rng.randrange(7)
        for x in range(x_start, x_start + width):
            for y in range(SIZE):
                color = bark[(strip_index + y // 8 + (x + phase) // 3) % len(bark)]
                if x == x_start and (y + phase) % 9 < 7:
                    color = dark
                elif x == x_start + width - 1 and (y + phase) % 8 < 5:
                    color = light
                pixels[x, y] = color
        x_start += width

    # Broken vertical grooves and compact knots make the strips less uniform.
    for _ in range(15):
        x = rng.randrange(SIZE)
        start_y = rng.randrange(SIZE)
        length = rng.randrange(2, 7)
        color = dark if rng.random() < 0.7 else light
        for offset in range(length):
            pixels[x, (start_y + offset) % SIZE] = color
            if offset > 2 and rng.random() < 0.3:
                pixels[(x + 1) % SIZE, (start_y + offset) % SIZE] = color

    for _ in range(3):
        cx, cy = rng.randrange(2, SIZE - 2), rng.randrange(3, SIZE - 3)
        for dx, dy in ((0, -1), (-1, 0), (0, 0), (1, 0), (0, 1)):
            pixels[cx + dx, cy + dy] = dark if (dx, dy) != (0, 0) else light
    return image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))["oak_log"]
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        "oak_log_end_01.png": generate_end_grain(palette),
        "oak_log_side_01.png": generate_bark_side(palette),
    }
    for filename, image in outputs.items():
        path = out_dir / filename
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
