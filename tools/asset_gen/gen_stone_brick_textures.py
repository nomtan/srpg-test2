"""Generate 32x32 pixel-art textures for the stone-brick asset family.

Usage:
    python tools/asset_gen/gen_stone_brick_textures.py
    python tools/asset_gen/gen_stone_brick_textures.py --out assets/texture/stone_bricks
"""

import argparse
import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "stone_bricks"
SIZE = 32
COURSE_HEIGHT = 10


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def _brick_bounds(x: int, y: int) -> tuple[int, int, int, int]:
    course = y // COURSE_HEIGHT
    row_top = course * COURSE_HEIGHT
    row_bottom = min(row_top + COURSE_HEIGHT - 1, SIZE - 1)
    offset = 0 if course % 2 == 0 else 8
    local_x = (x - offset) % 16
    left = x - local_x
    right = left + 15
    return left, right, row_top, row_bottom


def generate_stone_brick(colors: dict, seed: int = 7101) -> Image.Image:
    rng = Random(seed)
    stone = [hex_to_rgb(color) for color in colors["stone"]]
    mortar = hex_to_rgb(colors["mortar"])
    edge_light = hex_to_rgb(colors["edge_light"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    for y in range(SIZE):
        for x in range(SIZE):
            left, _right, top, _bottom = _brick_bounds(x, y)
            local_x = (x - left) % 16
            local_y = y - top
            if y in (0, 10, 20, 30, 31) or local_x == 0:
                pixels[x, y] = mortar
            elif local_y == 1 or local_x == 1:
                pixels[x, y] = edge_light
            else:
                value = (x * 13 + y * 17 + rng.randrange(5)) % len(stone)
                pixels[x, y] = stone[value]
    return image


def generate_infested_cracked(colors: dict, seed: int = 7201) -> Image.Image:
    image = generate_stone_brick(colors, seed)
    pixels = image.load()
    crack = hex_to_rgb(colors["crack"])
    pit = hex_to_rgb(colors["pit"])
    rng = Random(seed + 91)

    # Branching cracks stay off the outermost pixels so tile seams remain clean.
    for _ in range(11):
        x = rng.randrange(3, SIZE - 3)
        y = rng.randrange(2, SIZE - 3)
        length = rng.randrange(3, 9)
        for step in range(length):
            pixels[x, y] = crack
            if step > 1 and rng.random() < 0.28:
                pixels[x + (1 if rng.random() < 0.5 else -1), y] = pit
            x = min(max(x + rng.choice((-1, 0, 1)), 2), SIZE - 3)
            y = min(y + 1, SIZE - 3)

    for _ in range(28):
        x, y = rng.randrange(2, SIZE - 2), rng.randrange(2, SIZE - 2)
        pixels[x, y] = pit
        if rng.random() < 0.35:
            pixels[x + 1, y] = crack
    return image


def generate_chiseled(colors: dict, seed: int = 7301) -> Image.Image:
    rng = Random(seed)
    stone = [hex_to_rgb(color) for color in colors["stone"]]
    dark = hex_to_rgb(colors["mortar"])
    light = hex_to_rgb(colors["edge_light"])
    pit = hex_to_rgb(colors["pit"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    for y in range(SIZE):
        for x in range(SIZE):
            edge = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
            if edge in (0, 4, 5, 10, 11):
                color = dark
            elif edge in (1, 6, 12):
                color = light
            else:
                color = stone[(x * 7 + y * 11 + rng.randrange(3)) % len(stone)]
            pixels[x, y] = color

    # Recessed central square spiral inspired by the chiseled reference.
    path = []
    left, top, right, bottom = 12, 12, 19, 19
    while left <= right and top <= bottom:
        for x in range(left, right + 1):
            path.append((x, top))
        for y in range(top + 1, bottom + 1):
            path.append((right, y))
        if top < bottom:
            for x in range(right - 1, left - 1, -1):
                path.append((x, bottom))
        if left < right:
            for y in range(bottom - 1, top + 1, -1):
                path.append((left, y))
        left += 2
        top += 2
        right -= 2
        bottom -= 2
    for x, y in path:
        pixels[x, y] = pit
    return image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    colors = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))["stone_bricks"]
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        "stone_brick.png": generate_stone_brick(colors),
        "infested_cracked_stone_bricks.png": generate_infested_cracked(colors),
        "chiseled_stone_brick.png": generate_chiseled(colors),
    }
    for filename, image in outputs.items():
        path = out_dir / filename
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
