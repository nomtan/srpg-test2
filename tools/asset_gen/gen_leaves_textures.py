"""Generate seamless 32x32 RGBA leaf-block textures.

Usage:
    python tools/asset_gen/gen_leaves_textures.py
    python tools/asset_gen/gen_leaves_textures.py --out assets/texture/leaves
"""

import argparse
import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
DEFAULT_OUT_DIR = ROOT / "assets" / "texture" / "leaves"
SIZE = 32


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def lattice(seed: int, resolution: int) -> list[list[float]]:
    rng = Random(seed)
    return [[rng.random() for _ in range(resolution)] for _ in range(resolution)]


def smooth_sample(values: list[list[float]], resolution: int, x: int, y: int) -> float:
    fx = x * resolution / SIZE
    fy = y * resolution / SIZE
    x0, y0 = int(fx) % resolution, int(fy) % resolution
    x1, y1 = (x0 + 1) % resolution, (y0 + 1) % resolution
    tx, ty = fx - int(fx), fy - int(fy)
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    top = values[y0][x0] * (1.0 - tx) + values[y0][x1] * tx
    bottom = values[y1][x0] * (1.0 - tx) + values[y1][x1] * tx
    return top * (1.0 - ty) + bottom * ty


def generate_leaves(colors: dict, seed: int, hole_threshold: float) -> Image.Image:
    """Wrapped multi-scale noise produces organic clusters and seamless holes."""
    rng = Random(seed + 100)
    leaf = [hex_to_rgb(color) for color in colors["leaf"]]
    highlight = hex_to_rgb(colors["highlight"])
    coarse = lattice(seed, 4)
    medium = lattice(seed + 1, 8)
    fine = lattice(seed + 2, 16)
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()

    for y in range(SIZE):
        for x in range(SIZE):
            density = (
                smooth_sample(coarse, 4, x, y) * 0.45
                + smooth_sample(medium, 8, x, y) * 0.35
                + smooth_sample(fine, 16, x, y) * 0.20
            )
            density += ((x * 17 + y * 23 + seed) % 7 - 3) * 0.018
            if density < hole_threshold:
                continue
            value = min(max(density, 0.0), 0.999)
            color_index = min(int(value * len(leaf)), len(leaf) - 1)
            color = leaf[(color_index + rng.randrange(2)) % len(leaf)]
            if density > 0.74 and (x + y + seed) % 5 == 0:
                color = highlight
            pixels[x, y] = (*color, 255)
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
        "oak_leaves.png": generate_leaves(palette["oak_leaves"], 9101, 0.36),
        "acacia_leaves.png": generate_leaves(palette["acacia_leaves"], 9201, 0.48),
    }
    for filename, image in outputs.items():
        path = out_dir / filename
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
