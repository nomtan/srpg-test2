"""Procedurally generate 32x32 seamless terrain textures from palette.json.

Usage:
    python tools/asset_gen/gen_terrain_textures.py

Regenerates every texture consumed by build_terrain_glb.py into
assets/terrain/textures/. Colors come exclusively from palette.json
(docs/asset/map_texture_standard.md section 5) - no color codes are
hardcoded here.
"""

import json
from pathlib import Path
from random import Random

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
PALETTE_PATH = Path(__file__).resolve().parent / "palette.json"
OUT_DIR = ROOT / "assets" / "terrain" / "textures"

SIZE = 32
LATTICE_FINE = 8    # 32 / 8 = 4px blocks
LATTICE_COARSE = 4  # 32 / 4 = 8px blocks
CLIFF_TOP_BAND_ROWS = int(SIZE * 0.26)  # grass overhang band for cliff_side_top


def _lattice(seed: int, resolution: int) -> list:
    rng = Random(seed)
    return [[rng.random() for _ in range(resolution)] for _ in range(resolution)]


def _lattice_1d(seed: int, resolution: int) -> list:
    rng = Random(seed)
    return [rng.random() for _ in range(resolution)]


def _sample(lattice: list, resolution: int, x: int, y: int) -> float:
    block = SIZE // resolution
    return lattice[(y // block) % resolution][(x // block) % resolution]


def _sample_1d(lattice: list, resolution: int, y: int) -> float:
    block = SIZE // resolution
    return lattice[(y // block) % resolution]




def _smooth_sample(lattice: list, resolution: int, x: int, y: int) -> float:
    """Bilinear-interpolated, seamlessly wrapping value noise sample."""
    fx = x * resolution / SIZE
    fy = y * resolution / SIZE
    x0 = int(fx) % resolution
    y0 = int(fy) % resolution
    x1 = (x0 + 1) % resolution
    y1 = (y0 + 1) % resolution
    tx = fx - int(fx)
    ty = fy - int(fy)
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = lattice[y0][x0] * (1 - tx) + lattice[y0][x1] * tx
    b = lattice[y1][x0] * (1 - tx) + lattice[y1][x1] * tx
    return a * (1 - ty) + b * ty


def _sorted_by_luma(colors: list) -> list:
    """Order palette dark->light so quantized noise reads as gentle clumps,
    not a high-contrast mosaic."""
    def luma(c):
        r, g, b = _hex_to_rgb(c)
        return 0.299 * r + 0.587 * g + 0.114 * b
    return sorted(colors, key=luma)


def _hex_to_rgb(hex_color: str) -> tuple:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))


def _quantize(value: float, colors: list) -> tuple:
    index = min(int(value * len(colors)), len(colors) - 1)
    return _hex_to_rgb(colors[index])


def _base_image(colors: list, seed: int) -> Image.Image:
    """Per-pixel 3-octave smooth value noise, quantized to a luma-ordered
    palette. Tiles seamlessly because the lattices wrap."""
    l_coarse = _lattice(seed, 4)
    l_mid = _lattice(seed + 1, 8)
    l_fine = _lattice(seed + 2, 16)
    rng = Random(seed + 99)
    ordered = _sorted_by_luma(colors)
    values = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = (_smooth_sample(l_coarse, 4, x, y) * 0.5
                 + _smooth_sample(l_mid, 8, x, y) * 0.3
                 + _smooth_sample(l_fine, 16, x, y) * 0.2)
            row.append(v)
        values.append(row)
    v_min = min(min(r) for r in values)
    v_max = max(max(r) for r in values)
    span = (v_max - v_min) or 1.0
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = (values[y][x] - v_min) / span
            v = min(max(v + (rng.random() - 0.5) * 0.22, 0.0), 0.999)
            pixels[x, y] = _quantize(v, ordered)
    return img


def _layered_image(colors: list, seed: int) -> Image.Image:
    """Horizontal strata bands (cliff faces): band values vary smoothly down
    the face, with per-pixel jitter so bands read as sediment, not stripes."""
    bands = _lattice_1d(seed, LATTICE_COARSE)
    fine = _lattice(seed + 1, 16)
    rng = Random(seed + 7)
    ordered = _sorted_by_luma(colors)
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    res = LATTICE_COARSE
    for y in range(SIZE):
        fy = y * res / SIZE
        y0 = int(fy) % res
        y1 = (y0 + 1) % res
        t = fy - int(fy)
        t = t * t * (3 - 2 * t)
        band = bands[y0] * (1 - t) + bands[y1] * t
        for x in range(SIZE):
            v = band * 0.65 + _smooth_sample(fine, 16, x, y) * 0.35
            v = min(max(v + (rng.random() - 0.5) * 0.2, 0.0), 0.999)
            pixels[x, y] = _quantize(v, ordered)
    return img


def _add_lava_cores(img: Image.Image, core_color: str, seed: int) -> None:
    rng = Random(seed + 2)
    pixels = img.load()
    core_rgb = _hex_to_rgb(core_color)
    for _ in range(7):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        for _p in range(rng.randint(3, 6)):
            pixels[(cx + rng.randint(-1, 1)) % SIZE,
                   (cy + rng.randint(-1, 1)) % SIZE] = core_rgb


def _add_stone_cracks(img: Image.Image, crack_color: str, seed: int) -> None:
    rng = Random(seed + 3)
    pixels = img.load()
    crack_rgb = _hex_to_rgb(crack_color)
    for _ in range(2):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        length = rng.randint(10, 18)
        for _step in range(length):
            pixels[x % SIZE, y % SIZE] = crack_rgb
            direction = rng.choice([(1, 0), (0, 1), (1, 1), (-1, 1)])
            x += direction[0]
            y += direction[1]


def _generate_flat(palette: dict, name: str, seed: int) -> Image.Image:
    return _base_image(palette[name], seed)


def _generate_stone(palette: dict, seed: int) -> Image.Image:
    img = _base_image(palette["stone"], seed)
    _add_stone_cracks(img, palette["accent"]["stone_crack"], seed)
    return img


def _generate_lava(palette: dict, seed: int) -> Image.Image:
    img = _base_image(palette["lava"], seed)
    _add_lava_cores(img, palette["accent"]["lava_core"], seed)
    return img


def _generate_cliff_side(palette: dict, seed: int) -> Image.Image:
    return _layered_image(palette["dirt"], seed)


def _generate_cliff_side_top(palette: dict, seed: int) -> Image.Image:
    img = _layered_image(palette["dirt"], seed)
    grass_img = _base_image(palette["grass"], seed + 10)
    pixels = img.load()
    grass_pixels = grass_img.load()
    for y in range(CLIFF_TOP_BAND_ROWS):
        for x in range(SIZE):
            pixels[x, y] = grass_pixels[x, y]
    return img


def _generate_cliff_stone(palette: dict, seed: int) -> Image.Image:
    img = _base_image(palette["stone"], seed)
    _add_stone_cracks(img, palette["accent"]["stone_crack"], seed)
    return img


# (output stem, generator) - generator takes (palette, seed)
OUTPUTS = [
    ("terrain_grass_top_01", lambda p, s: _generate_flat(p, "grass", s)),
    ("terrain_dirt_top_01", lambda p, s: _generate_flat(p, "dirt", s)),
    ("terrain_stone_top_01", _generate_stone),
    ("terrain_water_top_01", lambda p, s: _generate_flat(p, "water", s)),
    ("terrain_lava_top_01", _generate_lava),
    ("terrain_cliff_side_01", _generate_cliff_side),
    ("terrain_cliff_side_top_01", _generate_cliff_side_top),
    ("terrain_cliff_stone_01", _generate_cliff_stone),
]


def main() -> None:
    palette = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for index, (stem, generator) in enumerate(OUTPUTS):
        img = generator(palette, 1000 + index)
        out_path = OUT_DIR / f"{stem}.png"
        img.save(out_path)
        print(f"wrote {out_path}")


if __name__ == "__main__":
    main()