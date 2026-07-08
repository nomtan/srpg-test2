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


def _hex_to_rgb(hex_color: str) -> tuple:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))


def _quantize(value: float, colors: list) -> tuple:
    index = min(int(value * len(colors)), len(colors) - 1)
    return _hex_to_rgb(colors[index])


def _base_image(colors: list, seed: int) -> Image.Image:
    """Blocky 2-octave quantized noise, tiling exactly since block sizes divide SIZE."""
    fine = _lattice(seed, LATTICE_FINE)
    coarse = _lattice(seed + 1, LATTICE_COARSE)
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            value = _sample(fine, LATTICE_FINE, x, y) * 0.6 + _sample(coarse, LATTICE_COARSE, x, y) * 0.4
            pixels[x, y] = _quantize(value, colors)
    return img


def _layered_image(colors: list, seed: int) -> Image.Image:
    """Horizontal strata bands (for cliff faces) with light per-pixel noise on top."""
    bands = _lattice_1d(seed, LATTICE_COARSE)
    fine = _lattice(seed + 1, LATTICE_FINE)
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            value = _sample_1d(bands, LATTICE_COARSE, y) * 0.7 + _sample(fine, LATTICE_FINE, x, y) * 0.3
            pixels[x, y] = _quantize(value, colors)
    return img


def _add_lava_cores(img: Image.Image, core_color: str, seed: int) -> None:
    rng = Random(seed + 2)
    pixels = img.load()
    core_rgb = _hex_to_rgb(core_color)
    resolution = LATTICE_COARSE
    block = SIZE // resolution
    for cy in range(resolution):
        for cx in range(resolution):
            if rng.random() < 0.18:
                for oy in range(block):
                    for ox in range(block):
                        pixels[cx * block + ox, cy * block + oy] = core_rgb


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
