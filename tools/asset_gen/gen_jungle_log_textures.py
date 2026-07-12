"""Generate deterministic 32x32 pixel-art textures for a jungle-log block.

Usage:
    python tools/asset_gen/gen_jungle_log_textures.py
    python tools/asset_gen/gen_jungle_log_textures.py --out assets/texture/jungle_log
"""

import argparse
import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "jungle_log"
SIZE = 32


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def generate_end_grain(colors: dict, seed: int = 4101) -> Image.Image:
    """Square-ish growth rings surrounded by an irregular bark rim."""
    rng = Random(seed)
    bark = [hex_to_rgb(color) for color in colors["bark"]]
    wood = [hex_to_rgb(color) for color in colors["end_grain"]]
    ring = hex_to_rgb(colors["ring"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    center_x, center_y = 15.5, 15.5
    for y in range(SIZE):
        for x in range(SIZE):
            edge = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
            # The 3-5px bark frame is deliberately chipped instead of exact.
            bark_depth = 3 + ((x * 7 + y * 11 + seed) % 3)
            if edge < bark_depth:
                stripe = (x // 3 + y // 2 + rng.randrange(2)) % len(bark)
                pixels[x, y] = bark[stripe]
                continue

            dx = abs(x - center_x)
            dy = abs(y - center_y)
            square_radius = max(dx, dy) + min(dx, dy) * 0.18
            wobble = ((x * 13 + y * 17 + seed) % 5 - 2) * 0.16
            ring_index = int((square_radius + wobble) / 3.0)
            if int(square_radius + wobble) % 3 == 0:
                pixels[x, y] = ring
            else:
                pixels[x, y] = wood[(ring_index + (x + y) // 7) % len(wood)]

    # A small offset heart keeps the rings from looking mechanically perfect.
    heart = hex_to_rgb(colors["heart"])
    for y in range(14, 18):
        for x in range(14, 18):
            if (x, y) not in ((14, 14), (17, 17)):
                pixels[x, y] = heart if (x + y) % 2 else wood[0]
    return image


def generate_bark_side(colors: dict, seed: int = 4201) -> Image.Image:
    """Horizontally layered bark; every row wraps seamlessly left-to-right."""
    rng = Random(seed)
    bark = [hex_to_rgb(color) for color in colors["bark"]]
    dark = hex_to_rgb(colors["bark_shadow"])
    light = hex_to_rgb(colors["bark_highlight"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    for y in range(SIZE):
        band = (y // 4 + (1 if y % 9 == 0 else 0)) % len(bark)
        phase = rng.randrange(SIZE)
        for x in range(SIZE):
            # Integer waves form chunky, readable bark ridges at 32px.
            wave = ((x + phase) // 5 + (x // 11) + y // 3) % 3
            color = bark[(band + wave) % len(bark)]
            if y % 7 in (0, 1) and (x + phase) % 9 < 6:
                color = dark
            elif y % 6 == 3 and (x + phase) % 8 < 4:
                color = light
            pixels[x, y] = color

    # Short knots/cracks; duplicated modulo SIZE so horizontal tiling remains clean.
    for _ in range(10):
        start_x = rng.randrange(SIZE)
        y = rng.randrange(2, SIZE - 2)
        length = rng.randrange(3, 8)
        color = dark if rng.random() < 0.7 else light
        for offset in range(length):
            pixels[(start_x + offset) % SIZE, y + (offset // 4)] = color
    return image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))["jungle_log"]
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        "jungle_log_end_01.png": generate_end_grain(palette),
        "jungle_log_side_01.png": generate_bark_side(palette),
    }
    for filename, image in outputs.items():
        path = out_dir / filename
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
