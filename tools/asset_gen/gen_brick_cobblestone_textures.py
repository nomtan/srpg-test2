"""Generate 32x32 pixel-art brick and cobblestone textures.

Usage:
    python tools/asset_gen/gen_brick_cobblestone_textures.py
    python tools/asset_gen/gen_brick_cobblestone_textures.py --out assets/texture/masonry
"""

import argparse
import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "masonry"
SIZE = 32


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def generate_bricks(colors: dict, seed: int = 8101) -> Image.Image:
    rng = Random(seed)
    brick = [hex_to_rgb(color) for color in colors["brick"]]
    mortar = hex_to_rgb(colors["mortar"])
    light = hex_to_rgb(colors["edge_light"])
    chip = hex_to_rgb(colors["chip"])
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    course_height = 8

    for y in range(SIZE):
        course = y // course_height
        offset = 0 if course % 2 == 0 else 8
        for x in range(SIZE):
            local_x = (x - offset) % 16
            local_y = y % course_height
            if local_y == 0 or local_x == 0:
                color = mortar
            elif local_y == 1 or local_x == 1:
                color = light
            else:
                color = brick[(x * 11 + y * 7 + rng.randrange(4)) % len(brick)]
                if (x * 5 + y * 13 + seed) % 47 == 0:
                    color = chip
            pixels[x, y] = color
    return image


def _wrapped_distance_sq(x: int, y: int, point: tuple[int, int]) -> int:
    dx = abs(x - point[0])
    dy = abs(y - point[1])
    dx = min(dx, SIZE - dx)
    dy = min(dy, SIZE - dy)
    # Weight vertical distance more strongly so regions spread sideways into
    # the chunky horizontal stones visible in the historical reference.
    return dx * dx + dy * dy * 2


def generate_cobblestone(colors: dict, seed: int = 8201) -> Image.Image:
    """Toroidal Voronoi stones create irregular but seamlessly wrapping cobbles."""
    rng = Random(seed)
    stone = [hex_to_rgb(color) for color in colors["stone"]]
    crevice = hex_to_rgb(colors["crevice"])
    light = hex_to_rgb(colors["edge_light"])
    pit = hex_to_rgb(colors["pit"])
    # Fewer regions yield the broad, connected stones of the requested
    # historical texture rather than many isolated pebble-like circles.
    points = [(rng.randrange(SIZE), rng.randrange(SIZE)) for _ in range(13)]
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()

    for y in range(SIZE):
        for x in range(SIZE):
            distances = sorted(
                (_wrapped_distance_sq(x, y, point), index)
                for index, point in enumerate(points)
            )
            nearest, region = distances[0]
            second = distances[1][0]
            edge_distance = second - nearest
            if edge_distance <= 3:
                color = crevice
            elif edge_distance <= 10:
                # Keep the stone boundary in middle gray. The old version's
                # bright continuous rim made every cobble read as line art.
                color = stone[(region + x + y) % 2]
            else:
                color = stone[(region + nearest // 7 + (x * 3 + y * 7) // 13) % len(stone)]
                if nearest < 9 and (x + y + region) % 3 == 0:
                    color = light
                if (x * 17 + y * 19 + region) % 61 == 0:
                    color = pit
            pixels[x, y] = color
    return image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        "bricks.png": generate_bricks(palette["bricks"]),
        "cobblestone.png": generate_cobblestone(palette["cobblestone"]),
    }
    for filename, image in outputs.items():
        path = out_dir / filename
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
