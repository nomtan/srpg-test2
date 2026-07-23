"""Split the generated 4x2 reference prop atlas into Godot-ready sprites.

The source atlas is intentionally retained next to the outputs so the art can
be regenerated or replaced without guessing crop coordinates. Each cell is
trimmed from alpha, padded, reduced with nearest-neighbor sampling, and given
a hard alpha edge to preserve the pixel-art silhouette.
"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE = ROOT / "assets" / "props" / "generated" / "reference_prop_atlas_rgba.png"
OUT_DIR = SOURCE.parent

NAMES = [
    "prop_supply_crate",
    "prop_wood_barrel",
    "prop_rock_cluster",
    "prop_campfire",
    "prop_grass_short_painted",
    "prop_grass_tall_painted",
    "prop_fence_painted",
    "prop_supply_cart",
]

COLS = 4
ROWS = 2
MAX_DIMENSION = 160
PADDING = 6


def _hard_alpha(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            pixels[x, y] = (red, green, blue, 255 if alpha >= 128 else 0)
    return rgba


def main() -> None:
    atlas = Image.open(SOURCE).convert("RGBA")
    cell_width = atlas.width // COLS
    cell_height = atlas.height // ROWS

    for index, name in enumerate(NAMES):
        column = index % COLS
        row = index // COLS
        cell = atlas.crop((
            column * cell_width,
            row * cell_height,
            (column + 1) * cell_width,
            (row + 1) * cell_height,
        ))
        alpha_bounds = cell.getchannel("A").getbbox()
        if not alpha_bounds:
            raise RuntimeError(f"No opaque pixels found in atlas cell {index}: {name}")
        sprite = cell.crop(alpha_bounds)
        scale = min(MAX_DIMENSION / sprite.width, MAX_DIMENSION / sprite.height, 1.0)
        target_size = (
            max(1, round(sprite.width * scale)),
            max(1, round(sprite.height * scale)),
        )
        sprite = sprite.resize(target_size, Image.Resampling.NEAREST)
        sprite = _hard_alpha(sprite)
        padded = Image.new("RGBA", (sprite.width + PADDING * 2, sprite.height + PADDING * 2))
        padded.alpha_composite(sprite, (PADDING, PADDING))
        output = OUT_DIR / f"{name}.png"
        padded.save(output)
        print(f"wrote {output} ({padded.width}x{padded.height})")


if __name__ == "__main__":
    main()
