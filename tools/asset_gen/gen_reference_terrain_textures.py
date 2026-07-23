"""Generate the brighter, broad-cluster terrain set used by flat_validation.

These remain 32x32 seamless textures, but deliberately use larger color
islands and sparse authored marks than the production terrain set. Colors
come from palette.json/reference_target so visual tuning stays centralized.
"""

import json
from pathlib import Path
from random import Random

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
OUT_DIR = ROOT / "assets" / "terrain" / "reference"
SIZE = 32


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def lattice(seed: int, resolution: int) -> list[list[float]]:
    rng = Random(seed)
    return [[rng.random() for _ in range(resolution)] for _ in range(resolution)]


def smooth_sample(values: list[list[float]], x: int, y: int) -> float:
    resolution = len(values)
    fx = x * resolution / SIZE
    fy = y * resolution / SIZE
    x0 = int(fx) % resolution
    y0 = int(fy) % resolution
    x1 = (x0 + 1) % resolution
    y1 = (y0 + 1) % resolution
    tx = fx - int(fx)
    ty = fy - int(fy)
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    top = values[y0][x0] * (1.0 - tx) + values[y0][x1] * tx
    bottom = values[y1][x0] * (1.0 - tx) + values[y1][x1] * tx
    return top * (1.0 - ty) + bottom * ty


def broad_texture(colors: list[str], seed: int) -> Image.Image:
    ordered = sorted(
        [rgb(color) for color in colors],
        key=lambda color: color[0] * 0.299 + color[1] * 0.587 + color[2] * 0.114,
    )
    coarse = lattice(seed, 4)
    medium = lattice(seed + 1, 8)
    values: list[list[float]] = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            row.append(smooth_sample(coarse, x, y) * 0.58 + smooth_sample(medium, x, y) * 0.42)
        values.append(row)
    minimum = min(min(row) for row in values)
    maximum = max(max(row) for row in values)
    span = maximum - minimum or 1.0
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            value = (values[y][x] - minimum) / span
            index = min(int(value * len(ordered)), len(ordered) - 1)
            pixels[x, y] = ordered[index]
    return image


def add_grass_marks(image: Image.Image, colors: list[str], seed: int) -> None:
    rng = Random(seed)
    pixels = image.load()
    mark_colors = [rgb(color) for color in colors]
    for _ in range(10):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        color = rng.choice(mark_colors)
        height = rng.choice([2, 3, 4])
        for step in range(height):
            pixels[(x + (step // 3)) % SIZE, (y - step) % SIZE] = color
        if rng.random() < 0.65:
            pixels[(x - 1) % SIZE, (y - 1) % SIZE] = color


def add_dirt_marks(image: Image.Image, colors: list[str], seed: int) -> None:
    rng = Random(seed)
    pixels = image.load()
    mark_colors = [rgb(color) for color in colors]
    for _ in range(12):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        color = rng.choice(mark_colors)
        pixels[x, y] = color
        if rng.random() < 0.45:
            pixels[(x + 1) % SIZE, y] = color


def cliff_texture(colors: list[str], seed: int) -> Image.Image:
    ordered = [rgb(color) for color in colors]
    rng = Random(seed)
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    band_values = [rng.random() for _ in range(6)]
    for y in range(SIZE):
        band = band_values[(y // 6) % len(band_values)]
        for x in range(SIZE):
            variation = ((x // 8) % 3) * 0.07 + rng.random() * 0.08
            value = min(0.999, max(0.0, band * 0.75 + variation))
            pixels[x, y] = ordered[min(int(value * len(ordered)), len(ordered) - 1)]
    return image


def cliff_with_grass_cap(cliff: Image.Image, grass: Image.Image, seed: int) -> Image.Image:
    image = cliff.copy()
    pixels = image.load()
    grass_pixels = grass.load()
    rng = Random(seed)
    raw_depths = [rng.randint(5, 9) for _ in range(SIZE)]
    for x in range(SIZE):
        depth = round((raw_depths[(x - 1) % SIZE] + raw_depths[x] + raw_depths[(x + 1) % SIZE]) / 3)
        for y in range(depth):
            pixels[x, y] = grass_pixels[x, y]
    return image


def main() -> None:
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))["reference_target"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    grass = broad_texture(palette["grass"], 7101)
    add_grass_marks(grass, palette["grass_blade"], 7111)
    dirt = broad_texture(palette["dirt"], 7201)
    add_dirt_marks(dirt, palette["dirt_detail"], 7211)
    stone = broad_texture(palette["stone"], 7301)
    cliff = cliff_texture(palette["cliff"], 7401)
    # The grass-capped side is a separate seamless texture so the top fringe
    # remains visible on the first exposed cliff block.
    cliff_top = cliff_with_grass_cap(cliff, grass, 7411)

    outputs = {
        "terrain_grass_top_ref.png": grass,
        "terrain_dirt_top_ref.png": dirt,
        "terrain_stone_top_ref.png": stone,
        "terrain_cliff_side_ref.png": cliff,
        "terrain_cliff_side_top_ref.png": cliff_top,
    }
    for name, image in outputs.items():
        path = OUT_DIR / name
        image.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
